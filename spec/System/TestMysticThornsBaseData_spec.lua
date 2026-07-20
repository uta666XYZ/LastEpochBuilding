-- @leb-regression-guard:mystic-thorns-base-letools
-- See REGRESSION_GUARDS.md "mystic-thorns-base-letools".
-- Validation provenance is retained in maintainer notes.
describe("MysticThornsBaseData", function()
	it("ThornTotemAttack carries the LETools prefab base (20 phys, eff 1)", function()
		local ge = data.skills["ThornTotemAttack"]
		assert.is_not_nil(ge, "ThornTotemAttack must exist in data.skills")
		assert.are.equals(20, ge.stats.spell_base_physical_damage)
		assert.are.equals(1, ge.stats.damageEffectiveness)
	end)
end)
