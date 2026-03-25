-- Last Epoch Building
--
-- Class: Idols Tab
-- Dedicated tab for viewing and equipping Idols.
-- Shows the idol inventory grid at 2x cell size for easy readability.
-- The grid layout (which cells are valid) is shared with ItemsTab via
-- build.itemsTab.idolGridLayout so there is one place to update it.
--

local IdolsTabClass = newClass("IdolsTab", "ControlHost", "Control", function(self, build)
	self.ControlHost()
	self.Control()

	self.build = build

	-- Label above the grid
	self.controls.title = new("LabelControl", {"TOPLEFT", self, "TOPLEFT"}, 8, 8, 0, 20, "^7Idol Inventory")

	-- Create the grid immediately so idol slots are registered in itemsTab
	-- before any calculation runs (even if the user never opens this tab)
	local itemsTab = build.itemsTab
	-- 2x the default cell size (68 → 136, 46 → 92)
	self.controls.idolGrid = new("IdolGridControl",
		{"TOPLEFT", self.controls.title, "BOTTOMLEFT"}, 0, 8,
		itemsTab, itemsTab.idolGridLayout, 136, 92)
end)

function IdolsTabClass:Draw(viewPort, inputEvents)
	self.x = viewPort.x
	self.y = viewPort.y
	self.width = viewPort.width
	self.height = viewPort.height

	self:ProcessControlsInput(inputEvents, viewPort)

	-- Draw background
	main:DrawBackground(viewPort)

	self:DrawControls(viewPort)
end
