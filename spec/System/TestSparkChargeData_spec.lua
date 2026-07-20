-- @leb-regression-guard:spark-charge-detonation
-- See REGRESSION_GUARDS.md "spark-charge-detonation".
-- Validation provenance is retained in maintainer notes.

describe("SparkChargeExplosion base data (no fabrication)", function()
    it("carries the datamined Lightning Spell hit base", function()
        local d = data.skills.SparkChargeExplosion
        assert.is_table(d, "SparkChargeExplosion must exist in data.skills")
        assert.are.equals("Spark Charge", d.name)
        assert.are.equals(258, d.skillTypeTags, "tagsBitmap 258 = Lightning + Spell")
        assert.are.equals(20, d.stats.spell_base_lightning_damage, "datamined base 20 Lightning")
        assert.are.equals(1, d.stats.damageEffectiveness, "addedDamageScaling 1.0")
        assert.are.equals(5, d.stats.critChance, "critChance 0.05")
        assert.are.equals(100, d.stats["base_critical_strike_multiplier_+"],
            "datamine critMultiplier 2.0 (base 100% + 100 = 200% = x2.0)")
        -- instant detonation hit: spell + hit, NOT a dot/ailment/duration.
        assert.is_true(d.baseFlags.spell)
        assert.is_true(d.baseFlags.hit)
        assert.is_nil(d.baseFlags.dot)
        assert.is_nil(d.baseFlags.ailment)
        assert.is_nil(d.baseFlags.duration)
        -- Mage/Runemaster Intelligence scaling (matches Mana Arc / Runebolt).
        local hasInt = false
        for _, s in ipairs(d.attributeScalings or {}) do if s == "Intelligence" then hasInt = true end end
        assert.is_true(hasInt, "attributeScalings must include Intelligence")
    end)

    it("is granted via the CalcSetup timer path, NOT data.subSkillGrants", function()
        -- The detonation rate is cross-skill (LB+Nova hit rate x SC chance), which the
        -- data.subSkillGrants registry (self-cast-rate sub-skills) cannot express. So
        -- SparkChargeExplosion must NOT appear in data.subSkillGrants; it is granted by
        -- the dedicated CalcSetup block instead. SmallLightningNova / LightningExplosion
        -- stay ungranted (data-only) entirely.
        for parentId, grants in pairs(data.subSkillGrants or {}) do
            for _, grant in ipairs(grants) do
                assert.is_not.equal("SparkChargeExplosion", grant.skillId,
                    "the detonation is granted via the CalcSetup timer path, not subSkillGrants (under " .. tostring(parentId) .. ")")
                assert.is_not.equal("SmallLightningNova", grant.skillId, "Spark Nova stays ungranted (data-only)")
                assert.is_not.equal("LightningExplosion", grant.skillId, "Lightning Explosion stays ungranted (data-only)")
            end
        end
        -- and the CalcSetup grant block must exist (locks the landed behavior so this
        -- spec is a real guard, not a vacuous scan of an unused registry).
        local f = io.open("Modules/CalcSetup.lua", "r") or io.open("src/Modules/CalcSetup.lua", "r")
        local text = assert(f and f:read("*a")); if f then f:close() end
        assert.is_truthy(text:find("@leb-regression-guard:spark-charge-detonation-grant", 1, true),
            "the detonation grant block must be present in CalcSetup")
        assert.is_truthy(text:find('source = "Timer:SparkChargeExplosion"', 1, true))
    end)
end)

describe("Spark Charge name-collision: the stack trigger must not become the hit", function()
    -- SparkChargeExplosion shares its display name "Spark Charge" with the
    -- Ailment_SparkCharge stack so it would receive Spark-Charge-scoped DAMAGE
    -- mods, but it MUST be excluded from the greedy "<name> chance" trigger rule,
    -- or "X% Spark Charge Chance On Hit" (which applies a STACK = 0 damage, e.g.
    -- tree node lb23il-25 "Cloud Answer") would mis-resolve to the explosion HIT
    -- (20 Lightning) and fabricate damage. This is what keeps the data-only entry
    -- inert: with the flag, builds resolve identically to before the entry existed.
    it("SparkChargeExplosion is flagged excludeFromTriggerNameList", function()
        assert.is_true(data.skills.SparkChargeExplosion.excludeFromTriggerNameList)
    end)

    it("'Spark Charge Chance On Hit' triggers the AILMENT, not the explosion", function()
        local mods = modLib.parseMod("10% Spark Charge Chance On Hit")
        assert.is_table(mods)
        assert.are.equals("ChanceToTriggerOnHit_Ailment_SparkCharge", mods[1].name)
        assert.are_not.equals("ChanceToTriggerOnHit_SparkChargeExplosion", mods[1].name)
    end)
end)

describe("Spark Charge engine wiring (guard marker)", function()
    it("ModParser honours excludeFromTriggerNameList", function()
        local f = io.open("Modules/ModParser.lua", "r") or io.open("src/Modules/ModParser.lua", "r")
        local text = assert(f and f:read("*a")); if f then f:close() end
        assert.is_truthy(text:find("not skill%.excludeFromTriggerNameList"),
            "the <name>-chance trigger rule must skip excludeFromTriggerNameList skills")
    end)
end)
