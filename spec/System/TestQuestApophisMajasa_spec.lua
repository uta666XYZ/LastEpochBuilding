-- @leb-regression-guard:quest-apophis-majasa-plus-one
-- LE in-game Completed Quests panel shows "Attribute Points: 1" for the Apophis
-- and Majasa quest, granted as +1 to each of Str/Dex/Int/Att/Vit. The Temple of
-- Eterra quest also grants +1 to all (Total 2/2 when both are completed).
-- Verified via in-game screenshot 2026-05-08.

describe("QuestApophisMajasa", function()
    it("applies +1 BASE to all five attributes", function()
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
            assert.are.equals(1, m.value, "Apophis quest reward must be +1 to all attributes")
            assert.are.equals("Quest", m.source)
            seen[m.name] = true
        end
        for _, stat in ipairs({"Str","Dex","Int","Att","Vit"}) do
            assert.is_true(seen[stat], "missing +1 mod for " .. stat)
        end
    end)
end)

describe("QuestTempleOfEterra", function()
    it("applies +1 BASE to all five attributes", function()
        newBuild()
        local ConfigOptions = require("Modules/ConfigOptions")
        local entry
        for _, opt in ipairs(ConfigOptions) do
            if opt.var == "questTempleOfEterra" then entry = opt; break end
        end
        assert.is_not_nil(entry, "questTempleOfEterra option must exist")

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
            assert.are.equals(1, m.value, "Temple of Eterra quest reward must be +1 to all attributes")
            assert.are.equals("Quest", m.source)
            seen[m.name] = true
        end
        for _, stat in ipairs({"Str","Dex","Int","Att","Vit"}) do
            assert.is_true(seen[stat], "missing +1 mod for " .. stat)
        end
    end)
end)
