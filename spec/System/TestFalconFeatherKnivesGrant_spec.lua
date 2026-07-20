-- @leb-regression-guard:falcon-feather-knives-grant
-- the datamined base. See REGRESSION_GUARDS.md "falcon-feather-knives-grant".
-- Validation provenance is retained in maintainer notes.

describe("FalconFeatherKnivesGrant #falcon parser contract", function()

    it("falc0-15 stat '10 Feather Knives Cooldown (seconds)' emits the RogueFalcon ExtraMinionSkill grant", function()
        local fk = modLib.parseMod("10 Feather Knives Cooldown (seconds)")
        assert.is_table(fk, "the node stat must parse to a mod list")
        assert.are.equals("ExtraMinionSkill", fk[1].name)
        assert.are.equals("LIST", fk[1].type)
        assert.are.equals("FeatherKnives", fk[1].value.skillId)
        assert.are.equals("RogueFalcon", fk[1].value.minionList[1])
    end)

    it("the whole line is consumed (no non-empty extra so PassiveTree keeps the mod)", function()
        local fk, extra = modLib.parseMod("10 Feather Knives Cooldown (seconds)")
        assert.is_table(fk)
        assert.is_nil(extra, "extra must be nil -- a non-empty residue is dropped at the tree gate")
    end)
end)

describe("FalconFeatherKnivesGrant #falcon data contract", function()

    it("FeatherKnives carries the datamined Physical 50 / eff 2.5 throwing base", function()
        local s = data.skills.FeatherKnives
        assert.is_table(s, "FeatherKnives must exist in data.skills")
        assert.are.equal(50, s.stats.throwing_base_physical_damage)
        assert.are.equal(2.5, s.stats.damageEffectiveness)
        assert.are.equal(100, s.stats["base_critical_strike_multiplier_+"])
        assert.is_true(s.baseFlags.attack)
        assert.is_true(s.baseFlags.hit)
    end)

    it("FeatherKnives is tagged THROWING (skillTypeTags 1025 = throwing 1024 + physical 1)", function()
        local s = data.skills.FeatherKnives
        assert.are.equal(1025, s.skillTypeTags)
    end)
end)
