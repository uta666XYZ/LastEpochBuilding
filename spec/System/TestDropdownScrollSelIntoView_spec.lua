-- @leb-regression-guard: dropdown-scrollselintoview-nil-selindex
-- Locks the contract that DropDownControl:ScrollSelIntoView never performs
-- arithmetic on a nil ListIndexToDropIndex result. Opening a dropdown whose
-- selIndex is nil or points outside the (possibly filtered) list used to crash
-- OnFrame ("attempt to perform arithmetic on a nil value" at
-- Classes/DropDownControl.lua:181) via OnKeyDown -> ScrollSelIntoView.
--
-- ListIndexToDropIndex returns nil (not its `default` arg) whenever selIndex is
-- nil, <= 0, or > #list; ScrollSelIntoView must clamp that to the first row.

describe("DropdownScrollSelIntoView", function()
	local function makeDropDown(list)
		return new("DropDownControl", nil, 0, 0, 100, 20, list, function() end)
	end

	local LIST = { "Alpha", "Beta", "Gamma" }

	it("does not error when selIndex is nil", function()
		local dd = makeDropDown(LIST)
		dd.selIndex = nil
		assert.has_no.errors(function() dd:ScrollSelIntoView() end)
	end)

	it("does not error when selIndex points past the end of the list", function()
		local dd = makeDropDown(LIST)
		dd.selIndex = #LIST + 5
		assert.has_no.errors(function() dd:ScrollSelIntoView() end)
	end)

	it("does not error when selIndex is zero", function()
		local dd = makeDropDown(LIST)
		dd.selIndex = 0
		assert.has_no.errors(function() dd:ScrollSelIntoView() end)
	end)

	it("still scrolls a valid selection into view without error", function()
		local dd = makeDropDown(LIST)
		dd.selIndex = 3
		assert.has_no.errors(function() dd:ScrollSelIntoView() end)
	end)
end)
