-- @leb-regression-guard: buff-tree-cooldown-recovery-skill-local
-- Locks the CooldownRecovery exemption in CalcSetup.lua
-- `buildModListForNodeList`. The buff-skill tree applyBuffPrefix path
-- strips SkillId tags from node mods so a buff's tree-node effects can
-- broadcast globally to the player. For CooldownRecovery mods that
-- semantic is wrong: a buff-tree CDR node describes the SKILL's own
-- cooldown ("Symbols of Hope has a shorter cooldown") and game-side
-- routes it through the ability's own CD timer, NOT through the
-- player's SP.IncreasedCooldownRecoverySpeed=70 property.
--
-- Game ground truth (LE_datamining/extracted):
--   * items/globalTreeData.json -> skillTrees[treeID=si4lgl].nodes[id=23]
--     internal name "Sigils Of Hope Cooldown Recovery"
--   * dump.cs IdolAltarPropertyID enum has no aggregate-CDR-from-tree
--     property; CDR-on-skill is per-ability state, not a player stat
--   * audit of si4lgl/ah443 buff-tree node stats confirms si4lgl-23 is
--     the only CooldownRecovery node in those trees (others are
--     Cooldown duration changes, not CooldownRecovery)
--
-- Symptoms before fix (BgRrekMz lv92 Paladin, si4lgl-23 #2 with
-- SymbolsOfHopeEffect +20%):
--   2 points x 25% x (1 + 0.20 SoH effect) = 60% global CDR leak
--   output.CooldownRecovery 19 -> 79 (LETools shows 19; +60 overshoot)
--
-- See REGRESSION_GUARDS.md "buff-tree-cooldown-recovery-skill-local".

describe("BuffTreeCooldownRecoverySkillLocal", function()
    it("CalcSetup.buildModListForNodeList exempts CooldownRecovery from SkillId strip", function()
        local f = io.open("Modules/CalcSetup.lua", "r")
        assert.is_not_nil(f, "must be able to open Modules/CalcSetup.lua")
        local text = f:read("*a")
        f:close()
        -- The exemption is a literal AND-clause on the strip-detection
        -- branch. Asserting on the textual form catches accidental
        -- removal during future refactors.
        assert.is_truthy(
            string.find(text, 'mod%.name ~= "MinionModifier" and mod%.name ~= "CooldownRecovery"'),
            'CalcSetup.lua buildModListForNodeList must guard the SkillId ' ..
            'strip with `mod.name ~= "MinionModifier" and mod.name ~= "CooldownRecovery"` ' ..
            'so buff-tree CDR nodes (e.g. si4lgl-23 Enduring Hope) stay ' ..
            'scoped to their own skill.')
        -- Inline guard comment must also stay so any reader hitting
        -- the line understands why the AND-clause exists.
        assert.is_truthy(
            string.find(text, "@leb%-regression%-guard: buff%-tree%-cooldown%-recovery%-skill%-local"),
            'CalcSetup.lua must retain the @leb-regression-guard comment ' ..
            'next to the CooldownRecovery strip exemption.')
    end)
end)
