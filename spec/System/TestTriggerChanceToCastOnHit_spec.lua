-- @leb-regression-guard:trigger-chance-to-cast-on-hit-bridge
-- Locks the S2 trigger-pipeline bridge: the item/affix wording
-- "(N)% Chance to cast <skill> on hit" must be CONSUMED, not merely recognized.
--
-- Before: ModParser emitted ChanceToCast_<SkillNoSpaces> (SkillName + Condition
-- tags, notSupported=true) which NOTHING read, so the triggered skill never
-- entered Full DPS. Meanwhile LEB's existing trigger framework
-- (CalcSetup grantedTriggeredSkills loop + CalcTriggers) consumes a DIFFERENT,
-- never-emitted mod: ChanceToTriggerOnHit_<skillId>.
--
-- Fix: when the triggered skill exists in data.skills, emit the FUNCTIONAL,
-- global ChanceToTriggerOnHit_<skillId> BASE mod (no SkillName scope). The
-- CalcSetup loop sums it per source skill; CalcTriggers derives the trigger rate
-- from the source skill's hit rate x this chance (uptime build-derived, not
-- fabricated). The skill id is the data.skills KEY (e.g. "AxeThrow"), resolved
-- via skillIdByLower built alongside skillNameByLower in ModParser.
--
-- Scope: only the bare "on hit$" form is bridged here. Rate-capped variants
-- ("... up to N times per M seconds", cooldowns) and tag-stripped forms
-- ("on melee hit") are intentionally NOT bridged - their rate cannot be derived
-- without fabrication. See REGRESSION_GUARDS.md "trigger-chance-to-cast-on-hit-bridge"
-- and the LEB-0.13.2 trigger design note for the per-condition rollout plan.

describe("TriggerChanceToCastOnHit bridge (parser)", function()
    it("'8% Chance to cast Axe Throw on hit' emits functional ChanceToTriggerOnHit_AxeThrow", function()
        local mods, extra = modLib.parseMod("8% Chance to cast Axe Throw on hit")
        assert.is_nil(extra)
        assert.is_not_nil(mods)
        assert.are.equals(1, #mods)
        local m = mods[1]
        assert.are.equals("ChanceToTriggerOnHit_AxeThrow", m.name)
        assert.are.equals("BASE", m.type)
        assert.are.equals(8, m.value)
        -- functional (consumed), NOT recognition-only
        assert.is_falsy(mods.notSupported)
    end)

    it("the triggered-skill id is the data.skills KEY, not the spaced name", function()
        -- AxeThrow is the data.skills key; "Axe Throw" is its .name. The framework
        -- (CalcSetup L#grantedTriggeredSkills) sums ChanceToTriggerOnHit_<KEY>.
        assert.is_table(data.skills.AxeThrow, "data.skills.AxeThrow must exist")
        assert.are.equals("Axe Throw", data.skills.AxeThrow.name)
        local mods = modLib.parseMod("12% Chance to cast Axe Throw on hit")
        assert.are.equals("ChanceToTriggerOnHit_AxeThrow", mods[1].name)
        assert.are.equals(12, mods[1].value)
    end)

    it("the emitted trigger mod is global (no SkillName scope) so any source skill sums it", function()
        local mods = modLib.parseMod("8% Chance to cast Axe Throw on hit")
        local m = mods[1]
        -- a SkillName tag would scope the mod to the TRIGGERED skill's cfg and the
        -- per-source-skill Sum would never match it. There must be no such tag.
        for i, tag in ipairs(m) do
            assert.are_not.equals("SkillName", tag.type,
                "functional trigger mod must not carry a SkillName tag")
        end
    end)
end)

describe("TriggerChanceToCastOnHit ModCache", function()
    it("no stale 'Chance To Cast Axe Throw On Hit' row short-circuits the parser", function()
        local f = assert(io.open("Data/ModCache.lua", "r"))
        local body = f:read("*a")
        f:close()
        assert.is_nil(body:find("Chance To Cast Axe Throw On Hit", 1, true),
            "stale ModCache row would re-mask the recognition-only behaviour")
    end)
end)

describe("TriggerChanceToCastOnHit source invariants", function()
    it("ModParser builds skillIdByLower and bridges on-hit to ChanceToTriggerOnHit_", function()
        local f = assert(io.open("Modules/ModParser.lua", "r"))
        local text = f:read("*a")
        f:close()
        assert.is_truthy(text:find("skillIdByLower", 1, true),
            "ModParser must build the skill-name -> skillId map")
        assert.is_truthy(text:find('ChanceToTriggerOnHit_" .. triggerSkillId', 1, true),
            "ModParser on-hit handler must emit the functional ChanceToTriggerOnHit_ mod")
        assert.is_truthy(text:find("@leb%-regression%-guard:trigger%-chance%-to%-cast%-on%-hit%-bridge"),
            "inline regression-guard marker must be present")
    end)

    it("CalcSetup consumes ChanceToTriggerOnHit_<skillId> into grantedTriggeredSkills", function()
        local f = assert(io.open("Modules/CalcSetup.lua", "r"))
        local text = f:read("*a")
        f:close()
        assert.is_truthy(text:find("ChanceToTriggerOnHit_", 1, true),
            "CalcSetup must sum ChanceToTriggerOnHit_<skillId> (existing consumer)")
        assert.is_truthy(text:find("grantedTriggeredSkills", 1, true),
            "CalcSetup must route triggered skills through grantedTriggeredSkills")
    end)
end)
