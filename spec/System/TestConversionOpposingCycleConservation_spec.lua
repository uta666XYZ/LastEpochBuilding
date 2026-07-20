-- @leb-regression-guard:conversion-opposing-cycle-conservation
-- Locks the rule that two OPPOSING base-damage conversions forming a pure (exit-less)
-- 100% CYCLE -- e.g. Cold->Physical together with Physical->Cold -- CONSERVE the
-- skill's convertible base instead of dropping it.
--
-- Bug: calcs.offence resolves conversion by a Gauss-Seidel fixpoint and then scales each
-- type by retention(t) = conversionTable[t].mult (the fraction that does NOT convert out).
-- For an ACYCLIC chain (or a LEAKY cycle that has an exit to a retention>0 sink) this
-- conserves -- base that converts out of t is counted in t's successors. But a PURE 100%
-- cycle gives EVERY member retention=0, so the circulating base (which the fixpoint drives
-- to infinity, then caps) is multiplied by 0 and DROPPED. Real corpus impact: Primalist
-- Avalanche allocating BOTH av75ch-9 "Rockfall" ( Cold Damage -> Physical Damage) and
-- av75ch-20 "Frost" ( Physical Damage -> Cold Damage) (src/TreeData/1_4/tree_0.json) lost
-- the whole intrinsic Avalanche base: SuXes2 lv92 Shaman body cold base 417.92 -> 337.92
-- (80 pre-eff cold dropped), even though both node reminders state the result must equal
-- Frost-only ("If you have this and Frost, Rockfall has no effect").
--
-- Game truth: DamageStatsHolder.BaseDamageStats.convertBaseDamage(from,to,proportion)
-- (datamining) is  damage[to] += proportion*damage[from]; damage[from] *= (1-prop),
-- applied ONCE per conversion stat in sequence -- mass is moved, never destroyed, so the
-- total is conserved at every step. The fix re-resolves the intrinsic base that way, but
-- ONLY when the fixpoint actually trapped base (a type that cannot reach a retention>0
-- sink accumulated base) -- the acyclic/leaky path is left to the fixpoint and stays
-- byte-identical. The trapped base lands at the type whose inbound conversion is applied
-- LAST in DamageTypes order, matching the node reminder.
--
-- See REGRESSION_GUARDS.md "conversion-opposing-cycle-conservation".

describe("ConversionOpposingCycleConservation", function()
	before_each(function()
		newBuild()
	end)

	-- Select a skill, inject config (non-weapon) BASE conversion mods, recompute, return
	-- the main output. Conversion stats reach activeSkill.conversionTable regardless of
	-- source, so config injection exercises the same cycle the tree nodes build.
	local function calcWith(skill, mods)
		newBuild()
		build.skillsTab:SelSkill(1, skill)
		runCallback("OnFrame")
		local cfg = build.configTab.modList
		for _, m in ipairs(mods or {}) do
			cfg:NewMod(m[1], "BASE", m[2], "OpposingCycleSpec")
		end
		build.buildFlag = true
		runCallback("OnFrame")
		return build.calcsTab.mainOutput
	end
	local function hit(out, t) return out[t .. "HitAverage"] or 0 end
	local function approx(a, b, tol) return math.abs(a - b) <= (tol or 0.5) end

	it("opposing 100% cycle on the skill's own base CONSERVES total (pre-fix: dropped to ~0)", function()
		-- Fireball is intrinsic Fire. Fire<->Cold opposing 100% cycle: Fire->Cold AND
		-- Cold->Fire. The intrinsic Fire base enters a pure exit-less cycle. Pre-fix the
		-- whole base was zeroed (retention=0 on both members); the fix conserves it.
		local base = calcWith("Fireball", {})
		local baseFire, baseTotal = hit(base, "Fire"), base.TotalAvg
		assert.is_true(baseFire > 0, "Fireball intrinsic Fire base must register")

		local cyc = calcWith("Fireball", {
			{ "FireDamageConvertToCold", 100 },
			{ "ColdDamageConvertToFire", 100 },
		})
		assert.is_true(approx(cyc.TotalAvg, baseTotal, 0.5),
			"the opposing cycle must CONSERVE the total base (pre-fix this collapsed to ~0)")
	end)

	it("opposing 100% cycle lands the base at the LAST-applied destination (DamageTypes order)", function()
		-- DamageTypes order is Fire, Cold, ... so the sequential pass applies Fire->Cold
		-- first then Cold->Fire last => the base ends on Fire (mirrors the in-game node
		-- reminder that the pair nets to the surviving direction). Total conserved, the
		-- intermediate Cold lane left empty.
		local base = calcWith("Fireball", {})
		local baseFire = hit(base, "Fire")
		local cyc = calcWith("Fireball", {
			{ "FireDamageConvertToCold", 100 },
			{ "ColdDamageConvertToFire", 100 },
		})
		assert.is_true(approx(hit(cyc, "Fire"), baseFire, 0.5),
			"the cycle base must return to Fire (last-applied conversion wins), not be dropped")
		assert.are.equals(0, hit(cyc, "Cold"),
			"no base may be stranded on the intermediate Cold lane")
	end)

	it("three-type pure cycle (Fire->Cold->Lightning->Fire) conserves", function()
		local base = calcWith("Fireball", {})
		local baseTotal = base.TotalAvg
		local cyc = calcWith("Fireball", {
			{ "FireDamageConvertToCold", 100 },
			{ "ColdDamageConvertToLightning", 100 },
			{ "LightningDamageConvertToFire", 100 },
		})
		assert.is_true(approx(cyc.TotalAvg, baseTotal, 0.5),
			"a 3-type exit-less cycle must also conserve the total base")
	end)

	it("ACYCLIC single-hop stays byte-identical (the trapped branch must NOT fire)", function()
		-- Fire->Cold with no back-edge: Cold is a retention>0 sink, nothing is trapped, so
		-- the fixpoint path is used unchanged. All base lands on Cold, total conserved.
		local base = calcWith("Fireball", {})
		local baseFire, baseTotal = hit(base, "Fire"), base.TotalAvg
		local out = calcWith("Fireball", { { "FireDamageConvertToCold", 100 } })
		assert.are.equals(0, hit(out, "Fire"), "Fire fully converts out")
		assert.is_true(approx(hit(out, "Cold"), baseFire, 0.5), "Cold receives the full base (single hop)")
		assert.is_true(approx(out.TotalAvg, baseTotal, 0.5), "single hop conserves total")
	end)

	it("LEAKY cycle (has an exit) is left to the fixpoint and still conserves", function()
		-- Fire->Cold 100%, Cold->Fire 50% + Cold->Lightning 50%: the cycle has an exit
		-- (Lightning is a retention>0 sink), so every type is grounded -> the trapped branch
		-- does NOT fire and the fixpoint drives the base out through Lightning. Total stays
		-- conserved either way; this pins that a leaky cycle keeps the (byte-identical)
		-- fixpoint behaviour rather than the sequential re-resolution.
		local base = calcWith("Fireball", {})
		local baseTotal = base.TotalAvg
		local out = calcWith("Fireball", {
			{ "FireDamageConvertToCold", 100 },
			{ "ColdDamageConvertToFire", 50 },
			{ "ColdDamageConvertToLightning", 50 },
		})
		assert.is_true(approx(out.TotalAvg, baseTotal, 0.5), "leaky cycle conserves total")
	end)

	it("source contract: the conserving sequential re-resolution is gated on a trapped (ungrounded) type", function()
		local f = io.open("Modules/CalcOffence.lua", "r") or io.open("src/Modules/CalcOffence.lua", "r")
		assert.is_not_nil(f, "must read Modules/CalcOffence.lua")
		local src = f:read("*a"); f:close()
		assert.is_truthy(src:find("@leb-regression-guard:conversion-opposing-cycle-conservation", 1, true),
			"the guard marker must be present")
		assert.is_truthy(src:find("seq[to] = (seq[to] or 0) + rate * seq[from]", 1, true),
			"the game-faithful sequential convertBaseDamage step must be present")
		assert.is_truthy(src:find("if not grounded[t] and (fix[t] or 0) > 1e-9 then trapped = true", 1, true),
			"the re-resolution must be gated on base trapped in an ungrounded type (keeps acyclic/leaky byte-identical)")
	end)
end)
