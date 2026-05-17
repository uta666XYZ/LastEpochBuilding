-- @leb-regression-guard: traitors-tongue-self-source-slot
-- Locks CalcSetup.lua's per-slot filtering for "with X equipped in the
-- mainhand/offhand" self-referential mods. The earlier commit 6d363fc89 used a
-- global Condition tag which double-fired when the same unique was equipped in
-- both weapon slots (e.g. dual Traitor's Tongue → Parry 24% instead of LE's
-- 13%). The filter drops the cross-slot mod from the wrong-slot item so each
-- TT instance contributes only the mod whose named slot matches its own.
--
-- Game-data evidence (2026-05-12): LE in-game / LETools tooltip on QWXjqWJ2
-- (dual Traitor's Tongue) shows Parry Chance = 13% = +10 unique + 3 Spell
-- Breaker, i.e. ONE mainhand-Parry fires. With LEB's global-condition fix
-- both items' mainhand-Parry fired → 24%.
--
-- See REGRESSION_GUARDS.md "traitors-tongue-self-source-slot".

describe("TraitorsTongueSelfSourceSlot", function()

    local source
    setup(function()
        local f = io.open("Modules/CalcSetup.lua", "r")
        assert.is_not_nil(f, "must be able to open Modules/CalcSetup.lua")
        source = f:read("*a")
        f:close()
    end)

    it("regression-guard comment block is present", function()
        assert.is_truthy(string.find(source, "traitors-tongue-self-source-slot", 1, true),
            "CalcSetup.lua must keep the @leb-regression-guard comment so future edits trip review")
    end)

    it("filters srcList by slotName for Weapon 1 / Weapon 2", function()
        -- The filter must branch on slotName and pick the correct drop prefix.
        assert.is_truthy(string.find(source,
            'if slotName == "Weapon 1" or slotName == "Weapon 2" then', 1, true),
            "CalcSetup.lua must gate the filter on weapon slot names")
        assert.is_truthy(string.find(source,
            'local dropPrefix = %(slotName == "Weapon 1"%) and "OffhandHas:" or "MainHandHas:"'),
            "Weapon 1 must drop OffhandHas:* mods; Weapon 2 must drop MainHandHas:* mods")
    end)

    it("matches the Condition tag prefix, not the full var", function()
        -- Using sub(1, #dropPrefix) keeps the filter generic across all item
        -- names captured by the "(.-)" matcher in ModParser.
        assert.is_truthy(string.find(source,
            'tag.type == "Condition" and tag.var and tag.var:sub(1, #dropPrefix) == dropPrefix', 1, true),
            "filter must prefix-match Condition.var so any future cross-slot unique works without per-item code")
    end)
end)
