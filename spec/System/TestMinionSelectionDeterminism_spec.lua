-- @leb-regression-guard:minion-selection-determinism
-- Locks the deterministic resolution of LETools-planner item imports in
-- buildMode:ReadLeToolsSave / processItemData (src/Modules/Build.lua).
--
-- Bug (found chasing a "minion skill selection" flap, hence the guard name):
-- the corpus flappers 1.2/minions.json (6 distinct output hashes / 8 fresh
-- processes), 1.3/throwing.json (3) and 1.2/warpath_channel.json (2) were NOT
-- flapping in the minion calc path at all -- the minion, its kit, and its
-- mainSkill were identical every run. What flapped was the EQUIPPED GEAR:
-- a legendary (unique + sealed affix) planner item carries an encoded id that
-- maps to a bases.json entry WITHOUT a uniqueId, and the recovery loop scanned
-- `pairs(data.LETools_itemBases)` (string-keyed) taking the FIRST entry with a
-- matching baseTypeId+subTypeId that has a uniqueId. Several uniques share one
-- base pair (six glove uniques on 4/5), and LuaJIT seeds string hashing
-- per-process, so pairs() order -- and therefore the equipped unique -- changed
-- run-to-run (minions.json hands: Li'raka's Claws / Falcon Fists / Maehlin's
-- Hubris; player Armour 423/473/567/634, Att 0<->3).
--
-- Fix: track the MINIMUM uniqueId across all matches (order-independent, and
-- stable across bases.json regenerations), plus the same min-tracking for the
-- latestBases base-name scan (lexically-smallest name wins; that table has no
-- duplicate baseTypeID+subTypeID pairs today, so this leg is inert but locked).

local function minimalSave(equipment)
    -- smallest saveContent ReadLeToolsSave accepts
    local classId
    for id, class in pairs(build.latestTree.classes) do
        if type(id) == "number" and class.name then
            if not classId or id < classId then classId = id end
        end
    end
    return {
        bio = { characterClass = classId, level = 100, chosenMastery = 1 },
        charTree = { selected = { } },
        skillTrees = { },
        equipment = equipment,
        idols = { },
    }
end

describe("MinionSelectionDeterminism (LETools import item resolution)", function()
    setup(function()
        newBuild()
    end)

    it("inline guard markers present in Build.lua", function()
        local f = io.open("Modules/Build.lua", "r") or io.open("src/Modules/Build.lua", "r") or io.open("../src/Modules/Build.lua", "r")
        assert.is_not_nil(f, "must be able to open Modules/Build.lua")
        local text = f:read("*a"); f:close()
        local _, n = text:gsub("@leb%-regression%-guard:minion%-selection%-determinism", "")
        assert.is_true(n >= 2, "both fixed sites in Build.lua must carry the inline guard marker (found " .. n .. ")")
    end)

    it("real data: the minions.json hands legendary resolves to the smallest sibling uniqueId", function()
        local handsId = "IIwBhBYwVjEg" -- 1.2/minions.json hands slot (legendary, no uniqueId in bases.json)
        local leBase = data.LETools_itemBases[handsId]
        assert.is_not_nil(leBase, "fixture id must exist in bases.json (update this spec if bases.json is regenerated)")
        assert.is_nil(leBase.uniqueId, "fixture id must be a legendary-style entry (no uniqueId)")
        local candidates = { }
        for _, entry in pairs(data.LETools_itemBases) do
            if entry.baseTypeId == leBase.baseTypeId and entry.subTypeId == leBase.subTypeId and entry.uniqueId then
                candidates[#candidates + 1] = entry.uniqueId
            end
        end
        table.sort(candidates)
        assert.is_true(#candidates >= 2, "fixture must be AMBIGUOUS (>=2 unique siblings) to exercise the guard; found " .. #candidates)
        local expected = data.uniques[candidates[1]]
        assert.is_not_nil(expected, "smallest-uniqueId candidate must exist in data.uniques")

        local char = build:ReadLeToolsSave(minimalSave({
            hands = { id = handsId, affixes = { } },
        }))
        assert.are.equal(1, #char.items)
        assert.are.equal("LEGENDARY", char.items[1].rarity)
        assert.are.equal(expected.name, char.items[1].name,
            "must resolve to the smallest uniqueId (" .. candidates[1] .. "), not a pairs()-order pick")
    end)

    it("synthetic: winner follows smallest uniqueId regardless of table insertion order", function()
        local injectedBases = {
            ["zzTestLegendaryBase"] = { baseTypeId = 9999, subTypeId = 9999 },
            ["aaTestUniqueHi"]      = { baseTypeId = 9999, subTypeId = 9999, uniqueId = 900003 },
            ["mmTestUniqueLo"]      = { baseTypeId = 9999, subTypeId = 9999, uniqueId = 900001 },
            ["zzTestUniqueMid"]     = { baseTypeId = 9999, subTypeId = 9999, uniqueId = 900002 },
        }
        local injectedUniques = {
            [900001] = { name = "Test Unique Lo",  mods = { } },
            [900002] = { name = "Test Unique Mid", mods = { } },
            [900003] = { name = "Test Unique Hi",  mods = { } },
        }
        for k, v in pairs(injectedBases) do data.LETools_itemBases[k] = v end
        for k, v in pairs(injectedUniques) do data.uniques[k] = v end

        local ok, err = pcall(function()
            local char = build:ReadLeToolsSave(minimalSave({
                hands = { id = "zzTestLegendaryBase", affixes = { } },
            }))
            assert.are.equal(1, #char.items)
            assert.are.equal("LEGENDARY", char.items[1].rarity)
            assert.are.equal("Test Unique Lo", char.items[1].name,
                "must pick uniqueId 900001 (the minimum), independent of hash order")
        end)

        for k in pairs(injectedBases) do data.LETools_itemBases[k] = nil end
        for k in pairs(injectedUniques) do data.uniques[k] = nil end
        assert.is_true(ok, tostring(err))
    end)

    it("synthetic: single-candidate fallback and direct uniqueId path are unchanged", function()
        local injectedBases = {
            ["zzTestSoloLegendary"] = { baseTypeId = 9998, subTypeId = 9998 },
            ["zzTestSoloUnique"]    = { baseTypeId = 9998, subTypeId = 9998, uniqueId = 900011 },
        }
        local injectedUniques = {
            [900011] = { name = "Test Solo Unique", mods = { } },
        }
        for k, v in pairs(injectedBases) do data.LETools_itemBases[k] = v end
        for k, v in pairs(injectedUniques) do data.uniques[k] = v end

        local ok, err = pcall(function()
            -- legendary-style id with exactly one unique sibling -> that unique, LEGENDARY
            local char = build:ReadLeToolsSave(minimalSave({
                hands = { id = "zzTestSoloLegendary", affixes = { } },
            }))
            assert.are.equal("LEGENDARY", char.items[1].rarity)
            assert.are.equal("Test Solo Unique", char.items[1].name)
            -- id that itself carries uniqueId -> UNIQUE, no fallback involved
            char = build:ReadLeToolsSave(minimalSave({
                hands = { id = "zzTestSoloUnique", affixes = { } },
            }))
            assert.are.equal("UNIQUE", char.items[1].rarity)
            assert.are.equal("Test Solo Unique", char.items[1].name)
        end)

        for k in pairs(injectedBases) do data.LETools_itemBases[k] = nil end
        for k in pairs(injectedUniques) do data.uniques[k] = nil end
        assert.is_true(ok, tostring(err))
    end)
end)
