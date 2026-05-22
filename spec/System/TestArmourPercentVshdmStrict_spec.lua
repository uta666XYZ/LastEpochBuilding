-- @leb-regression-guard:armour-percent-vshdm-strict
-- @leb-regression-guard:armour-percent-refracted-fractional
-- Locks the LE-faithful vshDm path for player "% increased/reduced Armour"
-- rolls, AND the refracted-slot prefix-boost fractional-retention exception.
--
-- Triangulated on ImPalmBeachPete lv48 Bladedancer (offline save BETA_12)
-- vs in-game tooltips:
--   Azure/Manafused Outcast Hat of Defense "(10-12)% increased Armor" byte=185
--     legacy floor : floor(10 + 185/255 × (12-10)) = 11  (LEB, wrong)
--     strict vshDm : floor((12+1-10) × 185/255 + 10) = 12 (in-game ✓)
--   Armored Minor Weaver Idol "(2-5)% increased Armor" byte=84
--     legacy floor : floor(2 + 84/255 × (5-2))      = 2   (LEB, wrong)
--     strict vshDm : floor((5+1-2) × 84/255 + 2)     = 3   (in-game ✓)
--
-- Refracted-slot prefix boost (Sunrise Visage Altar sealed +44% Effect of
-- Prefixes in Refracted Slots, postRoundScalar=1.44) on the idol's 3% roll:
-- LE keeps `increased*` as a float fraction, so the boosted value is NOT
-- re-rounded to an integer: 3 × 1.44 = 4.32 (NOT 4). With that fraction the
-- character-sheet Armour = round(232 × (1 + 81.32/100)) = round(420.66) = 421,
-- matching in-game; integer-rounding to 4 gave 419.92 → 420 (off by one).
-- This DIFFERS from the flat-additive two-phase path (Mana/res/Ward), which
-- keeps integer round-half-up/floor and is ZombieWarehouse-ground-truth-
-- verified — that path must stay intact.
--
-- Reverting the dispatcher in src/Modules/ItemTools.lua applyRange will flip
-- these back to off-by-one (strict cases) or collapse 4.32→4 (fractional case)
-- and fail this spec.

describe("TestArmourPercentVshdmStrict", function()
    -- HeadlessWrapper.lua exposes itemLib as a global and flips
    -- useLEToolsRounding=true; applyRangeStrict ignores that flag (pure fn).

    it("Hat (10-12) byte=185 → 12 (in-game)", function()
        local result = itemLib.applyRange("(10-12)% increased Armor", 185, 1.0)
        assert.are.equals("12% increased Armor", result)
    end)

    it("Idol (2-5) byte=84 → 3 (in-game)", function()
        local result = itemLib.applyRange("(2-5)% increased Armor", 84, 1.0)
        assert.are.equals("3% increased Armor", result)
    end)

    it("British 'Armour' spelling routes through the same strict path", function()
        local result = itemLib.applyRange("(10-12)% increased Armour", 185, 1.0)
        assert.are.equals("12% increased Armour", result)
    end)

    it("'% reduced Armor' also routes through strict path", function()
        local result = itemLib.applyRange("(10-12)% reduced Armor", 185, 1.0)
        assert.are.equals("12% reduced Armor", result)
    end)

    it("refracted prefix boost (×1.44) keeps the fraction: 3 → 4.32 (NOT 4)", function()
        -- args: (line, range, valueScalar, rounding, postRoundScalar, postRoundFloor)
        local result = itemLib.applyRange("(2-5)% increased Armor", 84, 1.0, 0, 1.44, false)
        assert.are.equals("4.32% increased Armor", result)
        assert.are_not.equals("4% increased Armor", result)
    end)

    it("property-4 (weaver-enchant) boost still FLOORS the % value", function()
        -- postRoundFloor=true → floor(3 × 1.46) = 4 (integer, no fraction)
        local result = itemLib.applyRange("(2-5)% increased Armor", 84, 1.0, 0, 1.46, true)
        assert.are.equals("4% increased Armor", result)
    end)

    it("Minion Armor is EXCLUDED from the fractional player branch", function()
        -- A refracted boost on "% increased Minion Armor" must not produce a
        -- fractional player-scope value (no decimal point in the result).
        local result = itemLib.applyRange("(20-30)% increased Minion Armor", 186, 1.0, 0, 1.44, false)
        assert.is_nil(tostring(result):find("%."))
    end)
end)
