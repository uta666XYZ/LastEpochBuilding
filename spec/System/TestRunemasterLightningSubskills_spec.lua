-- @leb-regression-guard:runemaster-lightning-subskills
-- @leb-regression-guard:modnamelist-deterministic-trigger-resolution
-- Validation provenance is retained in maintainer notes.

describe("Spark Nova base data (no fabrication)", function()
    it("SmallLightningNova carries the datamined Lightning Spell hit base + Int scaling", function()
        local d = data.skills.SmallLightningNova
        assert.is_table(d, "SmallLightningNova must exist in data.skills")
        assert.are.equals("Spark Nova", d.name)
        assert.are.equals(258, d.skillTypeTags)
        assert.are.equals(11, d.stats.spell_base_lightning_damage)
        assert.are.equals(1, d.stats.damageEffectiveness)
        assert.are.equals(5, d.stats.critChance)
        assert.are.equals(100, d.stats["base_critical_strike_multiplier_+"], "datamine crit x2.0")
        assert.is_true(d.baseFlags.spell)
        assert.is_true(d.baseFlags.hit)
        local hasInt = false
        for _, s in ipairs(d.attributeScalings or {}) do if s == "Intelligence" then hasInt = true end end
        assert.is_true(hasInt, "Spark Nova has Intelligence scaling (datamine)")
    end)
end)

describe("Lightning Explosion base data (no fabrication)", function()
    it("LightningExplosion carries Lightning 18 hit base WITHOUT Int scaling", function()
        local d = data.skills.LightningExplosion
        assert.is_table(d, "LightningExplosion must exist in data.skills")
        assert.are.equals("Lightning Explosion", d.name)
        assert.are.equals(258, d.skillTypeTags)
        assert.are.equals(18, d.stats.spell_base_lightning_damage)
        assert.are.equals(1, d.stats.damageEffectiveness)
        assert.are.equals(5, d.stats.critChance)
        assert.are.equals(100, d.stats["base_critical_strike_multiplier_+"], "datamine crit x2.0")
        assert.is_true(d.baseFlags.spell)
        assert.is_true(d.baseFlags.hit)
        -- DECISIVE: datamine attributeScalings == [] -> no Int scaling. Adding it
        -- would over-compute the per-hit ~10x (in-game corroborates: ~1,359 not ~14k).
        local hasInt = false
        for _, s in ipairs(d.attributeScalings or {}) do if s == "Intelligence" then hasInt = true end end
        assert.is_false(hasInt, "Lightning Explosion must NOT have Intelligence scaling")
        for _, m in ipairs(d.baseMods or {}) do
            assert.is_nil(m:find("per player Intelligence"),
                "Lightning Explosion must not carry an Int baseMod")
        end
    end)
end)

describe("deterministic trigger-name collision resolution", function()
    -- ModParser maps "<skill name> chance" -> ChanceToTriggerOnHit_<skillId>. When
    -- names collide, the LAST write wins; iterating data.skills with pairsSortByKey
    -- (not pairs) makes the winner the alphabetically-greatest skillId -- STABLE
    -- against any future skill addition (adding SparkChargeExplosion previously
    -- flipped Bone Curse + Arcane Ascendance to their Ailment_ variants via the
    -- pairs hash order). For every collision the base skill is the greatest key.
    it("ModParser iterates the trigger-name loop deterministically", function()
        local f = io.open("Modules/ModParser.lua", "r") or io.open("src/Modules/ModParser.lua", "r")
        local text = assert(f and f:read("*a")); if f then f:close() end
        assert.is_truthy(text:find("for skillId, skill in pairsSortByKey%(data%.skills%) do"),
            "the trigger-name loop must use pairsSortByKey for stable collision resolution")
    end)

    local cases = {
        { "Bone Curse",        "ChanceToTriggerOnHit_BoneCurse" },
        { "Arcane Ascendance", "ChanceToTriggerOnHit_ArcaneAscendance" },
        { "Spirit Plague",     "ChanceToTriggerOnHit_SpiritPlague" },
        { "Spark Nova",        "ChanceToTriggerOnHit_SmallLightningNova" },
        { "Lightning Explosion", "ChanceToTriggerOnHit_LightningExplosion" },
        -- Spark Charge stays the ailment (explosion excluded via excludeFromTriggerNameList)
        { "Spark Charge",      "ChanceToTriggerOnHit_Ailment_SparkCharge" },
        -- 5th collision: "Mark For Death" (MarkForDeath name vs Ailment_MarkedForDeath
        -- altName) -> the greatest key MarkForDeath wins deterministically. This is
        -- the no-corpus-user form whose winner the sort flipped (was Ailment_ under
        -- pairs); locking it documents the flip is intentional + stable.
        { "Mark For Death",    "ChanceToTriggerOnHit_MarkForDeath" },
        -- The actually-USED form "Marked For Death" (with -ed) has NO collision
        -- (only Ailment_MarkedForDeath carries that exact name) -> unaffected by the
        -- iteration change; the 13 corpus builds that use it stay byte-identical.
        { "Marked For Death",  "ChanceToTriggerOnHit_Ailment_MarkedForDeath" },
    }
    for _, c in ipairs(cases) do
        it("'" .. c[1] .. " Chance' resolves to " .. c[2], function()
            local mods = modLib.parseMod("10% " .. c[1] .. " Chance")
            assert.is_table(mods)
            assert.are.equals(c[2], mods[1].name)
        end)
    end
end)
