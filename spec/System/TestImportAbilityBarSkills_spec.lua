-- @leb-regression-guard:import-abilitybar-unspecialized-skills
-- See REGRESSION_GUARDS.md "import-abilitybar-unspecialized-skills".
-- Validation provenance is retained in maintainer notes.

local dkjson = require "dkjson"

-- Faithful Prepfor1o1 shape. Rogue = classId 4; Bladedancer = mastery 1
-- (ascendancies are 1-indexed: 1=Bladedancer, 2=Marksman, 3=Falconer).
-- savedSkillTrees carries a couple of allocated nodes each so we can assert the
-- specialization nodes survive unchanged.
local function makeSave()
    return {
        characterClass = 4,
        chosenMastery = 1,
        characterName = "AbilityBarFixture",
        level = 44,
        cycle = 0,
        savedCharacterTree = { nodeIDs = {}, nodePoints = {} },
        savedQuests = {},
        savedItems = {},
        savedSkillTrees = {
            -- both of these are ALSO on the bar (the double-count guard targets)
            { treeID = "aacfl", slotNumber = 1, nodeIDs = { 2 }, nodePoints = { 3 } }, -- Acid Flask
            { treeID = "sh4re", slotNumber = 2, nodeIDs = { 5 }, nodePoints = { 2 } }, -- Shadow Rend
            -- specialized but NOT barred (inverse case; must stay imported)
            { treeID = "ub5d9", slotNumber = 3, nodeIDs = { 7 }, nodePoints = { 4 } }, -- Umbral Blades
            { treeID = "bl5st", slotNumber = 4, nodeIDs = { 3 }, nodePoints = { 1 } }, -- Bladestorm Throw
        },
        -- the five EQUIPPED skills; pun22/shiif/deeco have no savedSkillTrees entry
        abilityBar = { "pun22", "shiif", "deeco", "sh4re", "aacfl" },
    }
end

local function abilityCounts(char)
    local counts = {}
    for _, name in ipairs(char.abilities) do
        counts[name] = (counts[name] or 0) + 1
    end
    return counts
end

describe("ImportAbilityBarSkills", function()
    local char, counts
    before_each(function()
        newBuild()
        char = build.importTab:ReadJsonSaveData(dkjson.encode(makeSave()))
        counts = abilityCounts(char)
    end)

    it("imports bar-only (unspecialized) skills that have no savedSkillTrees entry", function()
        assert.are.equal(1, counts["Puncture"] or 0)
        assert.are.equal(1, counts["Shift"] or 0)
        assert.are.equal(1, counts["Decoy"] or 0)
    end)

    it("still imports specialized skills (no regression on the savedSkillTrees path)", function()
        assert.is_true((counts["AcidFlask"] or 0) >= 1)
        assert.is_true((counts["ShadowRend"] or 0) >= 1)
        assert.is_true((counts["Umbral Blades 1"] or 0) >= 1)
        assert.is_true((counts["Bladestorm Throw"] or 0) >= 1)
    end)

    it("does not double-count a skill that is both barred and specialized", function()
        assert.are.equal(1, counts["AcidFlask"])  -- in abilityBar AND savedSkillTrees
        assert.are.equal(1, counts["ShadowRend"]) -- in abilityBar AND savedSkillTrees
    end)

    it("imports exactly the union of barred and specialized skills (6 distinct)", function()
        -- {Puncture, Shift, Decoy, AcidFlask, ShadowRend, Umbral Blades, Bladestorm}
        -- = 3 bar-only + 2 in-both + 2 specced-only = 7 entries, no duplicates.
        assert.are.equal(7, #char.abilities)
    end)

    it("preserves specialization tree nodes and adds a root hash for bar-only skills", function()
        local hashStr = table.concat(char.hashes, ",")
        -- specialization node from savedSkillTrees survives untouched
        assert.is_truthy(hashStr:find("aacfl%-2#3", 1), "Acid Flask specialization node aacfl-2#3 missing")
        -- bar-only skill gets its root node so the skill tree resolves
        assert.is_truthy(hashStr:find("pun22%-0#1", 1), "Puncture root hash pun22-0#1 missing")
        -- bar-only skills carry NO allocated tree nodes (base skill only)
        assert.is_nil(hashStr:find("pun22%-[1-9]"), "Puncture should have no allocated tree nodes")
    end)

    it("creates a usable Puncture socket group through the full import path", function()
        build.importTab:ImportPassiveTreeAndJewels(char)
        local bySkillId = {}
        for _, sg in pairs(build.skillsTab.socketGroupList) do
            local id = sg.skillId or (sg.grantedEffect and sg.grantedEffect.name)
            if id then bySkillId[id] = true end
        end
        assert.is_true(bySkillId["Puncture"] == true, "bar-only Puncture socket group not created")
        assert.is_true(bySkillId["AcidFlask"] == true, "specialized AcidFlask socket group not created")
    end)
end)

-- Guard the opposite extreme: a fully-specialized character (every barred skill
-- also has a savedSkillTrees entry, the high-level common case) must import each
-- skill exactly once -- the abilityBar pass must add nothing here.
describe("ImportAbilityBarSkills (all barred skills specialized)", function()
    local function makeAllSpecced()
        return {
            characterClass = 4,
            chosenMastery = 1,
            characterName = "AllSpeccedFixture",
            level = 90,
            cycle = 0,
            savedCharacterTree = { nodeIDs = {}, nodePoints = {} },
            savedQuests = {},
            savedItems = {},
            savedSkillTrees = {
                { treeID = "aacfl", slotNumber = 1, nodeIDs = { 2 }, nodePoints = { 3 } },
                { treeID = "sh4re", slotNumber = 2, nodeIDs = { 5 }, nodePoints = { 2 } },
            },
            abilityBar = { "aacfl", "sh4re" }, -- both already specialized
        }
    end

    it("imports each skill exactly once (abilityBar pass is a no-op)", function()
        newBuild()
        local char = build.importTab:ReadJsonSaveData(dkjson.encode(makeAllSpecced()))
        local counts = abilityCounts(char)
        assert.are.equal(1, counts["AcidFlask"])
        assert.are.equal(1, counts["ShadowRend"])
        assert.are.equal(2, #char.abilities)
    end)
end)
