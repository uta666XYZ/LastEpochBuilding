-- @leb-regression-guard: conditional-recent-action-stat-recognition
-- Locks the ModParser specialModList catch-all for
-- "+N <stat> if you have <action> recently" so it DECLINES (returns nil
-- and falls through to the generic parse chain) whenever BOTH the stat
-- name resolves through modNameList AND the condition phrase
-- re-resolves through modTagList. Before this guard the catch-all
-- emitted nsAny(num) → LEB_NotSupported even for combinations the
-- generic parser was perfectly capable of handling, causing silent
-- under-counting on corrupted-sealed affixes that pair a known defence
-- stat with a known "BeenHitRecently" / "CritRecently" / etc. tag.
--
-- Evidence: Q9J4w8PE Necromancer's Julra's Obsession gloves carry a
-- corrupted prefix "+(301-400) Endurance Threshold if you have not
-- been Hit Recently" (range 11 → 305). Pre-fix the parser produced a
-- single LEB_NotSupported BASE 305 mod that CalcDefence ignored,
-- producing the LEB-vs-LET EnduranceThreshold -316 diff. Post-fix the
-- parser produces EnduranceThreshold BASE 305 tagged with
-- Condition:BeenHitRecently(neg) — active by default per the
-- conditionBeenHitRecently Config toggle (off → neg mods active).
--
-- See REGRESSION_GUARDS.md entry
-- `conditional-recent-action-stat-recognition` for the full chain.

local parseMod = LoadModule("Modules/ModParser")

local function parseFresh(line)
    -- ModCache.lua may pin pre-fix LEB_NotSupported entries; clear before assert.
    local _, cache = LoadModule("Modules/ModParser")
    cache[line] = nil
    return parseMod(line)
end

local function findCondition(mods, var, neg)
    if type(mods) ~= "table" then return nil end
    for _, m in ipairs(mods) do
        for _, tag in ipairs(m) do
            if tag.type == "Condition" and tag.var == var and (not not tag.neg) == (not not neg) then
                return m
            end
        end
    end
    return nil
end

describe("ConditionalRecentActionStatRecognition", function()
    it("'+305 Endurance Threshold if you have not been Hit Recently' parses to EnduranceThreshold + BeenHitRecently(neg)", function()
        local mods = parseFresh("+305 Endurance Threshold if you have not been Hit Recently")
        assert.is_truthy(mods)
        assert.is_true(#mods >= 1)
        assert.are.equal("EnduranceThreshold", mods[1].name)
        assert.are.equal("BASE", mods[1].type)
        assert.are.equal(305, mods[1].value)
        assert.is_truthy(findCondition(mods, "BeenHitRecently", true),
            "must carry Condition:BeenHitRecently(neg) tag (not LEB_NotSupported)")
    end)

    it("'+305 Endurance Threshold if you have been Hit Recently' parses to EnduranceThreshold + BeenHitRecently(affirmative)", function()
        local mods = parseFresh("+305 Endurance Threshold if you have been Hit Recently")
        assert.is_truthy(mods)
        assert.are.equal("EnduranceThreshold", mods[1].name)
        assert.is_truthy(findCondition(mods, "BeenHitRecently", false))
    end)

    it("'+10 Dodge Rating if you have been hit recently' parses to Evasion + BeenHitRecently", function()
        local mods = parseFresh("+10 Dodge Rating if you have been hit recently")
        assert.is_truthy(mods)
        assert.are.equal("Evasion", mods[1].name)
        assert.is_truthy(findCondition(mods, "BeenHitRecently", false))
    end)

    it("'+10 Armour if you have not been Hit Recently' parses to Armour + BeenHitRecently(neg)", function()
        local mods = parseFresh("+10 Armour if you have not been Hit Recently")
        assert.is_truthy(mods)
        assert.are.equal("Armour", mods[1].name)
        assert.is_truthy(findCondition(mods, "BeenHitRecently", true))
    end)

    it("UNKNOWN stat × KNOWN condition still falls through to LEB_NotSupported (recognition-only)", function()
        -- "Floozle" is not in modNameList; the catch-all must still nsAny it
        local mods = parseFresh("+5 Floozle if you have been Hit Recently")
        assert.is_truthy(mods)
        assert.are.equal("LEB_NotSupported", mods[1].name)
    end)

    it("KNOWN stat × UNKNOWN condition still falls through to LEB_NotSupported (recognition-only)", function()
        -- "eaten a sandwich" is not in modTagList — must stay nsAny
        local mods = parseFresh("+5 Endurance if you have eaten a sandwich recently")
        assert.is_truthy(mods)
        assert.are.equal("LEB_NotSupported", mods[1].name)
    end)
end)
