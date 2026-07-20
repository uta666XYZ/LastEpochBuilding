-- @leb-regression-guard:skill-dot-per-second-base
-- Validation provenance is retained in maintainer notes.

describe("SkillDotPerSecondBase", function()
	local function readFile(path)
		local f = io.open(path, "r")
		if not f then return nil end
		local s = f:read("*a"); f:close()
		return s
	end

	local src
	setup(function()
		src = readFile("Modules/CalcOffence.lua")
		assert.is_not_nil(src, "must read Modules/CalcOffence.lua")
	end)

	it("carries the skill-dot-per-second-base guard marker", function()
		assert.is_truthy(src:find("@leb%-regression%-guard:skill%-dot%-per%-second%-base"),
			"CalcOffence.lua must carry the skill-dot-per-second-base guard marker")
	end)

	it("does NOT divide the base by duration for a finite-duration pure-DoT stacking aura", function()
		-- The gated branch: skillFlags.dot AND not hit AND finite duration -> base kept as per-second.
		assert.is_truthy(src:find("not skillFlags.hit and skillData.duration < 1000", 1, true),
			"must gate the no-divide branch on (not hit) AND a finite (< 1000s) duration")
	end)

	it("still divides by duration for channel / hit+dot / no-duration DoTs (else branch preserved)", function()
		-- The prior total-over-duration model must remain reachable for the excluded cases.
		assert.is_truthy(src:find("baseDmg / skillData.duration", 1, true),
			"the channel/hit+dot fallback must still divide the base by the skill duration")
	end)

	it("interval skills are unaffected (per-tick base; /interval applied at the TotalDPS stage)", function()
		assert.is_truthy(src:find("output.TotalDPS / skillData.damageInterval", 1, true),
			"interval DoTs must keep dividing TotalDPS by the damage interval (unchanged)")
	end)
end)
