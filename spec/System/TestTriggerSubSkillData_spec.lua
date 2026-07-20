-- @leb-regression-guard:trigger-sub-skill-base-data
-- Locks S1 of the trigger-skill DPS pipeline: base data for the four triggered
-- sub-skills that the game-bundle extraction could NOT recover (they are
-- runtime/mutator-internal or VFX-only assets). The data comes from LETools'
-- in-page skill DB (window.LEAbilities.abilityList, gameVersion 1.4.5), which is
-- a faithful mirror of the game files: its Lightning Blast (21 Lightning / eff
-- 1.0 / tags 258 / Int 4% / mana 3) matches LEB's verified skills.json exactly.
-- Each variant was disambiguated against the in-game corpus tooltips (user
-- captured) by added-damage effectiveness (Zap 250%, Ice Spike 300%, Fire Burst
-- 200% all match), so this is in-game-cross-validated, not LETools-alone.
-- "Mana Storm" is intentionally absent: it is not a standalone ability (no class
-- in datamined game source dump; not in the LETools DB).
--
-- These entries make "X% chance to cast <skill> on hit" affixes (Fire Burst /
-- Zap / Ice Spike / Mana Arc) resolve in skillIdByLower so the on-hit bridge
-- (@leb-regression-guard:trigger-chance-to-cast-on-hit-bridge) can emit the
-- functional ChanceToTriggerOnHit_<skillId> mod. See REGRESSION_GUARDS.md
-- "trigger-sub-skill-base-data" and the LEB-0.13.2 trigger firing-model note.

describe("TriggerSubSkillData (S1)", function()
    local expected = {
        FireBurst = { name = "Fire Burst", tags = 264, eff = 2,   dmgKey = "spell_base_fire_damage",      dmg = 40, critMult = 100 },
        Zap       = { name = "Zap",        tags = 258, eff = 2.5, dmgKey = "spell_base_lightning_damage", dmg = 50, critMult = 0   },
        IceSpike  = { name = "Ice Spike",  tags = 260, eff = 3,   dmgKey = "spell_base_cold_damage",      dmg = 60, critMult = 100 },
        ManaArc   = { name = "Mana Arc",   tags = 258, eff = 1.5, dmgKey = "spell_base_lightning_damage", dmg = 20, critMult = 0   },
        -- Divine Bolt: trigger-affix skill the user did NOT capture in-game; base
        -- data from LETools (verified on /skills/divine_bolt: 20 Fire, eff 100%,
        -- "Per point of Attunement: 4% increased Damage", tags 264).
        DivineBolt = { name = "Divine Bolt", tags = 264, eff = 1,  dmgKey = "spell_base_fire_damage",      dmg = 20, critMult = 100 },
        -- Wind Tempest: SKILL-TREE on-hit trigger (TreeData node "chance to cast
        -- Wind Tempest on hit"). Base data from LETools physTempest (idx 767):
        -- 7.5 Physical, eff 37.5%, tags 4353, no crit, Attunement-scaled.
        WindTempest = { name = "Wind Tempest", tags = 4353, eff = 0.375, dmgKey = "spell_base_physical_damage", dmg = 7.5, critMult = 0 },
    }

    for key, e in pairs(expected) do
        it(key .. " exists in data.skills with the LETools+corpus-validated base data", function()
            local s = data.skills[key]
            assert.is_table(s, "data.skills." .. key .. " must exist")
            assert.are.equals(e.name, s.name)
            assert.are.equals(e.tags, s.skillTypeTags)
            assert.are.equals(e.eff, s.stats.damageEffectiveness)
            assert.are.equals(e.dmg, s.stats[e.dmgKey])
            assert.are.equals(e.critMult, s.stats["base_critical_strike_multiplier_+"])
            assert.is_true(s.baseFlags.spell and s.baseFlags.hit)
        end)
    end

    it("Mana Storm is intentionally NOT added (not a standalone ability)", function()
        assert.is_nil(data.skills.ManaStorm)
    end)

    it("the new skills resolve through the on-hit trigger bridge", function()
        -- S1 -> S2 connection: now that the skill exists in data.skills, the
        -- ModParser on-hit handler emits the functional trigger mod.
        local cases = {
            ["12% chance to cast Fire Burst on hit"] = "ChanceToTriggerOnHit_FireBurst",
            ["20% chance to cast Zap on hit"]        = "ChanceToTriggerOnHit_Zap",
            ["8% chance to cast Ice Spike on hit"]   = "ChanceToTriggerOnHit_IceSpike",
            ["10% chance to cast Divine Bolt on hit"]= "ChanceToTriggerOnHit_DivineBolt",
            -- skill-tree node trigger text flows through the SAME parser, so the
            -- on-hit bridge is source-agnostic (verified via PassiveTree.lua parseMod path).
            ["8% chance to cast Wind Tempest on hit"] = "ChanceToTriggerOnHit_WindTempest",
        }
        for line, expectName in pairs(cases) do
            local mods = modLib.parseMod(line)
            assert.is_not_nil(mods, line .. " must parse")
            assert.are.equals(1, #mods, line)
            assert.are.equals(expectName, mods[1].name, line)
            assert.is_falsy(mods.notSupported, line .. " must be functional, not recognition-only")
        end
    end)
end)
