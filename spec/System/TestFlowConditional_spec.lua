-- @leb-regression-guard:flow-conditional-damage
-- ceiling, NOT sustained DPS. See REGRESSION_GUARDS.md "flow-conditional-damage".
-- Validation provenance is retained in maintainer notes.

local FLOW_LINES = {
    { line = "10% Increased Damage when generating or consuming Flow",
      name = "Damage", mtype = "INC", value = 10, cond = "GeneratingOrConsumingFlow" },
    { line = "+5% Critical Multiplier when generating or consuming Flow",
      name = "CritMultiplier", mtype = "BASE", value = 5, cond = "GeneratingOrConsumingFlow" },
    { line = "100% More Damage When Consuming Flow",
      name = "Damage", mtype = "MORE", value = 100, cond = "ConsumingFlow" },
    { line = "+100% More Damage Over Time when Consuming Flow",
      name = "Damage", mtype = "MORE", value = 100, cond = "ConsumingFlow" },
    { line = "+50% More Crit Chance when Consuming Flow",
      name = "CritChance", mtype = "MORE", value = 50, cond = "ConsumingFlow" },
}

describe("Flow-conditional damage family (parser)", function()
    for _, case in ipairs(FLOW_LINES) do
        it("'" .. case.line .. "' -> " .. case.name .. " " .. case.mtype .. " + Condition:" .. case.cond .. ", no residue", function()
            local mods, extra = modLib.parseMod(case.line)
            assert.is_nil(extra)                       -- the fix: phrase stripped, nothing dropped
            assert.is_not_nil(mods)
            assert.are.equals(1, #mods)
            assert.is_falsy(mods.notSupported)
            assert.are.equals(case.name, mods[1].name)
            assert.are.equals(case.mtype, mods[1].type)
            assert.are.equals(case.value, mods[1].value)
            local found
            for _, tag in ipairs(mods[1]) do
                if type(tag) == "table" and tag.type == "Condition" then found = tag.var end
            end
            assert.are.equals(case.cond, found)
        end)
    end

    it("mutual exclusion: the 'generating or consuming' line is NOT tagged ConsumingFlow", function()
        local mods = modLib.parseMod("10% Increased Damage when generating or consuming Flow")
        for _, tag in ipairs(mods[1]) do
            if type(tag) == "table" and tag.type == "Condition" then
                assert.are_not.equals("ConsumingFlow", tag.var,
                    "'or consuming flow' must not match the bare 'when consuming flow' key")
            end
        end
    end)
end)

describe("Flow-conditional damage family (registry)", function()
    it("ModParser modTagList carries both Flow Condition keys", function()
        local f = assert(io.open("Modules/ModParser.lua", "r"))
        local text = f:read("*a"); f:close()
        assert.is_truthy(text:find('["when generating or consuming flow"]', 1, true))
        assert.is_truthy(text:find('["when consuming flow"]', 1, true))
        assert.is_truthy(text:find("@leb%-regression%-guard:flow%-conditional%-damage"))
    end)

    it("ConfigOptions exposes both Flow toggles (default OFF, ifCond-gated)", function()
        local f = assert(io.open("Modules/ConfigOptions.lua", "r"))
        local text = f:read("*a"); f:close()
        assert.is_truthy(text:find("conditionGeneratingOrConsumingFlow", 1, true))
        assert.is_truthy(text:find("conditionConsumingFlow", 1, true))
        assert.is_truthy(text:find('ifCond = "GeneratingOrConsumingFlow"', 1, true))
        assert.is_truthy(text:find('ifCond = "ConsumingFlow"', 1, true))
    end)

    it("the stale silent-failure ModCache rows were removed (no parse-cache short-circuit)", function()
        local f = assert(io.open("Data/ModCache.lua", "r"))
        local text = f:read("*a"); f:close()
        assert.is_falsy(text:find("consuming Flow", 1, true),
            "no baked '...consuming Flow' cache row may remain (would bypass the new handler)")
        assert.is_falsy(text:find("Consuming Flow", 1, true))
    end)
end)
