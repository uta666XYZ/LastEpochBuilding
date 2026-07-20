-- @leb-regression-guard:adaptive-added-post-conversion-typing
-- @leb-regression-guard:adaptive-added-distributes-over-full-postconv-base
-- as @leb-regression-guard:conversion-base-only-scope requires.
-- See REGRESSION_GUARDS.md "adaptive-added-post-conversion-typing".
-- Validation provenance is retained in maintainer notes.

describe("AdaptiveAddedPostConversionTyping", function()
	before_each(function()
		newBuild()
	end)

	-- Select a skill, inject config (non-weapon) BASE mods, recompute, return output.
	-- A mod is { name, value } or { name, value, tag } where an optional tag table makes
	-- the mod SKILL-SCOPED (e.g. { type = "SkillName", skillName = "Fireball" }). A
	-- skill-scoped conversion converts the skill's intrinsic BASE only -- typed added
	-- keeps its type; an UNTAGGED conversion is player-global and also converts typed added
	-- (@leb-regression-guard:global-conversion-converts-added-offtype).
	local function calcWith(skill, mods)
		newBuild()
		build.skillsTab:SelSkill(1, skill)
		runCallback("OnFrame")
		local cfg = build.configTab.modList
		for _, m in ipairs(mods or {}) do
			if m[3] then
				cfg:NewMod(m[1], "BASE", m[2], "AdaptiveTypingSpec", 0, 0, m[3])
			else
				cfg:NewMod(m[1], "BASE", m[2], "AdaptiveTypingSpec")
			end
		end
		build.buildFlag = true
		runCallback("OnFrame")
		return build.calcsTab.mainOutput
	end
	-- Skill-scoped Fire->Cold tag, so the conversion is base-only (typed added keeps type),
	-- matching how real skill-base conversions are tagged (PassiveTree:ProcessStats tags
	-- every tree-node conversion with its owning skill: Mana Strike, Avalanche, Heartseeker).
	local fireballScoped = { type = "SkillName", skillName = "Fireball" }
	local function hit(out, t) return out[t .. "HitAverage"] or 0 end
	local function approx(a, b, tol) return math.abs(a - b) <= (tol or 0.5) end

	it("typeless/adaptive added rides the POST-conversion type (no pre-conversion residue)", function()
		-- Fireball is intrinsic Fire; convert it 100% Fire -> Cold (skill-scoped, base-only).
		local base = calcWith("Fireball", { { "FireDamageConvertToCold", 100, fireballScoped } })
		local baseFire, baseCold = hit(base, "Fire"), hit(base, "Cold")
		assert.are.equals(0, baseFire, "Fire must be fully converted out")
		assert.is_true(baseCold > 0, "Cold must receive the converted Fireball base")

		-- Add a NON-weapon typeless adaptive flat (config "Damage" BASE, no damage type).
		local out = calcWith("Fireball", { { "FireDamageConvertToCold", 100, fireballScoped }, { "Damage", 40 } })
		assert.are.equals(0, hit(out, "Fire"),
			"the adaptive must NOT leave a fake Fire residue on the converted-away lane (the bug)")
		assert.is_true(hit(out, "Cold") > baseCold,
			"the adaptive must land on the POST-conversion type (Cold)")
		-- Magnitude cross-check: the adaptive 40 landing on Cold equals the same 40 added
		-- as a TYPED flat (40 x effectiveness) -- it is the correct post-conversion type,
		-- not a discarded/duplicated amount. The conversion is SKILL-SCOPED so the typed Fire
		-- flat keeps its type (it would convert under a player-global conversion instead --
		-- see @leb-regression-guard:global-conversion-converts-added-offtype).
		local typedFire = calcWith("Fireball", { { "FireDamageConvertToCold", 100, fireballScoped }, { "FireDamage", 40 } })
		assert.is_true(approx(hit(out, "Cold") - baseCold, hit(typedFire, "Fire"), 0.5),
			"adaptive Cold delta must equal the same 40 added as a typed flat (40 x effectiveness)")
	end)

	it("TYPED non-weapon added KEEPS its type across a SKILL-SCOPED conversion (base-only)", function()
		-- A typed Fire added flat on a SKILL-SCOPED Fire->Cold skill must stay Fire
		-- (conversion-base-only-scope: a skill-base conversion converts the intrinsic base
		-- only; non-weapon typed added never converts). A player-GLOBAL conversion is the
		-- opposite (it converts the typed added too) -- locked separately in
		-- spec/System/TestGlobalConversionAddedOffType_spec.lua.
		local base = calcWith("Fireball", { { "FireDamageConvertToCold", 100, fireballScoped } })
		local out = calcWith("Fireball", { { "FireDamageConvertToCold", 100, fireballScoped }, { "FireDamage", 40 } })
		assert.is_true(hit(out, "Fire") > 0,
			"typed Fire added must keep its type even when the skill base converts away")
		assert.is_true(hit(out, "Fire") > hit(base, "Fire"),
			"the typed Fire added is the source of the Fire residue (not the converted base)")
	end)

	it("partial conversion splits the adaptive proportionally over the post-conversion base", function()
		-- 50% Fire->Cold => post-conversion base is 50% Fire / 50% Cold => the adaptive
		-- splits 50/50 and (with equal default inc/more/eff) Fire == Cold.
		local out = calcWith("Fireball", { { "FireDamageConvertToCold", 50 }, { "Damage", 40 } })
		assert.is_true(hit(out, "Fire") > 0 and hit(out, "Cold") > 0,
			"both retained post-conversion types must carry damage")
		assert.is_true(approx(hit(out, "Fire"), hit(out, "Cold"), 0.5),
			"adaptive splits proportionally; Fire and Cold are symmetric at 50% conversion")
	end)

	it("typeless adaptive is SHARED with a type-preserved added lane (full post-conv base, not skill-base-only)", function()
		-- Fireball converts its OWN base 100% Fire->Cold. A typed +Lightning added is
		-- type-preserved (Lightning does NOT convert). The typeless adaptive ("Damage")
		-- must split proportionally over the FULL post-conversion base = the converted
		-- Cold base PLUS the preserved Lightning lane -- NOT 100% onto Cold. Pre-fix the
		-- distribution weight was the skill's converted base ONLY (fix*retention), so the
		-- preserved lane got ZERO adaptive share -- the WardingMySchitzer Swarmblade phys
		-- undershoot (in-game 27.26% phys vs LEB 18.64% with the skill-base-only weight,
		-- 25.41% with this fix). @leb-regression-guard:adaptive-added-distributes-over-full-postconv-base
		local preserved = calcWith("Fireball", { { "FireDamageConvertToCold", 100 }, { "LightningDamage", 40 } })
		local out = calcWith("Fireball", { { "FireDamageConvertToCold", 100 }, { "LightningDamage", 40 }, { "Damage", 40 } })
		assert.is_true(hit(out, "Lightning") > hit(preserved, "Lightning") + 0.5,
			"the type-preserved Lightning lane MUST receive its proportional share of the typeless adaptive (the fix)")
		assert.is_true(hit(out, "Cold") > hit(preserved, "Cold"),
			"the converted Cold lane also gains a share (split, not all-to-one-lane)")
		assert.are.equals(0, hit(out, "Fire"),
			"Fire is fully converted out -- no residue on the converted-away lane")
	end)

	it("source contract: the adaptive distribution weight includes addedBasePart (full post-conv base)", function()
		local f = io.open("Modules/CalcOffence.lua", "r") or io.open("src/Modules/CalcOffence.lua", "r")
		assert.is_not_nil(f, "must read Modules/CalcOffence.lua")
		local src = f:read("*a"); f:close()
		-- The distribution weight is the post-conversion retained skill base
		-- (retainedIntrinsic[t] = fix*retention, or the conserving sequential re-resolution
		-- for a pure cycle -- see @leb-regression-guard:conversion-opposing-cycle-conservation)
		-- PLUS the type-preserved added (addedBasePart).
		assert.is_truthy(src:find("postBase[t] = (retainedIntrinsic[t] or 0) + (addedBasePart[t] or 0)", 1, true),
			"the adaptive distribution weight must be the retained intrinsic base PLUS addedBasePart (type-preserved added)")
		assert.is_truthy(src:find("@leb-regression-guard:adaptive-added-distributes-over-full-postconv-base", 1, true),
			"the full-postconv-base guard marker must be present")
	end)

	it("non-conversion build: adaptive applies on the natural type (unchanged pre-conversion path)", function()
		local base = calcWith("Fireball", {})
		local out = calcWith("Fireball", { { "Damage", 40 } })
		assert.is_true(hit(out, "Fire") > hit(base, "Fire"),
			"with no conversion the adaptive lands on Fireball's intrinsic Fire (byte-identical path)")
		assert.are.equals(0, hit(out, "Cold"),
			"no conversion -> no Cold at all")
	end)

	it("OFF-TYPE conversion (a type the skill does not source) does NOT defer the adaptive added", function()
		-- @leb-regression-guard:conversion-flag-requires-sourced-type
		-- Validation provenance is retained in maintainer notes.
		local voidOnly = calcWith("Fireball", { { "PhysicalDamageConvertToVoid", 100 }, { "VoidDamage", 40 } })
		local withGeneric = calcWith("Fireball", { { "PhysicalDamageConvertToVoid", 100 }, { "VoidDamage", 40 }, { "Damage", 40 } })
		assert.is_true(approx(hit(withGeneric, "Void"), hit(voidOnly, "Void"), 0.5),
			"the off-type conversion must not pull the typeless adaptive onto the Void lane")
		assert.is_true(hit(withGeneric, "Fire") > hit(voidOnly, "Fire") + 0.5,
			"the typeless adaptive must ride Fireball's sourced Fire (pre-conversion path)")
	end)
end)
