-- @leb-regression-guard: s4-apathy-per-point-mana-regen-inc
-- Locks the Apathy intrinsic "+2% Mana Regen INC per point" effect wired in
-- CalcSetup.
--
-- Evidence (LE_datamining extracted/localization/properties_localization.json):
--   Property_Player_653_Name: "Attunement Converted to Apathy"
--   Property_Player_653_AltText:
--     "Each point of Apathy grants 2% increased Mana Regeneration and 0.2%
--      of Current Health Lost when you Directly Use a Skill, instead of
--      adding Mana."
--
-- The +2% Mana Regen INC is a built-in property of the Apathy attribute
-- itself, not an affix-level effect. The conversion affix only emits
-- AttunementConvertedToApathy; the per-point regen INC must be applied by
-- the calculator at attribute-init time, mirroring the Guile intrinsic at
-- CalcSetup.lua (s4-guile-per-point-armour-reduction guard).
--
-- The "instead of adding Mana" half is implicitly correct: the +2 Mana
-- intrinsic in CalcSetup routes through PerStat:RawAtt (post-conversion
-- residual Att, 0 when 100% converted), so Apathy contributes no Mana on
-- conversion.
--
-- Affected at v0.14.6 (1 build, G3 aggregate, large negative LEB-LET ManaRegen):
--   BOwJRDdE Shaman Apathy=64  D=-10.28 (LET 30.48, LEB 20.2 pre-fix)
--     8 base * (1 + 153% pre-fix INC) = 20.24
--     8 base * (1 + 281% post-fix INC; +128 from 64 Apathy) = 30.48 — exact.

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("S4ApathyPerPointManaRegenInc", function()
    local calcSetupText

    setup(function()
        calcSetupText = readSource("Modules/CalcSetup.lua")
    end)

    it("CalcSetup wires ManaRegen INC 2 PerStat=Apathy", function()
        assert.is_truthy(string.find(calcSetupText,
            'modDB:NewMod("ManaRegen", "INC", 2, "Apathy", {type = "PerStat", stat = "Apathy"})', 1, true),
            "CalcSetup must register the +2% ManaRegen-per-Apathy intrinsic")
    end)

    it("CalcSetup carries @leb-regression-guard: s4-apathy-per-point-mana-regen-inc marker", function()
        assert.is_truthy(string.find(calcSetupText,
            "@leb-regression-guard: s4-apathy-per-point-mana-regen-inc", 1, true),
            "Intrinsic site must carry the named guard marker")
    end)

    it("intrinsic sits below the 'do-not-remove' inheritance-suppression block", function()
        local doNotRemoveAt = string.find(calcSetupText, "do-not-remove", 1, true)
        local intrinsicAt = string.find(calcSetupText,
            'modDB:NewMod("ManaRegen", "INC", 2, "Apathy"', 1, true)
        assert.is_not_nil(doNotRemoveAt, "do-not-remove anchor must exist")
        assert.is_not_nil(intrinsicAt, "intrinsic line must exist")
        assert.is_true(intrinsicAt > doNotRemoveAt,
            "intrinsic must be added AFTER the s4-converted-attr-no-base-inherit guard block")
    end)

    it("evidence comment references Property_Player_653_AltText", function()
        assert.is_truthy(string.find(calcSetupText,
            "Property_Player_653_AltText", 1, true),
            "Evidence comment must cite the localization key")
    end)

    it("does NOT scale Mana directly off Apathy (the 'instead of adding Mana' rule)", function()
        assert.is_nil(string.find(calcSetupText,
            'modDB:NewMod("Mana", "BASE", 2, "Apathy"', 1, true),
            "Must not add +2 Mana per Apathy — Apathy explicitly REPLACES the per-Attunement Mana grant")
        assert.is_nil(string.find(calcSetupText,
            'modDB:NewMod("Mana", "BASE", 2, "Attunement", {type = "PerStat", stat = "Apathy"})', 1, true),
            "Must not route the +2 Mana-per-Att intrinsic via Apathy")
    end)
end)
