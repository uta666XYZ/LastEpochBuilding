-- @leb-regression-guard: letools-quest-reward-from-completed-quests
-- Locks the contract for ImportTabClass:DetectLEToolsQuestRewards:
--   * Apophis and Majasa = quest id 124 in data.completedQuests
--   * Temple of Eterra   = quest id 151 in data.completedQuests
--   * Both flags must be derived FROM the JSON, never hardcoded.
--
-- Regression history this guard prevents:
--   * Hardcoding both ON  → +1..+2 over-shoot for 0/2 and 1/2 builds
--   * Hardcoding both OFF → -1..-2 under-shoot for 1/2 and 2/2 builds
--     (empirically observed across 36/38 G1 ATTR_UNIFORM_OTHER builds with
--     uniform Δ=-2 across all 5 attributes; all had {124,151} ⊂ completedQuests).
--
-- See REGRESSION_GUARDS.md "letools-quest-reward-from-completed-quests".

describe("LEToolsQuestImport", function()
    local ImportTab

    before_each(function()
        newBuild()
        ImportTab = build.importTab
    end)

    it("returns false,false when completedQuests is nil/missing", function()
        local a, e = ImportTab:DetectLEToolsQuestRewards({})
        assert.is_false(a)
        assert.is_false(e)
        local a2, e2 = ImportTab:DetectLEToolsQuestRewards({ completedQuests = nil })
        assert.is_false(a2)
        assert.is_false(e2)
    end)

    it("returns false,false when completedQuests is empty", function()
        local a, e = ImportTab:DetectLEToolsQuestRewards({ completedQuests = {} })
        assert.is_false(a)
        assert.is_false(e)
    end)

    it("detects Apophis (124) only", function()
        local a, e = ImportTab:DetectLEToolsQuestRewards({
            completedQuests = { 1, 49, 94, 124 },
        })
        assert.is_true(a)
        assert.is_false(e)
    end)

    it("detects Eterra (151) only", function()
        local a, e = ImportTab:DetectLEToolsQuestRewards({
            completedQuests = { 1, 49, 151 },
        })
        assert.is_false(a)
        assert.is_true(e)
    end)

    it("detects both Apophis (124) and Eterra (151)", function()
        local a, e = ImportTab:DetectLEToolsQuestRewards({
            completedQuests = { 1, 3, 9, 124, 128, 129, 151, 158, 159 },
        })
        assert.is_true(a)
        assert.is_true(e)
    end)

    it("ignores other quest IDs even when many are present", function()
        local a, e = ImportTab:DetectLEToolsQuestRewards({
            completedQuests = { 1, 3, 9, 20, 24, 30, 32, 35, 36, 37, 39, 45,
                                49, 57, 58, 94, 97, 117, 119, 120, 121, 128,
                                129, 158, 159 },
        })
        assert.is_false(a)
        assert.is_false(e)
    end)

    it("does not match string '124' or '151' (numeric ID only)", function()
        local a, e = ImportTab:DetectLEToolsQuestRewards({
            completedQuests = { "124", "151" },
        })
        assert.is_false(a)
        assert.is_false(e)
    end)
end)
