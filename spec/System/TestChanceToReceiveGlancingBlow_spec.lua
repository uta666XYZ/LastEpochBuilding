-- @leb-regression-guard:chance-to-receive-glancing-blow-when-hit
-- Locks ModParser handling of the item-affix wording
-- "(N)% Chance to receive a Glancing Blow when hit" (ModItem_1_4 affix
-- group 933_*). The form scanner consumes "N% chance" as the CHANCE
-- form, leaving the tail "to receive a glancing blow when hit"; that
-- tail must alias to GlancingBlowChance in modNameList so the value
-- accumulates as flat BASE.
--
-- Also asserts the cached short-circuit rows that previously masked
-- this bug have been pruned from src/Data/ModCache.lua.
--
-- Symptom before fix (G1 fresh diff, 2026-05-11):
--   BM6x3nKn lv66 Bladedancer GlancingBlowChance LE=24 LEB=2 Δ=-22
-- After fix the body-armor suffix contributes BASE GlancingBlowChance.
-- See REGRESSION_GUARDS.md "chance-to-receive-glancing-blow-when-hit".

describe("ChanceToReceiveGlancingBlowWhenHit parser", function()
    it("'24% Chance to receive a Glancing Blow when hit' parses to GlancingBlowChance BASE 24", function()
        local mods, extra = modLib.parseMod("24% Chance to receive a Glancing Blow when hit")
        assert.is_nil(extra)
        assert.is_not_nil(mods)
        assert.are.equals(1, #mods)
        local m = mods[1]
        assert.are.equals("GlancingBlowChance", m.name)
        assert.are.equals("BASE", m.type)
        assert.are.equals(24, m.value)
    end)

    it("low-roll '1% Chance to receive a Glancing Blow when hit' also parses", function()
        local mods, extra = modLib.parseMod("1% Chance to receive a Glancing Blow when hit")
        assert.is_nil(extra)
        assert.are.equals(1, #mods)
        assert.are.equals("GlancingBlowChance", mods[1].name)
        assert.are.equals("BASE", mods[1].type)
        assert.are.equals(1, mods[1].value)
    end)
end)

describe("ModCache stale rows for this affix have been pruned", function()
    it("no row in src/Data/ModCache.lua matches '% Chance to receive a Glancing Blow when hit'", function()
        local f = assert(io.open("Data/ModCache.lua", "r"))
        local body = f:read("*a")
        f:close()
        assert.is_nil(body:find("Chance to receive a Glancing Blow when hit", 1, true),
            "stale ModCache row would short-circuit parseMod and re-mask the bug")
    end)
end)
