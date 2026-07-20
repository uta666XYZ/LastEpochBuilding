-- @leb-regression-guard:falcon-avian-arsenal-buff
-- See REGRESSION_GUARDS.md "falcon-avian-arsenal-buff".
-- Validation provenance is retained in maintainer notes.

local function findTag(mod, tagType, var)
	for _, tag in ipairs(mod) do
		if tag.type == tagType and (var == nil or tag.var == var) then
			return tag
		end
	end
	return nil
end

describe("FalconAvianArsenal #falcon parser contract", function()

	it("'N% Character Damage -> Falcon Damage' parses to a player FalconAvianArsenalPercent BASE percent", function()
		local list = modLib.parseMod("10% Character Damage -> Falcon Damage")
		assert.is_table(list, "the node stat must parse to a mod list")
		assert.are.equals("FalconAvianArsenalPercent", list[1].name)
		assert.are.equals("BASE", list[1].type)
		assert.are.equals(10, list[1].value)
		-- player-scoped percent, NOT a MinionModifier wrapper (routing is done in CalcPerform)
		assert.are_not.equals("MinionModifier", list[1].name)
	end)

	it("carries a Multiplier:FalconAvianArsenalStacks tag (folds the config stack-count; drives the ifMult gate)", function()
		local list = modLib.parseMod("10% Character Damage -> Falcon Damage")
		assert.is_not_nil(findTag(list[1], "Multiplier", "FalconAvianArsenalStacks"),
			"the percent mod must reference Multiplier:FalconAvianArsenalStacks so a Sum yields percent x stacks")
	end)

	it("the whole line is consumed (nil extra so PassiveTree keeps the mod)", function()
		local _, extra = modLib.parseMod("10% Character Damage -> Falcon Damage")
		assert.is_nil(extra, "extra must be nil -- a non-empty residue is dropped at the tree gate")
	end)

	it("the live parser covers tree-scaled (non-cached) magnitudes too (30% at 3/3)", function()
		-- The tree scales the leading number before parse, so 3/3 -> "30% ...". Only the
		-- base "10% ..." string is in ModCache; the scaled strings exercise the live rule.
		local list = modLib.parseMod("30% Character Damage -> Falcon Damage")
		assert.are.equals("FalconAvianArsenalPercent", list[1].name)
		assert.are.equals(30, list[1].value)
	end)
end)

describe("FalconAvianArsenal #falcon routing", function()
	before_each(function()
		newBuild()
	end)

	-- Build a Falcon minion with a player added pool (customMods) + the node percent line,
	-- and the two Avian Arsenal config inputs (pool selector val + stack count).
	local function falconMinion(mods, pool, stacks)
		build.skillsTab:SelSkill(1, "Falconer 00 Falconry")
		build.configTab.input.customMods = mods or ""
		build.configTab.input.falconAvianArsenalPool = pool   -- nil / 0 = Off (default)
		build.configTab.input.falconAvianArsenalStacks = stacks -- nil / 0 = default
		build.configTab:BuildModList()
		runCallback("OnFrame")
		local minion = build.calcsTab.mainEnv.minion
		assert.is_not_nil(minion, "expected env.minion = RogueFalcon")
		assert.are.equals("RogueFalcon", minion.type)
		return minion
	end

	local function falconMelee(minion)
		return minion.modDB:Sum("BASE", { keywordFlags = KeywordFlag.Melee }, "FireDamage")
	end

	it("routes N% x stacks of the selected pool onto the Falcon as MELEE flat added", function()
		-- Bow pool, 10% node, 5 stacks -> 50% -> frac 0.5; player +40 Bow Fire -> 40 x 0.5 = 20
		local minion = falconMinion(
			"+40 Bow Fire Damage\n10% Character Damage -> Falcon Damage\n", 2048, 5)
		assert.are.equals(20, falconMelee(minion),
			"Falcon must gain 50% (10% x 5) of the player's added bow fire, as melee")
	end)

	it("RE-TAG: a Throwing-pool transfer still lands on the Falcon as MELEE (unlike Avian Hurl)", function()
		local minion = falconMinion(
			"+40 Throwing Fire Damage\n10% Character Damage -> Falcon Damage\n", 1024, 5)
		assert.are.equals(20, falconMelee(minion),
			"the throwing pool is granted to the Falcon re-tagged MELEE (Avian Arsenal grants melee)")
		assert.are.equals(0, minion.modDB:Sum("BASE", { keywordFlags = KeywordFlag.Throwing }, "FireDamage"),
			"the transfer must NOT be throwing-tagged on the Falcon (melee re-tag only)")
	end)

	it("POOL: only the selected pool's adds transfer (bow selected -> spell stays behind)", function()
		local minion = falconMinion(
			"+40 Bow Fire Damage\n+80 Spell Fire Damage\n10% Character Damage -> Falcon Damage\n", 2048, 5)
		assert.are.equals(20, falconMelee(minion),
			"only the +40 bow pool is picked (40 x 0.5 = 20); the +80 spell pool is not selected")
	end)

	it("STACKS: the transfer scales with the stack count (percent x stacks)", function()
		-- 10% node, 3 stacks -> 30% -> frac 0.3 -> 40 x 0.3 = 12
		local minion = falconMinion(
			"+40 Bow Fire Damage\n10% Character Damage -> Falcon Damage\n", 2048, 3)
		assert.are.equals(12, falconMelee(minion), "3 stacks -> 30% -> 40 x 0.3 = 12")
	end)

	it("SCOPED: player INC of the pool is NOT transferred (added-flat only)", function()
		local minion = falconMinion(
			"+40 Bow Fire Damage\n100% increased Bow Damage\n10% Character Damage -> Falcon Damage\n", 2048, 5)
		assert.are.equals(20, falconMelee(minion),
			"only the +40 added flat transfers at 50%; player INC bow stays player-side")
	end)

	it("CONTROL: default config (pool Off, stacks 0) -> inert even with the node % present", function()
		local minion = falconMinion("+40 Bow Fire Damage\n10% Character Damage -> Falcon Damage\n")
		assert.are.equals(0, falconMelee(minion),
			"corpus-neutral: with defaults the buff does nothing even when the node is allocated")
	end)

	it("CONTROL: pool selected but 0 stacks -> inert (buff applies only when stacks > 0)", function()
		local minion = falconMinion("+40 Bow Fire Damage\n10% Character Damage -> Falcon Damage\n", 2048, 0)
		assert.are.equals(0, falconMelee(minion), "stacks 0 -> percent Sum 0 -> inert")
	end)

	it("CONTROL: stacks set but pool Off -> inert", function()
		local minion = falconMinion("+40 Bow Fire Damage\n10% Character Damage -> Falcon Damage\n", 0, 5)
		assert.are.equals(0, falconMelee(minion), "pool Off -> no keyword -> inert")
	end)
end)

describe("FalconAvianArsenal #falcon source contract", function()
	local function readFile(path)
		local f = io.open(path, "r") or io.open("src/" .. path, "r")
		assert.is_not_nil(f, "must read " .. path)
		local s = f:read("*a"); f:close()
		return s
	end

	it("CalcPerform routes on the RogueFalcon modDB, keyword-gated to the config pool, re-tagged Melee", function()
		local src = readFile("Modules/CalcPerform.lua")
		assert.is_truthy(src:find("@leb-regression-guard:falcon-avian-arsenal-buff", 1, true),
			"guard marker must be present")
		assert.is_truthy(src:find("FalconAvianArsenalPercent", 1, true),
			"routing must read the player percent mod FalconAvianArsenalPercent")
		assert.is_truthy(src:find("FalconAvianArsenalPoolKeyword", 1, true),
			"routing must read the config-selected pool keyword")
		assert.is_truthy(src:find("env.minion.type == \"RogueFalcon\"", 1, true),
			"routing must be scoped to the RogueFalcon minion")
		assert.is_truthy(src:find("band(srcMod.keywordFlags, arsenalPoolKw)", 1, true),
			"the copied source must be keyword-gated to the selected pool")
		assert.is_truthy(src:find("copy.keywordFlags = KeywordFlag.Melee", 1, true),
			"the copied mod must be re-tagged MELEE")
		assert.is_truthy(src:find("env.minion.modDB:AddMod(copy)", 1, true),
			"the scaled/re-tagged mod must be added to the MINION modDB")
	end)

	it("config: both inputs are ifMult-gated and default OFF", function()
		local src = readFile("Modules/ConfigOptions.lua")
		local poolEntry = src:match('{ var = "falconAvianArsenalPool".-end },')
		assert.is_not_nil(poolEntry, "falconAvianArsenalPool config entry must exist")
		assert.is_truthy(poolEntry:find('type = "list"', 1, true))
		assert.is_truthy(poolEntry:find('ifMult = "FalconAvianArsenalStacks"', 1, true),
			"pool selector must be visibility-gated on the FalconAvianArsenalStacks multiplier")
		assert.is_truthy(poolEntry:find("defaultIndex = 1", 1, true),
			"pool selector must default to the first option (Off)")
		assert.is_truthy(poolEntry:find('NewMod("FalconAvianArsenalPoolKeyword"', 1, true),
			"pool apply must set FalconAvianArsenalPoolKeyword")

		local stackEntry = src:match('{ var = "falconAvianArsenalStacks".-end },')
		assert.is_not_nil(stackEntry, "falconAvianArsenalStacks config entry must exist")
		assert.is_truthy(stackEntry:find('type = "count"', 1, true))
		assert.is_truthy(stackEntry:find('ifMult = "FalconAvianArsenalStacks"', 1, true),
			"stack count must be visibility-gated on the FalconAvianArsenalStacks multiplier")
		assert.is_truthy(stackEntry:find("max 5", 1, true), "label must carry the cap hint '(max 5)'")
		assert.is_truthy(stackEntry:find('NewMod("Multiplier:FalconAvianArsenalStacks"', 1, true),
			"stack apply must set Multiplier:FalconAvianArsenalStacks")
		assert.is_truthy(stackEntry:find("math.min(val, 5)", 1, true),
			"stack count must be capped at 5 (property 54 = 5 max stacks)")
	end)

	it("ModCache: row 10491 rebaked to the clean player percent mod (not empty, not a bogus generic Damage)", function()
		local src = readFile("Data/ModCache.lua")
		local row = src:match('c%["10%% Character Damage %-> Falcon Damage"%]=(.-)\n')
		assert.is_not_nil(row, "the Avian Arsenal ModCache row must be present")
		assert.is_truthy(row:find("FalconAvianArsenalPercent", 1, true),
			"the row must bake the clean player percent mod (rescoped, not the residue no-op)")
		assert.is_truthy(row:find("FalconAvianArsenalStacks", 1, true),
			"the row must carry the Multiplier:FalconAvianArsenalStacks tag")
		assert.is_nil(row:find('c%["10%% Character Damage %-> Falcon Damage"%]={{},'),
			"the row must NOT be the empty-list residue-drop no-op")
	end)

	it("game-file: falc0-4 still carries the Avian Arsenal stat + consume-mark description", function()
		local tree = readFile("TreeData/1_4/tree_4.json")
		assert.is_truthy(tree:find("Avian Arsenal", 1, true))
		assert.is_truthy(tree:find("10% Character Damage -> Falcon Damage", 1, true),
			"the stat string the parse rule keys on must still be present")
		assert.is_truthy(tree:find("consume a {Falconer's Mark}", 1, true),
			"the consume-mark description that grounds the mechanic must still be present")
	end)
end)
