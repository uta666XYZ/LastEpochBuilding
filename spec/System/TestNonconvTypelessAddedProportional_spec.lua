-- @leb-regression-guard:nonconv-typeless-added-proportional
-- Locks the rule that the TYPELESS / adaptive added pool ("+X Damage", no element) on a
-- NON-conversion skill is added to the hit ONCE, distributed PROPORTIONALLY over the skill's
-- non-zero intrinsic base types -- NOT added in FULL to every intrinsic type (which
-- double/triple-counts the pool for multi-intrinsic-type skills).
--
-- Game truth: DamageStats.buildDamageStats distributes typeless added proportionally over the
-- (post-conversion) base array (datamined game source); the
-- conversion path already mirrors this (@leb-regression-guard:adaptive-added-post-conversion-typing).
-- The non-conversion branch historically kept a "single pool" that was added per-type, so a
-- multi-intrinsic-type skill (Avalanche phys+cold, Disintegrate fire+light, Prism Shard
-- fire+cold+light) counted "+X Damage" once PER type. e.g. Smelter's Wrath (fire+phys) Forge
-- Guards inflated ~+40% (the double-counted typeless was the dominant base contributor).
--
-- SINGLE-intrinsic-type skills are BYTE-IDENTICAL (the only type's ratio is 1.0).
-- See REGRESSION_GUARDS.md "nonconv-typeless-added-proportional".

describe("NonconvTypelessAddedProportional", function()
	before_each(function()
		newBuild()
	end)

	local function calcWith(skill, mods)
		newBuild()
		build.skillsTab:SelSkill(1, skill)
		runCallback("OnFrame")
		local cfg = build.configTab.modList
		for _, m in ipairs(mods or {}) do
			cfg:NewMod(m[1], "BASE", m[2], "NonconvTypelessSpec")
		end
		build.buildFlag = true
		runCallback("OnFrame")
		return build.calcsTab.mainOutput
	end
	local function hit(out, t) return out[t .. "HitAverage"] or 0 end
	local function approx(a, b, tol) return math.abs(a - b) <= (tol or 0.5) end

	it("multi-intrinsic-type (Avalanche phys+cold): typeless adds ONCE, split proportionally (no double-count)", function()
		-- Avalanche has equal intrinsic base (spell_base_physical 40 + spell_base_cold 40) and
		-- no conversion -> a typeless "+40 Damage" must split 20/20, so the TOTAL contribution
		-- across both lanes equals the same 40 added as a SINGLE typed flat (not 80).
		local base = calcWith("Avalanche", {})
		local typeless = calcWith("Avalanche", { { "Damage", 40 } })
		local typedPhys = calcWith("Avalanche", { { "PhysicalDamage", 40 } })

		local typelessTotalDelta = (hit(typeless, "Physical") - hit(base, "Physical"))
			+ (hit(typeless, "Cold") - hit(base, "Cold"))
		local typedSingleDelta = hit(typedPhys, "Physical") - hit(base, "Physical")

		assert.is_true(typelessTotalDelta > 0, "typeless must contribute damage")
		-- The pool is added ONCE: total across lanes == one typed flat of the same size.
		assert.is_true(approx(typelessTotalDelta, typedSingleDelta, 1.0),
			string.format("typeless pool must be counted ONCE (got total delta %.2f, expected ~%.2f = a single typed 40); the old per-type path double-counted it (~2x)",
				typelessTotalDelta, typedSingleDelta))
		-- And it actually splits across BOTH lanes (proportional), not all-to-one.
		assert.is_true(hit(typeless, "Physical") > hit(base, "Physical") + 0.5
			and hit(typeless, "Cold") > hit(base, "Cold") + 0.5,
			"both intrinsic lanes must receive a proportional share")
	end)

	it("single-intrinsic-type (Fireball fire): typeless rides the one type 100% (BYTE-IDENTICAL)", function()
		-- Single intrinsic type -> ratio 1.0 -> the typeless lands fully on Fire, identical to a
		-- typed Fire flat of the same size. This is the byte-identical safety property.
		local base = calcWith("Fireball", {})
		local typeless = calcWith("Fireball", { { "Damage", 40 } })
		local typedFire = calcWith("Fireball", { { "FireDamage", 40 } })
		assert.is_true(approx(hit(typeless, "Fire") - hit(base, "Fire"),
			hit(typedFire, "Fire") - hit(base, "Fire"), 0.5),
			"single-type: typeless 40 must equal a typed Fire 40 (100% to the one type)")
		assert.are.equals(0, hit(typeless, "Cold"), "no other intrinsic type -> no leak")
	end)

	it("source contract: non-conversion branch distributes by intrinsic-base ratio", function()
		local f = io.open("Modules/CalcOffence.lua", "r") or io.open("src/Modules/CalcOffence.lua", "r")
		assert.is_not_nil(f, "must read Modules/CalcOffence.lua")
		local src = f:read("*a"); f:close()
		assert.is_truthy(src:find("@leb-regression-guard:nonconv-typeless-added-proportional", 1, true),
			"the guard marker must be present")
		assert.is_truthy(src:find("nonConvIntrinsicTotal", 1, true),
			"the non-conversion branch must compute an intrinsic-base total for proportional distribution")
		assert.is_truthy(src:find("genericAdded * ((sv > 0 and sv or 0) / nonConvIntrinsicTotal)", 1, true),
			"the typeless pool must be distributed by intrinsic-base ratio (single-type ratio 1.0 = byte-identical)")
	end)
end)
