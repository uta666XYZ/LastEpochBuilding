-- @leb-regression-guard: broken-negative-inc-implicit-text
-- Locks the Item.lua ParseRaw substitution that repairs negative-INC
-- implicits saved as a literal broken text ("+-0.6 Armor") into the
-- correct percent-reduced template ("(42-60)% reduced Armor").
--
-- Evidence (LE_datamining extracted/items/equipmentItems.json):
--   Deadstar Amulet implicit[2]: property=10 (Armor), type=1 (INC),
--                                value=-0.6, maxValue=-0.42
--   Prophetic Homonculus implicit[2]: property=10 (Armor), type=1 (INC),
--                                value=-0.47, maxValue=-0.37
-- The dataminer-emitted raw string for these is "+-0.6 Armor" /
-- "+-0.47 Armor" (literal "+-" prefix). bases JSON renders the
-- parametrized form "{rounding:Integer}(42-60)% reduced Armor" /
-- "{rounding:Integer}(37-47)% reduced Armor" — but old XML build
-- snapshots cache the broken literal text on the implicit line.
-- On reload, the broken text has no "(N-M)" template, so applyRange
-- leaves it untouched and ModParser treats it as flat BASE -0.6 Armor
-- (effectively dropped — Armor +42.6% drift on BgRrekOY).
--
-- Three sites lock together:
-- a. `Classes/Item.lua` ParseRaw substitutes the broken literal with
--    self.base.implicits matching "(N-M)% reduced <stat>" template.
-- b. `Data/Bases/bases_1_4.json` carries the corrected templates for
--    Deadstar Amulet and Prophetic Homonculus.
-- c. `Data/Bases/bases.json` (legacy) carries the same corrected
--    templates so non-versioned base lookup also resolves.

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("BrokenNegativeIncImplicit", function()
    local itemText, bases14, basesLegacy

    setup(function()
        itemText    = readSource("Classes/Item.lua")
        bases14     = readSource("Data/Bases/bases_1_4.json")
        basesLegacy = readSource("Data/Bases/bases.json")
    end)

    it("Item.lua ParseRaw carries @leb-regression-guard marker", function()
        assert.is_truthy(string.find(itemText,
            "@leb-regression-guard: broken-negative-inc-implicit-text", 1, true),
            "Substitution site must carry the named guard marker")
    end)

    it("Item.lua ParseRaw detects '+-N.M <stat>' broken pattern", function()
        assert.is_truthy(string.find(itemText,
            [[line:find("^%+%-[%d%.]+%s+(.+)$")]], 1, true),
            "Broken-pattern detector must remain in ParseRaw")
    end)

    it("Item.lua ParseRaw substitutes from self.base.implicits", function()
        assert.is_truthy(string.find(itemText,
            "for _, baseImplLine in ipairs(self.base.implicits) do", 1, true),
            "Substitution must iterate self.base.implicits")
    end)

    it("Item.lua ParseRaw matches '(N-M)% reduced <stat>' template form", function()
        assert.is_truthy(string.find(itemText,
            [[%(%d+%-%d+%)%%%s+reduced%s+]], 1, true),
            "Substitution must match '(N-M)% reduced ' template form")
    end)

    it("bases_1_4.json Deadstar Amulet implicit uses (42-60)% reduced Armor", function()
        assert.is_truthy(string.find(bases14,
            '{rounding:Integer}(42-60)% reduced Armor', 1, true),
            "Deadstar Amulet implicit must use the corrected template")
        assert.is_nil(string.find(bases14, '"+-0.6 Armor"', 1, true),
            "bases_1_4.json must not carry the broken literal '+-0.6 Armor'")
    end)

    it("bases_1_4.json Prophetic Homonculus implicit uses (37-47)% reduced Armor", function()
        assert.is_truthy(string.find(bases14,
            '{rounding:Integer}(37-47)% reduced Armor', 1, true),
            "Prophetic Homonculus implicit must use the corrected template")
        assert.is_nil(string.find(bases14, '"+-0.47 Armor"', 1, true),
            "bases_1_4.json must not carry the broken literal '+-0.47 Armor'")
    end)

    it("bases.json (legacy) Deadstar Amulet implicit uses corrected template", function()
        assert.is_truthy(string.find(basesLegacy,
            '{rounding:Integer}(42-60)% reduced Armor', 1, true),
            "Deadstar Amulet implicit in legacy bases.json must also be corrected")
        assert.is_nil(string.find(basesLegacy, '"+-0.6 Armor"', 1, true),
            "bases.json must not carry the broken literal '+-0.6 Armor'")
    end)

    it("bases.json (legacy) Prophetic Homonculus implicit uses corrected template", function()
        assert.is_truthy(string.find(basesLegacy,
            '{rounding:Integer}(37-47)% reduced Armor', 1, true),
            "Prophetic Homonculus implicit in legacy bases.json must also be corrected")
        assert.is_nil(string.find(basesLegacy, '"+-0.47 Armor"', 1, true),
            "bases.json must not carry the broken literal '+-0.47 Armor'")
    end)
end)
