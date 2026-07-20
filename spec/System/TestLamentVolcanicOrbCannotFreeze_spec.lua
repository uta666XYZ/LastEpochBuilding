-- @leb-regression-guard: lament-volcanic-orb-cannot-freeze
-- Locks the contract that Lament of the Lost Refuge's altText clause
--   "It cannot freeze even if previously converted to cold."
-- is enforced by zeroing FreezeRate / FreezeChance on Volcanic Orb when
-- the equipped Lament drives a 100% base-damage conversion to a non-cold
-- destination. The clause is implicit in altText only; the explicit
-- mods[] entries in uniques*.json carry only the conversion line.
--
-- Two failure modes to defend:
--   (1) Volcanic Orb tree carries Fire->Cold conversion nodes (Frigid Wake);
--       the freeze gate must hold even if a future refactor of conversion
--       order leaves a residual Cold path through the tree.
--   (2) FreezeRate is a modDB:Sum aggregate, independent of damage type
--       actually dealt — gear/passives that grant FreezeRate would still
--       freeze without the explicit gate.
--
-- See REGRESSION_GUARDS.md "lament-volcanic-orb-cannot-freeze".

describe("LamentVolcanicOrbCannotFreeze", function()

    describe("CalcOffence freeze section is gated", function()
        local source
        setup(function()
            local f = io.open("Modules/CalcOffence.lua", "r")
            assert.is_not_nil(f, "must be able to open Modules/CalcOffence.lua")
            source = f:read("*a")
            f:close()
        end)

        it("regression-guard comment block is present", function()
            assert.is_truthy(string.find(source, "lament%-volcanic%-orb%-cannot%-freeze"),
                "CalcOffence.lua must keep the @leb-regression-guard comment so future edits trip review")
        end)

        it("FreezeRate assignment routes through the cannotFreeze gate", function()
            -- Lock the structural shape: FreezeRate = cannotFreeze and 0 or (...)
            local pat = "output%.FreezeRate%s*=%s*cannotFreeze%s+and%s+0%s+or"
            assert.is_truthy(string.find(source, pat),
                "CalcOffence.lua FreezeRate must be gated by the cannotFreeze ternary")
        end)

        it("FreezeChance assignment routes through the cannotFreeze gate", function()
            local pat = "output%.FreezeChance%s*=%s*cannotFreeze%s+and%s+0%s+or"
            assert.is_truthy(string.find(source, pat),
                "CalcOffence.lua FreezeChance must be gated by the cannotFreeze ternary")
        end)

        it("cannotFreeze trigger uses the base-damage-conversion helper", function()
            -- The gate predicate must call calcs.getItemSkillBaseDamageConversion
            -- so it shares the trigger with the lament-base-damage-conversion guard.
            local pat = "calcs%.getItemSkillBaseDamageConversion%s*%(%s*env%s*,"
            assert.is_truthy(string.find(source, pat),
                "CalcOffence.lua freeze gate must trigger on getItemSkillBaseDamageConversion")
        end)

        it("cannotFreeze does NOT inspect destination type", function()
            -- altText: "It cannot freeze even if previously converted to cold."
            -- The clause is unconditional — every documented conversion
            -- (currently only Lament -> Void) triggers suppression. A
            -- destination filter (e.g. dst ~= "cold") would be speculation
            -- about hypothetical conversions not present in game data.
            assert.is_nil(string.find(source, 'dst%s*~=%s*"cold"'),
                "CalcOffence.lua freeze gate must NOT filter on destination — see altText clause-mapping comment")
            assert.is_nil(string.find(source, 'dst%s*==%s*"void"'),
                "CalcOffence.lua freeze gate must NOT filter on destination — see altText clause-mapping comment")
        end)

        it("cannotFreeze gates on Volcanic Orb name", function()
            -- altText is the only authority for "cannot freeze" and only Lament
            -- + Volcanic Orb has it. Guard the explicit name match so that a
            -- future skill+item with parallel altText is added knowingly.
            local pat = '"Volcanic Orb"'
            assert.is_truthy(string.find(source, pat, 1, true),
                "CalcOffence.lua freeze gate must explicitly match Volcanic Orb")
        end)
    end)

    describe("CalcActiveSkill paired helper still exists", function()
        local source
        setup(function()
            local f = io.open("Modules/CalcActiveSkill.lua", "r")
            assert.is_not_nil(f, "must be able to open Modules/CalcActiveSkill.lua")
            source = f:read("*a")
            f:close()
        end)

        it("getItemSkillBaseDamageConversion is defined on calcs", function()
            assert.is_truthy(string.find(source,
                "function%s+calcs%.getItemSkillBaseDamageConversion%s*%("),
                "calcs.getItemSkillBaseDamageConversion (paired guard) must remain defined")
        end)

        it("paired regression-guard comment is present", function()
            assert.is_truthy(string.find(source, "lament%-base%-damage%-conversion"),
                "CalcActiveSkill.lua must keep its lament-base-damage-conversion guard")
        end)
    end)

    describe("uniques*.json carry the conversion line that triggers the gate", function()
        local paths = {
            "Data/Uniques/uniques.json",
            "Data/Uniques/uniques_1_2.json",
            "Data/Uniques/uniques_1_3.json",
            "Data/Uniques/uniques_1_4.json",
            "src/Data/Uniques/uniques.json",
            "src/Data/Uniques/uniques_1_2.json",
            "src/Data/Uniques/uniques_1_3.json",
            "src/Data/Uniques/uniques_1_4.json",
        }

        it("Lament of the Lost Refuge retains the 100% Volcanic Orb -> Void conversion line", function()
            local checked = 0
            for _, p in ipairs(paths) do
                local f = io.open(p, "r")
                if f then
                    local raw = f:read("*a")
                    f:close()
                    local nameIdx = raw:find('"Lament of the Lost Refuge"', 1, true)
                    if nameIdx then
                        local block = raw:sub(nameIdx, nameIdx + 2000)
                        assert.is_truthy(
                            block:find("100%% of Volcanic Orb Base Damage Converted to Void", 1, false),
                            p .. " missing Lament's 100% Volcanic Orb -> Void conversion line")
                        checked = checked + 1
                    end
                end
            end
            assert.is_true(checked > 0, "no uniques*.json file was readable for verification")
        end)
    end)
end)
