-- @leb-regression-guard:ailment-overstacking-uncapped
-- Locks the >100% ailment-chance OVERSTACKING behavior in CalcOffence.lua's
-- damaging-ailment steady-state loop.
--
-- Game ground truth (datamining, build 1.4.7c):
--   AilmentApplication__Apply (datamined game source) converts a hit's summed
--   ailment chance C (fraction, 1.0 = 100%) into stacks-this-hit via a floor+remainder
--   loop: `while (1 < C) { stacks++; C -= 1 }` then a single EpochExtensions__roll(C)
--   (datamined game source) adds one more stack on the leftover fraction. So the
--   EXPECTED stacks applied per hit = C, with NO 100% cap. All "chance to apply <this
--   ailment>" sources are SUMMED before the roll (AilmentApplication__addChance:1454),
--   and application is PER HIT-EVENT (ChanceToApplyAilmentsOnHit subscribes to the
--   HitDetector newEnemyHit/enemyHitAgain events).
--
-- LEB bug this guards against: CalcOffence line ~2479 caps every output.<X>Chance at
-- m_min(sum,100) because Ignite/Bleed Overload and the UI read it. Before this fix the
-- ailment APPLICATION RATE also used that capped value, silently discarding all
-- overstacking (a 282%-Bleed build applied at 100%, ~2.82x under on stack count). The
-- fix re-sums the UNCAPPED summed chance for the application rate ONLY, leaving the
-- capped output.<X>Chance (and every consumer of it) untouched.
--
-- Invariants locked here:
--   1. steady-state stacks are LINEAR in the uncapped summed chance, across the 100%
--      boundary (250% => 2.5x the 100% stacks). Impossible under the old min(,100) cap.
--   2. below 100% the behavior is byte-identical (50% => exactly 0.5x), i.e. the fix is
--      a strict no-op for the vast majority of builds (chance <= 100).
--   3. the DISPLAY/Overload value output.<X>Chance stays capped at 100.
--
-- See:
--   * REGRESSION_GUARDS.md "ailment-overstacking-uncapped"
--   * datamined game source
--   * the sibling formula guard "ailment-dps-steady-state-formula"

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

local function setMods(s)
    build.configTab.input.customMods = s
    build.configTab:BuildModList()
    runCallback("OnFrame")
end

-- Return output.BleedStacks for a Fireball build carrying `pct`% summed Bleed chance.
-- Fireball is a hitting skill unrelated to bleed, so the only bleed source is the affix.
local function bleedStacksAt(pct)
    build.skillsTab:SelSkill(1, "Fireball")
    setMods(string.format("+%d%% chance to inflict Bleed", pct))
    return build.calcsTab.mainOutput
end

describe("AilmentOverstackingUncapped", function()
    before_each(function()
        newBuild()
    end)

    it("CalcOffence.lua carries the inline regression-guard marker", function()
        local text = readSource("Modules/CalcOffence.lua")
        assert.is_truthy(string.find(text, "@leb-regression-guard:ailment-overstacking-uncapped", 1, true),
            "inline guard ID must remain in CalcOffence.lua for cross-reference auditing")
    end)

    it("the application rate uses the UNCAPPED summed chance, not output.<X>Chance", function()
        local text = readSource("Modules/CalcOffence.lua")
        assert.is_truthy(string.find(text, 'local overstackChance = modDB:Sum("BASE", skillCfg, ailmentName .. "Chance")', 1, true),
            "appRate must re-sum the uncapped summed ailment chance")
        assert.is_truthy(string.find(text, "applicationsPerSec = hitRate * (overstackChance / 100)", 1, true),
            "appRate must divide the uncapped chance by 100 (expected stacks/hit = C/100)")
    end)

    it("steady-state stacks are LINEAR in the uncapped chance ABOVE 100% (overstacking)", function()
        local at100 = bleedStacksAt(100).BleedStacks
        local at250 = bleedStacksAt(250).BleedStacks
        assert.is_truthy(at100 and at100 > 0, "the 100% baseline must produce bleed stacks")
        -- 250% chance => 2.5 guaranteed-plus-remainder applications per hit.
        -- Under the old m_min(chance,100) cap this ratio would be 1.0 (both clamped to 100).
        assert.is_near(2.5, at250 / at100, 1e-6,
            "250% summed bleed chance must apply 2.5x the stacks of 100% (uncapped overstacking)")
    end)

    it("below 100% the stack count is byte-identical (strict no-op for chance <= 100)", function()
        local at100 = bleedStacksAt(100).BleedStacks
        local at50 = bleedStacksAt(50).BleedStacks
        assert.is_truthy(at100 and at100 > 0)
        assert.is_near(0.5, at50 / at100, 1e-6,
            "50% summed chance must apply exactly half the 100% stacks -- unchanged by the fix")
    end)

    it("the displayed/Overload output.BleedChance stays capped at 100 even at 250%", function()
        local o = bleedStacksAt(250)
        assert.are.equals(100, o.BleedChance,
            "output.BleedChance must remain capped at 100 (Ignite/Bleed Overload + UI depend on it)")
    end)
end)
