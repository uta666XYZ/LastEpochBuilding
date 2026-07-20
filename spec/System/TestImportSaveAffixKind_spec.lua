-- @leb-regression-guard:import-save-affix-kind
-- Locks the contract that the offline-save binary item parser
-- (ImportTabClass:ReadJsonSaveData, non-unique affix-loop path,
-- src/Classes/ImportTab.lua) populates affix `kind` ("sealed" / "primordial" /
-- "corrupted"; nil for a normal affix) instead of leaving it nil on every
-- save-imported affix.
--
-- Background: the 3-byte affix triple carries ONLY tier<<4|id-hi, id-lo, roll --
-- the game's ItemData.RebuildID writes nothing else per affix, so sealed state
-- genuinely is not in the triple. It is stored in the byte immediately BEFORE the
-- affix region (BASE+8 == the game's id[11]), which the decoder never read:
--   id[11] = affixCount
--          | (hasSealedAffixFromCorruption and 0x40 or 0)
--          | (hasSealedRegularAffix        and 0x80 or 0)
-- (writer: datamined game source; reader: datamined game source
-- via GetBit(id[11],7) / GetBit(id[11],6) / (id[11] & 0x3f)).
--
-- Which affix is which is POSITIONAL, resolved at load time by
-- loadAffixFromSerialisation (datamined game source call site, body at datamined game source+):
--   regular sealed = hasSealedRegularAffix   and index == 0
--   corrupted      = hasSealedFromCorruption and index == (regular and 1 or 0)
--   primordial     = tier nibble == 7
-- with corruption tested BEFORE tier==7 (Item.GetSealedAffixType orders those two
-- the other way; the load path is authoritative).
--
-- Why it is not merely cosmetic: LE's ItemAffix.CanContributeToLevelRequirement
-- (datamined game source) is `specialAffixType == 0 && sealedAffixType
-- == 0`, mirrored by Item.lua's `not affix.kind` gate in
-- computeAffixDerivedLevelReq. With kind nil, a save-imported sealed/primordial/
-- corrupted affix wrongly contributed to the affix-derived req.level.
--
-- Scope: this is the game's rarity<5 branch (Normal/Magic/Rare/Exalted, and all
-- idols -- idol itemType 25-33 is far below the 0x65 cut and idols are never
-- rarity 9). Legendary (rarity 9) fused affixes live in a different region and are
-- NOT covered here.
--
-- See REGRESSION_GUARDS.md "import-save-affix-kind". Item bytes below are
-- SYNTHETIC minimal serialisation-v5 records; affix ids/tiers are read from the
-- LIVE mod data so the test is dataset-agnostic.

local dkjson = require "dkjson"

-- Encode one 3-byte affix record: affixId = idByte + (tierByte % 16) * 256 ;
-- tier = floor(tierByte / 16).
local function affixBytes(affixId, tier, range)
    local hi = math.floor(affixId / 256)
    local lo = affixId % 256
    return tier * 16 + hi, lo, (range or 128)
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
        characterName = "ImportSaveAffixKindFixture",
        level = 100,
        savedCharacterTree = { nodeIDs = {}, nodePoints = {} },
        savedSkillTrees = {},
        savedQuests = {},
        savedItems = items,
    }
end

-- Live facts, so no id/tier is hard-coded here:
--   normalId : an affixId present at tiers 0..2 and 5 (the multi-slot ordering and
--              req.level cases need several tiers of the SAME id)
--   primId   : an affixId present at tier 7 (the primordial row)
-- affixId 0 is unusable as a fixture: the decoder treats a decoded 0 as "empty
-- slot" (`if affixId and affixId > 0`), so ids start at 1.
local function liveAffixFacts()
    local normalId, primId
    for id = 1, 1200 do
        if not normalId
            and data.itemMods.Item[id .. "_0"] and data.itemMods.Item[id .. "_1"]
            and data.itemMods.Item[id .. "_2"] and data.itemMods.Item[id .. "_5"] then
            normalId = id
        end
        if not primId and data.itemMods.Item[id .. "_7"] then
            primId = id
        end
        if normalId and primId then break end
    end
    return normalId, 0, primId
end

local function importItems(save)
    local char = build.importTab:ReadJsonSaveData(dkjson.encode(save))
    return char
end

-- Flatten every imported affix into decode order.
local function affixesOf(char)
    local out = {}
    for _, it in ipairs(char.items or {}) do
        for _, a in ipairs(it.prefixes or {}) do out[#out + 1] = a end
        for _, a in ipairs(it.suffixes or {}) do out[#out + 1] = a end
    end
    return out
end

local function kindOfModId(char, modId)
    for _, a in ipairs(affixesOf(char)) do
        if a.modId == modId then return a.kind, true end
    end
    return nil, false
end

describe("ImportSaveAffixKind", function()
    local nId, nTier, pId
    before_each(function()
        newBuild()
        nId, nTier, pId = liveAffixFacts()
    end)

    it("has live fixture data (an affix at a normal tier and one with a tier-7 row)", function()
        assert.is_truthy(nId, "no live affixId with a _0 row found")
        assert.is_truthy(pId, "no live affixId with a _7 (primordial) row found")
    end)

    -- Baseline: this is the pre-fix behaviour for a plain item and must not change.
    it("leaves kind nil for a normal affix (no sealed flags set)", function()
        local t, i, r = affixBytes(nId, nTier, 128)
        -- flags byte: count 1, no sealed bits.
        local char = importItems(makeSave({ equipItem(1, { { t, i, r } }) }))
        local kind, found = kindOfModId(char, nId .. "_" .. nTier)
        assert.is_true(found, "the normal affix was not imported at all")
        assert.is_nil(kind)
    end)

    it("tags index 0 as sealed when bit7 (hasSealedRegularAffix) is set", function()
        local t, i, r = affixBytes(nId, nTier, 128)
        -- 0x80 | count 1
        local char = importItems(makeSave({ equipItem(0x80 + 1, { { t, i, r } }) }))
        assert.are.equal("sealed", (kindOfModId(char, nId .. "_" .. nTier)))
    end)

    it("tags index 0 as corrupted when bit6 is set and there is no sealed-regular affix", function()
        local t, i, r = affixBytes(nId, nTier, 128)
        -- 0x40 | count 1
        local char = importItems(makeSave({ equipItem(0x40 + 1, { { t, i, r } }) }))
        assert.are.equal("corrupted", (kindOfModId(char, nId .. "_" .. nTier)))
    end)

    it("tags a tier-7 affix as primordial", function()
        local t, i, r = affixBytes(pId, 7, 128)
        local char = importItems(makeSave({ equipItem(1, { { t, i, r } }) }))
        assert.are.equal("primordial", (kindOfModId(char, pId .. "_7")))
    end)

    -- The positional rule: with a sealed-regular affix present the corrupted slot
    -- shifts from index 0 to index 1.
    it("places sealed at index 0 and corrupted at index 1 when BOTH bits are set", function()
        local t0, i0, r0 = affixBytes(nId, 0, 128)
        local t1, i1, r1 = affixBytes(nId, 1, 128)
        local t2, i2, r2 = affixBytes(nId, 2, 128)
        -- 0x80 | 0x40 | count 3
        local char = importItems(makeSave({
            equipItem(0x80 + 0x40 + 3, { { t0, i0, r0 }, { t1, i1, r1 }, { t2, i2, r2 } }),
        }))
        assert.are.equal("sealed", (kindOfModId(char, nId .. "_0")))
        assert.are.equal("corrupted", (kindOfModId(char, nId .. "_1")))
        assert.is_nil((kindOfModId(char, nId .. "_2")))
    end)

    -- loadAffixFromSerialisation tests corruption BEFORE tier==7.
    it("prefers corrupted over primordial when the corrupted slot affix is itself tier 7", function()
        local t, i, r = affixBytes(pId, 7, 128)
        -- 0x40 | count 1 -> index 0 is the corrupted slot AND is tier 7.
        local char = importItems(makeSave({ equipItem(0x40 + 1, { { t, i, r } }) }))
        assert.are.equal("corrupted", (kindOfModId(char, pId .. "_7")))
    end)

    -- Slots past the serialised count are trailing Omen/Woven payload, never real
    -- affixes, so they must never be tagged.
    it("does not tag a slot beyond the serialised affix count", function()
        local t0, i0, r0 = affixBytes(nId, 0, 128)
        local t1, i1, r1 = affixBytes(nId, 1, 128)
        -- 0x80 set but count 0: nothing is in range, so nothing may be tagged.
        local char = importItems(makeSave({
            equipItem(0x80 + 0, { { t0, i0, r0 }, { t1, i1, r1 } }),
        }))
        for _, a in ipairs(affixesOf(char)) do
            assert.is_nil(a.kind)
        end
    end)

    -- The calc consequence. The decoder emits `kind`; Item.lua's
    -- computeAffixDerivedLevelReq then gates on `not affix.kind`, mirroring LE's
    -- ItemAffix.CanContributeToLevelRequirement (`specialAffixType == 0 &&
    -- sealedAffixType == 0`, datamined game source). This pins the end of that chain:
    -- the SAME high-tier affix must stop inflating req.level once it is tagged
    -- sealed -- which is exactly what a save-imported sealed affix could not do
    -- while every save affix had kind=nil.
    it("a sealed affix does not inflate the affix-derived req.level", function()
        local function reqLevelWithKind(kind)
            local item = new("Item", "", "RARE")
            item.crafted = true
            item.title = "Test Body"
            item.baseName = "Refuge Armor"
            item.prefixes = { { modId = nId .. "_5", range = 100, kind = kind } }
            item.suffixes = {}
            item:ParseRaw(item:BuildRaw())
            return item.requirements and item.requirements.level
        end
        local normalReq = reqLevelWithKind(nil)
        local sealedReq = reqLevelWithKind("sealed")
        assert.is_truthy(normalReq, "an untagged high-tier affix should derive a req.level")
        -- Untagged (normal) contributes; sealed must not, so sealed < normal.
        assert.is_true((sealedReq or 0) < normalReq,
            ("sealed req.level %s must be below untagged %s"):format(
                tostring(sealedReq), tostring(normalReq)))
    end)

    -- End-to-end: the decoder is what supplies that kind for a save import.
    it("supplies the sealed kind end-to-end from the save bytes", function()
        local t, i, r = affixBytes(nId, 5, 128)
        local sealed = importItems(makeSave({ equipItem(0x80 + 1, { { t, i, r } }) }))
        local normal = importItems(makeSave({ equipItem(1, { { t, i, r } }) }))
        assert.are.equal("sealed", (kindOfModId(sealed, nId .. "_5")))
        assert.is_nil((kindOfModId(normal, nId .. "_5")))
    end)
end)
