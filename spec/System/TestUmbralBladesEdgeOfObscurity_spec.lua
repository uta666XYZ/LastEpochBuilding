-- @leb-regression-guard:umbral-blades-edge-of-obscurity-per-shroud
-- Rogue "Edge of Obscurity" per-Dusk-Shroud MORE damage for Umbral Blades. The
-- "Edge of Obscurity" node (ub5d9-7, Umbral Blades tree) grants "+2% Damage per
-- Dusk Shroud, up to 20", but the bare stat string cannot be tagged generically:
--   * the "per Dusk Shroud" phrasing collides with unrelated Dusk-Shroud stats
--     (a sibling Shadow node sh4re-8 carries "+1% Damage per Dusk Shroud" with NO
--     "up to 20"); the raw line misparsed via ModCache to a SkillName="Dusk
--     Shroud" MORE with residue " per , up to 20 " (Data/ModCache.lua row 4465)
--     -- residue => dropped => the node contributed NOTHING.
--   * the MORE is scoped to Umbral Blades (the owning skill), so the DEFAULT
--     tree-node SkillId tag is exactly right and the node must NOT be lifted to
--     global scope (unlike Berserk's player-global buff).
-- Game source (TreeData/1_4/tree_4.json ub5d9-7 "Edge of Obscurity", maxPoints 3):
--   stats           ["+2% Damage per Dusk Shroud, up to 20"]
--   notScalingStats [" Doubled Inside Smoke Bomb"]
-- Datamine proof (datamined game source): MoreStat =
--   (InsideSmokeBomb?2:1) x nodeFloat(0x108 = 2%) x getStacks(0x52), capped at
--   DAT_183d71c44 = 20. (The Smoke-Bomb x2 doubling -- notScalingStats
--   " Doubled Inside Smoke Bomb" -- is OUT OF SCOPE here, a documented follow-up.)
--
-- The fix mirrors aerial-prowess-per-stack / berserk-stack-melee-damage /
-- germination-per-companion-scaling:
--   * Data/Global.lua LE_TREE_NODE_STAT_REWRITE["ub5d9-7"] rewrites the Damage
--     line to end in "per stack of dusk shroud" ($-anchored, value-tolerant) and
--     DROPS the literal "20" (folded into the modTagList key as limit). It runs
--     BEFORE PassiveTree rank-scaling, so "+2%" scales to "+6%" at 3/3.
--   * ModParser modTagList "per stack of dusk shroud" ->
--     Multiplier:DuskShroudStacks (limit 20 = the node's "up to 20").
--   * ub5d9-7 is deliberately NOT in LE_TREE_NODE_GLOBAL_SCOPE, so the default
--     owning-skill SkillId tag (Umbral Blades) scopes the MORE to that skill.
--   * ConfigOptions: the EXISTING "Dusk Shroud Stacks" config
--     (multiplierDuskShroudStacks, default 0 -> strict no-op) now ALSO emits
--     Multiplier:DuskShroudStacks off the same stack count, so one count gates
--     both the defensive Glancing Blow/Evasion and this offensive MORE.
--   * Data/ModCache.lua: the stale row 4465 is LEFT IN PLACE (the rewrite changes
--     the node string before lookup, so the row goes dead -- the Berserk
--     leave-it precedent; confirmed here by the end-to-end test producing the
--     multiplier mod, NOT the dead row's SkillName="Dusk Shroud" misparse).
-- Per-stack stacking is ADDITIVE within the mod (one MORE of value x stacks).
-- See REGRESSION_GUARDS.md "umbral-blades-edge-of-obscurity-per-shroud".

describe("UmbralBladesEdgeOfObscurity #skills", function()
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

	it("registry: rewrite drops the literal 20 and appends 'per stack of dusk shroud' to the Damage stat", function()
		assert.are.equal("+2% Damage per stack of dusk shroud",
			applyRewrites("ub5d9-7", "+2% Damage per Dusk Shroud, up to 20"))
		-- value-tolerant (a re-tuned per-stack value still rewrites)
		assert.are.equal("+3% Damage per stack of dusk shroud",
			applyRewrites("ub5d9-7", "+3% Damage per Dusk Shroud, up to 20"))
		-- the sibling Shadow node string ("+1% Damage per Dusk Shroud" WITHOUT
		-- "up to 20") must NOT match this $-anchored pattern (and is node-keyed
		-- to ub5d9-7 anyway), nor must the "Ward Gain per Dusk Shroud" line.
		assert.are.equal("+1% Damage per Dusk Shroud", applyRewrites("ub5d9-7", "+1% Damage per Dusk Shroud"))
		assert.are.equal("+2 Ward Gain per Dusk Shroud", applyRewrites("ub5d9-7", "+2 Ward Gain per Dusk Shroud"))
	end)

	it("registry: ub5d9-7 is scoped to its own skill (NOT lifted to global scope)", function()
		assert.is_table(LE_TREE_NODE_GLOBAL_SCOPE, "LE_TREE_NODE_GLOBAL_SCOPE must be defined")
		assert.is_nil(LE_TREE_NODE_GLOBAL_SCOPE["ub5d9-7"],
			"Edge of Obscurity MORE is scoped to Umbral Blades, so the default SkillId scope must stay -- do NOT global-lift")
	end)

	it("parse contract: rewritten line -> MORE Damage 2% x Multiplier:DuskShroudStacks (limit 20), no residue, no SkillId/SkillName", function()
		local list, extra = modLib.parseMod("+2% Damage per stack of dusk shroud")
		assert.is_not_nil(list, "must parse")
		assert.is_true(not extra or extra == "", "must leave no residue, got: " .. tostring(extra))
		assert.are.equal(1, #list)
		local mod = list[1]
		assert.are.equal("Damage", mod.name)
		assert.are.equal("MORE", mod.type)
		assert.are.equal(2, mod.value)
		local mult = findTag(mod, "Multiplier", "DuskShroudStacks")
		assert.is_not_nil(mult, "must carry Multiplier:DuskShroudStacks")
		assert.are.equal(20, mult.limit, "limit must cap at 20 (the node's 'up to 20' / '20 Max Dusk Shrouds Considered')")
		assert.is_nil(findTag(mod, "SkillId"), "parse must not produce a SkillId tag (scope comes from the tree node)")
		-- the dead ModCache row 4465 misparsed to a SkillName="Dusk Shroud" tag; the
		-- live rewrite path must NOT reproduce that.
		assert.is_nil(findTag(mod, "SkillName"), "live parse must NOT carry the dead row's SkillName='Dusk Shroud' misparse")
	end)

	it("tree node end-to-end: ub5d9-7 at 3/3 rank-scales to +6% MORE Damage scoped to Umbral Blades (SkillId kept)", function()
		newBuild()
		local node = build.spec.nodes["ub5d9-7"]
		assert.is_not_nil(node, "ub5d9-7 must exist in the loaded 1.4 tree")
		assert.is_not_nil(node.skillId, "ub5d9-7 must be a skill-subtree node (skillId set)")
		node.alloc = 3
		build.spec.tree:ProcessStats(node)
		local found
		for _, mod in ipairs(node.modList) do
			if mod.name == "Damage" and mod.type == "MORE" then found = mod end
		end
		assert.is_not_nil(found, "Edge of Obscurity must emit a MORE Damage mod")
		assert.are.equal(6, found.value, "2% per point x 3 allocated points must rank-scale to +6%")
		assert.is_not_nil(findTag(found, "Multiplier", "DuskShroudStacks"),
			"the node mod must be per-Dusk-Shroud-stack")
		assert.is_nil(findTag(found, "SkillName"),
			"end-to-end must NOT carry the dead ModCache row's SkillName='Dusk Shroud' tag (the dead row is no longer consulted)")
		assert.is_not_nil(findTag(found, "SkillId"),
			"the SkillId scoping must be KEPT -- Edge of Obscurity MORE only buffs Umbral Blades")
	end)

	it("behaviour: scoped MORE = 6% x stacks (cap 20) at 3/3; 0 = no-op; other skills unaffected", function()
		newBuild()
		local node = build.spec.nodes["ub5d9-7"]
		node.alloc = 3
		build.spec.tree:ProcessStats(node)
		local perStackMod
		for _, mod in ipairs(node.modList) do
			if mod.name == "Damage" and mod.type == "MORE" then perStackMod = mod end
		end
		assert.is_not_nil(perStackMod, "must have the per-stack MORE Damage mod")

		local ubCfg = { skillGrantedEffect = { id = node.skillId } }
		local otherCfg = { skillGrantedEffect = { id = "Some Other Skill" } }
		local function moreAt(stacks, cfg)
			local modDB = new("ModDB")
			modDB:AddMod(perStackMod)
			modDB.multipliers.DuskShroudStacks = stacks
			return modDB:More(cfg, "Damage")
		end

		-- 0 stacks (default) -> strict no-op
		assert.are.equal(1, moreAt(0, ubCfg))
		-- 10 stacks -> +6% x 10 = +60% MORE (1.60) -- the spec target
		assert.is_true(math.abs(moreAt(10, ubCfg) - 1.60) < 1e-9,
			"10 stacks must give 1.60 MORE, got " .. tostring(moreAt(10, ubCfg)))
		-- exactly 20 stacks -> +6% x 20 = +120% MORE (2.20)
		assert.is_true(math.abs(moreAt(20, ubCfg) - 2.20) < 1e-9,
			"20 stacks must give 2.20 MORE, got " .. tostring(moreAt(20, ubCfg)))
		-- cap: 25 stacks must still be +120% (parser limit 20)
		assert.is_true(math.abs(moreAt(25, ubCfg) - 2.20) < 1e-9,
			"25 stacks must cap at 2.20 MORE, got " .. tostring(moreAt(25, ubCfg)))
		-- scope: a non-Umbral-Blades skill gets nothing even at 20 stacks
		assert.are.equal(1, moreAt(20, otherCfg))
	end)

	it("config: the existing 'Dusk Shroud Stacks' config now ALSO emits Multiplier:DuskShroudStacks (defensive emits preserved)", function()
		local src = readFile("Modules/ConfigOptions.lua")
		assert.is_not_nil(src, "must read Modules/ConfigOptions.lua")
		local entry = src:match('{ var = "multiplierDuskShroudStacks".-end },')
		assert.is_not_nil(entry, "multiplierDuskShroudStacks config entry must exist")
		assert.is_truthy(entry:find('type = "count"', 1, true))
		-- the existing defensive emits must be preserved
		assert.is_truthy(entry:find('NewMod("GlancingBlowChance", "BASE", val * 5', 1, true),
			"defensive Glancing Blow emit must be preserved")
		assert.is_truthy(entry:find('NewMod("Evasion", "BASE", val * 50', 1, true),
			"defensive Evasion emit must be preserved")
		-- the new offensive emit
		assert.is_truthy(entry:find('NewMod("Multiplier:DuskShroudStacks", "BASE", val, "Config"', 1, true),
			"apply must now set Multiplier:DuskShroudStacks off the same count (default 0 -> no-op)")
	end)

	it("ModCache: the stale row 4465 is left in place but is no longer consulted (rewrite changes the key before lookup)", function()
		-- Per the fix, the dead row is NOT hand-edited (Berserk leave-it precedent);
		-- it remains in the cache as documentation of the raw string, but the
		-- PassiveTree rewrite transforms ub5d9-7's string before any cache lookup,
		-- so the row is never hit (proven by the end-to-end test above producing
		-- the Multiplier mod, not this row's SkillName="Dusk Shroud" misparse).
		local src = readFile("Data/ModCache.lua")
		assert.is_not_nil(src, "must read Data/ModCache.lua")
		local row = src:match('c%["%+2%% Damage per Dusk Shroud, up to 20"%]=(.-)\n')
		assert.is_not_nil(row, "the raw row should still be present (we do NOT hand-edit it)")
		assert.is_truthy(row:find('skillName="Dusk Shroud"', 1, true),
			"the dead row is the SkillName-misparse one -- confirming it is the row the rewrite makes inert")
		assert.is_truthy(row:find('up to 20', 1, true),
			"the dead row carries the unparsed ' per , up to 20 ' residue that the rewrite eliminates")
	end)

	it("game-file: ub5d9-7 still carries the stat string, the Smoke Bomb line and the node name", function()
		local tree = readFile("TreeData/1_4/tree_4.json")
		assert.is_not_nil(tree, "must read TreeData/1_4/tree_4.json")
		assert.is_truthy(tree:find('"ub5d9%-7"', 1, false))
		assert.is_truthy(tree:find("Edge of Obscurity", 1, true),
			"the node name the fix documents must still be present")
		assert.is_truthy(tree:find("+2% Damage per Dusk Shroud, up to 20", 1, true),
			"the stat string the rewrite keys on must still be present (a rename should fail this loudly)")
		assert.is_truthy(tree:find("Doubled Inside Smoke Bomb", 1, true),
			"the Smoke-Bomb x2 notScalingStat (the deferred Mechanic 2) must still be present")
	end)
end)
