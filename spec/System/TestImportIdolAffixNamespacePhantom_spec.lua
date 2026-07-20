-- @leb-regression-guard:import-idol-affix-namespace-phantom
-- Companion to import-affix-id-ceiling-phantom. Locks the contract that the
-- offline-save binary item parser (ImportTabClass:ReadJsonSaveData, non-unique
-- affix-loop path, src/Classes/ImportTab.lua) classifies a SUB-ceiling decoded
-- affixId that lands on a GRID IDOL (containerID 29) but is NOT a member of the
-- idol-affix namespace as a phantom over-read of trailing Woven/Omen payload --
-- NOT as a "dropped affix" -- so it is not counted in char._droppedAffixes.
--
-- Background: an idol's trailing "omen"/Woven bytes can decode to an equipment
-- affix id <= the registry ceiling (1112) yet impossible on an idol. Observed on
-- the Golem ACG-3 Minor Weaver Idols: affixId 597 ("Mage Level of Shatter
-- Strike", tier 9) and 545 ("Primalist Level of Summon Frenzy Totem", tier 12)
-- -- class-specific *+Level of Skill* EQUIPMENT ids. They miss itemMods.Item at
-- their impossible tiers so they fell to the else-branch and were counted as
-- genuine "[IMPORT-DROP]" affixes, inflating the "N affix(es) dropped" message
-- exactly like the >ceiling phantoms. The fix builds the idol-affix id-set from
-- LEB's own idol mod data (the per-idol-base tables under data.itemMods) and, for
-- container-29 idols only, reclassifies a <=ceiling non-idol-namespace decode as
-- [IMPORT-OVERREAD]. Datamine cross-check: LEB's grid-idol id-set equals the
-- datamined game source single+multi idol-affix pool exactly, minus the 20 "Idol Altar"
-- affixes (1088-1109) which roll only on the Idol Altar (container 123) -- hence
-- the container-29 gate (equipment legitimately carries 545/597; altars
-- legitimately carry 1088-1109; neither must be rejected).
--
-- See REGRESSION_GUARDS.md "import-idol-affix-namespace-phantom". Item bytes below
-- are SYNTHETIC minimal serialisation-v5 records; every affix id / tier / ceiling
-- is read from the LIVE mod data so the test is dataset-agnostic.

local dkjson = require "dkjson"

-- Encode one 3-byte affix record so the parser decodes it back to (affixId,
-- tier): the loop computes affixId = idByte + (tierByte % 16) * 256 ;
-- tier = floor(tierByte / 16).
local function affixBytes(affixId, tier, range)
    local hi = math.floor(affixId / 256)
    local lo = affixId % 256
    return tier * 16 + hi, lo, (range or 128)
end

-- A non-unique body-armour record (baseType 1 / subType 4 = Banded Armor) on
-- containerID 3 (equipment). Layout: d[1]=version 5, d[2..3]=seed, d[4..5]=
-- base/subType, d[6]=rarity, d[7..12]=header, d[13..]=affix records.
-- d[12] (BASE+8) low 6 bits = the serialised affix count that bounds the import
-- loop (@leb-regression-guard:import-nonunique-affix-count); set it from the record
-- count, matching the game's serialiser (`id[11] = affixes.Count | flags`), so the
-- fixture stays a realizable save and the loop actually reaches these slots.
local function equipItem(affixRecords)
    local d = { 5, 0, 0, 1, 4, 2, 128, 128, 128, 0, 0, #affixRecords }
    for _, rec in ipairs(affixRecords) do
        d[#d + 1] = rec[1]; d[#d + 1] = rec[2]; d[#d + 1] = rec[3]
    end
    return { containerID = 3, data = d }
end

-- A grid-idol record: containerID 29, base 26/1 = Minor Weaver Idol (the exact
-- ACG-3 Golem case). inventoryPosition is required by the container-29 path.
local function idolItem(affixRecords)
    local d = { 5, 0, 0, 26, 1, 2, 128, 128, 128, 0, 0, #affixRecords }
    for _, rec in ipairs(affixRecords) do
        d[#d + 1] = rec[1]; d[#d + 1] = rec[2]; d[#d + 1] = rec[3]
    end
    return { containerID = 29, inventoryPosition = { x = 0, y = 0 }, data = d }
end

local function makeSave(items)
    return {
        characterClass = 3,
        chosenMastery = 2,
        characterName = "ImportIdolNamespaceFixture",
        level = 100,
        savedCharacterTree = { nodeIDs = {}, nodePoints = {} },
        savedSkillTrees = {},
        savedQuests = {},
        savedItems = items,
    }
end

-- Read live facts straight from the loaded data so the fixture hard-codes no ids:
--   ceiling   : registry max affixId (data.itemMods.Item)
--   idolId    : an affixId that IS an idol-pool member and present in itemMods.Item
--   eqId      : an affixId present in itemMods.Item that is NOT an idol-pool member
--               (an equipment-only id -- the 545/597 signature)
local function liveIdolFacts()
    local pool = {}
    for _, idolType in ipairs({
        "Small Idol", "Minor Idol", "Humble Idol", "Stout Idol",
        "Grand Idol", "Large Idol", "Adorned Idol", "Ornate Idol", "Huge Idol",
    }) do
        local t = data.itemMods[idolType]
        if type(t) == "table" then
            for modId in pairs(t) do
                local id = tonumber(tostring(modId):match("^(%d+)_"))
                if id then pool[id] = true end
            end
        end
    end
    local ceiling = 0
    local idolId, idolTier, eqId, eqTier
    for modId in pairs(data.itemMods.Item) do
        local idStr, tierStr = tostring(modId):match("^(%d+)_(%d+)$")
        local id = idStr and tonumber(idStr)
        local tier = tierStr and tonumber(tierStr)
        if id then
            if id > ceiling then ceiling = id end
            if id > 0 and id < 500 and tier and tier <= 7 then
                if pool[id] and not idolId then idolId, idolTier = id, tier end
                if (not pool[id]) and not eqId then eqId, eqTier = id, tier end
            end
        end
    end
    return pool, ceiling, idolId, idolTier, eqId, eqTier
end

local function droppedFor(save)
    local char = build.importTab:ReadJsonSaveData(dkjson.encode(save))
    return char._droppedAffixes or 0, char
end

describe("ImportIdolAffixNamespacePhantom", function()
    local pool, ceiling, idolId, idolTier, eqId, eqTier
    before_each(function()
        newBuild()
        pool, ceiling, idolId, idolTier, eqId, eqTier = liveIdolFacts()
    end)

    it("builds a non-empty idol-affix pool that is a strict subset of the registry", function()
        assert.is_truthy(next(pool), "idol-affix pool is empty")
        -- 545 / 597 (the captured Golem payload ids) are equipment ids, NOT idol affixes.
        assert.is_falsy(pool[545])
        assert.is_falsy(pool[597])
    end)

    it("(a) imports a real in-pool idol affix normally (0 dropped)", function()
        assert.is_truthy(idolId, "no live in-pool idol affixId < 500 found")
        local tb, ib, rb = affixBytes(idolId, idolTier, 128)
        local dropped, char = droppedFor(makeSave({ idolItem({ { tb, ib, rb } }) }))
        assert.are.equal(0, dropped)
        local total = 0
        for _, it in ipairs(char.items) do
            total = total + #(it.prefixes or {}) + #(it.suffixes or {})
        end
        assert.is_true(total >= 1, "the valid in-pool idol affix was not imported")
    end)

    it("(a) STILL counts a genuine in-pool idol affix missing at its decoded tier as a drop", function()
        assert.is_truthy(idolId, "no live in-pool idol affixId < 500 found")
        -- In-pool id with an impossible tier (15): absent from itemMods.Item but
        -- the affixId IS an idol-namespace member => a genuine possible data gap.
        local tb, ib, rb = affixBytes(idolId, 15, 128)
        local dropped = droppedFor(makeSave({ idolItem({ { tb, ib, rb } }) }))
        assert.are.equal(1, dropped)
    end)

    it("(c) reclassifies a sub-ceiling non-idol-namespace decode on an IDOL as over-read (not counted)", function()
        assert.is_truthy(eqId, "no live equipment-only affixId < 500 found")
        assert.is_true(eqId <= ceiling, "control id must be <= ceiling")
        assert.is_falsy(pool[eqId], "control id must NOT be an idol-pool member")
        -- Impossible tier (15) so it misses itemMods.Item and reaches the branch.
        local tb, ib, rb = affixBytes(eqId, 15, 128)
        local dropped = droppedFor(makeSave({ idolItem({ { tb, ib, rb } }) }))
        assert.are.equal(0, dropped)
    end)

    it("(b) an EQUIPMENT affix (eqId at a real tier) imports normally on an equipment item", function()
        assert.is_truthy(eqId, "no live equipment-only affixId < 500 found")
        local tb, ib, rb = affixBytes(eqId, eqTier, 128)
        local dropped, char = droppedFor(makeSave({ equipItem({ { tb, ib, rb } }) }))
        assert.are.equal(0, dropped)
        local total = 0
        for _, it in ipairs(char.items) do
            total = total + #(it.prefixes or {}) + #(it.suffixes or {})
        end
        assert.is_true(total >= 1, "the valid equipment affix was not imported")
    end)

    it("(b) the idol namespace gate does NOT apply to equipment: eqId missing at its tier still DROPs", function()
        assert.is_truthy(eqId, "no live equipment-only affixId < 500 found")
        -- Same non-idol id + impossible tier, but on an EQUIPMENT item (container 3):
        -- the container-29 gate must not fire, so it stays a counted [IMPORT-DROP].
        local tb, ib, rb = affixBytes(eqId, 15, 128)
        local dropped = droppedFor(makeSave({ equipItem({ { tb, ib, rb } }) }))
        assert.are.equal(1, dropped)
    end)

    it("(d) preserves the >ceiling phantom behavior on an idol (over-read, not counted)", function()
        -- 1822 > 1112 ceiling = the captured Xiemiel Omen Idol over-read.
        local tb, ib, rb = affixBytes(1822, 1, 8)
        local dropped = droppedFor(makeSave({ idolItem({ { tb, ib, rb } }) }))
        assert.are.equal(0, dropped)
    end)

    it("mixes a real in-pool affix + a payload mis-read on one idol: real imports, phantom not counted", function()
        assert.is_truthy(idolId, "no live in-pool idol affixId < 500 found")
        assert.is_truthy(eqId, "no live equipment-only affixId < 500 found")
        local vtb, vib, vrb = affixBytes(idolId, idolTier, 128)  -- slot0: real idol affix
        local ptb, pib, prb = affixBytes(eqId, 15, 209)          -- slot1: non-idol payload mis-read
        local dropped, char = droppedFor(makeSave({ idolItem({ { vtb, vib, vrb }, { ptb, pib, prb } }) }))
        assert.are.equal(0, dropped)
        local total = 0
        for _, it in ipairs(char.items) do
            total = total + #(it.prefixes or {}) + #(it.suffixes or {})
        end
        assert.is_true(total >= 1, "the real idol affix beside a phantom was not imported")
    end)
end)
