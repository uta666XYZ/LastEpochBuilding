-- @leb-regression-guard: kuzons-fury-reforged-burning-dagger-chance
-- Locks parser / ModCache / CalcOffence / CalcSections wiring for the
-- 8-tier Kuzon's Fury Reforged affix (statOrderKey=961). Source:
--   "+(N)% chance to throw a Burning Dagger when you use a melee fire
--    attack and hit at least one enemy, doubled for Dancing Strikes
--    (up to 4 times per second)"
--
-- Game-file evidence (LE 1.4.6 dump.cs):
--   L77400  AbilityStatsMutatorManager.burningDaggerChanceOnMeleeFire
--           (the exact per-skill stat field; PascalCase'd verbatim ->
--            BurningDaggerChanceOnMeleeFire as the LEB stat name)
--   L35408-L35546 DancingStrikes1..4Mutator family + ability_keyed_array.json
--                 (4 player variants share abilityName="Dancing Strikes")
--
-- v1 wiring decisions:
--   A: stat = BurningDaggerChanceOnMeleeFire (dump.cs verbatim)
--   B: tier 7 outlier `{rounding:Integer}+(1-1.2)` deferred ({} emit)
--   C: Dancing Strikes skill-identity gate wired here (F5 pattern)
--   D: "(up to 4 times per second)" rate cap deferred (no LEB infra)
--
-- See REGRESSION_GUARDS.md "kuzons-fury-reforged-burning-dagger-chance"
-- and Obsidian "Kuzon's Fury Reforged 設計フォーク.md".

describe("KuzonsFuryReforged", function()

	local parserSrc, cacheSrc, calcSrc, secSrc
	setup(function()
		local f = io.open("Modules/ModParser.lua", "r")
		assert.is_not_nil(f, "must be able to open Modules/ModParser.lua")
		parserSrc = f:read("*a"):gsub("\r\n", "\n")
		f:close()

		local g = io.open("Data/ModCache.lua", "r")
		assert.is_not_nil(g, "must be able to open Data/ModCache.lua")
		cacheSrc = g:read("*a"):gsub("\r\n", "\n")
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

	it("parser keeps the @leb-regression-guard anchor", function()
		assert.is_truthy(
			string.find(parserSrc, "kuzons-fury-reforged-burning-dagger-chance", 1, true),
			"ModParser.lua must keep the @leb-regression-guard:kuzons-fury-reforged-burning-dagger-chance comment"
		)
	end)

	it("parser anchors tiers 0..6 emitting BurningDaggerChanceOnMeleeFire BASE with DancingStrikes mult=2 and RateLimit metadata", function()
		assert.is_truthy(string.find(parserSrc,
			'["^%+?([%d%.]+)%% chance to throw a burning dagger when you use a melee fire attack and hit at least one enemy, doubled for dancing strikes %(up to 4 times per second%)$"]', 1, true),
			"ModParser must register the tier 0..6 full-line specialModList anchor")
		-- Condition{DancingStrikes, mult=2}: doubles the chance value when
		-- Dancing Strikes is the active skill (F4 condition-tag-mult contract).
		assert.is_truthy(string.find(parserSrc,
			'{%s*type%s*=%s*"Condition",%s*var%s*=%s*"DancingStrikes",%s*mult%s*=%s*2%s*}'),
			"parser must include Condition{DancingStrikes, mult=2} on the emitted mod")
		-- RateLimit{limit=4, interval=1, var="BurningDaggerOnMeleeFire"}: game-file-
		-- authoritative metadata harvested from the static "(up to 4 times per second)"
		-- suffix. The tag has NO handler in ModStore.lua EvalMod (pure metadata) and
		-- LEB does NOT compute an equilibrium effective-procs/sec because the game
		-- exposes no such planner-visible stat (runtime PTT gate only; dump.cs
		-- L239352-L239378 + L33671-L33713). See guard "proc-rate-limit-metadata-v1".
		assert.is_truthy(string.find(parserSrc,
			'{%s*type%s*=%s*"RateLimit",%s*limit%s*=%s*4,%s*interval%s*=%s*1,%s*var%s*=%s*"BurningDaggerOnMeleeFire"%s*}'),
			"parser must include RateLimit{limit=4, interval=1, var=\"BurningDaggerOnMeleeFire\"} metadata tag")
	end)

	it("parser registers tier 7 outlier as deferred (no mod emission)", function()
		assert.is_truthy(string.find(parserSrc,
			'["^%+?1 chance to throw a burning dagger when you use a melee fire attack and hit at least one enemy, doubled for dancing strikes %(up to 4 times per second%)$"] = function() return {} end', 1, true),
			"ModParser must register the tier 7 deferred anchor returning {}")
	end)

	it("ModCache carries proper BurningDaggerChanceOnMeleeFire BASE entries with RateLimit metadata", function()
		for _, v in ipairs({ 8, 15, 22, 29, 37, 55, 60, 65 }) do
			local needle = 'c%["%+' .. v .. '%% chance to throw a Burning Dagger when you use a melee fire attack and hit at least one enemy, doubled for Dancing Strikes %(up to 4 times per second%)"%]={{%[1%]={%[1%]={mult=2,type="Condition",var="DancingStrikes"},%[2%]={interval=1,limit=4,type="RateLimit",var="BurningDaggerOnMeleeFire"},flags=0,keywordFlags=0,name="BurningDaggerChanceOnMeleeFire",type="BASE",value=' .. v .. '}},nil}'
			assert.is_truthy(string.find(cacheSrc, needle),
				"ModCache.lua must carry +" .. v .. "% Kuzon entry with the BurningDaggerChanceOnMeleeFire BASE mod + RateLimit metadata tag")
		end
	end)

	it("ModCache carries the tier 7 outlier as deferred-empty", function()
		assert.is_truthy(string.find(cacheSrc,
			'c%["%+1 chance to throw a Burning Dagger when you use a melee fire attack and hit at least one enemy, doubled for Dancing Strikes %(up to 4 times per second%)"%]={{},""}',
			1),
			"ModCache.lua must carry the tier-7 outlier as a deferred-empty entry")
	end)

	it("CalcOffence keeps the @leb-regression-guard anchor", function()
		assert.is_truthy(
			string.find(calcSrc, "kuzons-fury-reforged-burning-dagger-chance", 1, true),
			"CalcOffence.lua must keep the @leb-regression-guard:kuzons-fury-reforged-burning-dagger-chance comment"
		)
	end)

	it("CalcOffence sets the DancingStrikes skill-identity condition", function()
		assert.is_truthy(string.find(calcSrc,
			'local dancingStrikesSkills%s*=%s*{%s*%[%"Dancing Strikes%"%]%s*=%s*true,%s*}'),
			"CalcOffence must declare the dancingStrikesSkills allowlist")
		assert.is_truthy(string.find(calcSrc,
			'skillCfg%.skillCond%["DancingStrikes"%]%s*=%s*dancingStrikesSkills%[activeGrantedName%]%s*or%s*false'),
			"CalcOffence must set skillCfg.skillCond[\"DancingStrikes\"] from the allowlist")
	end)

	it("CalcOffence surfaces BurningDaggerChanceOnMeleeFire on output", function()
		assert.is_truthy(string.find(calcSrc,
			'output%.BurningDaggerChanceOnMeleeFire%s*=%s*skillModList:Sum%("BASE",%s*skillCfg,%s*"BurningDaggerChanceOnMeleeFire"%)'),
			"CalcOffence must sum BurningDaggerChanceOnMeleeFire BASE on the active skill")
	end)

	it("CalcSections registers the Burning Dagger Throw Chance row", function()
		assert.is_truthy(
			string.find(secSrc, "kuzons-fury-reforged-burning-dagger-chance", 1, true),
			"CalcSections.lua must keep the @leb-regression-guard:kuzons-fury-reforged-burning-dagger-chance comment"
		)
		assert.is_truthy(string.find(secSrc,
			'label%s*=%s*"Burning Dagger Throw Chance",%s*haveOutput%s*=%s*"BurningDaggerChanceOnMeleeFire"'),
			"CalcSections must register the Burning Dagger Throw Chance row gated on the output stat")
	end)
end)
