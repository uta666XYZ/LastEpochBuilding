-- @leb-regression-guard:trigger-rate-cap-ptt
-- Locks the PTT rate-cap decorator on bridged trigger conditions. LE rate-limits
-- triggered casts with a ProcTimeTracker (datamined game source: at most `limit` procs per
-- `interval` seconds), so the effective cap = limit/interval:
--   "(up to N times per second)"     -> N
--   "(up to N times per M seconds)"  -> N/M
--   "(K second cooldown)" = PTT(1,K)  -> 1/K
-- The parser emits the base condition's functional mod PLUS a global
-- TriggerRateCapPerSecond_<skillId>; CalcSetup attaches it to the injected group and
-- the CalcTriggers handler applies output.TriggerRateCap = min(cap, ...). LEB's
-- default handler previously only narrowed the cap via maxStacks, so without this an
-- affix-specified cap was ignored. See REGRESSION_GUARDS.md.

describe("TriggerRateCap decorator (parser)", function()
    it("'on melee hit (up to 3 times per second)' emits melee-hit mod + cap 3/s", function()
        assert.are.equals("Smite", data.skills.Smite.name)
        local mods, extra = modLib.parseMod("39% chance to cast Smite on melee hit (up to 3 times per second)")
        assert.is_nil(extra)
        assert.is_not_nil(mods)
        assert.are.equals(2, #mods)
        local byName = {}
        for _, m in ipairs(mods) do byName[m.name] = m.value end
        assert.are.equals(39, byName["ChanceToTriggerOnMeleeHit_Smite"])
        assert.are.equals(3, byName["TriggerRateCapPerSecond_Smite"])
        assert.is_falsy(mods.notSupported)
    end)

    it("'(up to N times per M seconds)' computes cap = N/M", function()
        local mods = modLib.parseMod("20% chance to cast Smite on melee hit (up to 10 times per 2 seconds)")
        local cap
        for _, m in ipairs(mods) do if m.name == "TriggerRateCapPerSecond_Smite" then cap = m.value end end
        assert.is_true(math.abs(cap - 5) < 1e-9, "10 per 2s = 5/s")
    end)

    it("'(K second cooldown)' computes cap = 1/K", function()
        local mods = modLib.parseMod("12% chance to cast Smite on hit (3 second cooldown)")
        local capMod, baseMod
        for _, m in ipairs(mods) do
            if m.name == "TriggerRateCapPerSecond_Smite" then capMod = m.value end
            if m.name == "ChanceToTriggerOnHit_Smite" then baseMod = m.value end
        end
        assert.are.equals(12, baseMod)
        assert.is_true(math.abs(capMod - (1/3)) < 1e-9, "3 second cooldown = 1/3 per second")
    end)
end)

describe("TriggerRateCap source invariants", function()
    it("CalcSetup attaches the per-skill cap and CalcTriggers applies it gated", function()
        local f = assert(io.open("Modules/CalcSetup.lua", "r"))
        local cs = f:read("*a"); f:close()
        assert.is_truthy(cs:find("TriggerRateCapPerSecond_", 1, true),
            "CalcSetup must sum the per-skill TriggerRateCapPerSecond_ cap")
        assert.is_truthy(cs:find("triggerRateCapPerSecond", 1, true),
            "CalcSetup must carry triggerRateCapPerSecond onto the group")
        local g = assert(io.open("Modules/CalcTriggers.lua", "r"))
        local ct = g:read("*a"); g:close()
        assert.is_truthy(ct:find("srcInst.triggerRateCapPerSecond", 1, true),
            "CalcTriggers must read the cap off srcInstance")
        assert.is_truthy(ct:find("m_min%(output%.TriggerRateCap, srcInst%.triggerRateCapPerSecond%)"),
            "CalcTriggers must apply TriggerRateCap = min(cap, ...) gated on the field")
        assert.is_truthy(ct:find("@leb%-regression%-guard:trigger%-rate%-cap%-ptt"),
            "inline regression-guard marker must be present in CalcTriggers")
    end)
end)
