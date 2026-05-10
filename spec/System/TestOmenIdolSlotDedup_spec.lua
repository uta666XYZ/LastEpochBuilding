-- @leb-regression-guard: omen-idol-slot-dedup-on-corruption-count
-- Locks the contract that CalcSetup's corrupted-item counting loop
-- deduplicates idol items that appear under both `Idol N` and
-- `Omen Idol N` slot names. Omen Idol N slots are populated by
-- ItemsTab:AutoPopulateOmenIdolSlots as secondary references to physical
-- idol items already in Idol N grid cells; without dedup the corrupted
-- counter double-tallies and inflates `CorruptedIdolItemsEquipped` plus
-- the sibling `Multiplier:EquippedCorruptedIdol` emission.
--
-- Establishing build: B7GrkJrK lv100 Lich/Reaper. Pre-dedup 16 corrupted
-- idol items, post-dedup 14 (item.id 21 and 30 each duplicate-referenced).
-- Reaper Mana 1548 → 1526 matches LETools breakdown exactly.
--
-- See REGRESSION_GUARDS.md "omen-idol-slot-dedup-on-corruption-count".

describe("OmenIdolSlotDedupOnCorruptionCount", function()

    local source
    setup(function()
        local f = io.open("Modules/CalcSetup.lua", "r")
        assert.is_not_nil(f, "must be able to open Modules/CalcSetup.lua")
        source = f:read("*a")
        f:close()
    end)

    it("regression-guard comment block is present", function()
        assert.is_truthy(string.find(source, "omen-idol-slot-dedup-on-corruption-count", 1, true),
            "CalcSetup.lua must keep the @leb-regression-guard comment so future edits trip review")
    end)

    it("declares a `seenIdolItem` table inside the corrupted-counting block", function()
        -- The dedup state must be a local table, not a module-level field,
        -- so it resets on every BuildOutput run.
        assert.is_truthy(string.find(source, "local%s+seenIdolItem%s*=%s*{}"),
            "CalcSetup.lua must declare `local seenIdolItem = {}` inside the corrupted-counting block")
    end)

    it("keys the dedup on item.id (with table-reference fallback)", function()
        -- `item.id` is the load-time identity carried in the XML; when it
        -- isn't populated (synthetic items in tests) the table reference
        -- itself is a stable identity for the run.
        assert.is_truthy(string.find(source, "local%s+key%s*=%s*item%.id%s+or%s+item"),
            "CalcSetup.lua must dedup on `item.id or item` so Idol N <-> Omen Idol N "
            .. "pairs that share a physical item are counted once")
    end)

    it("the dedup applies inside the idol-slot branch (skips before incrementing)", function()
        -- Match the `if seenIdolItem[key] then return end` early-return
        -- inside the same block that bumps the `idol` accumulator.
        assert.is_truthy(string.find(source, "if%s+seenIdolItem%[key%]%s+then%s+return%s+end"),
            "dedup must short-circuit BEFORE incrementing the idol counter, not after")
        assert.is_truthy(string.find(source, "seenIdolItem%[key%]%s*=%s*true"),
            "dedup must record the key after the early-return check")
    end)

    it("dedup state is shared across the active and level-gated iteration loops", function()
        -- Both loops must use the same closure (`countItem`) so a level-
        -- gated idol that already appeared via Omen Idol N (or vice
        -- versa) doesn't slip past the dedup. Pattern: a single
        -- `seenIdolItem` declaration followed by two `for ... pairs ...`
        -- loops that both call `countItem`.
        local i, j = string.find(source, "local%s+seenIdolItem%s*=%s*{}")
        assert.is_not_nil(i, "seenIdolItem declaration must exist as anchor")
        local window = string.sub(source, j, j + 2000)
        local active = string.find(window, "for%s+slotName,%s*item%s+in%s+pairs%(items%)")
        local gated  = string.find(window, "_levelGatedAllItems")
        assert.is_truthy(active, "active items loop must call countItem after seenIdolItem is declared")
        assert.is_truthy(gated, "level-gated items loop must call countItem inside the same scope as seenIdolItem")
    end)

    it("Omen Idol N slot prefix is recognised as an idol slot", function()
        -- The classifier must treat both `Idol N` and `Omen Idol N` as
        -- idol slots so the dedup is reached in the first place.
        assert.is_truthy(string.find(source, '"Omen Idol "', 1, true),
            "CalcSetup.lua classifier must include the `Omen Idol ` prefix as an idol slot")
    end)
end)
