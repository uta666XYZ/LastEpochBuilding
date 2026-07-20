-- @leb-regression-guard:htsk5-10-cold-conversion
-- See REGRESSION_GUARDS.md "htsk5-10-cold-conversion".
-- Validation provenance is retained in maintainer notes.

describe("ColdConversion #skills", function()
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

	it("registry: rewrite turns ' Cold Conversion' into the 'Physical -> Cold' arrow ONLY", function()
		assert.are.equal("Physical -> Cold", applyRewrites("htsk5-10", " Cold Conversion"))
		-- leading-space-tolerant (the live tree string carries a leading space)
		assert.are.equal("Physical -> Cold", applyRewrites("htsk5-10", "Cold Conversion"))
		-- the node's OTHER stats must NOT be touched
		assert.are.equal(" Bleed -> Frostbite Chance", applyRewrites("htsk5-10", " Bleed -> Frostbite Chance"))
		assert.are.equal("40 Base Freeze Rate", applyRewrites("htsk5-10", "40 Base Freeze Rate"))
	end)

	it("registry: htsk5-10 is scoped to its own skill (NOT lifted to global scope)", function()
		assert.is_table(LE_TREE_NODE_GLOBAL_SCOPE, "LE_TREE_NODE_GLOBAL_SCOPE must be defined")
		assert.is_nil(LE_TREE_NODE_GLOBAL_SCOPE["htsk5-10"],
			"Controlled Icicle converts only Heartseeker's base damage, so the default SkillId scope must stay -- do NOT global-lift")
		-- the OTHER node that shares the bare ' Cold Conversion' string is a DIFFERENT
		-- source type (ga2st-26 Frostbringer = Lightning->Cold) and must NOT be swept
		-- into this Physical-sourced rewrite registry
		assert.is_nil(LE_TREE_NODE_STAT_REWRITE["ga2st-26"], "ga2st-26 (Gathering Storm, Lightning->Cold) must NOT be rewritten as Physical")
	end)

	it("parse contract: 'Physical -> Cold' -> a SINGLE PhysicalDamageConvertToCold BASE 100, no tag", function()
		local list, extra = modLib.parseMod("Physical -> Cold")
		assert.is_not_nil(list, "must parse")
		assert.is_true(not extra or extra == "", "must leave no residue, got: " .. tostring(extra))
		-- single source type (Physical only) -- this is the faithfulness check vs the
		-- all-types-convert skillBaseDamageConversionHandler form
		assert.are.equal(1, #list)
		local mod = list[1]
		assert.are.equal("PhysicalDamageConvertToCold", mod.name)
		assert.are.equal("BASE", mod.type)
		assert.are.equal(100, mod.value)
		-- the plain type arrow carries NO parser tag: scoping comes from the tree node
		assert.is_nil(mod[1], "global type arrow must NOT carry a SkillName/SkillId tag")
	end)

	it("tree node end-to-end: htsk5-10 emits PhysicalDamageConvertToCold BASE 100 scoped to Heartseeker (SkillId kept)", function()
		newBuild()
		local node = build.spec.nodes["htsk5-10"]
		assert.is_not_nil(node, "htsk5-10 must exist in the loaded 1.4 tree")
		assert.are.equal("Heartseeker", node.skillId,
			"htsk5-10 must scope to the Heartseeker skill (treeId htsk5 -> skill 'Heartseeker')")
		node.alloc = 1
		build.spec.tree:ProcessStats(node)
		local found
		for _, mod in ipairs(node.modList) do
			if mod.name == "PhysicalDamageConvertToCold" and mod.type == "BASE" then found = mod end
		end
		assert.is_not_nil(found, "Controlled Icicle must emit a PhysicalDamageConvertToCold BASE mod")
		assert.are.equal(100, found.value)
		local skillIdTag = findTag(found, "SkillId")
		assert.is_not_nil(skillIdTag, "the SkillId scoping must be KEPT -- the conversion only applies to Heartseeker")
		assert.are.equal("Heartseeker", skillIdTag.skillId)
	end)

	it("behaviour: conversionTable[Physical][Cold] == 1.0 (mult 0), Physical-only, scoped to Heartseeker", function()
		newBuild()
		local node = build.spec.nodes["htsk5-10"]
		node.alloc = 1
		build.spec.tree:ProcessStats(node)

		local hsCfg = { skillGrantedEffect = { id = node.skillId } }
		local otherCfg = { skillGrantedEffect = { id = "Some Other Skill" } }

		-- replicate CalcOffence's conversionTable build (CalcOffence.lua ~1704/1731):
		--   globalConv[Cold] = skillModList:Sum("BASE", skillCfg, "PhysicalDamageConvertToCold")
		--   conversionTable[Physical][Cold] = globalConv[Cold] / 100
		--   conversionTable[Physical].mult   = 1 - min(globalTotal/100, 1)
		local phys2cold = node.modList:Sum("BASE", hsCfg, "PhysicalDamageConvertToCold")
		assert.are.equal(100, phys2cold, "Physical->Cold must sum to 100 under the Heartseeker cfg")
		assert.are.equal(1.0, phys2cold / 100, "conversionTable[Physical][Cold] must be 1.0 (100%)")
		assert.are.equal(0, 1 - math.min(phys2cold / 100, 1),
			"the Physical share retained after conversion (mult) must be 0 -- all Physical becomes Cold")

		-- FAITHFULNESS: only Physical converts (the datamining converts type 0 ONLY).
		-- A different (all-types) handler would also recolour any non-physical added
		-- base on Heartseeker to Cold -- which the game does NOT do.
		assert.are.equal(0, node.modList:Sum("BASE", hsCfg, "FireDamageConvertToCold"),
			"Fire base must NOT convert (Controlled Icicle is Physical-only)")
		assert.are.equal(0, node.modList:Sum("BASE", hsCfg, "LightningDamageConvertToCold"),
			"Lightning base must NOT convert (Controlled Icicle is Physical-only -- this is the ga2st-26 source type, not htsk5-10)")

		-- SCOPE: a non-Heartseeker skill (and the global nil cfg) must see nothing.
		assert.are.equal(0, node.modList:Sum("BASE", otherCfg, "PhysicalDamageConvertToCold"),
			"conversion must NOT leak to another skill")
		assert.are.equal(0, node.modList:Sum("BASE", nil, "PhysicalDamageConvertToCold"),
			"conversion must NOT apply globally (nil cfg)")
	end)

	it("node-keyed: the sibling ga2st-26 ' Cold Conversion' (Lightning source) is NOT rewritten to Physical", function()
		-- ga2st-26 shares the bare display string but has no rewrite entry, so its
		-- " Cold Conversion" stays the inert ModCache row (its real Lightning->Cold
		-- source is a separate follow-up; the point here is htsk5-10's Physical
		-- rewrite must NOT leak onto it).
		assert.is_nil(LE_TREE_NODE_STAT_REWRITE["ga2st-26"])
		-- applying htsk5-10's rules to ga2st-26's string is NOT what the engine does
		-- (rewrites are keyed by node id), but prove the key isolation explicitly:
		local hs = LE_TREE_NODE_STAT_REWRITE["htsk5-10"]
		assert.is_not_nil(hs)
	end)

	it("ModCache: the shared ' Cold Conversion' inert row is deliberately KEPT (ga2st-26 needs it)", function()
		local src = readFile("Data/ModCache.lua")
		assert.is_not_nil(src, "must read Data/ModCache.lua")
		assert.is_truthy(src:find('c[" Cold Conversion"]', 1, true),
			"the inert ' Cold Conversion' row must REMAIN (ga2st-26 still emits it and must stay inert; the rewrite intercepts htsk5-10 before parseMod)")
	end)

	it("game-file: htsk5-10 still carries the ' Cold Conversion' stat and the convert-to-cold description", function()
		local tree = readFile("TreeData/1_4/tree_4.json")
		assert.is_not_nil(tree, "must read TreeData/1_4/tree_4.json")
		assert.is_truthy(tree:find('"htsk5%-10"', 1, false))
		assert.is_truthy(tree:find("Controlled Icicle", 1, true))
		assert.is_truthy(tree:find(" Cold Conversion", 1, true),
			"the ' Cold Conversion' stat string the rewrite keys on must still be present")
		assert.is_truthy(tree:find("base physical damage is converted to cold", 1, true),
			"the convert-to-cold description that justifies the rewrite must still be present")
	end)
end)
