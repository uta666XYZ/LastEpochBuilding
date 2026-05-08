-- @leb-regression-guard:quest-apophis-majasa-plus-two
-- LE in-game tooltip on the Vitality breakdown shows "Quest Reward: +2 Vitality"
-- (and equivalently +2 Str/Dex/Int/Att). See REGRESSION_GUARDS.md for the
-- ATTR_UNIFORM_OTHER Δ=-2 symptom this guard prevents from regressing.

describe("QuestApophisMajasa", function()
    it("applies +2 BASE to all five attributes", function()
        newBuild()
        -- Locate the option entry by its var name and run its apply().
        local ConfigOptions = require("Modules/ConfigOptions")
        local entry
        for _, opt in ipairs(ConfigOptions) do
            if opt.var == "questApophisMajasa" then entry = opt; break end
        end
        assert.is_not_nil(entry, "questApophisMajasa option must exist")

        local fakeMods = {}
        local fakeModList = {
            NewMod = function(_, name, modType, value, source)
                table.insert(fakeMods, { name = name, type = modType, value = value, source = source })
            end,
        }
        entry.apply(true, fakeModList, fakeModList)

        local seen = {}
        for _, m in ipairs(fakeMods) do
            assert.are.equals("BASE", m.type)
            assert.are.equals(2, m.value, "Apophis quest reward must be +2 (was +1 before fix)")
            assert.are.equals("Quest", m.source)
            seen[m.name] = true
        end
        for _, stat in ipairs({"Str","Dex","Int","Att","Vit"}) do
            assert.is_true(seen[stat], "missing +2 mod for " .. stat)
        end
    end)
end)
