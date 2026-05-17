-- @leb-regression-guard: minion-modifier-type-narrowing
-- Locks the assembly-side support for narrowing MinionModifier LIST mods
-- to specific env.minion.type(s) via misc.addToMinionType (single) or
-- misc.addToMinionTypes (array). This is the counterpart of the
-- value.type / value.minionTypes dispatch gate in CalcPerform.lua and
-- the precondition for F3+F9 Shadow scope wiring.

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("MinionModifierTypeNarrowing", function()
    local parserText, calcText

    setup(function()
        parserText = readSource("Modules/ModParser.lua")
        calcText   = readSource("Modules/CalcPerform.lua")
    end)

    it("ModParser: misc.addToMinionType propagates into minionValue.type", function()
        local needle = 'if misc%.addToMinionType then minionValue%.type%s*=%s*misc%.addToMinionType end'
        assert.is_truthy(string.find(parserText, needle),
            "parser must forward misc.addToMinionType onto the MinionModifier value table as `type`")
    end)

    it("ModParser: misc.addToMinionTypes propagates into minionValue.minionTypes", function()
        local needle = 'if misc%.addToMinionTypes then minionValue%.minionTypes%s*=%s*misc%.addToMinionTypes end'
        assert.is_truthy(string.find(parserText, needle),
            "parser must forward misc.addToMinionTypes onto the MinionModifier value table as `minionTypes`")
    end)

    it("ModParser: MinionModifier LIST is constructed from the prepared value table (not a fresh `{ mod = ... }`)", function()
        -- The new shape must pass `minionValue` so type/minionTypes survive.
        local needle = 'mod%("MinionModifier",%s*"LIST",%s*minionValue,'
        assert.is_truthy(string.find(parserText, needle),
            "MinionModifier LIST must be built from `minionValue`, not a fresh inline table")
    end)

    it("CalcPerform: dispatch gate consumes both value.type and value.minionTypes", function()
        -- Sanity-check the consumer side still reads both fields; without
        -- this the parser changes would be silent no-ops.
        assert.is_truthy(string.find(calcText, 'value%.type'),
            "CalcPerform must read value.type")
        assert.is_truthy(string.find(calcText, 'value%.minionTypes'),
            "CalcPerform must read value.minionTypes")
    end)
end)
