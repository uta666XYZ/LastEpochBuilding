-- @leb-regression-guard:riverbend-grasp-throw-axe
-- rolls of 18-30). See REGRESSION_GUARDS.md "riverbend-grasp-throw-axe".
-- Validation provenance is retained in maintainer notes.

describe("RiverbendGrasp Throw Axe proc (parser)", function()
    it("the affix line emits functional ChanceToTriggerOnHit_AxeThrow + 1/s cap, no residue", function()
        local mods, extra = modLib.parseMod(
            "24% Chance to Throw an Axe at a nearby enemy on hit (1 second cooldown)")
        assert.is_nil(extra)
        assert.is_not_nil(mods)
        assert.are.equals(2, #mods)
        local byName = {}
        for _, m in ipairs(mods) do byName[m.name] = m.value end
        assert.are.equals(24, byName["ChanceToTriggerOnHit_AxeThrow"])
        assert.are.equals(1, byName["TriggerRateCapPerSecond_AxeThrow"])
        -- functional (consumed), NOT recognition-only
        assert.is_falsy(mods.notSupported)
    end)

    it("preserves the rolled value (corpus uses {range:N} floats interpolating 18-30)", function()
        local mods = modLib.parseMod(
            "28.26% Chance to Throw an Axe at a nearby enemy on hit (1 second cooldown)")
        local chance
        for _, m in ipairs(mods) do
            if m.name == "ChanceToTriggerOnHit_AxeThrow" then chance = m.value end
        end
        assert.is_not_nil(chance)
        assert.is_true(math.abs(chance - 28.26) < 1e-9, "float roll must be preserved verbatim")
    end)

    it("the trigger mod is global (no SkillName scope) so any source skill sums it", function()
        local mods = modLib.parseMod(
            "18% Chance to Throw an Axe at a nearby enemy on hit (1 second cooldown)")
        local trig
        for _, m in ipairs(mods) do
            if m.name == "ChanceToTriggerOnHit_AxeThrow" then trig = m end
        end
        assert.is_not_nil(trig)
        -- a SkillName tag would scope the mod to the TRIGGERED skill's cfg and the
        -- per-source-skill Sum in CalcSetup would never match it.
        for _, tag in ipairs(trig) do
            assert.are_not.equals("SkillName", tag.type,
                "functional trigger mod must not carry a SkillName tag")
        end
    end)
end)

describe("RiverbendGrasp Throw Axe grounding (skills.json)", function()
    it("data.skills.AxeThrow exists with the datamined base (phys 25 / eff 1 / crit 5x2)", function()
        local s = data.skills.AxeThrow
        assert.is_table(s, "data.skills.AxeThrow must exist (the proc target)")
        assert.are.equals("Axe Throw", s.name)
        assert.are.equals(25, s.stats.throwing_base_physical_damage)
        assert.are.equals(1, s.stats.damageEffectiveness)
        assert.are.equals(5, s.stats.critChance)
        assert.are.equals(100, s.stats["base_critical_strike_multiplier_+"])
        -- Physical + Throwing, a discrete hit (so the on-hit trigger path is valid)
        assert.is_true(s.baseFlags.hit, "AxeThrow must be a discrete-hit skill")
    end)
end)

describe("RiverbendGrasp Throw Axe ModCache", function()
    it("no stale 'Throw an Axe ... on hit' no-op row short-circuits the parser", function()
        local f = assert(io.open("Data/ModCache.lua", "r"))
        local body = f:read("*a")
        f:close()
        assert.is_nil(body:find("Chance to Throw an Axe at a nearby enemy on hit", 1, true),
            "stale ModCache row would re-mask the proc as an unmodelled no-op")
    end)
end)

describe("RiverbendGrasp Throw Axe source invariants", function()
    it("ModParser carries the guard marker and emits the functional trigger + cap", function()
        local f = assert(io.open("Modules/ModParser.lua", "r"))
        local text = f:read("*a")
        f:close()
        assert.is_truthy(text:find("@leb%-regression%-guard:riverbend%-grasp%-throw%-axe"),
            "inline regression-guard marker must be present")
        assert.is_truthy(text:find('ChanceToTriggerOnHit_AxeThrow', 1, true),
            "ModParser must emit the functional ChanceToTriggerOnHit_AxeThrow mod")
        assert.is_truthy(text:find('TriggerRateCapPerSecond_AxeThrow', 1, true),
            "ModParser must emit the 1/s PTT cap")
    end)

    it("CalcSetup consumes ChanceToTriggerOnHit_/TriggerRateCapPerSecond_ (existing infra)", function()
        local f = assert(io.open("Modules/CalcSetup.lua", "r"))
        local text = f:read("*a")
        f:close()
        assert.is_truthy(text:find("ChanceToTriggerOnHit_", 1, true),
            "CalcSetup must sum ChanceToTriggerOnHit_<skillId> into grantedTriggeredSkills")
        assert.is_truthy(text:find("TriggerRateCapPerSecond_", 1, true),
            "CalcSetup must sum the per-skill trigger rate cap")
    end)
end)
