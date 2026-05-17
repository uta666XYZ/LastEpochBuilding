-- @leb-regression-guard:minion-skillid-scope-martyrdom
-- Locks the MinionModifier exemption in CalcSetup.lua
-- `buildModListForNodeList`. The buff-skill tree applyBuffPrefix path
-- strips SkillId tags from node mods so the buff's tree-node effects
-- broadcast globally (player). For MinionModifier mods this would
-- destroy per-skill scoping and let any buff-skill's MinionModifier
-- (e.g. Dread Shade tree's Martyrdom ds4d3-3 "30 Minion Armour Per
-- Vitality") leak onto every minion's modDB regardless of whether
-- that minion is the buff target.
--
-- ModStore.lua's SkillId tag filter (cfg.skillGrantedEffect.id gate)
-- is the only mechanism that keeps MinionModifier mods scoped per
-- skill, so the tag must survive the strip path.
--
-- Symptoms before fix (BxvJP3g1 lv99 Necromancer, ds4d3-3 #3):
--   * With Option A (PerStat → parent inject) applied, Skeleton.Armour
--     ballooned to 1730 (= (30 BASE + 30 Vit × 30 BASE) × 1.86 INC),
--     revealing Martyrdom contamination on a minion that is NOT the
--     Dread Shade target. Layer 1 fix here stops the contamination at
--     source even before Layer 2 (PassiveTree canonical id) lands.
-- See REGRESSION_GUARDS.md "minion-skillid-scope-martyrdom" and
-- [[Minion Armor 三角測量 g1 調査]] (Obsidian).

describe("MinionSkillIdScopeMartyrdom", function()
    it("CalcSetup.buildModListForNodeList exempts MinionModifier from SkillId strip", function()
        local f = io.open("Modules/CalcSetup.lua", "r")
        assert.is_not_nil(f, "must be able to open Modules/CalcSetup.lua")
        local text = f:read("*a")
        f:close()
        -- The exemption is a literal AND-clause on the strip-detection
        -- branch. Asserting on the textual form catches accidental
        -- removal during future refactors (e.g. when someone replaces
        -- the inline loop with a helper).
        assert.is_truthy(
            string.find(text, 'stripSkillId and mod%.name ~= "MinionModifier"'),
            'CalcSetup.lua buildModListForNodeList must guard the SkillId ' ..
            'strip with `stripSkillId and mod.name ~= "MinionModifier"` ' ..
            'so Dread Shade Martyrdom et al. stay scoped per skill.')
        -- Inline guard comment must also stay so any reader hitting
        -- the line understands why the AND-clause exists.
        assert.is_truthy(
            string.find(text, "@leb%-regression%-guard:minion%-skillid%-scope%-martyrdom"),
            'CalcSetup.lua must retain the @leb-regression-guard comment ' ..
            'next to the MinionModifier strip exemption.')
    end)
end)
