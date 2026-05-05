-- @leb-regression-guard: s4-converted-attr-no-base-inherit
-- Locks the contract that Season-4 converted attributes (Brutality, Guile,
-- Apathy, Rampancy) do NOT inherit the base-attribute global bonuses.
-- Verified against in-game LE 1.4 tooltips: Brutality grants only "more
-- melee damage per mana cost" + "reduced damage leeched as health" — no
-- Armour Increased PerStat. Earlier LEB releases applied Strength's
-- +4% Armour INC PerStat to Brutality (and equivalents to Guile/Apathy/
-- Rampancy), inflating Qdz2yXN3 player Armour Increased by +132%.
-- This test re-reads CalcSetup.lua source and asserts the offending
-- NewMod lines are absent.
-- See REGRESSION_GUARDS.md "s4-converted-attr-no-base-inherit".

describe("S4ConvertedAttrNoBaseInherit", function()
    local source
    setup(function()
        local f = io.open("Modules/CalcSetup.lua", "r")
        assert.is_not_nil(f, "must be able to open Modules/CalcSetup.lua")
        source = f:read("*a")
        f:close()
    end)

    local cases = {
        { stat = "Brutality", target = "Armour" },
        { stat = "Guile",     target = "Evasion" },
        { stat = "Apathy",    target = "Mana" },
        { stat = "Rampancy",  target = "Life" },
        { stat = "Rampancy",  target = "PoisonResist" },
        { stat = "Rampancy",  target = "NecroticResist" },
    }

    for _, c in ipairs(cases) do
        it(c.stat .. " does NOT have a PerStat NewMod for " .. c.target, function()
            -- Match patterns like:
            --   modDB:NewMod("Armour", "INC", 4, "Brutality", {type = "PerStat", stat = "Brutality"})
            -- The regression is any NewMod whose target stat is `c.target`
            -- AND whose PerStat tag references `c.stat`.
            local pat = 'NewMod%(%s*"' .. c.target .. '".-PerStat.-"' .. c.stat .. '"'
            local hit = string.find(source, pat)
            assert.is_falsy(hit,
                ("CalcSetup.lua must NOT register %s PerStat:%s — that would re-introduce the base-attr-inheritance bug"):format(c.target, c.stat))
        end)
    end

    it("the regression-guard comment block is still present", function()
        assert.is_truthy(string.find(source, "s4-converted-attr-no-base-inherit", 1, true),
            "CalcSetup.lua must keep the regression-guard comment so future edits are blocked at review time")
    end)
end)
