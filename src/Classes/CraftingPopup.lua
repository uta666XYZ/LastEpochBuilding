-- Last Epoch Building
--
-- Class: Crafting Popup
-- Maxroll-style crafting UI with Select/Edit tabs for item creation.
--
local t_insert = table.insert
local t_remove = table.remove
local m_max = math.max
local m_min = math.min
local m_floor = math.floor
local m_ceil = math.ceil
local pairs = pairs
local ipairs = ipairs

-- Rarity tier color mapping: maps affix tier sum to rarity display
local function getRarityForTierSum(tierSum, hasAffix)
	if not hasAffix then return "NORMAL" end
	if tierSum <= 4 then return "MAGIC" end
	if tierSum <= 6 then return "RARE" end
	return "EXALTED"
end

-- Clean implicit text: remove formatting tags and filter out UNKNOWN_STAT entries
local function cleanImplicitText(line)
	if line:find("%[UNKNOWN_STAT%]") then
		return nil
	end
	return line:gsub("{rounding:%w+}", ""):gsub("{[^}]+}", "")
end

-- Ordered item type list with category headers
-- Headers have isSeparator=true and are not selectable
local function buildOrderedTypeList(dataTypeList)
	local available = {}
	for _, t in ipairs(dataTypeList) do
		available[t] = true
	end

	local ordered = {}
	local sections = {
		{ header = "-- Armor --", types = {
			"Helmet", "Body Armor", "Belt", "Boots", "Gloves",
		}},
		{ header = "-- Weapons --", types = {
			"One-Handed Axe", "Dagger", "One-Handed Mace", "Sceptre",
			"One-Handed Sword", "Wand", "Two-Handed Axe", "Two-Handed Mace",
			"Two-Handed Spear", "Two-Handed Staff", "Two-Handed Sword", "Bow",
		}},
		{ header = "-- Off-Hand --", types = {
			"Quiver", "Shield", "Off-Hand Catalyst",
		}},
		{ header = "-- Accessories --", types = {
			"Amulet", "Ring", "Relic",
		}},
		{ header = "-- Idols --", types = {
			"Small Idol", "Minor Idol", "Humble Idol", "Stout Idol",
			"Grand Idol", "Large Idol", "Ornate Idol", "Huge Idol", "Adorned Idol",
		}},
		{ header = "-- Other --", types = {
			"Idol Altar",
		}},
	}

	local used = {}
	for _, sec in ipairs(sections) do
		t_insert(ordered, { label = "^8" .. sec.header, isSeparator = true })
		for _, typeName in ipairs(sec.types) do
			if available[typeName] then
				t_insert(ordered, { label = typeName, typeName = typeName })
				used[typeName] = true
			end
		end
	end

	-- Append any remaining types not in the predefined order
	for _, t in ipairs(dataTypeList) do
		if not used[t] and t ~= "" and t ~= "Blessing"
			and not t:find("Lens$") then
			t_insert(ordered, { label = t, typeName = t })
		end
	end

	return ordered
end

local CraftingPopupClass = newClass("CraftingPopup", "ControlHost", "Control", function(self, itemsTab)
	local popupW = 800
	local popupH = 600
	self.ControlHost()
	self.Control(nil, 0, 0, popupW, popupH)
	self.x = function()
		return m_floor((main.screenW - popupW) / 2)
	end
	self.y = function()
		return m_floor((main.screenH - popupH) / 2)
	end
	self.itemsTab = itemsTab
	self.build = itemsTab.build

	-- State
	self.currentTab = "select"  -- "select" or "edit"
	self.selectedTypeIndex = 1
	self.selectedBaseCategory = "basic" -- "basic", "unique", or "set"
	self.editItem = nil

	-- Load set data
	self.setItems = self:LoadSetData()

	-- Build ordered type list
	self.orderedTypeList = buildOrderedTypeList(self.build.data.itemBaseTypeList)
	-- Find first selectable index
	for i, entry in ipairs(self.orderedTypeList) do
		if not entry.isSeparator then
			self.selectedTypeIndex = i
			break
		end
	end

	-- Affix state: each entry = { modKey = nil, tier = 0, range = 128 }
	self.affixState = {
		prefix1  = { modKey = nil, tier = 0, range = 128 },
		prefix2  = { modKey = nil, tier = 0, range = 128 },
		suffix1  = { modKey = nil, tier = 0, range = 128 },
		suffix2  = { modKey = nil, tier = 0, range = 128 },
		sealed   = { modKey = nil, tier = 0, range = 128 },
	}
	self.corrupted = false

	self:BuildControls()
end)

-- Load set data from JSON
function CraftingPopupClass:LoadSetData()
	local ver = self.build.targetVersion or "1_4"
	local setData = readJsonFile("Data/Set/set_" .. ver .. ".json")
	if not setData then
		setData = readJsonFile("Data/Set/set_1_4.json")
	end
	return setData or {}
end

-- Get the currently selected type name
function CraftingPopupClass:GetSelectedTypeName()
	local entry = self.orderedTypeList[self.selectedTypeIndex]
	return entry and entry.typeName or nil
end

-- Build all UI controls
function CraftingPopupClass:BuildControls()
	local self_ref = self
	local controls = { }
	self.controls = controls

	-- ========================
	-- Tab buttons (top)
	-- ========================
	controls.tabSelect = new("ButtonControl", {"TOPLEFT", self, "TOPLEFT"}, 10, 10, 80, 24, function()
		return self_ref.currentTab == "select" and "^7>> Select <<" or "^7Select"
	end, function()
		self_ref.currentTab = "select"
	end)

	controls.tabEdit = new("ButtonControl", {"LEFT", controls.tabSelect, "RIGHT"}, 5, 0, 80, 24, function()
		return self_ref.currentTab == "edit" and "^7>> Edit <<" or "^7Edit"
	end, function()
		if self_ref.editItem then
			self_ref.currentTab = "edit"
		end
	end)

	controls.closeBtn = new("ButtonControl", {"TOPRIGHT", self, "TOPRIGHT"}, -10, 10, 40, 24, "X", function()
		self_ref:Close()
	end)

	-- ========================
	-- SELECT TAB controls
	-- ========================

	-- Item Type label + dropdown
	controls.typeLabel = new("LabelControl", {"TOPLEFT", self, "TOPLEFT"}, 15, 50, 0, 16, "^7Item Type:")
	controls.typeLabel.shown = function() return self_ref.currentTab == "select" end

	-- Build dropdown list from ordered types
	local typeDropList = {}
	for _, entry in ipairs(self.orderedTypeList) do
		t_insert(typeDropList, entry)
	end

	controls.typeDropdown = new("DropDownControl", {"LEFT", controls.typeLabel, "RIGHT"}, 5, 0, 220, 20,
		typeDropList,
		function(index, value)
			if value.isSeparator then
				-- Skip separators: find next selectable
				for i = index + 1, #typeDropList do
					if not typeDropList[i].isSeparator then
						controls.typeDropdown.selIndex = i
						self_ref.selectedTypeIndex = i
						self_ref:RefreshBaseList()
						return
					end
				end
				return
			end
			self_ref.selectedTypeIndex = index
			self_ref:RefreshBaseList()
		end)
	controls.typeDropdown.shown = function() return self_ref.currentTab == "select" end
	controls.typeDropdown.selIndex = self.selectedTypeIndex
	controls.typeDropdown.enableDroppedWidth = true
	controls.typeDropdown.maxDroppedWidth = 300

	-- Category tabs: Basic / Unique / Set
	controls.catBasic = new("ButtonControl", {"TOPLEFT", self, "TOPLEFT"}, 15, 80, 80, 20, function()
		return self_ref.selectedBaseCategory == "basic" and "^7Basic" or "^8Basic"
	end, function()
		self_ref.selectedBaseCategory = "basic"
		self_ref:RefreshBaseList()
	end)
	controls.catBasic.shown = function() return self_ref.currentTab == "select" end
	controls.catBasic.locked = function() return self_ref.selectedBaseCategory == "basic" end

	controls.catUnique = new("ButtonControl", {"LEFT", controls.catBasic, "RIGHT"}, 5, 0, 80, 20, function()
		return self_ref.selectedBaseCategory == "unique" and "^7Unique" or "^8Unique"
	end, function()
		self_ref.selectedBaseCategory = "unique"
		self_ref:RefreshBaseList()
	end)
	controls.catUnique.shown = function() return self_ref.currentTab == "select" end
	controls.catUnique.locked = function() return self_ref.selectedBaseCategory == "unique" end

	controls.catSet = new("ButtonControl", {"LEFT", controls.catUnique, "RIGHT"}, 5, 0, 80, 20, function()
		return self_ref.selectedBaseCategory == "set" and "^7Set" or "^8Set"
	end, function()
		self_ref.selectedBaseCategory = "set"
		self_ref:RefreshBaseList()
	end)
	controls.catSet.shown = function() return self_ref.currentTab == "select" end
	controls.catSet.locked = function() return self_ref.selectedBaseCategory == "set" end

	-- Column headers (between category tabs and item list)
	controls.colHeaderName = new("LabelControl", {"TOPLEFT", self, "TOPLEFT"}, 18, 106, 0, 14, "^8Item Name")
	controls.colHeaderName.shown = function() return self_ref.currentTab == "select" end
	controls.colHeaderType = new("LabelControl", {"TOPLEFT", self, "TOPLEFT"}, 318, 106, 0, 14, "^8Type")
	controls.colHeaderType.shown = function() return self_ref.currentTab == "select" end
	controls.colHeaderLv = new("LabelControl", {"TOPLEFT", self, "TOPLEFT"}, 478, 106, 0, 14, "^8Lv Req")
	controls.colHeaderLv.shown = function() return self_ref.currentTab == "select" end

	-- Separator line under headers
	-- (drawn in Draw())

	-- Base item list (scrollbar enabled)
	controls.baseList = new("ListControl", {"TOPLEFT", self, "TOPLEFT"}, 15, 122, 770, 420, 20, true, false, {})
	controls.baseList.shown = function() return self_ref.currentTab == "select" end
	controls.baseList.colList = {
		{ width = function() return 300 end },
		{ width = function() return 160 end },
		{ width = function() return 80 end },
	}
	controls.baseList.GetRowValue = function(control, column, index, entry)
		if entry.isImplicitRow then
			-- Sub-row showing implicit text
			if column == 1 then
				return "^8    " .. (entry.implicitText or "")
			end
			return ""
		end
		if column == 1 then
			local colorCode = colorCodes.NORMAL
			if entry.rarity then
				colorCode = colorCodes[entry.rarity] or colorCodes.NORMAL
			end
			return colorCode .. (entry.label or entry.name or "?")
		elseif column == 2 then
			return "^7" .. (entry.displayType or "")
		elseif column == 3 then
			local lvl = entry.base and entry.base.req and entry.base.req.level or 0
			return "^7" .. tostring(lvl)
		end
	end
	controls.baseList.OnSelClick = function(control, index, entry, doubleClick)
		if entry and entry.isImplicitRow then
			-- Clicking implicit sub-row selects the parent
			return
		end
		if doubleClick then
			self_ref:SelectBase(entry)
		end
	end
	controls.baseList.OverrideSelectIndex = function(control, index)
		-- Prevent selecting implicit sub-rows
		local entry = control.list[index]
		if entry and entry.isImplicitRow then
			return true
		end
	end

	-- Select button
	controls.selectBtn = new("ButtonControl", {"BOTTOMRIGHT", self, "BOTTOMRIGHT"}, -15, -15, 100, 28, "Select", function()
		local list = controls.baseList.list
		local idx = controls.baseList.selIndex
		if list[idx] and not list[idx].isImplicitRow then
			self_ref:SelectBase(list[idx])
		end
	end)
	controls.selectBtn.shown = function() return self_ref.currentTab == "select" end

	-- ========================
	-- EDIT TAB controls
	-- ========================

	-- Item name display
	controls.editItemName = new("LabelControl", {"TOPLEFT", self, "TOPLEFT"}, 15, 50, 0, 18, "")
	controls.editItemName.shown = function() return self_ref.currentTab == "edit" end
	controls.editItemName.label = function()
		if not self_ref.editItem then return "" end
		local item = self_ref.editItem
		local col = colorCodes[item.rarity] or colorCodes.NORMAL
		return col .. (item.title or item.namePrefix .. item.baseName .. item.nameSuffix)
	end

	-- "Change Item" button
	controls.changeItemBtn = new("ButtonControl", {"LEFT", controls.editItemName, "LEFT"}, 0, 22, 100, 20, "Change Item", function()
		self_ref.currentTab = "select"
	end)
	controls.changeItemBtn.shown = function() return self_ref.currentTab == "edit" end

	-- Implicits section label
	controls.implicitLabel = new("LabelControl", {"TOPLEFT", self, "TOPLEFT"}, 15, 100, 0, 14, colorCodes.UNIQUE .. "IMPLICITS")
	controls.implicitLabel.shown = function() return self_ref.currentTab == "edit" end

	-- Implicit lines (dynamic labels, up to 8)
	for i = 1, 8 do
		local key = "implicit" .. i
		controls[key] = new("LabelControl", {"TOPLEFT", self, "TOPLEFT"}, 25, 100 + i * 18, 0, 14, "")
		controls[key].shown = function()
			if self_ref.currentTab ~= "edit" or not self_ref.editItem then return false end
			return self_ref.editItem.implicitModLines[i] ~= nil
		end
		controls[key].label = function()
			if not self_ref.editItem or not self_ref.editItem.implicitModLines[i] then return "" end
			local ml = self_ref.editItem.implicitModLines[i]
			return "^7" .. itemLib.formatModLine(ml)
		end
	end

	-- Affix sections
	local affixSections = {
		{ key = "prefix",  label = "PREFIXES",       slots = {"prefix1", "prefix2"}, type = "Prefix", y = 210 },
		{ key = "suffix",  label = "SUFFIXES",       slots = {"suffix1", "suffix2"}, type = "Suffix", y = 310 },
		{ key = "sealed",  label = "SEALED AFFIX",   slots = {"sealed"},             type = nil,      y = 400 },
	}

	for _, section in ipairs(affixSections) do
		-- Section label
		local labelKey = section.key .. "Label"
		controls[labelKey] = new("LabelControl", {"TOPLEFT", self, "TOPLEFT"}, 15, section.y, 0, 14,
			colorCodes.UNIQUE .. section.label)
		controls[labelKey].shown = function() return self_ref.currentTab == "edit" end

		for slotIdx, slotKey in ipairs(section.slots) do
			local slotY = section.y + slotIdx * 26

			-- Affix display label (shows selected affix text)
			local dispKey = slotKey .. "Display"
			controls[dispKey] = new("LabelControl", {"TOPLEFT", self, "TOPLEFT"}, 25, slotY, 0, 14, "")
			controls[dispKey].shown = function()
				if self_ref.currentTab ~= "edit" then return false end
				return self_ref.affixState[slotKey].modKey ~= nil
			end
			controls[dispKey].label = function()
				return self_ref:GetAffixDisplayText(slotKey)
			end

			-- Range value edit (numeric input for direct value entry, 0-256)
			local rangeKey = slotKey .. "Range"
			controls[rangeKey] = new("EditControl", {"TOPLEFT", self, "TOPLEFT"}, 450, slotY - 1, 60, 18,
				"128", nil, "%D", nil, function(buf)
					local val = tonumber(buf) or 128
					val = m_max(0, m_min(256, val))
					self_ref.affixState[slotKey].range = val
					self_ref:RebuildEditItem()
				end)
			controls[rangeKey].shown = function()
				if self_ref.currentTab ~= "edit" then return false end
				return self_ref.affixState[slotKey].modKey ~= nil
			end
			controls[rangeKey].numberInc = 1

			-- Tier display button (right side)
			local tierKey = slotKey .. "Tier"
			controls[tierKey] = new("ButtonControl", {"TOPLEFT", self, "TOPLEFT"}, 530, slotY, 40, 18,
				function()
					local st = self_ref.affixState[slotKey]
					if st.modKey then
						return "^7T" .. tostring(st.tier + 1)
					end
					return ""
				end,
				function()
					self_ref:CycleTier(slotKey)
				end)
			controls[tierKey].shown = function()
				if self_ref.currentTab ~= "edit" then return false end
				return self_ref.affixState[slotKey].modKey ~= nil
			end
			controls[tierKey].tooltipFunc = function(tooltip, mode)
				if mode == "OUT" then return end
				self_ref:BuildTierTooltip(tooltip, slotKey)
			end

			-- Remove affix button
			local removeKey = slotKey .. "Remove"
			controls[removeKey] = new("ButtonControl", {"TOPLEFT", self, "TOPLEFT"}, 580, slotY, 20, 18, "x", function()
				self_ref.affixState[slotKey].modKey = nil
				self_ref.affixState[slotKey].tier = 0
				self_ref.affixState[slotKey].range = 128
				if controls[rangeKey].SetText then
					controls[rangeKey]:SetText("128")
				end
				self_ref:RebuildEditItem()
			end)
			controls[removeKey].shown = function()
				if self_ref.currentTab ~= "edit" then return false end
				return self_ref.affixState[slotKey].modKey ~= nil
			end

			-- "Add" dropdown (shown when no affix selected)
			local addKey = slotKey .. "Add"
			controls[addKey] = new("DropDownControl", {"TOPLEFT", self, "TOPLEFT"}, 25, slotY, 400, 18,
				{}, function(index, value)
					if value and value.statOrderKey then
						self_ref.affixState[slotKey].modKey = value.statOrderKey
						self_ref.affixState[slotKey].tier = value.maxTier or 0
						self_ref.affixState[slotKey].range = 128
						if controls[rangeKey].SetText then
							controls[rangeKey]:SetText("128")
						end
						self_ref:RebuildEditItem()
					end
				end)
			controls[addKey].shown = function()
				if self_ref.currentTab ~= "edit" then return false end
				if self_ref.affixState[slotKey].modKey ~= nil then return false end
				-- For second prefix/suffix, only show if first slot is filled
				if slotKey == "prefix2" then
					return self_ref.affixState.prefix1.modKey ~= nil
				elseif slotKey == "suffix2" then
					return self_ref.affixState.suffix1.modKey ~= nil
				end
				return true
			end
			controls[addKey].enableDroppedWidth = true
			controls[addKey].maxDroppedWidth = 500
			controls[addKey].tooltipFunc = function(tooltip, mode, index, value)
				tooltip:Clear()
				if mode ~= "OUT" and value and value.statOrderKey then
					self_ref:BuildAffixTooltip(tooltip, value.statOrderKey)
				end
			end
		end
	end

	-- Corrupted checkbox
	controls.corruptedLabel = new("LabelControl", {"TOPLEFT", self, "TOPLEFT"}, 15, 460, 0, 14,
		colorCodes.UNIQUE .. "CORRUPTED")
	controls.corruptedLabel.shown = function() return self_ref.currentTab == "edit" end

	controls.corruptedCheck = new("CheckBoxControl", {"TOPLEFT", self, "TOPLEFT"}, 115, 460, 18, "", function(state)
		self_ref.corrupted = state
		self_ref:RebuildEditItem()
	end)
	controls.corruptedCheck.shown = function() return self_ref.currentTab == "edit" end

	-- Save button
	controls.saveBtn = new("ButtonControl", {"BOTTOMRIGHT", self, "BOTTOMRIGHT"}, -15, -15, 100, 28, "Save", function()
		self_ref:SaveItem()
	end)
	controls.saveBtn.shown = function() return self_ref.currentTab == "edit" and self_ref.editItem ~= nil end

	-- Cancel button
	controls.cancelBtn = new("ButtonControl", {"BOTTOMRIGHT", self, "BOTTOMRIGHT"}, -125, -15, 100, 28, "Cancel", function()
		self_ref:Close()
	end)

	-- Set up anchoring
	for id, control in pairs(self.controls) do
		if not control.anchor.point then
			control:SetAnchor("TOP", self, "TOP")
		elseif not control.anchor.other then
			control.anchor.other = self
		elseif type(control.anchor.other) ~= "table" then
			control.anchor.other = self.controls[control.anchor.other]
		end
	end

	-- Initial population
	self:RefreshBaseList()
	self:RefreshAffixDropdowns()
end

-- Refresh the base item list based on selected type and category
function CraftingPopupClass:RefreshBaseList()
	local typeName = self:GetSelectedTypeName()
	if not typeName then return end

	local list = {}

	if self.selectedBaseCategory == "basic" then
		local bases = self.build.data.itemBaseLists[typeName]
		if bases then
			for _, entry in ipairs(bases) do
				t_insert(list, {
					label = entry.name,
					name = entry.name,
					base = entry.base,
					type = typeName,
					displayType = entry.base.type or "",
					rarity = "NORMAL",
					category = "basic",
				})
			end
		end
		-- Sort by level requirement ascending
		table.sort(list, function(a, b)
			local lvlA = a.base and a.base.req and a.base.req.level or 0
			local lvlB = b.base and b.base.req and b.base.req.level or 0
			if lvlA == lvlB then
				return a.name < b.name
			end
			return lvlA < lvlB
		end)
	elseif self.selectedBaseCategory == "unique" then
		-- Find uniques matching the current type
		local bases = self.build.data.itemBaseLists[typeName]
		if bases then
			for uid, unique in pairs(self.build.data.uniques) do
				for _, baseEntry in ipairs(bases) do
					if baseEntry.base.baseTypeID == unique.baseTypeID and
					   baseEntry.base.subTypeID == unique.subTypeID then
						t_insert(list, {
							label = unique.name,
							name = unique.name,
							base = baseEntry.base,
							baseName = baseEntry.name,
							type = typeName,
							displayType = baseEntry.base.type or "",
							rarity = "UNIQUE",
							category = "unique",
							uniqueData = unique,
							uniqueID = uid,
						})
						break
					end
				end
			end
			table.sort(list, function(a, b) return a.label < b.label end)
		end
	elseif self.selectedBaseCategory == "set" then
		-- Find set items matching the current type
		local bases = self.build.data.itemBaseLists[typeName]
		if bases then
			for sid, setItem in pairs(self.setItems) do
				for _, baseEntry in ipairs(bases) do
					if baseEntry.base.baseTypeID == setItem.baseTypeID and
					   baseEntry.base.subTypeID == setItem.subTypeID then
						t_insert(list, {
							label = setItem.name,
							name = setItem.name,
							base = baseEntry.base,
							baseName = baseEntry.name,
							type = typeName,
							displayType = baseEntry.base.type or "",
							rarity = "SET",
							category = "set",
							setData = setItem,
							setID = sid,
						})
						break
					end
				end
			end
			table.sort(list, function(a, b) return a.label < b.label end)
		end
	end

	-- Insert implicit sub-rows below each base item (filter UNKNOWN_STAT)
	local expandedList = {}
	for _, entry in ipairs(list) do
		t_insert(expandedList, entry)
		if entry.base and entry.base.implicits then
			for _, impl in ipairs(entry.base.implicits) do
				local text = cleanImplicitText(impl)
				if text then
					t_insert(expandedList, {
						isImplicitRow = true,
						implicitText = text,
						parentEntry = entry,
					})
				end
			end
		end
	end

	self.controls.baseList.list = expandedList
	self.controls.baseList.selIndex = 1
end

-- Select a base item and switch to Edit tab
function CraftingPopupClass:SelectBase(entry)
	if not entry or entry.isImplicitRow then return end

	-- Reset affix state
	for _, st in pairs(self.affixState) do
		st.modKey = nil
		st.tier = 0
		st.range = 128
	end
	self.corrupted = false
	self.controls.corruptedCheck.state = false

	-- Reset range edits
	local slotKeys = {"prefix1", "prefix2", "suffix1", "suffix2", "sealed"}
	for _, slotKey in ipairs(slotKeys) do
		local rangeCtrl = self.controls[slotKey .. "Range"]
		if rangeCtrl and rangeCtrl.SetText then
			rangeCtrl:SetText("128")
		end
	end

	-- Create item
	local item = new("Item")
	item.name = entry.name
	item.baseName = entry.baseName or entry.name
	item.base = entry.base
	item.buffModLines = {}
	item.enchantModLines = {}
	item.classRequirementModLines = {}
	item.implicitModLines = {}
	item.explicitModLines = {}
	item.quality = 0
	item.crafted = true

	if entry.category == "unique" then
		item.rarity = "UNIQUE"
		item.title = entry.uniqueData.name
		item.uniqueID = entry.uniqueID
		-- Add unique mods as explicit lines
		if entry.uniqueData.mods then
			for i, modText in ipairs(entry.uniqueData.mods) do
				local rollId = entry.uniqueData.rollIds and entry.uniqueData.rollIds[i]
				local modLine = { line = modText }
				if rollId then
					modLine.range = 128
				end
				t_insert(item.explicitModLines, modLine)
			end
		end
	elseif entry.category == "set" then
		item.rarity = "SET"
		item.title = entry.setData.name
		item.setID = entry.setID
		-- Add set mods as explicit lines
		if entry.setData.mods then
			for i, modText in ipairs(entry.setData.mods) do
				local rollId = entry.setData.rollIds and entry.setData.rollIds[i]
				local modLine = { line = modText }
				if rollId then
					modLine.range = 128
				end
				t_insert(item.explicitModLines, modLine)
			end
		end
	else
		item.rarity = "RARE"
		item.title = "New Item"
	end

	-- Add implicit mod lines (filter UNKNOWN_STAT)
	if entry.base.implicits then
		for _, line in ipairs(entry.base.implicits) do
			if not line:find("%[UNKNOWN_STAT%]") then
				t_insert(item.implicitModLines, { line = line })
			end
		end
	end

	item:NormaliseQuality()
	item:BuildAndParseRaw()

	self.editItem = item
	self.editBaseEntry = entry
	self.currentTab = "edit"

	self:RefreshAffixDropdowns()
end

-- Refresh all affix dropdown lists based on current item
function CraftingPopupClass:RefreshAffixDropdowns()
	if not self.editItem then return end

	local itemMods = self.editItem.affixes or data.itemMods.Item
	if not itemMods then return end

	-- Build grouped affix lists by statOrderKey
	local prefixGroups = {}
	local suffixGroups = {}

	for modId, mod in pairs(itemMods) do
		if mod.statOrderKey then
			if mod.type == "Prefix" then
				if not prefixGroups[mod.statOrderKey] then
					local labelParts = {}
					for k = 1, 10 do
						if mod[k] then
							t_insert(labelParts, mod[k])
						end
					end
					local label = table.concat(labelParts, " / ")
					label = label:gsub("{rounding:%w+}", ""):gsub("{[^}]+}", "")
					prefixGroups[mod.statOrderKey] = {
						label = label,
						statOrderKey = mod.statOrderKey,
						affix = mod.affix,
						type = "Prefix",
						maxTier = mod.tier or 0,
					}
				else
					local g = prefixGroups[mod.statOrderKey]
					if mod.tier and mod.tier > g.maxTier then
						g.maxTier = mod.tier
					end
				end
			elseif mod.type == "Suffix" then
				if not suffixGroups[mod.statOrderKey] then
					local labelParts = {}
					for k = 1, 10 do
						if mod[k] then
							t_insert(labelParts, mod[k])
						end
					end
					local label = table.concat(labelParts, " / ")
					label = label:gsub("{rounding:%w+}", ""):gsub("{[^}]+}", "")
					suffixGroups[mod.statOrderKey] = {
						label = label,
						statOrderKey = mod.statOrderKey,
						affix = mod.affix,
						type = "Suffix",
						maxTier = mod.tier or 0,
					}
				else
					local g = suffixGroups[mod.statOrderKey]
					if mod.tier and mod.tier > g.maxTier then
						g.maxTier = mod.tier
					end
				end
			end
		end
	end

	-- Build sorted lists
	local prefixList = { { label = "-- Select Prefix --" } }
	local suffixList = { { label = "-- Select Suffix --" } }
	local sealedList = { { label = "-- Select Affix --" } }

	for _, g in pairs(prefixGroups) do
		t_insert(prefixList, g)
		t_insert(sealedList, { label = g.label, statOrderKey = g.statOrderKey, affix = g.affix, type = g.type, maxTier = g.maxTier })
	end
	for _, g in pairs(suffixGroups) do
		t_insert(suffixList, g)
		t_insert(sealedList, { label = g.label, statOrderKey = g.statOrderKey, affix = g.affix, type = g.type, maxTier = g.maxTier })
	end

	local function sortByLabel(a, b)
		if not a.statOrderKey then return true end
		if not b.statOrderKey then return false end
		return (a.label or "") < (b.label or "")
	end
	table.sort(prefixList, sortByLabel)
	table.sort(suffixList, sortByLabel)
	table.sort(sealedList, sortByLabel)

	-- Apply mutual exclusion
	local function filterExclusions(list, excludeKeys)
		local filtered = { list[1] }
		for i = 2, #list do
			local excluded = false
			for _, exKey in ipairs(excludeKeys) do
				if list[i].statOrderKey == exKey then
					excluded = true
					break
				end
			end
			if not excluded then
				t_insert(filtered, list[i])
			end
		end
		return filtered
	end

	local p1Key = self.affixState.prefix1.modKey
	local p2Key = self.affixState.prefix2.modKey
	local s1Key = self.affixState.suffix1.modKey
	local s2Key = self.affixState.suffix2.modKey

	self.controls.prefix1Add.list = filterExclusions(prefixList, p2Key and {p2Key} or {})
	self.controls.prefix2Add.list = filterExclusions(prefixList, p1Key and {p1Key} or {})
	self.controls.suffix1Add.list = filterExclusions(suffixList, s2Key and {s2Key} or {})
	self.controls.suffix2Add.list = filterExclusions(suffixList, s1Key and {s1Key} or {})

	local sealedExclude = {}
	if p1Key then t_insert(sealedExclude, p1Key) end
	if p2Key then t_insert(sealedExclude, p2Key) end
	if s1Key then t_insert(sealedExclude, s1Key) end
	if s2Key then t_insert(sealedExclude, s2Key) end
	self.controls.sealedAdd.list = filterExclusions(sealedList, sealedExclude)
end

-- Get the ModItem key (statOrderKey_tier) for an affix slot
function CraftingPopupClass:GetModKey(slotKey)
	local st = self.affixState[slotKey]
	if not st or not st.modKey then return nil end
	return tostring(st.modKey) .. "_" .. tostring(st.tier)
end

-- Get display text for an affix slot
function CraftingPopupClass:GetAffixDisplayText(slotKey)
	local st = self.affixState[slotKey]
	if not st or not st.modKey then return "" end

	local modKey = self:GetModKey(slotKey)
	local itemMods = data.itemMods.Item
	local mod = itemMods and itemMods[modKey]
	if not mod then return "^7(unknown affix)" end

	local parts = {}
	for k = 1, 10 do
		local line = mod[k]
		if line and type(line) == "string" then
			local displayLine = itemLib.applyRange(line, st.range, nil, nil)
			if not displayLine then displayLine = line end
			displayLine = displayLine:gsub("{rounding:%w+}", ""):gsub("{[^}]+}", "")
			t_insert(parts, displayLine)
		end
	end

	local col = "^7"
	if st.tier >= 5 then col = colorCodes.EXALTED
	elseif st.tier >= 3 then col = colorCodes.RARE
	elseif st.tier >= 0 then col = colorCodes.MAGIC end

	return col .. table.concat(parts, ", ")
end

-- Build tooltip showing all tiers for an affix
function CraftingPopupClass:BuildTierTooltip(tooltip, slotKey)
	tooltip:Clear()
	local st = self.affixState[slotKey]
	if not st or not st.modKey then return end

	local itemMods = data.itemMods.Item
	if not itemMods then return end

	local baseMod = itemMods[tostring(st.modKey) .. "_0"]
	if baseMod then
		tooltip:AddLine(16, colorCodes.UNIQUE .. (baseMod.affix or "Affix"))
		tooltip:AddLine(14, "^7\"" .. (baseMod.affix or "") .. "\"")
		tooltip:AddSeparator(10)
	end

	for tier = 0, 7 do
		local key = tostring(st.modKey) .. "_" .. tostring(tier)
		local mod = itemMods[key]
		if mod then
			local parts = {}
			for k = 1, 10 do
				local line = mod[k]
				if line and type(line) == "string" then
					line = line:gsub("{rounding:%w+}", ""):gsub("{[^}]+}", "")
					t_insert(parts, line)
				end
			end
			local text = table.concat(parts, ", ")
			local marker = (tier == st.tier) and " <<" or ""
			local col = (tier == st.tier) and colorCodes.UNIQUE or "^7"
			tooltip:AddLine(14, col .. "T" .. tostring(tier + 1) .. ": " .. text .. marker)
		end
	end

	tooltip:AddSeparator(10)
	tooltip:AddLine(12, "^8Click to cycle through tiers")
end

-- Build tooltip showing affix details for the add dropdown
function CraftingPopupClass:BuildAffixTooltip(tooltip, statOrderKey)
	local itemMods = data.itemMods.Item
	if not itemMods then return end

	local baseMod = itemMods[tostring(statOrderKey) .. "_0"]
	if not baseMod then return end

	tooltip:AddLine(16, colorCodes.UNIQUE .. (baseMod.affix or "Affix"))
	tooltip:AddSeparator(10)

	for tier = 0, 7 do
		local key = tostring(statOrderKey) .. "_" .. tostring(tier)
		local mod = itemMods[key]
		if mod then
			local parts = {}
			for k = 1, 10 do
				local line = mod[k]
				if line and type(line) == "string" then
					line = line:gsub("{rounding:%w+}", ""):gsub("{[^}]+}", "")
					t_insert(parts, line)
				end
			end
			tooltip:AddLine(14, "^7T" .. tostring(tier + 1) .. ": " .. table.concat(parts, ", "))
		end
	end
end

-- Cycle tier for an affix slot
function CraftingPopupClass:CycleTier(slotKey)
	local st = self.affixState[slotKey]
	if not st or not st.modKey then return end

	local maxTier = 0
	local itemMods = data.itemMods.Item
	for tier = 7, 0, -1 do
		local key = tostring(st.modKey) .. "_" .. tostring(tier)
		if itemMods[key] then
			maxTier = tier
			break
		end
	end

	st.tier = (st.tier + 1) % (maxTier + 1)
	self:RebuildEditItem()
end

-- Rebuild the edit item from current affix state
function CraftingPopupClass:RebuildEditItem()
	if not self.editItem then return end

	local item = self.editItem
	local itemMods = data.itemMods.Item

	wipeTable(item.explicitModLines)
	wipeTable(item.prefixes)
	wipeTable(item.suffixes)
	item.namePrefix = ""
	item.nameSuffix = ""

	-- Re-add unique/set mods if applicable
	if self.editBaseEntry and self.editBaseEntry.category == "unique" and self.editBaseEntry.uniqueData then
		for i, modText in ipairs(self.editBaseEntry.uniqueData.mods) do
			local rollId = self.editBaseEntry.uniqueData.rollIds and self.editBaseEntry.uniqueData.rollIds[i]
			local modLine = { line = modText }
			if rollId then
				modLine.range = 128
			end
			t_insert(item.explicitModLines, modLine)
		end
	elseif self.editBaseEntry and self.editBaseEntry.category == "set" and self.editBaseEntry.setData then
		for i, modText in ipairs(self.editBaseEntry.setData.mods) do
			local rollId = self.editBaseEntry.setData.rollIds and self.editBaseEntry.setData.rollIds[i]
			local modLine = { line = modText }
			if rollId then
				modLine.range = 128
			end
			t_insert(item.explicitModLines, modLine)
		end
	end

	-- Add affix mod lines
	local prefixIdx = 0
	local suffixIdx = 0
	local tierSum = 0
	local hasAffix = false

	local slotOrder = {"prefix1", "prefix2", "suffix1", "suffix2", "sealed"}
	for _, slotKey in ipairs(slotOrder) do
		local st = self.affixState[slotKey]
		if st.modKey then
			hasAffix = true
			tierSum = tierSum + st.tier
			local modKey = tostring(st.modKey) .. "_" .. tostring(st.tier)
			local mod = itemMods[modKey]
			if mod then
				if mod.type == "Prefix" then
					prefixIdx = prefixIdx + 1
					item.prefixes[prefixIdx] = { modId = modKey, range = st.range }
					if prefixIdx == 1 then
						item.namePrefix = (mod.affix or "") .. " "
					end
				elseif mod.type == "Suffix" then
					suffixIdx = suffixIdx + 1
					item.suffixes[suffixIdx] = { modId = modKey, range = st.range }
					if suffixIdx == 1 then
						item.nameSuffix = " " .. (mod.affix or "")
					end
				end

				local modScalar = 1 + (item.base.affixEffectModifier or 0)
				if mod.standardAffixEffectModifier then
					modScalar = modScalar - mod.standardAffixEffectModifier
				end
				for k = 1, 10 do
					local line = mod[k]
					if line and type(line) == "string" then
						t_insert(item.explicitModLines, {
							line = line,
							range = st.range,
							valueScalar = modScalar,
						})
					end
				end
			end
		end
	end

	-- Update rarity based on affixes
	if self.editBaseEntry and self.editBaseEntry.category == "basic" then
		item.rarity = getRarityForTierSum(tierSum, hasAffix)
		if item.rarity == "RARE" or item.rarity == "EXALTED" then
			item.title = item.title or "New Item"
		else
			item.title = nil
		end
	elseif self.editBaseEntry and self.editBaseEntry.category == "unique" and hasAffix then
		item.rarity = "LEGENDARY"
	end

	item.corrupted = self.corrupted
	item:BuildAndParseRaw()
	self:RefreshAffixDropdowns()
end

-- Save item and close
function CraftingPopupClass:SaveItem()
	if not self.editItem then return end
	self:RebuildEditItem()
	self.itemsTab:SetDisplayItem(self.editItem)
	self:Close()
end

-- Close the popup
function CraftingPopupClass:Close()
	main:ClosePopup()
end

-- Draw override
function CraftingPopupClass:Draw(viewPort)
	local x, y = self:GetPos()
	local width, height = self:GetSize()

	-- Draw popup background
	SetDrawColor(0.05, 0.05, 0.05)
	DrawImage(nil, x, y, width, height)

	-- Draw border
	SetDrawColor(0.4, 0.35, 0.2)
	DrawImage(nil, x, y, width, 2)
	DrawImage(nil, x, y + height - 2, width, 2)
	DrawImage(nil, x, y, 2, height)
	DrawImage(nil, x + width - 2, y, 2, height)

	-- Draw title
	local title = "Craft Item"
	if self.editItem then
		title = "Craft Item - " .. (self.editItem.baseName or "")
	end
	SetDrawColor(1, 1, 1)
	DrawString(x + m_floor(width / 2), y + 12, "CENTER_X", 16, "VAR", "^7" .. title)

	-- Draw separator under tabs
	SetDrawColor(0.3, 0.3, 0.3)
	DrawImage(nil, x + 10, y + 40, width - 20, 1)

	-- Draw separator under column headers (select tab)
	if self.currentTab == "select" then
		SetDrawColor(0.25, 0.25, 0.25)
		DrawImage(nil, x + 15, y + 120, width - 30, 1)
	end

	-- Draw rarity-colored name background in edit mode
	if self.currentTab == "edit" and self.editItem then
		local col = colorCodes[self.editItem.rarity]
		if col then
			local r, g, b = col:match("%%^x(%x%x)(%x%x)(%x%x)")
			if not r then
				r, g, b = col:match("%^x(%x%x)(%x%x)(%x%x)")
			end
			if r then
				SetDrawColor(tonumber(r, 16)/255 * 0.15, tonumber(g, 16)/255 * 0.15, tonumber(b, 16)/255 * 0.15)
				DrawImage(nil, x + 10, y + 45, width - 20, 28)
			end
		end
	end

	self:DrawControls(viewPort)
end

-- Input processing
function CraftingPopupClass:ProcessInput(inputEvents, viewPort)
	for id, event in ipairs(inputEvents) do
		if event.type == "KeyDown" then
			if event.key == "ESCAPE" then
				self:Close()
				return
			end
		end
	end
	self:ProcessControlsInput(inputEvents, viewPort)
end
