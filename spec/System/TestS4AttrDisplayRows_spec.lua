-- @leb-regression-guard: s4-converted-attr-single-row
-- Locks the Season 4 (1.4) converted-attribute sidebar rows to EXACTLY ONE row each.
-- Each converted attribute (Brutality/Guile/Madness/Apathy/Rampancy) is inserted into
-- build.displayStats solely by the s4AttrPair loop in Build.lua, in its base-attribute
-- slot. A previously-present second block re-listed all five at the end of the attribute
-- section, producing a DUPLICATE sidebar row (the reported "Madness shown twice" bug).
-- See REGRESSION_GUARDS.md "s4-converted-attr-single-row".

describe("TestS4AttrDisplayRows", function()
	before_each(function()
		newBuild()
	end)

	local S4_CONVERTED = { "Brutality", "Guile", "Madness", "Apathy", "Rampancy" }

	it("emits exactly one displayStats row per converted attribute", function()
		local counts = {}
		for _, entry in ipairs(build.displayStats) do
			if entry.stat then
				counts[entry.stat] = (counts[entry.stat] or 0) + 1
			end
		end
		for _, stat in ipairs(S4_CONVERTED) do
			assert.are.equals(1, counts[stat] or 0,
				stat .. " must appear exactly once in displayStats (duplicate row regression)")
		end
	end)

	it("places each converted attribute immediately after its base attribute", function()
		-- base -> converted pairing (mirrors Build.lua s4AttrPair)
		local pair = { Str = "Brutality", Dex = "Guile", Int = "Madness", Att = "Apathy", Vit = "Rampancy" }
		-- index every stat row's position
		local posOf = {}
		for i, entry in ipairs(build.displayStats) do
			if entry.stat and posOf[entry.stat] == nil then posOf[entry.stat] = i end
		end
		for base, conv in pairs(pair) do
			assert.is_not_nil(posOf[base], base .. " base attribute row missing")
			assert.is_not_nil(posOf[conv], conv .. " converted attribute row missing")
			-- converted sits right after its base (base, [conv]); the Req<base> row follows.
			assert.are.equals(posOf[base] + 1, posOf[conv],
				conv .. " must directly follow " .. base)
		end
	end)
end)
