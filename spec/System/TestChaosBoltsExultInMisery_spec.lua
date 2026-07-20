-- @leb-regression-guard:chaos-bolts-exult-in-misery-enemy-ailment
-- Warlock "Exult in Misery" (Chaos Bolts tree node ch4bo-11) per-distinct-negative-
-- ailment MORE damage. The node's four DISPLAY stat lines are ONE engine value:
--   stats (TreeData/{1_2,1_3,1_4}/tree_3.json ch4bo-11, maxPoints 3, 1_4 L8600-8629):
--     ["+4% Hit Damage to Damned", "+4% Hit Damage to Ignited",
--      "+4% Hit Damage to Bleeding", "+4% Hit Damage to Frostbitten"]
--     description "Chaos Bolts' hits deal more damage (multiplicative with other
--     modifiers) to damned, ignited, bleeding and frostbitten."
--     reminderText "Hitting enemies inflicted with multiple of these ailments, will
--     cause the damage modifier to stack."
-- Datamine (datamined game source): datamined game source builds ONE
-- DamageEffectMoreDamagePerNegativeAilment(perAilment = field+0x154 = the node's
-- 4%/pt, maxAilments = 0). Apply (datamined game source):
-- factor = 1 + perAilment * GetUniqueNegativeAilmentCount(target). So a 3/3 node with
-- all four ailments present = x(1 + 0.12*4) = x1.48 on Chaos Bolts hits -- exactly the
-- reminderText's "multiple of these ailments ... will cause the damage modifier to
-- stack".
--
-- LEB BUG this fixes (pre-fix Data/ModCache.lua): the four lines mis-parsed, each
-- leaving NON-EMPTY residue ("to Bleeding"->SkillName "Bleed" + "   to ing ",
-- "to Ignited"->SkillName "Ignite" + "   to d ", "to Damned" + "   to  ",
-- "to Frostbitten"->bare MORE + "   to Frostbitten "). PassiveTree's tree gate drops
-- any node mod with non-empty extra (`if mod.list and (not mod.extra or
-- mod.extra == "")`), so ALL FOUR were DROPPED -- pre-fix the node contributed
-- NOTHING (the AerialProwess "node contributed nothing" class, NOT an over-count;
-- verified by a tree probe: 0 surviving Damage MORE mods, and a 3-build corpus A/B:
-- zero output change at default config). The fix is therefore strictly corpus-neutral
-- at default config AND newly ENABLES the node for config > 0.
--
-- The fix collapses the four DISPLAY lines into ONE count-scaled MORE (the engine's
-- single perAilment): Data/Global.lua LE_TREE_NODE_STAT_REWRITE["ch4bo-11"] rewrites
-- the Damned line to "per Negative Ailment on Enemy" (value-tolerant, $-anchored) and
-- EMPTIES the other three; PassiveTree.lua ProcessStats skips the emptied lines;
-- ModParser attaches Multiplier:EnemyNegativeAilmentCount (actor=enemy); the
-- "# Distinct Negative Ailments on Enemy" config (default 0 -> strict no-op) sets a
-- Multiplier:EnemyNegativeAilmentCount BASE mod on the enemy modList, which
-- ModStore:GetMultiplier sums directly via its 3rd term (there is NO CalcPerform
-- propagation into enemyDB.multipliers -- that loop was removed because it made the
-- count double-count to 2N; see multiplier-propagation-loop-no-double-count). Four
-- separate MOREs would be WRONG --
-- ModDB:MoreInternal compounds them multiplicatively (~x1.57 at count=4), not the
-- engine's additive-within-mod value*count (x1.48). See REGRESSION_GUARDS.md
-- "chaos-bolts-exult-in-misery-enemy-ailment".

local MODFLAG_HIT = 8388608 -- Global.lua ModFlag.Hit (the "Hit Damage" gate)

describe("ChaosBoltsExultInMisery #skills", function()
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

	it("registry: collapses the four display lines into ONE count-scaled line", function()
		-- Damned carries the count multiplier (leading value preserved, value-tolerant)
		assert.are.equal("+4% Hit Damage per Negative Ailment on Enemy",
			applyRewrites("ch4bo-11", "+4% Hit Damage to Damned"))
		assert.are.equal("+5% Hit Damage per Negative Ailment on Enemy",
			applyRewrites("ch4bo-11", "+5% Hit Damage to Damned"))
		-- the other three are EMPTIED so exactly one MORE survives the collapse
		assert.are.equal("", applyRewrites("ch4bo-11", "+4% Hit Damage to Ignited"))
		assert.are.equal("", applyRewrites("ch4bo-11", "+4% Hit Damage to Bleeding"))
		assert.are.equal("", applyRewrites("ch4bo-11", "+4% Hit Damage to Frostbitten"))
		-- an unrelated stat (no "to <ailment>" suffix) is untouched
		assert.are.equal("+10% Cast Speed", applyRewrites("ch4bo-11", "+10% Cast Speed"))
	end)

	it("registry: ch4bo-11 is scoped to its own skill (NOT lifted to global scope)", function()
		assert.is_table(LE_TREE_NODE_GLOBAL_SCOPE, "LE_TREE_NODE_GLOBAL_SCOPE must be defined")
		assert.is_nil(LE_TREE_NODE_GLOBAL_SCOPE["ch4bo-11"],
			"the MORE is consumed by Chaos Bolts, so the default SkillId scope must stay -- do NOT global-lift")
	end)

	it("parse contract: rewritten line -> MORE Hit Damage 4% x Multiplier:EnemyNegativeAilmentCount(enemy), no residue, no SkillId", function()
		local list, extra = modLib.parseMod("+4% Hit Damage per Negative Ailment on Enemy")
		assert.is_not_nil(list, "must parse")
		assert.is_true(not extra or extra == "", "must leave no residue, got: " .. tostring(extra))
		assert.are.equal(1, #list)
		local mod = list[1]
		assert.are.equal("Damage", mod.name)
		assert.are.equal("MORE", mod.type)
		assert.are.equal(4, mod.value)
		assert.are.equal(MODFLAG_HIT, mod.flags, "must carry the Hit flag (Hit Damage), so it only scales hits")
		local mult = findTag(mod, "Multiplier", "EnemyNegativeAilmentCount")
		assert.is_not_nil(mult, "must carry Multiplier:EnemyNegativeAilmentCount")
		assert.are.equal("enemy", mult.actor, "the count is read from the enemy modDB (mirrors per-Bleed precedent)")
		assert.is_nil(mult.limit, "no tag limit -- the engine maxAilments arg = 0 (uncapped); the realistic cap is config-side")
		assert.is_nil(findTag(mod, "SkillId"), "parse must not produce a SkillId tag (scope comes from the tree node)")
	end)

	it("tree node end-to-end: ch4bo-11 at 3/3 emits exactly ONE MORE Hit Damage mod (value 12), scoped to Chaos Bolts, no node.extra", function()
		newBuild()
		local node = build.spec.nodes["ch4bo-11"]
		assert.is_not_nil(node, "ch4bo-11 must exist in the loaded 1.4 tree")
		assert.is_not_nil(node.skillId, "ch4bo-11 must be a skill-subtree node (skillId set)")
		node.alloc = 3
		build.spec.tree:ProcessStats(node)
		assert.is_falsy(node.extra,
			"the emptied display lines must be skipped, not flagged as unsupported (node.extra stays unset)")
		local moreCount, moreMod = 0
		for _, mod in ipairs(node.modList) do
			if mod.name == "Damage" and mod.type == "MORE" then
				moreCount = moreCount + 1
				moreMod = mod
			end
		end
		assert.are.equal(1, moreCount, "exactly ONE MORE Damage mod must survive the four-line collapse")
		assert.are.equal(12, moreMod.value, "+4%/pt at 3/3 rank-scales to +12%")
		assert.is_not_nil(findTag(moreMod, "Multiplier", "EnemyNegativeAilmentCount"),
			"the node mod must be per-distinct-negative-ailment")
		assert.is_not_nil(findTag(moreMod, "SkillId"),
			"the SkillId scoping must be KEPT -- the MORE only buffs Chaos Bolts")
	end)

	it("behaviour: scoped MORE = 4%/pt x points x distinct-ailment count; 0 = no-op; no double-count; other skills unaffected", function()
		newBuild()
		local node = build.spec.nodes["ch4bo-11"]
		node.alloc = 3
		build.spec.tree:ProcessStats(node)
		local perAilmentMod
		for _, mod in ipairs(node.modList) do
			if mod.name == "Damage" and mod.type == "MORE" then perAilmentMod = mod end
		end
		assert.is_not_nil(perAilmentMod, "must have the per-ailment MORE Damage mod")

		local cbCfg    = { skillGrantedEffect = { id = node.skillId }, flags = MODFLAG_HIT }
		local otherCfg = { skillGrantedEffect = { id = "Some Other Skill" }, flags = MODFLAG_HIT }
		local function moreAt(count, cfg)
			local modDB = new("ModDB")
			modDB:AddMod(perAilmentMod)
			local enemyDB = new("ModDB")
			modDB.actor.enemy = { modDB = enemyDB }
			enemyDB.multipliers.EnemyNegativeAilmentCount = count
			return modDB:More(cfg, "Damage")
		end

		-- 0 distinct ailments (default config) -> strict no-op
		assert.are.equal(1, moreAt(0, cbCfg))
		-- 1/2/4 distinct ailments at 3/3 -> 1 + 0.12*count
		assert.is_true(math.abs(moreAt(1, cbCfg) - 1.12) < 1e-9, "1 ailment -> x1.12, got " .. tostring(moreAt(1, cbCfg)))
		assert.is_true(math.abs(moreAt(2, cbCfg) - 1.24) < 1e-9, "2 ailments -> x1.24, got " .. tostring(moreAt(2, cbCfg)))
		assert.is_true(math.abs(moreAt(4, cbCfg) - 1.48) < 1e-9,
			"3/3 with all 4 distinct ailments -> x1.48 (NOT x1.96 = no double-count), got " .. tostring(moreAt(4, cbCfg)))
		-- scope: a non-Chaos-Bolts skill gets nothing even at 4 ailments
		assert.are.equal(1, moreAt(4, otherCfg))
		-- the MORE only scales HITS: a DoT cfg (no Hit flag) is unaffected
		assert.are.equal(1, moreAt(4, { skillGrantedEffect = { id = node.skillId }, flags = 0 }))
	end)

	it("config: '# Distinct Negative Ailments on Enemy' is ifMult-gated, capped at 4, feeds the enemy multiplier", function()
		local src = readFile("Modules/ConfigOptions.lua")
		assert.is_not_nil(src, "must read Modules/ConfigOptions.lua")
		local entry = src:match('{ var = "multiplierEnemyNegativeAilmentCount".-end },')
		assert.is_not_nil(entry, "multiplierEnemyNegativeAilmentCount config entry must exist")
		assert.is_truthy(entry:find('type = "count"', 1, true))
		assert.is_truthy(entry:find('ifMult = "EnemyNegativeAilmentCount"', 1, true),
			"must be visibility-gated on the EnemyNegativeAilmentCount multiplier being referenced (AerialProwess pattern)")
		assert.is_truthy(entry:find("max 4", 1, true), "label must carry the cap hint '(max 4)'")
		assert.is_truthy(entry:find("math.min(val, 4)", 1, true), "apply must clamp the count to 4")
		assert.is_truthy(entry:find('NewMod("Multiplier:EnemyNegativeAilmentCount", "BASE", val, "Config"', 1, true),
			"apply must set Multiplier:EnemyNegativeAilmentCount on the enemy modList")
	end)

	it("CalcPerform: the enemy-stack propagation loop is REMOVED (it double-counted to 2N)", function()
		-- The loop `multipliers[var] = enemyDB:Sum("BASE", nil, "Multiplier:"..var)` used to
		-- copy the config BASE mod into enemyDB.multipliers. But GetMultiplier already sums
		-- that BASE mod (3rd term), and enemyDB.conditions.Effective is true in the effective
		-- pass, so the copy made GetMultiplier = multipliers[var] + Sum(BASE) = 2N. It is
		-- deleted so the BASE-sum is the single source of truth. See
		-- multiplier-propagation-loop-no-double-count.
		local src = readFile("Modules/CalcPerform.lua")
		assert.is_not_nil(src, "must read Modules/CalcPerform.lua")
		local loop = src:match('for _, var in ipairs%(%b{}%) do\n%s*local val = enemyDB:Sum%("BASE", nil, "Multiplier:"%.%.var%)')
		assert.is_nil(loop, "the enemy-stack propagation loop must NOT exist (it caused a 2N double-count)")
		assert.is_truthy(src:find("@leb-regression-guard:multiplier-propagation-loop-no-double-count", 1, true),
			"the removal must be marked with the multiplier-propagation-loop-no-double-count guard")
	end)

	it("no double-count: a config Multiplier:EnemyNegativeAilmentCount BASE mod (the REAL path) yields GetMultiplier == N, not 2N", function()
		-- Reproduces the exact config-driven path (ConfigOptions.lua:1246): a BASE
		-- "Multiplier:EnemyNegativeAilmentCount" mod on the enemy modDB, gated by
		-- Condition:Effective, with conditions.Effective = true (the effective-DPS pass).
		-- Before the loop removal GetMultiplier returned 2N here; now it must return N.
		local enemyDB = new("ModDB")
		enemyDB.conditions.Effective = true
		enemyDB:NewMod("Multiplier:EnemyNegativeAilmentCount", "BASE", 3, "Config", { type = "Condition", var = "Effective" })
		assert.are.equal(3, enemyDB:GetMultiplier("EnemyNegativeAilmentCount", nil),
			"config-in 3 must give multiplier-out 3 (single-count), not 6")
	end)

	it("ModCache: the four stale ch4bo-11 rows were removed; the unrelated 'to Cursed' row is kept", function()
		local src = readFile("Data/ModCache.lua")
		assert.is_not_nil(src, "must read Data/ModCache.lua")
		for _, ailment in ipairs({ "Bleeding", "Damned", "Frostbitten", "Ignited" }) do
			assert.is_nil(src:find('c["+4% Hit Damage to ' .. ailment .. '"]', 1, true),
				"the stale mis-parsed row for '" .. ailment .. "' must be removed so the live parser regenerates the collapsed mod")
		end
		assert.is_not_nil(src:find('c["+4% Hit Damage to Cursed"]', 1, true),
			"the unrelated enemy-Cursed ActorCondition row must be KEPT")
	end)

	it("game-file: ch4bo-11 still carries the four stat strings and the stacking reminderText", function()
		local tree = readFile("TreeData/1_4/tree_3.json")
		assert.is_not_nil(tree, "must read TreeData/1_4/tree_3.json")
		assert.is_truthy(tree:find('"ch4bo%-11"', 1, false))
		assert.is_truthy(tree:find("Exult in Misery", 1, true))
		for _, ailment in ipairs({ "Damned", "Ignited", "Bleeding", "Frostbitten" }) do
			assert.is_truthy(tree:find("+4% Hit Damage to " .. ailment, 1, true),
				"the '" .. ailment .. "' stat string the rewrite keys on must still be present")
		end
		assert.is_truthy(tree:find("will cause the damage modifier to stack", 1, true),
			"the reminderText that justifies the count-stacking model must still be present")
	end)
end)
