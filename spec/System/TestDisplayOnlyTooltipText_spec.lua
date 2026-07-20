-- @leb-regression-guard:display-only-tooltip-text
-- Some unique tooltip lines carry NO modifier at all. In LE's game data they live in the
-- unique's `tooltipDescriptions` block rather than its `mods` array -- the dispatcher is
-- `tooltipEntries[].modDisplay`: < 128 renders `mods[modDisplay]`, >= 128 renders
-- `tooltipDescriptions[modDisplay - 128]` as raw text. Throne of Ambition (id=211) is the
-- pure case: its ONLY real mod is property 98 with hideInTooltip=true, and all six visible
-- lines are modDisplay 128..133, i.e. all text.
--
-- LEB transcribes those lines so the tooltip matches in-game, so the parser must consume
-- them to nothing. Two failure modes this locks:
--   1. extra ~= nil -> ItemTools.formatModLine paints the line red UNSUPPORTED, which is a
--      lie: the line is not an unmodelled mod, it is not a mod. (The Ambition mechanics ARE
--      modelled -- "per stack of ambition" -> Multiplier:AmbitionStacks limit 20, count via
--      ConfigOptions "# of Active Ambition Stacks".) NOTE extra must be nil, not "" -- an
--      empty string is truthy in Lua and paints red just the same.
--   2. #mods ~= 0 -> a ghost mod silently enters modDB and shifts DPS.
--
-- Historical: LEB carried only 4 of the 6 lines, and paraphrased the stack-gain line as
-- "100% Chance to gain a stack of Ambition when you hit a boss or rare enemy" -- wording
-- that appears in neither the datamine nor the in-game tooltip, and which dropped the
-- "(1 second cooldown)" qualifier. It parsed to {} + residue -> rendered red.
-- Verbatim source: uniques_v3.json id=211 tooltipDescriptions; confirmed against an in-game
-- screenshot 2026-07-16. See REGRESSION_GUARDS.md "display-only-tooltip-text".

describe("Display-only tooltip text parses to nothing #parser", function()
	before_each(function() newBuild() end)

	-- Bypass the ModCache so the LIVE parser logic is exercised (locks the fix even if
	-- ModCache is later regenerated), then RESTORE the original entry so the live parse
	-- can't shadow the baked Data/ModCache row for later specs in this process.
	local function reparse(line)
		local saved = modLib.parseModCache[line]
		modLib.parseModCache[line] = nil
		local mods, extra = modLib.parseMod(line)
		modLib.parseModCache[line] = saved
		return mods, extra
	end

	local DISPLAY_ONLY = {
		"You gain a stack of Ambition when you hit a boss or rare enemy (1 second cooldown)",
		"20 Maximum Stacks of Ambition",
		"You lose all stacks of Ambition if you go 4 seconds without gaining a stack",
	}

	for _, line in ipairs(DISPLAY_ONLY) do
		it(string.format("%q yields no mod and no residue", line), function()
			local mods, extra = reparse(line)
			assert.is_not_nil(mods, "must return an empty mod list, not nil")
			assert.are.equals(0, #mods, "display-only text must not produce a ghost mod")
			assert.is_nil(extra,
				"extra must be nil, not \"\" -- a truthy extra paints the line red UNSUPPORTED")
		end)
	end

	it("display-only lines are not painted red by formatModLine", function()
		for _, line in ipairs(DISPLAY_ONLY) do
			local mods, extra = reparse(line)
			local out = itemLib.formatModLine({ line = line, modList = mods, extra = extra })
			assert.is_not_nil(out, string.format("%q must not be hidden entirely", line))
			assert.is_nil(out:find(colorCodes.UNSUPPORTED, 1, true),
				string.format("%q must not render in UNSUPPORTED red", line))
			assert.is_nil(out:find("NOT SUPPORTED IN LEB YET", 1, true),
				string.format("%q is not an unsupported mod -- there is nothing to support", line))
		end
	end)

	it("the stack cap stays modelled by the parser, not by the display-only line", function()
		-- The "20 Maximum Stacks of Ambition" line contributes nothing; the cap is the
		-- `limit = 20` on the "per stack of ambition" modTagList entry. Guard that
		-- transcribing the text did not become load-bearing for the cap.
		local mods = reparse("2% more Cold Damage per stack of Ambition")
		assert.is_not_nil(mods)
		assert.are.equals(1, #mods, "the per-stack line must still parse to exactly one mod")
	end)
end)
