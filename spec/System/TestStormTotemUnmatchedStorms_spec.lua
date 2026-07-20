-- @leb-regression-guard:storm-totem-unmatched-storms-cadence
-- Validation provenance is retained in maintainer notes.

describe("StormTotemUnmatchedStorms", function()
    it("ModParser emits a minion-scoped MinionFixedCastTime for the node stat", function()
        local modList = modLib.parseMod("Storm Bolts Instead Of Lightning Strikes")
        assert.is_not_nil(modList, "parseMod must return a modList")
        assert.are.equal(1, #modList, "expected exactly one mod")
        local m = modList[1]
        assert.are.equal("MinionFixedCastTime", m.name)
        assert.are.equal("LIST", m.type)
        -- ~1/8.31 = 0.1204s
        assert.is_true(m.value.time > 0.11 and m.value.time < 0.13,
            "time should be ~1/8.31 = 0.1204s (got " .. tostring(m.value.time) .. ")")
        local found = false
        for _, t in ipairs(m.value.minionList or {}) do
            if t == "StormTotem" then found = true end
        end
        assert.is_true(found, "minionList must contain StormTotem")
    end)

    it("does NOT swap the minion skill (cadence-only by design)", function()
        local modList = modLib.parseMod("Storm Bolts Instead Of Lightning Strikes")
        for _, m in ipairs(modList) do
            assert.are_not.equal("ExtraMinionSkill", m.name,
                "Unmatched Storms must NOT grant/replace a minion skill (cadence-only) -- " ..
                "swapping to Storm Bolt double-counts the per-hit given LEB minion scaling")
        end
    end)

    it("parses identically from the raw leading-space ModCache key form", function()
        local modList = modLib.parseMod(" Storm Bolts Instead Of Lightning Strikes")
        assert.are.equal(1, #modList)
        assert.are.equal("MinionFixedCastTime", modList[1].name)
    end)

    it("createMinionSkills applies MinionFixedCastTime as a per-skill timeOverride", function()
        local f = io.open("Modules/CalcActiveSkill.lua", "r")
        assert.is_not_nil(f, "must open Modules/CalcActiveSkill.lua")
        local text = f:read("*a"); f:close()
        assert.is_truthy(string.find(text, "MinionFixedCastTime", 1, true),
            "createMinionSkills must consume the MinionFixedCastTime mod")
        assert.is_truthy(string.find(text, "skillData%.timeOverride = fixed%.time"),
            "the StormTotem's skills' skillData.timeOverride must be set from the mod")
    end)

    it("the ModCache no-op short-circuit for the node stat is removed", function()
        local f = io.open("Data/ModCache.lua", "r")
        assert.is_not_nil(f, "must open Data/ModCache.lua")
        local text = f:read("*a"); f:close()
        assert.is_nil(
            string.find(text, 'c%[" Storm Bolts Instead Of Lightning Strikes"%]={{},""}', 1, false),
            "the no-op ModCache row must be removed so the stat re-parses live")
    end)
end)
