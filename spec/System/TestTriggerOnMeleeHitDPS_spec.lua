-- @leb-regression-guard:trigger-chance-on-melee-hit-dps
-- Validation provenance is retained in maintainer notes.

describe("TriggerOnMeleeHit bridge (parser)", function()
    it("'31% chance to cast Smite on melee hit' emits functional ChanceToTriggerOnMeleeHit_Smite", function()
        local mods, extra = modLib.parseMod("31% chance to cast Smite on melee hit")
        assert.is_nil(extra)
        assert.is_not_nil(mods)
        assert.are.equals(1, #mods)
        assert.are.equals("ChanceToTriggerOnMeleeHit_Smite", mods[1].name)
        assert.are.equals("BASE", mods[1].type)
        assert.are.equals(31, mods[1].value)
        assert.is_falsy(mods.notSupported)
    end)

    it("the emitted chance mod is global (no SkillName scope) - melee gating is at source selection", function()
        local mods = modLib.parseMod("31% chance to cast Smite on melee hit")
        for _, tag in ipairs(mods[1]) do
            assert.are_not.equals("SkillName", tag.type,
                "on-melee-hit trigger mod must be global; melee gating happens at source selection")
        end
    end)
end)

describe("TriggerOnMeleeHit source/DPS invariants", function()
    it("CalcSetup sums ChanceToTriggerOnMeleeHit_ gated to a melee source skill", function()
        local f = assert(io.open("Modules/CalcSetup.lua", "r"))
        local text = f:read("*a"); f:close()
        assert.is_truthy(text:find("ChanceToTriggerOnMeleeHit_", 1, true),
            "CalcSetup must sum ChanceToTriggerOnMeleeHit_<skillId>")
        assert.is_truthy(text:find("sourceIsMelee", 1, true),
            "CalcSetup must gate the on-melee-hit source to SkillType.Melee (sourceIsMelee)")
    end)

    it("CalcTriggers reads the on-melee-hit chance in the cast-on-hit DPS handler (THE FIX)", function()
        local f = assert(io.open("Modules/CalcTriggers.lua", "r"))
        local text = f:read("*a"); f:close()
        assert.is_truthy(text:find('ChanceToTriggerOnMeleeHit_"%s*%.%.%s*triggeredId'),
            "CalcTriggers must add ChanceToTriggerOnMeleeHit_<id> to the trigger chance at DPS time")
        assert.is_truthy(text:find("SkillType%.Melee"),
            "the DPS-time melee chance read must be gated on the source's SkillType.Melee")
        assert.is_truthy(text:find("@leb%-regression%-guard:trigger%-chance%-on%-melee%-hit%-dps"),
            "inline regression-guard marker must be present in CalcTriggers")
    end)

    it("the spell-cast sibling is now wired at DPS time (ground-truthed 2026-07-09)", function()
        -- Validation provenance is retained in maintainer notes.
        local f = assert(io.open("Modules/CalcTriggers.lua", "r"))
        local text = f:read("*a"); f:close()
        assert.is_truthy(text:find('ChanceToTriggerOnSpellCast_"%s*%.%.%s*triggeredId'),
            "spell-cast DPS read is now wired (ground truth obtained)")
    end)
end)
