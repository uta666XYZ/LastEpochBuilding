-- @leb-regression-guard:trigger-chance-to-cast-on-spell-cast
-- Locks the on-(spell-)cast trigger bridge: "X% chance to cast <skill> on spell
-- cast" (and the "on cast" alias). The source is "you cast a spell".
--
-- Emits a functional, GLOBAL ChanceToTriggerOnSpellCast_<skillId>; the CalcSetup
-- grantedTriggeredSkills loop sums it ONLY for a source skill with SkillType.Spell,
-- then routes it through the on-hit path. For a spell source the handler's
-- hit-chance branch (Melee/Attack only) is not taken, so the rate is the spell's
-- CAST rate x this chance, build-derived. The triggered skill id is the data.skills
-- KEY (Storm Bolt -> "PrimalLightning"). See REGRESSION_GUARDS.md.

describe("TriggerOnSpellCast bridge (parser)", function()
    it("'8% chance to cast Storm Bolt on spell cast' emits functional ChanceToTriggerOnSpellCast_PrimalLightning", function()
        assert.are.equals("Storm Bolt", data.skills.PrimalLightning.name)
        local mods, extra = modLib.parseMod("8% chance to cast Storm Bolt on spell cast")
        assert.is_nil(extra)
        assert.is_not_nil(mods)
        -- chance mod + the datamined reminderText-cooldown rate cap (1s -> 1/s);
        -- see guard trigger-spell-cast-cooldown-cap / TestTriggerOnSpellCastDPS_spec.lua
        assert.are.equals(2, #mods)
        local m = mods[1]
        assert.are.equals("ChanceToTriggerOnSpellCast_PrimalLightning", m.name)
        assert.are.equals("BASE", m.type)
        assert.are.equals(8, m.value)
        assert.are.equals("TriggerRateCapPerSecond_PrimalLightning", mods[2].name)
        assert.are.equals(1, mods[2].value)
        assert.is_falsy(mods.notSupported)
    end)

    it("the 'on cast' alias maps to the same functional mod", function()
        local mods = modLib.parseMod("15% chance to cast Storm Bolt on cast")
        assert.are.equals("ChanceToTriggerOnSpellCast_PrimalLightning", mods[1].name)
        assert.are.equals(15, mods[1].value)
    end)

    it("the emitted mod is global (no SkillName scope) - source gated by SkillType.Spell in CalcSetup", function()
        local mods = modLib.parseMod("8% chance to cast Storm Bolt on spell cast")
        for _, tag in ipairs(mods[1]) do
            assert.are_not.equals("SkillName", tag.type,
                "on-spell-cast trigger mod must be global; spell gating happens at source selection")
        end
    end)
end)

describe("TriggerOnSpellCast ModCache", function()
    it("no stale 'Storm Bolt On Spell Cast' row short-circuits the parser", function()
        local f = assert(io.open("Data/ModCache.lua", "r"))
        local body = f:read("*a"); f:close()
        assert.is_nil(body:find("Storm Bolt On Spell Cast", 1, true),
            "stale ModCache row would re-mask the (previously unrecognized) text")
    end)
end)

describe("TriggerOnSpellCast source invariants", function()
    it("ModParser registers the on-spell-cast functional bridge", function()
        local f = assert(io.open("Modules/ModParser.lua", "r"))
        local text = f:read("*a"); f:close()
        assert.is_truthy(text:find('ChanceToTriggerOnSpellCast_" .. triggerSkillId', 1, true),
            "ModParser must emit the functional ChanceToTriggerOnSpellCast_ mod")
        assert.is_truthy(text:find("@leb%-regression%-guard:trigger%-chance%-to%-cast%-on%-spell%-cast"),
            "inline regression-guard marker must be present in ModParser")
    end)

    it("CalcSetup gates the on-spell-cast sum to a spell source skill", function()
        local f = assert(io.open("Modules/CalcSetup.lua", "r"))
        local text = f:read("*a"); f:close()
        assert.is_truthy(text:find("ChanceToTriggerOnSpellCast_", 1, true),
            "CalcSetup must sum ChanceToTriggerOnSpellCast_<skillId>")
        assert.is_truthy(text:find("SkillType.Spell", 1, true),
            "CalcSetup must gate the on-spell-cast source to SkillType.Spell")
    end)
end)
