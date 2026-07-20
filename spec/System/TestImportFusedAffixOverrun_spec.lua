-- @leb-regression-guard:import-fused-affix-overrun
-- See REGRESSION_GUARDS.md "import-fused-affix-overrun". Fixtures below are
-- Validation provenance is retained in maintainer notes.

local dkjson = require "dkjson"

local CORE_MTN_BASE = { 1, 4 }   -- Banded Armor -> uniqueID 255

-- Real (affixId, tier) pairs that resolve in data.itemMods.Item, encoded the way the
-- parser reads them: byte0 = tier*16 + floor(affixId/256), byte1 = affixId % 256.
local A_34_6  = { 96, 34 }   -- Prefix
local A_25_6  = { 96, 25 }   -- Suffix
local A_55_1  = { 16, 55 }   -- Suffix
local A_12_3  = { 48, 12 }   -- Prefix
local A_338_1 = { 17, 82 }   -- Prefix

-- Legendary record: `countByte` at d[21], then one 3-byte (tierByte, idByte, range)
-- triple per entry of `affixes`. `trailing` appends raw filler bytes instead.
local function fusedRecord(cid, uniqueId, countByte, affixes, trailing)
    local hi = math.floor(uniqueId / 256)
    local lo = uniqueId % 256
    local d = { 5, 0, 0, CORE_MTN_BASE[1], CORE_MTN_BASE[2], 9,   -- 0x09 clean legendary
                128, 128, 128,                                    -- 3 implicit rolls
                0,                                                -- flags
                hi, lo,                                           -- uniqueID
                128, 128, 128, 128, 128, 128, 128, 128,           -- 8 unique roll bytes
                countByte }                                       -- packed fused-affix byte
    for _, a in ipairs(affixes or {}) do
        d[#d + 1] = a[1]; d[#d + 1] = a[2]; d[#d + 1] = 128
    end
    for _ = 1, (trailing or 0) do d[#d + 1] = 128 end
    return { containerID = cid, data = d }
end

local function makeSave(items)
    return {
        characterClass = 3,
        chosenMastery = 2,
        characterName = "ImportFusedAffixOverrunFixture",
        level = 100,
        savedCharacterTree = { nodeIDs = {}, nodePoints = {} },
        savedSkillTrees = {},
        savedQuests = {},
        savedItems = items,
    }
end

local function importItems(save)
    local ok, charOrErr = pcall(function()
        return build.importTab:ReadJsonSaveData(dkjson.encode(save))
    end)
    assert.is_true(ok, "ReadJsonSaveData crashed: " .. tostring(charOrErr))
    local bySlot = {}
    for _, it in ipairs(charOrErr.items) do bySlot[it.inventoryId] = it end
    return bySlot
end

-- All fused affixes of an item as a modId set, plus the total count.
local function fusedMods(item)
    local set, n = {}, 0
    for _, group in ipairs({ item.prefixes or {}, item.suffixes or {} }) do
        for _, a in ipairs(group) do set[a.modId] = true; n = n + 1 end
    end
    return set, n
end

describe("ImportFusedAffixOverrun", function()
    describe("count byte is masked to its low 3 bits, not clamped", function()
        it("honours a bit7 count byte (130 -> 2), dropping the phantom triples after it", function()
            newBuild()
            -- 130 = 0x82: bit7 (sealed-from-corruption) + count 2. FOUR resolvable
            -- triples follow; only the first two are real. Pre-fix math.min(130,4)=4
            -- imported all four.
            local save = makeSave({ fusedRecord(3, 255, 130, { A_34_6, A_25_6, A_55_1, A_12_3 }) })
            local item = importItems(save)[3]
            local set, n = fusedMods(item)
            assert.are.equal("Core of the Mountain", item.name)
            assert.are.equal(2, n, "count byte 130 must decode to 2 fused affixes (130 & 7), not 4")
            assert.is_true(set["34_6"] and set["25_6"], "the two real fused affixes must import")
            assert.is_nil(set["55_1"], "triple past the masked count must NOT import (phantom)")
            assert.is_nil(set["12_3"], "triple past the masked count must NOT import (phantom)")
        end)

        it("keeps a count of 5 (byte 133), above MaxLegendaryPotential, instead of clamping to 4", function()
            newBuild()
            -- 133 = 0x85: bit7 + count 5. A legendary can carry a corruption-sealed
            -- affix on top of its <= 4 LP affixes. Pre-fix math.min(133,4)=4 dropped
            -- the 5th real affix.
            local save = makeSave({ fusedRecord(3, 255, 133, { A_34_6, A_25_6, A_55_1, A_12_3, A_338_1 }) })
            local item = importItems(save)[3]
            local set, n = fusedMods(item)
            assert.are.equal(5, n, "count byte 133 must decode to 5 fused affixes (133 & 7), not clamp to 4")
            assert.is_true(set["338_1"], "the 5th real fused affix must not be dropped by a clamp")
        end)

        it("still decodes a plain low count byte (3) unchanged", function()
            newBuild()
            -- The common bit7-clear case, where min(count,4) happened to be correct.
            local save = makeSave({ fusedRecord(3, 255, 3, { A_34_6, A_25_6, A_55_1, A_12_3 }) })
            local _, n = fusedMods(importItems(save)[3])
            assert.are.equal(3, n, "count byte 3 must decode to 3 fused affixes")
        end)

        it("decodes count 0 as no fused affixes", function()
            newBuild()
            local save = makeSave({ fusedRecord(3, 255, 0, { A_34_6 }) })
            local item = importItems(save)[3]
            local _, n = fusedMods(item)
            assert.are.equal("LEGENDARY", item.rarity)
            assert.are.equal(0, n, "count byte 0 must decode to no fused affixes")
        end)
    end)

    describe("short / truncated records do not crash the import", function()
        it("does not crash when the affix window overruns the data array (count=1, only 1 trailing byte)", function()
            newBuild()
            -- d[dataId] present, d[dataId+1] nil -> the exact pre-fix crash.
            local item = importItems(makeSave({ fusedRecord(3, 255, 1, {}, 1) }))[3]
            assert.are.equal("Core of the Mountain", item.name)
            assert.are.equal("LEGENDARY", item.rarity)
        end)

        it("does not crash when the count byte itself is past the data end (nbMods nil)", function()
            newBuild()
            local d = { 5, 0, 0, CORE_MTN_BASE[1], CORE_MTN_BASE[2], 9,
                        128, 128, 128, 0, 0, 255, 128, 128, 128, 128, 128, 128, 128, 128 } -- no count byte
            local item = importItems(makeSave({ { containerID = 3, data = d } }))[3]
            assert.are.equal("LEGENDARY", item.rarity)
        end)

        it("masks a 255 count byte to 7 and still stops at the data end", function()
            newBuild()
            -- 255 & 7 = 7, but only 4 trailing bytes exist: the full-triple guard must
            -- stop the loop rather than run off the array.
            local item = importItems(makeSave({ fusedRecord(3, 255, 255, {}, 4) }))[3]
            local _, n = fusedMods(item)
            assert.are.equal("Core of the Mountain", item.name)
            assert.is_true(n <= 7, "masked count must bound the loop")
        end)
    end)

    describe("captured fused-affix bytes", function()
        -- Validation provenance is retained in maintainer notes.
        local WEAPON_EXEC_TITHE = {   -- containerID 4 -> uniqueID 420
            5, 77, 118, 5, 9, 137, 87, 220, 204, 43, 1, 164, 195, 64, 198, 199, 111,
            241, 218, 71, 131, 99, 175, 179, 66, 212, 205, 16, 55, 81, 16, 146, 13,
            195, 164, 225, 241, 189, 50, 35, 185, 53, 207, 88, 161, 26,
        }
        local BODY_CORE_MTN_REAL = {  -- containerID 3 -> uniqueID 255
            5, 59, 253, 1, 4, 137, 89, 207, 95, 224, 0, 255, 19, 240, 52, 153, 113,
            147, 146, 137, 130, 96, 34, 251, 96, 25, 45, 9, 109, 74, 87, 18, 161, 121,
            227, 60, 197, 102, 92, 5, 236, 184, 156,
        }

        it("imports the real fused legendary weapon with exactly 131 & 7 = 3 fused affixes", function()
            newBuild()
            local item = importItems(makeSave({ { containerID = 4, data = WEAPON_EXEC_TITHE } }))[4]
            local set, n = fusedMods(item)
            assert.are.equal("Executioner's Tithe", item.name)
            assert.are.equal("LEGENDARY", item.rarity)
            assert.are.equal(3, n, "count byte 131 must decode to 3 fused affixes")
            assert.is_true(set["943_6"] and set["724_4"] and set["55_1"],
                "the three real fused affixes must import")
        end)

        it("imports the real fused legendary body with exactly 130 & 7 = 2 fused affixes", function()
            newBuild()
            local item = importItems(makeSave({ { containerID = 3, data = BODY_CORE_MTN_REAL } }))[3]
            local set, n = fusedMods(item)
            assert.are.equal("Core of the Mountain", item.name)
            assert.are.equal("LEGENDARY", item.rarity)
            assert.are.equal(2, n, "count byte 130 must decode to 2 fused affixes")
            assert.is_true(set["34_6"] and set["25_6"], "the two real fused affixes must import")
        end)
    end)
end)
