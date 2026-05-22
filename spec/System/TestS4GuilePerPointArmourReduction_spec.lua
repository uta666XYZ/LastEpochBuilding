-- @leb-regression-guard: s4-guile-per-point-armour-reduction
-- Locks the Guile intrinsic "-1% Armour per point" effect wired in CalcSetup.
--
-- Evidence (LE_datamining extracted/localization/properties_localization.json):
--   Property_Player_652_Name: "Dexterity Converted to Guile"
--   Property_Player_652_AltText:
--     "Each point of Guile grants 0.3% increased Cooldown Recovery Speed for
--      Movement Skills and 1% Reduced Armor, instead of granting dodge rating."
--
-- The "1% Reduced Armor per Guile" is a built-in property of the Guile
-- attribute itself, not an affix-level effect. The conversion affixes (1085_*)
-- only emit DexterityConvertedToGuile; the per-point armour reduction must be
-- applied by the calculator at attribute-init time, same place as the
-- Strength→+4% Armour intrinsic at CalcSetup.lua L732.
--
-- Affected at v0.14.6 (3 builds, all positive LEB-LET Armour delta):
--   QJWMRv53 Bladedancer  Guile=207  D=+920 (LET -260, LEB 660 pre-fix)
--   Qqwv6zGN Druid        D=+301
--   Qdz2yXN3 Necromancer  D=+253

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("S4GuilePerPointArmourReduction", function()
    local calcSetupText

    setup(function()
        calcSetupText = readSource("Modules/CalcSetup.lua")
    end)

    it("CalcSetup wires Armour INC -1 PerStat=Guile", function()
        assert.is_truthy(string.find(calcSetupText,
            'modDB:NewMod("Armour", "INC", -1, "Guile", {type = "PerStat", stat = "Guile"})', 1, true),
            "CalcSetup must register the -1% Armour-per-Guile intrinsic")
    end)

    it("CalcSetup carries @leb-regression-guard: s4-guile-per-point-armour-reduction marker", function()
        assert.is_truthy(string.find(calcSetupText,
            "@leb-regression-guard: s4-guile-per-point-armour-reduction", 1, true),
            "Intrinsic site must carry the named guard marker")
    end)

    it("intrinsic sits below the 'do-not-remove' inheritance-suppression block", function()
        local doNotRemoveAt = string.find(calcSetupText, "do-not-remove", 1, true)
        local intrinsicAt = string.find(calcSetupText,
            'modDB:NewMod("Armour", "INC", -1, "Guile"', 1, true)
        assert.is_not_nil(doNotRemoveAt, "do-not-remove anchor must exist")
        assert.is_not_nil(intrinsicAt, "intrinsic line must exist")
        assert.is_true(intrinsicAt > doNotRemoveAt,
            "intrinsic must be added AFTER the s4-converted-attr-no-base-inherit guard block")
    end)

    it("evidence comment references Property_Player_652_AltText", function()
        assert.is_truthy(string.find(calcSetupText,
            "Property_Player_652_AltText", 1, true),
            "Evidence comment must cite the localization key")
    end)

    it("does NOT re-introduce the suppressed +4% Armour PerStat=Brutality inheritance", function()
        assert.is_nil(string.find(calcSetupText,
            'modDB:NewMod("Armour", "INC", 4, "Strength", {type = "PerStat", stat = "Brutality"})', 1, true),
            "Must not re-introduce the s4-converted-attr-no-base-inherit regression")
        assert.is_nil(string.find(calcSetupText,
            'modDB:NewMod("Armour", "INC", 4, "Brutality"', 1, true),
            "Must not re-introduce +4% Armour scaling off Brutality directly")
    end)
end)
