-- @leb-regression-guard:pen-affix-vshdm-strict
-- Validation provenance is retained in maintainer notes.

describe("TestPenAffixVshdmStrict", function()
    -- HeadlessWrapper.lua already sets itemLib.useLEToolsRounding = true and
    -- exposes itemLib as a global. No additional setup required.

    it("Plague Bearer's Staff 'of the Scorpio' T4 (9-12) byte=140 scalar=1.829 → 19 (in-game EXACT)", function()
        local result = itemLib.applyRange("+(9-12)% Poison Penetration", 140, 1.829)
        assert.are.equals("+19% Poison Penetration", result)
    end)

    it("strict endpoint-first arithmetic gives 19 where legacy interpolate-first gave 20", function()
        -- Direct strict-function assertion (the legacy path is not exposed as a
        -- separate function; its closed form is documented above: 20).
        assert.are.equals(19, itemLib.applyRangeStrict(9, 12, 140, 1.829, 0, 0))
    end)

    it("the affix's paired 'Minion Poison Penetration' line routes identically → 19", function()
        -- Affix 725 carries both lines with the same roll byte; the in-game
        -- tooltip shows the same value on both.
        local result = itemLib.applyRange("+(9-12)% Minion Poison Penetration", 140, 1.829)
        assert.are.equals("+19% Minion Poison Penetration", result)
    end)

    it("'with Bleed' suffixed family pen line IS routed (same flat-% shape)", function()
        local result = itemLib.applyRange("+(9-12)% Physical Penetration with Bleed", 140, 1.829)
        assert.are.equals("+19% Physical Penetration with Bleed", result)
    end)

    it("scalar 1.0 is unchanged vs legacy (identical by construction)", function()
        -- Both formulas reduce to floor((max+1-min) × roll/255 + min) clamped
        -- at max when endpoints are integers and scalar is 1.0.
        -- (9-12) byte=140: floor(9 + 140/255 × 4) = floor(11.196) = 11
        assert.are.equals("+11% Poison Penetration",
            itemLib.applyRange("+(9-12)% Poison Penetration", 140, 1.0))
        -- (2-4) byte=200: floor(2 + 200/255 × 3) = floor(4.35) = 4
        assert.are.equals("4% Physical Penetration",
            itemLib.applyRange("(2-4)% Physical Penetration", 200, 1.0))
        -- top byte clamps at max on both paths
        assert.are.equals("+12% Poison Penetration",
            itemLib.applyRange("+(9-12)% Poison Penetration", 255, 1.0))
    end)

    it("relative '% increased Poison Penetration' line is NOT routed (useRound legacy path)", function()
        -- byte=200 diverges: legacy useRound round-half-up
        --   round(9 + 200/255 × (12-9)) = round(11.35) = 11
        -- strict would give floor((12+1-9) × 200/255 + 9) = floor(12.14) = 12.
        local result = itemLib.applyRange("(9-12)% increased Poison Penetration", 200, 1.0)
        assert.are.equals("11% increased Poison Penetration", result)
    end)

    it("Salt the Wound 'Converted to ... Penetration' conversion rate is NOT routed", function()
        -- The rolled percent is a conversion rate, not a pen roll. byte=140
        -- scalar=1.829 diverges: legacy floor((40 + 140/255 × 11) × 1.829) = 84;
        -- strict would give floor((banker(91.45)+1-banker(73.16)) × 140/255
        -- + banker(73.16)) = floor(19 × 0.549 + 73) = 83.
        local result = itemLib.applyRange(
            "(40-50)% of added Critical Strike Multiplier Converted to Poison Penetration with Poison",
            140, 1.829)
        assert.are.equals(
            "84% of added Critical Strike Multiplier Converted to Poison Penetration with Poison",
            result)
    end)
end)
