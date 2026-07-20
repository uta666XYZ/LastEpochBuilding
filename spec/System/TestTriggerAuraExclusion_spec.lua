-- @leb-regression-guard:trigger-aura-exclude-discrete-bridges
-- Locks the defensive aura exclusion on the discrete on-hit / on-melee-hit /
-- on-spell-cast trigger bridges (bare AND rate-capped variants). A pure aura/DoT
-- (Fire Aura: baseFlags {spell,dot,duration}, NO hit) "Is not a Hit", so routing it
-- through the discrete ChanceToTriggerOn*_ path would compute discrete hit-DPS for a
-- skill that has none. These bridges have no parse-time rate (rate = source hit/cast
-- rate x chance, derived in CalcSetup), so the honest fallback for an aura is
-- recognition-only (ChanceToCast_), NOT discrete. (The cooldown path keeps routing
-- auras to AuraTriggerRatePerSecond_ because it HAS a 1/K rate.) There is no in-data
-- aura-on-hit affix today; this is a guard so one cannot silently be discrete-modelled.
-- A discrete-hit skill (Meteor) must still bridge normally — the guard must not
-- regress the working on-hit/melee/spell-cast bridges. See REGRESSION_GUARDS.md.

describe("TriggerAuraExclusion on discrete bridges (parser)", function()
    it("Fire Aura is a pure aura (dot+duration, no hit)", function()
        local bf = data.skills.FireAura.baseFlags
        assert.is_true(bf.dot and bf.duration and not bf.hit)
    end)

    local function names(mods)
        local set = {}
        if mods then for _, m in ipairs(mods) do set[m.name] = true end end
        return set
    end

    it("'cast Fire Aura on hit' does NOT emit a discrete ChanceToTriggerOnHit_FireAura", function()
        local n = names(modLib.parseMod("10% chance to cast Fire Aura on hit"))
        assert.is_falsy(n["ChanceToTriggerOnHit_FireAura"])
    end)

    it("'cast Fire Aura on melee hit' does NOT emit ChanceToTriggerOnMeleeHit_FireAura", function()
        local n = names(modLib.parseMod("10% chance to cast Fire Aura on melee hit"))
        assert.is_falsy(n["ChanceToTriggerOnMeleeHit_FireAura"])
    end)

    it("'cast Fire Aura on cast' does NOT emit ChanceToTriggerOnSpellCast_FireAura", function()
        local n = names(modLib.parseMod("10% chance to cast Fire Aura on cast"))
        assert.is_falsy(n["ChanceToTriggerOnSpellCast_FireAura"])
    end)

    it("rate-capped 'cast Fire Aura on hit (up to 3 times per second)' also excludes the aura", function()
        local n = names(modLib.parseMod("10% chance to cast Fire Aura on hit (up to 3 times per second)"))
        assert.is_falsy(n["ChanceToTriggerOnHit_FireAura"])
    end)

    it("a discrete-hit skill (Meteor) on hit STILL bridges (no regression)", function()
        assert.is_true(data.skills.Meteor.baseFlags.hit)
        local n = names(modLib.parseMod("10% chance to cast Meteor on hit"))
        assert.is_true(n["ChanceToTriggerOnHit_Meteor"])
    end)
end)
