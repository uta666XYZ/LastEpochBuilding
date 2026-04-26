-- Last Epoch Building
--
-- Class: Item list
-- Build item list control.
--
local pairs = pairs
local t_insert = table.insert

-- Item type -> 16x16 icon filename (in Assets/).
-- Weapon/shield subtypes map to generic weapon icons.
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
	-- Blessings reuse an existing blessing sprite as a generic icon
	["Blessing"]          = "blessings/body_of_obsidian.png",
}

local function iconFileForItem(item)
	if not item or not item.type then return nil end
	local t = item.type
	local f = TYPE_ICON[t]
	if f then return f end
	-- All Idol size variants (Minor/Small/Humble/Stout/Grand/Large/Ornate/Huge/Adorned)
	if t:find("Idol") then return "Icon_Idol.png" end
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

-- Primordial detection: covers (a) currently-active craft editor state,
-- (b) explicitModLines flagged by CraftRebuildItem, and (c) any prefix/suffix
-- mod whose specialAffixType == 7 (covers imported items too).
local function itemHasPrimordial(item)
	if not item then return false end
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

local ItemListClass = newClass("ItemListControl", "ListControl", function(self, anchor, x, y, width, height, itemsTab, forceTooltip)
	self.ListControl(anchor, x, y, width, height, 16, "VERTICAL", true, itemsTab.itemOrderList, forceTooltip)
	self.itemsTab = itemsTab
	self.label = "^7All items:"
	self.defaultText = "^x7F7F7FThis is the list of items that have been added to this build.\nYou can add items to this list by dragging them from\none of the other lists, or by clicking 'Add to build' when\nviewing an item."
	self.dragTargetList = { }
	self.controls.delete = new("ButtonControl", {"BOTTOMRIGHT",self,"TOPRIGHT"}, 0, -2, 60, 18, "Delete", function()
		self:OnSelDelete(self.selIndex, self.selValue)
	end)
	self.controls.delete.enabled = function()
		return self.selValue ~= nil
	end
	self.controls.deleteAll = new("ButtonControl", {"RIGHT",self.controls.delete,"LEFT"}, -4, 0, 70, 18, "Delete All", function()
		main:OpenConfirmPopup("Delete All", "Are you sure you want to delete all items in this build?", "Delete", function()
			for _, slot in pairs(itemsTab.slots) do
				slot:SetSelItemId(0)
			end
			wipeTable(self.list)
			wipeTable(self.itemsTab.items)
			itemsTab:PopulateSlots()
			itemsTab:AddUndoState()
			itemsTab.build.buildFlag = true
			self.selIndex = nil
			self.selValue = nil
		end)
	end)
	self.controls.deleteAll.enabled = function()
		return #self.list > 0
	end
	self.controls.deleteUnused = new("ButtonControl", {"RIGHT",self.controls.deleteAll,"LEFT"}, -4, 0, 100, 18, "Delete Unused", function()
		self.itemsTab:DeleteUnused()
	end)
	self.controls.deleteUnused.enabled = function()
		return #self.list > 0
	end
	-- Sort toggles between Category and Equipment modes. Tooltip shows the
	-- mode that will be applied on the next click.
	self.controls.sort = new("ButtonControl", {"RIGHT",self.controls.deleteUnused,"LEFT"}, -4, 0, 60, 18, "Sort", function()
		itemsTab:ToggleSortMode()
	end)
	self.controls.sort.tooltipText = function()
		if itemsTab.sortMode == "category" then
			return "Click to sort by equipped state\n(currently: by category)"
		else
			return "Click to sort by category\n(currently: by equipped state)"
		end
	end
end)

function ItemListClass:GetRowValue(column, index, itemId)
	local item = self.itemsTab.items[itemId]
	if column == 1 then
		local used = ""
		local slot, itemSet = self.itemsTab:GetEquippedSlotForItem(item)
		if not slot then
			used = "  ^9(Unused)"
		elseif itemSet then
			used = "  ^9(Used in '" .. (itemSet.title or "Default") .. "')"
		end
		local color
		if item.type == "Idol Altar" then
			-- Idol Altar is always shown in Exalted (purple) colour
			color = colorCodes.EXALTED
		elseif item.type and item.type:find("Idol") and item.rarity ~= "UNIQUE" and item.rarity ~= "SET" and item.rarity ~= "LEGENDARY" then
			color = colorCodes.IDOL
		else
			color = colorCodes[item.rarity]
		end
		return color .. item.name .. used
	end
end

function ItemListClass:GetRowIcon(column, index, itemId)
	if column ~= 1 then return nil end
	local item = self.itemsTab.items[itemId]
	if not item then return nil end
	local list = {}
	local h = getIconHandle(iconFileForItem(item))
	if h and h:IsValid() then t_insert(list, h) end
	if itemHasPrimordial(item) then
		local p = getIconHandle("Icon_Primordial.png")
		if p and p:IsValid() then t_insert(list, p) end
	end
	if item.corrupted then
		local c = getIconHandle("Icon_Corrupted.png")
		if c and c:IsValid() then t_insert(list, c) end
	end
	if #list == 0 then return nil end
	if #list == 1 then return list[1] end
	return list
end

function ItemListClass:AddValueTooltip(tooltip, index, itemId)
	if main.popups[1] then
		tooltip:Clear()
		return
	end
	local item = self.itemsTab.items[itemId]
	if tooltip:CheckForUpdate(item, IsKeyDown("SHIFT"), launch.devModeAlt, self.itemsTab.build.outputRevision) then
		self.itemsTab:AddItemTooltip(tooltip, item)
	end
end

function ItemListClass:GetDragValue(index, itemId)
	return "Item", self.itemsTab.items[itemId]
end

function ItemListClass:ReceiveDrag(type, value, source)
	if type == "Item" then
		local newItem = new("Item", value.raw)
		newItem:NormaliseQuality()
		self.itemsTab:AddItem(newItem, true, self.selDragIndex)
		self.itemsTab:PopulateSlots()
		self.itemsTab:AddUndoState()
		self.itemsTab.build.buildFlag = true
	end
end

function ItemListClass:OnOrderChange()
	self.itemsTab:AddUndoState()
end

function ItemListClass:OnSelClick(index, itemId, doubleClick)
	local item = self.itemsTab.items[itemId]
	if IsKeyDown("CTRL") then
		local slotName = item:GetPrimarySlot()
		if slotName and self.itemsTab.slots[slotName] then
			if IsKeyDown("SHIFT") then
				-- Redirect to second slot if possible
				local altSlot = slotName:gsub("1","2")
				if self.itemsTab:IsItemValidForSlot(item, altSlot) then
					slotName = altSlot
				end
			end
			if self.itemsTab.slots[slotName].selItemId == item.id then
				self.itemsTab.slots[slotName]:SetSelItemId(0)
			else
				self.itemsTab.slots[slotName]:SetSelItemId(item.id)
			end
			self.itemsTab:PopulateSlots()
			self.itemsTab:AddUndoState()
			self.itemsTab.build.buildFlag = true
		end
	else
		-- Single click (or double click) opens the item editor on the right.
		-- This is more discoverable than the PoB-style double-click-only flow.
		local newItem = new("Item", item:BuildRaw())
		newItem.id = item.id
		self.itemsTab:SetDisplayItem(newItem)
	end
end

function ItemListClass:OnSelCopy(index, itemId)
	local item = self.itemsTab.items[itemId]
	Copy(item:BuildRaw():gsub("\n", "\r\n"))
end

function ItemListClass:OnSelDelete(index, itemId)
	local item = self.itemsTab.items[itemId]
	local equipSlot, equipSet = self.itemsTab:GetEquippedSlotForItem(item)
	if equipSlot then
		local inSet = equipSet and (" in set '"..(equipSet.title or "Default").."'") or ""
		main:OpenConfirmPopup("Delete Item", item.name.." is currently equipped in "..equipSlot.label..inSet..".\nAre you sure you want to delete it?", "Delete", function()
			self.itemsTab:DeleteItem(item)
			self.selIndex = nil
			self.selValue = nil
		end)
	else
		self.itemsTab:DeleteItem(item)
		self.selIndex = nil
		self.selValue = nil
	end
end

function ItemListClass:OnHoverKeyUp(key)
	if itemLib.wiki.matchesKey(key) then
		local itemId = self.ListControl:GetHoverValue()
		if itemId then
			local item = self.itemsTab.items[itemId]
			itemLib.wiki.openItem(item)
		end
	end
end