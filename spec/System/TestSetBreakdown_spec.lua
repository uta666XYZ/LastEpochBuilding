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

    -- Each call returns a distinct piece (unique `uniqueID`) so the dedup
    -- guard (set-bonus-dedup-by-uniqueid) treats them as separate set members.
    -- Without a distinct key, two `fakeSetItem()` calls share the same title
    -- fallback dedup key and collapse to pieceCount=1.
    local fakeSetItemCounter = 0
    local function fakeSetItem(bonusText)
        fakeSetItemCounter = fakeSetItemCounter + 1
        return {
            rarity = "SET",
            title = "Kuzon's fake item " .. fakeSetItemCounter,
            uniqueID = 90000 + fakeSetItemCounter,
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

    -- @leb-regression-guard: set-bonus-dedup-by-uniqueid
    -- Per LE_datamining/extracted/set_formulas.md §3: in-game `setCompletion`
    -- uses `addUnique(idx, uniqueID)`, so two copies of the same set piece in
    -- different slots count as one member.
    it("dedups duplicate uniqueIDs (same set ring in both ring slots)", function()
        local env = { itemModDB = new("ModDB") }
        -- Two copies of the same set ring (same uniqueID + title) equipped in
        -- both ring slots — the game counts this as 1, not 2.
        local function fakeRing()
            return {
                rarity = "SET",
                title = "Kuzon's Ring",
                uniqueID = 12345,
                setInfo = {
                    setId = KUZON_SET_ID,
                    name = "Kuzon's Set",
                    bonus = { ["2"] = "+10 Health" },
                },
            }
        end
        local items = { fakeRing(), fakeRing() }
        calcs.applySetBonuses(env, items, "1_4")

        local sb = env.itemModDB.setBreakdown
        assert.is_not_nil(sb)
        assert.are.equals(1, #sb.sets)
        -- Critical: 2 equipped copies of same uniqueID => pieceCount=1, not 2.
        assert.are.equals(1, sb.sets[1].pieceCount)
        assert.is_false(sb.sets[1].complete)
        assert.are.equals(0, sb.completeSetCount)
    end)

    it("dedups by title when uniqueID is absent (BuildAndParseRaw fallback)", function()
        local env = { itemModDB = new("ModDB") }
        -- Some items lose their uniqueID through XML round-trip; title falls
        -- through as the dedup key.
        local function fakeNoIDRing()
            return {
                rarity = "SET",
                title = "Kuzon's Ring",
                setInfo = {
                    setId = KUZON_SET_ID,
                    name = "Kuzon's Set",
                    bonus = { ["2"] = "+10 Health" },
                },
            }
        end
        calcs.applySetBonuses(env, { fakeNoIDRing(), fakeNoIDRing() }, "1_4")

        local sb = env.itemModDB.setBreakdown
        assert.is_not_nil(sb)
        assert.are.equals(1, sb.sets[1].pieceCount)
        assert.is_false(sb.sets[1].complete)
    end)

    it("distinct uniqueIDs in the same set still count separately", function()
        local env = { itemModDB = new("ModDB") }
        local a = {
            rarity = "SET", title = "Kuzon's Helm", uniqueID = 100,
            setInfo = { setId = KUZON_SET_ID, name = "Kuzon's Set",
                        bonus = { ["2"] = "+10 Health" } },
        }
        local b = {
            rarity = "SET", title = "Kuzon's Boots", uniqueID = 101,
            setInfo = { setId = KUZON_SET_ID, name = "Kuzon's Set",
                        bonus = { ["2"] = "+10 Health" } },
        }
        calcs.applySetBonuses(env, { a, b }, "1_4")

        local sb = env.itemModDB.setBreakdown
        assert.are.equals(2, sb.sets[1].pieceCount)
        assert.is_true(sb.sets[1].complete)
        assert.are.equals(1, sb.completeSetCount)
    end)

    -- @leb-regression-guard: set-bonus-wildcard-clamp
    -- Per LE_datamining/extracted/set_formulas.md §3: Legends Entwined "does
    -- not stack with itself (only one slot can hold it)". Defends against
    -- data-corruption / parse-bug paths where two wildcard-flagged items
    -- surface simultaneously.
    it("clamps wildcard contribution to +1 even with multiple wildcard items", function()
        local env = { itemModDB = new("ModDB") }
        local function wildcard(title)
            return {
                rarity = "UNIQUE",
                title = title,
                explicitModLines = {
                    { line = "Counts as a part of every equipped item set" },
                },
            }
        end
        -- Two wildcard-flagged items + 1 real Kuzon's piece. The game caps
        -- effective wildcards at 1 by slot constraint, so pieceCount must be
        -- 1 (real) + 1 (clamped wildcard) = 2, NOT 1 + 2 = 3.
        local items = { fakeSetItem(), wildcard("Legends Entwined"), wildcard("Legends Entwined Twin") }
        calcs.applySetBonuses(env, items, "1_4")

        local sb = env.itemModDB.setBreakdown
        assert.is_not_nil(sb)
        assert.are.equals(1, #sb.sets)
        assert.are.equals(2, sb.sets[1].pieceCount,
            "wildcard contribution must be clamped at +1 regardless of count")
        assert.is_true(sb.sets[1].complete)
        assert.are.equals(1, sb.completeSetCount)
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
