-- @leb-regression-guard:crit-extra-damage-reduction-display-uncapped
-- Locks the split between display value (uncapped) and effect-side
-- clamp (m_min(..., 100)) for "Reduced Bonus Damage Taken from Critical
-- Strikes". LE's sidebar shows the raw sum (e.g. 129 on BgRrP5rr Paladin
-- lv98) while internally the multiplier (1 - X/100) cannot go negative.
--
-- Symptoms before fix (G1 fresh diff, 2026-05-11):
--   * BgRrP5rr Paladin: LE=129 LEB=100 Δ=-29
--   * Q9J4wvmD Paladin: LE=116 LEB=100 Δ=-16
-- Root cause: m_min(modDB:Sum(...), 100) was applied to the displayed
-- output, capping the sidebar at the same point as the effect clamp.
-- See REGRESSION_GUARDS.md "crit-extra-damage-reduction-display-uncapped".

describe("CritExtraDamageReduction display vs effect", function()
    before_each(function()
        newBuild()
    end)

    it("display value is uncapped sum of ReduceCritExtraDamage BASE mods", function()
        build.configTab.input.customMods = [[
        +60% reduced bonus damage taken from critical strikes
        +40% reduced bonus damage taken from critical strikes
        +29% reduced bonus damage taken from critical strikes
        ]]
        build.configTab:BuildModList()
        runCallback("OnFrame")
        assert.are.equals(129, build.calcsTab.calcsOutput.CritExtraDamageReduction)
    end)

    it("EnemyCritEffect clamps effective reduction at 100", function()
        build.configTab.input.customMods = [[
        +200% reduced bonus damage taken from critical strikes
        ]]
        build.configTab:BuildModList()
        runCallback("OnFrame")
        -- Display reflects the raw sum, uncapped.
        assert.are.equals(200, build.calcsTab.calcsOutput.CritExtraDamageReduction)
        -- Effect-side: (1 - min(200,100)/100) = 0, so EnemyCritEffect collapses
        -- to the no-crit baseline (1 + critChance * critDmg * 0 = 1).
        assert.are.equals(1, build.calcsTab.calcsOutput.EnemyCritEffect)
    end)
end)
