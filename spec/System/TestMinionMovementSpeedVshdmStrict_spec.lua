-- @leb-regression-guard:minion-movement-speed-vshdm-strict
-- Locks the LE-faithful vshDm Hundredth path for
-- "% increased/reduced Minion Movement Speed" rolls.
--
-- Triangulation case: BxvJP3g1 lv99 Necromancer Pebbles' Collar Reforged
-- implicit `(6-16)% increased Minion Movement Speed` byte=186
--   legacy round-half-up: floor((6 + 186/255 × 10) + 0.5) = 13
--   strict (vshDm):       floor((16 + 1 - 6) × 186/255 + 6) = 14
-- LETools planner Minion-tab "Movement Speed" = 14% matches strict.
--
-- Reverting the dispatcher in src/Modules/ItemTools.lua applyRange to the
-- legacy %% branch will flip these values back to the off-by-one results
-- and fail this spec.

describe("TestMinionMovementSpeedVshdmStrict", function()
    -- HeadlessWrapper.lua already sets itemLib.useLEToolsRounding = true and
    -- exposes itemLib as a global. No additional setup required.

    it("Pebbles' Collar (6-16) byte=186 → 14 (matches LETools)", function()
        local result = itemLib.applyRange("(6-16)% increased Minion Movement Speed", 186, 1.0)
        assert.are.equals("14% increased Minion Movement Speed", result)
    end)

    it("low byte stays at min for narrow range", function()
        -- (6-16) byte=0 → floor((16+1-6) × 0/255 + 6) = 6
        local result = itemLib.applyRange("(6-16)% increased Minion Movement Speed", 0, 1.0)
        assert.are.equals("6% increased Minion Movement Speed", result)
    end)

    it("top byte clamps at max", function()
        -- (6-16) byte=255 → floor((16+1-6) × 1.0 + 6) = 17, clamped to d=16
        local result = itemLib.applyRange("(6-16)% increased Minion Movement Speed", 255, 1.0)
        assert.are.equals("16% increased Minion Movement Speed", result)
    end)

    it("'% reduced Minion Movement Speed' also routes through strict path", function()
        -- Mirror coverage so the negated affix variant is also locked.
        local result = itemLib.applyRange("(6-16)% reduced Minion Movement Speed", 186, 1.0)
        assert.are.equals("14% reduced Minion Movement Speed", result)
    end)

    it("player-scope '% increased Movement Speed' uses its own strict branch", function()
        -- The minion branch matches only the "Minion Movement Speed" substring,
        -- so it does NOT catch the player line. The player line is instead
        -- routed through the sibling movement-speed-vshdm-strict branch (also
        -- vshDm), locked by TestMovementSpeedVshdmStrict_spec.lua:
        --   (15-18) byte=63 strict = floor((18+1-15) × 63/255 + 15) = 15
        local result = itemLib.applyRange("(15-18)% increased Movement Speed", 63, 1.0)
        assert.are.equals("15% increased Movement Speed", result)
    end)
end)
