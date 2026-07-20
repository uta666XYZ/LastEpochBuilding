-- @leb-regression-guard:minion-level-more-scaling
-- See REGRESSION_GUARDS.md "minion-level-more-scaling".
-- Validation provenance is retained in maintainer notes.
describe("MinionLevelMoreScaling", function()
	before_each(function()
		newBuild()
	end)

	local function minionMoreDamage()
		local minion = build.calcsTab.mainEnv.minion
		assert.is_not_nil(minion, "expected env.minion")
		return minion.modDB:More(nil, "Damage")
	end

	it("lv88 player: minions get ~x1.5 more damage (0.8% x 62 levels, ModDB 2-decimal rounding)", function()
		-- raw 1 + 0.008 x 62 = 1.496; ModDB:MoreInternal rounds each MORE product
		-- to 2 decimals (round(modResult, 2)) -> 1.50. The in-game measurement
		-- (Fehm shred-free capture: needed x1.49916) fits the rounded value at
		-- -0.06% and the unrounded at +0.21% -- both within gear-INC rounding
		-- noise; we lock the engine behavior.
		build.characterLevel = 88
		build.skillsTab:SelSkill(1, "SummonThornTotem")
		runCallback("OnFrame")
		assert.are.equals(1.5, round(minionMoreDamage(), 3))
	end)

	it("lv26 and below: no scaling", function()
		build.characterLevel = 26
		build.skillsTab:SelSkill(1, "SummonThornTotem")
		runCallback("OnFrame")
		assert.are.equals(1, round(minionMoreDamage(), 3))
	end)

	it("lv100: x1.59 (raw 1.592, 2-decimal rounding)", function()
		build.characterLevel = 100
		build.skillsTab:SelSkill(1, "SummonThornTotem")
		runCallback("OnFrame")
		assert.are.equals(1.59, round(minionMoreDamage(), 3))
	end)
end)
