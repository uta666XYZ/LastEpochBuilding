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

local MAX_MOD_LINES = 3

-- Rarity tier color mapping
local function getRarityForTierSum(tierSum, hasAffix)
	if not hasAffix then return "NORMAL" end
	if tierSum <= 4 then return "MAGIC" end
	if tierSum <= 6 then return "RARE" end
	return "EXALTED"
end

-- Clean implicit text: remove formatting tags and filter UNKNOWN_STAT
local function cleanImplicitText(line)
	if line:find("%[UNKNOWN_STAT%]") then
		return nil
	end
	return line:gsub("{rounding:%w+}", ""):gsub("{[^}]+}", "")
end

-- Check if a mod line template contains a (min-max) range
local function hasRange(line)
	return line:match("%(%-?%d+%.?%d*%-%-?%d+%.?%d*%)") ~= nil
end

-- Get precision for a mod line based on rounding tag
local function getModPrecision(line)
	local precision = 100
	if line:find("{rounding:Integer}") then precision = 1
	elseif line:find("{rounding:Tenth}") then precision = 10
	elseif line:find("{rounding:Thousandth}") then precision = 1000 end
	if line:find("%%") and precision >= 100 then precision = precision / 100 end
	return precision
end

-- Extract rounding tag string from mod line for passing to itemLib.applyRange
local function getRounding(line)
	if line:find("{rounding:Integer}") then return "Integer"
	elseif line:find("{rounding:Tenth}") then return "Tenth"
	elseif line:find("{rounding:Thousandth}") then return "Thousandth" end
	return nil
end

-- Extract min and max from a mod line template
local function extractMinMax(line)
	local min, max = line:match("%(([%-]?%d+%.?%d*)%-([%-]?%d+%.?%d*)%)")
	if min and max then return tonumber(min), tonumber(max) end
	return nil, nil
end

-- Compute the actual displayed value from a mod line and range
local function computeModValue(line, range)
	local computed = itemLib.applyRange(line, range, nil, getRounding(line))
	if not computed then return nil end
	computed = computed:gsub("{rounding:%w+}", ""):gsub("{[^}]+}", "")
	local num = computed:match("([%-]?%d+%.?%d*)")
	return tonumber(num)
end

-- Reverse-map: given a desired value and mod line template, find range (0-256)
-- Uses m_ceil to counteract the m_floor in applyRange's forward computation,
-- then verifies with forward pass and adjusts if needed.
local function reverseModRange(line, targetValue)
	local min, max = extractMinMax(line)
	if not min or not max then return 128 end
	local precision = getModPrecision(line)
	local rangeSize = max - min + 1 / precision
	if rangeSize == 0 then return 0 end
	local rawRange = (targetValue - min) / rangeSize * 255
	local range = m_max(0, m_min(256, m_ceil(rawRange)))
	-- Verify forward computation matches; adjust up if needed
	local actual = computeModValue(line, range)
	if actual and actual < targetValue and range < 256 then
		range = range + 1
	end
	return range
end

-- Clamp a value to valid range for a mod line and return the clamped value
local function clampModValue(line, value)
	local min, max = extractMinMax(line)
	if not min or not max then return value end
	if min <= max then
		return m_max(min, m_min(max, value))
	else
		return m_max(max, m_min(min, value))
	end
end

-- Format a value for display (integer vs decimal based on mod precision)
local function formatModValue(line, value)
	local precision = getModPrecision(line)
	if precision <= 1 then
		return tostring(m_floor(value + 0.5))
	elseif precision <= 10 then
		return string.format("%.1f", value)
	elseif precision <= 100 then
		return string.format("%.2f", value)
	else
		return string.format("%.3f", value)
	end
end

-- Ordered item type list with category headers
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
	for _, t in ipairs(dataTypeList) do
		if not used[t] and t ~= "" and t ~= "Blessing" and not t:find("Lens$") then
			t_insert(ordered, { label = t, typeName = t })
		end
	end
	return ordered
end

local CraftingPopupClass = newClass("CraftingPopup", "ControlHost", "Control", function(self, itemsTab, existingItem)
	local popupW = 800
	local popupMinH = 600
	self.ControlHost()
	self.Control(nil, 0, 0, popupW, popupMinH)
	self.editContentH = popupMinH
	self.width = function()
		return popupW
	end
	self.height = function()
		if self.currentTab == "edit" then
			return m_max(popupMinH, m_min(self.editContentH, main.screenH - 40))
		end
		return popupMinH
	end
	self.x = function() return m_floor((main.screenW - popupW) / 2) end
	self.y = function()
		local _, h = self:GetSize()
		return m_max(20, m_floor((main.screenH - h) / 2))
	end
	self.itemsTab = itemsTab
	self.build = itemsTab.build

	self.currentTab = "select"
	self.selectedTypeIndex = 1
	self.selectedBaseCategory = "basic"
	self.searchText = ""
	self.editItem = nil
	self.rebuilding = false

	self.setItems = self:LoadSetData()
	self.orderedTypeList = buildOrderedTypeList(self.build.data.itemBaseTypeList)
	for i, entry in ipairs(self.orderedTypeList) do
		if not entry.isSeparator then
			self.selectedTypeIndex = i
			break
		end
	end

	-- Affix state: ranges is per-line array
	self.affixState = {
		prefix1    = { modKey = nil, tier = 0, ranges = {} },
		prefix2    = { modKey = nil, tier = 0, ranges = {} },
		suffix1    = { modKey = nil, tier = 0, ranges = {} },
		suffix2    = { modKey = nil, tier = 0, ranges = {} },
		sealed     = { modKey = nil, tier = 0, ranges = {} },
		primordial = { modKey = nil, tier = 7, ranges = {} },
		corrupted  = { modKey = nil, tier = 0, ranges = {} },
	}
	self.corrupted = false

	-- Mod info cache for edit tab display
	self.slotModInfo = {}
	for _, k in ipairs({"prefix1","prefix2","suffix1","suffix2","sealed","primordial","corrupted"}) do
		self.slotModInfo[k] = { count = 0, lines = {} }
	end

	-- Dynamic Y positions for edit tab
	self.editY = {}
	self:RecalcEditLayout()

	self:BuildControls()

	-- Restore existing crafted item for re-editing
	if existingItem and existingItem.craftState then
		self:RestoreCraftState(existingItem)
	end
end)

function CraftingPopupClass:LoadSetData()
	local ver = self.build.targetVersion or "1_4"
	local setData = readJsonFile("Data/Set/set_" .. ver .. ".json")
	if not setData then
		setData = readJsonFile("Data/Set/set_1_4.json")
	end
	return setData or {}
end

function CraftingPopupClass:GetSelectedTypeName()
	local entry = self.orderedTypeList[self.selectedTypeIndex]
	return entry and entry.typeName or nil
end

-- Compute max tier for a given statOrderKey
function CraftingPopupClass:GetMaxTier(statOrderKey)
	-- Idol affixes are always single-tier (T1 only)
	if self:IsAnyIdol() then return 0 end
	for tier = 7, 0, -1 do
		local key = tostring(statOrderKey) .. "_" .. tostring(tier)
		if data.itemMods.Item and data.itemMods.Item[key] then
			return tier
		end
	end
	return 0
end

-- Recalculate dynamic Y positions for edit tab
function CraftingPopupClass:RecalcEditLayout()
	local LINE_H = 18
	local implicitCount = self.editItem and #self.editItem.implicitModLines or 0
	local rarity = self.editItem and self.editItem.rarity
	local uniqueModCount = (rarity == "UNIQUE" or rarity == "WWUNIQUE" or rarity == "SET")
		and self.editItem and #self.editItem.explicitModLines or 0
	local totalDisplayCount = implicitCount + uniqueModCount
	local y = math.max(200, 126 + totalDisplayCount * LINE_H)
	local GAP = 4

	self.editY = {}

	local sectionOrder = {
		{ label = "prefixLabel", slots = {"prefix1", "prefix2"} },
		{ label = "suffixLabel", slots = {"suffix1", "suffix2"} },
		{ label = "sealedLabel", slots = {"sealed"} },
		{ label = "primordialLabel", slots = {"primordial"} },
		{ label = "corruptedLabel", slots = {"corrupted"} },
	}

	local function layoutSlots(slots)
		for _, slotKey in ipairs(slots) do
			local st = self.affixState[slotKey]
			self.editY[slotKey] = {}
			if st.modKey then
				local lc = self.slotModInfo[slotKey].count
				if lc == 0 then lc = 1 end
				for i = 1, MAX_MOD_LINES do
					self.editY[slotKey][i] = y + (i - 1) * LINE_H
				end
				y = y + lc * LINE_H + GAP
			else
				self.editY[slotKey].add = y
				y = y + LINE_H + GAP
			end
		end
	end

	local isUniqueIdol     = self:IsUniqueIdol()
	local isAnyIdol        = self:IsAnyIdol()
	local isEnchantable    = self:IsEnchantableIdol()

	for si, sec in ipairs(sectionOrder) do
		-- Skip sections that are hidden for this item type
		local skip = false
		if isUniqueIdol and sec.label ~= "corruptedLabel" then skip = true end
		if isAnyIdol and not isEnchantable
			and (sec.label == "sealedLabel" or sec.label == "primordialLabel") then
			skip = true
		end
		if skip then
			-- Zero-out positions so hidden controls stay at top (invisible)
			for _, slotKey in ipairs(sec.slots) do
				self.editY[slotKey] = {}
			end
			self.editY[sec.label] = 0
		else
			self.editY[sec.label] = y
			y = y + LINE_H + GAP
			if sec.label == "corruptedLabel" then
				if not self.corrupted then
					self.editY.corrupted = {}
					self.editY.corrupted.add = y
				else
					layoutSlots(sec.slots)
				end
			else
				-- For idols, skip prefix2/suffix2 from layout
				if isAnyIdol and (sec.label == "prefixLabel" or sec.label == "suffixLabel") then
					local mainSlot = sec.slots[1]
					layoutSlots({mainSlot})
				else
					layoutSlots(sec.slots)
				end
			end
			y = y + GAP
		end
	end

	-- Store total content height for dynamic sizing
	self.editContentH = y + 50
end

-- Update mod line cache for a slot
function CraftingPopupClass:UpdateSlotModInfo(slotKey)
	local info = { count = 0, lines = {} }
	local st = self.affixState[slotKey]
	if st.modKey then
		local modKey = tostring(st.modKey) .. "_" .. tostring(st.tier)
		local mod = data.itemMods.Item and data.itemMods.Item[modKey]
		if not mod and data.modIdol and data.modIdol.flat then
			mod = data.modIdol.flat[modKey]
		end
		if mod then
			for k = 1, 10 do
				local line = mod[k]
				if line and type(line) == "string" then
					info.count = info.count + 1
					info.lines[info.count] = line
					if info.count >= MAX_MOD_LINES then break end
				end
			end
		end
	end
	self.slotModInfo[slotKey] = info
end

-- Update all value edit controls for a slot (call after tier change or affix selection)
function CraftingPopupClass:UpdateSlotValueEdits(slotKey)
	local info = self.slotModInfo[slotKey]
	local st = self.affixState[slotKey]
	for i = 1, MAX_MOD_LINES do
		local valCtrl = self.controls[slotKey .. "Val" .. i]
		if valCtrl and valCtrl.SetText then
			if i <= info.count and hasRange(info.lines[i]) then
				local range = st.ranges[i] or 128
				local val = computeModValue(info.lines[i], range)
				if val then
					valCtrl:SetText(formatModValue(info.lines[i], val))
				else
					valCtrl:SetText("")
				end
				-- Update numberInc based on precision
				local precision = getModPrecision(info.lines[i])
				if precision <= 1 then
					valCtrl.numberInc = 1
				elseif precision <= 10 then
					valCtrl.numberInc = 0.1
				else
					valCtrl.numberInc = 0.01
				end
			else
				valCtrl:SetText("")
			end
		end
	end
end

function CraftingPopupClass:BuildControls()
	local self_ref = self
	local controls = {}
	self.controls = controls

	-- ========================
	-- Tab buttons
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
	-- SELECT TAB
	-- ========================
	controls.typeLabel = new("LabelControl", {"TOPLEFT", self, "TOPLEFT"}, 15, 50, 0, 16, "^7Item Type:")
	controls.typeLabel.shown = function() return self_ref.currentTab == "select" end

	local typeDropList = {}
	for _, entry in ipairs(self.orderedTypeList) do
		t_insert(typeDropList, entry)
	end

	controls.typeDropdown = new("DropDownControl", {"LEFT", controls.typeLabel, "RIGHT"}, 5, 0, 220, 20,
		typeDropList, function(index, value)
			if value.isSeparator then
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

	-- Category tabs
	controls.catBasic = new("ButtonControl", {"TOPLEFT", self, "TOPLEFT"}, 15, 80, 80, 20, function()
		return self_ref.selectedBaseCategory == "basic" and "^7Basic" or "^8Basic"
	end, function()
		self_ref.selectedBaseCategory = "basic"
		self_ref:RefreshBaseList()
	end)
	controls.catBasic.shown = function() return self_ref.currentTab == "select" end
	controls.catBasic.locked = function() return self_ref.selectedBaseCategory == "basic" end

	controls.catUnique = new("ButtonControl", {"LEFT", controls.catBasic, "RIGHT"}, 5, 0, 80, 20, function()
		return colorCodes.UNIQUE .. "Unique"
	end, function()
		self_ref.selectedBaseCategory = "unique"
		self_ref:RefreshBaseList()
	end)
	controls.catUnique.shown = function() return self_ref.currentTab == "select" end
	controls.catUnique.locked = function() return self_ref.selectedBaseCategory == "unique" end

	controls.catSet = new("ButtonControl", {"LEFT", controls.catUnique, "RIGHT"}, 5, 0, 80, 20, function()
		return colorCodes.SET .. "Set"
	end, function()
		self_ref.selectedBaseCategory = "set"
		self_ref:RefreshBaseList()
	end)
	controls.catSet.shown = function() return self_ref.currentTab == "select" end
	controls.catSet.locked = function() return self_ref.selectedBaseCategory == "set" end

	-- Search bar
	controls.searchLabel = new("LabelControl", {"LEFT", controls.catSet, "RIGHT"}, 18, 0, 0, 14, "^8Search:")
	controls.searchLabel.shown = function() return self_ref.currentTab == "select" end
	controls.searchEdit = new("EditControl", {"LEFT", controls.searchLabel, "RIGHT"}, 5, 0, 200, 18, "", nil, nil, nil, function(buf)
		self_ref.searchText = buf
		self_ref:RefreshBaseList()
	end)
	controls.searchEdit.shown = function() return self_ref.currentTab == "select" end

	-- Column headers
	controls.colHeaderName = new("LabelControl", {"TOPLEFT", self, "TOPLEFT"}, 18, 106, 0, 14, "^8Item Name")
	controls.colHeaderName.shown = function() return self_ref.currentTab == "select" end
	controls.colHeaderType = new("LabelControl", {"TOPLEFT", self, "TOPLEFT"}, 498, 106, 0, 14, "^8Type")
	controls.colHeaderType.shown = function() return self_ref.currentTab == "select" end
	controls.colHeaderLv = new("LabelControl", {"TOPLEFT", self, "TOPLEFT"}, 658, 106, 0, 14, "^8Lv Req")
	controls.colHeaderLv.shown = function() return self_ref.currentTab == "select" end

	-- Base item list (scrollbar enabled)
	controls.baseList = new("ListControl", {"TOPLEFT", self, "TOPLEFT"}, 15, 122, 770, 420, 20, true, false, {})
	controls.baseList.shown = function() return self_ref.currentTab == "select" end
	controls.baseList.colList = {
		{ width = function() return 480 end },
		{ width = function() return 160 end },
		{ width = function() return 80 end },
	}
	controls.baseList.GetRowValue = function(control, column, index, entry)
		if entry.isImplicitRow then
			if column == 1 then
				return "^8    " .. (entry.implicitText or "")
			end
			return ""
		end
		if column == 1 then
			local colorCode = colorCodes[entry.rarity] or colorCodes.NORMAL
			return colorCode .. (entry.label or entry.name or "?")
		elseif column == 2 then
			return "^7" .. (entry.displayType or "")
		elseif column == 3 then
			local lvl = entry.base and entry.base.req and entry.base.req.level or 0
			return "^7" .. tostring(lvl)
		end
	end
	controls.baseList.OnSelClick = function(control, index, entry, doubleClick)
		if entry and entry.isImplicitRow and entry.parentEntry then
			-- Redirect to parent item
			for i = index - 1, 1, -1 do
				if control.list[i] == entry.parentEntry then
					control.selIndex = i
					control.selValue = entry.parentEntry
					entry = entry.parentEntry
					break
				end
			end
		end
		if doubleClick and entry and not entry.isImplicitRow then
			self_ref:SelectBase(entry)
		end
	end

	controls.selectBtn = new("ButtonControl", {"BOTTOMRIGHT", self, "BOTTOMRIGHT"}, -15, -15, 100, 28, "Select", function()
		local list = controls.baseList.list
		local idx = controls.baseList.selIndex
		local entry = list[idx]
		if entry and entry.isImplicitRow then
			for i = idx - 1, 1, -1 do
				if not list[i].isImplicitRow then
					entry = list[i]
					break
				end
			end
		end
		if entry and not entry.isImplicitRow then
			self_ref:SelectBase(entry)
		end
	end)
	controls.selectBtn.shown = function() return self_ref.currentTab == "select" end

	-- ========================
	-- EDIT TAB
	-- ========================
	controls.editItemName = new("LabelControl", {"TOPLEFT", self, "TOPLEFT"}, 15, 50, 0, 18, "")
	controls.editItemName.shown = function() return self_ref.currentTab == "edit" end
	controls.editItemName.label = function()
		if not self_ref.editItem then return "" end
		local item = self_ref.editItem
		local col
		if item.type and item.type:find("Idol") and item.rarity ~= "UNIQUE" then
			col = colorCodes.IDOL
		else
			col = colorCodes[item.rarity] or colorCodes.NORMAL
		end
		return col .. (item.title or item.namePrefix .. item.baseName .. item.nameSuffix)
	end

	controls.changeItemBtn = new("ButtonControl", {"LEFT", controls.editItemName, "LEFT"}, 0, 22, 100, 20, "Change Item", function()
		self_ref.currentTab = "select"
	end)
	controls.changeItemBtn.shown = function() return self_ref.currentTab == "edit" end

	controls.implicitLabel = new("LabelControl", {"TOPLEFT", self, "TOPLEFT"}, 15, 100, 0, 14, colorCodes.UNIQUE .. "IMPLICITS")
	controls.implicitLabel.shown = function() return self_ref.currentTab == "edit" end

	for i = 1, 20 do
		local key = "implicit" .. i
		controls[key] = new("LabelControl", {"TOPLEFT", self, "TOPLEFT"}, 25, 100 + i * 18, 0, 14, "")
		controls[key].shown = function()
			if self_ref.currentTab ~= "edit" or not self_ref.editItem then return false end
			local item = self_ref.editItem
			local implicitCount = #item.implicitModLines
			if i <= implicitCount then return true end
			local rarity = item.rarity
			if rarity == "UNIQUE" or rarity == "WWUNIQUE" or rarity == "SET" then
				local j = i - implicitCount
				return item.explicitModLines[j] ~= nil
			end
			return false
		end
		controls[key].label = function()
			if not self_ref.editItem then return "" end
			local item = self_ref.editItem
			local implicitCount = #item.implicitModLines
			if i <= implicitCount then
				return "^7" .. itemLib.formatModLine(item.implicitModLines[i])
			end
			local rarity = item.rarity
			if rarity == "UNIQUE" or rarity == "WWUNIQUE" or rarity == "SET" then
				local j = i - implicitCount
				if item.explicitModLines[j] then
					return "^7" .. itemLib.formatModLine(item.explicitModLines[j])
				end
			end
			return ""
		end
	end

	-- Affix section controls
	local affixSections = {
		{ key = "prefix",     label = "PREFIXES",        slots = {"prefix1", "prefix2"} },
		{ key = "suffix",     label = "SUFFIXES",        slots = {"suffix1", "suffix2"} },
		{ key = "sealed",     label = "SEALED AFFIX",    slots = {"sealed"} },
		{ key = "primordial", label = "PRIMORDIAL AFFIX", slots = {"primordial"} },
		{ key = "corrupted",  label = "CORRUPTED",       slots = {"corrupted"} },
	}

	-- Fixed-tier slots: primordial (always T8)
	local fixedTierSlots = { primordial = true }
	-- No T8 for all non-primordial slots (T8 is primordial only)
	local noT8Slots = { prefix1 = true, prefix2 = true, suffix1 = true, suffix2 = true, sealed = true, corrupted = true }

	-- Returns available affix count from a dropdown control's list (excludes placeholder entry)
	local function affixCount(ctrl)
		local list = ctrl and ctrl.list
		return list and #list > 1 and (#list - 1) or 0
	end

	-- Returns section label with dynamic available count appended
	local function sectionLabelWithCount(baseLabel, countCtrlKey)
		return function()
			local n = affixCount(self_ref.controls[countCtrlKey])
			return colorCodes.UNIQUE .. baseLabel .. " (" .. n .. ")"
		end
	end

	for _, section in ipairs(affixSections) do
		local labelKey = section.key .. "Label"
		local capturedSectionKey = section.key
		local capturedSectionLabel = section.label
		-- Map each section to its primary dropdown control key for count
		local countCtrlKeys = {
			prefix    = "prefix1Add",
			suffix    = "suffix1Add",
			sealed    = "sealedAdd",
			primordial = "primordialAdd",
			corrupted = "corruptedAdd",
		}
		local countCtrlKey = countCtrlKeys[capturedSectionKey]
		controls[labelKey] = new("LabelControl", {"TOPLEFT", self, "TOPLEFT"}, 15,
			function() return self_ref.editY[labelKey] or 200 end,
			0, 14, colorCodes.UNIQUE .. section.label)
		if capturedSectionKey == "sealed" then
			controls[labelKey].label = function()
				local base = self_ref:IsAnyIdol() and "ENCHANTED 1" or capturedSectionLabel
				local n = affixCount(self_ref.controls[countCtrlKey])
				return colorCodes.UNIQUE .. base .. " (" .. n .. ")"
			end
		elseif capturedSectionKey == "primordial" then
			controls[labelKey].label = function()
				local base = self_ref:IsAnyIdol() and "ENCHANTED 2" or capturedSectionLabel
				local n = affixCount(self_ref.controls[countCtrlKey])
				return colorCodes.UNIQUE .. base .. " (" .. n .. ")"
			end
		else
			controls[labelKey].label = sectionLabelWithCount(capturedSectionLabel, countCtrlKey)
		end
		controls[labelKey].shown = function()
			if self_ref.currentTab ~= "edit" then return false end
			-- Unique idols: only show corrupted section
			if capturedSectionKey ~= "corrupted" and self_ref:IsUniqueIdol() then return false end
			-- Enchanted slots: only for Grand/Large/Ornate/Huge/Adorned non-omen idols
			if (capturedSectionKey == "sealed" or capturedSectionKey == "primordial")
				and self_ref:IsAnyIdol() and not self_ref:IsEnchantableIdol() then
				return false
			end
			return true
		end

		-- Corrupted checkbox (next to corrupted label)
		if section.key == "corrupted" then
			controls.corruptedCheck = new("CheckBoxControl", {"TOPLEFT", self, "TOPLEFT"}, 150,
				function() return self_ref.editY[labelKey] or 200 end,
				18, "", function(state)
					self_ref.corrupted = state
					if not state then
						self_ref.affixState.corrupted.modKey = nil
						self_ref.affixState.corrupted.tier = 0
						self_ref.affixState.corrupted.ranges = {}
						self_ref:UpdateSlotModInfo("corrupted")
					end
					self_ref:RebuildEditItem()
				end)
			controls.corruptedCheck.shown = function() return self_ref.currentTab == "edit" end
		end

		for _, slotKey in ipairs(section.slots) do
			-- Mod line labels and value edits (up to MAX_MOD_LINES per slot)
			for li = 1, MAX_MOD_LINES do
				local lineKey = slotKey .. "Line" .. li
				local valKey = slotKey .. "Val" .. li

				-- Mod line label
				controls[lineKey] = new("LabelControl", {"TOPLEFT", self, "TOPLEFT"}, 25,
					function()
						local ey = self_ref.editY[slotKey]
						return ey and ey[li] or 0
					end, 0, 14, "")
				controls[lineKey].shown = function()
					if self_ref.currentTab ~= "edit" then return false end
					if not self_ref.affixState[slotKey].modKey then return false end
					if slotKey == "corrupted" and not self_ref.corrupted then return false end
					return li <= self_ref.slotModInfo[slotKey].count
				end
				controls[lineKey].label = function()
					local info = self_ref.slotModInfo[slotKey]
					if li > info.count then return "" end
					local line = info.lines[li]
					local st = self_ref.affixState[slotKey]
					local range = st.ranges[li] or 128
					local computed = itemLib.applyRange(line, range, nil, getRounding(line)) or line
					computed = computed:gsub("{rounding:%w+}", ""):gsub("{[^}]+}", "")
					local col = "^7"
					if st.tier >= 5 then col = colorCodes.EXALTED
					elseif st.tier >= 3 then col = colorCodes.RARE
					else col = colorCodes.MAGIC end
					return col .. computed
				end

				-- Value edit control (right side, after mod text)
				controls[valKey] = new("EditControl", {"TOPLEFT", self, "TOPLEFT"}, 500,
					function()
						local ey = self_ref.editY[slotKey]
						return ey and (ey[li] or 0) - 1 or 0
					end, 65, 18, "", nil, "^%-%d%.", nil,
					function(buf)
						if self_ref.rebuilding then return end
						local val = tonumber(buf)
						if not val then return end
						local info = self_ref.slotModInfo[slotKey]
						if li > info.count then return end
						local line = info.lines[li]
						-- Clamp to valid range
						val = clampModValue(line, val)
						local range = reverseModRange(line, val)
						self_ref.affixState[slotKey].ranges[li] = range
						-- Update display to clamped value
						local actual = computeModValue(line, range)
						if actual then
							self_ref.rebuilding = true
							controls[valKey]:SetText(formatModValue(line, actual))
							self_ref.rebuilding = false
						end
						self_ref:RebuildEditItem()
					end)
				controls[valKey].shown = function()
					if self_ref.currentTab ~= "edit" then return false end
					if not self_ref.affixState[slotKey].modKey then return false end
					if slotKey == "corrupted" and not self_ref.corrupted then return false end
					local info = self_ref.slotModInfo[slotKey]
					return li <= info.count and hasRange(info.lines[li])
				end
				controls[valKey].numberInc = 1
				-- Tooltip on the EditControl itself
				controls[valKey].tooltipFunc = function(tooltip, mode)
					if mode == "OUT" then return end
					tooltip:Clear()
					local info = self_ref.slotModInfo[slotKey]
					if li > info.count then return end
					local line = info.lines[li]
					local min, max = extractMinMax(line)
					if min and max then
						tooltip:AddLine(14, "^7Range: " .. tostring(min) .. " - " .. tostring(max))
					end
				end
				-- Propagate tooltip to +/- buttons
				controls[valKey].tooltipPropagated = true
			end

			-- Tier label (on first mod line)
			local tierLabelKey = slotKey .. "TierLabel"
			controls[tierLabelKey] = new("LabelControl", {"TOPLEFT", self, "TOPLEFT"}, 600,
				function()
					local ey = self_ref.editY[slotKey]
					return ey and ey[1] or 0
				end, 0, 14, "")
			controls[tierLabelKey].shown = function()
				if self_ref.currentTab ~= "edit" then return false end
				if slotKey == "corrupted" and not self_ref.corrupted then return false end
				return self_ref.affixState[slotKey].modKey ~= nil
			end
			controls[tierLabelKey].label = function()
				local st = self_ref.affixState[slotKey]
				return "^7T" .. tostring(st.tier + 1)
			end
			controls[tierLabelKey].tooltipFunc = function(tooltip, mode)
				if mode == "OUT" then return end
				self_ref:BuildTierTooltip(tooltip, slotKey)
			end

			-- Tier up button (+) - hidden for primordial (fixed T8)
			local tierUpKey = slotKey .. "TierUp"
			controls[tierUpKey] = new("ButtonControl", {"TOPLEFT", self, "TOPLEFT"}, 625,
				function()
					local ey = self_ref.editY[slotKey]
					return ey and ey[1] or 0
				end, 18, 18, "+", function()
					local st = self_ref.affixState[slotKey]
					if not st.modKey then return end
					local maxTier = self_ref:GetMaxTier(st.modKey)
					if noT8Slots[slotKey] then
						maxTier = m_min(maxTier, 6)
					end
					st.tier = st.tier + 1
					if st.tier > maxTier then st.tier = 0 end
					self_ref:UpdateSlotModInfo(slotKey)
					self_ref:UpdateSlotValueEdits(slotKey)
					self_ref:RebuildEditItem()
				end)
			controls[tierUpKey].shown = function()
				if self_ref.currentTab ~= "edit" then return false end
				if fixedTierSlots[slotKey] then return false end
				if slotKey == "corrupted" and not self_ref.corrupted then return false end
				return self_ref.affixState[slotKey].modKey ~= nil
			end
			controls[tierUpKey].tooltipFunc = function(tooltip, mode)
				if mode == "OUT" then return end
				self_ref:BuildTierTooltip(tooltip, slotKey)
			end

			-- Tier down button (-)
			local tierDownKey = slotKey .. "TierDown"
			controls[tierDownKey] = new("ButtonControl", {"TOPLEFT", self, "TOPLEFT"}, 645,
				function()
					local ey = self_ref.editY[slotKey]
					return ey and ey[1] or 0
				end, 18, 18, "-", function()
					local st = self_ref.affixState[slotKey]
					if not st.modKey then return end
					local maxTier = self_ref:GetMaxTier(st.modKey)
					if noT8Slots[slotKey] then
						maxTier = m_min(maxTier, 6)
					end
					st.tier = st.tier - 1
					if st.tier < 0 then st.tier = maxTier end
					self_ref:UpdateSlotModInfo(slotKey)
					self_ref:UpdateSlotValueEdits(slotKey)
					self_ref:RebuildEditItem()
				end)
			controls[tierDownKey].shown = function()
				if self_ref.currentTab ~= "edit" then return false end
				if fixedTierSlots[slotKey] then return false end
				if slotKey == "corrupted" and not self_ref.corrupted then return false end
				return self_ref.affixState[slotKey].modKey ~= nil
			end
			controls[tierDownKey].tooltipFunc = function(tooltip, mode)
				if mode == "OUT" then return end
				self_ref:BuildTierTooltip(tooltip, slotKey)
			end

			-- Remove button (x)
			local removeKey = slotKey .. "Remove"
			controls[removeKey] = new("ButtonControl", {"TOPLEFT", self, "TOPLEFT"}, 670,
				function()
					local ey = self_ref.editY[slotKey]
					return ey and ey[1] or 0
				end, 18, 18, "x", function()
					self_ref.affixState[slotKey].modKey = nil
					self_ref.affixState[slotKey].tier = (slotKey == "primordial") and 7 or 0
					self_ref.affixState[slotKey].ranges = {}
					self_ref:UpdateSlotModInfo(slotKey)
					self_ref:RebuildEditItem()
				end)
			controls[removeKey].shown = function()
				if self_ref.currentTab ~= "edit" then return false end
				if slotKey == "corrupted" and not self_ref.corrupted then return false end
				return self_ref.affixState[slotKey].modKey ~= nil
			end

			-- Add dropdown (shown when no affix selected)
			local addKey = slotKey .. "Add"
			controls[addKey] = new("DropDownControl", {"TOPLEFT", self, "TOPLEFT"}, 25,
				function()
					local ey = self_ref.editY[slotKey]
					return ey and ey.add or 0
				end, 400, 18,
				{}, function(index, value)
					if value and value.statOrderKey then
						local st = self_ref.affixState[slotKey]
						st.modKey = value.statOrderKey
						-- Default to T5 (tier index 4); cap at maxTier if lower
						local maxT = value.maxTier or 0
						st.tier = m_min(4, maxT)
						-- Sealed and corrupted: cap at tier 6 (no T8)
						if noT8Slots[slotKey] and st.tier > 6 then
							st.tier = 6
						end
						st.ranges = {}
						-- Default all ranges to 128
						self_ref:UpdateSlotModInfo(slotKey)
						local info = self_ref.slotModInfo[slotKey]
						for i = 1, info.count do
							st.ranges[i] = 128
						end
						self_ref:UpdateSlotValueEdits(slotKey)
						self_ref:RebuildEditItem()
					end
				end)
			controls[addKey].shown = function()
				if self_ref.currentTab ~= "edit" then return false end
				if self_ref.affixState[slotKey].modKey ~= nil then return false end
				-- Unique idols can only have corrupted affix; hide all other slots
				if slotKey ~= "corrupted" and self_ref:IsUniqueIdol() then return false end
				-- Idols have only 1 prefix and 1 suffix (no prefix2/suffix2)
				if (slotKey == "prefix2" or slotKey == "suffix2") and self_ref:IsAnyIdol() then return false end
				-- Enchanted slots only for Grand/Large/Ornate/Huge/Adorned non-omen idols
				if (slotKey == "sealed" or slotKey == "primordial")
					and self_ref:IsAnyIdol() and not self_ref:IsEnchantableIdol() then
					return false
				end
				if slotKey == "corrupted" then
					return self_ref.corrupted
				end
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

	-- Save / Cancel
	controls.saveBtn = new("ButtonControl", {"BOTTOMRIGHT", self, "BOTTOMRIGHT"}, -15, -15, 100, 28, "Save", function()
		self_ref:SaveItem()
	end)
	controls.saveBtn.shown = function() return self_ref.currentTab == "edit" and self_ref.editItem ~= nil end

	controls.cancelBtn = new("ButtonControl", {"BOTTOMRIGHT", self, "BOTTOMRIGHT"}, -125, -15, 100, 28, "Cancel", function()
		self_ref:Close()
	end)

	-- Anchoring
	for id, control in pairs(self.controls) do
		if not control.anchor.point then
			control:SetAnchor("TOP", self, "TOP")
		elseif not control.anchor.other then
			control.anchor.other = self
		elseif type(control.anchor.other) ~= "table" then
			control.anchor.other = self.controls[control.anchor.other]
		end
	end

	self:RefreshBaseList()
	self:RefreshAffixDropdowns()
end

-- Refresh base item list
function CraftingPopupClass:RefreshBaseList()
	local typeName = self:GetSelectedTypeName()
	if not typeName then return end

	local list = {}

	if self.selectedBaseCategory == "basic" then
		local bases = self.build.data.itemBaseLists[typeName]
		if bases then
			local myClassBit = self:GetCurrentClassReqBit()
			for _, entry in ipairs(bases) do
				local classReq = entry.base.classReq or 0
				-- Skip idol bases restricted to a different class
				if classReq == 0 or myClassBit == 0 or bit.band(classReq, myClassBit) ~= 0 then
					t_insert(list, {
						label = entry.name, name = entry.name, base = entry.base,
						type = typeName, displayType = entry.base.type or "",
						rarity = "NORMAL", category = "basic",
					})
				end
			end
		end
		table.sort(list, function(a, b)
			local lvlA = a.base and a.base.req and a.base.req.level or 0
			local lvlB = b.base and b.base.req and b.base.req.level or 0
			if lvlA == lvlB then return a.name < b.name end
			return lvlA < lvlB
		end)
	elseif self.selectedBaseCategory == "unique" then
		local bases = self.build.data.itemBaseLists[typeName]
		if bases then
			local myClassBit = self:GetCurrentClassReqBit()
			for uid, unique in pairs(self.build.data.uniques) do
				for _, baseEntry in ipairs(bases) do
					if baseEntry.base.baseTypeID == unique.baseTypeID and
					   baseEntry.base.subTypeID == unique.subTypeID then
						local classReq = baseEntry.base.classReq or 0
						if classReq == 0 or myClassBit == 0 or bit.band(classReq, myClassBit) ~= 0 then
							local isWW = unique.name and unique.name:find("an Erased ") and true or false
							t_insert(list, {
								label = unique.name, name = unique.name,
								base = baseEntry.base, baseName = baseEntry.name,
								type = typeName, displayType = baseEntry.base.type or "",
								rarity = isWW and "WWUNIQUE" or "UNIQUE",
								category = isWW and "ww" or "unique",
								uniqueData = unique, uniqueID = uid,
							})
						end
						break
					end
				end
			end
			table.sort(list, function(a, b) return a.label < b.label end)
		end
	elseif self.selectedBaseCategory == "set" then
		local bases = self.build.data.itemBaseLists[typeName]
		if bases then
			local myClassBit = self:GetCurrentClassReqBit()
			for sid, setItem in pairs(self.setItems) do
				for _, baseEntry in ipairs(bases) do
					if baseEntry.base.baseTypeID == setItem.baseTypeID and
					   baseEntry.base.subTypeID == setItem.subTypeID then
						local classReq = baseEntry.base.classReq or 0
						if classReq == 0 or myClassBit == 0 or bit.band(classReq, myClassBit) ~= 0 then
							t_insert(list, {
								label = setItem.name, name = setItem.name,
								base = baseEntry.base, baseName = baseEntry.name,
								type = typeName, displayType = baseEntry.base.type or "",
								rarity = "SET", category = "set",
								setData = setItem, setID = sid,
							})
						end
						break
					end
				end
			end
			table.sort(list, function(a, b) return a.label < b.label end)
		end
	end

	-- Apply search filter
	local query = (self.searchText or ""):lower():gsub("^%s*(.-)%s*$", "%1")
	if query ~= "" then
		local filtered = {}
		for _, entry in ipairs(list) do
			local matched = false
			-- Match item name
			if (entry.label or entry.name or ""):lower():find(query, 1, true) then
				matched = true
			end
			-- WW alias: "ww", "weaver", "weavers will", "weaver's will"
			if not matched and (entry.rarity == "WWUNIQUE" or entry.rarity == "WWLEGENDARY") then
				if query == "ww" or ("weavers will"):find(query, 1, true) or ("weaver's will"):find(query, 1, true) then
					matched = true
				end
			end
			-- Match basic item implicit texts
			if not matched and entry.category == "basic" and entry.base and entry.base.implicits then
				for _, implText in ipairs(entry.base.implicits) do
					local cleaned = cleanImplicitText(implText)
					if cleaned and cleaned:lower():find(query, 1, true) then matched = true; break end
				end
			end
			-- Match unique/ww mod texts and affix field
			if not matched then
				local modData = (entry.category == "unique" or entry.category == "ww") and entry.uniqueData
				             or (entry.category == "set" and entry.setData)
				if modData then
					if modData.mods then
						for _, modText in ipairs(modData.mods) do
							if modText:lower():find(query, 1, true) then matched = true; break end
						end
					end
					-- Set bonus effects
					if not matched and modData.set then
						if modData.set.name and modData.set.name:lower():find(query, 1, true) then
							matched = true
						end
						if not matched and modData.set.bonus then
							for _, bonusText in pairs(modData.set.bonus) do
								if tostring(bonusText):lower():find(query, 1, true) then matched = true; break end
							end
						end
					end
				end
			end
			if matched then
				t_insert(filtered, entry)
			end
		end
		list = filtered
	end

	-- Insert implicit sub-rows (and unique/set mods for idols)
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
		-- For unique/set idols show their mods as sub-rows (idols have no base implicits)
		if entry.type and entry.type:find("Idol") then
			local modData = (entry.category == "unique" and entry.uniqueData)
			             or (entry.category == "set" and entry.setData)
			if modData and modData.mods then
				for _, modText in ipairs(modData.mods) do
					local text = cleanImplicitText(modText)
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
	end

	self.controls.baseList.list = expandedList
	self.controls.baseList.selIndex = 1
end

-- Select a base item
function CraftingPopupClass:SelectBase(entry)
	if not entry or entry.isImplicitRow then return end

	for key, st in pairs(self.affixState) do
		st.modKey = nil
		st.tier = (key == "primordial") and 7 or 0
		st.ranges = {}
	end
	self.corrupted = false
	self.controls.corruptedCheck.state = false

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
		if entry.uniqueData.mods then
			for i, modText in ipairs(entry.uniqueData.mods) do
				local rollId = entry.uniqueData.rollIds and entry.uniqueData.rollIds[i]
				local modLine = { line = modText }
				if rollId then modLine.range = 128 end
				t_insert(item.explicitModLines, modLine)
			end
		end
	elseif entry.category == "ww" then
		item.rarity = "WWUNIQUE"
		item.title = entry.uniqueData.name
		item.uniqueID = entry.uniqueID
		if entry.uniqueData.mods then
			for i, modText in ipairs(entry.uniqueData.mods) do
				local rollId = entry.uniqueData.rollIds and entry.uniqueData.rollIds[i]
				local modLine = { line = modText }
				if rollId then modLine.range = 128 end
				t_insert(item.explicitModLines, modLine)
			end
		end
	elseif entry.category == "set" then
		item.rarity = "SET"
		item.title = entry.setData.name
		item.setID = entry.setID
		if entry.setData.mods then
			for i, modText in ipairs(entry.setData.mods) do
				local rollId = entry.setData.rollIds and entry.setData.rollIds[i]
				local modLine = { line = modText }
				if rollId then modLine.range = 128 end
				t_insert(item.explicitModLines, modLine)
			end
		end
	else
		item.rarity = "RARE"
		item.title = "New Item"
	end

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

	-- Update mod info for all slots
	for _, k in ipairs({"prefix1","prefix2","suffix1","suffix2","sealed","primordial","corrupted"}) do
		self:UpdateSlotModInfo(k)
	end
	self:RecalcEditLayout()
	self:RefreshAffixDropdowns()
end

-- Refresh affix dropdown lists
function CraftingPopupClass:RefreshAffixDropdowns()
	if not self.editItem then return end

	-- Route idol items to dedicated handler
	if self:IsAnyIdol() and data.modIdol and next(data.modIdol) then
		self:RefreshIdolAffixDropdowns()
		return
	end

	local itemMods = self.editItem.affixes or data.itemMods.Item
	if not itemMods then return end

	local wwPool = nil
	local wwClassBit = 0
	if self:IsWWItem() then
		local bt = self.editBaseEntry and self.editBaseEntry.base and self.editBaseEntry.base.baseTypeID
		wwPool = bt and data.wwMods and data.wwMods[tostring(bt)]
		wwClassBit = self:GetWWClassBit()
	end
	-- classSpecificity bit for non-WW items (game encoding: Primalist=2,Mage=4,Sentinel=8,Acolyte=16,Rogue=32)
	local playerCsBit = self:GetCurrentClassReqBit() * 2

	local prefixGroups = {}
	local suffixGroups = {}

	for modId, mod in pairs(itemMods) do
		if mod.statOrderKey then
			if wwPool then
				local cs = wwPool[tostring(mod.statOrderKey)]
				if cs == nil then goto continue end
				if cs ~= 0 and wwClassBit ~= 0 and bit.band(cs, wwClassBit) == 0 then goto continue end
			else
				-- Filter class-specific affixes for non-WW items
				local cs = mod.classSpecificity or 0
				if cs ~= 0 and playerCsBit ~= 0 and bit.band(cs, playerCsBit) == 0 then goto continue end
			end
			local groups = mod.type == "Prefix" and prefixGroups or (mod.type == "Suffix" and suffixGroups or nil)
			if groups then
				if not groups[mod.statOrderKey] then
					local labelParts = {}
					for k = 1, 10 do
						if mod[k] then t_insert(labelParts, mod[k]) end
					end
					local label = table.concat(labelParts, " / ")
					label = label:gsub("{rounding:%w+}", ""):gsub("{[^}]+}", "")
					groups[mod.statOrderKey] = {
						label = label,
						statOrderKey = mod.statOrderKey,
						affix = mod.affix,
						type = mod.type,
						maxTier = mod.tier or 0,
					}
				else
					local g = groups[mod.statOrderKey]
					if mod.tier and mod.tier > g.maxTier then g.maxTier = mod.tier end
				end
			end
		end
		::continue::
	end

	local prefixList = { { label = "-- Select Prefix --" } }
	local suffixList = { { label = "-- Select Suffix --" } }
	local sealedList = { { label = "-- Select Affix --" } }
	local primordialList = { { label = "-- Select T8 Affix --" } }

	for _, g in pairs(prefixGroups) do
		t_insert(prefixList, g)
		t_insert(sealedList, { label = g.label, statOrderKey = g.statOrderKey, affix = g.affix, type = g.type, maxTier = m_min(g.maxTier, 6) })
		-- Only add to primordial if T8 (tier 7) exists
		if g.maxTier >= 7 then
			-- Build T8 label from tier 7 data
			local t8Key = tostring(g.statOrderKey) .. "_7"
			local t8Mod = itemMods[t8Key]
			if t8Mod then
				local t8Parts = {}
				for k = 1, 10 do
					if t8Mod[k] then t_insert(t8Parts, t8Mod[k]) end
				end
				local t8Label = table.concat(t8Parts, " / ")
				t8Label = t8Label:gsub("{rounding:%w+}", ""):gsub("{[^}]+}", "")
				t_insert(primordialList, { label = t8Label, statOrderKey = g.statOrderKey, affix = g.affix, type = g.type, maxTier = 7 })
			end
		end
	end
	for _, g in pairs(suffixGroups) do
		t_insert(suffixList, g)
		t_insert(sealedList, { label = g.label, statOrderKey = g.statOrderKey, affix = g.affix, type = g.type, maxTier = m_min(g.maxTier, 6) })
		if g.maxTier >= 7 then
			local t8Key = tostring(g.statOrderKey) .. "_7"
			local t8Mod = itemMods[t8Key]
			if t8Mod then
				local t8Parts = {}
				for k = 1, 10 do
					if t8Mod[k] then t_insert(t8Parts, t8Mod[k]) end
				end
				local t8Label = table.concat(t8Parts, " / ")
				t8Label = t8Label:gsub("{rounding:%w+}", ""):gsub("{[^}]+}", "")
				t_insert(primordialList, { label = t8Label, statOrderKey = g.statOrderKey, affix = g.affix, type = g.type, maxTier = 7 })
			end
		end
	end

	local function sortByLabel(a, b)
		if not a.statOrderKey then return true end
		if not b.statOrderKey then return false end
		return (a.label or "") < (b.label or "")
	end
	table.sort(prefixList, sortByLabel)
	table.sort(suffixList, sortByLabel)
	table.sort(sealedList, sortByLabel)
	table.sort(primordialList, sortByLabel)

	local function filterExclusions(list, excludeKeys)
		local filtered = { list[1] }
		for i = 2, #list do
			local excluded = false
			for _, exKey in ipairs(excludeKeys) do
				if list[i].statOrderKey == exKey then excluded = true; break end
			end
			if not excluded then t_insert(filtered, list[i]) end
		end
		return filtered
	end

	local p1Key = self.affixState.prefix1.modKey
	local p2Key = self.affixState.prefix2.modKey
	local s1Key = self.affixState.suffix1.modKey
	local s2Key = self.affixState.suffix2.modKey
	local prKey = self.affixState.primordial.modKey

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

	local primExclude = {}
	if p1Key then t_insert(primExclude, p1Key) end
	if p2Key then t_insert(primExclude, p2Key) end
	if s1Key then t_insert(primExclude, s1Key) end
	if s2Key then t_insert(primExclude, s2Key) end
	self.controls.primordialAdd.list = filterExclusions(primordialList, primExclude)

	-- Corrupted affix dropdown: all prefixes + suffixes (no T8 filter)
	local corruptedList = { { label = "-- Select Corrupted Affix --" } }
	for _, g in pairs(prefixGroups) do
		-- Cap maxTier to 6 for corrupted (no T8)
		local mt = m_min(g.maxTier, 6)
		t_insert(corruptedList, { label = g.label, statOrderKey = g.statOrderKey, affix = g.affix, type = g.type, maxTier = mt })
	end
	for _, g in pairs(suffixGroups) do
		local mt = m_min(g.maxTier, 6)
		t_insert(corruptedList, { label = g.label, statOrderKey = g.statOrderKey, affix = g.affix, type = g.type, maxTier = mt })
	end
	table.sort(corruptedList, sortByLabel)
	self.controls.corruptedAdd.list = corruptedList

	-- Enforce T8 exclusion: cap non-primordial slots at T7 (tier 6)
	for _, slotKey in ipairs({"prefix1","prefix2","suffix1","suffix2","sealed","corrupted"}) do
		local st = self.affixState[slotKey]
		if st.modKey and st.tier >= 7 then
			st.tier = 6
			self:UpdateSlotModInfo(slotKey)
			self:UpdateSlotValueEdits(slotKey)
		end
	end
end

-- Refresh affix dropdowns for idol items using ModIdol data
function CraftingPopupClass:RefreshIdolAffixDropdowns()
	local baseTypeID = self.editBaseEntry and self.editBaseEntry.base and self.editBaseEntry.base.baseTypeID
	if not baseTypeID then return end

	local general   = data.modIdol.general   or {}
	local enchanted = data.modIdol.enchanted  or {}
	local corrupted = data.modIdol.corrupted  or {}
	local weaver    = self:IsWeaverIdol() and (data.modIdol.weaver or {}) or {}

	local function buildLabel(mod)
		local parts = {}
		for k = 1, 10 do if mod[k] then t_insert(parts, mod[k]) end end
		local s = table.concat(parts, " / ")
		return s:gsub("{rounding:%w+}", ""):gsub("{[^}]+}", "")
	end

	-- ModIdol classSpecificity encoding:
	--   bit 0 (value 1): "available on universal/small idols for ALL classes" flag
	--   bits 1-5 (values 2,4,8,16,32): class bits — 2=Primalist,4=Mage,8=Sentinel,16=Acolyte,32=Rogue
	-- idol classReq (from bases) uses LEB encoding: 1=Primalist,2=Mage,4=Sentinel,8=Acolyte,16=Rogue
	-- Conversion: game_cs_bit = idol_classReq * 2
	local idolClassReq = self.editBaseEntry and self.editBaseEntry.base and self.editBaseEntry.base.classReq or 0
	local idolCsBit = idolClassReq * 2  -- 0 for universal idols (bt=25-28)

	local isOmen = self:IsOmenIdol()
	-- Large idol baseTypeIDs: 29=Grand, 30=Large, 31=Ornate, 32=Huge, 33=Adorned
	local LARGE_IDS = { [29]=true, [30]=true, [31]=true, [32]=true, [33]=true }

	local function canRollOnIdol(mod)
		if not mod.canRollOn then return false end
		local btMatch = false
		for _, bt in ipairs(mod.canRollOn) do
			if bt == baseTypeID then btMatch = true; break end
		end
		if not btMatch then return false end
		local cs = mod.classSpecificity or 0
		if idolClassReq == 0 then
			-- Universal idol (Small/Minor/Humble/Stout): bit 0 means available to all classes
			return cs == 0 or bit.band(cs, 1) ~= 0
		else
			-- Class-specific large idol: strip bit 0, then filter by class
			local classMask = bit.band(cs, 0xFFFFFFFE)
			return classMask == 0 or idolCsBit == 0 or bit.band(classMask, idolCsBit) ~= 0
		end
	end

	-- prefix / suffix from general section (+ weaver extras if applicable)
	local prefixList = { { label = "-- Select Prefix --" } }
	local suffixList = { { label = "-- Select Suffix --" } }
	for _, pool in ipairs({ general, weaver }) do
		for _, mod in pairs(pool) do
			if mod.statOrderKey and canRollOnIdol(mod) then
				local entry = { label = buildLabel(mod), statOrderKey = mod.statOrderKey, affix = mod.affix, type = mod.type, maxTier = 0 }
				if mod.type == "Prefix" then
					t_insert(prefixList, entry)
				elseif mod.type == "Suffix" then
					t_insert(suffixList, entry)
				end
			end
		end
	end

	-- enchanted affixes (sealed slot = ENCHANTED 1, primordial slot = ENCHANTED 2)
	local enchantedList = { { label = "-- Select Enchanted --" } }
	for _, mod in pairs(enchanted) do
		if mod.statOrderKey and canRollOnIdol(mod) then
			t_insert(enchantedList, { label = buildLabel(mod), statOrderKey = mod.statOrderKey, affix = mod.affix, type = mod.type, maxTier = 0 })
		end
	end

	-- corrupted affixes: omen shows all corrupted from any large idol (bt 29-33); class shows bt-exact match
	local corruptedList = { { label = "-- Select Corrupted Affix --" } }
	for _, mod in pairs(corrupted) do
		local show = false
		if isOmen then
			if mod.canRollOn then
				for _, bt in ipairs(mod.canRollOn) do
					if LARGE_IDS[bt] then show = true; break end
				end
			end
		else
			show = mod.statOrderKey and canRollOnIdol(mod)
		end
		if show and mod.statOrderKey then
			t_insert(corruptedList, { label = buildLabel(mod), statOrderKey = mod.statOrderKey, affix = mod.affix, type = mod.type, maxTier = 0 })
		end
	end

	local function sortByLabel(a, b)
		if not a.statOrderKey then return true end
		if not b.statOrderKey then return false end
		return (a.label or "") < (b.label or "")
	end
	table.sort(prefixList, sortByLabel)
	table.sort(suffixList, sortByLabel)
	table.sort(enchantedList, sortByLabel)
	table.sort(corruptedList, sortByLabel)

	local function filterExclusions(list, excludeKeys)
		local filtered = { list[1] }
		for i = 2, #list do
			local excluded = false
			for _, exKey in ipairs(excludeKeys) do
				if list[i].statOrderKey == exKey then excluded = true; break end
			end
			if not excluded then t_insert(filtered, list[i]) end
		end
		return filtered
	end

	self.controls.prefix1Add.list = prefixList
	self.controls.suffix1Add.list = suffixList
	-- sealed/primordial controls are reused as enchanted 1/2
	self.controls.sealedAdd.list    = filterExclusions(enchantedList, self.affixState.primordial.modKey and {self.affixState.primordial.modKey} or {})
	self.controls.primordialAdd.list = filterExclusions(enchantedList, self.affixState.sealed.modKey and {self.affixState.sealed.modKey} or {})
	self.controls.corruptedAdd.list = corruptedList

	-- Cap all idol slot tiers to 0 (all idol affixes are T1 only)
	for _, slotKey in ipairs({"prefix1","suffix1","sealed","primordial","corrupted"}) do
		local st = self.affixState[slotKey]
		if st.modKey and st.tier ~= 0 then
			st.tier = 0
			self:UpdateSlotModInfo(slotKey)
			self:UpdateSlotValueEdits(slotKey)
		end
	end
end

-- Build tier tooltip
function CraftingPopupClass:BuildTierTooltip(tooltip, slotKey)
	tooltip:Clear()
	local st = self.affixState[slotKey]
	if not st or not st.modKey then return end
	local function getMod(key)
		local m = data.itemMods.Item and data.itemMods.Item[key]
		if not m and data.modIdol and data.modIdol.flat then m = data.modIdol.flat[key] end
		return m
	end

	local baseMod = getMod(tostring(st.modKey) .. "_0")
	if baseMod then
		tooltip:AddLine(16, colorCodes.UNIQUE .. (baseMod.affix or "Affix"))
		tooltip:AddSeparator(10)
	end

	local maxTierShow = 7
	if slotKey == "sealed" or slotKey == "corrupted" then maxTierShow = 6 end
	if self:IsAnyIdol() then maxTierShow = 0 end
	for tier = 0, maxTierShow do
		local key = tostring(st.modKey) .. "_" .. tostring(tier)
		local mod = getMod(key)
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
end

-- Build affix tooltip for dropdown
function CraftingPopupClass:BuildAffixTooltip(tooltip, statOrderKey)
	local function getMod(key)
		local m = data.itemMods.Item and data.itemMods.Item[key]
		if not m and data.modIdol and data.modIdol.flat then m = data.modIdol.flat[key] end
		return m
	end
	local baseMod = getMod(tostring(statOrderKey) .. "_0")
	if not baseMod then return end
	tooltip:AddLine(16, colorCodes.UNIQUE .. (baseMod.affix or "Affix"))
	tooltip:AddSeparator(10)
	local maxTierTooltip = self:IsAnyIdol() and 0 or 7
	for tier = 0, maxTierTooltip do
		local key = tostring(statOrderKey) .. "_" .. tostring(tier)
		local mod = getMod(key)
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

-- Returns true when the current edit item is a unique idol
function CraftingPopupClass:IsUniqueIdol()
	return self.editBaseEntry
		and self.editBaseEntry.category == "unique"
		and self.editBaseEntry.type
		and self.editBaseEntry.type:find("Idol")
		and true or false
end

-- Returns true when any idol type is being edited
function CraftingPopupClass:IsAnyIdol()
	return self.editBaseEntry
		and self.editBaseEntry.type
		and self.editBaseEntry.type:find("Idol")
		and true or false
end

-- Returns true when the idol is a Heretical variant (enchanted affixes only on heretical)
-- Grand/Large/Ornate/Huge(29-32): heretical = subTypeID 5-9
-- Adorned(33): heretical = subTypeID 7-11 (5,6 are Silver/Volcano, hidden)
function CraftingPopupClass:IsEnchantableIdol()
	if not self.editBaseEntry or not self.editBaseEntry.base then return false end
	local bt = self.editBaseEntry.base.baseTypeID
	local st = self.editBaseEntry.base.subTypeID or 0
	if bt == nil or bt < 29 then return false end
	if bt == 33 then return st >= 7 and st <= 11 end
	return st >= 5 and st <= 9
end

-- Returns true when the current idol is an Omen variant
-- Only Grand(29) and Large(30) have omen subtypes (subTypeID 10-14)
function CraftingPopupClass:IsOmenIdol()
	if not self.editBaseEntry or not self.editBaseEntry.base then return false end
	local bt = self.editBaseEntry.base.baseTypeID
	local st = self.editBaseEntry.base.subTypeID or 0
	return (bt == 29 or bt == 30) and st >= 10 and st <= 14
end

-- Returns true when the current idol is a Weaver variant
-- Small(25): subTypeID==2, Minor/Humble/Stout(26-28): subTypeID==1
function CraftingPopupClass:IsWeaverIdol()
	if not self.editBaseEntry or not self.editBaseEntry.base then return false end
	local bt = self.editBaseEntry.base.baseTypeID
	local st = self.editBaseEntry.base.subTypeID
	if bt == 25 then return st == 2 end
	if bt == 26 or bt == 27 or bt == 28 then return st == 1 end
	return false
end

-- Returns the classReq bitmask for the current character class (0 if unknown)
local CLASS_REQ_BITS = { Primalist=1, Mage=2, Sentinel=4, Acolyte=8, Rogue=16 }
function CraftingPopupClass:GetCurrentClassReqBit()
	local spec = self.build and self.build.spec
	local name = spec and spec.curClassName
	return CLASS_REQ_BITS[name] or 0
end

-- Returns true when the current item has a WW rarity (WWUNIQUE or WWLEGENDARY)
function CraftingPopupClass:IsWWItem()
	local r = self.editItem and self.editItem.rarity
	return r == "WWUNIQUE" or r == "WWLEGENDARY"
end

-- Returns the WW class specificity bit for filtering the WW affix pool.
-- WW uses game encoding: Primalist=2, Mage=4, Sentinel=8, Acolyte=16, Rogue=32.
-- Falls back to current build class if item name has no class keyword.
local WW_CLASS_BITS = { Primalist=2, Mage=4, Sentinel=8, Acolyte=16, Rogue=32 }
function CraftingPopupClass:GetWWClassBit()
	local title = self.editItem and (self.editItem.title or self.editItem.name) or ""
	for class, bit in pairs(WW_CLASS_BITS) do
		if title:find(class) then return bit end
	end
	local spec = self.build and self.build.spec
	local name = spec and spec.curClassName
	return WW_CLASS_BITS[name] or 0
end

-- Rebuild edit item from current affix state
function CraftingPopupClass:RebuildEditItem()
	if not self.editItem then return end

	self.rebuilding = true

	local item = self.editItem
	local itemMods = data.itemMods.Item

	wipeTable(item.explicitModLines)
	wipeTable(item.prefixes)
	wipeTable(item.suffixes)
	item.namePrefix = ""
	item.nameSuffix = ""

	-- Re-add unique/set mods
	if self.editBaseEntry and self.editBaseEntry.category == "unique" and self.editBaseEntry.uniqueData then
		for i, modText in ipairs(self.editBaseEntry.uniqueData.mods) do
			local rollId = self.editBaseEntry.uniqueData.rollIds and self.editBaseEntry.uniqueData.rollIds[i]
			local modLine = { line = modText }
			if rollId then modLine.range = 128 end
			t_insert(item.explicitModLines, modLine)
		end
	elseif self.editBaseEntry and self.editBaseEntry.category == "set" and self.editBaseEntry.setData then
		for i, modText in ipairs(self.editBaseEntry.setData.mods) do
			local rollId = self.editBaseEntry.setData.rollIds and self.editBaseEntry.setData.rollIds[i]
			local modLine = { line = modText }
			if rollId then modLine.range = 128 end
			t_insert(item.explicitModLines, modLine)
		end
	end

	local prefixIdx = 0
	local suffixIdx = 0
	local tierSum = 0
	local hasAffix = false

	local slotOrder = {"prefix1", "prefix2", "suffix1", "suffix2", "sealed", "primordial"}
	for _, slotKey in ipairs(slotOrder) do
		local st = self.affixState[slotKey]
		if st.modKey then
			hasAffix = true
			tierSum = tierSum + st.tier
			local modKey = tostring(st.modKey) .. "_" .. tostring(st.tier)
			local mod = itemMods[modKey]
			if not mod and data.modIdol and data.modIdol.flat then
				mod = data.modIdol.flat[modKey]
			end
			if mod then
				if mod.type == "Prefix" then
					prefixIdx = prefixIdx + 1
					item.prefixes[prefixIdx] = { modId = modKey, range = st.ranges[1] or 128 }
					local pfxName = mod.affix
					if pfxName and pfxName ~= "UNKNOWN" and prefixIdx == 1 then
						item.namePrefix = pfxName .. " "
					end
				elseif mod.type == "Suffix" then
					suffixIdx = suffixIdx + 1
					item.suffixes[suffixIdx] = { modId = modKey, range = st.ranges[1] or 128 }
					local sfxName = mod.affix
					if sfxName and sfxName ~= "UNKNOWN" and suffixIdx == 1 then
						item.nameSuffix = " " .. sfxName
					end
				end

				local modScalar = 1 + (item.base.affixEffectModifier or 0)
				if mod.standardAffixEffectModifier then
					modScalar = modScalar - mod.standardAffixEffectModifier
				end
				local lineIdx = 0
				for k = 1, 10 do
					local line = mod[k]
					if line and type(line) == "string" then
						lineIdx = lineIdx + 1
						t_insert(item.explicitModLines, {
							line = line,
							range = st.ranges[lineIdx] or 128,
							valueScalar = modScalar,
						})
					end
				end
			end
		end
	end

	-- Update rarity
	if self.editBaseEntry and self.editBaseEntry.category == "basic" then
		item.rarity = getRarityForTierSum(tierSum, hasAffix)
		if item.rarity == "RARE" or item.rarity == "EXALTED" then
			item.title = item.title or "New Item"
		else
			item.title = nil
		end
	elseif self.editBaseEntry and self.editBaseEntry.category == "unique" and hasAffix then
		item.rarity = "LEGENDARY"
	elseif self.editBaseEntry and self.editBaseEntry.category == "ww" then
		item.rarity = hasAffix and "WWLEGENDARY" or "WWUNIQUE"
	end

	-- Add corrupted affix mod lines
	if self.corrupted then
		local ca = self.affixState.corrupted
		if ca.modKey then
			local modKey = tostring(ca.modKey) .. "_" .. tostring(ca.tier)
			local mod = itemMods[modKey]
			if not mod and data.modIdol and data.modIdol.flat then
				mod = data.modIdol.flat[modKey]
			end
			if mod then
				local lineIdx = 0
				for k = 1, 10 do
					local line = mod[k]
					if line and type(line) == "string" then
						lineIdx = lineIdx + 1
						t_insert(item.explicitModLines, {
							line = line,
							range = ca.ranges[lineIdx] or 128,
							crafted = true,
						})
					end
				end
			end
		end
	end

	item.corrupted = self.corrupted
	item:BuildAndParseRaw()

	-- Update mod info and layout
	for _, k in ipairs(slotOrder) do
		self:UpdateSlotModInfo(k)
	end
	self:UpdateSlotModInfo("corrupted")
	self:RecalcEditLayout()
	self:RefreshAffixDropdowns()

	self.rebuilding = false
end

function CraftingPopupClass:SaveItem()
	if not self.editItem then return end
	self:RebuildEditItem()
	-- Save craft state for re-editing
	local savedState = {}
	for key, st in pairs(self.affixState) do
		savedState[key] = { modKey = st.modKey, tier = st.tier, ranges = {} }
		for i, r in ipairs(st.ranges) do
			savedState[key].ranges[i] = r
		end
	end
	self.editItem.craftState = {
		affixState = savedState,
		corrupted = self.corrupted,
		baseEntry = self.editBaseEntry,
	}
	self.itemsTab:SetDisplayItem(self.editItem)
	self:Close()
end

function CraftingPopupClass:RestoreCraftState(existingItem)
	local cs = existingItem.craftState
	self.editBaseEntry = cs.baseEntry
	self.editItem = existingItem
	self.corrupted = cs.corrupted
	self.controls.corruptedCheck.state = cs.corrupted

	for key, saved in pairs(cs.affixState) do
		local st = self.affixState[key]
		if st then
			st.modKey = saved.modKey
			st.tier = saved.tier
			st.ranges = {}
			for i, r in ipairs(saved.ranges) do
				st.ranges[i] = r
			end
		end
	end

	for _, k in ipairs({"prefix1","prefix2","suffix1","suffix2","sealed","primordial","corrupted"}) do
		self:UpdateSlotModInfo(k)
		self:UpdateSlotValueEdits(k)
	end
	self:RecalcEditLayout()
	self:RefreshAffixDropdowns()
	self.currentTab = "edit"
end

function CraftingPopupClass:Close()
	main:ClosePopup()
end

function CraftingPopupClass:Draw(viewPort)
	local x, y = self:GetPos()
	local width, height = self:GetSize()

	SetDrawColor(0.05, 0.05, 0.05)
	DrawImage(nil, x, y, width, height)

	SetDrawColor(0.4, 0.35, 0.2)
	DrawImage(nil, x, y, width, 2)
	DrawImage(nil, x, y + height - 2, width, 2)
	DrawImage(nil, x, y, 2, height)
	DrawImage(nil, x + width - 2, y, 2, height)

	local title = "Craft Item"
	if self.editItem then
		title = "Craft Item - " .. (self.editItem.baseName or "")
	end
	SetDrawColor(1, 1, 1)
	DrawString(x + m_floor(width / 2), y + 12, "CENTER_X", 16, "VAR", "^7" .. title)

	SetDrawColor(0.3, 0.3, 0.3)
	DrawImage(nil, x + 10, y + 40, width - 20, 1)

	if self.currentTab == "select" then
		SetDrawColor(0.25, 0.25, 0.25)
		DrawImage(nil, x + 15, y + 120, width - 30, 1)
	end

	if self.currentTab == "edit" and self.editItem then
		local item = self.editItem
		local col
		if item.type and item.type:find("Idol") and item.rarity ~= "UNIQUE" and item.rarity ~= "SET" and item.rarity ~= "LEGENDARY" then
			col = colorCodes.IDOL
		else
			col = colorCodes[item.rarity]
		end
		if col then
			local r, g, b = col:match("%^x(%x%x)(%x%x)(%x%x)")
			if r then
				SetDrawColor(tonumber(r, 16)/255 * 0.15, tonumber(g, 16)/255 * 0.15, tonumber(b, 16)/255 * 0.15)
				DrawImage(nil, x + 10, y + 45, width - 20, 28)
			end
		end
	end

	self:DrawControls(viewPort)
end

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
