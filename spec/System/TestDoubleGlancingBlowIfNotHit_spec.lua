-- @leb-regression-guard:double-glancing-blow-if-not-hit
-- Locks ModParser's handling of Rogue-104 ("Poise") notScalingStat
-- "Double Glancing Blow Chance If Not Hit" + the CalcDefence display
-- path that composes BASE × (1 + INC/100). LE applies the stat as
-- +100 INC GlancingBlowChance while the player has NOT been hit
-- recently. LEB gates the mod on the shared BeenHitRecently condition
-- (neg); the ConfigOptions toggle defaults off, so by default the
-- bonus applies and matches the LETools sidebar. Toggling
-- conditionBeenHitRecently=true collapses the bonus.
--
-- Symptoms before fix (G1 fresh diff, 2026-05-11):
--   * BM6x3nKn lv66 Bladedancer GlancingBlowChance LE=24 LEB=2 Δ=-22
--   * om6xnlL1 lv100 Bladedancer LE=26 LEB=2 Δ=-24
--   * o3Zl6gkV lv100 Bladedancer LE=26 LEB=16 Δ=-10
-- Root cause: the bare wording fell through to the generic parser
-- (see ModCache.lua entry that left empty mods + leftover text), AND
-- CalcDefence.lua summed only BASE for output.GlancingBlowChance.
-- See REGRESSION_GUARDS.md "double-glancing-blow-if-not-hit".

describe("DoubleGlancingBlowIfNotHit parser", function()
    it("'Double Glancing Blow Chance If Not Hit' parses to GlancingBlowChance INC 100 gated on BeenHitRecently neg", function()
        local mods, extra = modLib.parseMod("Double Glancing Blow Chance If Not Hit")
        assert.is_nil(extra)
        assert.is_not_nil(mods)
        assert.are.equals(1, #mods)
        local m = mods[1]
        assert.are.equals("GlancingBlowChance", m.name)
        assert.are.equals("INC", m.type)
        assert.are.equals(100, m.value)
        assert.is_not_nil(m[1])
        assert.are.equals("Condition", m[1].type)
        assert.are.equals("BeenHitRecently", m[1].var)
        assert.is_true(m[1].neg)
    end)

    it("leading whitespace (as authored in tree JSON notScalingStats) is tolerated", function()
        local mods, extra = modLib.parseMod(" Double Glancing Blow Chance If Not Hit")
        assert.is_nil(extra)
        assert.is_not_nil(mods)
        assert.are.equals(1, #mods)
        assert.are.equals("GlancingBlowChance", mods[1].name)
        assert.are.equals("INC", mods[1].type)
        assert.are.equals(100, mods[1].value)
    end)
end)

describe("GlancingBlowChance display composes BASE x (1 + INC/100)", function()
    before_each(function()
        newBuild()
    end)

    it("BASE 12 + INC 100 produces 24 by default (BeenHitRecently off)", function()
        build.configTab.input.customMods = [[
        +12% Glancing Blow Chance
        Double Glancing Blow Chance If Not Hit
        ]]
        build.configTab:BuildModList()
        runCallback("OnFrame")
        assert.are.equals(24, build.calcsTab.calcsOutput.GlancingBlowChance)
    end)

    it("BASE only (no INC) is unchanged", function()
        build.configTab.input.customMods = [[
        +13% Glancing Blow Chance
        ]]
        build.configTab:BuildModList()
        runCallback("OnFrame")
        assert.are.equals(13, build.calcsTab.calcsOutput.GlancingBlowChance)
    end)

    it("composed total is clamped at 100", function()
        build.configTab.input.customMods = [[
        +60% Glancing Blow Chance
        Double Glancing Blow Chance If Not Hit
        ]]
        build.configTab:BuildModList()
        runCallback("OnFrame")
        assert.are.equals(100, build.calcsTab.calcsOutput.GlancingBlowChance)
    end)

    it("toggling conditionBeenHitRecently collapses the bonus to BASE", function()
        build.configTab.input.customMods = [[
        +12% Glancing Blow Chance
        Double Glancing Blow Chance If Not Hit
        ]]
        build.configTab.input.conditionBeenHitRecently = true
        build.configTab:BuildModList()
        runCallback("OnFrame")
        assert.are.equals(12, build.calcsTab.calcsOutput.GlancingBlowChance)
    end)
end)
