-- @leb-regression-guard:multiplier-propagation-loop-no-double-count
-- Enemy "per X stack / per negative ailment" counts are fed by config
-- "Multiplier:XStack" BASE mods on the enemy modList (with Condition:Effective),
-- e.g. ConfigOptions.lua:1246 for EnemyNegativeAilmentCount. ModStore:GetMultiplier
-- (Classes/ModStore.lua:261) already reads those via its 3rd term
-- `Sum("BASE", cfg, "Multiplier:"..var)`, and enemyDB.conditions.Effective is true in
-- the effective-DPS pass, so the BASE mod is summed there.
--
-- LEB BUG this guards against: a former propagation loop in CalcPerform.lua
-- (`for var in {BleedStack, ..., EnemyNegativeAilmentCount} do
--    multipliers[var] = enemyDB:Sum("BASE", nil, "Multiplier:"..var) end`) copied the
-- SAME BASE value into enemyDB.multipliers, so GetMultiplier returned
-- `multipliers[var] + Sum(BASE) = 2N` -- an UNCONDITIONAL DOUBLER for every one of the
-- 11 vars it touched. Consumers (Chaos Bolts "Exult in Misery" ch4bo-11, Mad
-- Alchemist's Ladle, Profane Orb Hex Flurry pr5fm-29, per-bleed / per-curse mods) then
-- read `factor = 1 + perAilment * (2N)` instead of the datamined `1 + perAilment * N`
-- (e.g. ch4bo-11 3/3 all-4 = x1.96 instead of x1.48). It was latent (no corpus build
-- sets any of these configs, all default 0) but real at config > 0. The loop was
-- deleted so the BASE-sum is the single source of truth: GetMultiplier(var, cfg) == N.
-- There is ZERO direct reader of enemyDB.multipliers[<stackvar>] in src/ (grep), so
-- nothing depended on the propagated copy. See REGRESSION_GUARDS.md
-- "multiplier-propagation-loop-no-double-count". Do NOT reintroduce the loop.

describe("MultiplierPropagationNoDoubleCount #skills", function()
	local function readSource(relPath)
		local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
		if not f then return nil end
		local s = f:read("*a"); f:close()
		return s
	end

	-- The core invariant: config-in N -> multiplier-out N (NOT 2N), driven by the exact
	-- config path (a BASE Multiplier mod gated on Condition:Effective, in the effective
	-- pass). Covers BOTH EnemyNegativeAilmentCount (ch4bo-11 / Ladle / Profane) AND
	-- BleedStack (per-bleed consumers) -- the loop doubled ALL 11 vars identically, so a
	-- partial fix that spared one would leave the others broken.
	local function multAt(var, n)
		local enemyDB = new("ModDB")
		enemyDB.conditions.Effective = true
		enemyDB:NewMod("Multiplier:" .. var, "BASE", n, "Config", { type = "Condition", var = "Effective" })
		return enemyDB:GetMultiplier(var, nil)
	end

	it("EnemyNegativeAilmentCount: config-in N -> GetMultiplier == N (single-count)", function()
		assert.are.equal(0, multAt("EnemyNegativeAilmentCount", 0), "0 -> 0 (no-op)")
		assert.are.equal(3, multAt("EnemyNegativeAilmentCount", 3), "3 -> 3, NOT 6 (no double-count)")
		assert.are.equal(4, multAt("EnemyNegativeAilmentCount", 4), "4 -> 4, NOT 8")
	end)

	it("BleedStack: config-in N -> GetMultiplier == N (single-count)", function()
		assert.are.equal(5, multAt("BleedStack", 5), "5 -> 5, NOT 10 (the loop doubled BleedStack identically)")
	end)

	it("source: the CalcPerform enemy-stack propagation loop is gone and the guard marker is present", function()
		local src = readSource("Modules/CalcPerform.lua")
		assert.is_not_nil(src, "must read Modules/CalcPerform.lua")
		local loop = src:match('for _, var in ipairs%(%b{}%) do\n%s*local val = enemyDB:Sum%("BASE", nil, "Multiplier:"%.%.var%)')
		assert.is_nil(loop, "the enemy-stack propagation loop must NOT exist (it caused a 2N double-count)")
		assert.is_truthy(src:find("@leb-regression-guard:multiplier-propagation-loop-no-double-count", 1, true),
			"the removal site must carry the guard marker")
	end)
end)
