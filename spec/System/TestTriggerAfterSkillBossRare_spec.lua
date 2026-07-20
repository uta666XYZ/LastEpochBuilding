-- @leb-regression-guard:trigger-chance-after-skill
-- Source-SCOPED trigger variant "X% chance to cast <T> after you use <SOURCE> and
-- hit a boss or rare enemy" (Aurelis, uniques_1_4 id 225: "100% Chance to cast
-- Smite after you use Multistrike and hit a Boss or Rare enemy").
--
-- Unlike the on-hit / on-melee-hit / on-throwing-hit bridges (which emit a GLOBAL
-- chance summed across EVERY eligible source of a skill TYPE), this fires from ONE
-- named source skill only. The parse layer emits ChanceToTriggerAfterSkill_<T>
-- BASE tagged {SkillName=<SOURCE>}, so CalcSetup's per-source Sum
-- (activeSkill.skillCfg) is non-zero ONLY when the active source IS <SOURCE>
-- (Multistrike). This is the over-count invariant: a bare ChanceToTriggerOnMeleeHit_
-- sum (Multistrike is melee) would ALSO fire for Rive / every other melee source ->
-- massive over-count. The boss/rare enemy condition is applied at DPS time in
-- CalcTriggers (env.enemyDB), NOT at parse/group-creation, so the group is created
-- regardless of enemy config and a non-boss target zeroes it downstream.
--
-- GATED feat: exactly 1 corpus build (<private build> lv95 Paladin) carries Aurelis
-- (Multistrike main + Smite FullDPS) and needs a snapshot regen.

describe("TriggerAfterSkill boss/rare bridge (parser)", function()
    local line = "100% Chance to cast Smite after you use Multistrike and hit a Boss or Rare enemy"

    it("emits a single functional ChanceToTriggerAfterSkill_Smite BASE mod, residue-free", function()
        local mods, extra = modLib.parseMod(line)
        assert.is_nil(extra)
        assert.is_not_nil(mods)
        assert.are.equals(1, #mods)
        assert.are.equals("ChanceToTriggerAfterSkill_Smite", mods[1].name)
        assert.are.equals("BASE", mods[1].type)
        assert.are.equals(100, mods[1].value)
        assert.is_falsy(mods.notSupported)
    end)

    it("scopes the chance to the SOURCE skill (Multistrike) via a SkillName tag - the over-count invariant", function()
        local mods = modLib.parseMod(line)
        local found = false
        for _, tag in ipairs(mods[1]) do
            if tag.type == "SkillName" then
                found = true
                assert.are.equals("Multistrike", tag.skillName,
                    "the SkillName scope must name the SOURCE skill (Multistrike), so Rive/other melee sources sum 0")
            end
        end
        assert.is_true(found, "the after-skill trigger mod MUST carry a SkillName scope (prevents flat-melee over-count)")
    end)

    it("declines (recognition-only fallback) when the source skill is unknown", function()
        -- an unknown source name has no canonical -> the functional branch is skipped,
        -- so no ChanceToTriggerAfterSkill_ mod is produced.
        local mods = modLib.parseMod("100% chance to cast Smite after you use Notaskillxyz and hit a boss or rare enemy")
        if mods and mods[1] then
            assert.are_not.equals("ChanceToTriggerAfterSkill_Smite", mods[1].name,
                "an unknown source must not emit a functional after-skill trigger mod")
        end
    end)
end)

describe("TriggerAfterSkill source/DPS invariants", function()
    it("CalcSetup sums ChanceToTriggerAfterSkill_ with NO source-type gate (SkillName self-gates)", function()
        local f = assert(io.open("Modules/CalcSetup.lua", "r"))
        local text = f:read("*a"); f:close()
        assert.is_truthy(text:find("ChanceToTriggerAfterSkill_", 1, true),
            "CalcSetup must sum ChanceToTriggerAfterSkill_<skillId> in the trigger loop")
        assert.is_truthy(text:find("@leb%-regression%-guard:trigger%-chance%-after%-skill"),
            "inline regression-guard marker must be present in CalcSetup")
    end)

    it("CalcTriggers reads the after-skill chance gated on a Boss OR Rare enemy at DPS time (THE FIX)", function()
        local f = assert(io.open("Modules/CalcTriggers.lua", "r"))
        local text = f:read("*a"); f:close()
        assert.is_truthy(text:find('ChanceToTriggerAfterSkill_"%s*%.%.%s*triggeredId'),
            "CalcTriggers must add ChanceToTriggerAfterSkill_<id> to the trigger chance at DPS time")
        assert.is_truthy(text:find('Condition:Boss'),
            "the DPS-time after-skill read must be gated on the enemy Boss condition")
        assert.is_truthy(text:find('Condition:Rare'),
            "the DPS-time after-skill read must ALSO honor the enemy Rare condition")
        assert.is_truthy(text:find("@leb%-regression%-guard:trigger%-chance%-after%-skill%-dps"),
            "inline regression-guard marker must be present in CalcTriggers")
    end)
end)
