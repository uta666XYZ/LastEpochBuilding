-- @leb-regression-guard: quest-reward-requires-completion
-- Locks the contract for ImportTabClass:DetectSaveQuestRewards (offline-save
-- decode path). The save's `savedQuests` is a list of quest PROGRESS records,
-- not completed quests; the +1-to-all-attributes reward (Apophis and Majasa =
-- 124, Temple of Eterra = 151) is granted ONLY when the quest reaches its
-- terminal step (questStepID 124->656, 151->830). Mere presence of the questID
-- is not enough.
--
-- Regression history this guard prevents:
--   * Presence-based detection (any questID 124/151 present => reward) wrongly
--     granted +1 to all five attributes for ImPalmBeachPete (lv48), whose quest
--     124 was at questStepID=652 (in-progress) and 151 absent. In-game grants
--     NEITHER reward; the over-shoot inflated Health 992->998 and Mana 195->197.
--   * Completed builds ShutFackUp (lv85) and ZombieWarehouse (lv72) have
--     124@656 + 151@830 and must still receive +1 from each (+2 total).
-- The per-step `state` field is always 0 across every observed save, so it
-- cannot be used as the completion signal; the terminal questStepID can.
--
-- See REGRESSION_GUARDS.md "quest-reward-requires-completion".

describe("SaveQuestRewardCompletion", function()
    local ImportTab

    before_each(function()
        newBuild()
        ImportTab = build.importTab
    end)

    it("returns false,false when savedQuests is nil/empty", function()
        local a, e = ImportTab:DetectSaveQuestRewards(nil)
        assert.is_false(a)
        assert.is_false(e)
        local a2, e2 = ImportTab:DetectSaveQuestRewards({})
        assert.is_false(a2)
        assert.is_false(e2)
    end)

    it("does NOT grant the reward for an in-progress quest 124 (Pete lv48)", function()
        -- ImPalmBeachPete: quest 124 stuck at step 652, quest 151 absent.
        local a, e = ImportTab:DetectSaveQuestRewards({
            { questID = 124, questStepID = 652, state = 0 },
        })
        assert.is_false(a)
        assert.is_false(e)
    end)

    it("grants Apophis (124) only when at terminal step 656", function()
        local a, e = ImportTab:DetectSaveQuestRewards({
            { questID = 124, questStepID = 656, state = 0 },
        })
        assert.is_true(a)
        assert.is_false(e)
    end)

    it("grants Eterra (151) only when at terminal step 830", function()
        local a, e = ImportTab:DetectSaveQuestRewards({
            { questID = 151, questStepID = 830, state = 0 },
        })
        assert.is_false(a)
        assert.is_true(e)
    end)

    it("grants both for a fully-completed save (ShutFackUp / ZombieWarehouse)", function()
        local a, e = ImportTab:DetectSaveQuestRewards({
            { questID = 124, questStepID = 656, state = 0 },
            { questID = 151, questStepID = 830, state = 0 },
            { questID = 1,   questStepID = 5,   state = 0 },
        })
        assert.is_true(a)
        assert.is_true(e)
    end)

    it("does NOT grant Eterra when 151 is present but pre-terminal", function()
        local a, e = ImportTab:DetectSaveQuestRewards({
            { questID = 124, questStepID = 656, state = 0 },
            { questID = 151, questStepID = 820, state = 0 },
        })
        assert.is_true(a)
        assert.is_false(e)
    end)

    it("ignores unrelated quest IDs even at high step numbers", function()
        local a, e = ImportTab:DetectSaveQuestRewards({
            { questID = 100, questStepID = 656, state = 0 },
            { questID = 200, questStepID = 830, state = 0 },
        })
        assert.is_false(a)
        assert.is_false(e)
    end)
end)
