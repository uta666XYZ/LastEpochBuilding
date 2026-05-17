-- @leb-regression-guard:with-attribute-threshold
-- LE phrasing "with N <Attribute>" gates a leading effect behind a StatThreshold.
-- The effect applies in full once the player reaches N points of the attribute —
-- it is NOT a per-N divisor.
--
-- Establishing build: BgRrekaR lv100 Spellblade. Mage-91 "Transcendence" rank 6
-- emits "+24 Additional Ward per Second with 60 Intelligence" via notScalingStats
-- when node.alloc >= noScalingPointThreshold. Without parser support the tail
-- " with 60 Intelligence " stayed as parseMod `extra`, and PassiveTree.lua:458
-- silently dropped the whole mod list. Pre-fix WardPerSecond=304 (LE=323), with
-- this fix the +24 contribution from Mage-91 now reaches modDB.
--
-- See REGRESSION_GUARDS.md > with-attribute-threshold.

describe("WithAttributeThreshold", function()

    describe("parser", function()
        it("'+24 Ward per Second with 60 Intelligence' → StatThreshold Int 60", function()
            local mods, extra = modLib.parseMod("+24 Ward per Second with 60 Intelligence")
            assert.is_nil(extra, "must have no unparsed leftover")
            assert.is_not_nil(mods, "must return a parsed mod list")
            assert.is_true(#mods >= 1)
            local m = mods[1]
            assert.are.equals("WardPerSecond", m.name)
            assert.are.equals("BASE", m.type)
            assert.are.equals(24, m.value)
            -- locate the StatThreshold tag (order is not contractual)
            local thr
            for _, tag in ipairs(m) do
                if tag.type == "StatThreshold" then thr = tag; break end
            end
            assert.is_not_nil(thr, "must carry a StatThreshold tag")
            assert.are.equals("Int", thr.stat)
            assert.are.equals(60, thr.threshold)
        end)

        it("'+24 Additional Ward per Second with 60 Intelligence' parses (alias strips 'Additional')", function()
            local mods, extra = modLib.parseMod("+24 Additional Ward per Second with 60 Intelligence")
            assert.is_nil(extra, "the 'Additional' alias must clean up the line so no extra residue remains")
            assert.is_not_nil(mods)
            local m = mods[1]
            assert.are.equals("WardPerSecond", m.name)
            assert.are.equals(24, m.value)
            local thr
            for _, tag in ipairs(m) do
                if tag.type == "StatThreshold" then thr = tag; break end
            end
            assert.is_not_nil(thr)
            assert.are.equals("Int", thr.stat)
            assert.are.equals(60, thr.threshold)
        end)

        it("works for abbreviated attribute names too ('with 30 Str')", function()
            local mods, extra = modLib.parseMod("+10 Health with 30 Str")
            assert.is_nil(extra)
            local m = mods[1]
            assert.are.equals("Life", m.name)
            assert.are.equals(10, m.value)
            local thr
            for _, tag in ipairs(m) do
                if tag.type == "StatThreshold" then thr = tag; break end
            end
            assert.is_not_nil(thr)
            assert.are.equals("Str", thr.stat)
            assert.are.equals(30, thr.threshold)
        end)
    end)

end)
