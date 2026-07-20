-- @leb-regression-guard:trigger-chance-to-cast-on-melee-hit
-- Locks the on-melee-hit trigger bridge: "X% chance to cast <skill> on melee hit".
--
-- Like the bare on-hit bridge it emits a functional, GLOBAL
-- ChanceToTriggerOnMeleeHit_<skillId> (no SkillName scope), but the source is
-- constrained at selection time: the CalcSetup grantedTriggeredSkills loop only
-- sums it for a source skill with SkillType.Melee, then routes it through the
-- SAME on-hit path (triggeredOnHit) so the handler applies the melee source's hit
-- chance. Rate = melee attack rate x hit chance x this chance, build-derived.
--
-- The triggered skill must exist in data.skills (the parser pattern is only
-- registered for skills in skillNameByLower). A non-data skill (e.g. Summon Forged
-- Weapon, a minion) is NOT bridged - it stays recognition-only / cached, unchanged.
-- See REGRESSION_GUARDS.md "trigger-chance-to-cast-on-melee-hit".

describe("TriggerOnMeleeHit bridge (parser)", function()
    it("'10% chance to cast Marrow Shards on melee hit' emits functional ChanceToTriggerOnMeleeHit_MarrowShards", function()
        local mods, extra = modLib.parseMod("10% chance to cast Marrow Shards on melee hit")
        assert.is_nil(extra)
        assert.is_not_nil(mods)
        assert.are.equals(1, #mods)
        local m = mods[1]
        assert.are.equals("ChanceToTriggerOnMeleeHit_MarrowShards", m.name)
        assert.are.equals("BASE", m.type)
        assert.are.equals(10, m.value)
        assert.is_falsy(mods.notSupported)
    end)

    it("the emitted mod is global (no SkillName scope) - source is gated by skill type in CalcSetup", function()
        local mods = modLib.parseMod("12% chance to cast Marrow Shards on melee hit")
        for _, tag in ipairs(mods[1]) do
            assert.are_not.equals("SkillName", tag.type,
                "on-melee-hit trigger mod must be global; melee gating happens at source selection")
        end
    end)

    it("a non-data triggered skill (Summon Forged Weapon, a minion) is NOT bridged to functional", function()
        -- Summon Forged Weapon is absent from data.skills, so no functional pattern is
        -- registered for it; it must NOT become ChanceToTriggerOnMeleeHit_.
        assert.is_nil(data.skills.SummonForgedWeapon)
        local mods = modLib.parseMod("31% chance to cast Summon Forged Weapon on melee hit")
        if mods and mods[1] then
            assert.are_not.equals("ChanceToTriggerOnMeleeHit_SummonForgedWeapon", mods[1].name,
                "non-data minion skill must not be bridged to the functional trigger mod")
        end
    end)
end)

describe("TriggerOnMeleeHit source invariants", function()
    it("ModParser registers the on-melee-hit functional bridge", function()
        local f = assert(io.open("Modules/ModParser.lua", "r"))
        local text = f:read("*a"); f:close()
        assert.is_truthy(text:find('ChanceToTriggerOnMeleeHit_" .. triggerSkillId', 1, true),
            "ModParser must emit the functional ChanceToTriggerOnMeleeHit_ mod")
        assert.is_truthy(text:find("@leb%-regression%-guard:trigger%-chance%-to%-cast%-on%-melee%-hit"),
            "inline regression-guard marker must be present in ModParser")
    end)

    it("CalcSetup gates the on-melee-hit sum to a melee source skill", function()
        local f = assert(io.open("Modules/CalcSetup.lua", "r"))
        local text = f:read("*a"); f:close()
        assert.is_truthy(text:find("ChanceToTriggerOnMeleeHit_", 1, true),
            "CalcSetup must sum ChanceToTriggerOnMeleeHit_<skillId>")
        assert.is_truthy(text:find("SkillType.Melee", 1, true),
            "CalcSetup must gate the on-melee-hit source to SkillType.Melee")
        assert.is_truthy(text:find("@leb%-regression%-guard:trigger%-chance%-to%-cast%-on%-melee%-hit"),
            "inline regression-guard marker must be present in CalcSetup")
    end)
end)
