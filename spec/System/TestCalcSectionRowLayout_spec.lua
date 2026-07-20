-- @leb-regression-guard: calc-section-last-row-frame-gap
-- CalcSectionControl reserves a 2px gap after each subsection's rows so the
-- last row's label/value does not touch the section's bottom colour frame (or
-- the next subsection's header border). Every row label fills its row to the
-- bottom edge, so without this gap the final row sat flush against the orange
-- frame line. UpdateSize must therefore add (header 22 + 2px gap) per expanded
-- subsection, matching the "lineY = lineY + 2" after the rows in Draw.

describe("CalcSectionRowLayout", function()
	local function makeSection(nRows)
		local calcsTab = {
			CheckFlag = function() return true end,
			SearchMatch = function() return true end,
		}
		local data = { }
		for i = 1, nRows do
			table.insert(data, { label = "R"..i, { format = "0", { modName = "X" } } })
		end
		local subSection = { { label = "Test", defaultCollapsed = false, data = data } }
		return new("CalcSectionControl", calcsTab, 294, "Test", 1, "^xFFFFFF", subSection)
	end

	-- headless DrawStringWidth() == 1, so every label fits one line (rowHeight 18).
	-- height = 2 (top) + Σ rowHeight + 22 (header) + 2 (bottom gap)
	it("reserves a 2px bottom gap after the last row (2 rows)", function()
		local section = makeSection(2)
		section:UpdateSize()
		assert.are.equal(2 + (18 * 2) + 22 + 2, section.height)
	end)

	it("adds the gap once per subsection, not per row (3 rows)", function()
		local section = makeSection(3)
		section:UpdateSize()
		assert.are.equal(2 + (18 * 3) + 22 + 2, section.height)
	end)
end)
