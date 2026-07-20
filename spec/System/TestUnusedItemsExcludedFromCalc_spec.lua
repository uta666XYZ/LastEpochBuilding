-- @leb-regression-guard: unused-items-excluded-from-calc
-- Locks the contract that items present in the item list but NOT assigned to an
-- equipment slot ("unused" items) are EXCLUDED from the DPS/defence calculation,
-- while still being kept in the item list so they show as unused.
--
-- Why: offline-save import (loadBuildFromJSON) reads EVERY item in the save --
-- equipped (containerID -> a slot via slotMap) AND inventory/stash (containerID=1,
-- no slot). Inventory items (e.g. boss-swap gear / spare idols the player keeps in
-- the bag) must be listed-but-unused, NOT folded into the character's stats. The
-- calc only ever reads `build.itemsTab.orderedSlots` -> `items[slotName]`
-- (CalcSetup.lua ~L979), so an item that is in `itemsTab.items` but in no slot is
-- never seen by the calc. This test pins that: a huge +Health item added as unused
-- changes nothing, even though the SAME +Health via customMods clearly would.
--
-- User request 2026-07-04: keep the "show inventory items as unused" convenience,
-- but guarantee they are not in the DPS calc.

describe("UnusedItemsExcludedFromCalc", function()
    before_each(function()
        newBuild()
    end)

    it("an item in the list but not in a slot (unused) is excluded from the calc; the item is still kept and parsed", function()
        build.buildFlag = true
        runCallback("OnFrame")
        local baseLife = build.calcsTab.calcsOutput.Life

        -- POSITIVE CONTROL: the calc DOES respond to +5000 Health (so a later
        -- "no change" from an unused item is meaningful, not Health being ignored).
        build.configTab.input.customMods = "+5000 Health"
        build.configTab:BuildModList()
        build.buildFlag = true
        runCallback("OnFrame")
        assert.is_true(build.calcsTab.calcsOutput.Life >= baseLife + 5000,
            "sanity: +5000 Health via customMods must raise Life")
        build.configTab.input.customMods = ""
        build.configTab:BuildModList()
        build.buildFlag = true
        runCallback("OnFrame")
        assert.are.equal(baseLife, build.calcsTab.calcsOutput.Life)

        -- Build a REAL body-armour item carrying the SAME +5000 Health and add it
        -- as UNUSED (noAutoEquip = true -> not placed in any slot).
        build.itemsTab:CreateDisplayItemFromRaw("Rarity: RARE\nTest Plate\nCopper Plate\nImplicits: 0\n+5000 Health")
        local item = build.itemsTab.displayItem
        assert.is_not_nil(item, "display item should be created")
        -- The item is genuinely parsed (its modList carries the +5000 Health)...
        local healthOnItem = 0
        for _, mod in ipairs(item.modList) do
            if mod.name == "Life" and mod.type == "BASE" then healthOnItem = healthOnItem + mod.value end
        end
        assert.are.equal(5000, healthOnItem)

        build.itemsTab:AddDisplayItem(true) -- noAutoEquip = true => UNUSED
        build.buildFlag = true
        runCallback("OnFrame")

        -- ...it is kept in the item list (so it shows as an unused item)...
        assert.is_not_nil(build.itemsTab.items[item.id], "unused item must stay in the list")
        -- ...it occupies no equipment slot...
        local inASlot = false
        for _, slot in pairs(build.itemsTab.slots) do
            if slot.selItemId == item.id then inASlot = true end
        end
        assert.is_false(inASlot, "unused item must not be in any slot")
        -- ...and it does NOT affect the calc (Life unchanged from baseline).
        assert.are.equal(baseLife, build.calcsTab.calcsOutput.Life)

        -- Deleting unused items is a no-op for the calc too.
        build.itemsTab:DeleteUnused()
        build.buildFlag = true
        runCallback("OnFrame")
        assert.are.equal(baseLife, build.calcsTab.calcsOutput.Life)
    end)
end)
