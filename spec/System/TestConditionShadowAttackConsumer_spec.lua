-- @leb-regression-guard: condition-shadow-attack-consumer
-- Locks F5: CalcOffence wires skillCfg.skillCond["ShadowAttack"]
-- based on an allowlist of player-castable Shadow Attack skills.
-- Without this, every affix carrying tag={type="Condition",
-- var="ShadowAttack"} (including the F4 "Doubled for Shadow
-- Attack" mult clause) silently full-gates to zero on the player.

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("ConditionShadowAttackConsumer", function()
    local calcText

    setup(function()
        calcText = readSource("Modules/CalcOffence.lua")
    end)

    it("CalcOffence: carries the regression-guard marker", function()
        assert.is_truthy(
            string.find(calcText, '@leb%-regression%-guard:condition%-shadow%-attack%-consumer'),
            "CalcOffence must carry the F5 consumer guard marker so future refactors don't silently drop it"
        )
    end)

    it("CalcOffence: allowlist contains Shadow Cascade", function()
        assert.is_truthy(
            string.find(calcText, '%["Shadow Cascade"%]%s*=%s*true'),
            "Shadow Cascade must be in the Shadow Attack allowlist"
        )
    end)

    it("CalcOffence: allowlist contains Shadow Daggers", function()
        assert.is_truthy(
            string.find(calcText, '%["Shadow Daggers"%]%s*=%s*true'),
            "Shadow Daggers must be in the Shadow Attack allowlist"
        )
    end)

    it("CalcOffence: allowlist contains Shadow Rend", function()
        assert.is_truthy(
            string.find(calcText, '%["Shadow Rend"%]%s*=%s*true'),
            "Shadow Rend must be in the Shadow Attack allowlist"
        )
    end)

    it("CalcOffence: assigns skillCond['ShadowAttack'] from the allowlist", function()
        -- The actual wiring line: looks up the granted-effect name in
        -- the allowlist and writes the boolean into skillCfg.skillCond.
        local pattern = 'skillCfg%.skillCond%["ShadowAttack"%]%s*=%s*shadowAttackSkills%[activeGrantedName%]%s*or%s*false'
        assert.is_truthy(
            string.find(calcText, pattern),
            "CalcOffence must assign skillCfg.skillCond['ShadowAttack'] from the shadowAttackSkills lookup"
        )
    end)

    it("CalcOffence: reads the active skill's granted-effect name", function()
        -- We anchor to the canonical chain so a rename of the field
        -- chain (or a switch to a different identifier) is caught.
        local pattern = 'activeGrantedName%s*=%s*activeSkill%.activeEffect%s+and%s+activeSkill%.activeEffect%.grantedEffect%s+and%s+activeSkill%.activeEffect%.grantedEffect%.name'
        assert.is_truthy(
            string.find(calcText, pattern),
            "CalcOffence must read the granted-effect name via activeSkill.activeEffect.grantedEffect.name"
        )
    end)

    it("CalcOffence: does not allowlist Shurikens or Arrowstorm (player-cast forms are not Shadow Attacks)", function()
        -- These are skills the ShadowClone minion uses, but the player
        -- can cast them directly. Including them would make the
        -- player-context Condition:ShadowAttack falsely true.
        assert.is_nil(
            string.find(calcText, 'shadowAttackSkills%s*=%s*{[^}]-%["Shurikens"%]%s*=%s*true'),
            "Shurikens must NOT be in the player Shadow Attack allowlist"
        )
        assert.is_nil(
            string.find(calcText, 'shadowAttackSkills%s*=%s*{[^}]-%["Arrowstorm"%]%s*=%s*true'),
            "Arrowstorm must NOT be in the player Shadow Attack allowlist"
        )
    end)
end)
