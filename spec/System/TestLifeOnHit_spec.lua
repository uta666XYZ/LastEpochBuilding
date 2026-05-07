-- @leb-regression-guard: lifeonhit-flag-aware-sum
-- Locks the contract that character-aggregate output.LifeOnMeleeHit surfaces
-- the BASE sum from item/passive mods that ModParser tags with
-- `flags = bor(ModFlag.Melee, ModFlag.Hit)`. Reverting CalcDefence.lua's
-- `cfg = { flags = ... }` to the pre-fix `Sum("BASE", nil, ...)` shape silently
-- drops every flagged mod because ModDB:Sum requires
-- `band(cfg.flags, mod.flags) == mod.flags` and a nil cfg yields flags=0.
-- Real-world hit: Palarus's Sacred Light suffix "+11 Health Gain on Melee
-- Hit" surfaced as 0 on QDxZjL4J Paladin (LETools showed 11).
--
-- (output.LifeOnHit is overwritten per-skill in CalcOffence so its
-- defence-layer Sum does not propagate to a single global output and is
-- not asserted here.)
--
-- See REGRESSION_GUARDS.md for the index entry.

describe("LifeOnHitFlagAwareSum", function()
    before_each(function()
        newBuild()
    end)

    it("ModParser tags 'Health Gain on Melee Hit' with Melee+Hit flags", function()
        local mods = modLib.parseMod("+11 Health Gain on Melee Hit")
        assert.is_not_nil(mods)
        assert.are.equals(1, #mods)
        assert.are.equals("LifeOnMeleeHit", mods[1].name)
        assert.are.equals("BASE", mods[1].type)
        assert.are.equals(11, mods[1].value)
        local f = mods[1].flags
        assert.is_true(bit.band(f, ModFlag.Melee) ~= 0, "Melee flag missing")
        assert.is_true(bit.band(f, ModFlag.Hit) ~= 0, "Hit flag missing")
    end)

    it("BASE LifeOnMeleeHit surfaces on calcsOutput with Melee+Hit cfg", function()
        build.configTab.modList:NewMod("LifeOnMeleeHit", "BASE", 11, "Test",
            bit.bor(ModFlag.Melee, ModFlag.Hit), 0)
        runCallback("OnFrame")
        assert.are.equals(11, build.calcsTab.calcsOutput.LifeOnMeleeHit)
    end)
end)
