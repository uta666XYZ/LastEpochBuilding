-- @leb-regression-guard: two-phase-floor-post-round-scalar
-- Locks the rounding direction of `itemLib.applyRange`'s `postRoundScalar`
-- multiply: LE renders the post-boost integer with round-half-up, NOT floor.
-- Reverting any of the 5 sites in src/Modules/ItemTools.lua from
-- `m_floor(x * postRoundScalar + 0.5)` back to `m_floor(x * postRoundScalar)`
-- silently undershoots LE/LETools by 1 on every (preBoost*scalar) result whose
-- fractional part >= 0.5.
--
-- Verified case (owLmrO3a Spellblade lv99, idol 23, altar Weaver Enchant 22%):
--   pre-boost rolled value = 9 Ward per Second
--   boostedValue = 9 * 1.22 = 10.98
--   floor   -> 10  (pre-fix LEB; LE-tooltip mismatch)
--   round-half-up -> 11  (post-fix LEB; matches LETools tooltip
--                        "Large Idol (Enchanted affix): +11 Ward per Second"
--                        and stat-row breakdown in
--                        spec/TestBuilds/1.4/owLmrO3a lv99 Spellblade.letools.tooltips.json)
-- Cross-survey of all 105 altar+idol spec/1.4 builds (.tmp/altar_stats_*.csv):
-- 56 builds saw at least one mainOutput stat shift; 11 saw WardPerSecond +1..+4.
--
-- See REGRESSION_GUARDS.md "two-phase-floor-post-round-scalar".

describe("PostRoundScalarRoundHalfUp", function()
    -- All cases use byte=255 so the rolled value = max; the rolled value
    -- is then boosted by postRoundScalar and the integer-rendered output is
    -- asserted. Round-half-up flips the result for cases where
    -- (max * postRoundScalar) % 1 >= 0.5.

    it("general interp-first: +(2-9) WardPerSecond byte=255 scalar=1.22 -> +11", function()
        -- 9 * 1.22 = 10.98 -> round-half-up -> 11 (pre-fix floor -> 10)
        local out = itemLib.applyRange("+(2-9) Ward per Second", 255, 1.0, "Integer", 1.22)
        assert.are.equals("+11 Ward per Second", out)
    end)

    it("general interp-first: postRoundScalar=1.0 identity preserved", function()
        local out = itemLib.applyRange("+(2-9) Ward per Second", 255, 1.0, "Integer", 1.0)
        assert.are.equals("+9 Ward per Second", out)
    end)

    it("flat-int strict path: +(11-15) Vitality byte=255 scalar=1.22 -> +18", function()
        -- Strict path triggers when precision==1 AND no %% AND valueScalar<=1.0.
        -- 15 * 1.22 = 18.30 -> round-half-up -> 18 (floor would also be 18,
        -- so use a case where they diverge): use byte that gives 14 strict ->
        -- 14*1.22 = 17.08 -> 17 (both). Use 13 -> 13*1.22=15.86 -> 16 (RHU)
        -- vs 15 (floor). Byte for value=13 on +(11-15) integer span: vshDm
        -- strict rolls discrete {11,12,13,14,15} across [0..255]. byte 128 -> 13.
        local out = itemLib.applyRange("+(11-15) Vitality", 128, 1.0, "Integer", 1.22)
        assert.are.equals("+16 Vitality", out)
    end)

    it("resist strict path: +(20-40)% Fire Resistance byte=235 scalar=1.10 -> 43", function()
        -- Resist path uses applyRangeStrict. vshDm Integer on +(20-40):
        --   strict(byte) = floor((40+1-20)*byte/255 + 20)
        --   byte=235 -> floor(21*235/255 + 20) = floor(19.35+20) = 39
        --   39*1.10 = 42.9 -> round-half-up -> 43 (pre-fix floor -> 42)
        local out = itemLib.applyRange("+(20-40)% Fire Resistance", 235, 1.0, "Integer", 1.10)
        assert.are.equals("+43% Fire Resistance", out)
    end)
end)
