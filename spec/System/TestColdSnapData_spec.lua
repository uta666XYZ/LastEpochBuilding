-- @leb-regression-guard:runemaster-cold-snap-data
-- @leb-regression-guard:modnamelist-deterministic-trigger-resolution
-- Validation provenance is retained in maintainer notes.

describe("Cold Snap base data (no fabrication)", function()
    it("ColdSnapExplosion carries the datamined Cold Spell hit base WITHOUT Int scaling", function()
        local d = data.skills.ColdSnapExplosion
        assert.is_table(d, "ColdSnapExplosion must exist in data.skills")
        assert.are.equals("Cold Snap", d.name)
        assert.are.equals(260, d.skillTypeTags, "Ability tags 260 = Spell(256)+Cold(4)")
        assert.are.equals(50, d.stats.spell_base_cold_damage)
        assert.are.equals(2.5, d.stats.damageEffectiveness, "addedDamageScaling 2.5")
        assert.are.equals(5, d.stats.critChance)
        assert.are.equals(100, d.stats["base_critical_strike_multiplier_+"], "datamine crit x2.0")
        assert.is_true(d.baseFlags.spell)
        assert.is_true(d.baseFlags.hit)
        -- DECISIVE: the "Cold Snap" damage children have attributeScaling [] -> no
        -- Int. The parent "Wave of Frost" has Int, but that is a different ability.
        local hasInt = false
        for _, s in ipairs(d.attributeScalings or {}) do if s == "Intelligence" then hasInt = true end end
        assert.is_false(hasInt, "Cold Snap must NOT have Intelligence scaling")
        for _, m in ipairs(d.baseMods or {}) do
            assert.is_nil(m:find("per player Intelligence"),
                "Cold Snap must not carry an Int baseMod")
        end
    end)

    it("Cold Snap is NOT a Lightning skill (no lightning base leaked from the siblings)", function()
        local d = data.skills.ColdSnapExplosion
        assert.is_nil(d.stats.spell_base_lightning_damage,
            "Cold Snap deals Cold, not Lightning")
        local tags = d.skillTypeTags
        assert.are.equals(1, math.floor(tags / 4) % 2, "Cold bit (4) set in 260")
        assert.are.equals(0, math.floor(tags / 2) % 2, "Lightning bit (2) clear in 260")
        assert.are.equals(1, math.floor(tags / 256) % 2, "Spell bit (256) set in 260")
    end)
end)

describe("Cold Snap trigger-name resolution (deterministic, no collision)", function()
    -- "Cold Snap" introduces a NEW modNameList key with no pre-existing data.skills
    -- collision (the only other "Cold Snap" in the repo is the Glacier tree node
    -- gl14-15, which is a passive node and never enters data.skills). Because the
    -- trigger loop iterates pairsSortByKey, adding ColdSnapExplosion cannot perturb
    -- any unrelated collision group -- it only claims its own "cold snap chance".
    it("'Cold Snap Chance' resolves to ChanceToTriggerOnHit_ColdSnapExplosion", function()
        local mods = modLib.parseMod("10% Cold Snap Chance")
        assert.is_table(mods)
        assert.are.equals("ChanceToTriggerOnHit_ColdSnapExplosion", mods[1].name)
    end)

    -- The previously-locked collisions stay put (adding a Cold key does not flip the
    -- lightning/ailment winners) -- spot-check the two most fragile.
    it("adding Cold Snap leaves Spark Charge resolving to its Ailment", function()
        local mods = modLib.parseMod("10% Spark Charge Chance")
        assert.are.equals("ChanceToTriggerOnHit_Ailment_SparkCharge", mods[1].name)
    end)
    it("adding Cold Snap leaves Lightning Explosion resolving to itself", function()
        local mods = modLib.parseMod("10% Lightning Explosion Chance")
        assert.are.equals("ChanceToTriggerOnHit_LightningExplosion", mods[1].name)
    end)
end)
