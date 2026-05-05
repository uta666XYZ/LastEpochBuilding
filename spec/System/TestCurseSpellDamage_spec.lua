-- @leb-regression-guard: curse-spell-damage-stat
-- Locks the contract that ModParser recognizes "+N Curse Spell Damage"
-- (e.g. on Hexed Grand Bone Idol prefix, see ModItem_1_4.json affix
-- 49629 family) and emits a Damage BASE mod gated to:
--   * keywordFlags = KeywordFlag.Spell  (matches Spell-tagged skills)
--   * tag SkillType=Curse              (filters to Bone Curse, Torment,
--                                       Decrepify, Anguish, Penance)
-- Without this entry the parser leaves "Curse" as residual extra → the
-- tooltip renders the line in red "UNSUPPORTED" color and the affix is
-- silently dropped from curse skill DPS.
-- See REGRESSION_GUARDS.md "curse-spell-damage-stat".

describe("CurseSpellDamage", function()
    it("'+8 Curse Spell Damage' parses to Damage BASE with no residual extra", function()
        local mods, extra = modLib.parseMod("+8 Curse Spell Damage")
        assert.is_nil(extra)
        assert.is_not_nil(mods)
        assert.are.equals(1, #mods)
        local m = mods[1]
        assert.are.equals("Damage", m.name)
        assert.are.equals("BASE", m.type)
        assert.are.equals(8, m.value)
        -- KeywordFlag.Spell == 256
        assert.are.equals(256, m.keywordFlags)
    end)

    it("'+8 Curse Spell Damage' carries SkillType.Curse tag", function()
        local mods = modLib.parseMod("+8 Curse Spell Damage")
        local m = mods[1]
        local foundCurseTag = false
        for _, tag in ipairs(m) do
            if type(tag) == "table" and tag.type == "SkillType"
                    and tag.skillType == SkillType.Curse then
                foundCurseTag = true
                break
            end
        end
        assert.is_true(foundCurseTag)
    end)

    it("'+66 Curse Spell Damage' (uniques_1_4 high roll) parses cleanly", function()
        local mods, extra = modLib.parseMod("+66 Curse Spell Damage")
        assert.is_nil(extra)
        assert.is_not_nil(mods)
        assert.are.equals(66, mods[1].value)
        assert.are.equals("Damage", mods[1].name)
    end)
end)
