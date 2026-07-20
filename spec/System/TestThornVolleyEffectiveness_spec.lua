-- @leb-regression-guard:thornvolley-effectiveness-datamined
-- any value != the datamined 1.0). See REGRESSION_GUARDS.md "thornvolley-effectiveness-datamined".
-- Validation provenance is retained in maintainer notes.

describe("ThornVolleyEffectiveness #data contract", function()
	it("data.skills.ThornVolley.damageEffectiveness == 1.0 (datamined addedDamageScaling)", function()
		newBuild()
		local ge = build.data.skills["ThornVolley"]
		assert.is_table(ge, "ThornVolley must exist in data.skills")
		assert.is_table(ge.stats, "ThornVolley must carry a stats block")
		assert.are.equals(1, ge.stats.damageEffectiveness,
			"Thorn Volley damageEffectiveness must be the datamined 1.0, not the stale legacy 0.6")
	end)

	it("base physical damage is 20 (the buffed value the 1.0 effectiveness matches)", function()
		newBuild()
		local ge = build.data.skills["ThornVolley"]
		assert.are.equals(20, ge.stats.spell_base_physical_damage,
			"base 20 x 0.05 = 1.0 effectiveness (sanity heuristic; serialized value is authority)")
	end)
end)
