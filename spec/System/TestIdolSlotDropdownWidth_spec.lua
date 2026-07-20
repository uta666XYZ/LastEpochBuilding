-- @leb-regression-guard: idol-slot-dropdown-width
-- Locks the contract that a DropDownControl opting into auto-width
-- (enableDroppedWidth) sizes its open list to the item labels, NOT to the
-- narrow box width. Idol grid cells are only ~68px wide, and before the fix
-- the equippable-idol list was clipped down to that (roughly the width of the
-- "None" entry), making item names unreadable.
--
-- Three invariants are pinned:
--   1. Expansion: droppedWidth grows past the box width to fit a long label.
--   2. Font independence: the measuring font is the fixed dropdown row font
--      (16), NOT self.height - 4. A tall box (idol cell, height 46) must
--      compute the SAME droppedWidth as a standard 20px box for the same list.
--      (Pre-fix it over-estimated by ~ (height-4)/16, i.e. ~2.6x for idols.)
--   3. Icon reserve: dropExtraWidth adds room for the leading per-row icon
--      strip (type / primordial / corrupted) so long names aren't clipped
--      behind their icons.

describe("IdolSlotDropdownWidth", function()
	-- Stub DrawStringWidth so it depends on BOTH the font-size arg and the text
	-- length. This is what distinguishes the font-independence fix: the old code
	-- passed self.height - 4 as the font size, the new code passes a fixed 16.
	local function withCharWidth(fn)
		local orig = _G.DrawStringWidth
		_G.DrawStringWidth = function(height, _, text)
			return #(text or "") * height
		end
		local ok, err = pcall(fn)
		_G.DrawStringWidth = orig
		if not ok then error(err) end
	end

	local function makeDropDown(width, height, list, maxW, extra)
		local dd = new("DropDownControl", nil, 0, 0, width, height, list, function() end)
		dd.maxDroppedWidth = maxW
		dd.dropExtraWidth = extra or 0
		return dd
	end

	local LONG = { "None", "Grand Idol of the Erased Legion" }

	it("expands the open list past the narrow box width to fit item names", function()
		withCharWidth(function()
			-- Idol-cell geometry: 68px box, tall 46px cell, generous cap.
			local dd = makeDropDown(68, 46, LONG, 10000, 0)
			dd:CheckDroppedWidth(true)
			assert.is_true(dd.droppedWidth > 68,
				"dropped list should widen to fit item names, got " .. tostring(dd.droppedWidth))
		end)
	end)

	it("measures at the fixed row font, so box height does not change the width", function()
		withCharWidth(function()
			local tall = makeDropDown(68, 46, LONG, 10000, 0) -- idol grid cell
			local std  = makeDropDown(68, 20, LONG, 10000, 0) -- standard dropdown
			tall:CheckDroppedWidth(true)
			std:CheckDroppedWidth(true)
			assert.are.equal(std.droppedWidth, tall.droppedWidth,
				"tall and standard boxes must compute equal dropped width (font is fixed 16)")
			-- And it must be the font-16 measurement, not the height-42 one.
			local expected = #("Grand Idol of the Erased Legion") * 16 + 10
			assert.are.equal(expected, tall.droppedWidth)
		end)
	end)

	it("reserves extra width for the leading per-row icon strip", function()
		withCharWidth(function()
			local noIcons   = makeDropDown(68, 46, LONG, 10000, 0)
			local withIcons = makeDropDown(68, 46, LONG, 10000, 3 * 18)
			noIcons:CheckDroppedWidth(true)
			withIcons:CheckDroppedWidth(true)
			assert.are.equal(noIcons.droppedWidth + 3 * 18, withIcons.droppedWidth,
				"dropExtraWidth should be added on top of the label width")
		end)
	end)
end)
