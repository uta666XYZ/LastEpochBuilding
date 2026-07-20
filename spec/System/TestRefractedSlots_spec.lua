-- @leb-regression-guard: refracted-slot-overlap-only
-- @leb-regression-guard: refracted-display-not-omen-capacity
-- Locks the contract for ItemsTab:AutoPopulateOmenIdolSlots:
--   * Only idols whose footprint overlaps a Refracted (grid type=2) cell
--     are placed in Omen Idol slots (refracted-slot-overlap-only).
--   * EVERY overlapping idol is placed, up to MAX_OMEN_IDOL_SLOTS — the
--     display is NOT capped by the altar's Omen Idol capacity. A Refracted
--     Slot (altar grid cell) and Omen Idol capacity (MaximumOmenIdols) are
--     distinct concepts (refracted-display-not-omen-capacity).
-- See REGRESSION_GUARDS.md "refracted-slot-overlap-only" and
-- "refracted-display-not-omen-capacity".

describe("TestRefractedSlots", function()
    local itemsTab

    before_each(function()
        newBuild()
        itemsTab = build.itemsTab
        -- Use Archaic Altar for its known Refracted cells: (1,3) and (5,3).
        itemsTab.activeAltarLayout = "Archaic Altar"
        -- Force baseline capacity = 1 (Archaic Altar's omenIdolCapacity), no
        -- bonus from MaximumOmenIdols by default. Each test overrides as needed.
    end)

    -- Helper: drop a fake idol of given type onto the given Idol N slot.
    -- type values are real entries in idolSize: "Grand Idol" = 3x1 (cols x rows),
    -- "Large Idol" = 1x3, "Small Idol" = 1x1, etc.
    local nextItemId = 1000
    local function placeIdol(idolSlotN, idolType)
        nextItemId = nextItemId + 1
        local id = nextItemId
        itemsTab.items[id] = { type = idolType }
        local slot = itemsTab.slots["Idol " .. idolSlotN]
        assert.is_not_nil(slot, "Idol " .. idolSlotN .. " slot must exist")
        slot.selItemId = id
        return id
    end

    local function omenIdolItemId(n)
        local s = itemsTab.slots["Omen Idol " .. n]
        return s and s.selItemId or 0
    end

    local function setCapacityBonus(bonus)
        -- Stub GetOmenIdolCapacityBonus so we don't depend on parsing affixes.
        itemsTab.GetOmenIdolCapacityBonus = function() return bonus end
    end

    it("places Grand Idol at (1,2) into Omen Idol 1 (covers refracted cell (1,3))", function()
        setCapacityBonus(0)
        -- Idol 1 = grid (1,2); Grand = 3x1 -> covers (1,2)(1,3)(1,4).
        local id = placeIdol(1, "Grand Idol")
        itemsTab:AutoPopulateOmenIdolSlots()
        assert.are.equals(id, omenIdolItemId(1))
        assert.are.equals(0, omenIdolItemId(2))
    end)

    it("excludes idols that do not touch any refracted cell", function()
        setCapacityBonus(0)
        -- Idol 4 = grid (2,1); Large = 1x3 -> covers (2,1)(3,1)(4,1). No refracted overlap.
        placeIdol(4, "Large Idol")
        itemsTab:AutoPopulateOmenIdolSlots()
        assert.are.equals(0, omenIdolItemId(1))
    end)

    it("with capacity 2, places Idol 1 and Idol 18 (both overlap), skips non-overlapping Idol 4", function()
        setCapacityBonus(1)  -- 1 base + 1 bonus = 2 capacity
        local id1  = placeIdol(1,  "Grand Idol")  -- (1,2) 3x1 -> hits (1,3) ✓
        local _id4 = placeIdol(4,  "Large Idol")  -- (2,1) 1x3 -> no hit
        local id18 = placeIdol(18, "Grand Idol")  -- (5,2) 3x1 -> hits (5,3) ✓
        itemsTab:AutoPopulateOmenIdolSlots()
        assert.are.equals(id1,  omenIdolItemId(1))
        assert.are.equals(id18, omenIdolItemId(2))
        assert.are.equals(0,    omenIdolItemId(3))
    end)

    it("displays ALL overlapping idols even when they exceed Omen capacity", function()
        -- refracted-display-not-omen-capacity: capacity=1 must NOT hide the 2nd
        -- refracted idol. The Refracted N display shows every overlapping idol;
        -- the EquippedOmenIdol stat is clamped to capacity separately (CalcSetup).
        setCapacityBonus(0)  -- Omen capacity = 1
        local id1  = placeIdol(1,  "Grand Idol")  -- hits refracted, idol# 1
        local id18 = placeIdol(18, "Grand Idol")  -- hits refracted, idol# 18
        itemsTab:AutoPopulateOmenIdolSlots()
        assert.are.equals(id1,  omenIdolItemId(1))
        assert.are.equals(id18, omenIdolItemId(2))  -- shown despite capacity=1
        assert.are.equals(0,    omenIdolItemId(3))
    end)

    it("clears stale Omen Idol entries when no altar is active", function()
        setCapacityBonus(0)
        -- Pre-seed Omen Idol slot 1 with stale data.
        itemsTab.slots["Omen Idol 1"].selItemId = 9999
        itemsTab.activeAltarLayout = "Default"
        itemsTab:AutoPopulateOmenIdolSlots()
        assert.are.equals(0, omenIdolItemId(1))
    end)
end)
