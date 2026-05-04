-- @leb-regression-guard: set-bonus-breakdown-publish
-- @leb-regression-guard: set-bonus-breakdown-bridge
-- Locks the data contract between CalcSetup.applySetBonuses and the
-- Calcs-tab "Set Bonuses" UI section. If either guard regresses, the
-- section silently vanishes without any numeric calc divergence; this
-- spec is the only tripwire for that failure mode.
-- See REGRESSION_GUARDS.md "set-bonus-breakdown-publish".

describe("TestSetBreakdown", function()
    local calcs

    before_each(function()
        newBuild()
        calcs = build.calcsTab.calcs
    end)

    -- Kuzon's Set (setId=4) is a real 2-piece set in src/Data/Set/set_1_4.json
    -- so setSize lookup populates correctly. The bonus tier-2 text is just
    -- a flavor passthrough; the spec doesn't assert exact wording so balance
    -- updates to set_1_4.json don't break this test.
    local KUZON_SET_ID = 4

    local function fakeSetItem(bonusText)
        return {
            rarity = "SET",
            title = "Kuzon's fake item",
            setInfo = {
                setId = KUZON_SET_ID,
                name = "Kuzon's Set",
                bonus = { ["2"] = bonusText or "+10 Health" },
            },
        }
    end

    it("publishes empty-friendly state when no set items equipped", function()
        local env = { itemModDB = new("ModDB") }
        calcs.applySetBonuses(env, { {} }, "1_4")
        -- No setBreakdown publish when zero set pieces (sets list is empty,
        -- which triggers the early-skip path in the CalcPerform bridge so
        -- output.SetBreakdown stays nil and the UI section hides).
        local sb = env.itemModDB.setBreakdown
        assert.is_true(sb == nil or (sb.sets and #sb.sets == 0))
        assert.are.equals(0, env.itemModDB.multipliers["CompleteSetCount"] or 0)
    end)

    it("publishes setBreakdown with sets[] and bonuses for one set piece", function()
        local env = { itemModDB = new("ModDB") }
        local items = { fakeSetItem() }
        calcs.applySetBonuses(env, items, "1_4")

        local sb = env.itemModDB.setBreakdown
        assert.is_not_nil(sb, "setBreakdown should be published")
        assert.are.equals(1, #sb.sets)
        assert.are.equals(KUZON_SET_ID, sb.sets[1].setId)
        assert.are.equals("Kuzon's Set", sb.sets[1].name)
        assert.are.equals(1, sb.sets[1].pieceCount)
        assert.are.equals(2, sb.sets[1].setSize)
        assert.is_false(sb.sets[1].complete)
        -- 1/2 pieces => no tier-2 bonus parsed yet (loop runs tier=2..effective
        -- where effective = min(count=1, maxSize=2) = 1, so range 2..1 is empty)
        assert.are.equals(0, #sb.sets[1].bonuses)
        assert.are.equals(0, sb.completeSetCount)
        assert.are.equals(0, env.itemModDB.multipliers["CompleteSetCount"])
    end)

    it("flags a set complete and emits the tier-2 bonus when fully equipped", function()
        local env = { itemModDB = new("ModDB") }
        local items = { fakeSetItem(), fakeSetItem() }
        calcs.applySetBonuses(env, items, "1_4")

        local sb = env.itemModDB.setBreakdown
        assert.is_not_nil(sb)
        assert.are.equals(1, #sb.sets)
        assert.are.equals(2, sb.sets[1].pieceCount)
        assert.are.equals(2, sb.sets[1].setSize)
        assert.is_true(sb.sets[1].complete)
        assert.are.equals(1, #sb.sets[1].bonuses)
        assert.are.equals(2, sb.sets[1].bonuses[1].tier)
        assert.are.equals(1, sb.completeSetCount)
        assert.are.equals(1, env.itemModDB.multipliers["CompleteSetCount"])
    end)

    it("counts wildcard items separately from real set pieces", function()
        local env = { itemModDB = new("ModDB") }
        -- Construct a wildcard item by giving it the WILDCARD_SET_MOD line.
        -- The exact constant is internal to CalcSetup so we inline the
        -- production text; if it ever changes, both sides break together.
        local wildcard = {
            rarity = "UNIQUE",
            title = "Legends Entwined",
            explicitModLines = {
                { line = "Counts as a part of every equipped item set" },
            },
        }
        local items = { fakeSetItem(), wildcard }
        calcs.applySetBonuses(env, items, "1_4")

        local sb = env.itemModDB.setBreakdown
        assert.is_not_nil(sb)
        assert.are.equals(1, sb.wildcardCount)
        -- Wildcard pushes Kuzon's count from 1 to 2 (matches real LE rule:
        -- 1 actual set piece + Legends Entwined = 2-piece bonus active)
        assert.are.equals(2, sb.sets[1].pieceCount)
        assert.is_true(sb.sets[1].complete)
        assert.are.equals(1, sb.completeSetCount)
    end)
end)
