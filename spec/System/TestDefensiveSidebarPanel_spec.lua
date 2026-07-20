-- @leb-regression-guard: le-defensive-sidebar-panel
-- Locks the sidebar to surface the LE-specific defence-layer stats that CalcDefence
-- already computes onto the player output but the panel historically never displayed:
-- Endurance, EnduranceThreshold, BlockEffectiveness, GlancingBlowChance, CritAvoidance,
-- StunAvoidance. Each appears on the in-game character sheet's defence page (the sole
-- authority for derived stats), so the sidebar must keep parity. Every row is gated so
-- builds without a given stat are unaffected (presentation-only, no snapshot change).
-- HealingEffectiveness IS surfaced; the in-game sheet calls it "Increased Healing
-- Effectiveness" and shows the INC portion (verified MyLittleStJames lv79 = 189%),
-- which is precisely what output.HealingEffectiveness holds (Sum INC). The DISPLAY
-- label is the shortened "Healing Effectiveness" (the full label wraps to two sidebar
-- lines; user-requested 2026-06-10 — see guard sidebar-defence-display-tweaks).
-- See REGRESSION_GUARDS.md "le-defensive-sidebar-panel".

describe("TestDefensiveSidebarPanel", function()
	before_each(function()
		newBuild()
	end)

	-- LE-specific defence-layer stats that must each carry a sidebar row
	local REQUIRED = {
		"Endurance", "EnduranceThreshold", "BlockEffectiveness",
		"GlancingBlowChance", "CritAvoidance", "StunAvoidance",
		"HealingEffectiveness",
	}

	it("displayStats has a row for every LE-specific defence stat", function()
		assert.is_not_nil(build.displayStats, "displayStats must exist")
		local present = {}
		for _, row in ipairs(build.displayStats) do
			if row.stat then present[row.stat] = true end
		end
		for _, stat in ipairs(REQUIRED) do
			assert.is_true(present[stat] == true,
				"sidebar missing defence row for " .. stat)
		end
	end)

	it("each defence row is gated so builds without the stat are unaffected", function()
		for _, row in ipairs(build.displayStats) do
			for _, stat in ipairs(REQUIRED) do
				if row.stat == stat then
					assert.is_function(row.condFunc, stat .. " row must have a condFunc gate")
					assert.is_falsy(row.condFunc(0, {}), stat .. " row must hide when value is 0")
				end
			end
		end
	end)

	it("EnduranceThreshold row hides when Endurance is 0", function()
		for _, row in ipairs(build.displayStats) do
			if row.stat == "EnduranceThreshold" then
				assert.is_falsy(row.condFunc(601, { Endurance = 0 }),
					"EnduranceThreshold must hide when Endurance is 0")
				assert.is_true(row.condFunc(601, { Endurance = 20 }) == true,
					"EnduranceThreshold must show when Endurance > 0")
			end
		end
	end)

	it("surfaces HealingEffectiveness with the short 'Healing Effectiveness' label", function()
		-- The stat itself stays surfaced (in-game character-sheet parity); the display
		-- label is shortened because the full in-game name wraps to two sidebar lines
		-- (user-requested 2026-06-10; guard sidebar-defence-display-tweaks).
		local found
		for _, row in ipairs(build.displayStats) do
			if row.stat == "HealingEffectiveness" then found = row end
		end
		assert.is_not_nil(found, "HealingEffectiveness row must exist")
		assert.are.equal("Healing Effectiveness", found.label)
	end)
end)
