-- @leb-regression-guard:total-dot-dps-row
-- User-requested (2026-06-09, PoB parity): add a "Total DoT DPS" row to the
-- upper stat panel. PoB shows "Best Ignite/Bleed DPS" (max of a single source)
-- because PoE ailments are non-stacking; LE ailments STACK, so the LE-correct
-- aggregation is a TOTAL (sum), which LEB already computes per-ailment via
-- calcs.aggregateMainSkillAilment (maxStacks-clamped). The new row is backed by
-- output.MainSkillDotDPS = sum(main-skill damaging ailments) + (the skill's own
-- DoT when skillFlags.dot, since output.TotalDPS then IS the DoT). "DoT" is
-- LE-native vocabulary (AT_DoT / StatsPanel "Damage Over Time"), not PoE-only.
-- Display-only NEW output key (snapshot-safe, like the sibling MainSkill<Ailment>DPS).
-- Source-contract spec (mirrors the sibling display-stat specs). See
-- REGRESSION_GUARDS.md "total-dot-dps-row" and
-- wiki concepts/le-dot-vs-ailment-and-stacking.

describe("TotalDotDPSRow", function()
	local function readFile(path)
		local f = io.open(path, "r")
		if not f then return nil end
		local s = f:read("*a"); f:close()
		return s
	end

	local calcsSrc, buildSrc
	setup(function()
		calcsSrc = readFile("Modules/Calcs.lua")
		buildSrc = readFile("Modules/Build.lua")
		assert.is_not_nil(calcsSrc, "must read Modules/Calcs.lua")
		assert.is_not_nil(buildSrc, "must read Modules/Build.lua")
	end)

	it("carries the total-dot-dps-row guard marker in both files", function()
		assert.is_truthy(calcsSrc:find("@leb%-regression%-guard:total%-dot%-dps%-row"),
			"Calcs.lua must carry the total-dot-dps-row guard marker")
		assert.is_truthy(buildSrc:find("@leb%-regression%-guard:total%-dot%-dps%-row"),
			"Build.lua must carry the total-dot-dps-row guard marker")
	end)

	it("Calcs.lua computes output.MainSkillDotDPS = ailment total + skill-DoT", function()
		assert.is_truthy(calcsSrc:find("output.MainSkillDotDPS = mainDotTotal", 1, true),
			"must assign output.MainSkillDotDPS")
		-- TOTAL (sum), not PoB "Best"/max: built from mainAilmentTotal (the per-ailment sum)
		assert.is_truthy(calcsSrc:find("mainDotTotal = mainAilmentTotal", 1, true),
			"MainSkillDotDPS must be built from the summed mainAilmentTotal (LE ailments stack)")
		-- plus the skill's own DoT when it is itself a DoT skill
		assert.is_truthy(calcsSrc:find("mainSkillIsDot", 1, true),
			"must add the skill's own DoT when skillFlags.dot")
		assert.is_truthy(calcsSrc:find("mainSkill.skillFlags.dot", 1, true) or calcsSrc:find("skillFlags and mainSkill.skillFlags.dot", 1, true),
			"mainSkillIsDot must read skillFlags.dot")
	end)

	it("must NOT use PoB 'Best'/max ailment semantics (LE ailments stack)", function()
		-- Guard against a regression that copies PoB's non-stacking 'Best Ignite' max.
		assert.is_falsy(calcsSrc:find("Best Ignite", 1, true), "must not introduce a PoB 'Best Ignite' row")
		assert.is_falsy(buildSrc:find("Best DoT", 1, true), "must not introduce a 'Best DoT' row")
	end)

	it("Build.lua defines a 'Total DoT DPS' row backed by MainSkillDotDPS", function()
		assert.is_truthy(buildSrc:find('stat = "MainSkillDotDPS", label = "Total DoT DPS"', 1, true),
			"must define the Total DoT DPS display row backed by MainSkillDotDPS")
	end)

	it("Total DoT DPS row hides redundant single-source cases (condFunc)", function()
		-- The row must hide when it merely duplicates Hit DPS or a single ailment row.
		assert.is_truthy(buildSrc:find("v == (o.TotalDPS or 0) then return false", 1, true),
			"condFunc must hide when it duplicates Hit DPS")
		assert.is_truthy(buildSrc:find("MainSkillIgniteDPS", 1, true) and buildSrc:find("v > mx + 0.001", 1, true),
			"condFunc must hide single-ailment cases (show only when aggregate exceeds the largest single source)")
	end)

	it("Total DoT DPS row is placed before the per-skill roll-up (MainSkillWithAilmentsDPS)", function()
		-- The roll-up's label was renamed "Total DPS inc. Ailments" -> "Combined DPS"
		-- (combined-dps-row-label guard); match the stat key, which is stable.
		local dotAt = buildSrc:find('stat = "MainSkillDotDPS"', 1, true)
		local incAt = buildSrc:find('stat = "MainSkillWithAilmentsDPS"', 1, true)
		assert.is_not_nil(dotAt); assert.is_not_nil(incAt)
		assert.is_true(dotAt < incAt, "Total DoT DPS must appear above the MainSkillWithAilmentsDPS roll-up")
	end)
end)
