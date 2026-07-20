-- @leb-regression-guard: phase4-stun-aoe-melee-flag-isolation
-- @leb-regression-guard: phase4-minion-modifier-bucket-aggregation
--
-- Locks two non-obvious correctness contracts introduced in Phase 4 of the
-- LETools-parity Calcs-tab work:
--
-- 1. Melee* aggregates (MeleeStunChanceInc, MeleeAreaOfEffectInc) MUST be
--    computed as `melee-cfg sum minus unflagged sum`. modDB:Sum with
--    `{ flags = ModFlag.Melee }` returns mods matching the flag set OR mods
--    with no flags — NOT melee-only mods. A naive rewrite to a direct
--    melee-cfg call double-counts unflagged contributions into the Melee row.
--
-- 2. Every Minion* output read from Calcs tab MUST flow through the
--    MinionModifier-LIST bucket loop in CalcDefence.buildDefenceEstimations.
--    Reverting any single Minion* to a top-level `modDB:Sum(..., "<name>")`
--    silently returns 0 because minion mods live nested inside MinionModifier
--    LIST values, not at the modDB top level. Already broken-and-fixed once
--    against MinionLifeInc; the loop now backs ~30 outputs.
--
-- See REGRESSION_GUARDS.md "phase4-stun-aoe-melee-flag-isolation" and
-- "phase4-minion-modifier-bucket-aggregation".

describe("Phase4LEToolsParityAggregates", function()
    before_each(function()
        newBuild()
    end)

    it("Melee* aggregates isolate the melee-tagged delta (no double-count of unflagged)", function()
        -- 30% unflagged + 20% melee-flagged → expect:
        --   StunChanceInc = 30 (unflagged total)
        --   MeleeStunChanceInc = 20 (melee-only delta, NOT 50)
        build.configTab.modList:NewMod("StunChance", "INC", 30, "TestUnflagged")
        build.configTab.modList:NewMod("StunChance", "INC", 20, "TestMelee", ModFlag.Melee)
        build.configTab.modList:NewMod("AreaOfEffect", "INC", 40, "TestUnflagged")
        build.configTab.modList:NewMod("AreaOfEffect", "INC", 15, "TestMelee", ModFlag.Melee)
        runCallback("OnFrame")

        assert.are.equals(30, build.calcsTab.calcsOutput.StunChanceInc)
        assert.are.equals(20, build.calcsTab.calcsOutput.MeleeStunChanceInc,
            "MeleeStunChanceInc must equal melee-only delta (20), not melee-cfg total (50)")
        assert.are.equals(40, build.calcsTab.calcsOutput.AreaOfEffectInc)
        assert.are.equals(15, build.calcsTab.calcsOutput.MeleeAreaOfEffectInc,
            "MeleeAreaOfEffectInc must equal melee-only delta (15), not melee-cfg total (55)")
    end)

    it("Minion bucket aggregates MinionModifier LIST entries by (name,type)", function()
        -- Inject MinionModifier LIST entries directly — this is the same shape
        -- ModParser produces for "+N% increased minion <stat>" affixes. If the
        -- bucket loop is reverted to per-mod inline checks (or any Minion*
        -- output is rewritten as a top-level modDB:Sum), these assertions fail.
        local m = modLib.createMod
        build.configTab.modList:NewMod("MinionModifier", "LIST",
            { mod = m("Life", "INC", 50) }, "Test")
        build.configTab.modList:NewMod("MinionModifier", "LIST",
            { mod = m("Life", "INC", 25) }, "Test")
        build.configTab.modList:NewMod("MinionModifier", "LIST",
            { mod = m("Armour", "INC", 30) }, "Test")
        build.configTab.modList:NewMod("MinionModifier", "LIST",
            { mod = m("FireDamage", "INC", 40) }, "Test")
        build.configTab.modList:NewMod("MinionModifier", "LIST",
            { mod = m("VoidPenetration", "BASE", 12) }, "Test")
        runCallback("OnFrame")

        local out = build.calcsTab.calcsOutput
        assert.are.equals(75, out.MinionLifeInc,
            "MinionLifeInc must aggregate the bucket (50+25); a top-level modDB:Sum returns 0")
        assert.are.equals(30, out.MinionArmourInc,
            "MinionArmourInc must read the (Armour, INC) bucket")
        assert.are.equals(40, out.MinionFireDamageInc,
            "MinionFireDamageInc must read the (FireDamage, INC) bucket")
        assert.are.equals(12, out.MinionVoidPenetration,
            "MinionVoidPenetration must read the (VoidPenetration, BASE) bucket")
    end)

    it("Phase 4 outputs default to 0 with no mods (no character base leak)", function()
        runCallback("OnFrame")
        local out = build.calcsTab.calcsOutput
        -- Sample one output from each Phase 4 sub-area to catch any
        -- accidental constant-base regressions analogous to the historical
        -- PotionSlots `3 + Sum(...)` bug.
        assert.are.equals(0, out.StunChanceInc)
        assert.are.equals(0, out.MeleeStunChanceInc)
        assert.are.equals(0, out.AreaOfEffectInc)
        assert.are.equals(0, out.WardOnHit)
        assert.are.equals(0, out.WardOnCrit)
        assert.are.equals(0, out.HasteEffect)
        assert.are.equals(0, out.FrenzyEffect)
        assert.are.equals(0, out.BleedDamageInc)
        assert.are.equals(0, out.IgniteDamageInc)
        assert.are.equals(0, out.MinionLifeInc)
        assert.are.equals(0, out.MinionArmourInc)
        assert.are.equals(0, out.MinionVoidPenetration)
    end)
end)
