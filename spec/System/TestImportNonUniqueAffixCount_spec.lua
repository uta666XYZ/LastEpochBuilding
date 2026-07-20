-- @leb-regression-guard:import-nonunique-affix-count
-- See REGRESSION_GUARDS.md "import-nonunique-affix-count". Item bytes below are
-- Validation provenance is retained in maintainer notes.

local dkjson = require "dkjson"

-- Encode one 3-byte affix record: affixId = idByte + (tierByte % 16) * 256 ;
-- tier = floor(tierByte / 16).
local function affixBytes(affixId, tier, range)
    local hi = math.floor(affixId / 256)
    local lo = affixId % 256
    return { tier * 16 + hi, lo, (range or 128) }
end

-- Non-unique body-armour record (baseType 1 / subType 4 = Banded Armor) on
-- containerID 3. d[1]=version 5, d[2..3]=seed, d[4..5]=base/subType, d[6]=rarity,
-- d[7..11]=header, d[12]=BASE+8 sealed-flags/count byte, d[13..]=affix records.
local function equipItem(sealedFlagsByte, affixRecords)
    local d = { 5, 0, 0, 1, 4, 2, 128, 128, 128, 0, 0, sealedFlagsByte }
    for _, rec in ipairs(affixRecords) do
        d[#d + 1] = rec[1]; d[#d + 1] = rec[2]; d[#d + 1] = rec[3]
    end
    return { containerID = 3, data = d }
end

local function makeSave(items)
    return {
        characterClass = 3,
        chosenMastery = 2,
        characterName = "ImportNonUniqueAffixCountFixture",
        level = 100,
        savedCharacterTree = { nodeIDs = {}, nodePoints = {} },
        savedSkillTrees = {},
        savedQuests = {},
        savedItems = items,
    }
end

-- Live facts, so no id/tier is hard-coded: two DISTINCT affix ids that both
-- resolve at tier 1. affixId 0 is unusable (a decoded 0 means "empty slot").
local function liveAffixIds()
    local ids = {}
    for id = 1, 1200 do
        if data.itemMods.Item[id .. "_1"] then
            ids[#ids + 1] = id
            if #ids >= 3 then break end
        end
    end
    return ids[1], ids[2], ids[3]
end

local function importItems(save)
    return build.importTab:ReadJsonSaveData(dkjson.encode(save))
end

local function affixesOf(char)
    local out = {}
    for _, it in ipairs(char.items or {}) do
        for _, a in ipairs(it.prefixes or {}) do out[#out + 1] = a end
        for _, a in ipairs(it.suffixes or {}) do out[#out + 1] = a end
    end
    return out
end

describe("offline-save import: non-unique affix loop is bounded by the serialised count", function()
    local realId, payloadId, payloadId2

    setup(function()
        realId, payloadId, payloadId2 = liveAffixIds()
        assert.is_truthy(realId)
        assert.is_truthy(payloadId)
        assert.is_truthy(payloadId2)
    end)

    -- THE negative test: a count-2 item whose trailing bytes happen to decode to
    -- ids that DO resolve in itemMods. Pre-fix the window read all 7 slots and
    -- imported the payload as real affixes.
    it("must not import trailing payload that decodes to resolvable affixes (count=2)", function()
        local save = makeSave({ equipItem(2, {
            affixBytes(realId, 1),
            affixBytes(realId, 1),
            -- payload past the count -- resolvable, but NOT affixes
            affixBytes(payloadId, 1),
            affixBytes(payloadId2, 1),
        }) })
        local affixes = affixesOf(importItems(save))
        assert.are.equal(2, #affixes)
        for _, a in ipairs(affixes) do
            assert.are.equal(realId .. "_1", a.modId)
        end
    end)

    it("count=0 must import no affixes even when trailing bytes resolve", function()
        local save = makeSave({ equipItem(0, {
            affixBytes(payloadId, 1),
            affixBytes(payloadId2, 1),
        }) })
        assert.are.equal(0, #affixesOf(importItems(save)))
    end)

    -- The count byte is packed: flags must not leak into the bound.
    it("count must be masked out of the packed flag byte (0x80|2 -> 2 affixes)", function()
        local save = makeSave({ equipItem(0x80 + 2, {
            affixBytes(realId, 1),
            affixBytes(realId, 1),
            affixBytes(payloadId, 1),
        }) })
        assert.are.equal(2, #affixesOf(importItems(save)))
    end)

    it("count must be masked out of the packed flag byte (0x40|1 -> 1 affix)", function()
        local save = makeSave({ equipItem(0x40 + 1, {
            affixBytes(realId, 1),
            affixBytes(payloadId, 1),
        }) })
        assert.are.equal(1, #affixesOf(importItems(save)))
    end)

    -- Under-read direction: the count must not be clamped to some smaller window.
    it("count=6 must import all 6 declared affixes", function()
        local recs = {}
        for _ = 1, 6 do recs[#recs + 1] = affixBytes(realId, 1) end
        local save = makeSave({ equipItem(6, recs) })
        assert.are.equal(6, #affixesOf(importItems(save)))
    end)

    it("a truncated record must not crash and must import only what is present", function()
        -- declares 4 affixes but only ~1.5 triples of bytes follow
        local d = { 5, 0, 0, 1, 4, 2, 128, 128, 128, 0, 0, 4 }
        local r = affixBytes(realId, 1)
        d[#d + 1] = r[1]; d[#d + 1] = r[2]; d[#d + 1] = r[3]
        d[#d + 1] = r[1]
        local save = makeSave({ { containerID = 3, data = d } })
        local char
        assert.has_no.errors(function() char = importItems(save) end)
        assert.are.equal(1, #affixesOf(char))
    end)

    -- Guard the kind-tagging interplay: the bound now enforces what the old
    -- `i < serialisedAffixCount` test did, so positional tagging still applies
    -- only to counted slots.
    it("sealed tagging still applies positionally within the counted slots", function()
        local save = makeSave({ equipItem(0x80 + 2, {
            affixBytes(realId, 1),
            affixBytes(realId, 1),
            affixBytes(payloadId, 1),
        }) })
        local affixes = affixesOf(importItems(save))
        assert.are.equal(2, #affixes)
        local kinds = {}
        for _, a in ipairs(affixes) do kinds[#kinds + 1] = a.kind or "nil" end
        table.sort(kinds)
        assert.are.same({ "nil", "sealed" }, kinds)
    end)
end)
