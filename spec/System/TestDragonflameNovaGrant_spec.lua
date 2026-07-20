-- @leb-regression-guard:dragonflame-nova-grant
-- Dragonflame Edict (unique staff) mod "60% Chance for the nearest minion to the
-- target location to cast Dragonflame Nova when you use a minion skill (1 second
-- cooldown)" grants the summoned minion a Dragonflame Nova sub-skill. ModCache
-- baked the line as LEB_NotSupported, so the proc was a silent no-op -- the last
-- open root on the ACG-3 (Necromancer swarm) board row.
--
-- Game ground truth (no fabrication):
--   * data.skills.DragonfireNova already carries the datamined base: "Dragonflame
--     Nova", spell_base_fire_damage 80, damageEffectiveness 4, crit 5% x2.0,
--     spell hit (skills.json; per-hit grounded per the minion multiroot (4) board).
--   * "Nearest minion to the target location" = whichever minion is out -> the
--     grant carries NO minionList, so createMinionSkills applies it to ANY minion
--     type (CalcActiveSkill: `not skill.minionList or isValueInArray(...)`).
--
-- SCOPE: per-hit grant + kit ordering. Granted skills append AFTER the minion's
-- base kit, so the minion's main / FullDPS skill is unchanged. The proc RATE is
-- now rated separately -- both factors turned out datamine-grounded (chance =
-- affix property 98 value 0.6; 1s CD = text constant), so the line ALSO emits
-- ChanceToTriggerOnMinionSkillUse_DragonfireNova 60 + TriggerRateCapPerSecond_
-- DragonfireNova 1, folded in Calcs.lua calcFullDPS -- see the sibling guard
-- dragonflame-nova-proc-rate / TestDragonflameNovaProcRate_spec.lua.
--
-- Regression to prevent: a ModCache regen reverting the row to LEB_NotSupported
-- (re-silencing the proc), the grant acquiring a minionList (breaking the
-- any-minion semantics), or a skills.json edit changing the datamined base.
-- See REGRESSION_GUARDS.md "dragonflame-nova-grant".

local AFFIX = "60% Chance for the nearest minion to the target location to cast Dragonflame Nova when you use a minion skill (1 second cooldown)"

describe("DragonflameNovaGrant #minion parser contract", function()

	it("the Dragonflame Edict proc line emits an any-minion ExtraMinionSkill grant", function()
		local list = modLib.parseMod(AFFIX)
		assert.is_table(list, "the affix must parse to a mod list (not LEB_NotSupported)")
		assert.are.equals("ExtraMinionSkill", list[1].name)
		assert.are.equals("LIST", list[1].type)
		assert.are.equals("DragonfireNova", list[1].value.skillId)
		assert.is_nil(list[1].value.minionList, "no minionList -- 'nearest minion' applies to ANY minion type")
		assert.is_nil(list[1].notSupported, "must not carry the notSupported marker")
	end)

	it("the whole line is consumed (nil extra)", function()
		local _, extra = modLib.parseMod(AFFIX)
		assert.is_nil(extra, "extra must be nil -- a non-empty residue drops the mod")
	end)
end)

describe("DragonflameNovaGrant #minion data contract", function()

	it("DragonfireNova carries the datamined Fire 80 / eff 4.0 spell base", function()
		local s = data.skills.DragonfireNova
		assert.is_table(s, "DragonfireNova must exist in data.skills")
		assert.are.equals("Dragonflame Nova", s.name)
		assert.are.equals(80, s.stats.spell_base_fire_damage)
		assert.are.equals(4, s.stats.damageEffectiveness)
		assert.are.equals(100, s.stats["base_critical_strike_multiplier_+"])
		assert.is_true(s.baseFlags.spell)
		assert.is_true(s.baseFlags.hit)
	end)
end)

describe("DragonflameNovaGrant #minion routing", function()
	before_each(function()
		newBuild()
	end)

	local function summonWithAffix(summonSkill)
		build.skillsTab:SelSkill(1, summonSkill)
		build.configTab.input.customMods = AFFIX .. "\n"
		build.configTab:BuildModList()
		runCallback("OnFrame")
		local minion = build.calcsTab.mainEnv.minion
		assert.is_not_nil(minion, "expected env.minion")
		return minion
	end

	local function findGranted(minion)
		for _, s in ipairs(minion.activeSkillList or { }) do
			local ge = s.activeEffect and s.activeEffect.grantedEffect
			if ge and ge.name == "Dragonflame Nova" then
				return s
			end
		end
		return nil
	end

	it("a summoned minion gains the Dragonflame Nova sub-skill", function()
		local minion = summonWithAffix("SummonBoneGolem")
		assert.is_not_nil(findGranted(minion), "the Bone Golem must carry the granted Dragonflame Nova")
	end)

	it("any-minion: a DIFFERENT minion type gains it too (no minionList gate)", function()
		local minion = summonWithAffix("SummonBear")
		assert.is_not_nil(findGranted(minion), "the bear must also carry the granted Dragonflame Nova")
	end)

	it("the grant does NOT displace the minion's main (FullDPS) skill", function()
		local minion = summonWithAffix("SummonBoneGolem")
		assert.are.equal(minion.activeSkillList[1], minion.mainSkill,
			"granted skills append after the base kit -- the scored default must stay index 1")
	end)

	it("CONTROL: without the affix no Dragonflame Nova exists on the minion", function()
		build.skillsTab:SelSkill(1, "SummonBoneGolem")
		runCallback("OnFrame")
		local minion = build.calcsTab.mainEnv.minion
		assert.is_not_nil(minion, "expected env.minion")
		assert.is_nil(findGranted(minion), "no staff mod -> no granted nova")
	end)

	-- @leb-regression-guard:minion-grant-replacement-in-place
	-- The pyromancer REPLACEMENT grant must stand in the mage's base-kit slot even
	-- when an additive grant co-exists. Before the in-place fix, the emptied base
	-- kit put every grant into one sorted pool and "DragonfireNova" won index 1
	-- alphabetically -> the PROC became the mage's scored main skill and FullDPS
	-- tripled (QqwprgdN 32497 -> 99650). These cases pin the ordering.
	it("REPLACEMENT-IN-PLACE: Skeletal Mage + Pyromancers + nova keeps Fireball as the scored main", function()
		build.skillsTab:SelSkill(1, "SummonMage")
		build.configTab.input.customMods = " Adds Pyromancers\n" .. AFFIX .. "\n"
		build.configTab:BuildModList()
		runCallback("OnFrame")
		local minion = build.calcsTab.mainEnv.minion
		assert.is_not_nil(minion, "expected env.minion = SummonedSkeletonMage")
		local main = minion.mainSkill
		local mainName = main and main.activeEffect and main.activeEffect.grantedEffect and main.activeEffect.grantedEffect.name
		assert.are.equals("Fireball", mainName,
			"the pyromancer replacement must occupy the base-kit slot (index 1), not the alphabetically-first grant")
		assert.are.equal(minion.activeSkillList[1], main, "the scored default stays index 1")
		assert.is_not_nil(findGranted(minion), "the nova is still granted (appended after the kit)")
	end)

	it("REPLACEMENT-IN-PLACE control: pyromancer replacement alone is unchanged (Fireball main)", function()
		build.skillsTab:SelSkill(1, "SummonMage")
		build.configTab.input.customMods = " Adds Pyromancers\n"
		build.configTab:BuildModList()
		runCallback("OnFrame")
		local minion = build.calcsTab.mainEnv.minion
		assert.is_not_nil(minion, "expected env.minion = SummonedSkeletonMage")
		local mainName = minion.mainSkill and minion.mainSkill.activeEffect and minion.mainSkill.activeEffect.grantedEffect
			and minion.mainSkill.activeEffect.grantedEffect.name
		assert.are.equals("Fireball", mainName, "single replacement grant: same result as before the fix")
	end)
end)
