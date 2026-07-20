-- @leb-regression-guard:rive-temporal-warrior-void-conversion
-- See REGRESSION_GUARDS.md "rive-temporal-warrior-void-conversion".
-- Validation provenance is retained in maintainer notes.

describe("RiveVoidConversion #skills", function()
	local function readFile(path)
		local f = io.open(path, "r") or io.open("src/" .. path, "r")
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

	local function findTag(mod, tagType)
		for _, tag in ipairs(mod) do
			if tag.type == tagType then return tag end
		end
		return nil
	end

	it("registry: rewrite turns ' Void Conversion' into the 'Physical -> Void' arrow ONLY", function()
		assert.are.equal("Physical -> Void", applyRewrites("sndr1-5", " Void Conversion"))
		-- leading-space-tolerant (the live tree string carries a leading space)
		assert.are.equal("Physical -> Void", applyRewrites("sndr1-5", "Void Conversion"))
		-- the node's OTHER stats must NOT be touched
		assert.are.equal(" Bleed -> Time Rot Chance", applyRewrites("sndr1-5", " Bleed -> Time Rot Chance"))
		assert.are.equal(" Doubles Echo Chance", applyRewrites("sndr1-5", " Doubles Echo Chance"))
	end)

	it("registry: sndr1-5 is scoped to its own skill (NOT lifted to global scope)", function()
		assert.is_table(LE_TREE_NODE_GLOBAL_SCOPE, "LE_TREE_NODE_GLOBAL_SCOPE must be defined")
		assert.is_nil(LE_TREE_NODE_GLOBAL_SCOPE["sndr1-5"],
			"Temporal Warrior converts only Rive's base damage, so the default SkillId scope must stay -- do NOT global-lift")
		-- the OTHER nodes that share the bare ' Void Conversion' string belong to
		-- different skills and must NOT be swept into the rewrite registry
		assert.is_nil(LE_TREE_NODE_STAT_REWRITE["gs15de-18"], "gs15de-18 (Vengeance) must NOT be rewritten")
		assert.is_nil(LE_TREE_NODE_STAT_REWRITE["sm87r4-32"], "sm87r4-32 (Smite) must NOT be rewritten")
	end)

	it("parse contract: 'Physical -> Void' -> a SINGLE PhysicalDamageConvertToVoid BASE 100, no tag", function()
		local list, extra = modLib.parseMod("Physical -> Void")
		assert.is_not_nil(list, "must parse")
		assert.is_true(not extra or extra == "", "must leave no residue, got: " .. tostring(extra))
		-- single source type (Physical only) -- this is the faithfulness check vs the
		-- all-types-convert skillBaseDamageConversionHandler form (which would emit 6)
		assert.are.equal(1, #list)
		local mod = list[1]
		assert.are.equal("PhysicalDamageConvertToVoid", mod.name)
		assert.are.equal("BASE", mod.type)
		assert.are.equal(100, mod.value)
		-- the plain type arrow carries NO parser tag: scoping comes from the tree node
		assert.is_nil(mod[1], "global type arrow must NOT carry a SkillName/SkillId tag")
	end)

	it("tree node end-to-end: sndr1-5 emits PhysicalDamageConvertToVoid BASE 100 scoped to Rive (SkillId kept)", function()
		newBuild()
		local node = build.spec.nodes["sndr1-5"]
		assert.is_not_nil(node, "sndr1-5 must exist in the loaded 1.4 tree")
		assert.are.equal("Rive1", node.skillId,
			"sndr1-5 must scope to the Rive skill (treeId sndr1 -> skill 'Rive1')")
		node.alloc = 1
		build.spec.tree:ProcessStats(node)
		local found
		for _, mod in ipairs(node.modList) do
			if mod.name == "PhysicalDamageConvertToVoid" and mod.type == "BASE" then found = mod end
		end
		assert.is_not_nil(found, "Temporal Warrior must emit a PhysicalDamageConvertToVoid BASE mod")
		assert.are.equal(100, found.value)
		local skillIdTag = findTag(found, "SkillId")
		assert.is_not_nil(skillIdTag, "the SkillId scoping must be KEPT -- the conversion only applies to Rive")
		assert.are.equal("Rive1", skillIdTag.skillId)
	end)

	it("behaviour: conversionTable[Physical][Void] == 1.0 (mult 0), Physical-only, scoped to Rive", function()
		newBuild()
		local node = build.spec.nodes["sndr1-5"]
		node.alloc = 1
		build.spec.tree:ProcessStats(node)

		local riveCfg = { skillGrantedEffect = { id = node.skillId } }
		local otherCfg = { skillGrantedEffect = { id = "Some Other Skill" } }

		-- replicate CalcOffence's conversionTable build (CalcOffence.lua ~1704/1731):
		--   globalConv[Void] = skillModList:Sum("BASE", skillCfg, "PhysicalDamageConvertToVoid")
		--   conversionTable[Physical][Void] = globalConv[Void] / 100
		--   conversionTable[Physical].mult   = 1 - min(globalTotal/100, 1)
		local phys2void = node.modList:Sum("BASE", riveCfg, "PhysicalDamageConvertToVoid")
		assert.are.equal(100, phys2void, "Physical->Void must sum to 100 under the Rive cfg")
		assert.are.equal(1.0, phys2void / 100, "conversionTable[Physical][Void] must be 1.0 (100%)")
		assert.are.equal(0, 1 - math.min(phys2void / 100, 1),
			"the Physical share retained after conversion (mult) must be 0 -- all Physical becomes Void")

		-- FAITHFULNESS: only Physical converts (the datamining converts type 0 ONLY).
		-- A different (all-types) handler would also convert these, recolouring any
		-- non-physical added base on Rive to Void -- which the game does NOT do.
		assert.are.equal(0, node.modList:Sum("BASE", riveCfg, "FireDamageConvertToVoid"),
			"Fire base must NOT convert (Temporal Warrior is Physical-only)")
		assert.are.equal(0, node.modList:Sum("BASE", riveCfg, "LightningDamageConvertToVoid"),
			"Lightning base must NOT convert (Temporal Warrior is Physical-only)")

		-- SCOPE: a non-Rive skill (and the global nil cfg) must see nothing.
		assert.are.equal(0, node.modList:Sum("BASE", otherCfg, "PhysicalDamageConvertToVoid"),
			"conversion must NOT leak to another skill")
		assert.are.equal(0, node.modList:Sum("BASE", nil, "PhysicalDamageConvertToVoid"),
			"conversion must NOT apply globally (nil cfg)")
	end)

	it("ModCache: the shared ' Void Conversion' inert row is deliberately KEPT (other-skill nodes need it)", function()
		local src = readFile("Data/ModCache.lua")
		assert.is_not_nil(src, "must read Data/ModCache.lua")
		assert.is_truthy(src:find('c[" Void Conversion"]', 1, true),
			"the inert ' Void Conversion' row must REMAIN (gs15de-18 / sm87r4-32 still emit it and must stay inert; the rewrite intercepts sndr1-5 before parseMod)")
	end)

	it("game-file: sndr1-5 still carries the ' Void Conversion' stat and the convert-to-void description", function()
		local tree = readFile("TreeData/1_4/tree_2.json")
		assert.is_not_nil(tree, "must read TreeData/1_4/tree_2.json")
		assert.is_truthy(tree:find('"sndr1%-5"', 1, false))
		assert.is_truthy(tree:find("Temporal Warrior", 1, true))
		assert.is_truthy(tree:find(" Void Conversion", 1, true),
			"the ' Void Conversion' stat string the rewrite keys on must still be present")
		assert.is_truthy(tree:find("base physical damage is converted to void", 1, true),
			"the convert-to-void description that justifies the rewrite must still be present")
	end)
end)
