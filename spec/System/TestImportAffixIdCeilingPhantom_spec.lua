-- @leb-regression-guard:import-affix-id-ceiling-phantom
-- Locks the contract that the offline-save binary item parser
-- (ImportTabClass:ReadJsonSaveData, non-unique affix-loop path,
-- src/Classes/ImportTab.lua) classifies a decoded affixId ABOVE the affix
-- registry ceiling as a phantom over-read of trailing item payload -- NOT as a
-- "dropped affix" -- so it is not counted in char._droppedAffixes and does not
-- inflate the user-facing "N affix(es) dropped" import message.
--
-- Background: Omen Idols / Woven idols / Prophesied Altars serialize extra
-- "omen" bytes AFTER their real affixes. The fixed 7-slot affix loop reads those
-- trailing bytes as bogus 3-byte affix triples, which decode to affixIds far
-- beyond the game's real affix registry (1.4.7 tops out at affixId 1112) with
-- impossible tiers (>7). Observed on the Maxroll Hammerdin (Xiemiel): a Large
-- Iron Omen Idol -> 1822_1 / 1835_12, a Heretical Rahyeh Idol -> 3224_7 /
-- 2343_5, a Prophesied Altar -> 3238_1. These are correctly rejected (not in
-- itemMods.Item) but were previously counted as "silently dropped affixes",
-- producing an alarming "6 affix(es) dropped" message that falsely implied lost
-- build power and repeatedly misled DPS-gap investigations into hunting
-- non-existent >1112 idol/altar affixes. Datamine confirmed the game's entire
-- affix registry (AffixList singleAffixes+multiAffixes + all idol affixes) maxes
-- at affixId 1112; LEB's own ModItem/ModIdol data maxes at 1112 too. So no affix
-- can decode above the ceiling -- anything larger is a mis-decode of non-affix
-- bytes.
--
-- The fix derives maxKnownAffixId from data.itemMods.Item once per import, then
-- in the affix-loop else-branch splits the "not in itemMods" case: affixId >
-- ceiling -> [IMPORT-OVERREAD] (logged, not counted); affixId <= ceiling ->
-- [IMPORT-DROP] (still counted, a genuine possible data gap). Deriving the
-- ceiling from data (not hard-coding 1112) makes it self-update if the mod
-- tables ever gain higher ids.
--
-- See REGRESSION_GUARDS.md "import-affix-id-ceiling-phantom". Item bytes below
-- are SYNTHETIC minimal serialisation-v5 records (public enum values only,
-- same layout as TestImportFusedAffixOverrun_spec.lua); the valid/absent affix
-- ids are read from the LIVE mod data so the test is dataset-agnostic.

local dkjson = require "dkjson"

-- Encode one 3-byte affix record (tierByte, idByte, rangeByte) so that the
-- parser decodes it back to (affixId, tier): the loop computes
--   affixId = idByte + (tierByte % 16) * 256 ; tier = floor(tierByte / 16).
local function affixBytes(affixId, tier, range)
    local hi = math.floor(affixId / 256)          -- low nibble of tierByte
    local lo = affixId % 256                       -- idByte
    return tier * 16 + hi, lo, (range or 128)
end

-- A non-unique (rarity byte < 7) body-armour record on a real base
-- (baseType 1 / subType 4 = Banded Armor, per TestImportRarityFlagBits) so
-- matchedBase is true and the affix loop runs. Layout (1-indexed): d[1]=version
-- 5, d[2..3]=seed, d[4..5]=base/subType, d[6]=rarity, d[7..12]=implicit/flag
-- header, d[13..]=affix records (slot0 tierByte at BASE+9 = d[13]).
-- d[12] (BASE+8) is the packed sealed-flags/affix-count byte: its low 6 bits are
-- the serialised affix count, and the import loop is bounded by it
-- (@leb-regression-guard:import-nonunique-affix-count). It is set to the number of
-- records the fixture carries -- exactly what the game's serialiser writes
-- (`id[11] = affixes.Count | flags`) -- so these records stay realizable saves.
-- Leaving it 0 while appending affix bytes describes a save that cannot exist, and
-- the count-bounded loop would (correctly) read none of them.
local function rareItem(cid, affixRecords)
    local d = { 5, 0, 0, 1, 4, 2, 128, 128, 128, 0, 0, #affixRecords }
    for _, rec in ipairs(affixRecords) do
        d[#d + 1] = rec[1]; d[#d + 1] = rec[2]; d[#d + 1] = rec[3]
    end
    return { containerID = cid, data = d }
end

local function makeSave(items)
    return {
        characterClass = 3,
        chosenMastery = 2,
        characterName = "ImportAffixCeilingFixture",
        level = 100,
        savedCharacterTree = { nodeIDs = {}, nodePoints = {} },
        savedSkillTrees = {},
        savedQuests = {},
        savedItems = items,
    }
end

-- Read a real (affixId, tier) that IS in itemMods.Item, plus the registry
-- ceiling, straight from the loaded data so the fixture never hard-codes ids.
local function liveAffixFacts()
    local ceiling, validId, validTier = 0, nil, nil
    for modId in pairs(data.itemMods.Item) do
        local idStr, tierStr = tostring(modId):match("^(%d+)_(%d+)$")
        local id = idStr and tonumber(idStr)
        if id then
            if id > ceiling then ceiling = id end
            -- prefer a small, unambiguous id well below the ceiling
            if (not validId) and id > 0 and id < 500 then
                validId, validTier = id, tonumber(tierStr)
            end
        end
    end
    return ceiling, validId, validTier
end

describe("ImportAffixIdCeilingPhantom", function()
    local ceiling, validId, validTier
    before_each(function()
        newBuild()
        ceiling, validId, validTier = liveAffixFacts()
    end)

    it("derives a registry ceiling matching the datamined 1.4.7 max (1112)", function()
        assert.are.equal(1112, ceiling)
    end)

    it("does NOT count an above-ceiling decode as a dropped affix (phantom over-read)", function()
        -- 1822_1 = the real captured Large Iron Omen Idol over-read (id 1822 > 1112).
        local tb, ib, rb = affixBytes(1822, 1, 8)
        local save = makeSave({ rareItem(3, { { tb, ib, rb } }) })
        local char = build.importTab:ReadJsonSaveData(dkjson.encode(save))
        assert.are.equal(0, char._droppedAffixes or 0)
    end)

    it("STILL counts an at-or-below-ceiling missing affix as a dropped affix", function()
        -- Reuse a real affixId but with an impossible tier (15) so the modId is
        -- absent from itemMods yet the affixId stays <= ceiling: a genuine drop.
        assert.is_truthy(validId, "no live affixId < 500 found to build the control case")
        local tb, ib, rb = affixBytes(validId, 15, 128)
        local save = makeSave({ rareItem(3, { { tb, ib, rb } }) })
        local char = build.importTab:ReadJsonSaveData(dkjson.encode(save))
        assert.are.equal(1, char._droppedAffixes or 0)
    end)

    it("imports a real below-ceiling affix normally (the loop is genuinely exercised)", function()
        assert.is_truthy(validId, "no live affixId < 500 found to build the valid case")
        local tb, ib, rb = affixBytes(validId, validTier, 128)
        local save = makeSave({ rareItem(3, { { tb, ib, rb } }) })
        local char = build.importTab:ReadJsonSaveData(dkjson.encode(save))
        assert.are.equal(0, char._droppedAffixes or 0)
        local bySlot = {}
        for _, it in ipairs(char.items) do bySlot[it.inventoryId] = it end
        local item = bySlot[3]
        assert.is_not_nil(item)
        assert.is_true(#(item.prefixes or {}) + #(item.suffixes or {}) >= 1,
            "the valid below-ceiling affix was not imported")
    end)

    it("mixes valid + phantom on one item: valid imports, phantom not counted", function()
        assert.is_truthy(validId, "no live affixId < 500 found for the mixed case")
        local vtb, vib, vrb = affixBytes(validId, validTier, 128)   -- slot0: real affix
        local ptb, pib, prb = affixBytes(1835, 12, 209)             -- slot1: phantom (1835_12)
        local save = makeSave({ rareItem(3, { { vtb, vib, vrb }, { ptb, pib, prb } }) })
        local char = build.importTab:ReadJsonSaveData(dkjson.encode(save))
        assert.are.equal(0, char._droppedAffixes or 0)
        local bySlot = {}
        for _, it in ipairs(char.items) do bySlot[it.inventoryId] = it end
        assert.is_true(#(bySlot[3].prefixes or {}) + #(bySlot[3].suffixes or {}) >= 1,
            "the real affix beside a phantom over-read was not imported")
    end)
end)
