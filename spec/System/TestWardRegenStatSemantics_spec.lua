-- @leb-regression-guard: letools-diff-ward-regen-gross-mapping
-- Locks the semantic contract that LE's planner "Ward Regen" displays the
-- gross +Ward/sec from mods (Sanguine Runestones / Vessel of Strife etc.)
-- and that the LEB analogue is `output.WardPerSecond`, NOT `NetWardRegen`.
--
-- NetWardRegen = wps - decay, which trends to ~0 at steady state (the
-- decay curve auto-balances generation). Mapping LE "Ward Regen" to it
-- silently reports a -wps phantom drift on every ward-using build.
--
-- See REGRESSION_GUARDS.md "letools-diff-ward-regen-gross-mapping".

describe("WardRegenStatSemantics", function()
    it("'(N)% of Health Regen also applies to Ward' parses to LifeRegenAppliesToWard BASE", function()
        newBuild()
        local mods, extra = modLib.parseMod("29% of Health Regen also applies to Ward")
        assert.is_nil(extra, "expected no leftover text")
        assert.is_not_nil(mods, "parser must accept the Sanguine-Runestone phrasing")
        local found = false
        for _, m in ipairs(mods) do
            if m.name == "LifeRegenAppliesToWard" and m.type == "BASE" and m.value == 29 then
                found = true
            end
        end
        assert.is_true(found,
            "parser must emit LifeRegenAppliesToWard BASE 29 (got something else)")
    end)

    it("Vessel of Strife produces WardPerSecond (gross) > 0 and NetWardRegen ≈ 0 at steady state", function()
        local path1 = "../spec/TestBuilds/1.4/QeY7m5Xq lv97 Druid.xml"
        local path2 = "spec/TestBuilds/1.4/QeY7m5Xq lv97 Druid.xml"
        local f = io.open(path1, "r") or io.open(path2, "r")
        if not f then
            pending("QeY7m5Xq lv97 Druid build snapshot not present; semantic claim documented in REGRESSION_GUARDS")
            return
        end
        local importCode = f:read("*a"); f:close()
        newBuild()
        loadBuildFromXML(importCode, path1)
        build.buildFlag = true
        runCallback("OnFrame")
        build.calcsTab:BuildOutput()
        local output = build.calcsTab.mainEnv.player.output
        assert.is_true((output.WardPerSecond or 0) > 100,
            "WardPerSecond must be populated from Vessel of Strife conversion (got "..tostring(output.WardPerSecond)..")")
        assert.is_true(math.abs(output.NetWardRegen or 0) < 5,
            "NetWardRegen is wps - decay and must remain ~0 at steady state (got "..tostring(output.NetWardRegen)..")")
        -- Contract: WardPerSecond is the LE-comparable stat, NetWardRegen is not.
        assert.are_not.equal(output.WardPerSecond, output.NetWardRegen,
            "WardPerSecond (gross) and NetWardRegen (net) must remain distinct outputs")
    end)
end)
