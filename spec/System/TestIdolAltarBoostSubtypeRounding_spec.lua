-- @leb-regression-guard: idol-altar-boost-subtype-rounding
-- Locks the subtype-dependent rounding rule for Idol Altar refracted-slot
-- post-round boost (LE SimpleBlessingType property 4
-- `EffectOfIdolEnchantsInRefractedSlots`):
--   IdolEnchantment (SpecialAffixType=4) → round-half-up
--   IdolWeaver      (SpecialAffixType=5) → floor
--
-- Triangulation evidence:
--   * BxvJP3g1 lv99 Necromancer (g1) with Altar +46% boost:
--       Many Threads raw 6 → LETools 8 = floor(6×1.46)        (IdolWeaver)
--       Chitin       raw 12 → LETools 17 = floor(12×1.46)     (IdolWeaver)
--   * owLmrO3a Heretical Large Arcane Idol Ward per Second, raw 9, boost 1.22:
--       → LETools 11 = floor(9×1.22 + 0.5)                    (IdolEnchantment)
--
-- See REGRESSION_GUARDS.md "idol-altar-boost-subtype-rounding" and Obsidian
-- note "Idol Altar boost rounding 仕様" (Development folder).

describe("IdolAltarBoostSubtypeRounding", function()
    it("IdolWeaver path produces floor result on Many Threads ground truth", function()
        -- "+(4-6)% Elemental Resistance" at byte=255 → 6, boost 1.46:
        --   floor(6*1.46)            = 8   (IdolWeaver, expected)
        --   floor(6*1.46 + epsilon)  = 9   (IdolEnchantment)
        local roundOut = itemLib.applyRange("+(4-6)% Elemental Resistance", 255, 1.0, nil, 1.46, false)
        local floorOut = itemLib.applyRange("+(4-6)% Elemental Resistance", 255, 1.0, nil, 1.46, true)
        assert.is_truthy(string.find(floorOut, "8", 1, true),
            "IdolWeaver+Altar 1.46 on raw 6 must produce 8 (floor), got: " .. tostring(floorOut))
        assert.is_truthy(string.find(roundOut, "9", 1, true),
            "IdolEnchantment+Altar 1.46 on raw 6 must produce 9 (round-half-up), got: " .. tostring(roundOut))
    end)

    it("IdolWeaver path produces floor result on Chitin ground truth", function()
        -- "+(9-12)% Physical Resistance" at byte=255 → 12, boost 1.46:
        --   floor(12*1.46)           = 17  (IdolWeaver, expected)
        --   floor(12*1.46 + 0.5)     = 18  (IdolEnchantment)
        local roundOut = itemLib.applyRange("+(9-12)% Physical Resistance", 255, 1.0, nil, 1.46, false)
        local floorOut = itemLib.applyRange("+(9-12)% Physical Resistance", 255, 1.0, nil, 1.46, true)
        assert.is_truthy(string.find(floorOut, "17", 1, true),
            "IdolWeaver+Altar 1.46 on raw 12 must produce 17 (floor), got: " .. tostring(floorOut))
        assert.is_truthy(string.find(roundOut, "18", 1, true),
            "IdolEnchantment+Altar 1.46 on raw 12 must produce 18 (round-half-up), got: " .. tostring(roundOut))
    end)

    it("CalcSetup tags IdolWeaver affixes with postRoundFloor", function()
        local f = io.open("Modules/CalcSetup.lua", "r")
        local src = f:read("*a"); f:close()
        assert.is_truthy(string.find(src,
            'if sat == "IdolWeaver" then',
            1, true),
            "CalcSetup must branch on IdolWeaver subtype")
        assert.is_truthy(string.find(src,
            'affix.postRoundFloor = true',
            1, true),
            "CalcSetup must set affix.postRoundFloor for IdolWeaver")
    end)

    it("Item.lua plumbs postRoundFloor through Craft → writeModLine → ParseRaw → applyRange", function()
        local f = io.open("Classes/Item.lua", "r")
        local src = f:read("*a"); f:close()
        assert.is_truthy(string.find(src, "modLine.postRoundFloor = true", 1, true),
            "Craft must propagate affix.postRoundFloor → modLine.postRoundFloor")
        assert.is_truthy(string.find(src, '"{postFloor:1}"', 1, true),
            "writeModLine must serialize postFloor directive")
        assert.is_truthy(string.find(src, 'k == "postFloor"', 1, true),
            "ParseRaw must deserialize postFloor directive")
        assert.is_truthy(string.find(src, "modLine.postRoundFloor)", 1, true),
            "applyRange call must pass modLine.postRoundFloor")
    end)
end)
