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
-- T0 = Normal, T1-4 = Magic, T5-T6 = Rare, T7+ = Exalted
local function getRarityForTierSum(tierSum, hasAffix)
	if not hasAffix then return "NORMAL" end
	if tierSum <= 4 then return "MAGIC" end
	if tierSum <= 6 then return "RARE" end
	return "EXALTED"
end

local CraftingPopupClass = newClass("CraftingPopup", "ControlHost", "Control", function(self, itemsTab)
	local popupW = 750
	local popupH = 550
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
	self.selectedBaseIndex = 1
	self.selectedBaseCategory = "basic" -- "basic", "unique", "set"
	self.editItem = nil

	-- Affix state: each entry = { modKey = nil, tier = 0, range = 128 }
	-- modKey is the statOrderKey (grouping key)
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

	-- Type label + dropdown
	controls.typeLabel = new("LabelControl", {"TOPLEFT", self, "TOPLEFT"}, 15, 50, 0, 16, "^7Type:")
	controls.typeLabel.shown = function() return self_ref.currentTab == "select" end

	controls.typeDropdown = new("DropDownControl", {"LEFT", controls.typeLabel, "RIGHT"}, 5, 0, 200, 20,
		self.build.data.itemBaseTypeList,
		function(index, value)
			self_ref.selectedTypeIndex = index
			self_ref:RefreshBaseList()
		end)
	controls.typeDropdown.shown = function() return self_ref.currentTab == "select" end
	controls.typeDropdown.selIndex = self.selectedTypeIndex
	controls.typeDropdown.enableDroppedWidth = true

	-- Category tabs: Basic / Unique / Set
	controls.catBasic = new("ButtonControl", {"TOPLEFT", self, "TOPLEFT"}, 15, 80, 80, 20, function()
		return self_ref.selectedBaseCategory == "basic" and "^7[Basic]" or "^7Basic"
	end, function()
		self_ref.selectedBaseCategory = "basic"
		self_ref:RefreshBaseList()
	end)
	controls.catBasic.shown = function() return self_ref.currentTab == "select" end

	controls.catUnique = new("ButtonControl", {"LEFT", controls.catBasic, "RIGHT"}, 5, 0, 80, 20, function()
		return self_ref.selectedBaseCategory == "unique" and "^7[Unique]" or "^7Unique"
	end, function()
		self_ref.selectedBaseCategory = "unique"
		self_ref:RefreshBaseList()
	end)
	controls.catUnique.shown = function() return self_ref.currentTab == "select" end

	controls.catSet = new("ButtonControl", {"LEFT", controls.catUnique, "RIGHT"}, 5, 0, 80, 20, function()
		return self_ref.selectedBaseCategory == "set" and "^7[Set]" or "^7Set"
	end, function()
		self_ref.selectedBaseCategory = "set"
		self_ref:RefreshBaseList()
	end)
	controls.catSet.shown = function() return self_ref.currentTab == "select" end

	-- Base item list
	controls.baseList = new("ListControl", {"TOPLEFT", self, "TOPLEFT"}, 15, 108, 720, 380, 20, false, false, {})
	controls.baseList.shown = function() return self_ref.currentTab == "select" end
	controls.baseList.colList = {
		{ width = function() return 300 end, label = "Name" },
		{ width = function() return 200 end, label = "Type" },
		{ width = function() return 100 end, label = "Level" },
		{ width = function() return 100 end, label = "Implicits" },
	}
	controls.baseList.GetRowValue = function(control, column, index, entry)
		if column == 1 then
			local colorCode = colorCodes.NORMAL
			if entry.rarity then
				colorCode = colorCodes[entry.rarity] or colorCodes.NORMAL
			end
			return colorCode .. (entry.label or entry.name or "?")
		elseif column == 2 then
			return "^7" .. (entry.subType or entry.type or "")
		elseif column == 3 then
			local lvl = entry.base and entry.base.req and entry.base.req.level or 0
			return "^7" .. tostring(lvl)
		elseif column == 4 then
			if entry.base and entry.base.implicits then
				return "^7" .. tostring(#entry.base.implicits)
			end
			return "^7-"
		end
	end
	controls.baseList.OnSelClick = function(control, index, entry, doubleClick)
		if doubleClick then
			self_ref.selectedBaseIndex = index
			self_ref:SelectBase(entry)
		end
	end

	-- Select button
	controls.selectBtn = new("ButtonControl", {"BOTTOMRIGHT", self, "BOTTOMRIGHT"}, -15, -15, 100, 28, "Select", function()
		local list = controls.baseList.list
		local idx = controls.baseList.selIndex
		if list[idx] then
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

	-- Implicit lines (dynamic labels, up to 5)
	for i = 1, 5 do
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

			-- Tier display button (right side)
			local tierKey = slotKey .. "Tier"
			controls[tierKey] = new("ButtonControl", {"TOPLEFT", self, "TOPLEFT"}, 550, slotY, 40, 18,
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
			controls[removeKey] = new("ButtonControl", {"TOPLEFT", self, "TOPLEFT"}, 600, slotY, 20, 18, "x", function()
				self_ref.affixState[slotKey].modKey = nil
				self_ref.affixState[slotKey].tier = 0
				self_ref.affixState[slotKey].range = 128
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
						self_ref:RebuildEditItem()
					end
				end)
			controls[addKey].shown = function()
				if self_ref.currentTab ~= "edit" then return false end
				return self_ref.affixState[slotKey].modKey == nil
			end
			controls[addKey].enableDroppedWidth = true
			controls[addKey].maxDroppedWidth = 500
			controls[addKey].tooltipFunc = function(tooltip, mode, index, value)
				tooltip:Clear()
				if mode ~= "OUT" and value and value.statOrderKey then
					self_ref:BuildAffixTooltip(tooltip, value.statOrderKey)
				end
			end

			-- Placeholder text for add
			local addLabelKey = slotKey .. "AddLabel"
			local addText = "<Add " .. (section.type or "Affix") .. ">"
			controls[addLabelKey] = new("LabelControl", {"TOPLEFT", self, "TOPLEFT"}, 25, slotY, 0, 14,
				"^8" .. addText)
			controls[addLabelKey].shown = function()
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
	local typeList = self.build.data.itemBaseTypeList
	local typeName = typeList[self.selectedTypeIndex]
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
					subType = entry.base.type or "",
					rarity = "NORMAL",
					category = "basic",
				})
			end
		end
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
							subType = baseEntry.base.type or "",
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
		-- Set items use the same uniques data with set flag
		-- For now, show empty (Set items need separate data)
		-- TODO: Populate when set data is available
	end

	self.controls.baseList.list = list
	self.controls.baseList.selIndex = 1
end

-- Select a base item and switch to Edit tab
function CraftingPopupClass:SelectBase(entry)
	if not entry then return end

	-- Reset affix state
	for _, st in pairs(self.affixState) do
		st.modKey = nil
		st.tier = 0
		st.range = 128
	end
	self.corrupted = false
	self.controls.corruptedCheck.state = false

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
		item.title = entry.name
	else
		item.rarity = "RARE"
		item.title = "New Item"
	end

	-- Add implicit mod lines
	if entry.base.implicits then
		for _, line in ipairs(entry.base.implicits) do
			t_insert(item.implicitModLines, { line = line })
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
	local allGroups = {} -- for sealed

	for modId, mod in pairs(itemMods) do
		if mod.statOrderKey then
			local group
			if mod.type == "Prefix" then
				if not prefixGroups[mod.statOrderKey] then
					-- Build display label from tier 0
					local labelParts = {}
					for k = 1, 10 do
						if mod[k] then
							t_insert(labelParts, mod[k])
						end
					end
					local label = table.concat(labelParts, " / ")
					-- Strip range formatting for display
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
		t_insert(sealedList, g)
	end
	for _, g in pairs(suffixGroups) do
		t_insert(suffixList, g)
		t_insert(sealedList, g)
	end

	table.sort(prefixList, function(a, b)
		if not a.statOrderKey then return true end
		if not b.statOrderKey then return false end
		return (a.label or "") < (b.label or "")
	end)
	table.sort(suffixList, function(a, b)
		if not a.statOrderKey then return true end
		if not b.statOrderKey then return false end
		return (a.label or "") < (b.label or "")
	end)
	table.sort(sealedList, function(a, b)
		if not a.statOrderKey then return true end
		if not b.statOrderKey then return false end
		return (a.label or "") < (b.label or "")
	end)

	-- Apply mutual exclusion: prefix1 selection excluded from prefix2, etc.
	local function filterExclusions(list, excludeKeys)
		local filtered = { list[1] } -- keep header
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

	-- Prefix1 excludes prefix2's key
	local p1Exclude = {}
	if p2Key then t_insert(p1Exclude, p2Key) end
	self.controls.prefix1Add.list = filterExclusions(prefixList, p1Exclude)

	-- Prefix2 excludes prefix1's key
	local p2Exclude = {}
	if p1Key then t_insert(p2Exclude, p1Key) end
	self.controls.prefix2Add.list = filterExclusions(prefixList, p2Exclude)

	-- Suffix1 excludes suffix2's key
	local s1Exclude = {}
	if s2Key then t_insert(s1Exclude, s2Key) end
	self.controls.suffix1Add.list = filterExclusions(suffixList, s1Exclude)

	-- Suffix2 excludes suffix1's key
	local s2Exclude = {}
	if s1Key then t_insert(s2Exclude, s1Key) end
	self.controls.suffix2Add.list = filterExclusions(suffixList, s2Exclude)

	-- Sealed: exclude all selected prefix/suffix keys
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
			-- Apply range to get specific value
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

	-- Find affix name from tier 0
	local baseMod = itemMods[tostring(st.modKey) .. "_0"]
	if baseMod then
		tooltip:AddLine(16, colorCodes.UNIQUE .. (baseMod.affix or "Affix"))
		tooltip:AddLine(14, "^7\"" .. (baseMod.affix or "") .. "\"")
		tooltip:AddSeparator(10)
	end

	-- Show all tiers
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

	-- Find max tier for this affix
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

	-- Clear existing explicit lines (except unique mods)
	wipeTable(item.explicitModLines)
	wipeTable(item.prefixes)
	wipeTable(item.suffixes)
	item.namePrefix = ""
	item.nameSuffix = ""

	-- Re-add unique mods if applicable
	if self.editBaseEntry and self.editBaseEntry.category == "unique" and self.editBaseEntry.uniqueData then
		for i, modText in ipairs(self.editBaseEntry.uniqueData.mods) do
			local rollId = self.editBaseEntry.uniqueData.rollIds and self.editBaseEntry.uniqueData.rollIds[i]
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
				-- Determine prefix/suffix slot; modId must be the table key (e.g. "0_3")
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

				-- Add mod lines
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

	-- Update rarity based on affixes (for basic items)
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

	-- Corrupted flag
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
	DrawImage(nil, x, y, width, 2)      -- top
	DrawImage(nil, x, y + height - 2, width, 2) -- bottom
	DrawImage(nil, x, y, 2, height)      -- left
	DrawImage(nil, x + width - 2, y, 2, height) -- right

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

	-- Draw separator in edit mode between sections
	if self.currentTab == "edit" and self.editItem then
		-- Draw rarity-colored item name background
		local col = colorCodes[self.editItem.rarity]
		if col then
			-- Light tinted background behind item name area
			local r, g, b = col:match("^x(%x%x)(%x%x)(%x%x)")
			if r then
				SetDrawColor(tonumber(r, 16)/255 * 0.15, tonumber(g, 16)/255 * 0.15, tonumber(b, 16)/255 * 0.15)
				DrawImage(nil, x + 10, y + 45, width - 20, 28)
			end
		end
	end

	-- Draw controls
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
