-- @leb-regression-guard:abomination-minions-consumed-more
-- Assemble Abomination gains "5% more damage per minion consumed, up to 20
-- minions". The modifier is linear and capped. Three coupled sites:
--   (1) ModParser "per minion consumed" -> Multiplier:AbominationMinionsConsumed (limit 20).
--   (2) skills.json AssembleAbomination baseMod "5% more Minion Damage per Minion Consumed".
--   (3) ConfigOptions "multiplierAbominationMinionsConsumed" count -> sets the multiplier on
--       the minion via a MinionModifier (default 0 -> MORE 1.0 -> corpus-neutral).
-- The MORE = 1 + 0.05 * min(N, 20): N=20 -> x2.0, N>20 -> still x2.0 (capped).
-- See REGRESSION_GUARDS.md "abomination-minions-consumed-more".

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a"); f:close()
    return text
end

describe("AbominationMinionsConsumed #abomination", function()
    before_each(function()
        newBuild()
    end)

    it("'5% more Minion Damage per Minion Consumed' parses with the AbominationMinionsConsumed multiplier (limit 20)", function()
        local mods, extra = modLib.parseMod("5% more Minion Damage per Minion Consumed")
        assert.is_nil(extra, "must fully parse, no residue")
        assert.is_not_nil(mods)
        assert.are.equals(1, #mods)
        local m = mods[1]
        assert.are.equals("MinionModifier", m.name, "must route to the minion")
        -- the wrapped inner mod is a Damage MORE carrying the multiplier tag
        local inner = m.value and m.value.mod
        assert.is_not_nil(inner, "MinionModifier must wrap an inner mod")
        assert.are.equals("MORE", inner.type)
        local foundTag = false
        for _, tg in ipairs(inner) do
            if tg.type == "Multiplier" and tg.var == "AbominationMinionsConsumed" then
                foundTag = true
                assert.are.equals(20, tg.limit, "multiplier must cap at 20")
            end
        end
        assert.is_true(foundTag, "inner mod must carry Multiplier:AbominationMinionsConsumed")
    end)

    it("skills.json AssembleAbomination carries the consumed-minion baseMod", function()
        assert.is_table(data.skills.AssembleAbomination, "AssembleAbomination must exist")
        local txt = readSource("Data/skills.json")
        assert.is_truthy(string.find(txt, "5% more Minion Damage per Minion Consumed", 1, true),
            "AssembleAbomination must carry the 'per Minion Consumed' baseMod string")
    end)

    it("ModParser + ConfigOptions carry the guard marker and the wiring", function()
        local mp = readSource("Modules/ModParser.lua")
        assert.is_truthy(string.find(mp, "@leb-regression-guard:abomination-minions-consumed-more", 1, true))
        assert.is_truthy(string.find(mp, '["per minion consumed"]', 1, true))
        assert.is_truthy(string.find(mp, "AbominationMinionsConsumed", 1, true))
        local co = readSource("Modules/ConfigOptions.lua")
        assert.is_truthy(string.find(co, "@leb-regression-guard:abomination-minions-consumed-more", 1, true))
        assert.is_truthy(string.find(co, "multiplierAbominationMinionsConsumed", 1, true))
    end)

end)
