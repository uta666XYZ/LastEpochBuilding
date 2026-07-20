-- @leb-regression-guard:endurance-threshold-round-not-floor
-- Locks the round-half-up render of `output.EnduranceThreshold` in
-- CalcDefence.lua. The in-game character sheet ROUNDS the Endurance
-- Threshold total; it does not floor it.
--
-- Triangulation case study: MyLittleStJames lv79 Paladin (save BETA_13)
--   etBase = 0.20 × Life(1318) = 263.6
--          + 180 (si4lgl-15 passive) + 157 (Sentinel-71 passive) = 600.6
--   floor(600.6) = 600  (old LEB — off by 1)
--   round(600.6) = 601  = in-game character sheet
--
-- The sibling WardDecayThreshold render a few lines below already uses
-- round-half-up (`m_floor(x + 0.5)`); the bare floor here was an internal
-- inconsistency. Reverting `m_floor(etBase * etInc + 0.5)` back to a bare
-- `m_floor(etBase * etInc)` re-introduces the off-by-one and fails this spec.
--
-- See REGRESSION_GUARDS.md "endurance-threshold-round-not-floor".

describe("EnduranceThresholdRound", function()
    local function readFile(path)
        local f = io.open(path, "r")
        if not f then return nil end
        local s = f:read("*a"); f:close()
        return s
    end

    local defenceSrc = readFile("Modules/CalcDefence.lua")

    it("CalcDefence renders EnduranceThreshold with round-half-up, not bare floor", function()
        assert.is_not_nil(defenceSrc, "must read CalcDefence.lua")
        -- The total must add +0.5 inside m_floor so a .5+ fractional total
        -- rounds up to match the in-game character sheet.
        assert.is_truthy(string.find(defenceSrc,
            'output%.EnduranceThreshold%s*=%s*m_floor%(etBase%s*%*%s*etInc%s*%+%s*0%.5%)', 1, false),
            "output.EnduranceThreshold must be m_floor(etBase * etInc + 0.5)")
        -- Guard against a regression to the bare-floor form.
        assert.is_falsy(string.find(defenceSrc,
            'output%.EnduranceThreshold%s*=%s*m_floor%(etBase%s*%*%s*etInc%)', 1, false),
            "output.EnduranceThreshold must NOT use bare m_floor(etBase * etInc)")
    end)

    it("round-half-up arithmetic: 600.6 → 601, 600.49 → 600, 600.50 → 601", function()
        local m_floor = math.floor
        local function render(total) return m_floor(total + 0.5) end
        assert.are.equals(601, render(600.6))
        assert.are.equals(600, render(600.49))
        assert.are.equals(601, render(600.50))
        -- exact integer total is unchanged
        assert.are.equals(600, render(600.0))
    end)
end)
