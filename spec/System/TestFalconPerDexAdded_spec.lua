-- @leb-regression-guard:falcon-per-dex-added
-- Falconry per-Dexterity added-damage nodes route added damage onto the Falcon
-- (RogueFalcon), scaling off the PLAYER's Dexterity.
--
-- Game ground truth (datamining, no fabrication):
--   FalconryMutator: falconMeleeDamagePer4Dex  -> Stats.AddedStat(tag 0x200=Melee,
--   Dex * value * 0.25); falconThrowingDamagePer4Dex -> tag 0x400=Throwing. Two
--   SEPARATE tag-specific stats (NOT a global add). Tree tree_4.json:
--     L31   "+1 Falcon Melee Damage per 4 Dexterity" (Falconer ascendancy start)
--     L2296 "+1 Falcon Throwing Damage Per 4 Dex"
--   Rem-MK3 runtime dump (Dex 263): 65.75 added on both t512 (Melee) and t1024
--   (Throwing) = 263/4 -> div=4, value 1, reading the PLAYER's Dex.
--
-- ModCache baked both as a player-side Damage BASE PerStat + " Falcon " residue,
-- so the Falcon got neither (residue dropped at the tree gate; scope wrong).
-- Fix routes via MinionModifier{minionTypes={"RogueFalcon"}} with the inner PerStat
-- reading actor="parent" Dex and div=4, keeping each add tag-specific
-- (KeywordFlag.Melee 512 / Throwing 1024).
--
-- SCOPE: added-damage routing only. The residual to close per-hit magnitude vs the
-- capture (Falconer's Mark consume) is DEFER -- no curve-fit. Feather Knives grant
-- is the sibling landing (falcon-feather-knives-grant).
--
-- Regression to prevent: a ModCache regen / upstream re-sync reverting either row to
-- the player-side "{{...}, ' Falcon '}" residue no-op (dropping the Falcon add), a
-- global (keywordFlags 0) add that double-counts, or a minionTypes drop that leaks
-- the add to every minion. See REGRESSION_GUARDS.md "falcon-per-dex-added".

local function falconAdd(list)
	assert.is_table(list, "the node stat must parse to a mod list")
	assert.are.equals("MinionModifier", list[1].name)
	assert.are.equals("LIST", list[1].type)
	assert.are.equals("RogueFalcon", list[1].value.minionTypes[1])
	return list[1].value.mod
end

describe("FalconPerDexAdded #falcon parser contract", function()

	it("melee node routes a RogueFalcon-scoped Melee (512) Damage BASE per player Dex/4", function()
		local m = falconAdd(modLib.parseMod("+1 Falcon Melee Damage per 4 Dexterity"))
		assert.are.equals("Damage", m.name)
		assert.are.equals("BASE", m.type)
		assert.are.equals(1, m.value)
		assert.are.equals(512, m.keywordFlags)
		assert.are.equals("PerStat", m[1].type)
		assert.are.equals("parent", m[1].actor)
		assert.are.equals("Dex", m[1].stat)
		assert.are.equals(4, m[1].div)
	end)

	it("throwing node routes a RogueFalcon-scoped Throwing (1024) Damage BASE per player Dex/4", function()
		local m = falconAdd(modLib.parseMod("+1 Falcon Throwing Damage Per 4 Dex"))
		assert.are.equals("Damage", m.name)
		assert.are.equals("BASE", m.type)
		assert.are.equals(1, m.value)
		assert.are.equals(1024, m.keywordFlags)
		assert.are.equals("PerStat", m[1].type)
		assert.are.equals("parent", m[1].actor)
		assert.are.equals("Dex", m[1].stat)
		assert.are.equals(4, m[1].div)
	end)

	it("both lines are fully consumed (nil extra so PassiveTree keeps the mod)", function()
		local _, meleeExtra = modLib.parseMod("+1 Falcon Melee Damage per 4 Dexterity")
		local _, throwExtra = modLib.parseMod("+1 Falcon Throwing Damage Per 4 Dex")
		assert.is_nil(meleeExtra, "melee extra must be nil -- a non-empty residue is dropped at the tree gate")
		assert.is_nil(throwExtra, "throwing extra must be nil -- a non-empty residue is dropped at the tree gate")
	end)
end)
