-- @leb-regression-guard:overkill-damage-leech-parser
-- Locks ModParser's handling of the affix "(N)% of Overkill Damage
-- Leeched as Health". The wording must emit the OverkillLeech summary
-- modifier (display-only stat used by output.OverkillLeech), NOT the
-- generic DamageLifeLeech. LE applies overkill leech only to damage
-- exceeding remaining HP, so emitting DamageLifeLeech (which CalcOffence
-- consumes for every-hit leech) would over-leech all damage while
-- leaving the OverkillLeech sidebar at 0.
--
-- Symptoms before fix (G1 batch #1, 2026-05-07):
--   * BgRrP5rr OverkillLeech LE=16 LEB=0
--   * Q9J4wvmD  OverkillLeech LE=9  LEB=0
-- Root cause: modNameList lacked an entry for the full affix wording,
-- so scan() picked the generic "damage" name and "leeched as health"
-- suffix, producing DamageLifeLeech with " Overkill " left as
-- unconsumed text.
-- See REGRESSION_GUARDS.md "overkill-damage-leech-parser".

describe("OverkillLeech parser", function()
    it("'11% of Overkill Damage Leeched as Health' parses to OverkillLeech BASE 11", function()
        local mods = modLib.parseMod("11% of Overkill Damage Leeched as Health")
        assert.is_not_nil(mods)
        assert.is_not_nil(mods[1])
        assert.are.equals("OverkillLeech", mods[1].name)
        assert.are.equals("BASE", mods[1].type)
        assert.are.equals(11, mods[1].value)
    end)

    it("'5% of Overkill Damage Leeched as Health' parses to OverkillLeech BASE 5", function()
        local mods = modLib.parseMod("5% of Overkill Damage Leeched as Health")
        assert.is_not_nil(mods)
        assert.is_not_nil(mods[1])
        assert.are.equals("OverkillLeech", mods[1].name)
        assert.are.equals("BASE", mods[1].type)
        assert.are.equals(5, mods[1].value)
    end)

    it("does not emit DamageLifeLeech for the overkill affix wording", function()
        local mods = modLib.parseMod("9% of Overkill Damage Leeched as Health")
        assert.is_not_nil(mods)
        for _, m in ipairs(mods) do
            assert.are_not.equals("DamageLifeLeech", m.name)
        end
    end)
end)
