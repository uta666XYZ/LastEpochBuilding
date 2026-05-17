-- @leb-regression-guard:dodge-more-multiplier
-- Locks two coupled invariants for displayed Dodge Rating (output.Evasion):
--   (1) parser site: "(multiplicative with other modifiers)" must be stripped
--       so parseMod returns no `extra` residue. PassiveTree.lua skips mods
--       whose parse left non-empty extra (`if mod.list and not mod.extra`),
--       so without the strip the Bladedancer ascendancy "15% more dodge
--       rating (multiplicative with other modifiers)" silently never reaches
--       modDB.
--   (2) display site: CalcDefence.lua must compute Evasion as
--       BASE × (1+INC) × MORE (i.e. calcLib.mod) to match the LETools planner.
--       An earlier version used INC only and dropped 15%-MORE class ascendancy
--       and item bonuses from the displayed value.
--
-- Establishing observation: o3Zl6gkV lv100 Bladedancer
--   pre-fix  Evasion=2616 (LE 3236, Δ=-620; 15% MORE missing AND not applied)
--   post-fix Evasion=3009 (LE 3236, Δ=-227; 15% MORE present and applied)
--
-- See REGRESSION_GUARDS.md > dodge-more-multiplier.

describe("TestDodgeMoreMultiplier", function()
    before_each(function()
        newBuild()
    end)

    it("parser strips '(multiplicative with other modifiers)' suffix and emits MORE Evasion", function()
        build.configTab.input.customMods = "15% more dodge rating (multiplicative with other modifiers)"
        build.configTab:BuildModList()
        runCallback("OnFrame")
        -- The MORE Evasion mod must reach modDB even though the parenthetical
        -- clarification follows the recognised modifier text.
        local moreSum = build.configTab.modList:Sum("MORE", nil, "Evasion")
        assert.are.equals(15, moreSum,
            "15% more dodge rating must produce MORE=+15 Evasion (parser strip layer)")
    end)

    it("displayed Evasion applies BASE × (1+INC) × MORE", function()
        -- 100 BASE × (1 + 50%) × (1 + 15%) = 172.5 → rounded 173
        build.configTab.input.customMods = "+100 Dodge Rating\n\z
        50% Increased Dodge Rating\n\z
        15% more dodge rating (multiplicative with other modifiers)"
        build.configTab:BuildModList()
        build.buildFlag = true
        runCallback("OnFrame")
        local evasion = build.calcsTab.calcsOutput.Evasion
        assert.are.equals(173, evasion,
            "Evasion must be BASE×(1+INC)×MORE = 100×1.5×1.15 = 173, not the INC-only 150")
    end)

    it("INC-only path still works when no MORE source is present", function()
        -- 100 BASE × (1 + 50%) × 1 = 150
        build.configTab.input.customMods = "+100 Dodge Rating\n\z
        50% Increased Dodge Rating"
        build.configTab:BuildModList()
        build.buildFlag = true
        runCallback("OnFrame")
        assert.are.equals(150, build.calcsTab.calcsOutput.Evasion,
            "Without MORE the formula must still yield BASE×(1+INC) = 150")
    end)
end)
