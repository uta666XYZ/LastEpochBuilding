-- @leb-regression-guard:trigger-chance-to-cast-on-bow-hit
-- Locks the Reign of Winter "(23-28)% Chance to cast Icicle on Bow Hit" proc wire
-- across its three layers (bow sibling of the throwing/melee/spell on-hit bridges):
--
--   1. ModParser  -- "X% chance to cast Icicle on bow hit" (bare and "+X%" forms)
--      emits a functional, GLOBAL ChanceToTriggerOnBowHit_HeorotUniqueBowIcicle mod.
--      Before this, "on bow hit" matched NO specialModList rule and the line baked to
--      an EMPTY ModCache entry (`{{}," to cast  on   "}`) -> no FullDPS contribution.
--   2. CalcSetup  -- the grantedTriggeredSkills loop sums that stat ONLY for a source
--      skill with SkillType.Bow AND the config toggle
--      (Condition:ModelReignOfWinterIcicleProc, default OFF), routing it through the
--      on-hit (triggeredOnHit) path so the group is created + inherits includeInFullDPS.
--   3. CalcTriggers -- the "cast on hit" DPS handler reads the SAME
--      ChanceToTriggerOnBowHit_<id> with the SAME Bow + config gating; without it the
--      (config-enabled) group would appear at triggerChance=0 -> dropped by TotalDPS>0.
--
-- Config-gated (default OFF) because the proc's rate cap / internal cooldown is NOT
-- datamined -- so folding at the full bow-hit rate x chance would be a fabricated
-- magnitude. Default OFF keeps the corpus byte-identical (nothing consumes the OnBowHit
-- mod); a user who wants to model the proc opts in. The triggered skill Icicle is
-- data.skills.HeorotUniqueBowIcicle (spell, hit, cold base 100). See REGRESSION_GUARDS.md
-- "trigger-chance-to-cast-on-bow-hit".

describe("ReignOfWinter on-bow-hit Icicle bridge (parser)", function()
    it("'26% Chance to cast Icicle on Bow Hit' emits functional ChanceToTriggerOnBowHit_HeorotUniqueBowIcicle", function()
        local mods, extra = modLib.parseMod("26% Chance to cast Icicle on Bow Hit")
        assert.is_nil(extra)
        assert.is_not_nil(mods)
        assert.are.equals(1, #mods)
        assert.are.equals("ChanceToTriggerOnBowHit_HeorotUniqueBowIcicle", mods[1].name)
        assert.are.equals("BASE", mods[1].type)
        assert.are.equals(26, mods[1].value)
        assert.is_falsy(mods.notSupported)
    end)

    it("the '+X%' combined-affix form parses to the same functional bow-hit mod", function()
        local mods, extra = modLib.parseMod("+5% Chance to cast Icicle on Bow Hit")
        assert.is_nil(extra)
        assert.is_not_nil(mods)
        assert.are.equals(1, #mods)
        assert.are.equals("ChanceToTriggerOnBowHit_HeorotUniqueBowIcicle", mods[1].name)
        assert.are.equals(5, mods[1].value)
    end)

    it("the emitted chance mod is global (no SkillName scope) - bow gating is at source selection", function()
        local mods = modLib.parseMod("26% Chance to cast Icicle on Bow Hit")
        for _, tag in ipairs(mods[1]) do
            assert.are_not.equals("SkillName", tag.type,
                "on-bow-hit trigger mod must be global; bow gating happens at source selection")
        end
    end)
end)

describe("ReignOfWinter source/DPS/config invariants", function()
    it("ModParser registers the on-bow-hit functional bridge", function()
        local f = assert(io.open("Modules/ModParser.lua", "r"))
        local text = f:read("*a"); f:close()
        assert.is_truthy(text:find('ChanceToTriggerOnBowHit_" .. triggerSkillId', 1, true),
            "ModParser must emit the functional ChanceToTriggerOnBowHit_ mod")
        assert.is_truthy(text:find("@leb%-regression%-guard:trigger%-chance%-to%-cast%-on%-bow%-hit"),
            "inline regression-guard marker must be present in ModParser")
    end)

    it("CalcSetup gates the on-bow-hit sum to a bow source AND the config toggle", function()
        local f = assert(io.open("Modules/CalcSetup.lua", "r"))
        local text = f:read("*a"); f:close()
        assert.is_truthy(text:find("ChanceToTriggerOnBowHit_", 1, true),
            "CalcSetup must sum ChanceToTriggerOnBowHit_<skillId>")
        assert.is_truthy(text:find("SkillType.Bow", 1, true),
            "CalcSetup must gate the on-bow-hit source to SkillType.Bow")
        assert.is_truthy(text:find("Condition:ModelReignOfWinterIcicleProc", 1, true),
            "CalcSetup must gate the on-bow-hit sum behind the config condition")
        assert.is_truthy(text:find("@leb%-regression%-guard:trigger%-chance%-to%-cast%-on%-bow%-hit"),
            "inline regression-guard marker must be present in CalcSetup")
    end)

    it("CalcTriggers reads the on-bow-hit chance in the cast-on-hit DPS handler, same gating", function()
        local f = assert(io.open("Modules/CalcTriggers.lua", "r"))
        local text = f:read("*a"); f:close()
        assert.is_truthy(text:find('ChanceToTriggerOnBowHit_"..triggeredId', 1, true),
            "CalcTriggers must add ChanceToTriggerOnBowHit_<id> to the trigger chance at DPS time")
        assert.is_truthy(text:find("SkillType.Bow", 1, true),
            "the DPS-time bow chance read must be gated on the source's SkillType.Bow")
        assert.is_truthy(text:find("Condition:ModelReignOfWinterIcicleProc", 1, true),
            "the DPS-time bow chance read must be gated on the config condition")
        assert.is_truthy(text:find("@leb%-regression%-guard:trigger%-chance%-on%-bow%-hit%-dps"),
            "inline regression-guard marker must be present in CalcTriggers")
    end)

    it("ConfigOptions exposes the default-OFF opt-in toggle", function()
        local f = assert(io.open("Modules/ConfigOptions.lua", "r"))
        local text = f:read("*a"); f:close()
        assert.is_truthy(text:find("conditionModelReignOfWinterIcicleProc", 1, true),
            "ConfigOptions must define the opt-in toggle var")
        assert.is_truthy(text:find('NewMod("Condition:ModelReignOfWinterIcicleProc"', 1, true),
            "the toggle must set the Condition flag its apply() consumers read")
    end)

    it("no stale empty ModCache row shadows the new rule (determinism)", function()
        local f = assert(io.open("Data/ModCache.lua", "r"))
        local text = f:read("*a"); f:close()
        assert.is_falsy(text:find("Chance to cast Icicle on Bow Hit", 1, true),
            "stale empty 'Chance to cast Icicle on Bow Hit' ModCache rows must be deleted so the affix re-parses live")
    end)
end)
