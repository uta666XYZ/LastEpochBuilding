-- @leb-regression-guard:leech-le-instance-model
-- Locks LEB's leech model to Last Epoch's engine (datamining, formulas_verified.md §47),
-- replacing the Path-of-Building port that diverged AND was inert.
--
-- LE leech (LeechTracker / PlayerLeechTracker, datamined game source):
--   * Each leeching hit enqueues an instance of size Sum(typeDmg x HealthLeech%) (SP51),
--     paired with a window = LeechDuration / (1 + IncreasedLeechRate) seconds
--     (defaultLeechDuration = 3s; AddLifeLeech datamined offset = 3.0/(1+ILR)).
--   * OnUpdateTick (datamined offset) drains each instance LINEARLY: heal = amount*dt/remDur,
--     so every instance pays out its FULL amount over its window. Therefore the sustained
--     leech/s under continuous combat = leechPerHit x (leeching hits/second), INDEPENDENT of
--     the window / IncreasedLeechRate (ILR shortens the window => faster burst recovery, same
--     total throughput).
--   * There is NO per-second "% of pool" cap anywhere in the leech path; the only limiters are
--     the per-instance window, the full-health overheal discard (leechDropoffThreshold), and
--     DisableLeechForDuration.
--
-- The PoB port (removed) used data.misc.LeechRateBase = 0.02 (PoE 2%/s/instance pool), a
-- MaxLifeLeechRate/MaxManaLeechRate per-second pool cap, and an InstantLeech split -- none of
-- which exist in LE. Worse, MaxLifeLeechInstance / MaxLifeLeechRate were never seeded, so
-- calcLib.val -> 0 and `m_min(total, 0) = 0` zeroed ALL leech (leech was identically 0 for
-- every LE build, not merely mismatched).
--
-- See REGRESSION_GUARDS.md "leech-le-instance-model".

local function readSource(relPath)
	local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
	assert.is_not_nil(f, "must be able to open " .. relPath)
	local text = f:read("*a"); f:close()
	return text
end

local function setMods(s)
	build.configTab.input.customMods = s
	build.configTab:BuildModList()
	runCallback("OnFrame")
end

describe("LeechLeInstanceModel", function()

	---------------------------------------------------------------------------
	-- Source invariants: lock the structural removal of the PoB machinery.
	---------------------------------------------------------------------------
	describe("source invariants", function()
		local data_, off, def, brk, sec

		setup(function()
			data_ = readSource("Modules/Data.lua")
			off = readSource("Modules/CalcOffence.lua")
			def = readSource("Modules/CalcDefence.lua")
			brk = readSource("Modules/CalcBreakdown.lua")
			sec = readSource("Modules/CalcSections.lua")
		end)

		it("Data.lua defines the LE LeechDuration (3s) and drops the PoE LeechRateBase", function()
			assert.is_truthy(data_:find("LeechDuration = 3", 1, true),
				"Data.lua must define LeechDuration = 3 (LE defaultLeechDuration)")
			assert.is_falsy(data_:find("LeechRateBase = 0.02", 1, true),
				"the PoE LeechRateBase = 0.02 constant must be gone")
		end)

		it("CalcOffence carries the guard and computes rate = perHit x leechHitRate (no LeechRateBase)", function()
			assert.is_truthy(off:find("@leb-regression-guard:leech-le-instance-model", 1, true),
				"CalcOffence must declare the guard")
			assert.is_truthy(off:find("output.LifeLeechRate = output.LifeLeechPerHit * leechHitRate", 1, true),
				"sustained life leech rate must be perHit x leechHitRate")
			assert.is_truthy(off:find("output.LifeLeechDuration = data.misc.LeechDuration / leechRateMod", 1, true),
				"window must be LeechDuration / (1 + IncreasedLeechRate)")
			assert.is_falsy(off:find("data.misc.LeechRateBase", 1, true),
				"no reference to the removed LeechRateBase may remain in CalcOffence")
			assert.is_falsy(off:find("m_min(output.LifeLeechRate, output.MaxLifeLeechRate)", 1, true),
				"the PoE per-second leech-rate cap clamp must be gone")
		end)

		it("CalcDefence no longer computes the PoE leech-rate pool cap", function()
			assert.is_truthy(def:find("@leb-regression-guard:leech-le-instance-model", 1, true),
				"CalcDefence must declare the guard where the cap was removed")
			assert.is_falsy(def:find('calcLib.val(modDB, "MaxLifeLeechRate")', 1, true),
				"MaxLifeLeechRate cap computation must be gone")
			assert.is_falsy(def:find('calcLib.val(modDB, "MaxLifeLeechInstance")', 1, true),
				"MaxLifeLeechInstance cap computation must be gone")
		end)

		it("CalcBreakdown.leech uses the LE-model signature (no LeechRateBase)", function()
			assert.is_truthy(brk:find("function breakdown.leech(perHit, rate, instances, duration, hitRate, leechRateMod, poolLabel)", 1, true),
				"breakdown.leech must take the LE-model arguments")
			assert.is_falsy(brk:find("data.misc.LeechRateBase", 1, true),
				"breakdown.leech must not reference LeechRateBase")
		end)

		it("CalcSections drops the Life/Mana Leech Cap rows", function()
			assert.is_falsy(sec:find('label = "Life Leech Cap"', 1, true),
				"the PoE 'Life Leech Cap' display row must be gone")
			assert.is_falsy(sec:find('label = "Mana Leech Cap"', 1, true),
				"the PoE 'Mana Leech Cap' display row must be gone")
		end)
	end)

	---------------------------------------------------------------------------
	-- Parse contract: the LE leech-% affix wires to DamageLifeLeech (SP51) and
	-- "Increased Leech Rate" to LeechRate (SP102).
	---------------------------------------------------------------------------
	describe("parse contract", function()
		it("'20% of Damage Leeched as Health' -> DamageLifeLeech BASE 20", function()
			local mods = modLib.parseMod("20% of Damage Leeched as Health")
			assert.is_not_nil(mods and mods[1], "must parse")
			assert.are.equals("DamageLifeLeech", mods[1].name)
			assert.are.equals("BASE", mods[1].type)
			assert.are.equals(20, mods[1].value)
		end)

		it("'100% Increased Leech Rate' -> LeechRate INC 100", function()
			local mods = modLib.parseMod("100% Increased Leech Rate")
			assert.is_not_nil(mods and mods[1], "must parse")
			assert.are.equals("LeechRate", mods[1].name)
			assert.are.equals("INC", mods[1].type)
			assert.are.equals(100, mods[1].value)
		end)
	end)

	---------------------------------------------------------------------------
	-- Behavioural: drive a directly-cast Fireball (positive cast speed) and a
	-- leech mod through the full calc.
	---------------------------------------------------------------------------
	describe("behavioural", function()
		before_each(function()
			newBuild()
			-- Fireball: a directly-cast spell with cast speed so leechHitRate > 0.
			build.skillsTab:SelSkill(1, "Fireball")
		end)

		it("leech is non-zero (regression: the PoB port made it identically 0)", function()
			setMods("200% increased Spell Damage\n20% of Damage Leeched as Health")
			local o = build.calcsTab.mainOutput
			assert.is_truthy(o.LifeLeechPerHit > 0, "leech per hit must be > 0")
			assert.is_truthy(o.LifeLeechRate > 0, "sustained leech rate must be > 0 (was 0 pre-fix)")
		end)

		it("leech per hit = leech%% x AverageHit (SP51 wiring), rate = perHit x a positive hit rate", function()
			setMods("200% increased Spell Damage\n20% of Damage Leeched as Health")
			local o = build.calcsTab.mainOutput
			assert.is_near(0.20 * o.AverageHit, o.LifeLeechPerHit, math.max(1, 0.20 * o.AverageHit * 1e-3),
				"per-hit leech must equal 20% of the average hit")
			local k = o.LifeLeechRate / o.LifeLeechPerHit
			assert.is_truthy(k > 0, "rate/perHit (the leeching-hits-per-second factor) must be positive")
		end)

		it("recovery window = LeechDuration / (1 + IncreasedLeechRate)", function()
			setMods("20% of Damage Leeched as Health")
			assert.is_near(3.0, build.calcsTab.mainOutput.LifeLeechDuration, 1e-6,
				"with 0 Increased Leech Rate the window is the 3s base")

			setMods("20% of Damage Leeched as Health\n100% Increased Leech Rate")
			assert.is_near(1.5, build.calcsTab.mainOutput.LifeLeechDuration, 1e-6,
				"+100% Increased Leech Rate halves the window to 1.5s")
		end)

		it("IncreasedLeechRate does NOT change the sustained rate (window only) -- key §47 invariant", function()
			setMods("200% increased Spell Damage\n20% of Damage Leeched as Health")
			local base = build.calcsTab.mainOutput.LifeLeechRate
			setMods("200% increased Spell Damage\n20% of Damage Leeched as Health\n100% Increased Leech Rate")
			local withIlr = build.calcsTab.mainOutput.LifeLeechRate
			assert.is_near(base, withIlr, math.max(1, base * 1e-4),
				"sustained leech/s must be invariant under Increased Leech Rate (each instance pays its full amount)")
		end)

		it("no per-second pool cap: doubling leech%% doubles the sustained rate (linear)", function()
			setMods("200% increased Spell Damage\n20% of Damage Leeched as Health")
			local r20 = build.calcsTab.mainOutput.LifeLeechRate
			setMods("200% increased Spell Damage\n40% of Damage Leeched as Health")
			local r40 = build.calcsTab.mainOutput.LifeLeechRate
			assert.is_truthy(r20 > 0 and r40 > 0, "both rates must be positive")
			assert.is_near(2 * r20, r40, math.max(1, 2 * r20 * 1e-3),
				"leech scales linearly with leech% -- there is no PoE-style rate cap")
		end)
	end)
end)
