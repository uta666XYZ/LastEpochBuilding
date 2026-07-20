-- @leb-regression-guard:aerial-prowess-per-stack
-- Falconer "Aerial Prowess" per-stack MORE damage for Aerial Assault. The
-- "Aerial Prowess" node (aa989-19, Aerial Assault tree) grants "+2% Damage Per
-- stack" (notScalingStats) backed by "12 Max Aerial Prowess stacks", but the
-- bare stat string carries NEITHER fact:
--   * the per-stack semantics live in the node ("Per stack" = per Aerial Prowess
--     stack); the bare "Per stack" phrasing is shared by ~18 unrelated stacking
--     stats, so a generic tag would collide.
--   * the MORE is consumed by, and scoped to, Aerial Assault (the owning skill) --
--     unlike Berserk's player-global buff, so the DEFAULT tree-node SkillId tag is
--     exactly right and the node must NOT be lifted to global scope.
-- Game source (TreeData/1_4/tree_4.json aa989-19 "Aerial Prowess", maxPoints 3):
--   stats           ["12 Max Aerial Prowess stacks"]
--   notScalingStats ["6 Health Gain per stack", "+2% Damage Per stack"]
--   description "...When you next use Aerial Assault, it consumes all stacks to
--   restore health per stack and deal more damage (multiplicative with other
--   modifiers) per stack."
-- Datamine proof (datamining):
--   GetMoreDamageFromAerialProwess (datamined offset) returns
--   stackCount(field 0x138) x perStackFloat(0x15c = 2%), capped at
--   maxStacks(0x150 = 12) and consumed on the next cast (0x138 set to 0).
--   (A separate per-stack MORE buff applied to the Falcon minion at cast,
--   AerialAssaultMutator ~L1684-1702, is OUT OF SCOPE here -- documented follow-up.)
--
-- The fix mirrors throne-of-ambition-stacks / berserk-stack-melee-damage /
-- germination-per-companion-scaling:
--   * Data/Global.lua LE_TREE_NODE_STAT_REWRITE["aa989-19"] appends
--     "per stack of Aerial Prowess" to the Damage line ($-anchored, value-tolerant).
--   * ModParser modTagList "per stack of aerial prowess" ->
--     Multiplier:AerialProwessStacks (limit 12 = the node's max stacks).
--   * aa989-19 is deliberately NOT in LE_TREE_NODE_GLOBAL_SCOPE, so the default
--     owning-skill SkillId tag (Aerial Assault) scopes the MORE to that skill.
--   * ConfigOptions "# of Aerial Prowess Stacks" (ifMult AerialProwessStacks,
--     default 0 -> strict no-op, zero corpus impact until the user sets it).
--   * Data/ModCache.lua: the stale FLAT-baked "+2% Damage Per stack" row was
--     REMOVED so the live parser regenerates it WITH the multiplier (the
--     Ambition/Germination REMOVE-not-patch precedent).
-- Per-stack stacking is ADDITIVE within the mod (one MORE of value x stacks).
-- See REGRESSION_GUARDS.md "aerial-prowess-per-stack".

describe("AerialProwessPerStack #skills", function()
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

	it("registry: rewrite appends 'per stack of Aerial Prowess' to the Damage stat only", function()
		assert.are.equal("+2% Damage per stack of Aerial Prowess",
			applyRewrites("aa989-19", "+2% Damage Per stack"))
		-- value-tolerant (a re-tuned per-stack value still rewrites)
		assert.are.equal("+3% Damage per stack of Aerial Prowess",
			applyRewrites("aa989-19", "+3% Damage Per stack"))
		-- the node's OTHER stats must NOT be touched (no "Damage" before "per stack",
		-- or trailing "stacks" not "stack")
		assert.are.equal("6 Health Gain per stack", applyRewrites("aa989-19", "6 Health Gain per stack"))
		assert.are.equal("12 Max Aerial Prowess stacks", applyRewrites("aa989-19", "12 Max Aerial Prowess stacks"))
	end)

	it("registry: aa989-19 is scoped to its own skill (NOT lifted to global scope)", function()
		assert.is_table(LE_TREE_NODE_GLOBAL_SCOPE, "LE_TREE_NODE_GLOBAL_SCOPE must be defined")
		assert.is_nil(LE_TREE_NODE_GLOBAL_SCOPE["aa989-19"],
			"Aerial Prowess MORE is consumed by Aerial Assault, so the default SkillId scope must stay -- do NOT global-lift")
		-- sibling Aerial Prowess nodes are not swept into the rewrite registry
		assert.is_nil(LE_TREE_NODE_STAT_REWRITE["aa989-20"])
		assert.is_nil(LE_TREE_NODE_STAT_REWRITE["aa989-23"])
	end)

	it("parse contract: rewritten line -> MORE Damage 2% x Multiplier:AerialProwessStacks (limit 12), no residue, no SkillId", function()
		local list, extra = modLib.parseMod("+2% Damage per stack of Aerial Prowess")
		assert.is_not_nil(list, "must parse")
		assert.is_true(not extra or extra == "", "must leave no residue, got: " .. tostring(extra))
		assert.are.equal(1, #list)
		local mod = list[1]
		assert.are.equal("Damage", mod.name)
		assert.are.equal("MORE", mod.type)
		assert.are.equal(2, mod.value)
		local mult = findTag(mod, "Multiplier", "AerialProwessStacks")
		assert.is_not_nil(mult, "must carry Multiplier:AerialProwessStacks")
		assert.are.equal(12, mult.limit, "limit must cap at 12 (the node's '12 Max Aerial Prowess stacks')")
		assert.is_nil(findTag(mod, "SkillId"), "parse must not produce a SkillId tag (scope comes from the tree node)")
	end)

	it("tree node end-to-end: aa989-19 emits a MORE Damage mod scoped to Aerial Assault (SkillId kept)", function()
		newBuild()
		local node = build.spec.nodes["aa989-19"]
		assert.is_not_nil(node, "aa989-19 must exist in the loaded 1.4 tree")
		assert.is_not_nil(node.skillId, "aa989-19 must be a skill-subtree node (skillId set)")
		node.alloc = 1
		build.spec.tree:ProcessStats(node)
		local found
		for _, mod in ipairs(node.modList) do
			if mod.name == "Damage" and mod.type == "MORE" then found = mod end
		end
		assert.is_not_nil(found, "Aerial Prowess must emit a MORE Damage mod")
		assert.are.equal(2, found.value)
		assert.is_not_nil(findTag(found, "Multiplier", "AerialProwessStacks"),
			"the node mod must be per-Aerial-Prowess-stack")
		assert.is_not_nil(findTag(found, "SkillId"),
			"the SkillId scoping must be KEPT -- Aerial Prowess MORE only buffs Aerial Assault")
	end)

	it("behaviour: scoped MORE = 2% x stacks (cap 12); 0 = no-op; other skills unaffected", function()
		newBuild()
		local node = build.spec.nodes["aa989-19"]
		node.alloc = 1
		build.spec.tree:ProcessStats(node)
		local perStackMod
		for _, mod in ipairs(node.modList) do
			if mod.name == "Damage" and mod.type == "MORE" then perStackMod = mod end
		end
		assert.is_not_nil(perStackMod, "must have the per-stack MORE Damage mod")

		local aaCfg = { skillGrantedEffect = { id = node.skillId } }
		local otherCfg = { skillGrantedEffect = { id = "Some Other Skill" } }
		local function moreAt(stacks, cfg)
			local modDB = new("ModDB")
			modDB:AddMod(perStackMod)
			modDB.multipliers.AerialProwessStacks = stacks
			return modDB:More(cfg, "Damage")
		end

		-- 0 stacks (default) -> strict no-op
		assert.are.equal(1, moreAt(0, aaCfg))
		-- 12 stacks -> +2% x 12 = +24% MORE (1.24)
		assert.is_true(math.abs(moreAt(12, aaCfg) - 1.24) < 1e-9,
			"12 stacks must give 1.24 MORE, got " .. tostring(moreAt(12, aaCfg)))
		-- cap: 20 stacks must still be +24% (parser limit 12)
		assert.is_true(math.abs(moreAt(20, aaCfg) - 1.24) < 1e-9,
			"20 stacks must cap at 1.24 MORE, got " .. tostring(moreAt(20, aaCfg)))
		-- scope: a non-Aerial-Assault skill gets nothing even at 12 stacks
		assert.are.equal(1, moreAt(12, otherCfg))
	end)

	it("config: '# of Aerial Prowess Stacks' is ifMult-gated with the cap hint", function()
		local src = readFile("Modules/ConfigOptions.lua")
		assert.is_not_nil(src, "must read Modules/ConfigOptions.lua")
		local entry = src:match('{ var = "multiplierAerialProwessStacks".-end },')
		assert.is_not_nil(entry, "multiplierAerialProwessStacks config entry must exist")
		assert.is_truthy(entry:find('type = "count"', 1, true))
		assert.is_truthy(entry:find('ifMult = "AerialProwessStacks"', 1, true),
			"must be visibility-gated on the AerialProwessStacks multiplier being referenced (Throne pattern)")
		assert.is_truthy(entry:find("max 12", 1, true),
			"label must carry the cap hint '(max 12)'")
		assert.is_truthy(entry:find('NewMod("Multiplier:AerialProwessStacks", "BASE", val, "Config"', 1, true),
			"apply must set Multiplier:AerialProwessStacks")
	end)

	it("ModCache: the stale FLAT '+2% Damage Per stack' row was removed (re-parses live with the multiplier)", function()
		local src = readFile("Data/ModCache.lua")
		assert.is_not_nil(src, "must read Data/ModCache.lua")
		assert.is_nil(src:find('c["+2% Damage Per stack"]', 1, true),
			"the stale inert/residue row must be removed so the live parser regenerates it with Multiplier:AerialProwessStacks")
	end)

	it("game-file: aa989-19 still carries the stat strings and the per-stack/consume description", function()
		local tree = readFile("TreeData/1_4/tree_4.json")
		assert.is_not_nil(tree, "must read TreeData/1_4/tree_4.json")
		assert.is_truthy(tree:find('"aa989%-19"', 1, false))
		assert.is_truthy(tree:find("Aerial Prowess", 1, true))
		assert.is_truthy(tree:find("+2% Damage Per stack", 1, true),
			"the Aerial Prowess stat string the rewrite keys on must still be present")
		assert.is_truthy(tree:find("12 Max Aerial Prowess stacks", 1, true),
			"the max-stacks stat backing the cap must still be present")
		assert.is_truthy(tree:find("consumes all stacks", 1, true),
			"the consume-on-cast / per-stack more-damage description that justifies the rewrite must still be present")
	end)
end)
