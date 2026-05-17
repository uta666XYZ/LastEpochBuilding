-- @leb-regression-guard:minions-have-dread-shade-buff-gating
-- Locks the SkillId→ActorCondition injection at CalcPerform.lua's
-- MinionModifier dispatch loop.
--
-- In-game (dump.cs L38327-38446) Dread Shade is implemented as
-- DreadShadeMutator : AbilityMutator, attaching a per-target Buff
-- Component (DelayedCastOnMinion) that exposes auraStats /
-- statsToParent / addedArmorPerVit on the specific minion that
-- received the cast. Tree-passive contributions like Martyrdom's
-- "30 Minion Armour per Vitality" therefore live on the buff
-- Component, not on a global skill-scope flag.
--
-- LEB models this with a "minions have <buff>" Condition gated via
-- LE_MINION_BUFF_SKILL_TO_CONDITION (Global.lua). When a
-- MinionModifier's inner mod carries a SkillId tag for a registered
-- buff-skill (e.g. SkillId:"DreadShade"), CalcPerform appends an
-- ActorCondition tag (actor="parent", var=<mapped condition>) before
-- handing the mod to env.minion.modDB. This makes the contribution
-- visible in the minion breakdown only while the player has toggled
-- the matching condition (default OFF → existing snapshots
-- unchanged).
--
-- See REGRESSION_GUARDS.md "minions-have-dread-shade-buff-gating"
-- and [[Minion Armor 三角測量 g1 調査]] for the triangulation that
-- motivated the gating.

describe("MinionsHaveDreadShadeBuffGating", function()
    it("LE_MINION_BUFF_SKILL_TO_CONDITION maps DreadShade to MinionsHaveDreadShade", function()
        assert.is_table(LE_MINION_BUFF_SKILL_TO_CONDITION,
            "LE_MINION_BUFF_SKILL_TO_CONDITION must be defined in Global.lua")
        assert.are.equal("MinionsHaveDreadShade",
            LE_MINION_BUFF_SKILL_TO_CONDITION.DreadShade,
            "DreadShade must map to the MinionsHaveDreadShade condition flag")
    end)

    it("LE_WHILE_ACTIVE_BUFF_BY_TREE_ID carries the Dread Shade treeId", function()
        assert.is_table(LE_WHILE_ACTIVE_BUFF_BY_TREE_ID,
            "LE_WHILE_ACTIVE_BUFF_BY_TREE_ID must be defined in Global.lua")
        assert.are.equal("MinionsHaveDreadShade",
            LE_WHILE_ACTIVE_BUFF_BY_TREE_ID["ds4d3"],
            "Dread Shade treeId ds4d3 must gate on MinionsHaveDreadShade")
    end)

    it("CalcPerform MinionModifier dispatch appends ActorCondition for registered buff-skill SkillId tags", function()
        local f = io.open("Modules/CalcPerform.lua", "r")
        assert.is_not_nil(f, "must be able to open Modules/CalcPerform.lua")
        local text = f:read("*a")
        f:close()
        assert.is_truthy(
            string.find(text, "LE_MINION_BUFF_SKILL_TO_CONDITION%[tag%.skillId%]"),
            "CalcPerform.lua MinionModifier dispatch must look up " ..
            "LE_MINION_BUFF_SKILL_TO_CONDITION[tag.skillId].")
        assert.is_truthy(
            string.find(text, 'type%s*=%s*"ActorCondition".-actor%s*=%s*"parent"'),
            "CalcPerform.lua must append an ActorCondition tag with " ..
            'actor="parent" so the buff-skill condition resolves on the ' ..
            "player's modDB.")
        assert.is_truthy(
            string.find(text, "@leb%-regression%-guard:minions%-have%-dread%-shade%-buff%-gating"),
            "CalcPerform.lua must retain the @leb-regression-guard comment " ..
            "next to the SkillId→ActorCondition injection.")
    end)

    it("ConfigOptions.lua exposes the MinionsHaveDreadShade toggle", function()
        local f = io.open("Modules/ConfigOptions.lua", "r")
        assert.is_not_nil(f, "must be able to open Modules/ConfigOptions.lua")
        local text = f:read("*a")
        f:close()
        assert.is_truthy(
            string.find(text, 'var%s*=%s*"conditionMinionsHaveDreadShade"'),
            "ConfigOptions.lua must declare the conditionMinionsHaveDreadShade entry.")
        assert.is_truthy(
            string.find(text, 'Condition:MinionsHaveDreadShade'),
            "ConfigOptions.lua must set the Condition:MinionsHaveDreadShade flag.")
    end)
end)
