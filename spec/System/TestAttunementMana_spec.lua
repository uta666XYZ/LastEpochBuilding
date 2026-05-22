-- @leb-regression-guard: attunement-mana-per-point
-- Diagnostic / regression guard for "Attunement grants +2 flat Mana per point".
-- Game source-of-truth: LE_datamining/extracted/formulas_verified.md §23.
-- Establishing context: Qqwv73q2 lv62 Warlock LETools Mana 269.31 vs LEB 175
-- (Δ=-94.31 == Att=47 * +2/pt, confirming Attunement contribution = 0).
--
-- The intrinsic +2 Mana PerStat:RawAtt mod is registered in CalcSetup.lua:735.
-- This spec exercises it end-to-end: bump Att via a custom mod and assert
-- output.Mana goes up by exactly 2 * delta(Att).

describe("AttunementManaPerPoint", function()
    before_each(function()
        newBuild()
    end)

    it("each Attunement point adds +2 flat Mana via PerStat:RawAtt", function()
        runCallback("OnFrame")
        local baseMana = build.calcsTab.mainEnv.player.output.Mana
        local baseAtt  = build.calcsTab.mainEnv.player.output.Att or 0
        local baseRawAtt = build.calcsTab.mainEnv.player.output.RawAtt or 0
        -- Sanity: Raw mirror must match live Att
        assert.are.equals(baseAtt, baseRawAtt,
            "output.RawAtt should mirror output.Att after attribute conversion")

        build.configTab.input.customMods = "+10 to Attunement\n"
        build.configTab:BuildModList()
        runCallback("OnFrame")

        local newMana = build.calcsTab.mainEnv.player.output.Mana
        local newAtt  = build.calcsTab.mainEnv.player.output.Att
        local newRawAtt = build.calcsTab.mainEnv.player.output.RawAtt

        assert.are.equals(baseAtt + 10, newAtt,
            "Att must climb by 10")
        assert.are.equals(baseRawAtt + 10, newRawAtt,
            "RawAtt must mirror Att")
        assert.are.equals(baseMana + 20, newMana,
            "Mana must increase by 2 per Attunement point (LE formula)")
    end)
end)
