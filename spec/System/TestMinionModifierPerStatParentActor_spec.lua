-- @leb-regression-guard:minion-modifier-perstat-parent-actor
-- See REGRESSION_GUARDS.md "minion-modifier-perstat-parent-actor"
-- Validation provenance is retained in maintainer notes.

describe("MinionModifierPerStatParentActor", function()
    it("LE_MINION_PERSTAT_PARENT_ATTRS covers the five primary attributes and their Raw twins", function()
        assert.is_table(LE_MINION_PERSTAT_PARENT_ATTRS,
            "LE_MINION_PERSTAT_PARENT_ATTRS must be defined in Global.lua")
        for _, attr in ipairs({ "Vit", "Str", "Dex", "Int", "Att" }) do
            assert.is_true(LE_MINION_PERSTAT_PARENT_ATTRS[attr] == true,
                "missing primary attribute key: " .. attr)
            assert.is_true(LE_MINION_PERSTAT_PARENT_ATTRS["Raw" .. attr] == true,
                "missing Raw twin key: Raw" .. attr)
        end
    end)
    it("CalcPerform MinionModifier dispatch routes PerStat actor=parent for primary attrs", function()
        local f = io.open("Modules/CalcPerform.lua", "r")
        assert.is_not_nil(f, "must be able to open Modules/CalcPerform.lua")
        local text = f:read("*a")
        f:close()
        -- Guard the runtime path: the PerStat tag walk must check the
        -- shared registry before injecting actor.
        assert.is_truthy(
            string.find(text, 'LE_MINION_PERSTAT_PARENT_ATTRS%[tag%.stat%]'),
            "CalcPerform.lua MinionModifier dispatch must gate the actor " ..
            "injection on LE_MINION_PERSTAT_PARENT_ATTRS[tag.stat].")
        assert.is_truthy(
            string.find(text, 'injected%[ti%]%.actor%s*=%s*"parent"'),
            "CalcPerform.lua MinionModifier dispatch must set " ..
            'injected[ti].actor = "parent" for matching PerStat tags.')
        assert.is_truthy(
            string.find(text, "@leb%-regression%-guard:minion%-modifier%-perstat%-parent%-actor"),
            "CalcPerform.lua must retain the @leb-regression-guard comment " ..
            "next to the PerStat parent-actor injection.")
    end)
end)
