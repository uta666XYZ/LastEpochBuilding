-- @leb-regression-guard:scaleaddmod-stacking-coeff-fractional-retention
-- Locks the fractional-retention path in ModStore.lua ScaleAddMod for mods
-- that carry a Multiplier / PerStat tag (per-stack coefficients).
--
-- A buff-effect scale (e.g. SymbolsOfHopeEffect +20%) applied to a per-stack
-- coefficient must retain its fractional part, because the stack count
-- multiplies it AFTER scaling:
--   3 (per active symbol) * 1.2 (effect) = 3.6 ; * 5 symbols = 18
-- The legacy `m_modf(round(x*scale,2))` truncated 3.6 -> 3, so * 5 = 15.
--
-- Triangulation case: MyLittleStJames lv79 Paladin (save BETA_13).
--   si4lgl-26 "+1% Block Chance Per Active Symbol" alloc 3 -> 3/symbol.
--   in-game character-sheet Block Chance = 35
--                    = 8 (Sentinel-89) + 3 + 3 + 3 (Sentinel-1/27/72 flat)
--                    + 18 (si4lgl-26: 3.6/symbol * 5).
--   LEB was 32 (si4lgl-26 contributed 15, not 18) before the fix.
--   Block EFFECTIVENESS escaped the bug only because 45 * 1.2 = 54 is integral.
--
-- Reverting ScaleAddMod to a bare `m_modf(...)` for every numeric value
-- re-introduces the off-by-3 and fails this spec.
--
-- See REGRESSION_GUARDS.md "scaleaddmod-stacking-coeff-fractional-retention".

describe("ScaleAddModStackingCoeff", function()
    local function readFile(path)
        local f = io.open(path, "r")
        if not f then return nil end
        local s = f:read("*a"); f:close()
        return s
    end

    local modStoreSrc = readFile("Classes/ModStore.lua")

    it("ModStore.lua detects a stacking tag (Multiplier/PerStat)", function()
        assert.is_not_nil(modStoreSrc, "must read Classes/ModStore.lua")
        assert.is_truthy(string.find(modStoreSrc, "hasStackingTag", 1, true),
            "ScaleAddMod must compute hasStackingTag")
        assert.is_truthy(string.find(modStoreSrc,
            'effects%.type%s*==%s*"Multiplier"%s*or%s*effects%.type%s*==%s*"PerStat"', 1, false),
            "hasStackingTag must be set for Multiplier or PerStat tags")
    end)

    it("ScaleAddMod retains the scaled float for stacking-tag mods (no m_modf)", function()
        assert.is_not_nil(modStoreSrc)
        -- The stacking-tag branch keeps round(value*scale,2) WITHOUT m_modf.
        assert.is_truthy(string.find(modStoreSrc,
            'elseif hasStackingTag then', 1, true),
            "must have an elseif hasStackingTag branch")
        assert.is_truthy(string.find(modStoreSrc,
            'subMod%.value%s*=%s*round%(subMod%.value%s*%*%s*scale,%s*2%)', 1, false),
            "stacking-tag branch must retain round(value*scale,2) as a float")
    end)

    it("arithmetic: per-symbol 3 * 1.2 retained as 3.6, * 5 symbols = 18", function()
        local m_modf = math.modf
        local function round(x, p) local m = 10 ^ (p or 0); return math.floor(x * m + 0.5) / m end
        local perSymbol = 3
        local effectScale = 1.2
        local symbols = 5
        -- legacy (buggy) truncation path
        local legacy = (m_modf(round(perSymbol * effectScale, 2))) * symbols
        assert.are.equals(15, legacy)
        -- fixed fractional-retention path
        local fixed = round(perSymbol * effectScale, 2) * symbols
        assert.are.equals(18, fixed)
    end)

    it("block-effectiveness sibling stays integral (45 * 1.2 = 54, no change)", function()
        local function round(x, p) local m = 10 ^ (p or 0); return math.floor(x * m + 0.5) / m end
        assert.are.equals(54, round(45 * 1.2, 2))
        assert.are.equals(270, round(45 * 1.2, 2) * 5)
    end)
end)
