-- @leb-regression-guard: regen-alias-coverage
-- Locks the contract that ModParser recognizes both short and long
-- forms of regen affix nouns:
--   * "Health Regen" and "Health Regeneration" → LifeRegen
--   * "Mana Regen" and "Mana Regeneration" → ManaRegen
-- In-game tooltips use both forms (verified via screenshots
-- 2026-05-05; see Obsidian "Web版着手プラン.md"). Only registering
-- the short form silently drops "% increased Mana Regeneration"
-- affixes from the calc.
-- See REGRESSION_GUARDS.md "regen-alias-coverage".

describe("RegenAlias", function()
    it("'% increased Health Regen' parses to LifeRegen INC", function()
        local mods = modLib.parseMod("28% increased Health Regen")
        assert.is_not_nil(mods)
        assert.are.equals("LifeRegen", mods[1].name)
        assert.are.equals("INC", mods[1].type)
        assert.are.equals(28, mods[1].value)
    end)

    it("'% increased Health Regeneration' parses to LifeRegen INC", function()
        local mods = modLib.parseMod("28% increased Health Regeneration")
        assert.is_not_nil(mods)
        assert.are.equals("LifeRegen", mods[1].name)
        assert.are.equals("INC", mods[1].type)
        assert.are.equals(28, mods[1].value)
    end)

    it("'% increased Mana Regen' parses to ManaRegen INC", function()
        local mods = modLib.parseMod("28% increased Mana Regen")
        assert.is_not_nil(mods)
        assert.are.equals("ManaRegen", mods[1].name)
        assert.are.equals("INC", mods[1].type)
        assert.are.equals(28, mods[1].value)
    end)

    it("'% increased Mana Regeneration' parses to ManaRegen INC", function()
        local mods = modLib.parseMod("28% increased Mana Regeneration")
        assert.is_not_nil(mods)
        assert.are.equals("ManaRegen", mods[1].name)
        assert.are.equals("INC", mods[1].type)
        assert.are.equals(28, mods[1].value)
    end)
end)
