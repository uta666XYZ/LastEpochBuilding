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
	local itemsTab = build.itemsTab

	-- Title
	self.controls.title = new("LabelControl", {"TOPLEFT", self, "TOPLEFT"}, 8, 8, 0, 20, "^7Idol Inventory")

	-- Altar label showing current altar from ItemsTab
	self.controls.altarInfo = new("LabelControl",
		{"TOPLEFT", self.controls.title, "BOTTOMLEFT"}, 0, 6, 0, 16,
		function()
			local altarSlot = itemsTab.controls.idolAltarSlot
			local item = altarSlot and itemsTab.items[altarSlot.selItemId]
			if item then
				return "^7Idol Altar: " .. colorCodes[item.rarity] .. item.name
			else
				return "^7Idol Altar: None"
			end
		end)

	-- Create the idol grid immediately so slots are registered before any calculation
	-- 2x the default cell size (68 → 136, 46 → 92)
	self.controls.idolGrid = new("IdolGridControl",
		{"TOPLEFT", self.controls.altarInfo, "BOTTOMLEFT"}, 0, 8,
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
