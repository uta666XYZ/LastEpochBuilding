-- @leb-regression-guard: ward-decay-floor-zero-passive
-- Locks the 0.5/s ward-decay floor implementation in CalcPerform.lua's
-- post-offence ManaSpentGainedAsWard recomputation site.
--
-- Game `ProtectionClass.Update` (RVA 0x234B8C0, non-boss branch) clamps the
-- per-frame ward decay to `dt * minimumWardDecayWithoutRegen` (0.5/s in
-- GlobalPlayerProperties) iff `wardRegen + wardRegenFromStats <= 0`.
-- In LEB terms passive-only WPS corresponds to that pair, and the only
-- decay-computation site that can observe `passive == 0 AND total > 0` is
-- the post-offence ManaSpentGainedAsWard path in CalcPerform.lua.
--
-- See:
--   * LE_datamining/extracted/ward_formulas.md
--   * REGRESSION_GUARDS.md "ward-decay-floor-zero-passive"

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("WardDecayFloorZeroPassive", function()
    it("CalcPerform.lua snapshots passive WPS and assigns it to the display before folding event-driven into local wps", function()
        local text = readSource("Modules/CalcPerform.lua")
        -- The passive snapshot folds in current-mana / missing-health PASSIVE
        -- contributions (which belong in game `wardRegenFromStats`); only
        -- ManaSpentGainedAsWard is event-driven and excluded.
        local idxSnap = string.find(text,
            "local passiveWardPerSecond = [%w_]+ %+ currentManaContribution %+ missingHealthContribution")
        assert.is_not_nil(idxSnap,
            "passiveWardPerSecond must combine base WPS + currentMana + missingHealth contributions")
        -- Display stat = passive-only (game-faithful per ProtectionClass.Update).
        -- @leb-regression-guard:ward-regen-passive-vs-event-split — the event-driven
        -- ManaSpentGainedAsWard contribution lives only in the local `wps` used
        -- for the Ward/WardDecay inversion math, never in pOut.WardPerSecond.
        local idxDisplay = string.find(text,
            "pOut%.WardPerSecond%s*=%s*passiveWardPerSecond")
        assert.is_not_nil(idxDisplay,
            "pOut.WardPerSecond must be assigned the passive-only snapshot")
        assert.is_true(idxSnap < idxDisplay, "passive snapshot must come before the display assignment")
        local idxWps = string.find(text,
            "local%s+wps%s*=%s*passiveWardPerSecond%s*%+%s*manaSpentContribution")
        assert.is_not_nil(idxWps,
            "local wps must fold passive + event-driven manaSpentContribution after the display assignment")
        assert.is_true(idxDisplay < idxWps, "local wps must be defined after the display assignment")
    end)

    it("CalcPerform.lua applies 0.5/s decay floor when passive WPS <= 0", function()
        local text = readSource("Modules/CalcPerform.lua")
        assert.is_truthy(string.find(text, "if passiveWardPerSecond <= 0 then", 1, true),
            "floor must gate on passive-only WPS being non-positive")
        assert.is_truthy(string.find(text, "rawWardDecayPerSecond = m_max(rawWardDecayPerSecond, 0.5)", 1, true),
            "floor must clamp rawWardDecayPerSecond at 0.5 (minimumWardDecayWithoutRegen)")
    end)

    it("CalcPerform.lua carries the inline regression-guard marker", function()
        local text = readSource("Modules/CalcPerform.lua")
        assert.is_truthy(string.find(text, "@leb-regression-guard:ward-decay-floor-zero-passive", 1, true),
            "inline guard ID must remain in CalcPerform.lua for cross-reference auditing")
    end)

    it("CalcDefence.lua documents why the floor cannot trigger at its decay sites", function()
        -- Defensive: if a future change moves the decay computation back into
        -- CalcDefence and short-circuits Ward to 0 when WPS<=0, the floor will
        -- be silently missing. The comment block must remain.
        local text = readSource("Modules/CalcDefence.lua")
        assert.is_truthy(string.find(text, "ward-decay-floor-zero-passive", 1, true),
            "CalcDefence.lua must cross-reference the floor guard")
    end)
end)
