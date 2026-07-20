-- @leb-regression-guard:enemy-full-health-alt-order
-- Word-order aliases of the enemy FullLife conditional. Real affix/tree damage lines
-- phrase the "enemy is at full life" condition in orders the single "against full health
-- enemies" key did not cover: "<stat> To Full Health Enemies", "<stat> Vs Full Health
-- Enemies", "<stat> Against Enemies At Full Health" (plus the "full life" spelling).
--
-- LEB BUG this fixes: only "against full health enemies" was registered in modTagList,
-- so the alt-order lines parsed the leading stat but left "To/Vs Full Health Enemies" /
-- "Against Enemies At Full Health" as NON-EMPTY residue -> Item.lua's mod-line gate
-- (isConnectorOnlyExtra, Item.lua:1901) DROPPED the whole mod (silent UNDER-count, the
-- "node contributed nothing" class, same as against-full-health-enemies /
-- to-low-health-enemies / to-moving-enemies). Stale ModCache rows cached those dropped
-- shapes; they were deleted so the lines re-parse live.
--
-- The fix: modTagList enemy forms ("to full health enemies", "to full life enemies",
-- "vs full health enemies", "vs full life enemies", "against enemies at full health",
-- "against enemies at full life") -> ActorCondition{actor=enemy, var=FullLife} -- the
-- SAME enemy condition conditionEnemyFullLife raises (ConfigOptions ~L984; its
-- suggestPattern already lists "to full life enemies"/"to full health enemies"). It just
-- had no modTagList entry for those orders.
--
-- LONGEST-MATCH: "against enemies at full health" CONTAINS the player-self "at full
-- health" substring (ModParser ~L1691). scan() is earliest-then-longest, so the longer
-- enemy key wins and the line stays enemy-scoped. This spec asserts that explicitly.
--
-- CORPUS-NEUTRAL (deductively proven, no snapshot regen): the ONLY setter of the enemy
-- Condition:FullLife flag is conditionEnemyFullLife's apply (ConfigOptions L985), and
-- that config is absent from EVERY corpus snapshot (grep conditionEnemyFullLife
-- spec/TestBuilds = 0; grep Condition:FullLife = 0) -> the enemy is never flagged full
-- life -> the (non-neg) FullLife condition evaluates FALSE -> the kept MORE is inert,
-- byte-identical to the pre-fix dropped state (every equipping build unaffected). Enable
-- the config (opener/burst) to make it live. See REGRESSION_GUARDS.md
-- "enemy-full-health-alt-order".

describe("EnemyFullHealthAltOrder #skills", function()
	local KEYWORD_MELEE = 512 -- Global.lua KeywordFlag.Melee
	local HIT = 8388608       -- Global.lua ModFlag.Hit

	local function findTag(mod, tagType)
		for _, tag in ipairs(mod) do
			if tag.type == tagType then return tag end
		end
		return nil
	end

	local function assertEnemyFullLife(line, expectValue, expectKeyword)
		local list, extra = modLib.parseMod(line)
		assert.is_not_nil(list, "must parse: " .. line)
		assert.is_true(not extra or extra == "", "must leave no residue (else Item.lua drops it) for: " .. line .. " got: " .. tostring(extra))
		assert.are.equal(1, #list, "one mod for: " .. line)
		local mod = list[1]
		assert.are.equal("Damage", mod.name)
		assert.are.equal("MORE", mod.type)
		assert.are.equal(expectValue, mod.value)
		local cond = findTag(mod, "ActorCondition")
		assert.is_not_nil(cond, "must carry the enemy ActorCondition (else the mod is dropped/unconditional) for: " .. line)
		assert.are.equal("enemy", cond.actor)
		assert.are.equal("FullLife", cond.var)
		assert.is_nil(cond.neg, "must be NON-negated FullLife (that is the enemy at full life) for: " .. line)
		if expectKeyword then
			assert.are.equal(expectKeyword, mod.keywordFlags, "keyword scope must survive the tag attach for: " .. line)
		end
	end

	it("parse contract: all word orders -> MORE Damage x enemy ActorCondition FullLife, no residue", function()
		assertEnemyFullLife("+10% Damage To Full Health Enemies", 10)
		assertEnemyFullLife("+30% Hit Damage Vs Full Health Enemies", 30)
		assertEnemyFullLife("+30% Hit Damage Against Enemies At Full Health", 30)
	end)

	it("'full life' spelling resolves the same as 'full health'", function()
		assertEnemyFullLife("+15% Damage To Full Life Enemies", 15)
		assertEnemyFullLife("+20% Damage Vs Full Life Enemies", 20)
		assertEnemyFullLife("+25% Damage Against Enemies At Full Life", 25)
	end)

	it("keyword preservation: 'Melee Damage Vs Full Health Enemies' keeps Melee + enemy FullLife", function()
		assertEnemyFullLife("+25% Melee Damage Vs Full Health Enemies", 25, KEYWORD_MELEE)
	end)

	-- Folded in from the retired TestErasingStrikeRuthless_spec.lua. Erasing Strike Ruthless
	-- (es6ai-10, maxPoints 4) grants the RAW per-point stat below (x4 -> +100% at max). It used
	-- to require a LE_TREE_NODE_STAT_REWRITE entry to escape a residue-drop; <see git log>'s
	-- "vs full health enemies" key made the raw line parse residue-free, so the rewrite was
	-- retired as a NO-OP. This case is the surviving contract: if EITHER the bare-form ->
	-- BASE_MORE behaviour (@leb-regression-guard:bare-form-damage-affix-increased, ModParser:56)
	-- OR the "vs full health enemies" key breaks, the es6ai-10 raw line goes red HERE.
	it("es6ai-10 (Erasing Strike Ruthless) raw line -> MORE (not INCREASED), Melee kept, non-neg enemy FullLife", function()
		assertEnemyFullLife("+25% Melee Damage Vs Full Health Enemies", 25, KEYWORD_MELEE)
		-- explicit MORE-not-INCREASED assertion (bare "+N%" must stay BASE_MORE for tree nodes)
		local mod = modLib.parseMod("+25% Melee Damage Vs Full Health Enemies")[1]
		assert.are.equal("MORE", mod.type, "bare '+N%' tree-node damage must be MORE, not INCREASED")
	end)

	it("longest-match: 'Against Enemies At Full Health' is ENEMY-scoped, not the player 'at full health'", function()
		local mod = modLib.parseMod("+30% Hit Damage Against Enemies At Full Health")[1]
		-- must be the enemy ActorCondition, and must NOT collapse to the player self-Condition
		assert.is_not_nil(findTag(mod, "ActorCondition"), "must be enemy-scoped")
		local selfCond = findTag(mod, "Condition")
		assert.is_nil(selfCond, "must NOT attach the player-self Condition:FullLife (that is 'while at full health')")
	end)

	it("control: the player self-form stays player-scoped (regression fence)", function()
		local mod = modLib.parseMod("27% more Physical Damage while at Full Health")[1]
		local cond = findTag(mod, "Condition")
		assert.is_not_nil(cond, "player self-form must keep its Condition")
		assert.is_nil(cond.actor, "player self-form must NOT become enemy-scoped")
		assert.are.equal("FullLife", cond.var)
		assert.is_nil(findTag(mod, "ActorCondition"), "player self-form must NOT be enemy ActorCondition")
	end)
end)
