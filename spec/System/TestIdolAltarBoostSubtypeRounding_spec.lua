-- @leb-regression-guard: idol-altar-boost-subtype-rounding
-- Locks that ALL Idol Altar refracted-slot post-round boosts use ROUND-HALF-UP,
-- regardless of which property (1/2/3 or 4) or subtype (Standard / IdolWeaver /
-- IdolEnchantment) drives them.
--
-- HISTORY: an earlier revision claimed property 4 (`EffectOfIdolEnchants
-- InRefractedSlots`) floored. That was a MISDIAGNOSIS — it rested on an
-- unverified <private build> "Many Threads raw 6 -> 8" claim, but <private build>'s altar
-- has NO property-4 mod, so weaverBoost is always 0 there and the floor branch
-- could never fire. The floor override has been removed from CalcSetup.
--
-- Ground truth (round-half-up):
--   * <private build> lv99 Spellblade Large Enchanted Idol 897_4 "+(2-9) Ward per
--     Second" rolled 9, property 4 = +22%: 9*1.22 = 10.98 -> round-half-up 11
--     (matches LETools tooltip "+11 Ward per Second"); floor would give 10.
--   * ShutFackUp lv85 Spellblade IdolEnchantment crit-multi suffix 892_3 base
--     6, property 4 = +23%: 6*1.23 = 7.38 -> round-half-up 7 (in-game +7);
--     floor would also give 7 here, but the global crit-multi match (227%)
--     requires +7, which round-half-up + property-4-only routing produces.
--
-- See TestPostRoundScalarRoundHalfUp_spec (105-build cross-survey),
-- TestIdolRefractedStandardBoostAllSubtypes_spec (subtype routing), and
-- REGRESSION_GUARDS.md "idol-altar-boost-subtype-rounding".

describe("IdolAltarBoostSubtypeRounding", function()
    it("property-4 boost rounds half-up on owLmrO3a Ward ground truth", function()
        -- rolled 9, boost 1.22: round-half-up = 11 (in-game / LETools), floor = 10
        local out = itemLib.applyRange("+(2-9) Ward per Second", 255, 1.0, "Integer", 1.22)
        assert.are.equals("+11 Ward per Second", out)
    end)

    it("property-4 boost rounds half-up on ShutFackUp crit-multi ground truth", function()
        -- rolled 6, boost 1.23: round-half-up = 7 (in-game +7)
        local out = itemLib.applyRange("+(2-6)% Critical Strike Multiplier", 255, 1.0, nil, 1.23)
        assert.is_truthy(string.find(out, "7", 1, true),
            "6 * 1.23 = 7.38 must round-half-up to 7, got: " .. tostring(out))
    end)

    it("CalcSetup sets NO postRoundFloor for altar boosts (all round-half-up)", function()
        local f = io.open("Modules/CalcSetup.lua", "r")
        local src = f:read("*a"); f:close()
        assert.is_falsy(string.find(src, "weaverBoost%s*>%s*0%s+and%s+stdBoost%s*==%s*0"),
            "the misdiagnosed property-4-only floor branch must be removed from CalcSetup")
        assert.is_falsy(string.find(src, 'if sat == "IdolWeaver" then'),
            "the older subtype-only `if sat == \"IdolWeaver\" then` floor gate must also be gone")
    end)
end)
