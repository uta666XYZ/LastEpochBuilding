-- @leb-regression-guard:fissure-of-wrath-ailment-scaled-added-spell-damage
-- See REGRESSION_GUARDS.md "fissure-of-wrath-ailment-scaled-added-spell-damage".
-- Validation provenance is retained in maintainer notes.

describe("FissureOfWrathAilmentScaledDamage", function()
    it("ModParser emits the ailment-scaled marker (no dropped scaling, no stray skill tag)", function()
        local mods = modLib.parseMod("+1 Fissure Spell Damage per 2% Ignite Chance")
        assert.is_not_nil(mods, "modLib.parseMod must return a mod list")
        assert.are.equals(1, #mods)
        local m = mods[1]
        assert.are.equals("FissureSpellDamagePerUncappedAilment_Per2", m.name)
        assert.are.equals("BASE", m.type)
        assert.are.equals(1, m.value)
        -- the old mis-parse carried a SkillName="Ignite" tag; the marker carries none
        assert.is_nil(m[1], "marker must not carry a stray skill/per-stat tag")
    end)

    it("scales Flame Whip on the converted (bleed) ailment chance, x damage effectiveness", function()
        local xmlPath = "../spec/TestBuilds/1.4/bin/YsGhostSurfing Acolyte Legacy.xml"
        local fh = io.open(xmlPath, "r")
        if not fh then
            pending("YsGhostSurfing build XML not present (spec/TestBuilds is gitignored)")
            return
        end
        local xml = fh:read("*a"); fh:close()
        local calcs = require("Modules/Calcs")

        loadBuildFromXML(xml)
        local env = build.calcsTab.mainEnv
        local fw
        for _, s in ipairs(env.player.activeSkillList) do
            local ge = s.activeEffect and s.activeEffect.grantedEffect
            if ge and ge.name == "Flame Whip" then fw = s end
        end
        assert.is_not_nil(fw, "Flame Whip must be injected (Chthonic Fissure cast node)")

        env.player.mainSkill = fw
        calcs.perform(env)
        local sml, cfg = fw.skillModList, fw.skillCfg
        local o = env.player.output

        -- the build is fire->physical converted (Blood Gulch ch0fs-28), so node 22
        -- scales on the UNCAPPED bleed chance, not ignite (which is 0 here).
        assert.is_truthy(sml:Sum("BASE", cfg, "FireDamageConvertToPhysical") > 0,
            "build must have the Blood Gulch fire->physical conversion")
        local bleed = sml:Sum("BASE", cfg, "BleedChance")
        assert.is_truthy(bleed > 100, "uncapped skill bleed chance must exceed the 100 display cap")

        -- node22 added spell damage (= bleed/2, x3.0 effectiveness) must still be
        -- INCLUDED (the old parser bug dropped it -> 255). This build is Fire->Physical
        -- (Blood Gulch) and is in-game phys 100%, so the typeless/adaptive added (node22
        -- + Spine) now rides the POST-conversion Physical lane, not the converted-away
        -- Fire lane (@leb-regression-guard:adaptive-added-post-conversion-typing).
        -- output[<t>DamageBase] now holds the converged post-conversion base, so the
        -- node-22 contribution surfaces on Physical and the total is conserved.
        -- (Exact magnitude is locked by spec/System/TestAdaptiveAddedPostConversionTyping_spec.)
        local node22Added = bleed / 2
        assert.is_truthy(node22Added > 50, "node-22 adds > 50 base from bleed/2")
        local totalBase = 0
        for _, t in ipairs({ "Physical", "Fire", "Cold", "Lightning", "Necrotic", "Void", "Poison" }) do
            totalBase = totalBase + (o[t .. "DamageBase"] or 0)
        end
        assert.is_truthy(totalBase > 600,
            "node-22 bleed scaling must lift the total post-conversion base well above the pre-fix 255")
        -- the adaptive rides the converted-TO (Physical) lane, not the converted-away Fire
        assert.is_truthy((o.PhysicalDamageBase or 0) > (o.FireDamageBase or 0),
            "Fire->Physical: the post-conversion Physical base carries the converted base + adaptive")
        assert.is_truthy((o.PhysicalDamageBase or 0) > 600,
            "node-22 bleed-scaled added spell damage must land on the post-conversion Physical lane")
    end)
end)
