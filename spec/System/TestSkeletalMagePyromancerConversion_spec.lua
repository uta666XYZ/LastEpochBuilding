-- @leb-regression-guard:skeletal-mage-pyromancer-conversion
-- See REGRESSION_GUARDS.md "skeletal-mage-pyromancer-conversion".
-- Validation provenance is retained in maintainer notes.

describe("SkeletalMagePyromancerConversion #pyromancer parser contract", function()

    it("' Adds Pyromancers' emits a SummonedSkeletonMage ExtraMinionSkill grant that REPLACES Dread Bolt with Fireball", function()
        local m = modLib.parseMod(" Adds Pyromancers")
        assert.is_table(m, "' Adds Pyromancers' must parse to a mod list")
        assert.are.equals("ExtraMinionSkill", m[1].name)
        assert.are.equals("LIST", m[1].type)
        assert.are.equals("Skeletal Mages Fire Projectile", m[1].value.skillId)
        assert.are.equals("Skeletal Mages Necrotic Projectile", m[1].value.replaces)
        assert.are.equals("SummonedSkeletonMage", m[1].value.minionList[1])
    end)
end)

describe("SkeletalMagePyromancerConversion #pyromancer data contract", function()

    it("'Skeletal Mages Fire Projectile' (Fireball) carries the datamined Fire 34 / eff 1.75 spell base", function()
        local s = data.skills["Skeletal Mages Fire Projectile"]
        assert.is_table(s, "'Skeletal Mages Fire Projectile' must exist in data.skills")
        assert.are.equal("Fireball", s.name)
        assert.are.equal(34, s.stats.spell_base_fire_damage)
        assert.are.equal(1.75, s.stats.damageEffectiveness)
        assert.are.equal(100, s.stats["base_critical_strike_multiplier_+"])
        assert.is_true(s.baseFlags.spell)
        assert.is_true(s.baseFlags.hit)
        assert.is_true(s.fromMinion)
    end)

    it("the necrotic sibling (Dread Bolt) it replaces is unchanged (Necrotic 30 / eff 1.5)", function()
        local s = data.skills["Skeletal Mages Necrotic Projectile"]
        assert.is_table(s)
        assert.are.equal("Dread Bolt", s.name)
        assert.are.equal(30, s.stats.spell_base_necrotic_damage)
        assert.are.equal(1.5, s.stats.damageEffectiveness)
    end)

    it("Fireball is whitelisted against the per-Int double-count (SummonMage already scales per Int)", function()
        assert.is_table(LE_MINION_SKILL_REDUNDANT_ATTR_SCALING["Skeletal Mages Fire Projectile"])
        assert.is_true(LE_MINION_SKILL_REDUNDANT_ATTR_SCALING["Skeletal Mages Fire Projectile"].Int)
    end)
end)
