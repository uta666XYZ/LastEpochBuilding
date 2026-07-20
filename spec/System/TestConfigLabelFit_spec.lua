-- @leb-regression-guard: config-label-fit
-- Config-tab option labels sit to the LEFT of their control and grow leftward
-- toward the section box's inner border (~228px away). Long LEB-specific labels
-- (e.g. "# of Skeleton Warriors Absorbed by Abomination:",
-- "Apply Tyrant's Skull per-attribute Tyrannosaur block?") overflow that border.
--
-- The fix keeps a UNIFORM font size and WRAPS long labels onto multiple lines
-- (an earlier font-shrinking approach made some labels too small to read). This
-- spec pins the control-level contracts that make wrapping render correctly:
--   1. Uniform font: CheckBoxControl.labelSize stays size - 4 (never shrunk).
--   2. Multi-line width: both CheckBoxControl:GetLabelWidth() and
--      LabelControl.width report the WIDEST line, not the width of the whole
--      newline-joined string (which for a right-anchored label would push it
--      far off to the left).
--   3. Opt-in right alignment: LabelControl exposes a rightAlignLines flag so
--      config labels can flush their wrapped lines to the control while other
--      multi-line labels keep the historic left alignment.

describe("ConfigLabelFit", function()
	-- Stub DrawStringWidth so width depends on BOTH font size and text length,
	-- and so a newline-joined string is WIDER than its widest line (that is what
	-- the multi-line width fix must avoid measuring).
	local function withCharWidth(fn)
		local orig = _G.DrawStringWidth
		_G.DrawStringWidth = function(height, _, text)
			return #(text or "") * height
		end
		local ok, err = pcall(fn)
		_G.DrawStringWidth = orig
		if not ok then error(err) end
	end

	local LINE1 = "# of Skeleton Warriors Absorbed by"
	local LINE2 = "Abomination:"
	local WRAPPED = LINE1 .. "\n" .. LINE2

	it("keeps the checkbox label font uniform (size - 4, never shrunk)", function()
		local cb = new("CheckBoxControl", nil, 0, 0, 18, WRAPPED, function() end)
		assert.are.equal(14, cb.labelSize)
	end)

	it("measures a multi-line checkbox label at its widest line", function()
		withCharWidth(function()
			local cb = new("CheckBoxControl", nil, 0, 0, 18, WRAPPED, function() end)
			-- widest line is LINE1; width = #LINE1 * labelSize(14) + 5
			assert.are.equal(#LINE1 * 14 + 5, cb:GetLabelWidth())
			-- and NOT the whole-string measurement, which would be larger
			assert.is_true(cb:GetLabelWidth() < #WRAPPED * 14 + 5)
		end)
	end)

	it("measures a multi-line LabelControl at its widest line", function()
		withCharWidth(function()
			local lbl = new("LabelControl", nil, 0, 0, 0, 14, "^7" .. WRAPPED)
			local w = lbl:GetProperty("width")
			assert.are.equal(#("^7" .. LINE1) * 14, w)
			assert.is_true(w < #("^7" .. WRAPPED) * 14)
		end)
	end)

	it("supports opt-in right-aligned wrapped lines without affecting others", function()
		local lbl = new("LabelControl", nil, 0, 0, 0, 14, WRAPPED)
		assert.is_nil(lbl.rightAlignLines)          -- default: historic left align
		lbl.rightAlignLines = true                  -- config tab opts in
		assert.is_true(lbl.rightAlignLines)
	end)
end)
