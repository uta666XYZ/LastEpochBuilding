-- @leb-regression-guard: flat-health-refracted-fractional
-- Locks the rounding behavior of a refracted-slot `postRoundScalar` boost
-- applied to a FLAT-additive Health affix: LE retains the boosted value as a
-- float in the Health accumulator (the item tooltip shows the un-boosted
-- integer roll), so LEB must NOT collapse it to an integer in the flat-int
-- strict branch of `itemLib.applyRange` (src/Modules/ItemTools.lua).
--
-- Verified case (ZombieWarehouse lv72 Necromancer, offline save BETA_15):
--   Jumping Spider's Minor Weaver Idol of Repose "+(14-18) Health" byte=3
--   rolls 14. The idol sits on a refracted cell; Sunset Twisted Altar's
--   sealed "+10% Effect of Suffixes for Idols in Refracted Slots" yields
--   postRoundScalar = 1.10, so the boosted contribution = 14 * 1.10 = 15.4.
--     integer round-half-up -> 15  (pre-fix LEB; maxHealth 1106 -> 1504)
--     float retention       -> 15.4 (post-fix; base 1106.4 -> round 1504.704
--                                    = 1505, matching in-game; LETools also
--                                    reports the wrong 1504)
--
-- SCOPE GUARD (critical): this float retention is Health-only. Other flat-
-- additive stats keep integer round-half-up, locked by the sibling guard
-- two-phase-floor-post-round-scalar (Ward per Second 9*1.22=10.98 -> 11;
-- Vitality 13*1.22=15.86 -> 16). The cases below assert BOTH directions so a
-- future broadening of the Health branch to all flat stats fails loudly.
--
-- See REGRESSION_GUARDS.md "flat-health-refracted-fractional".

describe("FlatHealthRefractedFractional", function()
    it("flat Health refracted boost retains float: +(14-18) Health byte=3 scalar=1.10 -> +15.4", function()
        -- applyRangeStrict(14,18,3) = floor(5*3/255 + 14) = 14; 14*1.10 = 15.4
        local out = itemLib.applyRange("+(14-18) Health", 3, 1.0, "Integer", 1.10)
        assert.are.equals("+15.4 Health", out)
    end)

    it("postRoundScalar=1.0 identity: flat Health unboosted stays integer", function()
        local out = itemLib.applyRange("+(14-18) Health", 3, 1.0, "Integer", 1.0)
        assert.are.equals("+14 Health", out)
    end)

    it("scope: flat Vitality refracted boost still integer round-half-up (NOT float)", function()
        -- byte=128 on +(11-15) -> strict 13; 13*1.22 = 15.86 -> round-half-up -> 16
        local out = itemLib.applyRange("+(11-15) Vitality", 128, 1.0, "Integer", 1.22)
        assert.are.equals("+16 Vitality", out)
    end)

    it("scope: Minion Health excluded from float retention", function()
        -- Minion Health is minion-scope, must not pick up the player Health branch.
        local out = itemLib.applyRange("+(14-18) Minion Health", 3, 1.0, "Integer", 1.10)
        assert.are.equals("+15 Minion Health", out)
    end)

    it("scope: Health Regen excluded from float retention", function()
        -- Health Regen is a separate property; keep integer round-half-up.
        local out = itemLib.applyRange("+(6-7) Health Regen", 255, 1.0, "Integer", 1.10)
        -- strict(6,7,255) = floor(2*255/255 + 6) = floor(8) = 8 -> wait span; use byte
        -- giving 7: 7*1.10 = 7.7 -> round-half-up -> 8 (integer, not 7.7)
        assert.are.equals("+8 Health Regen", out)
    end)
end)
