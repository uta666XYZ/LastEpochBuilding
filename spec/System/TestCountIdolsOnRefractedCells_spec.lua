-- @leb-regression-guard: refracted-count-independent-of-omen-capacity
-- Locks the contract for ItemsTab:CountIdolsOnRefractedCells (which drives the
-- Multiplier:IdolInRefractedSlot scaling for "+N per Idol in a Refracted Slot"
-- affixes):
--   * It counts EVERY distinct idol whose grid footprint overlaps a Refracted
--     (grid type=2) cell on the active altar.
--   * The count is INDEPENDENT of omenIdolCapacity / MaximumOmenIdols. A
--     Refracted Slot (an altar-grid cell) and an Omen Idol slot (a capped idol
--     category) are different concepts; refracted-overlap count must NOT be
--     gated by Omen Idol capacity.
--   * Multi-cell idols are counted once (dedup by itemId).
--
-- Why this guard exists: the "Refracted N" dropdown and AutoPopulateOmenIdolSlots
-- ARE capped at omenIdolCapacity (see refracted-slot-overlap-only). Twice the
-- refracted-overlap count was wrongly assumed to be capped at omenIdolCapacity
-- too, producing an undercounted IdolInRefractedSlot multiplier. This spec pins
-- the decoupling: capacity=1 but two overlapping idols => count == 2.
-- See REGRESSION_GUARDS.md "refracted-count-independent-of-omen-capacity" and
-- Obsidian "Refracted Slot vs Omen Idol vs Omen Idol Capacity 区別".

describe("TestCountIdolsOnRefractedCells", function()
    local itemsTab

    before_each(function()
        newBuild()
        itemsTab = build.itemsTab
        -- Archaic Altar has Refracted cells at (1,3) and (5,3); omenIdolCapacity = 1.
        itemsTab.activeAltarLayout = "Archaic Altar"
    end)

    local nextItemId = 2000
    local function placeIdol(idolSlotN, idolType)
        nextItemId = nextItemId + 1
        local id = nextItemId
        itemsTab.items[id] = { type = idolType }
        local slot = itemsTab.slots["Idol " .. idolSlotN]
        assert.is_not_nil(slot, "Idol " .. idolSlotN .. " slot must exist")
        slot.selItemId = id
        return id
    end

    it("counts a single overlapping idol", function()
        -- Idol 1 = grid (1,2); Grand = 3x1 -> covers (1,2)(1,3)(1,4) -> hits (1,3).
        placeIdol(1, "Grand Idol")
        assert.are.equals(1, itemsTab:CountIdolsOnRefractedCells())
    end)

    it("excludes idols that touch no refracted cell", function()
        -- Idol 4 = grid (2,1); Large = 1x3 -> covers (2,1)(3,1)(4,1). No refracted overlap.
        placeIdol(4, "Large Idol")
        assert.are.equals(0, itemsTab:CountIdolsOnRefractedCells())
    end)

    it("counts ALL overlapping idols, NOT capped by omenIdolCapacity (=1)", function()
        -- Two distinct idols both overlap refracted cells while capacity is 1.
        -- Refracted count must be 2.
        itemsTab.GetOmenIdolCapacityBonus = function() return 0 end -- capacity = 1
        placeIdol(1, "Grand Idol")   -- (1,2) 3x1 -> hits (1,3)
        placeIdol(18, "Grand Idol")  -- (5,2) 3x1 -> hits (5,3)

        assert.are.equals(2, itemsTab:CountIdolsOnRefractedCells())

        -- AutoPopulate also fills BOTH Omen Idol slots (display shows every
        -- refracted-overlapping idol, NOT capped by omenIdolCapacity=1; guard
        -- refracted-display-not-omen-capacity). The EquippedOmenIdol *stat* is
        -- clamped to capacity separately in CalcSetup (guard
        -- equipped-omen-idol-capped-by-capacity).
        itemsTab:AutoPopulateOmenIdolSlots()
        local filled = 0
        for i = 1, 6 do
            local s = itemsTab.slots["Omen Idol " .. i]
            if s and s.selItemId and s.selItemId ~= 0 then filled = filled + 1 end
        end
        assert.are.equals(2, filled)
    end)

    it("dedups a multi-cell idol so it is counted once", function()
        -- Grand Idol at (1,2) overlaps refracted cell (1,3) across its 3-cell
        -- footprint; it must contribute exactly 1 to the count, not per-cell.
        placeIdol(1, "Grand Idol")
        assert.are.equals(1, itemsTab:CountIdolsOnRefractedCells())
    end)

    it("returns 0 when no altar is active", function()
        placeIdol(1, "Grand Idol")
        itemsTab.activeAltarLayout = "Default"
        assert.are.equals(0, itemsTab:CountIdolsOnRefractedCells())
    end)
end)

-- @leb-regression-guard: equipped-omen-idol-capped-by-capacity
-- Now that AutoPopulateOmenIdolSlots fills EVERY refracted-overlapping idol
-- (uncapped display, guard refracted-display-not-omen-capacity), the raw count
-- of populated "Omen Idol N" slots can exceed the altar's Omen Idol capacity.
-- CalcSetup must clamp Multiplier:EquippedOmenIdol to that capacity so the
-- "+N per Equipped Omen Idol" stat is unchanged by the display change. This is
-- locked via source-text assertions (a full modDB build is heavy here; the
-- per-build snapshots provide the value-level lock).
-- See REGRESSION_GUARDS.md "equipped-omen-idol-capped-by-capacity".
describe("EquippedOmenIdolCappedByCapacity", function()
    local source
    setup(function()
        local f = io.open("Modules/CalcSetup.lua", "r")
        assert.is_not_nil(f, "must be able to open Modules/CalcSetup.lua")
        source = f:read("*a")
        f:close()
    end)

    it("keeps the regression-guard comment so future edits trip review", function()
        assert.is_truthy(string.find(source, "equipped-omen-idol-capped-by-capacity", 1, true),
            "CalcSetup.lua must keep the @leb-regression-guard comment")
    end)

    it("clamps equippedOmenIdolCount to the altar's Omen Idol capacity", function()
        -- Capacity = layout.omenIdolCapacity + GetOmenIdolCapacityBonus(); the
        -- raw populated-slot count is reduced to it before emitting the mod.
        assert.is_truthy(string.find(source, "omenIdolCapacity"),
            "clamp must derive capacity from omenIdolCapacity")
        assert.is_truthy(string.find(source, "GetOmenIdolCapacityBonus"),
            "clamp must add the MaximumOmenIdols affix bonus via GetOmenIdolCapacityBonus")
        assert.is_truthy(string.find(source, "equippedOmenIdolCount%s*>%s*omenCapacity"),
            "clamp must compare equippedOmenIdolCount against omenCapacity")
    end)

    it("still drives IdolInRefractedSlot from the uncapped refracted count", function()
        -- The refracted multiplier must NOT be clamped to omen capacity.
        assert.is_truthy(string.find(source, "Multiplier:IdolInRefractedSlot", 1, true),
            "IdolInRefractedSlot mod must still be emitted")
        assert.is_truthy(string.find(source, "CountIdolsOnRefractedCells", 1, true),
            "IdolInRefractedSlot must be driven by CountIdolsOnRefractedCells (uncapped)")
    end)
end)
