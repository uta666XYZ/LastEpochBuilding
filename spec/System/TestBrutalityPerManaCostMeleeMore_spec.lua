-- @leb-regression-guard:brutality-per-manacost-melee-more
-- See REGRESSION_GUARDS.md "brutality-per-manacost-melee-more".
-- Validation provenance is retained in maintainer notes.

describe("BrutalityPerManaCostMeleeMore", function()
	before_each(function()
		newBuild()
	end)

	-- Select a skill, inject config BASE mods, recompute, return mainOutput.
	-- "ManaCost" BASE adds to the skill's resolved Mana cost (output.ManaCost);
	-- "Brutality" BASE is a direct attribute grant (output.Brutality).
	local function calcWith(skill, mods)
		newBuild()
		build.skillsTab:SelSkill(1, skill)
		runCallback("OnFrame")
		local cfg = build.configTab.modList
		for _, m in ipairs(mods or {}) do
			cfg:NewMod(m[1], "BASE", m[2], "BrutalityMeleeMoreSpec")
		end
		build.buildFlag = true
		runCallback("OnFrame")
		return build.calcsTab.mainOutput
	end
	local function ah(o) return o.AverageHit or 0 end
	local function approx(a, b, tol) return math.abs(a - b) <= (tol or 0.01) end

	it("magnitude: Brutality melee-MORE = 1 + 0.02*Brut*min(ManaCost,20)", function()
		-- Brutality fixed at 100; the ONLY difference is the Mana cost, so the ratio is
		-- purely the per-mana-cost MORE. MC 25 -> capped 20 -> 1 + 0.02*100*20 = 1.40.
		local mc0  = calcWith("Vengeance", { { "ManaCost", 0 },  { "Brutality", 100 } })
		local mc25 = calcWith("Vengeance", { { "ManaCost", 25 }, { "Brutality", 100 } })
		assert.is_true(ah(mc0) > 0, "synthetic Vengeance must produce a non-zero hit")
		assert.is_true(approx(ah(mc25) / ah(mc0), 1.40, 0.01),
			"MC25/MC0 ratio must equal the 1.40 Brutality melee-MORE (got " .. (ah(mc25) / ah(mc0)) .. ")")
	end)

	it("cap: Mana cost is capped at 20 (MC 100 == MC 25)", function()
		local mc25  = calcWith("Vengeance", { { "ManaCost", 25 },  { "Brutality", 100 } })
		local mc100 = calcWith("Vengeance", { { "ManaCost", 100 }, { "Brutality", 100 } })
		assert.is_true(approx(ah(mc100), ah(mc25), 0.0005),
			"MC above 20 must NOT increase the MORE (cap 20)")
	end)

	it("sub-cap: scales linearly with Mana cost below the cap (MC 15 -> 1.30)", function()
		local mc0  = calcWith("Vengeance", { { "ManaCost", 0 },  { "Brutality", 100 } })
		local mc15 = calcWith("Vengeance", { { "ManaCost", 15 }, { "Brutality", 100 } })
		assert.is_true(approx(ah(mc15) / ah(mc0), 1.30, 0.01),
			"MC15/MC0 ratio must equal 1 + 0.02*100*15 = 1.30 (got " .. (ah(mc15) / ah(mc0)) .. ")")
	end)

	it("scope: a SPELL skill is NOT affected (melee keyword only)", function()
		-- Fireball is a spell; the Brutality melee-MORE (ModFlag.Melee) must not touch it,
		-- so varying the Mana cost leaves its hit unchanged even with Brutality present.
		local mc0  = calcWith("Fireball", { { "ManaCost", 0 },  { "Brutality", 100 } })
		local mc25 = calcWith("Fireball", { { "ManaCost", 25 }, { "Brutality", 100 } })
		assert.is_true(ah(mc0) > 0, "Fireball must produce a non-zero hit")
		assert.is_true(approx(ah(mc25), ah(mc0), 0.0005),
			"a spell's hit must not change with Mana cost (the MORE is melee-only)")
	end)

	it("requires Brutality: with Brutality 0 there is no MORE (MC 25 == MC 0)", function()
		local mc0  = calcWith("Vengeance", { { "ManaCost", 0 } })
		local mc25 = calcWith("Vengeance", { { "ManaCost", 25 } })
		assert.is_true(approx(ah(mc25), ah(mc0), 0.0005),
			"with no Brutality the Mana cost must not change melee damage")
	end)
end)
