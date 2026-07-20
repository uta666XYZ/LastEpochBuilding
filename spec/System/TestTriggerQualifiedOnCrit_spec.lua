-- @leb-regression-guard:trigger-qualified-oncrit-ratecap
-- Locks the source-qualified, rate-capped on-crit bridge:
--   "X% chance to cast <skill> on crit with <source> (up to N casts per second)"
-- e.g. "Lightning Blast on Crit with Frost Claw (up to 3 casts per second)".
-- The "up to N casts per second" is the explicit ProcTimeTracker cap (= N/s, datamined game source
-- L239352). Following the same model as trigger-global-capped-on-crit-when-hit, a
-- discrete-hit triggered skill is modelled at its cap (saturation upper bound; the
-- "with <source>" qualifier is assumed to drive the crits that saturate it). The
-- parser emits ChanceToTriggerCapped_<skillId> + TriggerRateCapPerSecond_<skillId>=N,
-- reusing the globalTrigger+cap path (no per-source crit-rate dependency, no
-- generalisation of the shared crit handler). ONLY hit skills are bridged; a pure
-- aura/DoT stays recognition-only. The "(up to N casts per M seconds)" variant
-- yields cap = N/M. See REGRESSION_GUARDS.md.
--
-- NOTE: strict value assertions use Meteor (a UNIQUE hit-skill name). The real-affix
-- Lightning Blast case below now asserts the PLAYER id strictly: skillIdByLower is
-- built deterministically and prefers the player skill over its minion/enemy/ailment
-- homonyms (see @leb-regression-guard:skillidbylower-prefer-player), so "Lightning
-- Blast" resolves to player LightningBlast — never the minion StormCrowLightningBlast
-- — identically across processes.

describe("TriggerQualifiedOnCrit rate-capped (parser)", function()
    it("'on crit with <source> (up to N casts per second)' for a hit skill emits capped trigger + cap N/s", function()
        assert.is_true(data.skills.Meteor.baseFlags.hit, "Meteor must be a hit skill")
        local mods, extra = modLib.parseMod("42% chance to cast Meteor on crit with Frost Claw (up to 3 casts per second)")
        assert.is_nil(extra)
        assert.are.equals(2, #mods)
        local byName = {}
        for _, m in ipairs(mods) do byName[m.name] = m.value end
        assert.are.equals(42, byName["ChanceToTriggerCapped_Meteor"])
        assert.are.equals(3, byName["TriggerRateCapPerSecond_Meteor"])
        assert.is_falsy(mods.notSupported)
    end)

    it("'(up to N casts per M seconds)' computes cap = N/M", function()
        local mods = modLib.parseMod("20% chance to cast Meteor on crit with Frost Claw (up to 3 casts per 2 seconds)")
        local byName = {}
        for _, m in ipairs(mods) do byName[m.name] = m.value end
        assert.are.equals(20, byName["ChanceToTriggerCapped_Meteor"])
        assert.is_true(math.abs(byName["TriggerRateCapPerSecond_Meteor"] - 1.5) < 1e-9)
        assert.is_falsy(mods.notSupported)
    end)

    it("the real affix (Lightning Blast on Crit with Frost Claw) bridges to the PLAYER LightningBlast", function()
        -- Deterministic now: skillIdByLower["lightning blast"] resolves to player
        -- LightningBlast, never the minion StormCrowLightningBlast.
        local mods, extra = modLib.parseMod("42% chance to cast Lightning Blast on crit with Frost Claw (up to 3 casts per second)")
        assert.is_nil(extra)
        assert.is_falsy(mods.notSupported)
        local byName = {}
        for _, m in ipairs(mods) do byName[m.name] = m.value end
        assert.are.equals(42, byName["ChanceToTriggerCapped_LightningBlast"])
        assert.are.equals(3, byName["TriggerRateCapPerSecond_LightningBlast"])
        assert.is_nil(byName["ChanceToTriggerCapped_StormCrowLightningBlast"],
            "must NOT resolve to the minion homonym")
    end)

    it("a pure aura (Fire Aura) is NOT bridged to a discrete capped trigger", function()
        assert.is_falsy(data.skills.FireAura.baseFlags.hit)
        local mods = modLib.parseMod("10% chance to cast Fire Aura on crit with Frost Claw (up to 3 casts per second)")
        if mods then
            for _, m in ipairs(mods) do
                assert.are_not.equals("ChanceToTriggerCapped_FireAura", m.name,
                    "an aura must not be modelled as a discrete capped trigger")
            end
        end
    end)
end)
