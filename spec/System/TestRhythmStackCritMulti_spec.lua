-- @leb-regression-guard:rhythm-stack-crit-multi
-- See REGRESSION_GUARDS.md "rhythm-stack-crit-multi".
-- Validation provenance is retained in maintainer notes.

describe("RhythmStackCritMulti #skills", function()
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

	it("registry: rewrites append 'per stack of Rhythm' to both Rhythm-family stats", function()
		assert.are.equal("+10% Global Critical Multiplier per stack of Rhythm",
			applyRewrites("dacn33-26", "+10% Global Critical Multiplier"))
		assert.are.equal("3% Global More Damage per stack of Rhythm",
			applyRewrites("dacn33-23", "3% Global More Damage"))
		-- Value-tolerant: a re-tuned per-point value still rewrites.
		assert.are.equal("+12% Global Critical Multiplier per stack of Rhythm",
			applyRewrites("dacn33-26", "+12% Global Critical Multiplier"))
		-- dacn33-23's other lines must NOT be touched.
		assert.are.equal("+2 Rhythm Maximum Stacks",
			applyRewrites("dacn33-23", "+2 Rhythm Maximum Stacks"))
		assert.are.equal("2 Rhythm Duration (seconds)",
			applyRewrites("dacn33-23", "2 Rhythm Duration (seconds)"))
	end)

	it("registry: LE_TREE_NODE_GLOBAL_SCOPE lifts SkillId for exactly the two Rhythm nodes", function()
		assert.is_table(LE_TREE_NODE_GLOBAL_SCOPE, "LE_TREE_NODE_GLOBAL_SCOPE must be defined in Global.lua")
		assert.is_true(LE_TREE_NODE_GLOBAL_SCOPE["dacn33-26"] == true)
		assert.is_true(LE_TREE_NODE_GLOBAL_SCOPE["dacn33-23"] == true)
		-- Scope guard: keep this registry tight — siblings like dacn33-25
		-- ("+5% Global Bleed Chance Per Stack") are NOT wired and must not be
		-- silently swept in without their own verification.
		assert.is_nil(LE_TREE_NODE_GLOBAL_SCOPE["dacn33-25"])
	end)

	it("parse contract: crit-mult line -> BASE CritMultiplier x Multiplier:RhythmStacks (limit 10), no residue", function()
		local list, extra = modLib.parseMod("+20% Global Critical Multiplier per stack of Rhythm")
		assert.is_not_nil(list, "must parse")
		assert.is_true(not extra or extra == "", "must leave no residue, got: " .. tostring(extra))
		assert.are.equal(1, #list)
		local mod = list[1]
		assert.are.equal("CritMultiplier", mod.name)
		assert.are.equal("BASE", mod.type)
		assert.are.equal(20, mod.value)
		local mult = findTag(mod, "Multiplier", "RhythmStacks")
		assert.is_not_nil(mult, "must carry Multiplier:RhythmStacks")
		assert.are.equal(10, mult.limit, "limit must cap at 10 (2 x 5/5 Rhythm)")
		assert.is_nil(findTag(mod, "SkillId"), "parse must not produce a SkillId tag")
	end)

	it("parse contract: more-damage line -> MORE Damage x Multiplier:RhythmStacks, no residue", function()
		local list, extra = modLib.parseMod("3% Global More Damage per stack of Rhythm")
		assert.is_not_nil(list, "must parse")
		assert.is_true(not extra or extra == "", "must leave no residue, got: " .. tostring(extra))
		assert.are.equal(1, #list)
		local mod = list[1]
		assert.are.equal("Damage", mod.name)
		assert.are.equal("MORE", mod.type)
		assert.are.equal(3, mod.value)
		local mult = findTag(mod, "Multiplier", "RhythmStacks")
		assert.is_not_nil(mult, "must carry Multiplier:RhythmStacks")
		assert.are.equal(10, mult.limit, "limit must cap at 10 (2 x 5/5 Rhythm)")
		assert.is_nil(findTag(mod, "SkillId"), "parse must not produce a SkillId tag")
	end)

	it("tree node end-to-end: dacn33-26 at 2/2 emits a GLOBAL Multiplier-tagged mod (no SkillId)", function()
		newBuild()
		local node = build.spec.nodes["dacn33-26"]
		assert.is_not_nil(node, "dacn33-26 must exist in the loaded 1.4 tree")
		assert.is_not_nil(node.skillId, "dacn33-26 must be a skill-subtree node (skillId set)")
		node.alloc = 2
		build.spec.tree:ProcessStats(node)
		local found
		for _, mod in ipairs(node.modList) do
			if mod.name == "CritMultiplier" then found = mod end
		end
		assert.is_not_nil(found, "Art of Blades must emit a CritMultiplier mod")
		assert.are.equal("BASE", found.type)
		assert.are.equal(20, found.value, "2/2 must rank-scale to 20")
		assert.is_not_nil(findTag(found, "Multiplier", "RhythmStacks"),
			"the node mod must be per-Rhythm-stack")
		assert.is_nil(findTag(found, "SkillId"),
			"the SkillId scoping must be LIFTED — in-game the effect is GLOBAL (player sheet)")
	end)

	it("tree node end-to-end: dacn33-23 notScalingStat emits global per-stack MORE Damage", function()
		newBuild()
		local node = build.spec.nodes["dacn33-23"]
		assert.is_not_nil(node, "dacn33-23 must exist in the loaded 1.4 tree")
		node.alloc = 5
		build.spec.tree:ProcessStats(node)
		local found
		for _, mod in ipairs(node.modList) do
			if mod.name == "Damage" and mod.type == "MORE" then found = mod end
		end
		assert.is_not_nil(found, "Rhythm must emit the per-stack MORE Damage mod")
		assert.are.equal(3, found.value, "notScalingStats must NOT rank-scale (3 at any rank)")
		assert.is_not_nil(findTag(found, "Multiplier", "RhythmStacks"))
		assert.is_nil(findTag(found, "SkillId"))
	end)

	it("behaviour: config 0 (default) is a strict no-op; 10 stacks add +200 crit multi; capped at 10", function()
		newBuild()
		build.itemsTab:CreateDisplayItemFromRaw([[Rarity: RARE
		Brass Sceptre
		Brass Sceptre
		+20% Global Critical Multiplier per stack of Rhythm]])
		build.itemsTab:AddDisplayItem()
		build.skillsTab:SelSkill(1, "Runemaster 05c3 Runebolt Cold")

		-- 0 stacks (default) -> no Rhythm contribution
		build.configTab.input["multiplierRhythmStacks"] = 0
		build.configTab:BuildModList()
		runCallback("OnFrame")
		local cm0 = build.calcsTab.mainOutput.CritMultiplier
		assert.is_not_nil(cm0)

		-- 10 stacks -> +20 x 10 = +200 added -> +2.00 on the output multiplier
		build.configTab.input["multiplierRhythmStacks"] = 10
		build.configTab:BuildModList()
		runCallback("OnFrame")
		assert.are.equals(round(cm0 + 2.00, 2), round(build.calcsTab.mainOutput.CritMultiplier, 2))

		-- cap: 15 stacks must still be 10 (the parser limit)
		build.configTab.input["multiplierRhythmStacks"] = 15
		build.configTab:BuildModList()
		runCallback("OnFrame")
		assert.are.equals(round(cm0 + 2.00, 2), round(build.calcsTab.mainOutput.CritMultiplier, 2))
	end)

	it("behaviour: 3% More Damage per stack is additive across stacks -> x1.30 at 10", function()
		newBuild()
		build.itemsTab:CreateDisplayItemFromRaw([[Rarity: RARE
		Brass Sceptre
		Brass Sceptre
		3% Global More Damage per stack of Rhythm]])
		build.itemsTab:AddDisplayItem()
		build.skillsTab:SelSkill(1, "Runemaster 05c3 Runebolt Cold")

		build.configTab.input["multiplierRhythmStacks"] = 0
		build.configTab:BuildModList()
		runCallback("OnFrame")
		local dps0 = build.calcsTab.mainOutput.TotalDPS
		assert.is_true(dps0 > 0)

		build.configTab.input["multiplierRhythmStacks"] = 10
		build.configTab:BuildModList()
		runCallback("OnFrame")
		assert.are.equals(round(dps0 * 1.30, 2), round(build.calcsTab.mainOutput.TotalDPS, 2))
	end)

	it("behaviour: a build WITHOUT any Rhythm mod ignores the config entirely", function()
		newBuild()
		build.skillsTab:SelSkill(1, "Runemaster 05c3 Runebolt Cold")

		build.configTab.input["multiplierRhythmStacks"] = 0
		build.configTab:BuildModList()
		runCallback("OnFrame")
		local cm0 = build.calcsTab.mainOutput.CritMultiplier
		local dps0 = build.calcsTab.mainOutput.TotalDPS

		build.configTab.input["multiplierRhythmStacks"] = 10
		build.configTab:BuildModList()
		runCallback("OnFrame")
		assert.are.equals(cm0, build.calcsTab.mainOutput.CritMultiplier)
		assert.are.equals(dps0, build.calcsTab.mainOutput.TotalDPS)
	end)

	it("config: '# of Rhythm Stacks' is ifMult-gated (visible only when referenced) with the cap hint", function()
		local src = readFile("Modules/ConfigOptions.lua")
		assert.is_not_nil(src, "must read Modules/ConfigOptions.lua")
		local entry = src:match('{ var = "multiplierRhythmStacks".-end },')
		assert.is_not_nil(entry, "multiplierRhythmStacks config entry must exist")
		assert.is_truthy(entry:find('type = "count"', 1, true))
		assert.is_truthy(entry:find('ifMult = "RhythmStacks"', 1, true),
			"must be visibility-gated on the RhythmStacks multiplier being referenced (Throne pattern)")
		assert.is_truthy(entry:find("max 10 at 5/5 Rhythm", 1, true),
			"label must carry the cap hint '(max 10 at 5/5 Rhythm)'")
		assert.is_truthy(entry:find('NewMod("Multiplier:RhythmStacks", "BASE", val, "Config"', 1, true),
			"apply must set Multiplier:RhythmStacks")
	end)

	it("source: PassiveTree lifts SkillId via LE_TREE_NODE_GLOBAL_SCOPE and rewrites notScalingStats", function()
		local pt = readFile("Classes/PassiveTree.lua")
		assert.is_not_nil(pt, "must read Classes/PassiveTree.lua")
		assert.is_truthy(pt:find("@leb%-regression%-guard:rhythm%-stack%-crit%-multi", 1, false),
			"PassiveTree.lua must carry the inline guard marker")
		assert.is_truthy(pt:find("node%.skillId and not LE_TREE_NODE_GLOBAL_SCOPE%[node%.id%]", 1, false),
			"the SkillId tag append must consult LE_TREE_NODE_GLOBAL_SCOPE")
		-- notScalingStats lines must run through the same rewrite registry
		-- (dacn33-23's per-stack line lives there).
		local nsBlock = pt:match("for _,stat in ipairs%(node%.notScalingStats%) do(.-)end")
		assert.is_not_nil(nsBlock, "notScalingStats loop must exist")
		assert.is_truthy(nsBlock:find("statRewrites", 1, true),
			"notScalingStats lines must apply LE_TREE_NODE_STAT_REWRITE")
	end)

	it("game-file: the two Rhythm nodes still carry the stats and per-stack descriptions", function()
		local tree = readFile("TreeData/1_4/tree_4.json")
		assert.is_not_nil(tree, "must read TreeData/1_4/tree_4.json")
		assert.is_truthy(tree:find('"dacn33%-26"', 1, false))
		assert.is_truthy(tree:find('"dacn33%-23"', 1, false))
		assert.is_truthy(tree:find("Art of Blades", 1, true))
		assert.is_truthy(tree:find("+10% Global Critical Multiplier", 1, true),
			"the Art of Blades stat string the rewrite keys on must still be present")
		assert.is_truthy(tree:find("Your critical strikes deal more damage per stack of {Rhythm}", 1, true),
			"the per-stack description that justifies the rewrite must still be present")
		assert.is_truthy(tree:find("3% Global More Damage", 1, true),
			"the Rhythm notScalingStat the rewrite keys on must still be present")
		assert.is_truthy(tree:find("granting you global more damage per stack", 1, true),
			"the per-stack More Damage description must still be present")
		assert.is_truthy(tree:find("+2 Rhythm Maximum Stacks", 1, true),
			"the max-stacks stat backing the limit=10 cap must still be present")
	end)
end)
