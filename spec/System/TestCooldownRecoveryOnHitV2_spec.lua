-- @leb-regression-guard: mod6-v2-combat-loop
-- Locks the v2 closed-form equilibrium fold-in of Mod#6
-- (cooldown-recovered-on-hit consumer).
--
-- v1 (commits f5dcbb2bf / 59e9fe7e7, guard
-- `cooldown-recovered-on-hit-consumer`) surfaces the paired stats
-- on the active skill:
--   output.CooldownRecoveryOnHit          (BASE pct, chance-folded)
--   output.CooldownRecoveryOnHitMaxPerCast (BASE cap)
-- both tagged SkillName="<X>" (Lethal Mirage cap=12, Aerial Assault
-- cap=3). v1 left the cooldown projection deferred.
--
-- v2 adds a closed-form equilibrium fold-in:
--   effectiveCD = baseCD * (1 - pct/100)^cap
-- assuming the cap is reached every cast (best-case steady state --
-- the affix's design intent). LEB has no time-axis combat loop, so
-- the closed form replaces a per-tick simulation (see Decision Log
-- L47, TODO.md "Mod#6 v2 combat-loop integration").
--
-- Game-side authority (dump.cs il2cpp re-extraction):
--   * L96712 chanceToRecover8pOfRemainingAerialAssaultCooldownOnThrowingHit
--   * L96714 maxTimesToRecover12pOfRemainingAerialAssaultCooldownOnThrowingHit = 3
--   * L96716 lethalMirageRemainingCooldownRecoveredOnMeleeHitUpTo12TimesPerUse
--   * L96718 lethalMirageMeleeHitCooldownRecoveryEventsSinceLastUse (int counter)
-- The per-skill SinceLast<Skill>Use counters are int, not float
-- timers; the closed form approximates their per-cast reset.
--
-- See REGRESSION_GUARDS.md "mod6-v2-combat-loop".

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("CooldownRecoveryOnHitV2", function()
    local offenceText, sectionsText

    setup(function()
        offenceText = readSource("Modules/CalcOffence.lua")
        sectionsText = readSource("Modules/CalcSections.lua")
    end)

    describe("CalcOffence fold-in", function()
        it("reads v1 aggregated CooldownRecoveryOnHit pct/cap", function()
            assert.is_truthy(string.find(offenceText,
                "local cdrPct = output%.CooldownRecoveryOnHit or 0", 1, false),
                "v2 must read v1's output.CooldownRecoveryOnHit")
            assert.is_truthy(string.find(offenceText,
                "local cdrCap = output%.CooldownRecoveryOnHitMaxPerCast or 0", 1, false),
                "v2 must read v1's output.CooldownRecoveryOnHitMaxPerCast")
        end)

        it("computes closed-form (1 - pct/100)^cap retention factor", function()
            assert.is_truthy(string.find(offenceText,
                "(1 - cdrPct / 100) ^ cdrCap", 1, true),
                "CalcOffence must use closed-form (1 - pct/100)^cap retention")
        end)

        it("assigns output.EffectiveCooldownFromOnHit", function()
            assert.is_truthy(string.find(offenceText,
                "output.EffectiveCooldownFromOnHit = effectiveCooldown", 1, true),
                "CalcOffence must expose EffectiveCooldownFromOnHit")
        end)

        it("propagates effective cooldown back into output.Cooldown", function()
            -- Required so downstream Speed clamp (output.Speed = min(Speed,
            -- 1/output.Cooldown * Repeats)) picks up the recovery.
            assert.is_truthy(string.find(offenceText,
                "output.Cooldown = effectiveCooldown", 1, true),
                "CalcOffence must overwrite output.Cooldown so speed clamps fold in the recovery")
        end)

        it("gates the math on both pct > 0 and cap > 0", function()
            assert.is_truthy(string.find(offenceText,
                "if cdrPct > 0 and cdrCap > 0", 1, true),
                "CalcOffence must gate the v2 fold-in on both pct and cap being positive")
        end)

        it("carries the inline regression-guard marker (effective-cooldown site)", function()
            assert.is_truthy(string.find(offenceText,
                "@leb-regression-guard:mod6-v2-combat-loop (effective-cooldown site)", 1, true),
                "inline guard ID (effective-cooldown site) must remain in CalcOffence.lua")
        end)

        it("emits an EffectiveCooldownFromOnHit breakdown", function()
            assert.is_truthy(string.find(offenceText,
                "breakdown.EffectiveCooldownFromOnHit", 1, true),
                "CalcOffence must populate a breakdown for the effective cooldown")
        end)
    end)

    describe("CalcSections row", function()
        it("declares an Effective Cooldown row gated on EffectiveCooldownFromOnHit", function()
            assert.is_truthy(string.find(sectionsText,
                'haveOutput = "EffectiveCooldownFromOnHit"', 1, true),
                "CalcSections must surface EffectiveCooldownFromOnHit when present")
        end)

        it("carries the inline regression-guard marker (section site)", function()
            assert.is_truthy(string.find(sectionsText,
                "@leb-regression-guard:mod6-v2-combat-loop (section site)", 1, true),
                "inline guard ID (section site) must remain in CalcSections.lua")
        end)
    end)

    describe("Math sanity (closed-form equilibrium)", function()
        local function effectiveCD(baseCD, pct, cap)
            return baseCD * (1 - pct / 100) ^ cap
        end

        it("Lethal Mirage 15% x 12 caps at ~14.2% retention", function()
            -- (1 - 0.15)^12 ~= 0.142
            local r = effectiveCD(1.0, 15, 12)
            assert.is_true(r > 0.140 and r < 0.143,
                "Lethal Mirage steady state should retain ~14.2% of base CD; got " .. tostring(r))
        end)

        it("Aerial Assault 1.36% (17% x 8%) x 3 caps at ~96% retention", function()
            -- chance-folded effective pct from parser: 17 * 8 / 100 = 1.36
            -- (1 - 0.0136)^3 ~= 0.9597
            local r = effectiveCD(1.0, 1.36, 3)
            assert.is_true(r > 0.959 and r < 0.961,
                "Aerial Assault steady state should retain ~96% of base CD; got " .. tostring(r))
        end)

        it("zero pct or zero cap leaves base CD unchanged (semantic check)", function()
            assert.are.equal(1.0, effectiveCD(1.0, 0, 12))
            assert.are.equal(1.0, effectiveCD(1.0, 15, 0))
        end)
    end)
end)
