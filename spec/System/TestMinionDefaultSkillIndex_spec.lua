-- @leb-regression-guard:minion-default-skill-index
-- See REGRESSION_GUARDS.md "minion-default-skill-index".
-- Validation provenance is retained in maintainer notes.
describe("MinionDefaultSkillIndex", function()
	before_each(function()
		newBuild()
	end)

	local function minionMainSkillName()
		local minion = build.calcsTab.mainEnv.minion
		assert.is_not_nil(minion, "expected env.minion")
		local ms = minion.mainSkill
		return ms and ms.activeEffect and ms.activeEffect.grantedEffect and ms.activeEffect.grantedEffect.name
	end

	it("data: LE_MINION_DEFAULT_SKILL_INDEX pins SummonedAbomination to index 2 (Melee Attack)", function()
		assert.are.equals(2, LE_MINION_DEFAULT_SKILL_INDEX["SummonedAbomination"])
	end)

	it("Assemble Abomination defaults its minion sub-skill to Melee Attack (index 2), not Devour (index 1)", function()
		build.skillsTab:SelSkill(1, "AssembleAbomination")
		runCallback("OnFrame")
		assert.are.equals("Melee Attack", minionMainSkillName())
	end)

	-- @leb-regression-guard:falcon-default-skill-aerial-assault
	-- RogueFalcon skillList = ["RogueFalcon Melee" (placeholder), "RogueFalcon Diving
	-- Attack" (Surge = the innate Aerial Assault / Falcon Strikes)]. The Rem-MK3 capture
	-- logs the Falcon's damage under ONLY "Aerial Assault" + "Feather Knives" (no Melee),
	-- so index 1 was the wrong (placeholder) sub-skill. Same class as SummonedAbomination.
	it("data: LE_MINION_DEFAULT_SKILL_INDEX pins RogueFalcon to index 2 (Diving Attack = Aerial Assault)", function()
		assert.are.equals(2, LE_MINION_DEFAULT_SKILL_INDEX["RogueFalcon"])
	end)

	it("Falconry defaults its Falcon sub-skill to Diving Attack (index 2), not the Melee placeholder (index 1)", function()
		build.skillsTab:SelSkill(1, "Falconer 00 Falconry")
		runCallback("OnFrame")
		-- grantedEffect.name of skillList[2] "RogueFalcon Diving Attack" is "Surge" (the
		-- Falcon's Aerial Assault dive); index 1 "RogueFalcon Melee" would be "Rogue Falcon Melee".
		assert.are.equals("Surge", minionMainSkillName())
		local minion = build.calcsTab.mainEnv.minion
		assert.are.equal(minion.activeSkillList[2], minion.mainSkill)
	end)

	it("control: a minion whose skillList[1] IS its attack (Bone Golem) still defaults to index 1", function()
		-- proves the override is per-minion (table-gated), not a global shift of the
		-- index-1 default for every other minion.
		assert.is_nil(LE_MINION_DEFAULT_SKILL_INDEX["SummonedBoneGolem"])
		build.skillsTab:SelSkill(1, "SummonBoneGolem")
		runCallback("OnFrame")
		local minion = build.calcsTab.mainEnv.minion
		assert.is_not_nil(minion, "expected env.minion")
		assert.are.equal(minion.activeSkillList[1], minion.mainSkill)
	end)
end)
