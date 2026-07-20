-- @leb-regression-guard:trigger-aura-stack-on-crit-when-hit
-- Locks the affix-granted STACKING-aura trigger model. "X% chance to cast Fire
-- Aura on crit / when hit (K second cooldown)" does NOT cast a discrete skill: Fire
-- Aura is a stacking aura (LETools "Each stack lasts 4 seconds"; datamined game source
-- FireAuraStacks buff / FireAuraMutator damageInterval=0.5). Each trigger gains a
-- stack at the PTT cap rate (1/K), each stack lasts the skill Duration, so the
-- steady-state stack count = gainRate x Duration (the ailment stack-uptime model).
--
-- The parser routes AURA skills (baseFlags.dot+duration, no hit) to a
-- source-independent AuraTriggerRatePerSecond_<skillId> (= 1/K), NOT the discrete
-- ChanceToTriggerCapped path. CalcSetup injects the aura like the TreeNodeGrant
-- precedent (continuous, includeInFullDPS) tagged source "AuraTrigger:<skillId>";
-- CalcOffence sets MaxStacks = gainRate x Duration (NOT clamped to 1, unlike the
-- single TreeNodeGrant aura). See REGRESSION_GUARDS.md.

describe("TriggerAuraStack on-crit / when-hit (parser)", function()
    it("'Fire Aura on crit (1 second cooldown)' emits AuraTriggerRatePerSecond (not discrete)", function()
        assert.is_truthy(data.skills.FireAura.baseFlags.dot)
        assert.is_falsy(data.skills.FireAura.baseFlags.hit)
        local mods, extra = modLib.parseMod("9% chance to cast Fire Aura on crit (1 second cooldown)")
        assert.is_nil(extra)
        assert.are.equals(1, #mods)
        assert.are.equals("AuraTriggerRatePerSecond_FireAura", mods[1].name)
        assert.are.equals(1, mods[1].value) -- 1/1
        assert.is_falsy(mods.notSupported)
        -- must NOT be the discrete-hit capped path
        assert.are_not.equals("ChanceToTriggerCapped_FireAura", mods[1].name)
    end)

    it("'when hit (2 second cooldown)' -> gain rate 1/2", function()
        local mods = modLib.parseMod("12% chance to cast Fire Aura when hit (2 second cooldown)")
        assert.are.equals("AuraTriggerRatePerSecond_FireAura", mods[1].name)
        assert.is_true(math.abs(mods[1].value - 0.5) < 1e-9)
    end)

    it("a discrete-hit skill (Meteor) still uses the discrete capped path, not the aura path", function()
        local mods = modLib.parseMod("20% chance to cast Meteor on crit (1 second cooldown)")
        local names = {}
        for _, m in ipairs(mods) do names[m.name] = true end
        assert.is_truthy(names["ChanceToTriggerCapped_Meteor"])
        assert.is_falsy(names["AuraTriggerRatePerSecond_Meteor"])
    end)
end)

describe("TriggerAuraStack ModCache", function()
    it("no stale 'cast Fire Aura on Crit/when Hit (1 second cooldown)' rows short-circuit the parser", function()
        local f = assert(io.open("Data/ModCache.lua", "r"))
        local body = f:read("*a"); f:close()
        assert.is_nil(body:find("cast Fire Aura on Crit (1 second cooldown)", 1, true))
        assert.is_nil(body:find("cast Fire Aura when Hit (1 second cooldown)", 1, true))
    end)
end)

describe("TriggerAuraStack source invariants", function()
    it("ModParser routes auras to AuraTriggerRatePerSecond_", function()
        local f = assert(io.open("Modules/ModParser.lua", "r"))
        local text = f:read("*a"); f:close()
        assert.is_truthy(text:find('AuraTriggerRatePerSecond_"..triggerSkillId', 1, true))
        assert.is_truthy(text:find("triggerSkillIsAura", 1, true))
    end)

    it("CalcSetup injects an AuraTrigger group and CalcOffence sets MaxStacks = rate x Duration", function()
        local f = assert(io.open("Modules/CalcSetup.lua", "r"))
        local cs = f:read("*a"); f:close()
        assert.is_truthy(cs:find("AuraTriggerRatePerSecond_", 1, true))
        assert.is_truthy(cs:find('"AuraTrigger:" .. skillId', 1, true))
        assert.is_truthy(cs:find("auraTriggerRatePerSecond", 1, true))
        local g = assert(io.open("Modules/CalcOffence.lua", "r"))
        local co = g:read("*a"); g:close()
        assert.is_truthy(co:find('source:find("^AuraTrigger:")', 1, true))
        assert.is_truthy(co:find("auraTriggerRatePerSecond %* output%.Duration"),
            "CalcOffence must set MaxStacks = gainRate x Duration for affix auras")
    end)
end)
