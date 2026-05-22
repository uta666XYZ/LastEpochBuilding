-- @leb-regression-guard:movement-speed-vshdm-strict
-- Locks the LE-faithful vshDm path for player-scope
-- "% increased/reduced Movement Speed" rolls.
--
-- Triangulation case: MyLittleStJames lv79 Paladin (save BETA_13) Army of Skin
-- prefix `(26-30)% increased Movement Speed` byte=157
--   legacy round-half-up: round(26 + 157/255 × (30-26))   = 28
--   strict (vshDm):       floor((30+1-26) × 157/255 + 26)  = 29
-- The in-game item tooltip reads "29% increased Movement Speed"; combined with
-- the boots' other two rolls (19 + 11) the character-sheet Movement Speed total
-- is 59% (LEB was 58% under the legacy path).
--
-- Reverting the dispatcher in src/Modules/ItemTools.lua applyRange to the
-- legacy %% branch will flip these values back to the off-by-one results
-- and fail this spec.

describe("TestMovementSpeedVshdmStrict", function()
    -- HeadlessWrapper.lua already sets itemLib.useLEToolsRounding = true and
    -- exposes itemLib as a global. No additional setup required.

    it("Army of Skin (26-30) byte=157 → 29 (matches in-game tooltip)", function()
        local result = itemLib.applyRange("(26-30)% increased Movement Speed", 157, 1.0)
        assert.are.equals("29% increased Movement Speed", result)
    end)

    it("low byte stays at min", function()
        -- (26-30) byte=0 → floor((30+1-26) × 0/255 + 26) = 26
        local result = itemLib.applyRange("(26-30)% increased Movement Speed", 0, 1.0)
        assert.are.equals("26% increased Movement Speed", result)
    end)

    it("top byte clamps at max", function()
        -- (26-30) byte=255 → floor((30+1-26) × 1.0 + 26) = 31, clamped to d=30
        local result = itemLib.applyRange("(26-30)% increased Movement Speed", 255, 1.0)
        assert.are.equals("30% increased Movement Speed", result)
    end)

    it("'% reduced Movement Speed' also routes through strict path", function()
        local result = itemLib.applyRange("(26-30)% reduced Movement Speed", 157, 1.0)
        assert.are.equals("29% reduced Movement Speed", result)
    end)

    it("'Minion Movement Speed' is unaffected by the player branch", function()
        -- The minion branch (minion-movement-speed-vshdm-strict) matches first
        -- and returns; the player branch must not intercept it. Strict result
        -- for (6-16) byte=186 stays 14.
        local result = itemLib.applyRange("(6-16)% increased Minion Movement Speed", 186, 1.0)
        assert.are.equals("14% increased Minion Movement Speed", result)
    end)
end)
