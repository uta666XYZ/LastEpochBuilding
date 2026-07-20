-- @leb-regression-guard:minion-damage-effectiveness-datamined
-- Test: spec/System/TestBoneGolemRampageBaseData_spec.lua "Bone Golem Rampage carries the datamined prefab base (2 phys, eff 1.0)"
-- See REGRESSION_GUARDS.md "minion-damage-effectiveness-datamined".
-- Validation provenance is retained in maintainer notes.
describe("BoneGolemRampageBaseData", function()
	it("Bone Golem Rampage carries the datamined prefab base (2 phys, eff 1.0)", function()
		local ge = data.skills["Bone Golem Rampage"]
		assert.is_not_nil(ge, "Bone Golem Rampage must exist in data.skills")
		assert.are.equals(2, ge.stats.melee_base_physical_damage)
		assert.are.equals(1, ge.stats.damageEffectiveness)
	end)
end)
