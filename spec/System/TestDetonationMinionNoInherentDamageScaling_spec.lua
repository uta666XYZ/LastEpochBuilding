-- @leb-regression-guard:detonation-minion-no-inherent-damage-scaling
-- See REGRESSION_GUARDS.md "detonation-minion-no-inherent-damage-scaling".
-- Validation provenance is retained in maintainer notes.
describe("DetonationMinionNoInherentDamageScaling", function()
	before_each(function()
		newBuild()
	end)

	local function minionMoreDamage()
		local minion = build.calcsTab.mainEnv.minion
		assert.is_not_nil(minion, "expected env.minion")
		return minion.modDB:More(nil, "Damage")
	end

	it("Volatile Zombie detonation minion: NO inherent damage MORE at lv88 (level-MORE + ActorStats Damage both bypassed)", function()
		-- Ungated this minion would read 1.50 (level-MORE) x 1.20 (ActorStats Damage)
		-- = 1.80; the noInherentDamageScaling flag removes both.
		build.characterLevel = 88
		build.skillsTab:SelSkill(1, "SummonVolatileZombie")
		runCallback("OnFrame")
		assert.are.equals(1, round(minionMoreDamage(), 3))
	end)

	it("control: a normal minion (Thorn Totem) STILL gets the inherent level-MORE at lv88 (~x1.5)", function()
		-- proves the bypass is per-minion (flag-gated), not a global regression of
		-- the minion-level-more-scaling guard.
		build.characterLevel = 88
		build.skillsTab:SelSkill(1, "SummonThornTotem")
		runCallback("OnFrame")
		assert.are.equals(1.5, round(minionMoreDamage(), 3))
	end)
end)
