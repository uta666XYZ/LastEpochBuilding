-- @leb-regression-guard:flaming-sword-fire-conversion
-- See REGRESSION_GUARDS.md "flaming-sword-fire-conversion".
-- Validation provenance is retained in maintainer notes.

describe("FlamingSwordFireConversion #skills", function()
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

	it("registry: rewrite turns ' Fire Conversion' into 'Physical -> Fire' and leaves the sibling stats untouched", function()
		assert.are.equal("Physical -> Fire", applyRewrites("gs15de-8", " Fire Conversion"))
		assert.are.equal("Physical -> Fire", applyRewrites("gs15de-8", "Fire Conversion"))
		-- the node's OTHER two stats must NOT be touched ($-anchored)
		assert.are.equal(" Physical -> Fire Res Shred Chance", applyRewrites("gs15de-8", " Physical -> Fire Res Shred Chance"))
		assert.are.equal(" Bleed -> Ignite Chance", applyRewrites("gs15de-8", " Bleed -> Ignite Chance"))
	end)

	it("registry: gs15de-8 is scoped to its own skill (NOT lifted to global scope)", function()
		assert.is_table(LE_TREE_NODE_GLOBAL_SCOPE, "LE_TREE_NODE_GLOBAL_SCOPE must be defined")
		assert.is_nil(LE_TREE_NODE_GLOBAL_SCOPE["gs15de-8"],
			"Flaming Sword converts only Vengeance's base damage, so the default SkillId scope must stay -- do NOT global-lift")
		-- the Void-sourced sharer of the same bare string must NOT be swept into this
		-- Physical-sourced rewrite registry.
		assert.is_nil(LE_TREE_NODE_STAT_REWRITE["vr53sl-18"], "vr53sl-18 (Volatile Reversal, Void->Fire) must NOT be rewritten as Physical")
	end)

	it("parse contract: 'Physical -> Fire' -> a SINGLE PhysicalDamageConvertToFire BASE 100, no tag", function()
		local list, extra = modLib.parseMod("Physical -> Fire")
		assert.is_not_nil(list, "must parse")
		assert.is_true(not extra or extra == "", "must leave no residue, got: " .. tostring(extra))
		assert.are.equal(1, #list)
		local mod = list[1]
		assert.are.equal("PhysicalDamageConvertToFire", mod.name)
		assert.are.equal("BASE", mod.type)
		assert.are.equal(100, mod.value)
		assert.is_nil(mod[1], "global type arrow must NOT carry a SkillName/SkillId tag")
	end)

	it("tree node end-to-end: gs15de-8 emits PhysicalDamageConvertToFire BASE 100 scoped to Vengeance (SkillId kept)", function()
		newBuild()
		local node = build.spec.nodes["gs15de-8"]
		assert.is_not_nil(node, "gs15de-8 must exist in the loaded 1.4 tree")
		assert.are.equal("Vengeance", node.skillId,
			"gs15de-8 must scope to the Vengeance skill (treeId gs15de -> skill 'Vengeance')")
		node.alloc = 1
		build.spec.tree:ProcessStats(node)
		local found
		for _, mod in ipairs(node.modList) do
			if mod.name == "PhysicalDamageConvertToFire" and mod.type == "BASE" then found = mod end
		end
		assert.is_not_nil(found, "Flaming Sword must emit a PhysicalDamageConvertToFire BASE mod")
		assert.are.equal(100, found.value)
		local skillIdTag = findTag(found, "SkillId")
		assert.is_not_nil(skillIdTag, "the SkillId scoping must be KEPT -- the conversion only applies to Vengeance")
		assert.are.equal("Vengeance", skillIdTag.skillId)
	end)

	it("behaviour: conversionTable[Physical][Fire] == 1.0 (Physical-only), scoped to Vengeance", function()
		newBuild()
		local node = build.spec.nodes["gs15de-8"]
		node.alloc = 1
		build.spec.tree:ProcessStats(node)

		local venCfg = { skillGrantedEffect = { id = node.skillId } }
		local otherCfg = { skillGrantedEffect = { id = "Some Other Skill" } }

		local phys2fire = node.modList:Sum("BASE", venCfg, "PhysicalDamageConvertToFire")
		assert.are.equal(100, phys2fire, "Physical->Fire must sum to 100 under the Vengeance cfg")
		assert.are.equal(1.0, phys2fire / 100, "conversionTable[Physical][Fire] must be 1.0 (100%)")
		assert.are.equal(0, 1 - math.min(phys2fire / 100, 1),
			"the Physical share retained after conversion must be 0 -- all Physical becomes Fire")

		-- FAITHFULNESS: only Physical converts (the tag swap is Physical->Fire ONLY).
		assert.are.equal(0, node.modList:Sum("BASE", venCfg, "ColdDamageConvertToFire"),
			"Cold base must NOT convert (Flaming Sword is Physical-only)")
		assert.are.equal(0, node.modList:Sum("BASE", venCfg, "VoidDamageConvertToFire"),
			"Void base must NOT convert (Void->Fire is the vr53sl-18 source type, not gs15de-8)")

		-- SCOPE: a non-Vengeance skill (and the global nil cfg) must see nothing.
		assert.are.equal(0, node.modList:Sum("BASE", otherCfg, "PhysicalDamageConvertToFire"),
			"conversion must NOT leak to another skill")
		assert.are.equal(0, node.modList:Sum("BASE", nil, "PhysicalDamageConvertToFire"),
			"conversion must NOT apply globally (nil cfg)")
	end)

	it("ModCache: the shared ' Fire Conversion' inert row is deliberately KEPT (vr53sl-18 still needs it)", function()
		local src = readFile("Data/ModCache.lua")
		assert.is_not_nil(src, "must read Data/ModCache.lua")
		assert.is_truthy(src:find('c[" Fire Conversion"]', 1, true),
			"the inert ' Fire Conversion' row must REMAIN (vr53sl-18 still emits it and must stay inert; the rewrite intercepts gs15de-8 before parseMod)")
	end)

	it("game-file: gs15de-8 still carries the ' Fire Conversion' stat and the convert-to-fire description", function()
		local tree = readFile("TreeData/1_4/tree_2.json")
		assert.is_not_nil(tree, "must read TreeData/1_4/tree_2.json")
		assert.is_truthy(tree:find('"gs15de%-8"', 1, false))
		assert.is_truthy(tree:find("Flaming Sword", 1, true))
		assert.is_truthy(tree:find(" Fire Conversion", 1, true),
			"the ' Fire Conversion' stat string the rewrite keys on must still be present")
		assert.is_truthy(tree:find("base physical damage is converted to fire", 1, true),
			"the convert-to-fire description that justifies the rewrite must still be present")
	end)
end)
