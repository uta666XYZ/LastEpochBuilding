-- @leb-regression-guard:berserk-stack-melee-damage
-- See REGRESSION_GUARDS.md "berserk-stack-melee-damage".
-- Validation provenance is retained in maintainer notes.

describe("BerserkStackMeleeDamage #skills", function()
	local function readFile(path)
		local f = io.open(path, "r")
		if not f then return nil end
		local s = f:read("*a"); f:close()
		return s
	end

	local function applyRewrites(nodeId, stat)
		local entry = LE_TREE_NODE_STAT_REWRITE[nodeId]
		assert.is_not_nil(entry, nodeId .. " must be registered in LE_TREE_NODE_STAT_REWRITE")
		for _, rw in ipairs(entry) do
			stat = (stat:gsub(rw.pat, rw.repl))
		end
		return stat
	end

	local function findTag(mod, tagType, var)
		for _, tag in ipairs(mod) do
			if tag.type == tagType and (var == nil or tag.var == var) then
				return tag
			end
		end
		return nil
	end

	it("registry: rewrite appends 'per stack of Berserk' to the Berserker melee stat only", function()
		assert.are.equal("+4 Melee Damage per stack of Berserk",
			applyRewrites("wc57-22", "+4 Melee Damage Per Stack"))
		-- value-tolerant (a re-tuned per-stack value still rewrites)
		assert.are.equal("+6 Melee Damage per stack of Berserk",
			applyRewrites("wc57-22", "+6 Melee Damage Per Stack"))
		-- the node's OTHER stats must NOT be touched
		assert.are.equal(" Berserk On Use", applyRewrites("wc57-22", " Berserk On Use"))
		assert.are.equal("+1 Berserk Stacks On Hit While Berserk",
			applyRewrites("wc57-22", "+1 Berserk Stacks On Hit While Berserk"))
		assert.are.equal("10 Maximum Stacks", applyRewrites("wc57-22", "10 Maximum Stacks"))
	end)

	it("registry: LE_TREE_NODE_GLOBAL_SCOPE lifts SkillId for wc57-22 only", function()
		assert.is_table(LE_TREE_NODE_GLOBAL_SCOPE, "LE_TREE_NODE_GLOBAL_SCOPE must be defined")
		assert.is_true(LE_TREE_NODE_GLOBAL_SCOPE["wc57-22"] == true)
		-- scope guard: sibling Berserk nodes (Brutality/Bloodthirst/Fury Strikes)
		-- are NOT swept into the global-scope lift without their own verification.
		assert.is_nil(LE_TREE_NODE_GLOBAL_SCOPE["wc57-24"])
		assert.is_nil(LE_TREE_NODE_GLOBAL_SCOPE["wc57-25"])
		assert.is_nil(LE_TREE_NODE_GLOBAL_SCOPE["wc57-26"])
	end)

	it("parse contract: rewritten line -> BASE Damage (Melee) x Multiplier:BerserkStacks (limit 15), no residue", function()
		local list, extra = modLib.parseMod("+4 Melee Damage per stack of Berserk")
		assert.is_not_nil(list, "must parse")
		assert.is_true(not extra or extra == "", "must leave no residue, got: " .. tostring(extra))
		assert.are.equal(1, #list)
		local mod = list[1]
		assert.are.equal("Damage", mod.name)
		assert.are.equal("BASE", mod.type)
		assert.are.equal(4, mod.value)
		assert.are.equal(KeywordFlag.Melee, mod.keywordFlags, "must be melee-scoped")
		local mult = findTag(mod, "Multiplier", "BerserkStacks")
		assert.is_not_nil(mult, "must carry Multiplier:BerserkStacks")
		assert.are.equal(15, mult.limit, "limit must cap at 15 (10 + 5/5 Brutality)")
		assert.is_nil(findTag(mod, "SkillId"), "parse must not produce a SkillId tag")
	end)

	it("tree node end-to-end: wc57-22 emits a GLOBAL melee BASE Damage mod (no SkillId)", function()
		newBuild()
		local node = build.spec.nodes["wc57-22"]
		assert.is_not_nil(node, "wc57-22 must exist in the loaded 1.4 tree")
		assert.is_not_nil(node.skillId, "wc57-22 must be a skill-subtree node (skillId set)")
		node.alloc = 1
		build.spec.tree:ProcessStats(node)
		local found
		for _, mod in ipairs(node.modList) do
			if mod.name == "Damage" and mod.type == "BASE" then found = mod end
		end
		assert.is_not_nil(found, "Berserker must emit a BASE Damage mod")
		assert.are.equal(4, found.value)
		assert.are.equal(KeywordFlag.Melee, found.keywordFlags)
		assert.is_not_nil(findTag(found, "Multiplier", "BerserkStacks"),
			"the node mod must be per-Berserk-stack")
		assert.is_nil(findTag(found, "SkillId"),
			"the SkillId scoping must be LIFTED -- in-game Berserk melee is GLOBAL")
	end)

	it("behaviour: config 0 (default) is a strict no-op; 15 stacks add +60 melee BASE; capped at 15", function()
		newBuild()
		build.itemsTab:CreateDisplayItemFromRaw([[Rarity: RARE
		Brass Sceptre
		Brass Sceptre
		+4 Melee Damage per stack of Berserk]])
		build.itemsTab:AddDisplayItem()
		local meleeCfg = { keywordFlags = KeywordFlag.Melee }
		local function meleeBase()
			return build.calcsTab.mainEnv.player.modDB:Sum("BASE", meleeCfg, "Damage")
		end

		-- 0 stacks (default) -> no Berserk contribution
		build.configTab.input["multiplierBerserkStacks"] = 0
		build.configTab:BuildModList()
		runCallback("OnFrame")
		local base0 = meleeBase()

		-- 15 stacks -> +4 x 15 = +60
		build.configTab.input["multiplierBerserkStacks"] = 15
		build.configTab:BuildModList()
		runCallback("OnFrame")
		assert.are.equal(base0 + 60, meleeBase())

		-- cap: 20 stacks must still be +60 (the parser limit 15)
		build.configTab.input["multiplierBerserkStacks"] = 20
		build.configTab:BuildModList()
		runCallback("OnFrame")
		assert.are.equal(base0 + 60, meleeBase())
	end)

	it("behaviour: a build WITHOUT any Berserk mod ignores the config entirely", function()
		newBuild()
		local meleeCfg = { keywordFlags = KeywordFlag.Melee }
		local function meleeBase()
			return build.calcsTab.mainEnv.player.modDB:Sum("BASE", meleeCfg, "Damage")
		end

		build.configTab.input["multiplierBerserkStacks"] = 0
		build.configTab:BuildModList()
		runCallback("OnFrame")
		local base0 = meleeBase()

		build.configTab.input["multiplierBerserkStacks"] = 15
		build.configTab:BuildModList()
		runCallback("OnFrame")
		assert.are.equal(base0, meleeBase())
	end)

	it("config: '# of Berserk Stacks' is ifMult-gated (visible only when referenced) with the cap hint", function()
		local src = readFile("Modules/ConfigOptions.lua")
		assert.is_not_nil(src, "must read Modules/ConfigOptions.lua")
		local entry = src:match('{ var = "multiplierBerserkStacks".-end },')
		assert.is_not_nil(entry, "multiplierBerserkStacks config entry must exist")
		assert.is_truthy(entry:find('type = "count"', 1, true))
		assert.is_truthy(entry:find('ifMult = "BerserkStacks"', 1, true),
			"must be visibility-gated on the BerserkStacks multiplier being referenced (Throne pattern)")
		assert.is_truthy(entry:find("max 15 at 5/5 Brutality", 1, true),
			"label must carry the cap hint '(max 15 at 5/5 Brutality)'")
		assert.is_truthy(entry:find('NewMod("Multiplier:BerserkStacks", "BASE", val, "Config"', 1, true),
			"apply must set Multiplier:BerserkStacks")
	end)

	it("game-file: wc57-22 still carries the melee stat and the per-stack/global description", function()
		local tree = readFile("TreeData/1_4/tree_0.json")
		assert.is_not_nil(tree, "must read TreeData/1_4/tree_0.json")
		assert.is_truthy(tree:find('"wc57%-22"', 1, false))
		assert.is_truthy(tree:find("Berserker", 1, true))
		assert.is_truthy(tree:find("+4 Melee Damage Per Stack", 1, true),
			"the Berserker stat string the rewrite keys on must still be present")
		assert.is_truthy(tree:find("granting you additional melee", 1, true),
			"the per-stack melee-damage description that justifies the rewrite must still be present")
		assert.is_truthy(tree:find("10 Maximum Stacks", 1, true),
			"the max-stacks stat backing the cap must still be present")
	end)
end)
