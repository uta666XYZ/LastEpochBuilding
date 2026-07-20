-- @leb-regression-guard:import-ww-idol-affix-overimport
-- Sibling of import-idol-affix-namespace-phantom. That guard reclassifies a
-- sub-ceiling non-idol-namespace decode on a grid idol (containerID 29) as a
-- phantom over-read -- but ONLY fired when the decode missed itemMods.Item
-- (modData == nil). This guard closes the CALC-AFFECTING hole: when a Weaver's-
-- Will / Omen idol's trailing payload byte decodes to an affixId that is BOTH
-- <= the registry ceiling AND a REAL entry in itemMods.Item at a valid tier, the
-- `if modData` branch imported it as a genuine idol affix -- silently inflating
-- build power. Observed on the Hammerdin SUNDAY build: its WW idols yielded
-- 32 (Fire Penetration) / 71 (Minion Dodge) / 78 (Melee Cold Damage) at tier 0,
-- all valid EQUIPMENT affixes, wrongly added to the idol.
--
-- The fix gates the import branch on the same idol-namespace check, so a cid29
-- non-idol-pool affix is reclassified as [IMPORT-OVERREAD] whether or not it
-- resolves in itemMods.Item. Genuine idol affixes are all in the idol pool
-- (LEB grid-idol pool == datamine single+multi idol affixes minus the 20
-- altar-only 1088-1109), so a real idol affix is never rejected.
--
-- See REGRESSION_GUARDS.md "import-ww-idol-affix-overimport". Item bytes below
-- are SYNTHETIC minimal serialisation-v5 records; every affix id / tier / ceiling
-- is read from the LIVE mod data so the test is dataset-agnostic.

local dkjson = require "dkjson"

-- Encode one 3-byte affix record so the parser decodes it back to (affixId,
-- tier): affixId = idByte + (tierByte % 16) * 256 ; tier = floor(tierByte / 16).
local function affixBytes(affixId, tier, range)
    local hi = math.floor(affixId / 256)
    local lo = affixId % 256
    return tier * 16 + hi, lo, (range or 128)
end

-- Equipment record: containerID 3, base 1/4 (Banded Armor).
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

-- Grid-idol record: containerID 29, base 26/1 (Minor Weaver Idol).
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
        characterName = "ImportWWIdolOverimportFixture",
        level = 100,
        savedCharacterTree = { nodeIDs = {}, nodePoints = {} },
        savedSkillTrees = {},
        savedQuests = {},
        savedItems = items,
    }
end

-- Live facts (no hard-coded ids): an in-pool idol affix present at a real tier,
-- and an equipment-only affix present at a real tier (the 32/71/78 signature:
-- <=ceiling, in itemMods.Item, NOT an idol-pool member).
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

local function importCounts(save)
    local char = build.importTab:ReadJsonSaveData(dkjson.encode(save))
    local imported = 0
    for _, it in ipairs(char.items or {}) do
        imported = imported + #(it.prefixes or {}) + #(it.suffixes or {})
    end
    return char._droppedAffixes or 0, imported, char
end

describe("ImportWWIdolAffixOverimport", function()
    local pool, ceiling, idolId, idolTier, eqId, eqTier
    before_each(function()
        newBuild()
        pool, ceiling, idolId, idolTier, eqId, eqTier = liveIdolFacts()
    end)

    it("has a live equipment-only affix that IS in itemMods.Item at a real tier", function()
        assert.is_truthy(eqId, "no live equipment-only affixId < 500 found")
        assert.is_true(eqId <= ceiling, "control id must be <= ceiling")
        assert.is_falsy(pool[eqId], "control id must NOT be an idol-pool member")
        assert.is_truthy(eqTier, "control id must resolve at a real tier (modData non-nil)")
    end)

    -- THE FIX: without it, this equipment affix (valid modData) is imported onto
    -- the idol. With it, the namespace gate rejects it as a phantom over-read.
    it("does NOT import an equipment-namespace affix (real tier) that lands on a grid idol", function()
        local tb, ib, rb = affixBytes(eqId, eqTier, 128)
        local dropped, imported = importCounts(makeSave({ idolItem({ { tb, ib, rb } }) }))
        assert.are.equal(0, imported)   -- reclassified as over-read, not imported
        assert.are.equal(0, dropped)    -- and not counted as a dropped affix
    end)

    -- Regression: the SAME affix on EQUIPMENT (container 3) must still import --
    -- the namespace gate is scoped to grid idols only.
    it("STILL imports the same equipment affix normally on an equipment item", function()
        local tb, ib, rb = affixBytes(eqId, eqTier, 128)
        local dropped, imported = importCounts(makeSave({ equipItem({ { tb, ib, rb } }) }))
        assert.are.equal(1, imported)
        assert.are.equal(0, dropped)
    end)

    -- Regression: a genuine in-pool idol affix at a real tier is untouched.
    it("STILL imports a genuine in-pool idol affix on a grid idol", function()
        assert.is_truthy(idolId, "no live in-pool idol affixId < 500 found")
        local tb, ib, rb = affixBytes(idolId, idolTier, 128)
        local dropped, imported = importCounts(makeSave({ idolItem({ { tb, ib, rb } }) }))
        assert.are.equal(1, imported)
        assert.are.equal(0, dropped)
    end)

    -- Mixed idol: a real idol affix beside an equipment-namespace payload byte.
    -- The real one imports (exactly 1); the phantom is neither imported nor dropped.
    it("imports only the real idol affix when a WW payload byte sits beside it", function()
        assert.is_truthy(idolId, "no live in-pool idol affixId < 500 found")
        local vtb, vib, vrb = affixBytes(idolId, idolTier, 128)   -- slot0: real idol affix
        local ptb, pib, prb = affixBytes(eqId, eqTier, 209)       -- slot1: equipment payload (valid modData)
        local dropped, imported = importCounts(makeSave({ idolItem({ { vtb, vib, vrb }, { ptb, pib, prb } }) }))
        assert.are.equal(1, imported)
        assert.are.equal(0, dropped)
    end)
end)
