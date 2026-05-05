-- @leb-regression-guard: potion-slots-no-character-base
-- Locks the contract that `output.PotionSlots` has no character/class base
-- and equals exactly the sum of `+N Potion Slots` BASE mods (belt implicit,
-- sealed, crafted). Reverting CalcDefence.lua:~1404 to `K + modDB:Sum(...)`
-- (any non-zero constant K) immediately fails the first assertion below.
-- See REGRESSION_GUARDS.md "potion-slots-no-character-base".

describe("PotionSlots", function()
    before_each(function()
        newBuild()
    end)

    it("PotionSlots has no character base (default = 0 with no mods)", function()
        runCallback("OnFrame")
        assert.are.equals(0, build.calcsTab.calcsOutput.PotionSlots)
    end)

    it("PotionSlots equals sum of '+N Potion Slots' BASE mods (3)", function()
        build.configTab.input.customMods = [[
        +3 Potion Slots
        ]]
        build.configTab:BuildModList()
        runCallback("OnFrame")
        assert.are.equals(3, build.calcsTab.calcsOutput.PotionSlots)
    end)

    it("PotionSlots stacks BASE mods additively (3 + 2 = 5)", function()
        build.configTab.input.customMods = [[
        +3 Potion Slots
        +2 Potion Slots
        ]]
        build.configTab:BuildModList()
        runCallback("OnFrame")
        assert.are.equals(5, build.calcsTab.calcsOutput.PotionSlots)
    end)
end)
