-- @leb-regression-guard:trigger-chance-on-throwing-hit-dps
-- Validation provenance is retained in maintainer notes.

describe("TriggerOnThrowingHit bridge (parser)", function()
    it("'31% chance to cast Smite on hit with throwing attacks' emits functional ChanceToTriggerOnThrowingHit_Smite", function()
        local mods, extra = modLib.parseMod("31% chance to cast Smite on hit with throwing attacks")
        assert.is_nil(extra)
        assert.is_not_nil(mods)
        assert.are.equals(1, #mods)
        assert.are.equals("ChanceToTriggerOnThrowingHit_Smite", mods[1].name)
        assert.are.equals("BASE", mods[1].type)
        assert.are.equals(31, mods[1].value)
        assert.is_falsy(mods.notSupported)
    end)

    it("the rate-cap variant emits both the chance and TriggerRateCapPerSecond", function()
        local mods = modLib.parseMod("33% chance to cast Smite on hit with throwing attacks (up to 5 times per second)")
        assert.is_not_nil(mods)
        local names = {}
        for _, m in ipairs(mods) do names[m.name] = m.value end
        assert.are.equals(33, names["ChanceToTriggerOnThrowingHit_Smite"])
        assert.are.equals(5, names["TriggerRateCapPerSecond_Smite"])
    end)

    it("the emitted chance mod is global (no SkillName scope) - throwing gating is at source selection", function()
        local mods = modLib.parseMod("31% chance to cast Smite on hit with throwing attacks")
        for _, tag in ipairs(mods[1]) do
            assert.are_not.equals("SkillName", tag.type,
                "on-throwing-hit trigger mod must be global; throwing gating happens at source selection")
        end
    end)
end)

describe("TriggerOnThrowingHit source/DPS invariants", function()
    it("ModParser registers the on-throwing-hit functional bridge", function()
        local f = assert(io.open("Modules/ModParser.lua", "r"))
        local text = f:read("*a"); f:close()
        assert.is_truthy(text:find('ChanceToTriggerOnThrowingHit_" .. triggerSkillId', 1, true),
            "ModParser must emit the functional ChanceToTriggerOnThrowingHit_ mod")
        assert.is_truthy(text:find("@leb%-regression%-guard:trigger%-chance%-to%-cast%-on%-throwing%-hit"),
            "inline regression-guard marker must be present in ModParser")
    end)

    it("CalcSetup gates the on-throwing-hit sum to a throwing source skill", function()
        local f = assert(io.open("Modules/CalcSetup.lua", "r"))
        local text = f:read("*a"); f:close()
        assert.is_truthy(text:find("ChanceToTriggerOnThrowingHit_", 1, true),
            "CalcSetup must sum ChanceToTriggerOnThrowingHit_<skillId>")
        assert.is_truthy(text:find("SkillType.Throwing", 1, true),
            "CalcSetup must gate the on-throwing-hit source to SkillType.Throwing")
        assert.is_truthy(text:find("@leb%-regression%-guard:trigger%-chance%-to%-cast%-on%-throwing%-hit"),
            "inline regression-guard marker must be present in CalcSetup")
    end)

    it("CalcTriggers reads the on-throwing-hit chance in the cast-on-hit DPS handler (THE FIX)", function()
        local f = assert(io.open("Modules/CalcTriggers.lua", "r"))
        local text = f:read("*a"); f:close()
        assert.is_truthy(text:find('ChanceToTriggerOnThrowingHit_"%s*%.%.%s*triggeredId'),
            "CalcTriggers must add ChanceToTriggerOnThrowingHit_<id> to the trigger chance at DPS time")
        assert.is_truthy(text:find("SkillType.Throwing", 1, true),
            "the DPS-time throwing chance read must be gated on the source's SkillType.Throwing")
        assert.is_truthy(text:find("@leb%-regression%-guard:trigger%-chance%-on%-throwing%-hit%-dps"),
            "inline regression-guard marker must be present in CalcTriggers")
    end)
end)
