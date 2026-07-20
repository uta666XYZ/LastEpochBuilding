-- @leb-regression-guard:bladestorm-storm-tick-base
-- See REGRESSION_GUARDS.md "bladestorm-storm-tick-base".
-- Validation provenance is retained in maintainer notes.

describe("BladestormStormTickBase #bladestorm", function()

    for _, name in ipairs({ "Bladestorm", "Bladestorm Throw" }) do
        it(name .. " carries the datamined storm-tick base/effectiveness", function()
            assert.is_table(data.skills[name], name .. " must exist in data.skills")
            local s = data.skills[name].stats
            assert.is_table(s, name .. ".stats must be a table")
            assert.are.equal(30, s.throwing_base_physical_damage,
                name .. " base physical must be 30 (datamined storm-tick 'Bladestorm Damage' bs6d9), not 0")
            assert.are.equal(1.5, s.damageEffectiveness,
                name .. " damageEffectiveness must be 1.5 (datamined addedDamageScaling), not 1.0")
        end)

        it(name .. " remains a physical attack hit (flags unchanged by the base fix)", function()
            local f = data.skills[name].baseFlags
            assert.is_table(f)
            assert.is_true(f.attack, name .. " must stay an attack")
            assert.is_true(f.hit, name .. " must stay a hit")
        end)
    end
end)
