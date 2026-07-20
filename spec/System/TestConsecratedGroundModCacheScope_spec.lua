-- @leb-regression-guard:conscrated-ground-typo-alias
-- Consecrated Ground (skill key ConsecratedGround, name "Consecrated Ground") was
-- added to data.skills on 2026-06-14, but src/Data/ModCache.lua was baked EARLIER,
-- so every "Consecrated Ground X" tree-node stat was cached with the skill name
-- left UNCONSUMED in the entry's `extra` field (a non-empty leftover). Tree/passive
-- sources DROP any mod whose extra is non-empty (PassiveTree.lua:566 /
-- PassiveSpec.lua:1024), so all CG tree-node modifiers were silently dropped and CG
-- was massively under-scaled (in-game MyLittleStJames CG ~56,454 fire/tick vs LEB
-- static 5,210, 10.84x under).
--
-- Two fixes lock the correct behaviour:
--   1. The stale CG ModCache rows are REMOVED so parseMod re-runs the LIVE parser
--      (which now knows the skill and scopes "Consecrated Ground X" cleanly).
--   2. LE game data MISSPELLS "Consecrated Ground" as "Conscrated Ground" (missing
--      the 2nd 'e') in two Judgement tree stats. The skill-name eater (skillNameList,
--      ModParser.lua) and the per-skill scoping loops (skillNameByLower) only key off
--      the real skill name, so the misspelled phrase failed to scope. An alias maps
--      the typo to the canonical skill.
--
-- These asserts exercise the LIVE parser: the ModCache rows were removed in step 1,
-- so a stale row can no longer mask the result. If a stale "Consecrated Ground X"
-- row somehow remained, the cached extra would be non-empty and these would fail.
--
-- See REGRESSION_GUARDS.md "conscrated-ground-typo-alias".

describe("ConsecratedGround ModCache scope (typo alias + stale-row removal)", function()

    it("'+35% Consecrated Ground Damage' live-parses to a single CG-scoped Damage MORE 35 (no leftover)", function()
        local mods, extra = modLib.parseMod("+35% Consecrated Ground Damage")
        assert.is_nil(extra, "must have no unparsed leftover (the skill name is consumed)")
        assert.is_not_nil(mods, "must return a parsed mod list")
        assert.are.equals(1, #mods)
        local m = mods[1]
        assert.are.equals("Damage", m.name)
        assert.are.equals("MORE", m.type)
        assert.are.equals(35, m.value)
        local skillTag
        for _, tag in ipairs(m) do
            if tag.type == "SkillName" then skillTag = tag; break end
        end
        assert.is_not_nil(skillTag, "must carry a SkillName tag")
        assert.are.equals("Consecrated Ground", skillTag.skillName)
    end)

    it("'+30% Conscrated Ground Damage Against Ignited Enemies' (typo) scopes to CG with an enemy-Ignited condition", function()
        local mods, extra = modLib.parseMod("+30% Conscrated Ground Damage Against Ignited Enemies")
        assert.is_nil(extra, "the typo alias must let the misspelled skill name be consumed (no leftover)")
        assert.is_not_nil(mods)
        assert.are.equals(1, #mods)
        local m = mods[1]
        assert.are.equals("Damage", m.name)
        assert.are.equals("MORE", m.type)
        assert.are.equals(30, m.value)
        local skillTag, igniteTag
        for _, tag in ipairs(m) do
            if tag.type == "SkillName" then skillTag = tag end
            if tag.type == "ActorCondition" and tag.var == "Ignited" then igniteTag = tag end
        end
        assert.is_not_nil(skillTag, "must carry a SkillName tag (typo aliased to the real skill)")
        assert.are.equals("Consecrated Ground", skillTag.skillName)
        assert.is_not_nil(igniteTag, "must carry an enemy-Ignited ActorCondition")
        assert.are.equals("enemy", igniteTag.actor)
    end)

end)
