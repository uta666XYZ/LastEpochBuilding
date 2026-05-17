-- @leb-regression-guard:minion-modifier-perstat-parent-actor
-- Locks the PerStat→parent injection at CalcPerform.lua's
-- MinionModifier dispatch. LE minions don't carry primary attributes
-- (Vit/Str/Dex/Int/Att) of their own — tree-passive text like
--   Acolyte-59 notScalingStats[0]:
--     "2% Increased Minion Armor Per Intelligence"
-- references the player's stat. Without the injection ModStore.lua's
-- PerStat resolve (L398) defaults `target = self` to minion.modDB
-- and GetStat("Int") returns 0, zeroing every "Per <PrimaryAttr>"
-- contribution that should land on minions via MinionModifier.
--
-- The injection walks value.mod's tags before
-- `env.minion.modDB:AddMod(value.mod)` and forces `actor = "parent"`
-- on PerStat tags whose stat (or any statList entry) appears in
-- LE_MINION_PERSTAT_PARENT_ATTRS — without overwriting an explicit
-- prior actor binding, and copying the mod first so shared
-- skillModList references stay clean.
--
-- Symptoms before fix (BxvJP3g1 lv99 Necromancer):
--   * Skeleton.Armour = 30 (LETools 57; Δ-27 = 47%)
--   * Bone_Golem.Armour = 30 (same gap)
-- After fix:
--   * Skeleton.Armour = 56 (LETools 57; Δ-1 = 1.7%, rounding noise)
--   * Bone_Golem.Armour = 56
-- See REGRESSION_GUARDS.md "minion-modifier-perstat-parent-actor"
-- and [[Minion Armor 三角測量 g1 調査]] (Obsidian).

describe("MinionModifierPerStatParentActor", function()
    it("LE_MINION_PERSTAT_PARENT_ATTRS covers the five primary attributes and their Raw twins", function()
        assert.is_table(LE_MINION_PERSTAT_PARENT_ATTRS,
            "LE_MINION_PERSTAT_PARENT_ATTRS must be defined in Global.lua")
        for _, attr in ipairs({ "Vit", "Str", "Dex", "Int", "Att" }) do
            assert.is_true(LE_MINION_PERSTAT_PARENT_ATTRS[attr] == true,
                "missing primary attribute key: " .. attr)
            assert.is_true(LE_MINION_PERSTAT_PARENT_ATTRS["Raw" .. attr] == true,
                "missing Raw twin key: Raw" .. attr)
        end
    end)
    it("CalcPerform MinionModifier dispatch routes PerStat actor=parent for primary attrs", function()
        local f = io.open("Modules/CalcPerform.lua", "r")
        assert.is_not_nil(f, "must be able to open Modules/CalcPerform.lua")
        local text = f:read("*a")
        f:close()
        -- Guard the runtime path: the PerStat tag walk must check the
        -- shared registry before injecting actor.
        assert.is_truthy(
            string.find(text, 'LE_MINION_PERSTAT_PARENT_ATTRS%[tag%.stat%]'),
            "CalcPerform.lua MinionModifier dispatch must gate the actor " ..
            "injection on LE_MINION_PERSTAT_PARENT_ATTRS[tag.stat].")
        assert.is_truthy(
            string.find(text, 'injected%[ti%]%.actor%s*=%s*"parent"'),
            "CalcPerform.lua MinionModifier dispatch must set " ..
            'injected[ti].actor = "parent" for matching PerStat tags.')
        assert.is_truthy(
            string.find(text, "@leb%-regression%-guard:minion%-modifier%-perstat%-parent%-actor"),
            "CalcPerform.lua must retain the @leb-regression-guard comment " ..
            "next to the PerStat parent-actor injection.")
    end)
end)
