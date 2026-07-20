-- @leb-regression-guard:falcon-avian-hurl-conversion
-- from the datamining subset). See REGRESSION_GUARDS.md "falcon-avian-hurl-conversion".
-- Validation provenance is retained in maintainer notes.

describe("FalconAvianHurl #falcon parser contract", function()

	it("'N% Added Throwing Damage Conversion To Falcon' parses to a player FalconAddedThrowingConversion BASE percent", function()
		local list = modLib.parseMod("50% Added Throwing Damage Conversion To Falcon")
		assert.is_table(list, "the node stat must parse to a mod list")
		assert.are.equals("FalconAddedThrowingConversion", list[1].name)
		assert.are.equals("BASE", list[1].type)
		assert.are.equals(50, list[1].value)
		-- player-scoped percent, NOT a MinionModifier wrapper (routing is done in CalcPerform)
		assert.are_not.equals("MinionModifier", list[1].name)
	end)

	it("the whole line is consumed (nil extra so PassiveTree keeps the mod)", function()
		local _, extra = modLib.parseMod("50% Added Throwing Damage Conversion To Falcon")
		assert.is_nil(extra, "extra must be nil -- a non-empty residue is dropped at the tree gate")
	end)
end)

describe("FalconAvianHurl #falcon routing", function()
	before_each(function()
		newBuild()
	end)

	local function falconMinion(mods)
		build.skillsTab:SelSkill(1, "Falconer 00 Falconry")
		build.configTab.input.customMods = mods or ""
		build.configTab:BuildModList()
		runCallback("OnFrame")
		local minion = build.calcsTab.mainEnv.minion
		assert.is_not_nil(minion, "expected env.minion = RogueFalcon")
		assert.are.equals("RogueFalcon", minion.type)
		return minion
	end

	it("routes 50% of the player's added throwing flat onto the Falcon as BOTH Melee and Throwing", function()
		local minion = falconMinion(
			"+40 Throwing Fire Damage\n50% Added Throwing Damage Conversion To Falcon\n")
		-- The player has +40 throwing FireDamage; the Falcon must get 50% = 20, and
		-- because the transfer is re-tagged Melee|Throwing (ANY-match) it lands for a
		-- throwing hit (Feather Knives) AND a melee hit (Aerial Assault).
		assert.are.equals(20, minion.modDB:Sum("BASE", { keywordFlags = KeywordFlag.Throwing }, "FireDamage"),
			"Falcon must gain 50% of the player's added throwing fire on a throwing hit")
		assert.are.equals(20, minion.modDB:Sum("BASE", { keywordFlags = KeywordFlag.Melee }, "FireDamage"),
			"the same transfer must also apply to the Falcon's melee hit (Aerial Assault)")
	end)

	it("CONTROL: without Avian Hurl (no conversion mod) the player's added throwing does NOT reach the Falcon", function()
		local minion = falconMinion("+40 Throwing Fire Damage\n")
		assert.are.equals(0, minion.modDB:Sum("BASE", { keywordFlags = KeywordFlag.Throwing }, "FireDamage"),
			"no conversion mod -> no routing (the Falcon does not inherit player added throwing by default)")
	end)

	it("CONTROL: Avian Hurl with no player added throwing is inert (Rem-MK3 = 0 -> corpus-neutral)", function()
		local minion = falconMinion("50% Added Throwing Damage Conversion To Falcon\n")
		assert.are.equals(0, minion.modDB:Sum("BASE", { keywordFlags = KeywordFlag.Throwing }, "FireDamage"),
			"nothing in the player's added-throwing pool -> nothing transfers")
	end)

	it("SCOPED: player INC throwing damage is NOT transferred (added-flat only)", function()
		-- The mechanic transfers ADDED flat, not the player's own increased/more scaling.
		local minion = falconMinion(
			"+40 Throwing Fire Damage\n100% increased Throwing Damage\n50% Added Throwing Damage Conversion To Falcon\n")
		-- Only the +40 flat is halved to 20; the +100% INC stays player-side (it is the
		-- player's scaling, not "added damage"). If INC leaked, the routed flat would differ.
		assert.are.equals(20, minion.modDB:Sum("BASE", { keywordFlags = KeywordFlag.Throwing }, "FireDamage"),
			"only the added flat transfers at 50%; player INC throwing must stay behind")
	end)
end)

describe("FalconAvianHurl #falcon source contract", function()

	it("CalcPerform routes on the RogueFalcon modDB, keyword-gated to Throwing, scaled by pct/100", function()
		local f = io.open("Modules/CalcPerform.lua", "r") or io.open("src/Modules/CalcPerform.lua", "r")
		assert.is_not_nil(f, "must read Modules/CalcPerform.lua")
		local src = f:read("*a"); f:close()
		assert.is_truthy(src:find("@leb-regression-guard:falcon-avian-hurl-conversion", 1, true),
			"guard marker must be present")
		assert.is_truthy(src:find("FalconAddedThrowingConversion", 1, true),
			"routing must read the player percent mod FalconAddedThrowingConversion")
		assert.is_truthy(src:find("env.minion.type == \"RogueFalcon\"", 1, true),
			"routing must be scoped to the RogueFalcon minion")
		assert.is_truthy(src:find("band(srcMod.keywordFlags, KeywordFlag.Throwing)", 1, true),
			"the copied source must be keyword-gated to the player's THROWING adds")
		assert.is_truthy(src:find("env.minion.modDB:AddMod(copy)", 1, true),
			"the scaled/re-tagged mod must be added to the MINION modDB")
	end)
end)
