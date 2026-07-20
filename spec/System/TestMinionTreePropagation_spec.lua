-- @leb-regression-guard:minion-skill-tree-mods-to-minion
-- @leb-regression-guard:companion-more-damage-health
-- @leb-regression-guard:bear-tree-grants-minion-skills
-- @leb-regression-guard:minion-crit-multiplier-base-2
-- See REGRESSION_GUARDS.md for the index entries.
-- Validation provenance is retained in maintainer notes.

local SYNTH_XML = [[<?xml version="1.0" encoding="UTF-8"?>
<LastEpochBuilding>
	<Build level="26" targetVersion="1_4" pantheonMajorGod="None" bandit="None" className="Primalist" ascendClassName="Beastmaster" characterLevelAutoMode="false" mainSocketGroup="1" viewMode="SKILLS" pantheonMinorGod="None">
	</Build>
	<Import/>
	<Calcs/>
	<Skills sortGemsByDPSField="CombinedDPS" activeSkillSet="1" sortGemsByDPS="true" defaultGemQuality="0" defaultGemLevel="normalMaximum" showSupportGemTypes="ALL" showAltQualityGems="false">
		<SkillSet id="1">
			<Skill skillId="SummonBear" slot="Skill 1" mainActiveSkill="1" includeInFullDPS="false" index="1" enabled="true" mainActiveSkillCalcs="1"/>
		</SkillSet>
	</Skills>
	<Tree activeSpec="1">
		<Spec ascendClassId="1" nodes="Beastmaster#1,Primalist#1,Primalist-14#1,Primalist-32#1,be36ar-0#1,be36ar-2#5,be36ar-11#1,be36ar-12#3,be36ar-15#1,be36ar-16#3,be36ar-17#4,be36ar-22#1,be36ar-23#4,be36ar-24#1" treeVersion="1_4" classId="0"/>
	</Tree>
	<Items activeItemSet="1">
		<ItemSet useSecondWeaponSet="false" id="1"/>
	</Items>
	<Config/>
</LastEpochBuilding>
]]

describe("MinionTreePropagation parser contracts", function()
    it("'75% More Companion Damage' parses to a companion-scoped MinionModifier MORE", function()
        local mods, extra = modLib.parseMod("75% More Companion Damage")
        assert.is_true(extra == nil or extra == "",
            "must parse residue-free (was dropped with residue ' Companion  ')")
        assert.are.equals(1, #mods)
        assert.are.equals("MinionModifier", mods[1].name)
        local inner = mods[1].value
        assert.are.equals("Damage", inner.mod.name)
        assert.are.equals("MORE", inner.mod.type)
        assert.are.equals(75, inner.mod.value)
        local hasBear = false
        for _, t in ipairs(inner.minionTypes or {}) do
            if t == "PrimalBear" then hasBear = true end
        end
        assert.is_true(hasBear, "companion scope must include PrimalBear")
    end)

    it("'85% More Companion Damage' and '75% More Companion Health' parse the same way", function()
        local mods = modLib.parseMod("85% More Companion Damage")
        assert.are.equals("MinionModifier", mods[1].name)
        assert.are.equals(85, mods[1].value.mod.value)
        local hmods, hextra = modLib.parseMod("75% More Companion Health")
        assert.is_true(hextra == nil or hextra == "")
        assert.are.equals("MinionModifier", hmods[1].name)
        assert.are.equals("Life", hmods[1].value.mod.name)
        assert.are.equals("MORE", hmods[1].value.mod.type)
    end)

    it("' Bear Can Use Earthquake' / ' Bears use Swipe' emit ExtraMinionSkill grants", function()
        local eq = modLib.parseMod(" Bear Can Use Earthquake")
        assert.are.equals("ExtraMinionSkill", eq[1].name)
        assert.are.equals("EarthquakeSlam", eq[1].value.skillId)
        assert.are.equals("PrimalBear", eq[1].value.minionList[1])
        local sw = modLib.parseMod(" Bears use Swipe")
        assert.are.equals("ExtraMinionSkill", sw[1].name)
        assert.are.equals("Swipe", sw[1].value.skillId)
    end)

    it("'-60% Bear Earthquake Damage' is bear-routed and Earthquake-scoped", function()
        local mods, extra = modLib.parseMod("-60% Bear Earthquake Damage")
        assert.is_true(extra == nil or extra == "",
            "must parse residue-free (was dropped with residue ' Bear   ')")
        assert.are.equals("MinionModifier", mods[1].name)
        assert.are.equals("PrimalBear", mods[1].value.minionTypes[1])
        local inner = mods[1].value.mod
        assert.are.equals("MORE", inner.type)
        assert.are.equals(-60, inner.value)
        local skillNameTag = false
        for _, t in ipairs(inner) do
            if t.type == "SkillName" and t.skillName == "Earthquake" then skillNameTag = true end
        end
        assert.is_true(skillNameTag, "the -60%% must stay scoped to Earthquake")
    end)

    it("grant lines that are intentionally NOT modeled stay clean no-ops", function()
        -- Teleport has no damage component (bear_abilities.json pid 263684);
        -- Earthquake charges are cast-cadence, out of the per-hit pipeline.
        local tp, tpExtra = modLib.parseMod(" Bear Can Use Teleport")
        assert.are.equals(0, #tp)
        assert.is_true(tpExtra == nil or tpExtra == "")
    end)
end)

describe("MinionTreePropagation data contracts", function()
    it("PrimalBear minions.json carries the game ActorStats baseline", function()
        local pb = data.minions.PrimalBear
        assert.is_table(pb)
        local found = {}
        for _, m in ipairs(pb.modList) do
            found[m.name .. ":" .. m.type] = m.value
        end
        assert.are.equals(75, found["Damage:MORE"], "x1.75 inherent MORE (ActorStats SP0 more 0.75)")
        assert.are.equals(-22, found["Speed:MORE"], "-22%% attack speed (ActorStats SP2 more -0.22)")
        assert.are.equals(-50, found["DamageTaken:MORE"], "-50%% damage taken (ActorStats SP6 more -0.5)")
        assert.are.equals(24, found["LifeRegen:BASE"], "+24 regen (ActorStats SP17 added 24)")
        assert.are.equals("360", pb.life, "life 360 (minion_stats_v4 maxHealth)")
    end)
end)

describe("MinionTreePropagation build integration (synthetic Beastmaster lv26)", function()
    before_each(function()
        newBuild()
    end)

    local function loadSynth()
        loadBuildFromXML(SYNTH_XML, "MinionTreePropagation synth")
        runCallback("OnFrame")
        local env = build.calcsTab.mainEnv
        assert.is_table(env.player.mainSkill, "mainSkill must exist")
        assert.is_table(env.player.mainSkill.minion, "SummonBear must summon a minion")
        return env, env.player.mainSkill.minion
    end

    it("grants Earthquake + Swipe to the bear, deterministically ordered after the base kit", function()
        local env, minion = loadSynth()
        local ids = {}
        for i, as in ipairs(minion.activeSkillList) do
            ids[i] = as.activeEffect.grantedEffect.id
        end
        assert.are.equals("PrimalBear 01 melee attack", ids[1],
            "base kit melee must stay the default selected skill")
        -- grants sort by their ORIGINAL skillId (EarthquakeSlam < Swipe), then the
        -- weapon-base clone renames each to <skillId>_MinionWeaponBase (<see git log>)
        assert.are.equals("EarthquakeSlam_MinionWeaponBase", ids[2], "granted skills sorted by skillId")
        assert.are.equals("Swipe_MinionWeaponBase", ids[3])
    end)

    it("bear-tree and companion MOREs reach the bear's melee (lv26 = level scaling neutral)", function()
        local env, minion = loadSynth()
        local cfg = minion.mainSkill.skillCfg
        local more = minion.modDB:More(cfg, "Damage")
        -- 1.75 (ActorStats) x 1.5 (Lacerating Claws 5pt MORE) x 1.75 (Natural
        -- Bond) x 1.85 (Artor's Loyalty) = 8.4984...; charLevel 26 keeps the
        -- minion-level MORE at exactly 1.0.
        local expected = 1.75 * 1.5 * 1.75 * 1.85
        assert.is_true(math.abs(more - expected) < 0.005,
            ("minion melee MORE chain = %.4f, expected %.4f"):format(more, expected))
        -- Forceful Swipes flat: +1 melee phys per 3 player Strength, PerStat
        -- re-pointed at the parent actor (bear has no Strength of its own).
        local str = env.player.output.Str or 0
        assert.is_true(str > 0, "player must have Strength for the PerStat leg")
        local flat = minion.modDB:Sum("BASE", cfg, "PhysicalDamage")
        assert.is_true(math.abs(flat - str / 3) < 0.01,
            ("bear flat melee phys = %.3f, expected Str/3 = %.3f"):format(flat, str / 3))
    end)

    it("bear crit chance/multiplier match the in-game contract (base CM 2.0, tree-added)", function()
        local env, minion = loadSynth()
        local mo = env.player.output.Minion
        -- base 5% + be36ar-16#3 (+12%) = 17, matching the in-game bear sheet
        assert.are.equals(17, mo.CritChance)
        -- base 2.0 (NO +30%% PoB-ism) + be36ar-17#4 (+100%%) = 3.0; in-game
        -- DNRT shows 3.11 = this 3.0 plus its ring implicit roll (11%%).
        assert.is_true(math.abs(mo.CritMultiplier - 3.0) < 0.001,
            ("bear CritMultiplier = %s, expected 3.0"):format(tostring(mo.CritMultiplier)))
    end)

    it("the granted EQ clone decouples from the -60% SkillName:Earthquake node and carries its own eff-6 MORE", function()
        local env, minion = loadSynth()
        local byId = {}
        for _, as in ipairs(minion.activeSkillList) do
            byId[as.activeEffect.grantedEffect.id] = as
        end
        local melee = byId["PrimalBear 01 melee attack"]
        local eq = byId["EarthquakeSlam_MinionWeaponBase"]
        local swipe = byId["Swipe_MinionWeaponBase"]
        assert.is_table(eq, "the EQ grant must be the weapon-base clone")
        assert.is_table(swipe, "the Swipe grant must be the weapon-base clone")
        -- F4 oracle (DoNotReleaseThem, 2026-07-01): the bear EQ element-MORE == Melee's
        -- (9.9, no x0.4), so the -60% node be36ar-15 does NOT apply in-game; the clone's
        -- skillNameForMatch id keeps SkillName:Earthquake mods (incl. the -60%) detached.
        local meleeMore = minion.modDB:More(melee.skillCfg, "Damage")
        local eqMore = minion.modDB:More(eq.skillCfg, "Damage")
        local swipeMore = minion.modDB:More(swipe.skillCfg, "Damage")
        assert.is_true(math.abs(eqMore / meleeMore - 1.0) < 0.005,
            ("EQ modDB MORE/melee MORE = %.4f, expected 1.00 (the -60%% must NOT re-attach to the clone)"):format(eqMore / meleeMore))
        assert.is_true(math.abs(swipeMore / meleeMore - 1.0) < 0.005,
            "Swipe must not catch any Earthquake-scoped mods")
        -- eff 6 rides the EQ clone's own skillModList as a Hit-scoped MORE
        -- (6 / bear-melee eff 1 - 1) * 100 = +500. Seismic Tide (eq5s-21) is NOT
        -- allocated in this synth build, so its slam-sum MORE must be absent.
        local effMore, tideMore
        for _, m in ipairs(eq.skillModList) do
            if m.source == "MinionWeaponAttackEffectiveness" then effMore = m end
            if m.source == "MinionEarthquakeSeismicTide" then tideMore = m end
        end
        assert.is_table(effMore, "the EQ clone must carry the MinionWeaponAttackEffectiveness MORE")
        assert.are.equals("MORE", effMore.type)
        assert.are.equals(500, effMore.value)
        assert.is_nil(tideMore, "the Seismic Tide MORE must stay gated on eq5s-21 allocation")
        for _, m in ipairs(swipe.skillModList) do
            assert.is_true(m.source ~= "MinionWeaponAttackEffectiveness" and m.source ~= "MinionEarthquakeSeismicTide",
                "the Swipe clone declares no minionAttackEffectiveness/slam grant fields and must carry neither MORE")
        end
    end)
end)
