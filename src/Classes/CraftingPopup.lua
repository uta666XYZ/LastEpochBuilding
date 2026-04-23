-- Last Epoch Building
--
-- Class: Crafting Popup
-- LETools-style left-right split crafting UI.
-- Left panel (320px): type list + item preview with inline affix controls.
-- Right panel (680px): item browser (item tab) or affix browser (prefix/suffix/etc tab).
--
-- Split across multiple files:
--   CraftingPopupHelpers.lua — pure helpers and layout constants
--   CraftingPopup.lua        — constructor, BuildControls, affix/base selection, tooltips
--   CraftingPopupItem.lua    — RebuildEditItem / SaveItem / type predicates
--   CraftingPopupDraw.lua    — Draw / DrawItemCards / DrawAffixCards / ProcessInput
--
local t_insert = table.insert
local t_remove = table.remove
local m_max = math.max
local m_min = math.min
local m_floor = math.floor
local m_ceil = math.ceil
local pairs = pairs
local ipairs = ipairs

local H = LoadModule("Classes/CraftingPopupHelpers")

local MAX_MOD_LINES      = H.MAX_MOD_LINES
local TYPE_ICON          = H.TYPE_ICON
local getTypeIcon        = H.getTypeIcon
local SLOT_TYPE_FILTER   = H.SLOT_TYPE_FILTER
local filterTypeList     = H.filterTypeList
local POPUP_W            = H.POPUP_W
local LEFT_W             = H.LEFT_W
local DIVIDER_X          = H.DIVIDER_X
local TYPE_LIST_Y        = H.TYPE_LIST_Y
local TYPE_LIST_H        = H.TYPE_LIST_H
local TYPE_ROW_H         = H.TYPE_ROW_H
local PREVIEW_Y          = H.PREVIEW_Y
local RP_X               = H.RP_X
local RP_W               = H.RP_W
local RP_TAB_Y           = H.RP_TAB_Y
local RP_TAB_H           = H.RP_TAB_H
local RP_FILTER_Y        = H.RP_FILTER_Y
local RP_FILTER_H        = H.RP_FILTER_H
local RP_CATTAB_Y        = H.RP_CATTAB_Y
local RP_CATTAB_H        = H.RP_CATTAB_H
local RP_CARD_Y          = H.RP_CARD_Y
local RP_CARD_PAD        = H.RP_CARD_PAD
local IC_COLS            = H.IC_COLS
local IC_GAP             = H.IC_GAP
local IC_W               = H.IC_W
local IC_H               = H.IC_H
local AC_H               = H.AC_H
local AC_GAP             = H.AC_GAP
local LP_LABEL_X         = H.LP_LABEL_X
local LP_LINE_X          = H.LP_LINE_X
local LP_LINE_W          = H.LP_LINE_W
local LP_VAL_X           = H.LP_VAL_X
local LP_VAL_W           = H.LP_VAL_W
local LP_TIER_X          = H.LP_TIER_X
local LP_TRUP_X          = H.LP_TRUP_X
local LP_TRDN_X          = H.LP_TRDN_X
local LP_REM_X           = H.LP_REM_X
local LP_REM_W           = H.LP_REM_W
local NO_T8_SLOTS        = H.NO_T8_SLOTS
local FIXED_TIER_SLOTS   = H.FIXED_TIER_SLOTS
local TIER_COLORS        = H.TIER_COLORS
local tierColor          = H.tierColor
local itemNameToFilename = H.itemNameToFilename
local getRarityForAffixes = H.getRarityForAffixes
local cleanImplicitText  = H.cleanImplicitText
local wrapByChars        = H.wrapByChars
local wrapForLabel       = H.wrapForLabel
local wrapTextLine       = H.wrapTextLine
local hasRange           = H.hasRange
local getModPrecision    = H.getModPrecision
local getRounding        = H.getRounding
local extractMinMax      = H.extractMinMax
local computeModValue    = H.computeModValue
local reverseModRange    = H.reverseModRange
local clampModValue      = H.clampModValue
local formatModValue     = H.formatModValue
local buildOrderedTypeList = H.buildOrderedTypeList

-- =============================================================================
-- CraftingPopup class
-- =============================================================================
local CraftingPopupClass = newClass("CraftingPopup", "ControlHost", "Control", function(self, itemsTab, existingItem, slotName)
	local popupMinH = 900
	self.ControlHost()
	self.Control(nil, 0, 0, POPUP_W, popupMinH)
	self.editContentH = popupMinH
	self.width  = function() return POPUP_W end
	self.height = function()
		return m_max(popupMinH, m_min(self.editContentH, main.screenH - 40))
	end
	self.x = function() return m_floor((main.screenW - POPUP_W) / 2) end
	self.y = function()
		local _, h = self:GetSize()
		return m_max(20, m_floor((main.screenH - h) / 2))
	end
	self.itemsTab = itemsTab
	self.build    = itemsTab.build
	self.slotName = slotName
	-- Expose the currently-edited slot so ItemSlotControl can highlight it.
	itemsTab.craftingSlotName = slotName

	-- Right panel state
	self.rightTab             = "item"   -- "item"|"prefix"|"suffix"|"sealed"|"primordial"|"corrupted"
	self.selectedBaseCategory = "basic"
	self.searchText           = ""
	self.editItem             = nil
	self.rebuilding           = false
	self.affixViewMode        = (main.config and main.config.craftAffixView) or "list"  -- "list"|"card"

	-- Scroll offsets (pixels)
	self.typeScrollY  = 0   -- type list scroll
	self.rightScrollY = 0   -- right panel card scroll

	-- Hit-test arrays rebuilt in Draw()
	self.typeCards  = {}
	self.rightCards = {}

	-- Phase 2: collapse state per slot -> per subcategory
	-- slotKey "prefix"/"suffix"/"sealed"/"primordial"/"corrupted" -> { [subcat]=true }
	-- Default: all expanded (nil means expanded)
	self.collapsedSubcats = {}

	-- Image handle cache for item cards
	self.imageHandles = {}

	-- Affix lists per slot (populated by RefreshAffixDropdowns)
	self.affixLists = {
		prefix1={}, prefix2={}, suffix1={}, suffix2={},
		sealed={}, primordial={}, corrupted={},
	}

	self.selectedTypeIndex = 1
	self.setItems = self:LoadSetData()
	self.orderedTypeList = filterTypeList(
		buildOrderedTypeList(self.build.data.itemBaseTypeList), slotName)

	-- Default type selection: if this is the off-hand slot (Weapon 2), prefer the
	-- Off-Hand section (Shield first). Otherwise pick the first non-separator entry.
	local preferOffhand = (slotName == "Weapon 2")
	local offhandTypes = { ["Shield"] = true, ["Off-Hand Catalyst"] = true, ["Quiver"] = true }
	local firstOffhandIdx, firstAnyIdx
	for i, entry in ipairs(self.orderedTypeList) do
		if not entry.isSeparator then
			if not firstAnyIdx then firstAnyIdx = i end
			if preferOffhand and not firstOffhandIdx and offhandTypes[entry.typeName] then
				firstOffhandIdx = i
			end
		end
	end
	self.selectedTypeIndex = firstOffhandIdx or firstAnyIdx or 1

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

	self.slotModInfo = {}
	for _, k in ipairs({"prefix1","prefix2","suffix1","suffix2","sealed","primordial","corrupted"}) do
		self.slotModInfo[k] = { count = 0, lines = {} }
	end

	self.editY = {}
	self:RecalcEditLayout()
	self:BuildControls()

	if existingItem and existingItem.craftState then
		self:RestoreCraftState(existingItem)
	end
end)

function CraftingPopupClass:LoadSetData()
	local ver = self.build.targetVersion or "1_4"
	local setData = readJsonFile("Data/Set/set_" .. ver .. ".json")
	if not setData then setData = readJsonFile("Data/Set/set_1_4.json") end
	return setData or {}
end

function CraftingPopupClass:GetItemImage(name, rarity)
	local isUnique = rarity == "UNIQUE" or rarity == "WWUNIQUE" or rarity == "SET"
	local filename = itemNameToFilename(name)
	local cacheKey = (isUnique and "u:" or "b:") .. filename
	if not self.imageHandles[cacheKey] then
		local h = NewImageHandle()
		local path = isUnique and ("Assets/items/uniques/" .. filename)
		             or ("Assets/items/bases/" .. filename)
		h:Load(path, "ASYNC")
		self.imageHandles[cacheKey] = h
	end
	return self.imageHandles[cacheKey]
end

function CraftingPopupClass:GetSelectedTypeName()
	local entry = self.orderedTypeList[self.selectedTypeIndex]
	return entry and entry.typeName or nil
end

function CraftingPopupClass:GetMaxTier(statOrderKey)
	if self:IsAnyIdol() then return 0 end
	local pool = self:IsIdolAltar() and (data.itemMods["Idol Altar"] or {}) or (data.itemMods.Item or {})
	for tier = 7, 0, -1 do
		local key = tostring(statOrderKey) .. "_" .. tostring(tier)
		if pool[key] then return tier end
	end
	return 0
end

-- Recalculate dynamic Y positions for left panel item preview.
-- All Y values are absolute from the popup's TOPLEFT.
function CraftingPopupClass:RecalcEditLayout()
	local LINE_H        = 18
	local WRAP_H        = 15  -- per wrapped sub-line
	local implicitCount = self.editItem and #self.editItem.implicitModLines or 0
	local rarity        = self.editItem and self.editItem.rarity

	self.editY = {}
	self.editY.implicits = {}
	self.editY.affixBands = {}

	-- Compute implicit Y positions, accounting for wrap
	local implicitStartY = PREVIEW_Y + 44 + 14 + 4 + 14
	local iy = implicitStartY
	local IMPLICIT_WRAP_W = LEFT_W - LP_LINE_X - 4
	for i = 1, implicitCount do
		self.editY.implicits[i] = iy
		local ml = self.editItem.implicitModLines[i]
		local wrapCount = 1
		if ml then
			local formatted = itemLib.formatModLine(ml)
			if formatted then
				local _, n = wrapForLabel("^7" .. formatted, IMPLICIT_WRAP_W, 13)
				wrapCount = n
			end
		end
		t_insert(self.editY.affixBands, { y = iy, h = wrapCount * WRAP_H })
		iy = iy + wrapCount * WRAP_H
	end
	local implicitEndY = implicitCount > 0 and iy or (PREVIEW_Y + 90)

	-- Affix sections start below the preview header and implicit lines
	local EDIT_START = m_max(330, implicitEndY + 8)
	local y = EDIT_START
	local GAP = 4

	local isUniqueIdol  = self:IsUniqueIdol()
	local isAnyIdol     = self:IsAnyIdol()
	local isEnchantable = self:IsEnchantableIdol()
	local isUniqueItem  = self:IsUniqueItem()
	local isSetItem     = self:IsSetItem()

	local sectionOrder = {
		{ label = "prefixLabel",    slots = {"prefix1", "prefix2"} },
		{ label = "suffixLabel",    slots = {"suffix1", "suffix2"} },
		{ label = "sealedLabel",    slots = {"sealed"} },
		{ label = "primordialLabel", slots = {"primordial"} },
		{ label = "corruptedLabel", slots = {"corrupted"} },
	}

	local AFFIX_LINE_W = LEFT_W - LP_LINE_X - 4
	local CTRL_H = 20
	local function layoutSlots(slots)
		for _, slotKey in ipairs(slots) do
			local st = self.affixState[slotKey]
			self.editY[slotKey] = {}
			self.editY[slotKey].ctrl = {}
			if st.modKey then
				local info = self.slotModInfo[slotKey]
				local lc = info.count
				if lc == 0 then lc = 1 end
				-- Initialize fallbacks for all MAX_MOD_LINES
				for i = 1, MAX_MOD_LINES do
					self.editY[slotKey][i] = y
					self.editY[slotKey].ctrl[i] = y
				end
				for i = 1, lc do
					local line = info.lines[i]
					local wrapN = 1
					if line then
						local range = (st.ranges and st.ranges[i]) or 128
						local computed = itemLib.applyRange(line, range, nil, getRounding(line)) or line
						computed = computed:gsub("{rounding:%w+}", ""):gsub("{[^}]+}", "")
						local col = tierColor(st.tier)
						local _, n = wrapForLabel(col .. computed, AFFIX_LINE_W, 13)
						wrapN = n
					end
					self.editY[slotKey][i] = y
					if wrapN > 1 then
						-- Controls go below the wrapped text
						self.editY[slotKey].ctrl[i] = y + wrapN * WRAP_H
						y = y + wrapN * WRAP_H + CTRL_H + 2
					else
						self.editY[slotKey].ctrl[i] = y
						y = y + LINE_H
					end
				end
				y = y + GAP
			else
				self.editY[slotKey].add = y
				y = y + LINE_H + GAP
			end
		end
	end

	for si, sec in ipairs(sectionOrder) do
		local skip = false
		if isUniqueIdol and sec.label ~= "corruptedLabel" then skip = true end
		if isSetItem then skip = true end
		if not skip and isUniqueItem
			and (sec.label == "sealedLabel" or sec.label == "primordialLabel") then
			skip = true
		end
		if isAnyIdol and not isEnchantable
			and (sec.label == "sealedLabel" or sec.label == "primordialLabel") then
			skip = true
		end
		-- Idols use only one enchant slot (sealed); hide primordial entirely
		if isAnyIdol and sec.label == "primordialLabel" then skip = true end
		if skip then
			for _, slotKey in ipairs(sec.slots) do self.editY[slotKey] = {} end
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
				if isAnyIdol and (sec.label == "prefixLabel" or sec.label == "suffixLabel") then
					layoutSlots({sec.slots[1]})
				else
					layoutSlots(sec.slots)
				end
			end
			y = y + GAP
		end
	end

	-- Unique/Set explicit mods shown after affix sections
	local isUniqueOrSet = (rarity == "UNIQUE" or rarity == "WWUNIQUE" or rarity == "SET")
	if isUniqueOrSet and self.editItem and #self.editItem.explicitModLines > 0 then
		self.editY.uniqueModsLabel = y
		y = y + LINE_H + GAP
		self.editY.uniqueMods = {}
		local um_w = LEFT_W - LP_LINE_X - 4
		for i = 1, #self.editItem.explicitModLines do
			self.editY.uniqueMods[i] = y
			local ml = self.editItem.explicitModLines[i]
			local wn = 1
			if ml then
				local formatted = itemLib.formatModLine(ml)
				if formatted then
					local _, n = wrapForLabel("^7" .. formatted, um_w, 13)
					wn = n
				end
			end
			t_insert(self.editY.affixBands, { y = y, h = wn * WRAP_H })
			y = y + wn * WRAP_H
		end
		y = y + GAP
	else
		self.editY.uniqueModsLabel = 0
		self.editY.uniqueMods = {}
	end

	-- Set info block (members + bonuses) for set items OR for Reforged crafted
	-- basic items whose editItem.setInfo has been populated.
	self.editY.setInfoY = 0
	local layoutSetId, layoutBonus
	if isSetItem then
		local sd = self.editBaseEntry and self.editBaseEntry.setData
		layoutSetId = sd and sd.set and sd.set.setId
		layoutBonus = sd and sd.set and sd.set.bonus
	elseif self.editItem and self.editItem.setInfo and self.editItem.setInfo.setId ~= nil then
		layoutSetId = self.editItem.setInfo.setId
		layoutBonus = self.editItem.setInfo.bonus
	end
	if layoutSetId ~= nil then
		self.editY.setInfoY = y
		y = y + LINE_H + GAP  -- "ITEM SET" header
		y = y + LINE_H        -- set name line
		local memberCount = 0
		for _, si in pairs(self.setItems or {}) do
			if si.set and si.set.setId == layoutSetId then memberCount = memberCount + 1 end
		end
		y = y + memberCount * LINE_H + GAP
		local bonus = layoutBonus
		if bonus then
			y = y + LINE_H + GAP  -- "SET BONUSES" header
			local bonusW = LEFT_W - LP_LINE_X - 4
			for k, v in pairs(bonus) do
				local line = tostring(k) .. " set: " .. tostring(v)
				local _, n = wrapForLabel("^7" .. line, bonusW, 13)
				y = y + n * WRAP_H + 2
			end
		end
		y = y + GAP
	end

	self.editContentH = y + 60
end

function CraftingPopupClass:UpdateSlotModInfo(slotKey)
	local info = { count = 0, lines = {} }
	local st = self.affixState[slotKey]
	if st.modKey then
		local modKey = tostring(st.modKey) .. "_" .. tostring(st.tier)
		local mod
		if self:IsIdolAltar() then
			local altarMods = data.itemMods["Idol Altar"]
			mod = altarMods and altarMods[modKey]
		else
			mod = data.itemMods.Item and data.itemMods.Item[modKey]
			if not mod and data.modIdol and data.modIdol.flat then
				mod = data.modIdol.flat[modKey]
			end
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
				local precision = getModPrecision(info.lines[i])
				if precision <= 1 then valCtrl.numberInc = 1
				elseif precision <= 10 then valCtrl.numberInc = 0.1
				else valCtrl.numberInc = 0.01 end
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

	-- Close button (always visible)
	controls.closeBtn = new("ButtonControl", {"TOPRIGHT", self, "TOPRIGHT"}, -10, 10, 40, 24, "X", function()
		self_ref:Close()
	end)

	-- =========================================================================
	-- RIGHT PANEL: tab buttons
	-- =========================================================================
	local rightTabDefs = {
		{ key = "item",       label = function()
			local n = self_ref.currentItemList and #self_ref.currentItemList or 0
			return (self_ref.rightTab == "item" and "^7" or "^8") .. "Item(" .. n .. ")"
		end },
		{ key = "prefix",    label = function()
			local n = #(self_ref.affixLists.prefix1 or {})
			return (self_ref.rightTab == "prefix" and "^7" or "^8") .. "Pre(" .. n .. ")"
		end },
		{ key = "suffix",    label = function()
			local n = #(self_ref.affixLists.suffix1 or {})
			return (self_ref.rightTab == "suffix" and "^7" or "^8") .. "Suf(" .. n .. ")"
		end },
		{ key = "sealed",    label = function()
			local base = self_ref:IsAnyIdol() and "Enc1" or "Sealed"
			local n = #(self_ref.affixLists.sealed or {})
			return (self_ref.rightTab == "sealed" and "^7" or "^8") .. base .. "(" .. n .. ")"
		end },
		{ key = "primordial", label = function()
			local base = self_ref:IsAnyIdol() and "Enc2" or "Primo"
			local n = #(self_ref.affixLists.primordial or {})
			return (self_ref.rightTab == "primordial" and "^7" or "^8") .. base .. "(" .. n .. ")"
		end },
		{ key = "corrupted", label = function()
			local n = #(self_ref.affixLists.corrupted or {})
			return (self_ref.rightTab == "corrupted" and "^7" or "^8") .. "Corrupt(" .. n .. ")"
		end },
	}
	-- Spread 6 tabs across RP_W pixels
	local tabW = m_floor((RP_W - 4) / #rightTabDefs)
	for i, def in ipairs(rightTabDefs) do
		local tabX = LEFT_W + 2 + (i - 1) * tabW
		local capturedKey = def.key
		local capturedLabel = def.label
		controls["rtab_" .. def.key] = new("ButtonControl", {"TOPLEFT", self, "TOPLEFT"},
			tabX, RP_TAB_Y, tabW - 2, RP_TAB_H,
			capturedLabel,
			function()
				self_ref.rightTab = capturedKey
				self_ref.rightScrollY = 0
			end)
		controls["rtab_" .. def.key].locked = function()
			return self_ref.rightTab == capturedKey
		end
		-- Hide affix tabs when no item selected
		if def.key ~= "item" then
			controls["rtab_" .. def.key].shown = function()
				return self_ref.editItem ~= nil
			end
		end
	end

	-- Right panel search bar
	controls.rightSearch = new("EditControl", {"TOPLEFT", self, "TOPLEFT"},
		LEFT_W + 2, RP_FILTER_Y, RP_W - 82, RP_FILTER_H, "", "^8Search", nil, nil,
		function(buf)
			self_ref.searchText = buf
			self_ref.rightScrollY = 0
			if self_ref.rightTab == "item" then
				self_ref:RefreshBaseList()
			end
		end)

	-- Card/List view toggle (affix tabs only)
	controls.affixViewToggle = new("ButtonControl", {"TOPLEFT", self, "TOPLEFT"},
		LEFT_W + 2 + (RP_W - 78), RP_FILTER_Y, 76, RP_FILTER_H,
		function()
			return self_ref.affixViewMode == "card" and "^7[Card]" or "^8[List]"
		end,
		function()
			self_ref.affixViewMode = (self_ref.affixViewMode == "card") and "list" or "card"
			if main.config then main.config.craftAffixView = self_ref.affixViewMode end
		end)
	controls.affixViewToggle.shown = function() return self_ref.rightTab ~= "item" end

	-- Right panel category tabs (item mode only)
	controls.catBasic = new("ButtonControl", {"TOPLEFT", self, "TOPLEFT"},
		LEFT_W + 2, RP_CATTAB_Y, 70, RP_CATTAB_H,
		function() return self_ref.selectedBaseCategory == "basic" and "^7Basic" or "^8Basic" end,
		function()
			self_ref.selectedBaseCategory = "basic"
			self_ref:RefreshBaseList()
		end)
	controls.catBasic.locked = function() return self_ref.selectedBaseCategory == "basic" end
	controls.catBasic.shown  = function() return self_ref.rightTab == "item" end

	controls.catUnique = new("ButtonControl", {"LEFT", controls.catBasic, "RIGHT"}, 4, 0, 70, RP_CATTAB_H,
		function() return colorCodes.UNIQUE .. "Unique" end,
		function()
			self_ref.selectedBaseCategory = "unique"
			self_ref:RefreshBaseList()
		end)
	controls.catUnique.locked = function() return self_ref.selectedBaseCategory == "unique" end
	controls.catUnique.shown  = function() return self_ref.rightTab == "item" end

	controls.catSet = new("ButtonControl", {"LEFT", controls.catUnique, "RIGHT"}, 4, 0, 55, RP_CATTAB_H,
		function() return colorCodes.SET .. "Set" end,
		function()
			self_ref.selectedBaseCategory = "set"
			self_ref:RefreshBaseList()
		end)
	controls.catSet.locked = function() return self_ref.selectedBaseCategory == "set" end
	controls.catSet.shown  = function() return self_ref.rightTab == "item" end

	-- =========================================================================
	-- LEFT PANEL: item preview controls
	-- =========================================================================
	controls.editItemName = new("LabelControl", {"TOPLEFT", self, "TOPLEFT"}, LP_LABEL_X,
		function() return PREVIEW_Y + 4 end, 0, 16, "")
	controls.editItemName.label = function()
		if not self_ref.editItem then return "^8<- Select an item" end
		local item = self_ref.editItem
		local col
		if item.type and item.type:find("Idol") and item.type ~= "Idol Altar" and item.rarity ~= "UNIQUE" then
			col = colorCodes.IDOL
		else
			col = colorCodes[item.rarity] or colorCodes.NORMAL
		end
		return col .. (item.title or (item.namePrefix or "") .. (item.baseName or item.name or "") .. (item.nameSuffix or ""))
	end

	controls.implicitLabel = new("LabelControl", {"TOPLEFT", self, "TOPLEFT"}, LP_LABEL_X,
		function() return PREVIEW_Y + 44 end, 0, 14, colorCodes.UNIQUE .. "IMPLICITS")
	controls.implicitLabel.shown = function()
		return self_ref.editItem ~= nil and #self_ref.editItem.implicitModLines > 0
	end

	local IMPLICIT_WRAP_W = LEFT_W - LP_LINE_X - 4
	for i = 1, 20 do
		local key = "implicit" .. i
		controls[key] = new("LabelControl", {"TOPLEFT", self, "TOPLEFT"}, LP_LINE_X,
			function() return self_ref.editY.implicits and self_ref.editY.implicits[i] or 0 end,
			IMPLICIT_WRAP_W, 13, "")
		controls[key].shown = function()
			if not self_ref.editItem then return false end
			return i <= #self_ref.editItem.implicitModLines
				and (self_ref.editY.implicits and self_ref.editY.implicits[i] or 0) > 0
		end
		controls[key].label = function()
			if not self_ref.editItem then return "" end
			local ml = self_ref.editItem.implicitModLines[i]
			if not ml then return "" end
			local formatted = itemLib.formatModLine(ml)
			if not formatted then return "" end
			local wrapped = wrapForLabel("^7" .. formatted, IMPLICIT_WRAP_W, 13)
			return wrapped
		end
	end

	-- Unique/Set explicit mod controls (MODIFIERS section)
	controls.uniqueModsLabel = new("LabelControl", {"TOPLEFT", self, "TOPLEFT"}, LP_LABEL_X,
		function() return self_ref.editY.uniqueModsLabel or 0 end, 0, 14,
		colorCodes.UNIQUE .. "MODIFIERS")
	controls.uniqueModsLabel.shown = function()
		if not self_ref.editItem then return false end
		local r = self_ref.editItem.rarity
		return (r == "UNIQUE" or r == "WWUNIQUE" or r == "SET")
			and #self_ref.editItem.explicitModLines > 0
			and (self_ref.editY.uniqueModsLabel or 0) > 0
	end

	for i = 1, 20 do
		local umKey = "uniqueMod" .. i
		controls[umKey] = new("LabelControl", {"TOPLEFT", self, "TOPLEFT"}, LP_LINE_X,
			function() return self_ref.editY.uniqueMods and self_ref.editY.uniqueMods[i] or 0 end,
			LEFT_W - LP_LINE_X - 4, 13, "")
		controls[umKey].shown = function()
			if not self_ref.editItem then return false end
			local r = self_ref.editItem.rarity
			if r ~= "UNIQUE" and r ~= "WWUNIQUE" and r ~= "SET" then return false end
			return self_ref.editItem.explicitModLines[i] ~= nil
				and (self_ref.editY.uniqueMods and self_ref.editY.uniqueMods[i] or 0) > 0
		end
		controls[umKey].label = function()
			if not self_ref.editItem then return "" end
			local ml = self_ref.editItem.explicitModLines[i]
			if not ml then return "" end
			local formatted = itemLib.formatModLine(ml)
			if not formatted then return "" end
			return wrapForLabel("^7" .. formatted, LEFT_W - LP_LINE_X - 4, 13)
		end
	end

	-- Affix section controls
	local affixSections = {
		{ key = "prefix",     label = "PREFIXES",         slots = {"prefix1", "prefix2"} },
		{ key = "suffix",     label = "SUFFIXES",         slots = {"suffix1", "suffix2"} },
		{ key = "sealed",     label = "SEALED AFFIX",     slots = {"sealed"} },
		{ key = "primordial", label = "PRIMORDIAL AFFIX", slots = {"primordial"} },
		{ key = "corrupted",  label = "CORRUPTED",        slots = {"corrupted"} },
	}

	for _, section in ipairs(affixSections) do
		local labelKey          = section.key .. "Label"
		local capturedSectionKey   = section.key
		local capturedSectionLabel = section.label

		controls[labelKey] = new("LabelControl", {"TOPLEFT", self, "TOPLEFT"}, LP_LABEL_X,
			function() return self_ref.editY[labelKey] or 0 end, 0, 14, "")

		if capturedSectionKey == "sealed" then
			controls[labelKey].label = function()
				local base = self_ref:IsAnyIdol() and "ENCHANT" or capturedSectionLabel
				local n = #(self_ref.affixLists.sealed or {})
				return colorCodes.UNIQUE .. base .. " (" .. n .. ")"
			end
		elseif capturedSectionKey == "primordial" then
			controls[labelKey].label = function()
				local n = #(self_ref.affixLists.primordial or {})
				return colorCodes.UNIQUE .. capturedSectionLabel .. " (" .. n .. ")"
			end
		else
			local sectionListKeyMap = { prefix = "prefix1", suffix = "suffix1", corrupted = "corrupted" }
			local capturedListKey = sectionListKeyMap[capturedSectionKey] or capturedSectionKey
			controls[labelKey].label = function()
				local n = #(self_ref.affixLists[capturedListKey] or {})
				return colorCodes.UNIQUE .. capturedSectionLabel .. " (" .. n .. ")"
			end
		end

		controls[labelKey].shown = function()
			if not self_ref.editItem then return false end
			if capturedSectionKey ~= "corrupted" and self_ref:IsUniqueIdol() then return false end
			if self_ref:IsSetItem() then return false end
			if (capturedSectionKey == "sealed" or capturedSectionKey == "primordial")
				and self_ref:IsUniqueItem() then return false end
			if (capturedSectionKey == "sealed" or capturedSectionKey == "primordial")
				and self_ref:IsAnyIdol() and not self_ref:IsEnchantableIdol() then return false end
			if capturedSectionKey == "primordial" and self_ref:IsAnyIdol() then return false end
			return self_ref.editY[labelKey] ~= nil and self_ref.editY[labelKey] > 0
		end

		if section.key == "corrupted" then
			controls.corruptedCheck = new("CheckBoxControl", {"TOPLEFT", self, "TOPLEFT"}, LP_LABEL_X + 110,
				function() return self_ref.editY[labelKey] or 0 end, 18, "", function(state)
					self_ref.corrupted = state
					if not state then
						self_ref.affixState.corrupted.modKey = nil
						self_ref.affixState.corrupted.tier   = 0
						self_ref.affixState.corrupted.ranges = {}
						self_ref:UpdateSlotModInfo("corrupted")
					end
					self_ref:RebuildEditItem()
				end)
			controls.corruptedCheck.shown = function() return self_ref.editItem ~= nil end
		end

		for _, slotKey in ipairs(section.slots) do
			for li = 1, MAX_MOD_LINES do
				local lineKey = slotKey .. "Line" .. li
				local valKey  = slotKey .. "Val"  .. li

				local AFFIX_LINE_W = LEFT_W - LP_LINE_X - 4
				controls[lineKey] = new("LabelControl", {"TOPLEFT", self, "TOPLEFT"}, LP_LINE_X,
					function()
						local ey = self_ref.editY[slotKey]
						return ey and ey[li] or 0
					end, AFFIX_LINE_W, 13, "")
				controls[lineKey].shown = function()
					if not self_ref.editItem then return false end
					if not self_ref.affixState[slotKey].modKey then return false end
					if slotKey == "corrupted" and not self_ref.corrupted then return false end
					return li <= self_ref.slotModInfo[slotKey].count
				end
				controls[lineKey].label = function()
					local info = self_ref.slotModInfo[slotKey]
					if li > info.count then return "" end
					local line  = info.lines[li]
					local st    = self_ref.affixState[slotKey]
					local range = st.ranges[li] or 128
					local computed = itemLib.applyRange(line, range, nil, getRounding(line)) or line
					computed = computed:gsub("{rounding:%w+}", ""):gsub("{[^}]+}", "")
					local col = tierColor(st.tier)
					return wrapForLabel(col .. computed, AFFIX_LINE_W, 13)
				end

				controls[valKey] = new("EditControl", {"TOPLEFT", self, "TOPLEFT"}, LP_VAL_X,
					function()
						local ey = self_ref.editY[slotKey]
						local cy = ey and ey.ctrl and ey.ctrl[li]
						return cy and (cy - 1) or 0
					end, LP_VAL_W, 18, "", nil, "^%-%d%.", nil,
					function(buf)
						if self_ref.rebuilding then return end
						local val = tonumber(buf)
						if not val then return end
						local info = self_ref.slotModInfo[slotKey]
						if li > info.count then return end
						local line = info.lines[li]
						val = clampModValue(line, val)
						local range = reverseModRange(line, val)
						self_ref.affixState[slotKey].ranges[li] = range
						local actual = computeModValue(line, range)
						if actual then
							self_ref.rebuilding = true
							controls[valKey]:SetText(formatModValue(line, actual))
							self_ref.rebuilding = false
						end
						self_ref:RebuildEditItem()
					end)
				controls[valKey].shown = function()
					if not self_ref.editItem then return false end
					if not self_ref.affixState[slotKey].modKey then return false end
					if slotKey == "corrupted" and not self_ref.corrupted then return false end
					local info = self_ref.slotModInfo[slotKey]
					return li <= info.count and hasRange(info.lines[li])
				end
				controls[valKey].numberInc = 1
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
				controls[valKey].tooltipPropagated = true
			end

			-- Tier label
			local tierLabelKey = slotKey .. "TierLabel"
			controls[tierLabelKey] = new("LabelControl", {"TOPLEFT", self, "TOPLEFT"}, LP_TIER_X,
				function()
					local ey = self_ref.editY[slotKey]
					return ey and ey.ctrl and ey.ctrl[1] or 0
				end, 0, 14, "")
			controls[tierLabelKey].shown = function()
				if not self_ref.editItem then return false end
				if slotKey == "corrupted" and not self_ref.corrupted then return false end
				return self_ref.affixState[slotKey].modKey ~= nil
			end
			controls[tierLabelKey].label = function()
				local st = self_ref.affixState[slotKey]
				-- Abbreviate in the preview to save space; "Tier 5" -> "T5"
				return tierColor(st.tier) .. "T" .. tostring(st.tier + 1)
			end
			controls[tierLabelKey].tooltipFunc = function(tooltip, mode)
				if mode == "OUT" then return end
				self_ref:BuildTierTooltip(tooltip, slotKey)
			end

			-- Tier up (+)
			local tierUpKey = slotKey .. "TierUp"
			controls[tierUpKey] = new("ButtonControl", {"TOPLEFT", self, "TOPLEFT"}, LP_TRUP_X,
				function()
					local ey = self_ref.editY[slotKey]
					return ey and ey.ctrl and ey.ctrl[1] or 0
				end, 18, 18, "+", function()
					local st = self_ref.affixState[slotKey]
					if not st.modKey then return end
					local maxTier = self_ref:GetMaxTier(st.modKey)
					if NO_T8_SLOTS[slotKey] then maxTier = m_min(maxTier, 6) end
					st.tier = st.tier + 1
					if st.tier > maxTier then st.tier = 0 end
					self_ref:UpdateSlotModInfo(slotKey)
					self_ref:UpdateSlotValueEdits(slotKey)
					self_ref:RebuildEditItem()
				end)
			controls[tierUpKey].shown = function()
				if not self_ref.editItem then return false end
				if FIXED_TIER_SLOTS[slotKey] then return false end
				if slotKey == "corrupted" and not self_ref.corrupted then return false end
				return self_ref.affixState[slotKey].modKey ~= nil
			end
			controls[tierUpKey].tooltipFunc = function(tooltip, mode)
				if mode == "OUT" then return end
				self_ref:BuildTierTooltip(tooltip, slotKey)
			end

			-- Tier down (-)
			local tierDownKey = slotKey .. "TierDown"
			controls[tierDownKey] = new("ButtonControl", {"TOPLEFT", self, "TOPLEFT"}, LP_TRDN_X,
				function()
					local ey = self_ref.editY[slotKey]
					return ey and ey.ctrl and ey.ctrl[1] or 0
				end, 18, 18, "-", function()
					local st = self_ref.affixState[slotKey]
					if not st.modKey then return end
					local maxTier = self_ref:GetMaxTier(st.modKey)
					if NO_T8_SLOTS[slotKey] then maxTier = m_min(maxTier, 6) end
					st.tier = st.tier - 1
					if st.tier < 0 then st.tier = maxTier end
					self_ref:UpdateSlotModInfo(slotKey)
					self_ref:UpdateSlotValueEdits(slotKey)
					self_ref:RebuildEditItem()
				end)
			controls[tierDownKey].shown = function()
				if not self_ref.editItem then return false end
				if FIXED_TIER_SLOTS[slotKey] then return false end
				if slotKey == "corrupted" and not self_ref.corrupted then return false end
				return self_ref.affixState[slotKey].modKey ~= nil
			end
			controls[tierDownKey].tooltipFunc = function(tooltip, mode)
				if mode == "OUT" then return end
				self_ref:BuildTierTooltip(tooltip, slotKey)
			end

			-- Remove (x)
			local removeKey = slotKey .. "Remove"
			controls[removeKey] = new("ButtonControl", {"TOPLEFT", self, "TOPLEFT"}, LP_REM_X,
				function()
					local ey = self_ref.editY[slotKey]
					return ey and ey.ctrl and ey.ctrl[1] or 0
				end, LP_REM_W, 18, "x", function()
					self_ref.affixState[slotKey].modKey  = nil
					self_ref.affixState[slotKey].tier    = (slotKey == "primordial") and 7 or 0
					self_ref.affixState[slotKey].ranges  = {}
					-- Keep lastAffixSlot in sync so SelectAffixEntry doesn't
					-- try to replace a now-empty slot on the next click.
					local tabKey = slotKey:match("^(prefix)") or slotKey:match("^(suffix)")
					if tabKey and self_ref.lastAffixSlot and self_ref.lastAffixSlot[tabKey] == slotKey then
						local otherSlot = (slotKey == tabKey .. "1") and (tabKey .. "2") or (tabKey .. "1")
						local otherSt   = self_ref.affixState[otherSlot]
						self_ref.lastAffixSlot[tabKey] = (otherSt and otherSt.modKey) and otherSlot or nil
					end
					self_ref:UpdateSlotModInfo(slotKey)
					self_ref:RebuildEditItem()
				end)
			controls[removeKey].shown = function()
				if not self_ref.editItem then return false end
				if slotKey == "corrupted" and not self_ref.corrupted then return false end
				return self_ref.affixState[slotKey].modKey ~= nil
			end

			-- [+ Add Prefix] / [+ Add Suffix] button (prefix and suffix sections only)
			if capturedSectionKey == "prefix" or capturedSectionKey == "suffix" then
				local addKey           = slotKey .. "AddBtn"
				local capturedSlotKey  = slotKey
				local addLabel         = capturedSectionKey == "prefix" and "+ Add Prefix" or "+ Add Suffix"
				controls[addKey] = new("ButtonControl", {"TOPLEFT", self, "TOPLEFT"}, LP_LINE_X,
					function()
						local ey = self_ref.editY[capturedSlotKey]
						return ey and (ey.add or 0) or 0
					end, 220, 18, addLabel,
					function()
						-- Map internal slot keys to consolidated tab keys
						local tabKey = (capturedSectionKey == "prefix") and "prefix"
						           or (capturedSectionKey == "suffix") and "suffix"
						           or capturedSlotKey
						self_ref.rightTab      = tabKey
						self_ref.rightScrollY  = 0
					end)
				controls[addKey].shown = function()
					if not self_ref.editItem then return false end
					if self_ref:IsUniqueItem() or self_ref:IsSetItem() or self_ref:IsUniqueIdol() then return false end
					local ey = self_ref.editY[capturedSlotKey]
					return ey ~= nil and ey.add ~= nil
						and self_ref.affixState[capturedSlotKey].modKey == nil
				end
			end
		end
	end

	-- Save / Cancel
	controls.saveBtn = new("ButtonControl", {"BOTTOMLEFT", self, "BOTTOMLEFT"}, LP_LABEL_X, -15, 90, 28, "Save", function()
		self_ref:SaveItem()
	end)
	controls.saveBtn.shown = function() return self_ref.editItem ~= nil end

	controls.cancelBtn = new("ButtonControl", {"LEFT", controls.saveBtn, "RIGHT"}, 8, 0, 90, 28, "Cancel", function()
		self_ref:Close()
	end)

	-- Fix anchoring
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

-- =============================================================================
-- Data refresh
-- =============================================================================
function CraftingPopupClass:RefreshBaseList()
	local typeName = self:GetSelectedTypeName()
	if not typeName then self.currentItemList = {}; return end

	local list = {}

	if self.selectedBaseCategory == "basic" then
		local bases = self.build.data.itemBaseLists[typeName]
		if bases then
			local myClassBit = self:GetCurrentClassReqBit()
			for _, entry in ipairs(bases) do
				if not entry.base.legacy then
					local classReq = entry.base.classReq or 0
					if classReq == 0 or myClassBit == 0 or bit.band(classReq, myClassBit) ~= 0 then
						t_insert(list, {
							label = entry.name, name = entry.name, base = entry.base,
							type = typeName, displayType = entry.base.type or "",
							rarity = "NORMAL", category = "basic",
						})
					end
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
				if unique.name and unique.name:lower():sub(1, 9) == "cocooned " then goto continueUID end
				local found = false
				for _, baseEntry in ipairs(bases) do
					if baseEntry.base.baseTypeID == unique.baseTypeID and
					   baseEntry.base.subTypeID  == unique.subTypeID then
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
						found = true
						break
					end
				end
				if not found and self.build.data.itemBases then
					for baseName, base in pairs(self.build.data.itemBases) do
						if base.hidden and base.type == typeName and
						   base.baseTypeID == unique.baseTypeID and
						   base.subTypeID  == unique.subTypeID then
							local classReq = base.classReq or 0
							if classReq == 0 or myClassBit == 0 or bit.band(classReq, myClassBit) ~= 0 then
								t_insert(list, {
									label = unique.name, name = unique.name,
									base = base, baseName = baseName,
									type = typeName, displayType = base.type or "",
									rarity = "UNIQUE", category = "unique",
									uniqueData = unique, uniqueID = uid,
								})
							end
							break
						end
					end
				end
				::continueUID::
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
					   baseEntry.base.subTypeID  == setItem.subTypeID then
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

	-- Search filter
	local query = (self.searchText or ""):lower():gsub("^%s*(.-)%s*$", "%1")
	if query ~= "" then
		local filtered = {}
		for _, entry in ipairs(list) do
			local matched = false
			if (entry.label or entry.name or ""):lower():find(query, 1, true) then matched = true end
			if not matched and (entry.rarity == "WWUNIQUE" or entry.rarity == "WWLEGENDARY") then
				if query == "ww" or ("weavers will"):find(query, 1, true) or ("weaver's will"):find(query, 1, true) then
					matched = true
				end
			end
			if not matched and entry.category == "basic" and entry.base and entry.base.implicits then
				for _, implText in ipairs(entry.base.implicits) do
					local cleaned = cleanImplicitText(implText)
					if cleaned and cleaned:lower():find(query, 1, true) then matched = true; break end
				end
			end
			if not matched then
				local modData = (entry.category == "unique" or entry.category == "ww") and entry.uniqueData
				             or (entry.category == "set" and entry.setData)
				if modData then
					if modData.mods then
						for _, modText in ipairs(modData.mods) do
							if modText:lower():find(query, 1, true) then matched = true; break end
						end
					end
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
			if matched then t_insert(filtered, entry) end
		end
		list = filtered
	end

	self.currentItemList = list
end

function CraftingPopupClass:SelectBase(entry)
	if not entry or entry.isImplicitRow then return end

	for key, st in pairs(self.affixState) do
		st.modKey = nil
		st.tier   = (key == "primordial") and 7 or 0
		st.ranges = {}
	end
	self.lastAffixSlot = {}
	self.corrupted = false
	if self.controls.corruptedCheck then
		self.controls.corruptedCheck.state = false
	end

	local item = new("Item")
	item.name       = entry.name
	item.baseName   = entry.baseName or entry.name
	item.base       = entry.base
	item.buffModLines          = {}
	item.enchantModLines       = {}
	item.classRequirementModLines = {}
	item.implicitModLines      = {}
	item.explicitModLines      = {}
	item.quality  = 0
	item.crafted  = true

	if entry.category == "unique" then
		item.rarity   = "UNIQUE"
		item.title    = entry.uniqueData.name
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
		item.rarity   = "WWUNIQUE"
		item.title    = entry.uniqueData.name
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
		item.rarity  = "SET"
		item.title   = entry.setData.name
		item.setID   = entry.setID
		-- Preserve set metadata so CalcSetup can aggregate N-piece bonuses.
		if entry.setData.set then
			item.setInfo = {
				setId = entry.setData.set.setId,
				name  = entry.setData.set.name,
				bonus = entry.setData.set.bonus,
			}
		end
		if entry.setData.mods then
			for i, modText in ipairs(entry.setData.mods) do
				local rollId = entry.setData.rollIds and entry.setData.rollIds[i]
				local modLine = { line = modText }
				if rollId then modLine.range = 128 end
				t_insert(item.explicitModLines, modLine)
			end
		end
	else
		item.rarity = "NORMAL"
		item.title  = nil
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

	self.editItem      = item
	self.editBaseEntry = entry
	-- Stay on item tab if just selected; user can switch to affix tabs
	local prevTab = self.rightTab
	if self.rightTab == "item" then
		-- auto-advance to prefix tab for basic items to help workflow
		if entry.category == "basic" then
			self.rightTab = "prefix"
		end
	end
	-- Only reset scroll when tab actually changed; preserve scroll when the
	-- user is just picking different items in the same list.
	if self.rightTab ~= prevTab then
		self.rightScrollY = 0
	end

	for _, k in ipairs({"prefix1","prefix2","suffix1","suffix2","sealed","primordial","corrupted"}) do
		self:UpdateSlotModInfo(k)
	end
	if entry.category == "basic" then self:RebuildEditItem() end
	self:RecalcEditLayout()
	self:RefreshAffixDropdowns()
end

-- Select or deselect an affix card in the right panel
function CraftingPopupClass:SelectAffixEntry(entry)
	local slotKey = self.rightTab
	if slotKey == "item" or not entry or not entry.statOrderKey then return end

	-- Consolidated prefix/suffix tabs: map to internal slot keys
	if slotKey == "prefix" or slotKey == "suffix" then
		local slot1 = slotKey == "prefix" and "prefix1" or "suffix1"
		local slot2 = slotKey == "prefix" and "prefix2" or "suffix2"
		local st1   = self.affixState[slot1]
		local st2   = self.affixState[slot2]
		-- Deselect if already selected in either slot
		self.lastAffixSlot = self.lastAffixSlot or {}
		if st1.modKey == entry.statOrderKey then
			st1.modKey = nil; st1.tier = 0; st1.ranges = {}
			if self.lastAffixSlot[slotKey] == slot1 then
				self.lastAffixSlot[slotKey] = st2.modKey and slot2 or nil
			end
			self:RebuildEditItem()
			return
		elseif st2.modKey == entry.statOrderKey then
			st2.modKey = nil; st2.tier = 0; st2.ranges = {}
			if self.lastAffixSlot[slotKey] == slot2 then
				self.lastAffixSlot[slotKey] = st1.modKey and slot1 or nil
			end
			self:RebuildEditItem()
			return
		end
		-- Pick a target slot:
		--   1. If slot1 is empty, always fill slot1 first.
		--   2. If only slot2 is empty, fill slot2.
		--   3. If both are occupied, replace the one that was filled
		--      FIRST (i.e. not the most recent). This preserves the user's
		--      most recent selection and avoids silently overwriting the
		--      latest card they clicked.
		self.lastAffixSlot = self.lastAffixSlot or {}
		local actualKey
		if st1.modKey == nil then
			actualKey = slot1
		elseif st2.modKey == nil then
			actualKey = slot2
		else
			local lastKey = self.lastAffixSlot[slotKey]
			if lastKey == slot2 then
				actualKey = slot1
			else
				actualKey = slot2
			end
		end
		local st = self.affixState[actualKey]
		if not st then return end
		local maxT = entry.maxTier or 0
		st.modKey = entry.statOrderKey
		st.tier   = m_min(4, maxT)
		st.ranges = {}
		self.lastAffixSlot[slotKey] = actualKey
		self:UpdateSlotModInfo(actualKey)
		local info = self.slotModInfo[actualKey]
		if info then
			for i = 1, info.count do st.ranges[i] = 128 end
			self:UpdateSlotValueEdits(actualKey)
		end
		self:RebuildEditItem()
		return
	end

	-- Single-slot tabs (sealed, primordial, corrupted)
	local st = self.affixState[slotKey]
	if st.modKey == entry.statOrderKey then
		-- Deselect
		st.modKey  = nil
		st.tier    = (slotKey == "primordial") and 7 or 0
		st.ranges  = {}
	else
		st.modKey = entry.statOrderKey
		local maxT = entry.maxTier or 0
		st.tier   = m_min(4, maxT)
		if NO_T8_SLOTS[slotKey] and st.tier > 6 then st.tier = 6 end
		st.ranges = {}
		self:UpdateSlotModInfo(slotKey)
		local info = self.slotModInfo[slotKey]
		for i = 1, info.count do st.ranges[i] = 128 end
		self:UpdateSlotValueEdits(slotKey)
	end
	self:RebuildEditItem()
end

-- =============================================================================
-- Affix list refresh (populates self.affixLists instead of dropdown controls)
-- =============================================================================
function CraftingPopupClass:RefreshAffixDropdowns()
	if not self.editItem then return end
	if self:IsAnyIdol() and data.modIdol and next(data.modIdol) then
		self:RefreshIdolAffixDropdowns()
		return
	end
	-- Set items are uncraftable: all affix tabs empty.
	if self:IsSetItem() then
		self.affixLists.prefix1    = {}
		self.affixLists.prefix2    = {}
		self.affixLists.suffix1    = {}
		self.affixLists.suffix2    = {}
		self.affixLists.sealed     = {}
		self.affixLists.primordial = {}
		self.affixLists.corrupted  = {}
		return
	end
	-- Rarity gate: Unique items cannot roll reforged (set_only, sat=3) affixes
	-- and have no Sealed / Primordial pools (those are Basic-only mechanics).
	local isUniqueOrSet = self:IsUniqueItem()

	local itemMods
	if self:IsIdolAltar() then
		itemMods = data.itemMods["Idol Altar"] or {}
	else
		itemMods = self.editItem.affixes or data.itemMods.Item
	end
	if not itemMods then return end

	local wwPool    = nil
	local wwClassBit = 0
	local itemBaseTypeID = self.editBaseEntry and self.editBaseEntry.base and self.editBaseEntry.base.baseTypeID
	if self:IsWWItem() then
		wwPool       = itemBaseTypeID and data.wwMods and data.wwMods[tostring(itemBaseTypeID)]
		wwClassBit   = self:GetWWClassBit()
	end
	local playerCsBit = self:GetCurrentClassReqBit() * 2

	-- Classify each affix into a subcategory so Phase 2 UI can section them.
	-- Buckets (keyed by statOrderKey):
	--   prefixGroups.general      : sat=0, cs=0
	--   prefixGroups.class_only   : sat=0, cs!=0 (still class-matched to player)
	--   prefixGroups.set_only     : sat=3 (reforged/set)
	--   prefixGroups.champion     : sat=2 with subcategory="champion"
	--   prefixGroups.personal     : sat=2 with subcategory="personal"
	--   prefixGroups.corrupted    : sat=6 (corrupted-only affix)
	-- Same shape for suffixGroups.
	local function newBuckets()
		return { general = {}, class_only = {}, set_only = {}, champion = {}, personal = {}, corrupted = {} }
	end
	local prefixGroups = newBuckets()
	local suffixGroups = newBuckets()

	local function classifySubcategory(mod)
		local sat = mod.specialAffixType or 0
		if sat == 0 then
			local cs = mod.classSpecificity or 0
			return cs ~= 0 and "class_only" or "general"
		elseif sat == 2 then
			return mod.subcategory == "champion" and "champion" or "personal"
		elseif sat == 3 then
			return "set_only"
		elseif sat == 6 then
			return "corrupted"
		end
		-- sat=1 (experimental) and sat=4/5 (sealed idol) are handled elsewhere
		return nil
	end

	for modId, mod in pairs(itemMods) do
		if mod.statOrderKey then
			local subcat = classifySubcategory(mod)
			if not subcat then goto continue end
			-- canRollOn filter: in both LEB bases.json and LETools affixes, the
			-- base type slot code is the same integer (e.g. Amulet=20, Shield=18).
			local cro = mod.canRollOn
			if cro and #cro > 0 and itemBaseTypeID then
				local canRoll = false
				for _, btid in ipairs(cro) do
					if btid == itemBaseTypeID then canRoll = true; break end
				end
				if not canRoll then goto continue end
			end
			-- Class filter: sat=0/2/3 respect classSpecificity vs player class.
			-- sat=6 (corrupted) typically has no class restriction but we check
			-- anyway for safety.
			if wwPool then
				local cs = wwPool[tostring(mod.statOrderKey)]
				if cs == nil then goto continue end
				if cs ~= 0 and wwClassBit ~= 0 and bit.band(cs, wwClassBit) == 0 then goto continue end
			else
				local cs = mod.classSpecificity or 0
				if cs ~= 0 and playerCsBit ~= 0 and bit.band(cs, playerCsBit) == 0 then goto continue end
			end
			local buckets = mod.type == "Prefix" and prefixGroups or (mod.type == "Suffix" and suffixGroups or nil)
			if buckets then
				local groups = buckets[subcat]
				-- Always derive the canonical label from tier 0 so UI sees a
				-- stable stat description (prior code used whichever tier
				-- iterated first, which looked like a random tier string).
				local t0 = itemMods[tostring(mod.statOrderKey) .. "_0"] or mod
				if not groups[mod.statOrderKey] then
					local labelParts = {}
					for k = 1, 10 do if t0[k] then t_insert(labelParts, t0[k]) end end
					local label = table.concat(labelParts, " / ")
					label = label:gsub("{rounding:%w+}", ""):gsub("{[^}]+}", "")
					groups[mod.statOrderKey] = {
						label = label, statOrderKey = mod.statOrderKey,
						affix = mod.affix, type = mod.type, maxTier = mod.tier or 0,
						subcategory = subcat,
					}
				else
					local g = groups[mod.statOrderKey]
					if mod.tier and mod.tier > g.maxTier then g.maxTier = mod.tier end
				end
			end
		end
		::continue::
	end

	-- Flatten buckets into legacy per-affix-type iterables. Preserves previous
	-- `for _, g in pairs(prefixGroups)` loop shape downstream.
	local function flattenBuckets(buckets, includeSubcats)
		local out = {}
		for _, sc in ipairs(includeSubcats) do
			for _, g in pairs(buckets[sc]) do t_insert(out, g) end
		end
		return out
	end
	-- Subcategory sets per rarity:
	--   Basic  : Prefix/Suffix = general+class_only+set_only ; Sealed/Primo adds champion+personal ; Corrupted adds corrupted-only
	--   Unique/
	--   Set    : Prefix/Suffix = general+class_only (set_only excluded) ; Sealed/Primo empty ; Corrupted = general+class_only+champion+personal+corrupted-only
	local ptabCats, corruptCats
	if isUniqueOrSet then
		ptabCats    = { "general", "class_only" }
		corruptCats = { "general", "class_only", "champion", "personal", "corrupted" }
	else
		ptabCats    = { "general", "class_only", "set_only" }
		corruptCats = { "general", "class_only", "set_only", "champion", "personal", "corrupted" }
	end
	local prefixIter = flattenBuckets(prefixGroups, ptabCats)
	local suffixIter = flattenBuckets(suffixGroups, ptabCats)
	-- Sealed/Primordial are Basic-only; for Unique/Set we feed empty iters so
	-- sealedList / primordialList stay empty.
	local sealedPrefixIter, sealedSuffixIter
	if isUniqueOrSet then
		sealedPrefixIter = {}
		sealedSuffixIter = {}
	else
		sealedPrefixIter = flattenBuckets(prefixGroups, { "general", "class_only", "set_only", "champion", "personal" })
		sealedSuffixIter = flattenBuckets(suffixGroups, { "general", "class_only", "set_only", "champion", "personal" })
	end
	local corruptedPrefixIter = flattenBuckets(prefixGroups, corruptCats)
	local corruptedSuffixIter = flattenBuckets(suffixGroups, corruptCats)

	local function sortByLabel(a, b)
		if not a.statOrderKey then return true end
		if not b.statOrderKey then return false end
		return (a.label or "") < (b.label or "")
	end

	local prefixList    = {}
	local suffixList    = {}
	local sealedList    = {}
	local primordialList = {}

	-- Sealed helper: push a copy capped at T6, and push a T8 primordial entry if available.
	local function pushSealedAndPrimordial(g)
		t_insert(sealedList, {
			label = g.label, statOrderKey = g.statOrderKey, affix = g.affix, type = g.type,
			maxTier = m_min(g.maxTier, 6), subcategory = g.subcategory,
		})
		if g.maxTier >= 7 then
			local t8Key = tostring(g.statOrderKey) .. "_7"
			local t8Mod = itemMods[t8Key]
			if t8Mod then
				local t8Parts = {}
				for k = 1, 10 do if t8Mod[k] then t_insert(t8Parts, t8Mod[k]) end end
				local t8Label = table.concat(t8Parts, " / "):gsub("{rounding:%w+}", ""):gsub("{[^}]+}", "")
				t_insert(primordialList, {
					label = t8Label, statOrderKey = g.statOrderKey, affix = g.affix, type = g.type,
					maxTier = 7, subcategory = g.subcategory,
				})
			end
		end
	end

	-- Prefix / Suffix tabs use the narrower iter (general + class_only + set_only).
	-- Cap maxTier at 6 (T7); T8 (index 7) is Primordial-only.
	local function copyCapped(g)
		return {
			label = g.label, statOrderKey = g.statOrderKey, affix = g.affix,
			type = g.type, maxTier = m_min(g.maxTier, 6), subcategory = g.subcategory,
		}
	end
	for _, g in ipairs(prefixIter) do t_insert(prefixList, copyCapped(g)) end
	for _, g in ipairs(suffixIter) do t_insert(suffixList, copyCapped(g)) end
	-- Sealed / Primordial include champion/personal (sat=2) on top.
	for _, g in ipairs(sealedPrefixIter) do pushSealedAndPrimordial(g) end
	for _, g in ipairs(sealedSuffixIter) do pushSealedAndPrimordial(g) end

	table.sort(prefixList, sortByLabel)
	table.sort(suffixList, sortByLabel)
	table.sort(sealedList, sortByLabel)
	table.sort(primordialList, sortByLabel)

	local function filterExclusions(list, excludeKeys)
		local filtered = {}
		for _, entry in ipairs(list) do
			local excluded = false
			for _, exKey in ipairs(excludeKeys) do
				if entry.statOrderKey == exKey then excluded = true; break end
			end
			if not excluded then t_insert(filtered, entry) end
		end
		return filtered
	end

	local p1Key = self.affixState.prefix1.modKey
	local p2Key = self.affixState.prefix2.modKey
	local s1Key = self.affixState.suffix1.modKey
	local s2Key = self.affixState.suffix2.modKey

	self.affixLists.prefix1    = filterExclusions(prefixList, p2Key and {p2Key} or {})
	self.affixLists.prefix2    = filterExclusions(prefixList, p1Key and {p1Key} or {})
	self.affixLists.suffix1    = filterExclusions(suffixList, s2Key and {s2Key} or {})
	self.affixLists.suffix2    = filterExclusions(suffixList, s1Key and {s1Key} or {})
	-- Unfiltered pools for the consolidated Prefix/Suffix tabs in the right panel.
	-- Using the p1-filtered list there would hide whichever affix is assigned to the
	-- other slot (e.g. selecting prefix2 would make that card vanish from the tab).
	self.affixLists.prefix     = prefixList
	self.affixLists.suffix     = suffixList

	local sealedExclude = {}
	if p1Key then t_insert(sealedExclude, p1Key) end
	if p2Key then t_insert(sealedExclude, p2Key) end
	if s1Key then t_insert(sealedExclude, s1Key) end
	if s2Key then t_insert(sealedExclude, s2Key) end
	self.affixLists.sealed     = filterExclusions(sealedList, sealedExclude)
	self.affixLists.primordial = filterExclusions(primordialList, sealedExclude)

	-- Corrupted list: Sealed content ∪ sat=6 corrupted-only affixes.
	-- Idol altar keeps its standalone sat=6-only path (weaver refracted slots).
	local corruptedList = {}
	if self:IsIdolAltar() then
		local corruptedGroups = {}
		for modId, mod in pairs(itemMods) do
			if mod.statOrderKey and mod.specialAffixType == 6 then
				if not corruptedGroups[mod.statOrderKey] then
					local labelParts = {}
					for k = 1, 10 do if mod[k] then t_insert(labelParts, mod[k]) end end
					local label = table.concat(labelParts, " / "):gsub("{rounding:%w+}", ""):gsub("{[^}]+}", "")
					corruptedGroups[mod.statOrderKey] = {
						label = label, statOrderKey = mod.statOrderKey,
						affix = mod.affix, type = mod.type, maxTier = mod.tier or 0,
						subcategory = "corrupted",
					}
				else
					local g = corruptedGroups[mod.statOrderKey]
					if mod.tier and mod.tier > g.maxTier then g.maxTier = mod.tier end
				end
			end
		end
		for _, g in pairs(corruptedGroups) do
			t_insert(corruptedList, { label = g.label, statOrderKey = g.statOrderKey, affix = g.affix, type = g.type, maxTier = m_min(g.maxTier, 6), subcategory = g.subcategory })
		end
	else
		for _, g in ipairs(corruptedPrefixIter) do
			t_insert(corruptedList, { label = g.label, statOrderKey = g.statOrderKey, affix = g.affix, type = g.type, maxTier = m_min(g.maxTier, 6), subcategory = g.subcategory })
		end
		for _, g in ipairs(corruptedSuffixIter) do
			t_insert(corruptedList, { label = g.label, statOrderKey = g.statOrderKey, affix = g.affix, type = g.type, maxTier = m_min(g.maxTier, 6), subcategory = g.subcategory })
		end
	end
	table.sort(corruptedList, sortByLabel)
	self.affixLists.corrupted = corruptedList

	-- Enforce T8 exclusion for non-primordial slots
	for _, slotKey in ipairs({"prefix1","prefix2","suffix1","suffix2","sealed","corrupted"}) do
		local st = self.affixState[slotKey]
		if st.modKey and st.tier >= 7 then
			st.tier = 6
			self:UpdateSlotModInfo(slotKey)
			self:UpdateSlotValueEdits(slotKey)
		end
	end
end

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
		return table.concat(parts, " / "):gsub("{rounding:%w+}", ""):gsub("{[^}]+}", "")
	end

	local idolClassReq = self.editBaseEntry and self.editBaseEntry.base and self.editBaseEntry.base.classReq or 0
	local idolCsBit    = idolClassReq * 2
	local isOmen       = self:IsOmenIdol()
	local LARGE_IDS    = { [29]=true, [30]=true, [31]=true, [32]=true, [33]=true }

	local omenPool = nil
	if isOmen then
		if baseTypeID == 29 then omenPool = { [29]=true, [31]=true, [33]=true }
		elseif baseTypeID == 30 then omenPool = { [30]=true, [32]=true, [33]=true } end
	end

	local function canRollOnIdol(mod)
		if not mod.canRollOn then return false end
		local btMatch = false
		if omenPool then
			for _, bt in ipairs(mod.canRollOn) do
				if omenPool[bt] then btMatch = true; break end
			end
		else
			for _, bt in ipairs(mod.canRollOn) do
				if bt == baseTypeID then btMatch = true; break end
			end
		end
		if not btMatch then return false end
		local cs = mod.classSpecificity or 0
		if idolClassReq == 0 then
			return cs == 0 or bit.band(cs, 1) ~= 0
		else
			local classMask = bit.band(cs, 0xFFFFFFFE)
			return classMask == 0 or idolCsBit == 0 or bit.band(classMask, idolCsBit) ~= 0
		end
	end

	local prefixList    = {}
	local suffixList    = {}
	local enchantedList = {}

	for _, pool in ipairs({ general, weaver }) do
		for _, mod in pairs(pool) do
			if mod.statOrderKey and canRollOnIdol(mod) then
				local entry = { label = buildLabel(mod), statOrderKey = mod.statOrderKey, affix = mod.affix, type = mod.type, maxTier = 0 }
				if mod.type == "Prefix" then t_insert(prefixList, entry)
				elseif mod.type == "Suffix" then t_insert(suffixList, entry) end
			end
		end
	end

	for _, mod in pairs(enchanted) do
		if mod.statOrderKey and canRollOnIdol(mod) then
			t_insert(enchantedList, { label = buildLabel(mod), statOrderKey = mod.statOrderKey, affix = mod.affix, type = mod.type, maxTier = 0 })
		end
	end

	local corruptedList = {}
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
		local filtered = {}
		for _, entry in ipairs(list) do
			local excluded = false
			for _, exKey in ipairs(excludeKeys) do
				if entry.statOrderKey == exKey then excluded = true; break end
			end
			if not excluded then t_insert(filtered, entry) end
		end
		return filtered
	end

	self.affixLists.prefix1    = prefixList
	self.affixLists.prefix2    = {}    -- idols have only 1 prefix/suffix
	self.affixLists.suffix1    = suffixList
	self.affixLists.suffix2    = {}
	self.affixLists.prefix     = prefixList
	self.affixLists.suffix     = suffixList
	self.affixLists.sealed     = filterExclusions(enchantedList, self.affixState.primordial.modKey and {self.affixState.primordial.modKey} or {})
	self.affixLists.primordial = filterExclusions(enchantedList, self.affixState.sealed.modKey and {self.affixState.sealed.modKey} or {})
	self.affixLists.corrupted  = corruptedList

	for _, slotKey in ipairs({"prefix1","suffix1","sealed","primordial","corrupted"}) do
		local st = self.affixState[slotKey]
		if st.modKey and st.tier ~= 0 then
			st.tier = 0
			self:UpdateSlotModInfo(slotKey)
			self:UpdateSlotValueEdits(slotKey)
		end
	end
end

-- =============================================================================
-- Tooltips
-- =============================================================================
function CraftingPopupClass:BuildTierTooltip(tooltip, slotKey)
	tooltip:Clear()
	tooltip.maxWidth = 520
	local st = self.affixState[slotKey]
	if not st or not st.modKey then return end
	local function getMod(key)
		if self:IsIdolAltar() then
			local altarMods = data.itemMods["Idol Altar"]
			return altarMods and altarMods[key]
		end
		local m = data.itemMods.Item and data.itemMods.Item[key]
		if not m and data.modIdol and data.modIdol.flat then m = data.modIdol.flat[key] end
		return m
	end
	local baseMod = getMod(tostring(st.modKey) .. "_0")
	if baseMod then
		tooltip:AddLine(16, colorCodes.UNIQUE .. (baseMod.affix or "Affix"))
		tooltip:AddSeparator(10)
	end
	-- Non-primordial affixes cap at T7 (tier index 6). Only the Primordial slot
	-- exposes the T8 (tier index 7) roll.
	local maxTierShow = 6
	if slotKey == "primordial" then maxTierShow = 7 end
	if self:IsAnyIdol() then maxTierShow = 0 end
	for tier = 0, maxTierShow do
		local key = tostring(st.modKey) .. "_" .. tostring(tier)
		local mod = getMod(key)
		if mod then
			local parts = {}
			for k = 1, 10 do
				local line = mod[k]
				if line and type(line) == "string" then
					local s = line:gsub("{rounding:%w+}", ""):gsub("{[^}]+}", "")
					t_insert(parts, s)
				end
			end
			local marker = (tier == st.tier) and " <<" or ""
			local col    = (tier == st.tier) and colorCodes.UNIQUE or "^7"
			tooltip:AddLine(14, col .. "Tier " .. tostring(tier + 1) .. ": " .. table.concat(parts, ", ") .. marker)
		end
	end
end

function CraftingPopupClass:BuildAffixTooltip(tooltip, statOrderKey)
	local function getMod(key)
		if self:IsIdolAltar() then
			local altarMods = data.itemMods["Idol Altar"]
			return altarMods and altarMods[key]
		end
		local m = data.itemMods.Item and data.itemMods.Item[key]
		if not m and data.modIdol and data.modIdol.flat then m = data.modIdol.flat[key] end
		return m
	end
	local baseMod = getMod(tostring(statOrderKey) .. "_0")
	if not baseMod then return end
	tooltip.maxWidth = 520
	tooltip:AddLine(16, colorCodes.UNIQUE .. (baseMod.affix or "Affix"))
	tooltip:AddSeparator(10)
	-- Non-primordial affixes display tiers T1-T7 only.
	local maxTierTooltip = self:IsAnyIdol() and 0 or 6
	for tier = 0, maxTierTooltip do
		local key = tostring(statOrderKey) .. "_" .. tostring(tier)
		local mod = getMod(key)
		if mod then
			local parts = {}
			for k = 1, 10 do
				local line = mod[k]
				if line and type(line) == "string" then
					local s = line:gsub("{rounding:%w+}", ""):gsub("{[^}]+}", "")
					t_insert(parts, s)
				end
			end
			tooltip:AddLine(14, "^7Tier " .. tostring(tier + 1) .. ": " .. table.concat(parts, ", "))
		end
	end
end

-- =============================================================================
-- Attach Item state / Draw methods (methods defined in companion modules)
-- =============================================================================
LoadModule("Classes/CraftingPopupItem", CraftingPopupClass, H)
LoadModule("Classes/CraftingPopupDraw", CraftingPopupClass, H)
