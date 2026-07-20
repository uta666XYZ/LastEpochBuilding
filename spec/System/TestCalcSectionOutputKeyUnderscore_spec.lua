-- @leb-regression-guard: calc-section-output-key-underscore
-- CalcSectionControl:FormatStr must substitute {output:KEY} / {N:output:KEY}
-- placeholders whose KEY contains underscores or digits (e.g.
-- BurningDaggerChanceOnMeleeFire_RateLimit). The key character class was
-- [%a%.:]+ (letters only), so any underscore/digit key never matched and the
-- raw "{0:output:...}" text was rendered in the Calcs tab.

describe("CalcSectionOutputKeyUnderscore", function()
	local function makeSection()
		local calcsTab = { }
		local subSection = { { label = "Test", defaultCollapsed = false, data = { } } }
		return new("CalcSectionControl", calcsTab, 294, "Test", 1, "^xFFFFFF", subSection)
	end

	it("substitutes output keys that contain underscores", function()
		local section = makeSection()
		local actor = { output = {
			BurningDaggerChanceOnMeleeFire_RateLimit = 3,
			BurningDaggerChanceOnMeleeFire_RateInterval = 1,
		} }
		local out = section:FormatStr(
			"{0:output:BurningDaggerChanceOnMeleeFire_RateLimit} per {1:output:BurningDaggerChanceOnMeleeFire_RateInterval} sec",
			actor)
		assert.are.equal("3 per 1 sec", out)
	end)

	it("still substitutes plain letter keys", function()
		local section = makeSection()
		local actor = { output = { CooldownRecovery = 5 } }
		assert.are.equal("5%", section:FormatStr("{0:output:CooldownRecovery}%", actor))
	end)
end)
