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

	-- Idol Altar dropdown (below title)
	-- Build sorted list: "Default" first, then altars alphabetically
	local altarLayouts = itemsTab.altarLayouts
	local altarDropList = { { label = "Default", key = "Default" } }
	do
		local names = {}
		for name in pairs(altarLayouts) do
			table.insert(names, name)
		end
		table.sort(names)
		for _, name in ipairs(names) do
			local layout = altarLayouts[name]
			table.insert(altarDropList, {
				label = (layout.mirrorOf or name) .. (layout.isMirrored and " [Mirrored]" or ""),
				key = name,
			})
		end
	end

	self.controls.altarSelect = new("DropDownControl",
		{"TOPLEFT", self.controls.title, "BOTTOMLEFT"}, 0, 6, 260, 20,
		altarDropList,
		function(index, value)
			itemsTab.activeAltarLayout = altarDropList[index].key
			build.buildFlag = true
		end)
	self.controls.altarLabel = new("LabelControl",
		{"RIGHT", self.controls.altarSelect, "LEFT"}, -4, 0, 0, 16, "^7Idol Altar:")

	-- Create the idol grid immediately so slots are registered before any calculation
	-- 2x the default cell size (68 → 136, 46 → 92)
	self.controls.idolGrid = new("IdolGridControl",
		{"TOPLEFT", self.controls.altarSelect, "BOTTOMLEFT"}, 0, 8,
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
