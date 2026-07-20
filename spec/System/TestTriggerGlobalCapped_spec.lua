-- @leb-regression-guard:trigger-global-capped-on-crit-when-hit
-- Locks the cooldown-bound on-crit / when-hit bridge. These triggers fire on a
-- crit / on being hit (a build-/combat-dependent event) bounded by a PTT cap
-- (datamined game source ProcTimeTracker L239352). Following PoB's CWDT model + LE's PTT, the
-- rate is modelled as the cap (= 1/K for a "(K second cooldown)"): the trigger
-- fires often enough to saturate its cooldown. This avoids generalising the shared
-- crit handler to spell sources (no per-source crit-rate dependency).
--
-- The parser emits a source-INDEPENDENT ChanceToTriggerCapped_<skillId> + the PTT
-- cap; CalcSetup injects a triggeredGlobalCapped group; CalcTriggers' gated config
-- sets globalTrigger so defaultTriggerHandler takes EffectiveSourceRate =
-- output.TriggerRateCap (the cap). ONLY discrete-hit skills are bridged
-- (baseFlags.hit): a pure aura/DoT like Fire Aura must use the aura-uptime model,
-- NOT discrete casts, so it stays recognition-only. See REGRESSION_GUARDS.md.

describe("TriggerGlobalCapped on-crit / when-hit (parser)", function()
    it("'on crit (1 second cooldown)' for a hit skill emits capped trigger + cap 1/s", function()
        assert.are.equals("Meteor", data.skills.Meteor.name)
        assert.is_true(data.skills.Meteor.baseFlags.hit, "Meteor must be a hit skill")
        local mods, extra = modLib.parseMod("20% chance to cast Meteor on crit (1 second cooldown)")
        assert.is_nil(extra)
        assert.are.equals(2, #mods)
        local byName = {}
        for _, m in ipairs(mods) do byName[m.name] = m.value end
        assert.are.equals(20, byName["ChanceToTriggerCapped_Meteor"])
        assert.are.equals(1, byName["TriggerRateCapPerSecond_Meteor"])
        assert.is_falsy(mods.notSupported)
    end)

    it("'when hit (2 second cooldown)' computes cap = 1/2", function()
        local mods = modLib.parseMod("15% chance to cast Meteor when hit (2 second cooldown)")
        local byName = {}
        for _, m in ipairs(mods) do byName[m.name] = m.value end
        assert.are.equals(15, byName["ChanceToTriggerCapped_Meteor"])
        assert.is_true(math.abs(byName["TriggerRateCapPerSecond_Meteor"] - 0.5) < 1e-9)
    end)

    it("a pure aura (Fire Aura) is NOT bridged to a discrete capped trigger", function()
        -- Fire Aura: baseFlags {spell, dot}, no hit -> needs the aura-uptime model.
        assert.is_falsy(data.skills.FireAura.baseFlags.hit)
        local mods = modLib.parseMod("10% chance to cast Fire Aura on crit (1 second cooldown)")
        if mods then
            for _, m in ipairs(mods) do
                assert.are_not.equals("ChanceToTriggerCapped_FireAura", m.name,
                    "an aura must not be modelled as a discrete capped trigger")
            end
        end
    end)
end)

describe("TriggerGlobalCapped source invariants", function()
    it("CalcSetup injects a triggeredGlobalCapped group and CalcTriggers gates a globalTrigger config", function()
        local f = assert(io.open("Modules/CalcSetup.lua", "r"))
        local cs = f:read("*a"); f:close()
        assert.is_truthy(cs:find("ChanceToTriggerCapped_", 1, true), "CalcSetup must sum ChanceToTriggerCapped_")
        assert.is_truthy(cs:find("triggeredGlobalCapped", 1, true), "CalcSetup must mark triggeredGlobalCapped")
        local g = assert(io.open("Modules/CalcTriggers.lua", "r"))
        local ct = g:read("*a"); g:close()
        assert.is_truthy(ct:find("globalCappedTriggerConfig", 1, true), "CalcTriggers must define the capped config")
        assert.is_truthy(ct:find("triggeredGlobalCapped", 1, true), "CalcTriggers must gate on triggeredGlobalCapped")
    end)
end)
