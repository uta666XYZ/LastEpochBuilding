-- @leb-regression-guard: proc-rate-limit-metadata-v1
-- Locks the game-file-conforming wiring for ProcTimeTracker-style
-- "(up to N times per M seconds)" rate-limit clauses on chance-to-proc
-- affixes. Source: LE 1.4.6 dump.cs.
--
--   L239352-L239378  ProcTimeTracker (rolling-window timestamp buffer;
--                    fields: int limit / float interval / float[] recentProcTimes;
--                    methods: CanProc / TryProc / ChangeLimit / ChangeInterval /
--                    ClearRecentProcs). Cap enforced at runtime only.
--   L33671-L33713    BurningDaggerMutator.burningDaggerOnMeleeFirePTT
--                    initialised in Awake() with (limit=4, interval=1.0);
--                    gate checked in OnDetailedHit() after the chance roll.
--
-- The game exposes NO planner-visible effective-rate stat: no
-- EffectiveChance / RateCappedChance property on the character mutator,
-- no tooltip helper that anticipates the cap, no character sheet field.
-- The clause is a static suffix in localisation
-- (Property_Ability_burningDagger_3_Name carries "(up to 4 times per second)"
-- verbatim). LEB therefore stores the (limit, interval) pair as passive
-- metadata only and does NOT compute equilibrium procs/sec -- doing so
-- would fabricate a stat the game itself does not surface.
--
-- v1 contract:
--   A: Parser emits Condition{DancingStrikes, mult=2} + RateLimit{limit, interval, var}
--   B: RateLimit has no handler in ModStore.lua EvalMod (pure metadata)
--   C: Distinct from existing `Limit` tag (ModStore.lua L560) whose
--      semantics are `value = min(value, tag.limit)` -- reuse would have
--      clamped 5%-70% chances to 4
--   D: CalcOffence surfaces two scalar outputs (RateLimit, RateInterval)
--      so future (N, M != 1) affixes generalise without re-shaping
--   E: CalcSections row is informational only ("N per M sec")
--
-- See REGRESSION_GUARDS.md "proc-rate-limit-metadata-v1".

describe("ProcRateLimitMetadata", function()

	local parserSrc, storeSrc, calcSrc, secSrc
	setup(function()
		local f = io.open("Modules/ModParser.lua", "r")
		assert.is_not_nil(f, "must be able to open Modules/ModParser.lua")
		parserSrc = f:read("*a"):gsub("\r\n", "\n")
		f:close()

		local g = io.open("Classes/ModStore.lua", "r")
		assert.is_not_nil(g, "must be able to open Classes/ModStore.lua")
		storeSrc = g:read("*a"):gsub("\r\n", "\n")
		g:close()

		local h = io.open("Modules/CalcOffence.lua", "r")
		assert.is_not_nil(h, "must be able to open Modules/CalcOffence.lua")
		calcSrc = h:read("*a"):gsub("\r\n", "\n")
		h:close()

		local s = io.open("Modules/CalcSections.lua", "r")
		assert.is_not_nil(s, "must be able to open Modules/CalcSections.lua")
		secSrc = s:read("*a"):gsub("\r\n", "\n")
		s:close()
	end)

	it("parser anchor carries the @leb-regression-guard tag", function()
		assert.is_truthy(
			string.find(parserSrc, "proc-rate-limit-metadata-v1", 1, true),
			"ModParser.lua must keep the @leb-regression-guard:proc-rate-limit-metadata-v1 comment near the harvester"
		)
	end)

	it("parser emits a RateLimit metadata tag with limit / interval / var", function()
		-- The tag MUST carry all three fields. Without `interval` the (N, M != 1)
		-- generalisation collapses; without `var` future PTTs can't be told apart.
		assert.is_truthy(string.find(parserSrc,
			'{%s*type%s*=%s*"RateLimit",%s*limit%s*=%s*4,%s*interval%s*=%s*1,%s*var%s*=%s*"BurningDaggerOnMeleeFire"%s*}'),
			"parser must emit RateLimit{limit=4, interval=1, var=\"BurningDaggerOnMeleeFire\"}")
	end)

	it("ModStore.lua does NOT add a RateLimit handler (pure metadata)", function()
		-- The whole point of RateLimit is to be a no-op for value sums.
		-- If a handler appears here, the value contract breaks: chance% may
		-- get silently clamped / mutated and LEB would diverge from the game.
		assert.is_falsy(
			string.find(storeSrc, 'tag.type%s*==%s*"RateLimit"'),
			"ModStore.lua must NOT have a RateLimit handler in EvalMod -- the tag is passive metadata only")
	end)

	it("ModStore.lua keeps the existing `Limit` tag (value clamp) distinct from RateLimit", function()
		-- Safety check: ensure we didn't accidentally rename or remove
		-- the existing Limit tag handler whose semantics are
		-- `value = min(value, tag.limit)`. Reusing that name would clamp
		-- chance percentages to 4.
		assert.is_truthy(
			string.find(storeSrc, 'elseif tag.type == "Limit" then'),
			"ModStore.lua must keep the existing `Limit` tag handler distinct from `RateLimit`")
	end)

	it("CalcOffence harvests RateLimit into two scalar outputs", function()
		assert.is_truthy(
			string.find(calcSrc, "proc-rate-limit-metadata-v1", 1, true),
			"CalcOffence.lua must keep the @leb-regression-guard:proc-rate-limit-metadata-v1 comment"
		)
		-- The harvester reads tag.limit / tag.interval and writes two outputs.
		-- Two scalars (not a composite table) so CalcSections can format with
		-- a normal `{N:output:STAT}` substitution and future (N, M != 1)
		-- affixes share the same shape.
		assert.is_truthy(string.find(calcSrc,
			'output%.BurningDaggerChanceOnMeleeFire_RateLimit%s*=%s*tag%.limit'),
			"CalcOffence must write tag.limit -> output.BurningDaggerChanceOnMeleeFire_RateLimit")
		assert.is_truthy(string.find(calcSrc,
			'output%.BurningDaggerChanceOnMeleeFire_RateInterval%s*=%s*tag%.interval'),
			"CalcOffence must write tag.interval -> output.BurningDaggerChanceOnMeleeFire_RateInterval")
		-- Guard: var match is required to avoid cross-talk if a future
		-- anchor stamps a RateLimit tag with a different `var`.
		assert.is_truthy(string.find(calcSrc,
			'tag%.var%s*==%s*"BurningDaggerOnMeleeFire"'),
			"CalcOffence must match tag.var to avoid cross-talk between different PTTs")
	end)

	it("CalcOffence does NOT compute an effective-procs/sec stat", function()
		-- Game-conforming scope: the game exposes no such stat, so LEB
		-- must not fabricate one. Specifically guard against accidental
		-- introduction of an "EffectiveProcs" or "RateCapped" output
		-- under the BurningDaggerChanceOnMeleeFire family.
		assert.is_falsy(
			string.find(calcSrc, "BurningDaggerChanceOnMeleeFire_EffectiveProcsPerSec"),
			"LEB must not compute equilibrium effective-procs/sec (game-conforming v1)")
		assert.is_falsy(
			string.find(calcSrc, "BurningDaggerChanceOnMeleeFire_RateCapped"),
			"LEB must not compute a rate-capped chance stat (game-conforming v1)")
	end)

	it("CalcSections renders the rate-limit row as informational only", function()
		assert.is_truthy(
			string.find(secSrc, "proc-rate-limit-metadata-v1", 1, true),
			"CalcSections.lua must keep the @leb-regression-guard:proc-rate-limit-metadata-v1 comment"
		)
		assert.is_truthy(string.find(secSrc,
			'label%s*=%s*"Burning Dagger Rate Limit",%s*haveOutput%s*=%s*"BurningDaggerChanceOnMeleeFire_RateLimit"'),
			"CalcSections must register the Burning Dagger Rate Limit row gated on the metadata output")
		-- The format must combine both outputs in "N per M sec" shape so
		-- (N, M != 1) affixes display correctly without re-shaping.
		assert.is_truthy(string.find(secSrc,
			'{0:output:BurningDaggerChanceOnMeleeFire_RateLimit}%s+per%s+{1:output:BurningDaggerChanceOnMeleeFire_RateInterval}%s+sec'),
			"format must read both outputs as \"N per M sec\"")
	end)

end)
