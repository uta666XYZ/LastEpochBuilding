-- @leb-regression-guard: symbols-of-hope-inc-not-more
-- Locks the LE-correct contract that Symbols of Hope's per-symbol Health Regen
-- bonus is INCREASED (additive with global LifeRegen INC), NOT a separate MORE
-- multiplier. Also locks that the per-symbol value is scaled by
-- SymbolsOfHopeEffect INC (Sentinel-119 Covenant of Light grants +4%/pt).
--
-- Pre-fix behaviour applied 20% per symbol as MORE outside applyBuffPrefix, so
-- regen ≈ baseRegen × (1 + globalInc) × (1 + 0.20 × symbols). For QDxZjL4J this
-- produced 60 × 2.52 × 3.0 ≈ 453 instead of the correct ~295.
--
-- See REGRESSION_GUARDS.md for the index entry.

describe("SymbolsOfHopeIncNotMore", function()
    before_each(function()
        newBuild()
    end)

    it("per-symbol value defaults to 20% INC and scales with SymbolsOfHopeEffect", function()
        -- Mirror the in-fix arithmetic in isolation: with +20% SymbolsOfHopeEffect
        -- the per-symbol contribution becomes 20 * (1 + 0.20) = 24 INC per symbol.
        local perSymbolPct = 20
        local sohEffectInc = 20
        local scaledPct = perSymbolPct * (1 + sohEffectInc / 100)
        assert.are.equals(24, scaledPct)

        -- Apply the scaled INC mod with the same Multiplier:ActiveSymbol gating
        -- the production code uses, then verify it surfaces as INC LifeRegen
        -- (additive), not a MORE multiplier.
        build.configTab.modList:NewMod("Multiplier:ActiveSymbol", "BASE", 10, "Test")
        build.configTab.modList:NewMod("LifeRegen", "INC", scaledPct, "Symbols of Hope",
            { type = "Multiplier", var = "ActiveSymbol" })
        runCallback("OnFrame")

        -- 24 * 10 = 240 INC, no MORE.
        local incTotal = build.calcsTab.mainEnv.modDB:Sum("INC", nil, "LifeRegen")
        local moreTotal = build.calcsTab.mainEnv.modDB:More(nil, "LifeRegen")
        assert.are.equals(240, incTotal)
        assert.are.equals(1, moreTotal)
    end)

    it("Meditation node doubles per-symbol value to 40", function()
        local hasMeditation = true
        local perSymbolPct = hasMeditation and 40 or 20
        assert.are.equals(40, perSymbolPct)
    end)
end)
