-- @leb-regression-guard:glacier-three-explosion-base
-- See REGRESSION_GUARDS.md "glacier-three-explosion-base".
-- Validation provenance is retained in maintainer notes.

describe("GlacierThreeExplosionBase #glacier", function()

    it("data.skills.Glacier carries the combined 3-explosion base/effectiveness", function()
        assert.is_table(data.skills.Glacier, "Glacier must exist in data.skills")
        local s = data.skills.Glacier.stats
        assert.is_table(s, "Glacier.stats must be a table")
        assert.are.equal(125, s.spell_base_cold_damage,
            "Glacier base cold must be 125 (= 20+35+70, the sum of the 3 explosions), not the single small explosion's 20")
        assert.are.equal(6.25, s.damageEffectiveness,
            "Glacier damageEffectiveness must be 6.25 (= 1+1.75+3.5), not the single small explosion's 1")
    end)

    it("base and effectiveness share the per-explosion ratio (combined hit == sum of explosions)", function()
        local s = data.skills.Glacier.stats
        -- small-explosion base 20 @ eff 1; the combined values must preserve base/eff = 20
        assert.are.equal(20, s.spell_base_cold_damage / s.damageEffectiveness,
            "spell_base_cold_damage / damageEffectiveness must equal the small explosion's 20:1 ratio")
    end)

    it("Glacier remains a cold spell hit (flags unchanged by the base fix)", function()
        local f = data.skills.Glacier.baseFlags
        assert.is_table(f)
        assert.is_true(f.spell, "Glacier must stay a spell")
        assert.is_true(f.hit, "Glacier must stay a hit")
    end)
end)
