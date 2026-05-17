-- @leb-regression-guard: idol-affix-source-and-formula
-- Locks two paired behaviors:
--   1. Data.lua registers idol base types in itemMods so Item.lua's affix
--      lookup resolves to ModIdol (not ModItem.Item fallback) for idol items.
--   2. Item.lua skips standardAffixEffectModifier subtraction for sealed-
--      corrupted (specialAffixType==6) affixes on idol bases.
--
-- Game-data evidence (2026-05-12): in-game trade screenshots of affix 1070_0
-- "All Resistances for you and your Minions" (ModIdol raw "+5%", sAEM=-0.83):
--   Adorned (aem=-0.05): displayed +4%   → 5 × 0.95 = 4.75 floor
--   Huge    (aem= 0   ): displayed +5%   → 5 × 1.00 = 5
--   Grand/Large (aem=-0.33): displayed +3% → 5 × 0.67 = 3.35 floor
-- sAEM is NOT applied. Throne of Ambition (Adorned Silver Idol) confirmed +4%.
--
-- See REGRESSION_GUARDS.md "idol-affix-source-and-formula".

describe("IdolAffixSourceAndFormula", function()

    local dataSrc, itemSrc
    setup(function()
        local f = io.open("Modules/Data.lua", "r")
        assert.is_not_nil(f, "must open Modules/Data.lua")
        dataSrc = f:read("*a"); f:close()
        f = io.open("Classes/Item.lua", "r")
        assert.is_not_nil(f, "must open Classes/Item.lua")
        itemSrc = f:read("*a"); f:close()
    end)

    it("Data.lua guard comment is present", function()
        assert.is_truthy(string.find(dataSrc,
            "idol-affix-source-and-formula", 1, true),
            "Data.lua must keep the @leb-regression-guard comment")
    end)

    it("Data.lua registers all idol base types in itemMods", function()
        for _, idolType in ipairs({
            "Small Idol", "Minor Idol", "Humble Idol", "Stout Idol",
            "Grand Idol", "Large Idol", "Adorned Idol", "Ornate Idol", "Huge Idol",
        }) do
            assert.is_truthy(string.find(dataSrc, '"' .. idolType .. '"', 1, true),
                "Data.lua must register idol type '" .. idolType .. "' in itemMods")
        end
    end)

    it("Item.lua guard comment is present", function()
        assert.is_truthy(string.find(itemSrc,
            "idol-affix-source-and-formula", 1, true),
            "Item.lua must keep the @leb-regression-guard comment")
    end)

    it("Item.lua gates sAEM subtraction on isIdolBase + corrupted/sealed kind", function()
        -- Detection uses affix.kind ("corrupted" / "sealed") because
        -- ModIdol entries do not carry specialAffixType=6.
        assert.is_truthy(string.find(itemSrc, "skipSaem", 1, true),
            "Item.lua must define a skipSaem flag for the idol sealed/corrupted case")
        assert.is_truthy(string.find(itemSrc,
            'isIdolBase and (affix.kind == "corrupted" or affix.kind == "sealed")', 1, true),
            "Item.lua skipSaem must check affix.kind for corrupted/sealed")
        assert.is_truthy(string.find(itemSrc, "not skipSaem", 1, true),
            "Item.lua sAEM subtraction must be gated on `not skipSaem`")
    end)
end)
