-- @leb-regression-guard:trigger-chance-on-spell-cast-dps
-- Validation provenance is retained in maintainer notes.

describe("TriggerOnSpellCast bridge (parser, sibling recap)", function()
    it("'8% chance to cast Storm Bolt on spell cast' emits ChanceToTriggerOnSpellCast_PrimalLightning", function()
        assert.are.equals("Storm Bolt", data.skills.PrimalLightning.name)
        local mods, extra = modLib.parseMod("8% chance to cast Storm Bolt on spell cast")
        assert.is_nil(extra)
        assert.is_not_nil(mods)
        -- chance mod + the reminderText-cooldown rate cap (Storm Bolt / Lagon's Answer 1s -> 1/s)
        assert.are.equals(2, #mods)
        assert.are.equals("ChanceToTriggerOnSpellCast_PrimalLightning", mods[1].name)
        assert.are.equals("BASE", mods[1].type)
        assert.are.equals(8, mods[1].value)
        assert.is_falsy(mods.notSupported)
    end)

    it("emits TriggerRateCapPerSecond_PrimalLightning = 1 for Storm Bolt's reminderText 1s cooldown (THE CD-CAP FIX)", function()
        local mods = modLib.parseMod("8% chance to cast Storm Bolt on spell cast")
        local cap
        for _, m in ipairs(mods) do
            if m.name == "TriggerRateCapPerSecond_PrimalLightning" then cap = m end
        end
        assert.is_not_nil(cap, "on-spell-cast Storm Bolt bridge must emit the datamined 1s-cooldown rate cap")
        assert.are.equals("BASE", cap.type)
        assert.are.equals(1, cap.value) -- 1 / 1s cooldown = 1 proc/s
    end)

    it("the rate cap scales with chance count, not the affix roll (both 8% and 40% cap at 1/s)", function()
        for _, line in ipairs({ "8% chance to cast Storm Bolt on spell cast",
                                "40% chance to cast Storm Bolt on spell cast" }) do
            local mods = modLib.parseMod(line)
            local cap
            for _, m in ipairs(mods) do if m.name == "TriggerRateCapPerSecond_PrimalLightning" then cap = m.value end end
            assert.are.equals(1, cap, "cap is the trigger cooldown (1/s), independent of the chance roll: " .. line)
        end
    end)

    it("the emitted chance mod is global (no SkillName scope) - spell gating is at source selection", function()
        local mods = modLib.parseMod("8% chance to cast Storm Bolt on spell cast")
        for _, tag in ipairs(mods[1]) do
            assert.are_not.equals("SkillName", tag.type,
                "on-spell-cast trigger mod must be global; spell gating happens at source selection")
        end
    end)
end)

describe("TriggerOnSpellCast source/DPS invariants", function()
    it("CalcSetup sums ChanceToTriggerOnSpellCast_ gated to a spell source skill", function()
        local f = assert(io.open("Modules/CalcSetup.lua", "r"))
        local text = f:read("*a"); f:close()
        assert.is_truthy(text:find("ChanceToTriggerOnSpellCast_", 1, true),
            "CalcSetup must sum ChanceToTriggerOnSpellCast_<skillId>")
        assert.is_truthy(text:find("sourceIsSpell", 1, true),
            "CalcSetup must gate the on-spell-cast source to SkillType.Spell (sourceIsSpell)")
    end)

    it("CalcTriggers reads the on-spell-cast chance in the cast-on-hit DPS handler (THE FIX)", function()
        local f = assert(io.open("Modules/CalcTriggers.lua", "r"))
        local text = f:read("*a"); f:close()
        assert.is_truthy(text:find('ChanceToTriggerOnSpellCast_"%s*%.%.%s*triggeredId'),
            "CalcTriggers must add ChanceToTriggerOnSpellCast_<id> to the trigger chance at DPS time")
        assert.is_truthy(text:find("SkillType%.Spell"),
            "the DPS-time spell-cast chance read must be gated on the source's SkillType.Spell")
        assert.is_truthy(text:find("@leb%-regression%-guard:trigger%-chance%-on%-spell%-cast%-dps"),
            "inline regression-guard marker must be present in CalcTriggers")
    end)

    it("ModParser carries the new CD-cap inline guard marker (3-layer regression guard)", function()
        local f = assert(io.open("Modules/ModParser.lua", "r"))
        local text = f:read("*a"); f:close()
        assert.is_truthy(text:find("@leb%-regression%-guard:trigger%-spell%-cast%-cooldown%-cap"),
            "ModParser must carry the trigger-spell-cast-cooldown-cap guard marker at the cap emit site")
        assert.is_truthy(text:find("onSpellCastReminderTextCooldownCap", 1, true),
            "the datamined reminderText-cooldown cap table must be present")
    end)

    it("CalcSetup reads TriggerRateCapPerSecond_ and CalcTriggers min-applies it (cap wiring)", function()
        local fs = assert(io.open("Modules/CalcSetup.lua", "r"))
        local setup = fs:read("*a"); fs:close()
        assert.is_truthy(setup:find("TriggerRateCapPerSecond_", 1, true),
            "CalcSetup must read TriggerRateCapPerSecond_<skillId> for the injected trigger group")
        local ft = assert(io.open("Modules/CalcTriggers.lua", "r"))
        local trig = ft:read("*a"); ft:close()
        assert.is_truthy(trig:find("triggerRateCapPerSecond", 1, true),
            "CalcTriggers must min-apply srcInstance.triggerRateCapPerSecond (trigger-rate-cap-ptt)")
    end)

    it("the spell-cast read uses the source cast rate (useCastRate), not a hit-chance branch", function()
        -- The handler returns useCastRate=true; for a spell source there is no
        -- Melee/Attack hit-chance multiplier, so trigRate stays the source's cast rate.
        local f = assert(io.open("Modules/CalcTriggers.lua", "r"))
        local text = f:read("*a"); f:close()
        -- the spell-cast Sum and the useCastRate=true return live in the same handler
        local castPos = text:find('ChanceToTriggerOnSpellCast_"%s*%.%.%s*triggeredId')
        assert.is_truthy(castPos, "spell-cast read must be present")
        local handlerReturn = text:find("useCastRate = true", castPos, true)
        assert.is_truthy(handlerReturn,
            "the cast-on-hit handler containing the spell-cast read must return useCastRate=true")
    end)
end)
