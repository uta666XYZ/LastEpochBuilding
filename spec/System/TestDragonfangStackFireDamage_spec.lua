-- @leb-regression-guard:dragonfang-stack-fire-damage
-- Marksman "Dragonfang" node (htsk5-15, Heartseeker tree). The node grants
-- "+1 Bow/Spell/Throwing Fire Damage Per Stack" (stats), with a Dragonfang stack
-- gained per consecutive Recurve (10s, max 20). The bare stat strings carry
-- NEITHER fact needed to model them:
--   * the per-stack semantics live in the node ("Per Stack" = per Dragonfang
--     stack, capped at 20 by the description); the bare "Per Stack" phrasing is
--     shared by ~18 unrelated stacking stats (e.g. the unrelated "+5% Fire Damage
--     Per Stack" MORE on a different tree_4.json node, L6862), so a generic tag
--     would collide -- the rewrite is node-keyed to htsk5-15.
--   * the flat Fire is granted to and consumed by Heartseeker (the owning skill),
--     so the DEFAULT tree-node SkillId tag is exactly right and the node must NOT
--     be lifted to global scope (unlike Berserk's player-global buff).
-- Game source (TreeData/1_4/tree_4.json htsk5-15 "Dragonfang", maxPoints 4):
--   stats           ["+1 Bow Fire Damage Per Stack",
--                    "+1 Spell Fire Damage Per Stack",
--                    "+1 Throwing Fire Damage Per Stack"]
--   notScalingStats [" Dragonfang On Recurve"]
--   description "Consecutive Recurves each grant a stack of Dragonfang for 10
--   seconds. Higher stacks can only be achieved by a higher amount of consecutive
--   Recurves, up to a maximum of 20."
-- Datamine proof (datamining):
--   L580/585/591 Stats__AddedStat(0, <tag>, field+0x144) = +1 Fire per stack,
--   capped at 0x14 = 20 (L603/608).
--
-- The fix mirrors aerial-prowess-per-stack / berserk-stack-melee-damage /
-- throne-of-ambition-stacks / germination-per-companion-scaling:
--   * Data/Global.lua LE_TREE_NODE_STAT_REWRITE["htsk5-15"] rewrites only the
--     trailing "Per Stack" -> "per stack of Dragonfang" ($-anchored,
--     value-tolerant; the leading Bow/Spell/Throwing keyword and "Fire Damage"
--     survive, so the keywordFlags parse -> FireDamage BASE 1 is preserved).
--   * ModParser modTagList "per stack of dragonfang" ->
--     Multiplier:DragonfangStacks (limit 20 = the node's "up to a maximum of 20").
--   * htsk5-15 is deliberately NOT in LE_TREE_NODE_GLOBAL_SCOPE, so the default
--     owning-skill SkillId tag (Heartseeker) scopes the flat Fire to that skill.
--   * ConfigOptions "# of Dragonfang Stacks" (ifMult DragonfangStacks, default
--     0 -> strict no-op, zero corpus impact until the user sets it).
--   * Data/ModCache.lua: the stale FLAT-baked "+1 <kw> Fire Damage Per Stack"
--     rows (Bow/Spell/Throwing, with "   Per Stack " residue) were REMOVED so the
--     live parser regenerates them WITH the multiplier (the Ambition/Germination/
--     Aerial-Prowess REMOVE-not-patch precedent).
-- Per-stack stacking is ADDITIVE within the mod (one BASE mod of value x stacks).
-- See REGRESSION_GUARDS.md "dragonfang-stack-fire-damage".

describe("DragonfangStackFireDamage #skills", function()
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

	it("registry: rewrite appends 'per stack of Dragonfang' to each Fire Damage stat only", function()
		assert.are.equal("+1 Bow Fire Damage per stack of Dragonfang",
			applyRewrites("htsk5-15", "+1 Bow Fire Damage Per Stack"))
		assert.are.equal("+1 Spell Fire Damage per stack of Dragonfang",
			applyRewrites("htsk5-15", "+1 Spell Fire Damage Per Stack"))
		assert.are.equal("+1 Throwing Fire Damage per stack of Dragonfang",
			applyRewrites("htsk5-15", "+1 Throwing Fire Damage Per Stack"))
		-- value-tolerant (a re-tuned per-stack value still rewrites)
		assert.are.equal("+2 Bow Fire Damage per stack of Dragonfang",
			applyRewrites("htsk5-15", "+2 Bow Fire Damage Per Stack"))
		-- the node's OTHER stats must NOT be touched (no "Fire Damage" before
		-- "Per Stack")
		assert.are.equal(" Dragonfang On Recurve", applyRewrites("htsk5-15", " Dragonfang On Recurve"))
	end)

	it("registry: htsk5-15 is scoped to its own skill (NOT lifted to global scope)", function()
		assert.is_table(LE_TREE_NODE_GLOBAL_SCOPE, "LE_TREE_NODE_GLOBAL_SCOPE must be defined")
		assert.is_nil(LE_TREE_NODE_GLOBAL_SCOPE["htsk5-15"],
			"Dragonfang flat Fire is granted to/consumed by Heartseeker, so the default SkillId scope must stay -- do NOT global-lift")
		-- sibling Heartseeker nodes are not swept into the rewrite registry
		assert.is_nil(LE_TREE_NODE_STAT_REWRITE["htsk5-14"])
		assert.is_nil(LE_TREE_NODE_STAT_REWRITE["htsk5-16"])
	end)

	it("parse contract: rewritten line -> FireDamage BASE 1 x Multiplier:DragonfangStacks (limit 20), keyword kept, no residue, no SkillId", function()
		local cases = {
			{ str = "+1 Bow Fire Damage per stack of Dragonfang", kw = KeywordFlag.Bow },
			{ str = "+1 Spell Fire Damage per stack of Dragonfang", kw = KeywordFlag.Spell },
			{ str = "+1 Throwing Fire Damage per stack of Dragonfang", kw = KeywordFlag.Throwing },
		}
		for _, case in ipairs(cases) do
			local list, extra = modLib.parseMod(case.str)
			assert.is_not_nil(list, "must parse: " .. case.str)
			assert.is_true(not extra or extra == "", "must leave no residue, got: " .. tostring(extra))
			assert.are.equal(1, #list)
			local mod = list[1]
			assert.are.equal("FireDamage", mod.name)
			assert.are.equal("BASE", mod.type)
			assert.are.equal(1, mod.value)
			assert.are.equal(case.kw, mod.keywordFlags, "must keep the Bow/Spell/Throwing keyword: " .. case.str)
			local mult = findTag(mod, "Multiplier", "DragonfangStacks")
			assert.is_not_nil(mult, "must carry Multiplier:DragonfangStacks")
			assert.are.equal(20, mult.limit, "limit must cap at 20 (the node's 'up to a maximum of 20')")
			assert.is_nil(findTag(mod, "SkillId"), "parse must not produce a SkillId tag (scope comes from the tree node)")
		end
	end)

	it("tree node end-to-end: htsk5-15 emits FireDamage BASE mods scoped to Heartseeker (SkillId kept)", function()
		newBuild()
		local node = build.spec.nodes["htsk5-15"]
		assert.is_not_nil(node, "htsk5-15 must exist in the loaded 1.4 tree")
		assert.is_not_nil(node.skillId, "htsk5-15 must be a skill-subtree node (skillId set)")
		node.alloc = 1
		build.spec.tree:ProcessStats(node)
		local found = {}
		for _, mod in ipairs(node.modList) do
			if mod.name == "FireDamage" and mod.type == "BASE" then
				found[mod.keywordFlags] = mod
			end
		end
		for _, kw in ipairs({ KeywordFlag.Bow, KeywordFlag.Spell, KeywordFlag.Throwing }) do
			local mod = found[kw]
			assert.is_not_nil(mod, "Dragonfang must emit a FireDamage BASE mod for keyword " .. tostring(kw))
			assert.are.equal(1, mod.value)
			assert.is_not_nil(findTag(mod, "Multiplier", "DragonfangStacks"),
				"the node mod must be per-Dragonfang-stack")
			assert.is_not_nil(findTag(mod, "SkillId"),
				"the SkillId scoping must be KEPT -- Dragonfang flat Fire only buffs Heartseeker")
		end
	end)

	it("behaviour: config 0 (default) is a strict no-op; 10 stacks add +10 Fire BASE per keyword; capped at 20", function()
		newBuild()
		build.itemsTab:CreateDisplayItemFromRaw([[Rarity: RARE
		Brass Sceptre
		Brass Sceptre
		+1 Bow Fire Damage per stack of Dragonfang
		+1 Spell Fire Damage per stack of Dragonfang
		+1 Throwing Fire Damage per stack of Dragonfang]])
		build.itemsTab:AddDisplayItem()
		local function fireBase(kw)
			return build.calcsTab.mainEnv.player.modDB:Sum("BASE", { keywordFlags = kw }, "FireDamage")
		end

		-- 0 stacks (default) -> no Dragonfang contribution
		build.configTab.input["multiplierDragonfangStacks"] = 0
		build.configTab:BuildModList()
		runCallback("OnFrame")
		local base0 = {
			[KeywordFlag.Bow] = fireBase(KeywordFlag.Bow),
			[KeywordFlag.Spell] = fireBase(KeywordFlag.Spell),
			[KeywordFlag.Throwing] = fireBase(KeywordFlag.Throwing),
		}

		-- 10 stacks -> +1 x 10 = +10 flat Fire on each keyword
		build.configTab.input["multiplierDragonfangStacks"] = 10
		build.configTab:BuildModList()
		runCallback("OnFrame")
		assert.are.equal(base0[KeywordFlag.Bow] + 10, fireBase(KeywordFlag.Bow))
		assert.are.equal(base0[KeywordFlag.Spell] + 10, fireBase(KeywordFlag.Spell))
		assert.are.equal(base0[KeywordFlag.Throwing] + 10, fireBase(KeywordFlag.Throwing))

		-- cap: 25 stacks must still be +20 (the parser limit 20)
		build.configTab.input["multiplierDragonfangStacks"] = 25
		build.configTab:BuildModList()
		runCallback("OnFrame")
		assert.are.equal(base0[KeywordFlag.Bow] + 20, fireBase(KeywordFlag.Bow))
		assert.are.equal(base0[KeywordFlag.Spell] + 20, fireBase(KeywordFlag.Spell))
		assert.are.equal(base0[KeywordFlag.Throwing] + 20, fireBase(KeywordFlag.Throwing))
	end)

	it("behaviour: a build WITHOUT any Dragonfang mod ignores the config entirely", function()
		newBuild()
		local function fireBase()
			return build.calcsTab.mainEnv.player.modDB:Sum("BASE", { keywordFlags = KeywordFlag.Bow }, "FireDamage")
		end

		build.configTab.input["multiplierDragonfangStacks"] = 0
		build.configTab:BuildModList()
		runCallback("OnFrame")
		local base0 = fireBase()

		build.configTab.input["multiplierDragonfangStacks"] = 20
		build.configTab:BuildModList()
		runCallback("OnFrame")
		assert.are.equal(base0, fireBase())
	end)

	it("config: '# of Dragonfang Stacks' is ifMult-gated with the cap hint", function()
		local src = readFile("Modules/ConfigOptions.lua")
		assert.is_not_nil(src, "must read Modules/ConfigOptions.lua")
		local entry = src:match('{ var = "multiplierDragonfangStacks".-end },')
		assert.is_not_nil(entry, "multiplierDragonfangStacks config entry must exist")
		assert.is_truthy(entry:find('type = "count"', 1, true))
		assert.is_truthy(entry:find('ifMult = "DragonfangStacks"', 1, true),
			"must be visibility-gated on the DragonfangStacks multiplier being referenced (Throne pattern)")
		assert.is_truthy(entry:find("max 20", 1, true),
			"label must carry the cap hint '(max 20)'")
		assert.is_truthy(entry:find('NewMod("Multiplier:DragonfangStacks", "BASE", val, "Config"', 1, true),
			"apply must set Multiplier:DragonfangStacks")
	end)

	it("ModCache: the stale FLAT '+1 <kw> Fire Damage Per Stack' rows were removed (re-parse live with the multiplier)", function()
		local src = readFile("Data/ModCache.lua")
		assert.is_not_nil(src, "must read Data/ModCache.lua")
		assert.is_nil(src:find('c["+1 Bow Fire Damage Per Stack"]', 1, true),
			"the stale Bow residue row must be removed so the live parser regenerates it with Multiplier:DragonfangStacks")
		assert.is_nil(src:find('c["+1 Spell Fire Damage Per Stack"]', 1, true),
			"the stale Spell residue row must be removed")
		assert.is_nil(src:find('c["+1 Throwing Fire Damage Per Stack"]', 1, true),
			"the stale Throwing residue row must be removed")
	end)

	it("game-file: htsk5-15 still carries the stat strings and the per-stack/max-20 description", function()
		local tree = readFile("TreeData/1_4/tree_4.json")
		assert.is_not_nil(tree, "must read TreeData/1_4/tree_4.json")
		assert.is_truthy(tree:find('"htsk5%-15"', 1, false))
		assert.is_truthy(tree:find("Dragonfang", 1, true))
		assert.is_truthy(tree:find("+1 Bow Fire Damage Per Stack", 1, true),
			"the Dragonfang stat string the rewrite keys on must still be present")
		assert.is_truthy(tree:find("+1 Spell Fire Damage Per Stack", 1, true))
		assert.is_truthy(tree:find("+1 Throwing Fire Damage Per Stack", 1, true))
		assert.is_truthy(tree:find("up to a maximum of 20", 1, true),
			"the max-20 description backing the cap must still be present")
	end)
end)
