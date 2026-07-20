-- @leb-regression-guard:profane-orb-hex-flurry-per-negative-ailment-more
-- Multiplier:EnemyNegativeAilmentCount (actor=enemy). See REGRESSION_GUARDS.md.
-- Validation provenance is retained in maintainer notes.

local MODFLAG_HIT = 8388608 -- Global.lua ModFlag.Hit
local ORB_SKILL = "Warlock 05.2 Profane Orb"

describe("ProfaneOrbHexFlurry #skills", function()
	local function readFile(relPath)
		local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
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

	it("registry: rewrites the per-Curse damage line to per-negative-ailment, leaves the frequency line untouched", function()
		assert.are.equal("+15% Hit Damage per Negative Ailment on Enemy",
			applyRewrites("pr5fm-29", "+15% Profane Orb Damage per Curse"))
		-- value-tolerant (rank-scaled input keeps its leading value)
		assert.are.equal("+60% Hit Damage per Negative Ailment on Enemy",
			applyRewrites("pr5fm-29", "+60% Profane Orb Damage per Curse"))
		-- the sibling frequency line is NOT touched
		assert.are.equal("+1% Profane Orb Frequency per 1% Cast Speed",
			applyRewrites("pr5fm-29", "+1% Profane Orb Frequency per 1% Cast Speed"))
	end)

	it("rescope: pr5fm-29 is rescoped to the granted orb sub-skill (single match), NOT global-lifted", function()
		assert.is_table(LE_TREE_NODE_SKILL_RESCOPE, "LE_TREE_NODE_SKILL_RESCOPE must be defined")
		local rs = LE_TREE_NODE_SKILL_RESCOPE["pr5fm-29"]
		assert.is_not_nil(rs, "pr5fm-29 must have a rescope entry")
		assert.are.equal(ORB_SKILL, rs.skillId, "must rescope to the orb's own grantedEffect.id")
		assert.is_table(LE_TREE_NODE_GLOBAL_SCOPE, "LE_TREE_NODE_GLOBAL_SCOPE must be defined")
		assert.is_nil(LE_TREE_NODE_GLOBAL_SCOPE["pr5fm-29"],
			"the MORE is consumed by the Profane Orb only, so it must NOT be lifted to global scope")
	end)

	it("parse contract: rewritten line -> MORE Hit Damage 15 x Multiplier:EnemyNegativeAilmentCount(enemy), no residue, no SkillId", function()
		local list, extra = modLib.parseMod("+15% Hit Damage per Negative Ailment on Enemy")
		assert.is_not_nil(list, "must parse")
		assert.is_true(not extra or extra == "", "must leave no residue, got: " .. tostring(extra))
		assert.are.equal(1, #list)
		local mod = list[1]
		assert.are.equal("Damage", mod.name)
		assert.are.equal("MORE", mod.type)
		assert.are.equal(15, mod.value)
		assert.are.equal(MODFLAG_HIT, mod.flags, "must carry the Hit flag so it only scales the orb explosion hit")
		local mult = findTag(mod, "Multiplier", "EnemyNegativeAilmentCount")
		assert.is_not_nil(mult, "must carry Multiplier:EnemyNegativeAilmentCount")
		assert.are.equal("enemy", mult.actor, "the count is read from the enemy modDB")
		assert.is_nil(findTag(mod, "SkillId"), "parse must not produce a SkillId tag (scope comes from the tree node rescope)")
	end)

	it("tree node end-to-end: pr5fm-29 at 4/4 emits ONE MORE Damage 60, Hit-flagged, Multiplier + SkillId(orb)", function()
		newBuild()
		local node = build.spec.nodes["pr5fm-29"]
		assert.is_not_nil(node, "pr5fm-29 must exist in the loaded 1.4 tree")
		node.alloc = 4
		build.spec.tree:ProcessStats(node)
		local moreCount, moreMod = 0
		for _, mod in ipairs(node.modList) do
			if mod.name == "Damage" and mod.type == "MORE" then
				moreCount = moreCount + 1
				moreMod = mod
			end
		end
		assert.are.equal(1, moreCount, "exactly ONE MORE Damage mod must survive")
		assert.are.equal(60, moreMod.value, "+15%/pt at 4/4 rank-scales to +60%")
		assert.are.equal(MODFLAG_HIT, moreMod.flags, "must carry the Hit flag")
		assert.is_not_nil(findTag(moreMod, "Multiplier", "EnemyNegativeAilmentCount"),
			"the node mod must be per-distinct-negative-ailment")
		local skillTag = findTag(moreMod, "SkillId")
		assert.is_not_nil(skillTag, "the SkillId scoping must be present")
		assert.are.equal(ORB_SKILL, skillTag.skillId, "the SkillId must be rescoped to the orb sub-skill")
	end)

	it("behaviour (single-count path): scoped MORE = 15%/pt x points x distinct-ailment count; 0 = no-op; scope + Hit gated", function()
		newBuild()
		local node = build.spec.nodes["pr5fm-29"]
		node.alloc = 4
		build.spec.tree:ProcessStats(node)
		local perAilmentMod
		for _, mod in ipairs(node.modList) do
			if mod.name == "Damage" and mod.type == "MORE" then perAilmentMod = mod end
		end
		assert.is_not_nil(perAilmentMod, "must have the per-ailment MORE Damage mod")

		local orbCfg   = { skillGrantedEffect = { id = ORB_SKILL }, flags = MODFLAG_HIT }
		local otherCfg = { skillGrantedEffect = { id = "Some Other Skill" }, flags = MODFLAG_HIT }
		local function moreAt(count, cfg)
			local modDB = new("ModDB")
			modDB:AddMod(perAilmentMod)
			local enemyDB = new("ModDB")
			modDB.actor.enemy = { modDB = enemyDB }
			enemyDB.multipliers.EnemyNegativeAilmentCount = count -- MANUAL single-count path
			return modDB:More(cfg, "Damage")
		end

		-- 0 distinct ailments -> strict no-op
		assert.are.equal(1, moreAt(0, orbCfg))
		-- 1/2/4 distinct ailments at 4/4 -> 1 + 0.60*count (single count, NO double)
		assert.is_true(math.abs(moreAt(1, orbCfg) - 1.60) < 1e-9, "1 ailment -> x1.60, got " .. tostring(moreAt(1, orbCfg)))
		assert.is_true(math.abs(moreAt(2, orbCfg) - 2.20) < 1e-9, "2 ailments -> x2.20, got " .. tostring(moreAt(2, orbCfg)))
		assert.is_true(math.abs(moreAt(4, orbCfg) - 3.40) < 1e-9,
			"4 distinct ailments -> x3.40 (NOT x6.76 = no double-count), got " .. tostring(moreAt(4, orbCfg)))
		-- scope: a non-orb skill gets nothing even at 4 ailments
		assert.are.equal(1, moreAt(4, otherCfg))
		-- Hit-only: a DoT cfg (no Hit flag) is unaffected
		assert.are.equal(1, moreAt(4, { skillGrantedEffect = { id = ORB_SKILL }, flags = 0 }))
	end)

	it("ModCache: the stale mis-parsed pr5fm-29 row was removed so the live rewrite path regenerates the mod", function()
		local src = readFile("Data/ModCache.lua")
		assert.is_not_nil(src, "must read Data/ModCache.lua")
		assert.is_nil(src:find('c["+15% Profane Orb Damage per Curse"]', 1, true),
			"the stale flat-MORE-plus-residue row must be removed")
	end)

	it("game-file: pr5fm-29 still carries the per-Curse damage stat and maxPoints 4", function()
		local tree = readFile("TreeData/1_4/tree_3.json")
		assert.is_not_nil(tree, "must read TreeData/1_4/tree_3.json")
		assert.is_truthy(tree:find('"pr5fm%-29"', 1, false))
		assert.is_truthy(tree:find("+15% Profane Orb Damage per Curse", 1, true),
			"the stat string the rewrite keys on must still be present")
	end)
end)
