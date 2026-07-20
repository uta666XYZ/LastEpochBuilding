-- @leb-regression-guard:htsk5-13-fire-conversion
-- See REGRESSION_GUARDS.md "htsk5-13-fire-conversion".
-- Validation provenance is retained in maintainer notes.

describe("FireConversion #skills", function()
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

	it("registry: rewrite turns ' Fire Conversion' into the 'Physical -> Fire' arrow ONLY", function()
		assert.are.equal("Physical -> Fire", applyRewrites("htsk5-13", " Fire Conversion"))
		-- leading-space-tolerant (the live tree string carries a leading space)
		assert.are.equal("Physical -> Fire", applyRewrites("htsk5-13", "Fire Conversion"))
		-- the node's OTHER stat must NOT be touched
		assert.are.equal(" Bleed -> Ignite Chance", applyRewrites("htsk5-13", " Bleed -> Ignite Chance"))
	end)

	it("registry: htsk5-13 is scoped to its own skill (NOT lifted to global scope)", function()
		assert.is_table(LE_TREE_NODE_GLOBAL_SCOPE, "LE_TREE_NODE_GLOBAL_SCOPE must be defined")
		assert.is_nil(LE_TREE_NODE_GLOBAL_SCOPE["htsk5-13"],
			"Molten Arrowstorm converts only Heartseeker's base damage, so the default SkillId scope must stay -- do NOT global-lift")
		-- the Void-sourced sharer must NEVER be swept into a Physical rewrite:
		--   vr53sl-18 (Volatile Reversal) is VOID->fire (different source type) -> stays inert.
		-- gs15de-8 (Vengeance) is Physical->fire of a DIFFERENT skill: it now carries its
		-- OWN node-keyed entry (correct, same source type), scoped to Vengeance via its own
		-- treeId -- NOT swept into htsk5-13's Heartseeker scope, and NOT global-lifted.
		assert.is_nil(LE_TREE_NODE_STAT_REWRITE["vr53sl-18"], "vr53sl-18 (Volatile Reversal, Void->Fire) must NOT be rewritten as Physical")
		assert.is_nil(LE_TREE_NODE_GLOBAL_SCOPE["gs15de-8"], "gs15de-8 (Vengeance) must stay skill-scoped (Vengeance), NOT global-lifted")
		assert.is_not_nil(LE_TREE_NODE_STAT_REWRITE["gs15de-8"], "gs15de-8 now has its own Vengeance-scoped Physical->Fire rewrite (no longer deferred)")
	end)

	it("parse contract: 'Physical -> Fire' -> a SINGLE PhysicalDamageConvertToFire BASE 100, no tag", function()
		local list, extra = modLib.parseMod("Physical -> Fire")
		assert.is_not_nil(list, "must parse")
		assert.is_true(not extra or extra == "", "must leave no residue, got: " .. tostring(extra))
		-- single source type (Physical only) -- this is the faithfulness check vs the
		-- all-types-convert skillBaseDamageConversionHandler form
		assert.are.equal(1, #list)
		local mod = list[1]
		assert.are.equal("PhysicalDamageConvertToFire", mod.name)
		assert.are.equal("BASE", mod.type)
		assert.are.equal(100, mod.value)
		-- the plain type arrow carries NO parser tag: scoping comes from the tree node
		assert.is_nil(mod[1], "global type arrow must NOT carry a SkillName/SkillId tag")
	end)

	it("tree node end-to-end: htsk5-13 emits PhysicalDamageConvertToFire BASE 100 scoped to Heartseeker (SkillId kept)", function()
		newBuild()
		local node = build.spec.nodes["htsk5-13"]
		assert.is_not_nil(node, "htsk5-13 must exist in the loaded 1.4 tree")
		assert.are.equal("Heartseeker", node.skillId,
			"htsk5-13 must scope to the Heartseeker skill (treeId htsk5 -> skill 'Heartseeker')")
		node.alloc = 1
		build.spec.tree:ProcessStats(node)
		local found
		for _, mod in ipairs(node.modList) do
			if mod.name == "PhysicalDamageConvertToFire" and mod.type == "BASE" then found = mod end
		end
		assert.is_not_nil(found, "Molten Arrowstorm must emit a PhysicalDamageConvertToFire BASE mod")
		assert.are.equal(100, found.value)
		local skillIdTag = findTag(found, "SkillId")
		assert.is_not_nil(skillIdTag, "the SkillId scoping must be KEPT -- the conversion only applies to Heartseeker")
		assert.are.equal("Heartseeker", skillIdTag.skillId)
	end)

	it("behaviour: conversionTable[Physical][Fire] == 1.0 (mult 0), Physical-only, scoped to Heartseeker", function()
		newBuild()
		local node = build.spec.nodes["htsk5-13"]
		node.alloc = 1
		build.spec.tree:ProcessStats(node)

		local hsCfg = { skillGrantedEffect = { id = node.skillId } }
		local otherCfg = { skillGrantedEffect = { id = "Some Other Skill" } }

		-- replicate CalcOffence's conversionTable build (CalcOffence.lua ~1704/1731):
		--   globalConv[Fire] = skillModList:Sum("BASE", skillCfg, "PhysicalDamageConvertToFire")
		--   conversionTable[Physical][Fire] = globalConv[Fire] / 100
		--   conversionTable[Physical].mult   = 1 - min(globalTotal/100, 1)
		local phys2fire = node.modList:Sum("BASE", hsCfg, "PhysicalDamageConvertToFire")
		assert.are.equal(100, phys2fire, "Physical->Fire must sum to 100 under the Heartseeker cfg")
		assert.are.equal(1.0, phys2fire / 100, "conversionTable[Physical][Fire] must be 1.0 (100%)")
		assert.are.equal(0, 1 - math.min(phys2fire / 100, 1),
			"the Physical share retained after conversion (mult) must be 0 -- all Physical becomes Fire")

		-- FAITHFULNESS: only Physical converts (the datamining converts type 0 ONLY).
		-- A different (all-types) handler would also recolour any non-physical added
		-- base on Heartseeker to Fire -- which the game does NOT do.
		assert.are.equal(0, node.modList:Sum("BASE", hsCfg, "ColdDamageConvertToFire"),
			"Cold base must NOT convert (Molten Arrowstorm is Physical-only)")
		assert.are.equal(0, node.modList:Sum("BASE", hsCfg, "VoidDamageConvertToFire"),
			"Void base must NOT convert (Molten Arrowstorm is Physical-only -- Void->Fire is the vr53sl-18 source type, not htsk5-13)")

		-- SCOPE: a non-Heartseeker skill (and the global nil cfg) must see nothing.
		assert.are.equal(0, node.modList:Sum("BASE", otherCfg, "PhysicalDamageConvertToFire"),
			"conversion must NOT leak to another skill")
		assert.are.equal(0, node.modList:Sum("BASE", nil, "PhysicalDamageConvertToFire"),
			"conversion must NOT apply globally (nil cfg)")
	end)

	it("node-keyed: the Void-source sharer (vr53sl-18) is NOT rewritten; the Physical-source sharer (gs15de-8) has its OWN entry", function()
		-- vr53sl-18 (Volatile Reversal, Void->fire) shares the bare display string but
		-- has NO rewrite entry, so its " Fire Conversion" stays the inert ModCache row --
		-- a global ModCache rewrite would mis-source the Void node as Physical.
		assert.is_nil(LE_TREE_NODE_STAT_REWRITE["vr53sl-18"])
		-- gs15de-8 (Vengeance) is the SAME source type as htsk5-13 (Physical), so it gets
		-- its OWN node-keyed entry rewriting to the SAME arrow form -- node-keyed isolation
		-- means each scopes to its own treeId's owning skill (htsk5->Heartseeker,
		-- gs15de->Vengeance), never cross-contaminating.
		local hs = LE_TREE_NODE_STAT_REWRITE["htsk5-13"]
		local fs = LE_TREE_NODE_STAT_REWRITE["gs15de-8"]
		assert.is_not_nil(hs)
		assert.is_not_nil(fs)
		assert.are.equal("Physical -> Fire", (" Fire Conversion"):gsub(fs[1].pat, fs[1].repl))
	end)

	it("ModCache: the shared ' Fire Conversion' inert row is deliberately KEPT (the sharers need it)", function()
		local src = readFile("Data/ModCache.lua")
		assert.is_not_nil(src, "must read Data/ModCache.lua")
		assert.is_truthy(src:find('c[" Fire Conversion"]', 1, true),
			"the inert ' Fire Conversion' row must REMAIN (gs15de-8 / vr53sl-18 still emit it and must stay inert; the rewrite intercepts htsk5-13 before parseMod)")
	end)

	it("game-file: htsk5-13 still carries the ' Fire Conversion' stat and the convert-to-fire description", function()
		local tree = readFile("TreeData/1_4/tree_4.json")
		assert.is_not_nil(tree, "must read TreeData/1_4/tree_4.json")
		assert.is_truthy(tree:find('"htsk5%-13"', 1, false))
		assert.is_truthy(tree:find("Molten Arrowstorm", 1, true))
		assert.is_truthy(tree:find(" Fire Conversion", 1, true),
			"the ' Fire Conversion' stat string the rewrite keys on must still be present")
		assert.is_truthy(tree:find("base physical damage is converted to fire", 1, true),
			"the convert-to-fire description that justifies the rewrite must still be present")
	end)
end)
