-- @leb-regression-guard: minion-ailment-upper-panel
-- See REGRESSION_GUARDS.md "minion-ailment-upper-panel".
-- Validation provenance is retained in maintainer notes.

describe("TestMinionAilmentRows", function()
	before_each(function()
		newBuild()
	end)

	-- every damaging ailment that should have a per-ailment minion DPS row
	local REQUIRED = { "Ignite", "Bleed", "Poison", "Frostbite", "Electrify", "Damned", "TimeRot", "Doom" }

	it("minionDisplayStats has a DPS row for every damaging ailment", function()
		assert.is_not_nil(build.minionDisplayStats, "minionDisplayStats must exist")
		local present = {}
		for _, row in ipairs(build.minionDisplayStats) do
			if row.stat then present[row.stat] = true end
		end
		for _, ail in ipairs(REQUIRED) do
			assert.is_true(present[ail .. "DPS"] == true,
				"minion display missing row for " .. ail .. "DPS")
		end
	end)

	it("each ailment DPS row is gated so non-applying minions are unaffected", function()
		local gated = {
			Frostbite = true, Electrify = true, Damned = true, TimeRot = true, Doom = true,
		}
		for _, row in ipairs(build.minionDisplayStats) do
			local ail = row.stat and row.stat:match("^(%a+)DPS$")
			if ail and gated[ail] then
				assert.is_function(row.condFunc, ail .. "DPS row must have a condFunc gate")
				assert.is_false(row.condFunc(0, {}), ail .. "DPS row must hide when value is 0")
				assert.is_true(row.condFunc(123, {}), ail .. "DPS row must show when value > 0")
			end
		end
	end)
end)
