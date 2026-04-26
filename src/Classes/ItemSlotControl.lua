-- Last Epoch Building
--
-- Class: Item Slot
-- Item Slot control, extends the basic dropdown control.
--
local pairs = pairs
local ipairs = ipairs
local t_insert = table.insert
local m_min = math.min

-- 16x16 type-icon mapping mirrored from ItemListControl so equipped slots can
-- show the same icon strip (type + primordial + corrupted) as the All items
-- list. Kept duplicated locally to avoid a cross-Class dependency.
local TYPE_ICON = {
	["Amulet"]            = "Icon_Amulet.png",
	["Belt"]              = "Icon_Belt.png",
	["Body Armor"]        = "Icon_Armor.png",
	["Boots"]             = "Icon_Boots.png",
	["Bow"]               = "Icon_Bow.png",
	["Dagger"]            = "Icon_Dagger.png",
	["Gloves"]            = "Icon_Gloves.png",
	["Helmet"]            = "Icon_Helmet.png",
	["Off-Hand Catalyst"] = "Icon_Shield.png",
	["One-Handed Axe"]    = "Icon_Axe.png",
	["Two-Handed Axe"]    = "Icon_Axe.png",
	["One-Handed Mace"]   = "Icon_Mace.png",
	["Two-Handed Mace"]   = "Icon_Mace.png",
	["One-Handed Sword"]  = "Icon_Sword.png",
	["Two-Handed Sword"]  = "Icon_Sword.png",
	["Two-Handed Spear"]  = "Icon_Polearm.png",
	["Two-Handed Staff"]  = "Icon_Staff.png",
	["Quiver"]            = "Icon_Quiver.png",
	["Relic"]             = "Icon_Relic.png",
	["Ring"]              = "Icon_Ring.png",
	["Sceptre"]           = "Icon_Sceptre.png",
	["Shield"]            = "Icon_Shield.png",
	["Wand"]              = "Icon_Wand.png",
	["Idol Altar"]        = "idol/Idol_Altar_Pyramidal_Altar.png",
	["Blessing"]          = "blessings/body_of_obsidian.png",
}

local function iconFileForItem(item)
	if not item or not item.type then return nil end
	local f = TYPE_ICON[item.type]
	if f then return f end
	if item.type:find("Idol") then return "Icon_Idol.png" end
	return nil
end

local iconHandles = {}
local function getIconHandle(filename)
	if not filename then return nil end
	if not iconHandles[filename] then
		local h = NewImageHandle()
		h:Load("Assets/" .. filename, "ASYNC")
		iconHandles[filename] = h
	end
	return iconHandles[filename]
end

-- Whether an item has a Primordial affix (sat=7). Detection covers (a) the
-- live craft editor state, (b) explicitModLines flagged by CraftRebuildItem,
-- and (c) any prefix/suffix mod entry with specialAffixType == 7 (this
-- catches imported items whose craftState was rebuilt without the flag).
local function itemHasPrimordial(item)
	if not item then return false end
	if item.primordial then return true end
	if item.craftState and item.craftState.affixState
		and item.craftState.affixState.primordial
		and item.craftState.affixState.primordial.modKey ~= nil then
		return true
	end
	if item.explicitModLines then
		for _, line in ipairs(item.explicitModLines) do
			if line.primordial then return true end
		end
	end
	if item.affixes then
		local lists = { item.prefixes, item.suffixes }
		for li = 1, 2 do
			local list = lists[li]
			if list then
				for _, slot in ipairs(list) do
					if slot.modId and slot.modId ~= "None" then
						local mod = item.affixes[slot.modId]
						if mod and mod.specialAffixType == 7 then return true end
					end
				end
			end
		end
	end
	return false
end

local ItemSlotClass = newClass("ItemSlotControl", "DropDownControl", function(self, anchor, x, y, itemsTab, slotName, slotLabel, nodeId, w, h)
	self.DropDownControl(anchor, x, y, w or 310, h or 20, { }, function(index, value)
		if self.items[index] ~= self.selItemId then
			local newItemId = self.items[index]
			local newItem = newItemId and newItemId ~= 0 and itemsTab.items[newItemId]
			-- Block equipping a second Primordial item: only one Primordial
			-- item may be equipped across the entire character at once.
			if newItem and itemHasPrimordial(newItem) then
				local conflict
				for _, otherSlot in pairs(itemsTab.slots or {}) do
					if otherSlot ~= self and otherSlot.selItemId and otherSlot.selItemId ~= 0 then
						local other = itemsTab.items[otherSlot.selItemId]
						if other and itemHasPrimordial(other) then
							conflict = { slot = otherSlot, item = other }
							break
						end
					end
				end
				if conflict then
					local msg = "Only one Primordial item can be equipped at a time."
					local cur = "^7Currently equipped in " .. (conflict.slot.label or conflict.slot.slotName)
						.. ": " .. (conflict.item.title or conflict.item.name or "")
					local popup = {}
					popup.label = new("LabelControl", nil, 0, 20, 0, 16, "^1"..msg)
					popup.label2 = new("LabelControl", nil, 0, 45, 0, 14, cur)
					popup.ok = new("ButtonControl", nil, 0, 80, 80, 20, "OK", function()
						main:ClosePopup()
					end)
					main:OpenPopup(460, 110, "Primordial Limit", popup, "ok")
					for i, id in ipairs(self.items) do
						if id == self.selItemId then self.selIndex = i; break end
					end
					return
				end
			end
			self:SetSelItemId(newItemId)
			itemsTab:PopulateSlots()
			itemsTab:AddUndoState()
			itemsTab.build.buildFlag = true
		end
	end)
	self.anchor.collapse = true
	self.enabled = function()
		return #self.items > 1
	end
	self.shown = function()
		return not self.inactive
	end
	self.itemsTab = itemsTab
	self.items = { }
	self.selItemId = 0
	self.slotName = slotName
	-- Leading 16x16 icon strip drawn by DropDownControl: type, primordial,
	-- corrupted (only the markers that apply for the equipped item).
	-- preLabelIcons disabled: returning a non-nil list from this callback
	-- caused a non-deterministic C++ renderer crash inside DropDownControl's
	-- icon-strip loop (frame swap / GPU submit). Primordial/corrupted markers
	-- are still shown in the All Items list (ItemListControl:GetRowIcon).
	self.preLabelIcons = nil
	self.slotNum = tonumber(slotName:match("%d+$") or slotName:match("%d+"))
	if slotName:match("Flask") then
		self.controls.activate = new("CheckBoxControl", {"RIGHT",self,"LEFT"}, -2, 0, 20, nil, function(state)
			self.active = state
			itemsTab.activeItemSet[self.slotName].active = state
			itemsTab:AddUndoState()
			itemsTab.build.buildFlag = true
		end)
		self.controls.activate.enabled = function()
			return self.selItemId ~= 0
		end
		self.controls.activate.tooltipText = "Activate this flask."
		self.labelOffset = -24
	else
		self.labelOffset = -2
	end
	self.abyssalSocketList = { }
	self.tooltipFunc = function(tooltip, mode, index, itemId)
		local item = itemsTab.items[self.items[index]]
		if main.popups[1] or mode == "OUT" or not item or (not self.dropped and itemsTab.selControl and itemsTab.selControl ~= self.controls.activate) then
			tooltip:Clear()
		elseif tooltip:CheckForUpdate(item, launch.devModeAlt, itemsTab.build.outputRevision) then
			itemsTab:AddItemTooltip(tooltip, item, self)
		end
	end
	self.label = slotLabel or slotName
	self.nodeId = nodeId
end)

function ItemSlotClass:SetSelItemId(selItemId)
    self.itemsTab.activeItemSet[self.slotName].selItemId = selItemId
	self.selItemId = selItemId
end

function ItemSlotClass:Populate()
	wipeTable(self.items)
	wipeTable(self.list)
	self.items[1] = 0
	self.list[1] = "None"
	self.selIndex = 1
	for _, item in pairs(self.itemsTab.items) do
		if self.itemsTab:IsItemValidForSlot(item, self.slotName) then
			t_insert(self.items, item.id)
			local itemColor
			if item.type == "Idol Altar" then
				itemColor = colorCodes.EXALTED
			elseif item.type and item.type:find("Idol") and item.rarity ~= "UNIQUE" then
				itemColor = colorCodes.IDOL
			else
				itemColor = colorCodes[item.rarity]
			end
			t_insert(self.list, itemColor..item.name)
			if item.id == self.selItemId then
				self.selIndex = #self.list
			end
		end
	end
	if not self.selItemId or not self.itemsTab.items[self.selItemId] or not self.itemsTab:IsItemValidForSlot(self.itemsTab.items[self.selItemId], self.slotName) then
		self:SetSelItemId(0)
	end

	-- Update Abyssal Sockets
	local abyssalSocketCount = 0
	if self.selItemId > 0 then
		local selItem = self.itemsTab.items[self.selItemId]
		abyssalSocketCount = selItem.abyssalSocketCount or 0
	end
	for i, abyssalSocket in ipairs(self.abyssalSocketList) do
		abyssalSocket.inactive = i > abyssalSocketCount
	end
end

function ItemSlotClass:CanReceiveDrag(type, value)
	if type ~= "Item" then return false end
	if not self.itemsTab:IsItemValidForSlot(value, self.slotName) then return false end
	-- For idol slots, ensure the idol's footprint doesn't overlap other placed idols
	if value.type and value.type:find("Idol$") and self.slotName:match("^Idol ") then
		if self.itemsTab:IdolFootprintOverlaps(value, self.slotName, self.selItemId ~= 0 and self.selItemId or nil) then
			return false
		end
	end
	return true
end

function ItemSlotClass:ReceiveDrag(type, value, source)
	if value.id and self.itemsTab.items[value.id] then
		self:SetSelItemId(value.id)
	else
		local newItem = new("Item", value.raw)
		newItem:NormaliseQuality()
		self.itemsTab:AddItem(newItem, true)
		self:SetSelItemId(newItem.id)
	end
	self.itemsTab:PopulateSlots()
	self.itemsTab:AddUndoState()
	self.itemsTab.build.buildFlag = true
end

function ItemSlotClass:Draw(viewPort)
	local x, y = self:GetPos()
	local width, height = self:GetSize()
	if self.label ~= "" then
		-- Slot label color: plain white. The previous orange highlight for
		-- the active craft slot / equipped slots was removed per UI request.
		local labelColor = "^7"
		DrawString(x + self.labelOffset, y + 2, "RIGHT_X", height - 4, "VAR", labelColor..self.label..":")
	end
	self.DropDownControl:Draw(viewPort)
	self:DrawControls(viewPort)
	if not main.popups[1] and self.nodeId and (self.dropped or (self:IsMouseOver() and (self.otherDragSource or not self.itemsTab.selControl))) then
		SetDrawLayer(nil, 15)
		local viewerY
		if self.DropDownControl.dropUp and self.DropDownControl.dropped then
			viewerY = y + 20
		else
			viewerY = m_min(y - 300 - 5, viewPort.y + viewPort.height - 304)
		end
		local viewerX = x
		SetDrawColor(1, 1, 1)
		DrawImage(nil, viewerX, viewerY, 304, 304)
		local viewer = self.itemsTab.socketViewer
		local node = self.itemsTab.build.spec.nodes[self.nodeId]
		viewer.zoom = 5
		local scale = self.itemsTab.build.spec.tree.size / 1500
		viewer.zoomX = -node.x / scale
		viewer.zoomY = -node.y / scale
		SetViewport(viewerX + 2, viewerY + 2, 300, 300)
		viewer:Draw(self.itemsTab.build, { x = 0, y = 0, width = 300, height = 300 }, { })
		SetDrawLayer(nil, 30)
		SetDrawColor(1, 1, 1, 0.2)
		DrawImage(nil, 149, 0, 2, 300)
		DrawImage(nil, 0, 149, 300, 2)
		SetViewport()
		SetDrawLayer(nil, 0)
	end
end

function ItemSlotClass:OnKeyDown(key)
	if not self:IsShown() or not self:IsEnabled() then
		return
	end
	local mOverControl = self:GetMouseOverControl()
	if mOverControl and mOverControl == self.controls.activate then
		return mOverControl:OnKeyDown(key)
	end
	return self.DropDownControl:OnKeyDown(key)
end

function ItemSlotClass:OnHoverKeyUp(key)
	if itemLib.wiki.matchesKey(key) then
		local index = self.DropDownControl:GetHoverIndex()
		if index then
			local itemIndex = self.items[index]
			local item = self.itemsTab.items[itemIndex]

			if item then
				itemLib.wiki.openItem(item)
			end
		end
	end
end