-- @leb-regression-guard:whole-attack-conversion
-- Locks the rule that an ability whose damage conversion is ABILITY-INTRINSIC (hardcoded
-- in a mutator, i.e. LE's `convertAllDamageOfType` = whole attack slot: weapon base + ALL
-- typed added + intrinsic) converts the typed ADDED damage too -- not just the intrinsic
-- base. Such abilities carry `wholeAttackConversion` (skills.json). Hail of Arrows is the
-- grounded case: exvol8-12 "physical -> fire" is set in HailOfArrowsMutator.Mutate()
-- (datamined game source), a whole-slot convert, but LEB parses it as a
-- SkillId-tagged (skill-scoped) conversion which -- absent this flag -- would convert only
-- the intrinsic base and leave `addedBasePart[Physical]` type-preserved (phys over-read +
-- fire under; project_amhoa_hailofarrows_fire_light_under).
--
-- The DISCRIMINATOR (mirrors global-conversion-converts-added-offtype): the SAME
-- skill-scoped conversion behaves differently by ability --
--   * Hail of Arrows (wholeAttackConversion=true): the skill's own phys->fire converts the
--     typed added physical too (whole attack).
--   * Fireball (no flag): a skill-scoped phys->fire converts the intrinsic base only; the
--     typed added physical KEEPS its type (base-only, the default for STAT-granted
--     conversions like Swarmblade / Mana Strike -- no regression there).
--
-- Fix #1 INVARIANT (adaptive-added-base-derived-types-only): populating globalConversionTable
-- from the skill's OWN conversion must NOT make the adaptive "+Bow Damage" pool treat HoA as
-- a player-global conversion (which would re-leak the pool onto independently-added lightning).
-- The base-derived gate stays ON for a wholeAttackConversion skill -- verified in-corpus by
-- AmHoA lightning DmgBase staying 58.5 (unchanged) while fire goes 205.36 -> 210.0.
-- See REGRESSION_GUARDS.md "whole-attack-conversion".

describe("WholeAttackConversion", function()
	before_each(function()
		newBuild()
	end)

	local function calcWith(skill, mods)
		newBuild()
		build.skillsTab:SelSkill(1, skill)
		runCallback("OnFrame")
		local cfg = build.configTab.modList
		for _, m in ipairs(mods or {}) do
			if m[3] then
				cfg:NewMod(m[1], "BASE", m[2], "WholeAttackSpec", 0, 0, m[3])
			else
				cfg:NewMod(m[1], "BASE", m[2], "WholeAttackSpec")
			end
		end
		build.buildFlag = true
		runCallback("OnFrame")
		return build.calcsTab.mainOutput
	end
	local function hit(out, t) return out[t .. "HitAverage"] or 0 end
	local hoaScoped      = { type = "SkillName", skillName = "Hail of Arrows" }
	local fireballScoped = { type = "SkillName", skillName = "Fireball" }

	it("wholeAttackConversion (Hail of Arrows): its OWN skill-scoped phys->fire converts typed ADDED physical", function()
		local noConv = calcWith("HailOfArrows", { { "PhysicalDamage", 40 } })
		assert.is_true(hit(noConv, "Physical") > 0, "sanity: typed physical added shows as Physical with no conversion")

		local out = calcWith("HailOfArrows", { { "PhysicalDamageConvertToFire", 100, hoaScoped }, { "PhysicalDamage", 40 } })
		assert.are.equals(0, hit(out, "Physical"),
			"wholeAttackConversion: the skill-scoped phys->fire must convert the typed added physical (no phys residue)")
		assert.is_true(hit(out, "Fire") > hit(noConv, "Fire"),
			"the converted added physical must land on Fire")
	end)

	it("NON-wholeAttackConversion (Fireball): the SAME skill-scoped phys->fire LEAVES typed added (base-only)", function()
		-- Fireball has no intrinsic physical base, so a skill-scoped (base-only) phys->fire
		-- has nothing to convert and the typed added physical must keep its type.
		local out = calcWith("Fireball", { { "PhysicalDamageConvertToFire", 100, fireballScoped }, { "PhysicalDamage", 40 } })
		assert.is_true(hit(out, "Physical") > 0,
			"base-only default: a skill-scoped conversion must NOT convert the typed added (no whole-attack)")
	end)

	it("source contract: the flag is read and the base-derived gate excludes it (Fix #1 preserved)", function()
		local f = io.open("Modules/CalcOffence.lua", "r") or io.open("src/Modules/CalcOffence.lua", "r")
		assert.is_not_nil(f, "must read Modules/CalcOffence.lua")
		local src = f:read("*a"); f:close()
		assert.is_truthy(src:find("grantedEffect.wholeAttackConversion", 1, true),
			"CalcOffence must read the wholeAttackConversion flag")
		assert.is_truthy(src:find("@leb-regression-guard:whole-attack-conversion", 1, true),
			"the guard marker must be present")
		-- the base-derived gate must exclude a wholeAttackConversion skill (Fix #1 invariant)
		assert.is_truthy(src:find("not activeSkill.activeEffect.grantedEffect.wholeAttackConversion", 1, true),
			"the base-derived gate must keep ON for a wholeAttackConversion skill (else AmHoA lightning re-leaks)")
	end)

	it("data contract: Hail of Arrows carries wholeAttackConversion in skills.json", function()
		local f = io.open("Data/skills.json", "r") or io.open("src/Data/skills.json", "r")
		assert.is_not_nil(f, "must read Data/skills.json")
		local src = f:read("*a"); f:close()
		local hoa = src:match('"HailOfArrows"%s*:%s*{.-}')
		-- match up to the first close is unreliable for nested; just assert the flag appears
		-- within a reasonable window after the HailOfArrows key
		local at = src:find('"HailOfArrows"', 1, true)
		assert.is_not_nil(at, "HailOfArrows entry must exist")
		local window = src:sub(at, at + 400)
		assert.is_truthy(window:find('"wholeAttackConversion"%s*:%s*true'),
			"HailOfArrows must carry wholeAttackConversion:true")
	end)
end)
