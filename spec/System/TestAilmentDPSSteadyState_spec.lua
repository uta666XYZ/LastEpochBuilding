-- @leb-regression-guard: ailment-dps-steady-state-formula
-- Locks the steady-state ailment DPS formula in CalcOffence.lua against the
-- game pipeline documented in LE_datamining/extracted/dot_channel_formulas.md.
--
-- The formula has three structural invariants that must hold together:
--   1. per-stack DPS divides by BASE duration (rate preserved), not effDuration
--   2. steady-state stack count uses applicationsPerSec * effDuration
--   3. total DPS = stacks * dpsPerStack, capped at data.misc.DotDpsCap
--
-- Removing any one of these silently shifts the DPS by a `durationMult`
-- factor — the build-snapshot diff catches it on builds with non-1 enemy
-- ailment duration, but a structural source check is cheaper to maintain
-- than triangulating from snapshots.
--
-- See:
--   * LE_datamining/extracted/dot_channel_formulas.md §3, §4
--   * REGRESSION_GUARDS.md "ailment-dps-steady-state-formula"

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("AilmentDPSSteadyStateFormula", function()
    it("CalcOffence.lua carries the inline regression-guard marker", function()
        local text = readSource("Modules/CalcOffence.lua")
        assert.is_truthy(string.find(text, "@leb-regression-guard:ailment-dps-steady-state-formula", 1, true),
            "inline guard ID must remain in CalcOffence.lua for cross-reference auditing")
    end)

    it("per-stack DPS divides by BASE duration (rate-preserved invariant)", function()
        local text = readSource("Modules/CalcOffence.lua")
        assert.is_truthy(string.find(text, "dpsPerStack = totalDamagePerStack / baseDuration", 1, true),
            "per-stack DPS must be baseDamage/baseDuration — using effDuration would " ..
            "dilute rate as duration extends, violating dot_channel_formulas.md §4")
    end)

    it("steady-state stack count uses applicationsPerSec * effDuration", function()
        local text = readSource("Modules/CalcOffence.lua")
        assert.is_truthy(string.find(text, "applicationsPerSec = hitRate * (chance / 100)", 1, true),
            "applicationsPerSec must factor proc chance into hit rate")
        assert.is_truthy(string.find(text, "rawStacks = applicationsPerSec * effDuration", 1, true),
            "steady-state stacks must grow with effDuration; otherwise increased " ..
            "ailment duration loses its DPS contribution")
    end)

    it("total DPS is clamped at data.misc.DotDpsCap", function()
        local text = readSource("Modules/CalcOffence.lua")
        assert.is_truthy(string.find(text, "totalDPS = m_min(dpsPerStack * stacks, data.misc.DotDpsCap)", 1, true),
            "total ailment DPS must be capped at the engine-side int32/60s ceiling")
    end)

    it("dpsPerStack snapshot precedes stack-count derivation", function()
        local text = readSource("Modules/CalcOffence.lua")
        local idxRate    = string.find(text, "dpsPerStack = totalDamagePerStack / baseDuration", 1, true)
        local idxStacks  = string.find(text, "rawStacks = applicationsPerSec * effDuration", 1, true)
        local idxTotal   = string.find(text, "totalDPS = m_min(dpsPerStack * stacks, data.misc.DotDpsCap)", 1, true)
        assert.is_not_nil(idxRate)
        assert.is_not_nil(idxStacks)
        assert.is_not_nil(idxTotal)
        assert.is_true(idxRate < idxStacks, "per-stack rate must be computed before stack count")
        assert.is_true(idxStacks < idxTotal, "stack count must be computed before total DPS")
    end)
end)
