-- @leb-regression-guard:import-rarity-flag-bits
-- See REGRESSION_GUARDS.md "import-rarity-flag-bits".
-- Validation provenance is retained in maintainer notes.

local dkjson = require "dkjson"

-- Build a minimal serialisation-v5 offline-save item record for a unique/
-- legendary. Layout (Lua 1-indexed d[]): d[1]=version(5, != 2 so BASE=4),
-- d[2..3]=seed, d[BASE]=baseType, d[BASE+1]=subType, d[BASE+2]=rarity byte,
-- d[BASE+3..5]=implicit rolls, d[BASE+6]=flags, d[BASE+7..8]=uniqueID hi/lo,
-- d[BASE+9..16]=8 unique roll bytes, d[BASE+17]=fused-affix count (0 = none).
local function uniqueRecord(cid, baseType, subType, rarityByte, uniqueId)
    local hi = math.floor(uniqueId / 256)
    local lo = uniqueId % 256
    return {
        containerID = cid,
        data = { 5, 0, 0, baseType, subType, rarityByte,
                 128, 128, 128,                      -- 3 implicit rolls
                 0,                                  -- flags byte
                 hi, lo,                             -- uniqueID
                 128, 128, 128, 128, 128, 128, 128, 128, -- 8 unique roll bytes
                 0 },                                -- fused-affix count
    }
end

-- A non-unique exalted record: rarity 0x82 (130) = bit7|2. Low nibble 2 must
-- route to the affix path, NOT the unique path. Affix region all-zero so no
-- affixes are parsed.
local function exaltedNonUniqueRecord(cid, baseType, subType)
    return {
        containerID = cid,
        data = { 5, 0, 0, baseType, subType, 130,
                 0, 0, 0, 0, 0, 0,
                 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    }
end

-- baseType/subType pairs are the real bases of these uniques.
local EXEC_TITHE_BASE = { 5, 9 }   -- Soul Harvester  -> uniqueID 420
local CORE_MTN_BASE   = { 1, 4 }   -- Banded Armor    -> uniqueID 255

local function makeSave()
    return {
        characterClass = 3,   -- valid class (Acolyte family); known-good scaffold
        chosenMastery = 2,
        characterName = "ImportRarityFlagBitsFixture",
        level = 100,
        savedCharacterTree = { nodeIDs = {}, nodePoints = {} },
        savedSkillTrees = {},
        savedQuests = {},
        savedItems = {
            -- THE BUG: bit7 (0x89) Legendary-Potential-fused legendaries.
            uniqueRecord(4, EXEC_TITHE_BASE[1], EXEC_TITHE_BASE[2], 137, 420),
            uniqueRecord(3, CORE_MTN_BASE[1],   CORE_MTN_BASE[2],   137, 255),
            -- Controls that must keep working:
            uniqueRecord(5, EXEC_TITHE_BASE[1], EXEC_TITHE_BASE[2],   9, 420), -- clean legendary
            uniqueRecord(6, CORE_MTN_BASE[1],   CORE_MTN_BASE[2],    73, 255), -- Weaver's Will (bit6)
            -- bit7 on a non-unique = Exalted; must NOT be read as a unique.
            exaltedNonUniqueRecord(7, CORE_MTN_BASE[1], CORE_MTN_BASE[2]),
        },
    }
end

describe("ImportRarityFlagBits", function()
    local char, bySlot

    before_each(function()
        newBuild()
        char = build.importTab:ReadJsonSaveData(dkjson.encode(makeSave()))
        bySlot = {}
        for _, it in ipairs(char.items) do
            bySlot[it.inventoryId] = it
        end
    end)

    it("imports a bit7 (0x89) legendary weapon as the unique, not as Exalted", function()
        assert.is_not_nil(bySlot[4])
        assert.are.equal("Executioner's Tithe", bySlot[4].name)
        assert.are.equal("LEGENDARY", bySlot[4].rarity)
    end)

    it("imports a bit7 (0x89) legendary body as the unique, not as Exalted", function()
        assert.is_not_nil(bySlot[3])
        assert.are.equal("Core of the Mountain", bySlot[3].name)
        assert.are.equal("LEGENDARY", bySlot[3].rarity)
    end)

    it("still imports a clean legendary (0x09) correctly", function()
        assert.are.equal("Executioner's Tithe", bySlot[5].name)
        assert.are.equal("LEGENDARY", bySlot[5].rarity)
    end)

    it("still imports a Weaver's Will legendary (0x49 = bit6|9) correctly", function()
        assert.are.equal("Core of the Mountain", bySlot[6].name)
        assert.are.equal("LEGENDARY", bySlot[6].rarity)
    end)

    it("routes a bit7 non-unique (0x82 Exalted) to the affix path, not the unique path", function()
        assert.is_not_nil(bySlot[7])
        assert.is_not.equal("Core of the Mountain", bySlot[7].name)
        assert.is_not.equal("LEGENDARY", bySlot[7].rarity)
        assert.is_not.equal("UNIQUE", bySlot[7].rarity)
        assert.is_not.equal("SET", bySlot[7].rarity)
    end)

    it("does not mis-read the unique roll bytes as bogus affixes", function()
        -- The pre-fix symptom was [IMPORT-DROP] affixes + parse errors when the
        -- legendary fell through to the affix path. With correct routing the
        -- fused-affix count is 0 and nothing is dropped.
        assert.are.equal(0, char._parseErrors)
        assert.are.equal(0, char._droppedAffixes)
    end)
end)
