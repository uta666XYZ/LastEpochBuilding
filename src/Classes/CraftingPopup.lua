-- Last Epoch Building
--
-- Class: Crafting Popup
-- LETools-style left-right split crafting UI.
-- Left panel (320px): type list + item preview with inline affix controls.
-- Right panel (680px): item browser (item tab) or affix browser (prefix/suffix/etc tab).
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

-- Slot -> allowed item types (nil = show all)
local SLOT_TYPE_FILTER = {
	["Helmet"]     = { "Helmet" },
	["Body Armor"] = { "Body Armor" },
	["Gloves"]     = { "Gloves" },
	["Boots"]      = { "Boots" },
	["Belt"]       = { "Belt" },
	["Amulet"]     = { "Amulet" },
	["Ring 1"]     = { "Ring" },
	["Ring 2"]     = { "Ring" },
	["Relic"]      = { "Relic" },
	["Weapon 1"]   = {
		"One-Handed Axe", "Dagger", "One-Handed Mace", "Sceptre",
		"One-Handed Sword", "Wand", "Two-Handed Axe", "Two-Handed Mace",
		"Two-Handed Spear", "Two-Handed Staff", "Two-Handed Sword", "Bow",
	},
	["Weapon 2"]   = {
		-- Off-Hand slot: off-hand base types, plus weapons for dual-wield.
		"Quiver", "Shield", "Off-Hand Catalyst",
		"One-Handed Sword", "One-Handed Axe", "One-Handed Mace",
		"Dagger", "Sceptre", "Wand",
		"Two-Handed Sword", "Two-Handed Axe", "Two-Handed Mace",
		"Two-Handed Spear", "Two-Handed Staff", "Bow",
	},
}

local function filterTypeList(orderedList, slotName)
	local filter = SLOT_TYPE_FILTER[slotName]
	if not filter then return orderedList end
	local allowed = {}
	for _, t in ipairs(filter) do allowed[t] = true end
	local pending_sep = nil
	local groups = {}
	local current = nil
	for _, entry in ipairs(orderedList) do
		if entry.isSeparator then
			pending_sep = entry
			current = nil
		elseif allowed[entry.typeName] then
			if pending_sep then
				current = { sep = pending_sep, items = {} }
				t_insert(groups, current)
				pending_sep = nil
			end
			if current then t_insert(current.items, entry) end
		end
	end
	-- For Weapon 2 (Off-Hand), show Off-Hand section first, then Weapons below.
	if slotName == "Weapon 2" then
		table.sort(groups, function(a, b)
			local function rank(sep)
				if sep.label:find("Off.Hand") then return 0 end
				if sep.label:find("Weapons") then return 1 end
				return 2
			end
			return rank(a.sep) < rank(b.sep)
		end)
	end
	local filtered = {}
	for _, g in ipairs(groups) do
		t_insert(filtered, g.sep)
		for _, e in ipairs(g.items) do t_insert(filtered, e) end
	end
	return filtered
end

-- Layout constants
local POPUP_W       = 1200
local LEFT_W        = 320
local DIVIDER_X     = LEFT_W
local TYPE_LIST_Y   = 34
local TYPE_LIST_H   = 190
local TYPE_ROW_H    = 20
local PREVIEW_Y     = TYPE_LIST_Y + TYPE_LIST_H + 6   -- ~230

-- Right panel layout
local RP_X          = LEFT_W + 1
local RP_W          = POPUP_W - LEFT_W - 1
local RP_TAB_Y      = 34
local RP_TAB_H      = 24
local RP_FILTER_Y   = RP_TAB_Y + RP_TAB_H + 3
local RP_FILTER_H   = 20
local RP_CATTAB_Y   = RP_FILTER_Y + RP_FILTER_H + 3
local RP_CATTAB_H   = 20
local RP_CARD_Y     = RP_CATTAB_Y + RP_CATTAB_H + 4
local RP_CARD_PAD   = 8

-- Item cards (item tab, right panel)
local IC_COLS       = 2
local IC_GAP        = 6
local IC_W          = m_floor((RP_W - 2 * RP_CARD_PAD - (IC_COLS - 1) * IC_GAP) / IC_COLS)
local IC_H          = 80

-- Affix cards (affix tabs, right panel) -- compact single-row cards
local AC_H          = 24
local AC_GAP        = 2

-- Left panel control positions
local LP_LABEL_X    = 15
local LP_LINE_X     = 20
local LP_LINE_W     = 118
local LP_VAL_X      = 142
local LP_VAL_W      = 50
local LP_TIER_X     = 196
local LP_TRUP_X     = 213
local LP_TRDN_X     = 233
local LP_REM_X      = 254
local LP_REM_W      = 18

-- Slots where T8 is not allowed
local NO_T8_SLOTS = { prefix1=true, prefix2=true, suffix1=true, suffix2=true, sealed=true, corrupted=true }
-- Fixed-tier slots
local FIXED_TIER_SLOTS = { primordial=true }

-- Tier color codes: T1-T5 = Basic (magic blue), T6-T8 = Exalted (purple)
local TIER_COLORS = {
	[1] = "^x36A3E2",  -- T1 basic
	[2] = "^x36A3E2",  -- T2 basic
	[3] = "^x36A3E2",  -- T3 basic
	[4] = "^x36A3E2",  -- T4 basic
	[5] = "^x36A3E2",  -- T5 basic
	[6] = "^xC184FF",  -- T6 exalted
	[7] = "^xC184FF",  -- T7 exalted
	[8] = "^xC184FF",  -- T8 exalted (primordial only)
}
local function tierColor(tier0)
	return TIER_COLORS[tier0 + 1] or "^7"
end

-- Convert item display name to image filename
-- "Acolyte's Sceptre" -> "acolyte_s_sceptre.png"
local function itemNameToFilename(name)
	return name:lower():gsub("'", "_"):gsub("[^%a%d]+", "_"):gsub("_+", "_"):gsub("^_",""):gsub("_$","") .. ".png"
end

-- Rarity for crafted items based on affix count and highest tier index (0-based)
local function getRarityForAffixes(affixCount, maxTier)
	if affixCount == 0 then return "NORMAL" end
	if maxTier >= 5 then return "EXALTED" end
	if affixCount >= 3 then return "RARE" end
	return "MAGIC"
end

local function cleanImplicitText(line)
	if line:find("%[UNKNOWN_STAT%]") then return nil end
	return line:gsub("{rounding:%w+}", ""):gsub("{[^}]+}", "")
end

-- Wrap a single logical line into word-bounded chunks of at most maxChars.
-- Returns a table of strings (always at least one element if input is non-empty).
local function wrapTextLine(text, maxChars)
	if not text or text == "" then return { "" } end
	if maxChars < 1 then return { text } end
	local out = {}
	local cur = ""
	for word in text:gmatch("%S+") do
		if cur == "" then
			cur = word
		elseif #cur + 1 + #word <= maxChars then
			cur = cur .. " " .. word
		else
			t_insert(out, cur)
			cur = word
		end
		-- Hard-break a single word longer than maxChars
		while #cur > maxChars do
			t_insert(out, cur:sub(1, maxChars))
			cur = cur:sub(maxChars + 1)
		end
	end
	if cur ~= "" then t_insert(out, cur) end
	if #out == 0 then out[1] = text end
	return out
end

local function hasRange(line)
	return line:match("%(%-?%d+%.?%d*%-%-?%d+%.?%d*%)") ~= nil
end

local function getModPrecision(line)
	local precision = 100
	if line:find("{rounding:Integer}") then precision = 1
	elseif line:find("{rounding:Tenth}") then precision = 10
	elseif line:find("{rounding:Thousandth}") then precision = 1000 end
	if line:find("%%") and precision >= 100 then
		local decPart = line:match("%(%-?%d+%.(%d+)%-") or line:match("%-%-?%d+%.(%d+)%)")
		if decPart then
			precision = 10 ^ #decPart
		else
			precision = 1
		end
	end
	return precision
end

local function getRounding(line)
	if line:find("{rounding:Integer}") then return "Integer"
	elseif line:find("{rounding:Tenth}") then return "Tenth"
	elseif line:find("{rounding:Thousandth}") then return "Thousandth" end
	return nil
end

local function extractMinMax(line)
	local min, max = line:match("%(([%-]?%d+%.?%d*)%-([%-]?%d+%.?%d*)%)")
	if min and max then return tonumber(min), tonumber(max) end
	return nil, nil
end

local function computeModValue(line, range)
	local computed = itemLib.applyRange(line, range, nil, getRounding(line))
	if not computed then return nil end
	computed = computed:gsub("{rounding:%w+}", ""):gsub("{[^}]+}", "")
	local num = computed:match("([%-]?%d+%.?%d*)")
	return tonumber(num)
end

local function reverseModRange(line, targetValue)
	local min, max = extractMinMax(line)
	if not min or not max then return 128 end
	local precision = getModPrecision(line)
	local rangeSize = max - min + 1 / precision
	if rangeSize == 0 then return 0 end
	local rawRange = (targetValue - min) / rangeSize * 255
	local range = m_max(0, m_min(256, m_ceil(rawRange)))
	local actual = computeModValue(line, range)
	if actual and actual < targetValue and range < 256 then range = range + 1 end
	return range
end

local function clampModValue(line, value)
	local min, max = extractMinMax(line)
	if not min or not max then return value end
	if min <= max then return m_max(min, m_min(max, value))
	else return m_max(max, m_min(min, value)) end
end

local function formatModValue(line, value)
	local precision = getModPrecision(line)
	if precision <= 1 then return tostring(m_floor(value + 0.5))
	elseif precision <= 10 then return string.format("%.1f", value)
	elseif precision <= 100 then return string.format("%.2f", value)
	else return string.format("%.3f", value) end
end

local function buildOrderedTypeList(dataTypeList)
	local available = {}
	for _, t in ipairs(dataTypeList) do available[t] = true end
	local ordered = {}
	local sections = {
		{ header = "-- Armor --", types = {
			"Helmet", "Body Armor", "Belt", "Boots", "Gloves",
		}},
		{ header = "-- Weapons --", types = {
			"One-Handed Sword", "One-Handed Axe", "One-Handed Mace",
			"Dagger", "Sceptre", "Wand",
			"Two-Handed Sword", "Two-Handed Axe", "Two-Handed Mace",
			"Two-Handed Spear", "Two-Handed Staff", "Bow",
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
	local implicitCount = self.editItem and #self.editItem.implicitModLines or 0
	local rarity        = self.editItem and self.editItem.rarity
	local totalDisplayCount = implicitCount

	-- Affix sections start below the preview header and implicit lines
	local EDIT_START = m_max(330, PREVIEW_Y + 90 + totalDisplayCount * LINE_H)
	local y = EDIT_START
	local GAP = 4

	self.editY = {}

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
		for i = 1, #self.editItem.explicitModLines do
			self.editY.uniqueMods[i] = y
			y = y + LINE_H
		end
		y = y + GAP
	else
		self.editY.uniqueModsLabel = 0
		self.editY.uniqueMods = {}
	end

	-- Set info block (members + bonuses) for set items
	self.editY.setInfoY = 0
	if isSetItem then
		self.editY.setInfoY = y
		y = y + LINE_H + GAP  -- "ITEM SET" header + set name
		y = y + LINE_H        -- set name line
		-- count members
		local entrySetData = self.editBaseEntry and self.editBaseEntry.setData
		local setId = entrySetData and entrySetData.set and entrySetData.set.setId
		if setId ~= nil then
			local memberCount = 0
			for _, si in pairs(self.setItems or {}) do
				if si.set and si.set.setId == setId then memberCount = memberCount + 1 end
			end
			y = y + memberCount * LINE_H + GAP
		end
		-- bonuses
		local bonus = entrySetData and entrySetData.set and entrySetData.set.bonus
		if bonus then
			local bonusCount = 0
			for _ in pairs(bonus) do bonusCount = bonusCount + 1 end
			y = y + LINE_H + GAP + bonusCount * LINE_H
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

	for i = 1, 20 do
		local key = "implicit" .. i
		controls[key] = new("LabelControl", {"TOPLEFT", self, "TOPLEFT"}, LP_LINE_X,
			function() return PREVIEW_Y + 44 + 14 + 4 + i * 14 end, 0, 13, "")
		controls[key].shown = function()
			if not self_ref.editItem then return false end
			return i <= #self_ref.editItem.implicitModLines
		end
		controls[key].label = function()
			if not self_ref.editItem then return "" end
			local ml = self_ref.editItem.implicitModLines[i]
			if not ml then return "" end
			return "^7" .. itemLib.formatModLine(ml)
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
			return "^7" .. formatted
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

				controls[lineKey] = new("LabelControl", {"TOPLEFT", self, "TOPLEFT"}, LP_LINE_X,
					function()
						local ey = self_ref.editY[slotKey]
						return ey and ey[li] or 0
					end, LP_LINE_W, 14, "")
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
					if #computed > 20 then computed = computed:sub(1, 18) .. ".." end
					return col .. computed
				end

				controls[valKey] = new("EditControl", {"TOPLEFT", self, "TOPLEFT"}, LP_VAL_X,
					function()
						local ey = self_ref.editY[slotKey]
						return ey and ((ey[li] or 0) - 1) or 0
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
					return ey and ey[1] or 0
				end, 0, 14, "")
			controls[tierLabelKey].shown = function()
				if not self_ref.editItem then return false end
				if slotKey == "corrupted" and not self_ref.corrupted then return false end
				return self_ref.affixState[slotKey].modKey ~= nil
			end
			controls[tierLabelKey].label = function()
				local st = self_ref.affixState[slotKey]
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
					return ey and ey[1] or 0
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
					return ey and ey[1] or 0
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
					return ey and ey[1] or 0
				end, LP_REM_W, 18, "x", function()
					self_ref.affixState[slotKey].modKey  = nil
					self_ref.affixState[slotKey].tier    = (slotKey == "primordial") and 7 or 0
					self_ref.affixState[slotKey].ranges  = {}
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
	if self.rightTab == "item" then
		-- auto-advance to prefix tab for basic items to help workflow
		if entry.category == "basic" then
			self.rightTab = "prefix"
		end
	end
	self.rightScrollY = 0

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
		if st1.modKey == entry.statOrderKey then
			st1.modKey = nil; st1.tier = 0; st1.ranges = {}
			self:RebuildEditItem()
			return
		elseif st2.modKey == entry.statOrderKey then
			st2.modKey = nil; st2.tier = 0; st2.ranges = {}
			self:RebuildEditItem()
			return
		end
		-- Assign to first empty slot (slot1 first, then slot2)
		local actualKey = (st1.modKey == nil) and slot1 or slot2
		local st = self.affixState[actualKey]
		if not st then return end  -- both slots occupied, ignore
		local maxT = entry.maxTier or 0
		st.modKey = entry.statOrderKey
		st.tier   = m_min(4, maxT)
		st.ranges = {}
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
			tooltip:AddLine(14, col .. "T" .. tostring(tier + 1) .. ": " .. table.concat(parts, ", ") .. marker)
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
			tooltip:AddLine(14, "^7T" .. tostring(tier + 1) .. ": " .. table.concat(parts, ", "))
		end
	end
end

-- =============================================================================
-- Type helpers
-- =============================================================================
function CraftingPopupClass:IsUniqueIdol()
	return self.editBaseEntry and self.editBaseEntry.category == "unique"
		and self.editBaseEntry.type and self.editBaseEntry.type:find("Idol") and true or false
end

function CraftingPopupClass:IsAnyIdol()
	return self.editBaseEntry and self.editBaseEntry.type
		and self.editBaseEntry.type:find("Idol")
		and self.editBaseEntry.type ~= "Idol Altar" and true or false
end

function CraftingPopupClass:IsIdolAltar()
	return self.editBaseEntry and self.editBaseEntry.type == "Idol Altar" and true or false
end

function CraftingPopupClass:IsUniqueItem()
	local cat = self.editBaseEntry and self.editBaseEntry.category
	return cat == "unique" or cat == "ww"
end

function CraftingPopupClass:IsSetItem()
	return self.editBaseEntry and self.editBaseEntry.category == "set"
end

function CraftingPopupClass:IsEnchantableIdol()
	if not self.editBaseEntry or not self.editBaseEntry.base then return false end
	local bt = self.editBaseEntry.base.baseTypeID
	local st = self.editBaseEntry.base.subTypeID or 0
	if bt == nil or bt < 29 then return false end
	if bt == 33 then return st >= 7 and st <= 11 end
	return st >= 5 and st <= 9
end

function CraftingPopupClass:IsOmenIdol()
	if not self.editBaseEntry or not self.editBaseEntry.base then return false end
	local bt = self.editBaseEntry.base.baseTypeID
	local st = self.editBaseEntry.base.subTypeID or 0
	return (bt == 29 or bt == 30) and st >= 10 and st <= 14
end

function CraftingPopupClass:IsWeaverIdol()
	if not self.editBaseEntry or not self.editBaseEntry.base then return false end
	local bt = self.editBaseEntry.base.baseTypeID
	local st = self.editBaseEntry.base.subTypeID
	if bt == 25 then return st == 2 end
	if bt == 26 or bt == 27 or bt == 28 then return st == 1 end
	return false
end

local CLASS_REQ_BITS = { Primalist=1, Mage=2, Sentinel=4, Acolyte=8, Rogue=16 }
function CraftingPopupClass:GetCurrentClassReqBit()
	local spec = self.build and self.build.spec
	local name = spec and spec.curClassName
	return CLASS_REQ_BITS[name] or 0
end

function CraftingPopupClass:IsWWItem()
	local r = self.editItem and self.editItem.rarity
	return r == "WWUNIQUE" or r == "WWLEGENDARY"
end

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

-- =============================================================================
-- Rebuild edit item
-- =============================================================================
function CraftingPopupClass:RebuildEditItem()
	if not self.editItem then return end
	self.rebuilding = true

	local item         = self.editItem
	local isAltarItem  = self:IsIdolAltar()
	local itemMods     = isAltarItem and (data.itemMods["Idol Altar"] or {}) or (data.itemMods.Item or {})

	wipeTable(item.explicitModLines)
	wipeTable(item.prefixes)
	wipeTable(item.suffixes)
	item.namePrefix = ""
	item.nameSuffix = ""

	if self.editBaseEntry and self.editBaseEntry.category == "unique" and self.editBaseEntry.uniqueData then
		for i, modText in ipairs(self.editBaseEntry.uniqueData.mods) do
			local rollId  = self.editBaseEntry.uniqueData.rollIds and self.editBaseEntry.uniqueData.rollIds[i]
			local modLine = { line = modText }
			if rollId then modLine.range = 128 end
			t_insert(item.explicitModLines, modLine)
		end
	elseif self.editBaseEntry and self.editBaseEntry.category == "set" and self.editBaseEntry.setData then
		for i, modText in ipairs(self.editBaseEntry.setData.mods) do
			local rollId  = self.editBaseEntry.setData.rollIds and self.editBaseEntry.setData.rollIds[i]
			local modLine = { line = modText }
			if rollId then modLine.range = 128 end
			t_insert(item.explicitModLines, modLine)
		end
	end

	local prefixIdx  = 0
	local suffixIdx  = 0
	local affixCount = 0
	local maxTier    = 0
	local hasAffix   = false

	local slotOrder = {"prefix1","prefix2","suffix1","suffix2","sealed","primordial"}
	for _, slotKey in ipairs(slotOrder) do
		local st = self.affixState[slotKey]
		if st.modKey then
			affixCount = affixCount + 1
			hasAffix   = true
			if st.tier > maxTier then maxTier = st.tier end
			local modKey = tostring(st.modKey) .. "_" .. tostring(st.tier)
			local mod = itemMods[modKey]
			if not mod and not isAltarItem and data.modIdol and data.modIdol.flat then
				mod = data.modIdol.flat[modKey]
			end
			if mod then
				-- Guard against malformed affix data where mod.affix holds the
				-- stat description instead of the crafting title (e.g. "Increased
				-- Cooldown Recovery Speed while Transformed"). Such strings contain
				-- digits, %, parentheses, or are unusually long.
				local function isValidCraftName(s)
					if not s or s == "" or s == "UNKNOWN" then return false end
					if #s > 25 then return false end
					if s:find("[%%%(%)%+]") then return false end
					if s:find("%d") then return false end
					return true
				end
				if mod.type == "Prefix" then
					prefixIdx = prefixIdx + 1
					item.prefixes[prefixIdx] = { modId = modKey, range = st.ranges[1] or 128 }
					local pfxName = mod.affix
					if isValidCraftName(pfxName) and prefixIdx == 1 then
						item.namePrefix = pfxName .. " "
					end
				elseif mod.type == "Suffix" then
					suffixIdx = suffixIdx + 1
					item.suffixes[suffixIdx] = { modId = modKey, range = st.ranges[1] or 128 }
					local sfxName = mod.affix
					if isValidCraftName(sfxName) and suffixIdx == 1 then
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
							line = line, range = st.ranges[lineIdx] or 128,
							valueScalar = modScalar,
						})
					end
				end
			end
		end
	end

	if self.editBaseEntry and self.editBaseEntry.category == "basic" then
		item.rarity = getRarityForAffixes(affixCount, maxTier)
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

	if self.corrupted then
		local ca = self.affixState.corrupted
		if ca.modKey then
			local modKey = tostring(ca.modKey) .. "_" .. tostring(ca.tier)
			local mod = itemMods[modKey]
			if not mod and not isAltarItem and data.modIdol and data.modIdol.flat then
				mod = data.modIdol.flat[modKey]
			end
			if mod then
				local lineIdx = 0
				for k = 1, 10 do
					local line = mod[k]
					if line and type(line) == "string" then
						lineIdx = lineIdx + 1
						t_insert(item.explicitModLines, {
							line = line, range = ca.ranges[lineIdx] or 128,
							crafted = true,
						})
					end
				end
			end
		end
	end

	item.corrupted = self.corrupted
	item:BuildAndParseRaw()

	for _, k in ipairs(slotOrder) do self:UpdateSlotModInfo(k) end
	self:UpdateSlotModInfo("corrupted")
	self:RecalcEditLayout()
	self:RefreshAffixDropdowns()

	self.rebuilding = false
end

-- =============================================================================
-- Save / Restore / Close
-- =============================================================================
function CraftingPopupClass:SaveItem()
	if not self.editItem then return end
	self:RebuildEditItem()
	local savedState = {}
	for key, st in pairs(self.affixState) do
		savedState[key] = { modKey = st.modKey, tier = st.tier, ranges = {} }
		for i, r in ipairs(st.ranges) do savedState[key].ranges[i] = r end
	end
	self.editItem.craftState = {
		affixState = savedState,
		corrupted  = self.corrupted,
		baseEntry  = self.editBaseEntry,
	}
	self.itemsTab:SetDisplayItem(self.editItem)
	self:Close()
end

function CraftingPopupClass:RestoreCraftState(existingItem)
	local cs = existingItem.craftState
	self.editBaseEntry = cs.baseEntry
	self.editItem      = existingItem
	self.corrupted     = cs.corrupted
	if self.controls.corruptedCheck then
		self.controls.corruptedCheck.state = cs.corrupted
	end
	for key, saved in pairs(cs.affixState) do
		local st = self.affixState[key]
		if st then
			st.modKey = saved.modKey
			st.tier   = saved.tier
			st.ranges = {}
			for i, r in ipairs(saved.ranges) do st.ranges[i] = r end
		end
	end
	for _, k in ipairs({"prefix1","prefix2","suffix1","suffix2","sealed","primordial","corrupted"}) do
		self:UpdateSlotModInfo(k)
		self:UpdateSlotValueEdits(k)
	end
	self:RecalcEditLayout()
	self:RefreshAffixDropdowns()
	self.rightTab = "prefix"
end

function CraftingPopupClass:Close()
	if self.itemsTab then
		self.itemsTab.craftingSlotName = nil
	end
	main:ClosePopup()
end

-- =============================================================================
-- Set info panel (item set members + bonuses)
-- =============================================================================
function CraftingPopupClass:DrawSetInfo(px, py)
	local entry = self.editBaseEntry
	if not entry or entry.category ~= "set" then return end
	local sd = entry.setData
	if not sd or not sd.set then return end

	local set    = sd.set
	local setId  = set.setId
	local LINE_H = 18
	local GAP    = 4
	local y      = self.editY.setInfoY
	if not y or y <= 0 then return end

	SetDrawColor(1, 1, 1)
	DrawString(px + LP_LABEL_X, py + y, "LEFT", 14, "VAR", colorCodes.SET .. "ITEM SET")
	y = y + LINE_H + GAP
	DrawString(px + LP_LINE_X, py + y, "LEFT", 13, "VAR", "^7" .. (set.name or ""))
	y = y + LINE_H

	-- Collect and sort set members
	local members = {}
	for _, si in pairs(self.setItems or {}) do
		if si.set and si.set.setId == setId then
			local typeName = ""
			for tname, bases in pairs(self.build.data.itemBaseLists or {}) do
				for _, bEntry in ipairs(bases) do
					if bEntry.base.baseTypeID == si.baseTypeID and bEntry.base.subTypeID == si.subTypeID then
						typeName = bEntry.base.type or tname
						break
					end
				end
				if typeName ~= "" then break end
			end
			t_insert(members, { name = si.name, typeName = typeName })
		end
	end
	table.sort(members, function(a, b) return a.name < b.name end)
	for _, m in ipairs(members) do
		DrawString(px + LP_LINE_X + 8, py + y, "LEFT", 12, "VAR",
			"^8" .. m.name .. (m.typeName ~= "" and ("  " .. m.typeName) or ""))
		y = y + LINE_H
	end
	y = y + GAP

	-- Set bonuses
	local bonus = set.bonus
	if bonus and next(bonus) then
		DrawString(px + LP_LABEL_X, py + y, "LEFT", 14, "VAR", colorCodes.SET .. "SET BONUSES")
		y = y + LINE_H + GAP
		local bonusKeys = {}
		for k in pairs(bonus) do t_insert(bonusKeys, k) end
		table.sort(bonusKeys, function(a, b) return tonumber(a) < tonumber(b) end)
		for _, k in ipairs(bonusKeys) do
			DrawString(px + LP_LINE_X, py + y, "LEFT", 13, "VAR",
				"^8" .. k .. " set: ^7" .. tostring(bonus[k]))
			y = y + LINE_H
		end
	end
end

-- =============================================================================
-- Draw
-- =============================================================================
function CraftingPopupClass:Draw(viewPort)
	-- Reset alpha to 1.0 in case the dim overlay (SetDrawColor 0,0,0,0.5) left a
	-- persistent alpha state in the rendering context.
	SetDrawColor(1, 1, 1, 1)
	local px, py = self:GetPos()
	px = m_floor(px); py = m_floor(py)
	local pw, ph = self:GetSize()
	pw = m_floor(pw); ph = m_floor(ph)

	-- Popup background
	SetDrawColor(0.05, 0.05, 0.05, 1)
	DrawImage(nil, px, py, pw, ph)

	-- Outer border
	SetDrawColor(0.4, 0.35, 0.2)
	DrawImage(nil, px,          py,          pw, 2)
	DrawImage(nil, px,          py + ph - 2, pw, 2)
	DrawImage(nil, px,          py,          2,  ph)
	DrawImage(nil, px + pw - 2, py,          2,  ph)

	-- Title
	SetDrawColor(1, 1, 1)
	DrawString(px + m_floor(LEFT_W / 2), py + 12, "CENTER_X", 16, "VAR",
		"^7" .. (self.editItem and ("Craft - " .. (self.editItem.baseName or "")) or "Craft Item"))

	-- -------------------------------------------------------------------------
	-- Vertical divider
	-- -------------------------------------------------------------------------
	SetDrawColor(0.25, 0.25, 0.25)
	DrawImage(nil, px + DIVIDER_X, py + 30, 1, ph - 32)

	-- Top horizontal separator
	SetDrawColor(0.3, 0.3, 0.3)
	DrawImage(nil, px + 4, py + 30, pw - 8, 1)

	-- -------------------------------------------------------------------------
	-- Left panel: type list
	-- -------------------------------------------------------------------------
	local tlX  = px + 4
	local tlY  = py + TYPE_LIST_Y
	local tlW  = LEFT_W - 8
	local tlH  = TYPE_LIST_H
	local rowH = TYPE_ROW_H

	-- Type list background
	SetDrawColor(0.08, 0.08, 0.08)
	DrawImage(nil, tlX, tlY, tlW, tlH)

	-- Compute visible range
	local mx, my = GetCursorPos()
	local isInTypeList = mx >= tlX and mx < tlX + tlW and my >= tlY and my < tlY + tlH

	-- Clamp scroll
	local totalTypeH = #self.orderedTypeList * rowH
	local maxScroll  = m_max(0, totalTypeH - tlH)
	self.typeScrollY = m_max(0, m_min(self.typeScrollY, maxScroll))

	-- Rebuild typeCards for hit-testing
	self.typeCards = {}
	local visY = tlY - self.typeScrollY
	for i, entry in ipairs(self.orderedTypeList) do
		local cardY = visY + (i - 1) * rowH
		if cardY >= tlY and cardY + rowH <= tlY + tlH then
			if not entry.isSeparator then
				t_insert(self.typeCards, { y1 = cardY, y2 = cardY + rowH, entry = entry, index = i })
			end
			-- Background highlight for selected type
			local isSelected = (i == self.selectedTypeIndex)
			local isHovered  = isInTypeList and mx >= tlX and mx < tlX + tlW
			              and my >= cardY and my < cardY + rowH

			if entry.isSeparator then
				-- Category header row
				SetDrawColor(0.12, 0.12, 0.12)
				DrawImage(nil, tlX, cardY, tlW, rowH)
				SetDrawColor(0.55, 0.55, 0.55)
				local headerText = entry.label:gsub("%^8", "")
				DrawString(tlX + 4, cardY + 3, "LEFT", 12, "VAR", "^8" .. headerText)
			elseif isSelected then
				SetDrawColor(0.20, 0.18, 0.10)
				DrawImage(nil, tlX, cardY, tlW, rowH)
				SetDrawColor(0.8, 0.75, 0.4)
				DrawImage(nil, tlX, cardY, 2, rowH)
				SetDrawColor(1, 1, 1)
				DrawString(tlX + 6, cardY + 3, "LEFT", 13, "VAR", "^7" .. (entry.typeName or entry.label))
			elseif isHovered then
				SetDrawColor(0.14, 0.14, 0.14)
				DrawImage(nil, tlX, cardY, tlW, rowH)
				SetDrawColor(1, 1, 1)
				DrawString(tlX + 6, cardY + 3, "LEFT", 13, "VAR", "^8" .. (entry.typeName or entry.label))
			else
				SetDrawColor(1, 1, 1)
				DrawString(tlX + 6, cardY + 3, "LEFT", 13, "VAR", "^8" .. (entry.typeName or entry.label))
			end
		end
	end

	-- Type list bottom border
	SetDrawColor(0.25, 0.25, 0.25)
	DrawImage(nil, tlX, tlY + tlH, tlW, 1)

	-- -------------------------------------------------------------------------
	-- Left panel: item preview header (below type list)
	-- -------------------------------------------------------------------------
	if self.editItem then
		local item = self.editItem
		-- Type and Lv req row
		local lvReq = item.base and item.base.req and item.base.req.level or 0
		local typeStr = (item.base and item.base.type or item.type or "") ..
			(lvReq > 0 and ("  Lv " .. tostring(lvReq)) or "")
		SetDrawColor(1, 1, 1)
		DrawString(px + LP_LABEL_X, py + PREVIEW_Y + 22, "LEFT", 12, "VAR", "^8" .. typeStr)

		-- Divider below item name area
		SetDrawColor(0.2, 0.2, 0.2)
		DrawImage(nil, px + 4, py + PREVIEW_Y + 38, LEFT_W - 8, 1)

		if self:IsSetItem() then
			self:DrawSetInfo(px, py)
		end
	end

	-- -------------------------------------------------------------------------
	-- Right panel: background
	-- -------------------------------------------------------------------------
	local rpX = px + RP_X
	local rpY = py
	SetDrawColor(0.06, 0.06, 0.06)
	DrawImage(nil, rpX, rpY + 30, RP_W - 1, ph - 32)

	-- -------------------------------------------------------------------------
	-- Right panel: card content area
	-- -------------------------------------------------------------------------
	local cardAreaX = rpX + RP_CARD_PAD
	local cardAreaY = py + RP_CARD_Y
	local cardAreaW = RP_W - 2 * RP_CARD_PAD
	local cardAreaH = ph - RP_CARD_Y - 8

	self.rightCards = {}

	if self.rightTab == "item" then
		self:DrawItemCards(cardAreaX, cardAreaY, cardAreaW, cardAreaH, mx, my)
	else
		self:DrawAffixCards(cardAreaX, cardAreaY, cardAreaW, cardAreaH, mx, my)
	end

	-- -------------------------------------------------------------------------
	-- Draw Controls (overlays drawn items)
	-- -------------------------------------------------------------------------
	self:DrawControls(viewPort)
end

-- Draw item cards in the right panel
function CraftingPopupClass:DrawItemCards(areaX, areaY, areaW, areaH, mx, my)
	local list = self.currentItemList or {}
	if #list == 0 then
		SetDrawColor(1, 1, 1)
		DrawString(areaX + 4, areaY + 20, "LEFT", 14, "VAR", "^8No items found.")
		return
	end

	-- Category detection: unique/set/ww cards show full implicits + modifiers
	-- (single-column, variable-height). Basic cards keep the 2-col 80px grid.
	local firstCat = list[1] and list[1].category
	local isDetail = (firstCat == "unique" or firstCat == "set" or firstCat == "ww")

	local IMG = 46
	local DETAIL_FONT = 14       -- bumped from 12
	local DETAIL_LINE_H = 18     -- bumped from 16 to match font
	-- Approx char width for font size 14, VAR font (~7.2 px/char empirically)
	local DETAIL_CHAR_W = 7.2
	-- computeWrapLines returns the total number of visual lines after wrapping
	local function computeWrapLines(text, maxChars)
		if not text then return 0 end
		return #wrapTextLine(text, maxChars)
	end

	-- Helper: compute card height given entry (detail mode)
	local function computeCardH(entry)
		-- Card's text area width = cw - 12 (6px pad each side), chars = width / charW
		local lineW = IC_W - 12
		local maxLineChars = m_max(10, m_floor(lineW / DETAIL_CHAR_W))
		local nImplLines = 0
		if entry.base and entry.base.implicits then
			for _, implText in ipairs(entry.base.implicits) do
				local cleaned = cleanImplicitText(implText)
				if cleaned then
					nImplLines = nImplLines + computeWrapLines(cleaned, maxLineChars)
				end
			end
		end
		local mods
		if entry.category == "set" then
			mods = entry.setData and entry.setData.mods
		else
			mods = entry.uniqueData and entry.uniqueData.mods
		end
		local nModLines = 0
		if mods then
			for _, modText in ipairs(mods) do
				local cleaned = cleanImplicitText(modText)
				if cleaned then
					nModLines = nModLines + computeWrapLines(cleaned, maxLineChars)
				end
			end
		end
		local sep = (nImplLines > 0 and nModLines > 0) and 6 or 0
		-- Header: name(18) + type(16) + level(16) = ~58, then per-line DETAIL_LINE_H
		local h = 4 + 18 + 16 + 16 + 4 + (nImplLines + nModLines) * DETAIL_LINE_H + sep + 8
		return m_max(IC_H, h)
	end

	-- Precompute layout
	local cardHs, cardYs = {}, {}
	local totalH

	if isDetail then
		-- 2-column grid; each row shares the max height of its pair so the two
		-- cards on the same row are the same size.
		local y = 0
		for i = 1, #list, IC_COLS do
			local rowH = 0
			for j = 0, IC_COLS - 1 do
				local idx = i + j
				if list[idx] then
					local h = computeCardH(list[idx])
					if h > rowH then rowH = h end
				end
			end
			for j = 0, IC_COLS - 1 do
				local idx = i + j
				if list[idx] then
					cardHs[idx] = rowH
					cardYs[idx] = y
				end
			end
			y = y + rowH + IC_GAP
		end
		totalH = y
	else
		local rows = m_ceil(#list / IC_COLS)
		totalH     = rows * (IC_H + IC_GAP)
	end

	local maxScroll  = m_max(0, totalH - areaH)
	self.rightScrollY = m_max(0, m_min(self.rightScrollY, maxScroll))

	self.rightCards = {}
	local scrollY = self.rightScrollY

	-- Clip card rendering to the card area so cards that scroll above/below
	-- the area don't overlap the tab bar or other popup controls. SetViewport
	-- both clips and translates the origin, so all card draw coordinates
	-- below are relative to (areaX, areaY). Hit-test rects are still stored
	-- in absolute screen coordinates.
	SetViewport(areaX, areaY, areaW, areaH)

	for i, entry in ipairs(list) do
		local ax, ay, cw, ch         -- absolute screen coords (for hit-test)
		local col = (i - 1) % IC_COLS
		if isDetail then
			ax = areaX + col * (IC_W + IC_GAP)
			ay = areaY + cardYs[i] - scrollY
			cw = IC_W
			ch = cardHs[i]
		else
			local row = m_floor((i - 1) / IC_COLS)
			ax = areaX + col * (IC_W + IC_GAP)
			ay = areaY + row * (IC_H + IC_GAP) - scrollY
			cw = IC_W
			ch = IC_H
		end
		local ax2, ay2 = ax + cw, ay + ch
		-- Viewport-relative coords for drawing
		local cx = ax - areaX
		local cy = ay - areaY

		if ay2 > areaY and ay < areaY + areaH then
			t_insert(self.rightCards, { x1=ax, y1=ay, x2=ax2, y2=ay2, entry=entry })

			local isSelected = self.editBaseEntry and self.editBaseEntry.name == entry.name
			local isHovered  = mx >= ax and mx < ax2 and my >= ay and my < ay2

			-- Card background
			if isSelected then
				SetDrawColor(0.18, 0.16, 0.08)
			elseif isHovered then
				SetDrawColor(0.14, 0.14, 0.14)
			else
				SetDrawColor(0.10, 0.10, 0.10)
			end
			DrawImage(nil, cx, cy, cw, ch)

			-- Left accent bar (rarity color)
			local col3 = colorCodes[entry.rarity] or colorCodes.NORMAL
			local r, g, b = col3:match("%^x(%x%x)(%x%x)(%x%x)")
			if r then
				SetDrawColor(tonumber(r,16)/255, tonumber(g,16)/255, tonumber(b,16)/255)
			else
				SetDrawColor(0.5, 0.5, 0.5)
			end
			DrawImage(nil, cx, cy, 3, ch)

			-- Item image (46x46, left side)
			local imgHandle = self:GetItemImage(entry.name, entry.rarity)
			if imgHandle and imgHandle:IsValid() then
				SetDrawColor(1, 1, 1)
				DrawImage(imgHandle, cx + 4, cy + 4, IMG, IMG)
			end
			local textX = cx + IMG + 8
			local textW = cw - IMG - 12

			-- Item name (line 1)
			local maxChars = m_floor(textW / 7)
			local label = entry.label or entry.name
			local truncLabel = #label > maxChars and label:sub(1, maxChars - 2) .. ".." or label
			DrawString(textX, cy + 4, "LEFT", 16, "VAR", (col3 or "^7") .. truncLabel)

			-- Item type (line 2)
			local typeStr = "^8" .. (entry.displayType or "")
			DrawString(textX, cy + 24, "LEFT", 14, "VAR", typeStr)

			-- Level requirement (line 3)
			local lvReq = entry.base and entry.base.req and entry.base.req.level or 0
			if lvReq > 0 then
				DrawString(textX, cy + 40, "LEFT", 14, "VAR", "^8Lv. " .. tostring(lvReq))
			end

			if isDetail then
				-- Full implicits + modifiers list, spans full card width below header
				local lineX = cx + 6
				local lineW = cw - 12
				local maxLineChars = m_max(10, m_floor(lineW / DETAIL_CHAR_W))
				local ly = cy + 58
				-- Alternating affix background: each affix (implicit or modifier)
				-- gets its own bg band so wrapped lines visually group together.
				local affixIdx = 0
				local function drawAffix(text, color)
					if not text then return end
					local lines = wrapTextLine(text, maxLineChars)
					local blockH = #lines * DETAIL_LINE_H
					affixIdx = affixIdx + 1
					-- Alternating bands: darker/lighter based on affixIdx parity.
					if affixIdx % 2 == 1 then
						SetDrawColor(0.14, 0.14, 0.16)
					else
						SetDrawColor(0.09, 0.09, 0.11)
					end
					DrawImage(nil, lineX - 2, ly - 1, lineW + 4, blockH)
					for _, ln in ipairs(lines) do
						DrawString(lineX, ly, "LEFT", DETAIL_FONT, "VAR", (color or "^8") .. ln)
						ly = ly + DETAIL_LINE_H
					end
				end
				if entry.base and entry.base.implicits then
					for _, implText in ipairs(entry.base.implicits) do
						drawAffix(cleanImplicitText(implText), "^x8888FF")
					end
				end
				local mods
				if entry.category == "set" then
					mods = entry.setData and entry.setData.mods
				else
					mods = entry.uniqueData and entry.uniqueData.mods
				end
				if mods and #mods > 0 then
					if entry.base and entry.base.implicits and #entry.base.implicits > 0 then
						ly = ly + 6
					end
					for _, modText in ipairs(mods) do
						drawAffix(cleanImplicitText(modText), "^7")
					end
				end
			else
				-- Basic card: single implicit line
				local implText
				if entry.base and entry.base.implicits and entry.base.implicits[1] then
					implText = cleanImplicitText(entry.base.implicits[1])
				end
				if implText then
					local maxImpl = m_floor(textW / 6.5)
					local truncImpl = #implText > maxImpl and implText:sub(1, maxImpl - 2) .. ".." or implText
					DrawString(textX, cy + 58, "LEFT", 14, "VAR", "^8" .. truncImpl)
				end
			end

			-- Card border
			if isSelected then
				SetDrawColor(0.8, 0.7, 0.3)
			elseif isHovered then
				SetDrawColor(0.35, 0.35, 0.35)
			else
				SetDrawColor(0.2, 0.2, 0.2)
			end
			DrawImage(nil, cx,      cy,      cw, 1)
			DrawImage(nil, cx,      cy+ch-1, cw, 1)
			DrawImage(nil, cx,      cy,      1, ch)
			DrawImage(nil, cx+cw-1, cy,      1, ch)
		end
	end
	SetViewport()

	-- Scrollbar
	if maxScroll > 0 then
		local sbX = areaX + areaW + 2
		local thH = m_max(20, m_floor(areaH * areaH / totalH))
		local thY = areaY + m_floor((areaH - thH) * self.rightScrollY / maxScroll)
		SetDrawColor(0.15, 0.15, 0.15)
		DrawImage(nil, sbX, areaY, 4, areaH)
		SetDrawColor(0.50, 0.45, 0.30)
		DrawImage(nil, sbX, thY, 4, thH)
	end
end

-- Draw affix cards in the right panel (list or card view)
function CraftingPopupClass:DrawAffixCards(areaX, areaY, areaW, areaH, mx, my)
	local slotKey  = self.rightTab
	-- Map consolidated tabs to their primary internal list
	local listKey  = (slotKey == "prefix") and "prefix1"
	              or (slotKey == "suffix") and "suffix1"
	              or slotKey
	local list     = self.affixLists[listKey] or {}
	local cardMode = (self.affixViewMode == "card")
	local rowH     = cardMode and 72 or AC_H   -- taller card rows for larger text
	local gap      = cardMode and 6  or AC_GAP
	local nCols    = cardMode and 2 or 1        -- card mode: 2-column layout
	local colGap   = 6
	local cardW    = cardMode and m_floor((areaW - colGap) / 2) or areaW

	-- List-mode layout (2-col cards with stat_name / craft_name / Tier N lines)
	local LIST_STAT_H  = 18  -- stat name header
	local LIST_CRAFT_H = 16  -- craft name subheader
	local LIST_TIER_H  = 15  -- per-tier line
	local LIST_PAD     = 6
	local listColGap   = 6
	local listCardW    = m_floor((areaW - listColGap) / 2)
	-- Kept for legacy single-col path (no longer used but harmless if referenced)
	local LIST_NAME_H = LIST_STAT_H
	-- Fetch + cache tier stat lines for an entry (reused from BuildAffixTooltip logic).
	local self_ref = self
	local function getAffixTierLines(entry)
		if entry._tierLines then return entry._tierLines end
		local function getMod(key)
			if self_ref:IsIdolAltar() then
				local altarMods = data.itemMods["Idol Altar"]
				return altarMods and altarMods[key]
			end
			local m = data.itemMods.Item and data.itemMods.Item[key]
			if not m and data.modIdol and data.modIdol.flat then m = data.modIdol.flat[key] end
			return m
		end
		-- Extract LETools-style "a to b%" or "n%" range from a cleaned stat line.
		local function extractRange(text)
			if not text or text == "" then return text or "" end
			-- Range in parentheses: (a-b) optionally followed by %
			local a, b, pct = text:match("%((%-?[%d%.]+)%-(%-?[%d%.]+)%)(%%?)")
			if a and b then
				return a .. (pct or "") .. " to " .. b .. (pct or "")
			end
			-- Single value: +5% or 6 or -2
			local sign, n, pct2 = text:match("([%+%-]?)([%d%.]+)(%%?)")
			if n then
				return (sign or "") .. n .. (pct2 or "")
			end
			return text
		end
		local out  = {}
		local maxT = entry.maxTier or 0
		for tier = 0, maxT do
			local mod = getMod(tostring(entry.statOrderKey) .. "_" .. tostring(tier))
			if mod then
				local parts, ranges = {}, {}
				for k = 1, 10 do
					local line = mod[k]
					if line and type(line) == "string" then
						local s = line:gsub("{rounding:%w+}", ""):gsub("{[^}]+}", "")
						t_insert(parts, s)
						t_insert(ranges, extractRange(s))
					end
				end
				t_insert(out, {
					tier = tier,
					text = table.concat(parts, ", "),
					range = table.concat(ranges, ", "),
					parts = parts,
					ranges = ranges,
				})
			end
		end
		entry._tierLines = out
		return out
	end

	if not self.editItem then
		SetDrawColor(1, 1, 1)
		DrawString(areaX + 4, areaY + 20, "LEFT", 14, "VAR", "^8Select an item first.")
		return
	end
	if #list == 0 then
		SetDrawColor(1, 1, 1)
		DrawString(areaX + 4, areaY + 20, "LEFT", 14, "VAR", "^8No affixes available.")
		return
	end

	-- Apply search filter
	local query = (self.searchText or ""):lower():gsub("^%s*(.-)%s*$", "%1")
	local filteredList = list
	if query ~= "" then
		filteredList = {}
		for _, entry in ipairs(list) do
			if (entry.label or ""):lower():find(query, 1, true) or
			   (entry.affix or ""):lower():find(query, 1, true) then
				t_insert(filteredList, entry)
			end
		end
	end

	-- For consolidated prefix/suffix tabs, check both slots for selection
	local function isEntrySelected(statOrderKey)
		if slotKey == "prefix" then
			return (self.affixState.prefix1.modKey == statOrderKey)
			    or (self.affixState.prefix2.modKey == statOrderKey)
		elseif slotKey == "suffix" then
			return (self.affixState.suffix1.modKey == statOrderKey)
			    or (self.affixState.suffix2.modKey == statOrderKey)
		else
			return self.affixState[slotKey] and self.affixState[slotKey].modKey == statOrderKey
		end
	end

	-- For consolidated tabs, find the active selected slot (for tier display)
	local function getSelectedSlotState(statOrderKey)
		if slotKey == "prefix" then
			if self.affixState.prefix1.modKey == statOrderKey then return self.affixState.prefix1, "P1" end
			if self.affixState.prefix2.modKey == statOrderKey then return self.affixState.prefix2, "P2" end
		elseif slotKey == "suffix" then
			if self.affixState.suffix1.modKey == statOrderKey then return self.affixState.suffix1, "S1" end
			if self.affixState.suffix2.modKey == statOrderKey then return self.affixState.suffix2, "S2" end
		else
			return self.affixState[slotKey], nil
		end
	end

	-- Phase 2: group entries by subcategory
	local SUBCAT_ORDER = { "general", "class_only", "set_only", "champion", "personal", "corrupted" }
	local SUBCAT_LABELS = {
		general    = "General",
		class_only = "Class Specific",
		set_only   = "Reforged / Set",
		champion   = "Champion",
		personal   = "Personal",
		corrupted  = "Corrupted Only",
	}
	local groups = {}
	for _, sc in ipairs(SUBCAT_ORDER) do groups[sc] = {} end
	for _, entry in ipairs(filteredList) do
		local sc = entry.subcategory or "general"
		if not groups[sc] then groups[sc] = {}; t_insert(SUBCAT_ORDER, sc) end
		t_insert(groups[sc], entry)
	end

	-- Build a flat render plan (headers + entries), respecting collapse state
	self.collapsedSubcats[slotKey] = self.collapsedSubcats[slotKey] or {}
	local collapsed = self.collapsedSubcats[slotKey]
	local HEADER_H = 20
	local plan = {}  -- each item: { kind="header"|"entry", subcat=..., entry=..., h=... }
	for _, sc in ipairs(SUBCAT_ORDER) do
		local g = groups[sc]
		if g and #g > 0 then
			-- Always show header if there is more than one non-empty subcat total, or if it's non-general.
			local showHeader = (sc ~= "general") or false
			-- If general is the only group, skip its header; otherwise show a header for it too.
			if sc == "general" then
				local otherNonEmpty = false
				for _, sc2 in ipairs(SUBCAT_ORDER) do
					if sc2 ~= "general" and groups[sc2] and #groups[sc2] > 0 then
						otherNonEmpty = true; break
					end
				end
				showHeader = otherNonEmpty
			end
			if showHeader then
				t_insert(plan, { kind = "header", subcat = sc, h = HEADER_H, count = #g })
			end
			if not collapsed[sc] then
				if cardMode then
					-- Pack entries into rows of up to nCols
					for i = 1, #g, nCols do
						local rowEntries = {}
						for k = 0, nCols - 1 do
							if g[i + k] then t_insert(rowEntries, g[i + k]) end
						end
						t_insert(plan, { kind = "entryRow", entries = rowEntries, h = rowH })
					end
				else
					-- List mode: 2-col rows with dynamic per-row height
					for i = 1, #g, 2 do
						local rowEntries = {}
						local maxH = 0
						for k = 0, 1 do
							local e = g[i + k]
							if e then
								t_insert(rowEntries, e)
								local tls = getAffixTierLines(e)
								local nT = #tls
								if nT == 0 then nT = 1 end
								local function isCraftName(s)
									if not s or s == "" or s == "UNKNOWN" then return false end
									if #s > 25 then return false end
									if s:find("[%%%(%)%+]") then return false end
									if s:find("%d") then return false end
									return true
								end
								local craftH = isCraftName(e.affix or "") and LIST_CRAFT_H or 0
								local headerH = 0
								if tls[1] and tls[1].ranges and #tls[1].ranges >= 2 then
									headerH = LIST_TIER_H
								end
								local eH = LIST_PAD * 2 + LIST_STAT_H + craftH + headerH + nT * LIST_TIER_H
								if eH > maxH then maxH = eH end
							end
						end
						if maxH == 0 then maxH = LIST_PAD * 2 + LIST_STAT_H + LIST_CRAFT_H + LIST_TIER_H end
						t_insert(plan, { kind = "listRow", entries = rowEntries, h = maxH })
					end
				end
			end
		end
	end

	-- Compute total height
	local totalH = 0
	for _, it in ipairs(plan) do totalH = totalH + it.h + gap end
	local maxScroll = m_max(0, totalH - areaH)
	self.rightScrollY = m_max(0, m_min(self.rightScrollY, maxScroll))

	self.rightCards = {}
	local scrollY   = self.rightScrollY
	local yCursor   = areaY - scrollY

	for _, it in ipairs(plan) do
		local cy  = yCursor
		local cy2 = cy + it.h
		yCursor = cy2 + gap

		if it.kind == "header" then
			if cy < areaY + areaH and cy2 > areaY then
				-- Header hit-test + background
				t_insert(self.rightCards, { x1=areaX, y1=cy, x2=areaX+areaW, y2=cy2, isHeader=true, subcat=it.subcat })
				local isHoveredH = mx >= areaX and mx < areaX + areaW and my >= cy and my < cy2
				if isHoveredH then
					SetDrawColor(0.20, 0.20, 0.22)
				else
					SetDrawColor(0.13, 0.13, 0.16)
				end
				DrawImage(nil, areaX, cy, areaW, it.h)
				SetDrawColor(0.35, 0.35, 0.40)
				DrawImage(nil, areaX, cy2 - 1, areaW, 1)
				local arrow = collapsed[it.subcat] and "^7> " or "^7v "
				local title = arrow .. "^xFFCC66" .. (SUBCAT_LABELS[it.subcat] or it.subcat)
				              .. " ^8(" .. tostring(it.count) .. ")"
				DrawString(areaX + 8, cy + 2, "LEFT", 14, "VAR", title)
			end
		end
		if it.kind == "entryRow" then
			-- 2-column card row
			for ci, entry in ipairs(it.entries) do
				local cx1 = areaX + (ci - 1) * (cardW + colGap)
				local cx2 = cx1 + cardW
				if cy >= areaY and cy2 <= areaY + areaH then
					t_insert(self.rightCards, { x1=cx1, y1=cy, x2=cx2, y2=cy2, entry=entry })
					local isSelected = isEntrySelected(entry.statOrderKey)
					local isHovered  = mx >= cx1 and mx < cx2 and my >= cy and my < cy2
					-- Card background + border (distinct card look)
					if isSelected then
						SetDrawColor(0.30, 0.26, 0.10)
					elseif isHovered then
						SetDrawColor(0.18, 0.18, 0.20)
					else
						SetDrawColor(0.12, 0.12, 0.14)
					end
					DrawImage(nil, cx1, cy, cardW, rowH)
					-- Outer border
					SetDrawColor(isSelected and 0.70 or 0.32, isSelected and 0.60 or 0.32, isSelected and 0.22 or 0.36)
					DrawImage(nil, cx1, cy, cardW, 1)
					DrawImage(nil, cx1, cy2 - 1, cardW, 1)
					DrawImage(nil, cx1, cy, 1, rowH)
					DrawImage(nil, cx2 - 1, cy, 1, rowH)
					-- Left accent bar: Prefix=blue, Suffix=orange
					local typeStr = entry.type or ""
					if typeStr == "Prefix" then
						SetDrawColor(0.33, 0.60, 1.0)
					else
						SetDrawColor(1.0, 0.60, 0.33)
					end
					DrawImage(nil, cx1 + 1, cy + 1, 4, rowH - 2)
					-- Affix name
					local nameCol = isSelected and colorCodes.UNIQUE or "^7"
					DrawString(cx1 + 10, cy + 6, "LEFT", 15, "VAR",
						nameCol .. (entry.affix or entry.label or ""))
					-- First stat (description)
					local desc = entry.label or ""
					desc = desc:gsub("{rounding:%w+}", ""):gsub("{[^}]+}", "")
					local firstPart = desc:match("^(.-)%s*/%s*.+$") or desc
					local maxChars = m_floor((cardW - 20) / 7)
					if #firstPart > maxChars then firstPart = firstPart:sub(1, maxChars - 2) .. ".." end
					DrawString(cx1 + 10, cy + 26, "LEFT", 13, "VAR", "^8" .. firstPart)
					-- Tier range inside card (bottom-right)
					local maxT = entry.maxTier or 0
					local tierStr = maxT > 0
						and (TIER_COLORS[1] .. "T1^8-" .. tierColor(maxT) .. "T" .. tostring(maxT + 1))
						or  (TIER_COLORS[1] .. "T1")
					DrawString(cx2 - 8, cy + rowH - 18, "RIGHT", 13, "VAR", tierStr)
					-- Selection indicator
					if isSelected then
						local st, slotLabel = getSelectedSlotState(entry.statOrderKey)
						if st and st.modKey then
							local t1 = st.tier + 1
							local indicator = tierColor(st.tier) .. "T" .. tostring(t1)
							if slotLabel then indicator = indicator .. " ^8(" .. slotLabel .. ")" end
							DrawString(cx1 + 10, cy + rowH - 18, "LEFT", 13, "VAR", "^xFFCC44> " .. indicator)
						end
					end
				end
			end
		end
		if it.kind == "listRow" then
			local rowEntryH = it.h
			for ci, entry in ipairs(it.entries) do
				local cx1 = areaX + (ci - 1) * (listCardW + listColGap)
				local cx2 = cx1 + listCardW
				if cy < areaY + areaH and cy2 > areaY then
					t_insert(self.rightCards, { x1=cx1, y1=cy, x2=cx2, y2=cy2, entry=entry })
					local isSelected = isEntrySelected(entry.statOrderKey)
					local isHovered  = mx >= cx1 and mx < cx2 and my >= cy and my < cy2
					-- Card background
					if isSelected then
						SetDrawColor(0.22, 0.18, 0.06)
					elseif isHovered then
						SetDrawColor(0.14, 0.14, 0.16)
					else
						SetDrawColor(0.10, 0.10, 0.12)
					end
					DrawImage(nil, cx1, cy, listCardW, rowEntryH)
					-- Border
					SetDrawColor(isSelected and 0.78 or 0.26, isSelected and 0.64 or 0.26, isSelected and 0.16 or 0.30)
					DrawImage(nil, cx1, cy, listCardW, 1)
					DrawImage(nil, cx1, cy2 - 1, listCardW, 1)
					DrawImage(nil, cx1, cy, 1, rowEntryH)
					DrawImage(nil, cx2 - 1, cy, 1, rowEntryH)
					-- Accent bar: Prefix=blue, Suffix=orange
					local typeStr = entry.type or ""
					if typeStr == "Prefix" then
						SetDrawColor(0.33, 0.60, 1.0)
					else
						SetDrawColor(1.0, 0.60, 0.33)
					end
					DrawImage(nil, cx1 + 1, cy + 1, 3, rowEntryH - 2)

					local textX  = cx1 + 10
					local availW = listCardW - (textX - cx1) - 8
					local maxCh  = m_floor(availW / 6.8)

					-- Row 1: stat name (stripped label)
					local stat = (entry.label or ""):gsub("{rounding:%w+}", ""):gsub("{[^}]+}", "")
					stat = stat:match("^(.-)%s*/%s*.+$") or stat
					if #stat > maxCh then stat = stat:sub(1, maxCh - 2) .. ".." end
					local statCol = isSelected and colorCodes.UNIQUE or "^7"
					DrawString(textX, cy + LIST_PAD, "LEFT", 14, "VAR", statCol .. stat)

					-- Row 2: craft name (entry.affix) — only when it looks like a real name
					local rawCraft = entry.affix or ""
					local function isName(s)
						if not s or s == "" or s == "UNKNOWN" then return false end
						if #s > 25 then return false end
						if s:find("[%%%(%)%+]") then return false end
						if s:find("%d") then return false end
						return true
					end
					local hasCraft = isName(rawCraft)
					if hasCraft then
						local craft = rawCraft
						if #craft > maxCh then craft = craft:sub(1, maxCh - 2) .. ".." end
						DrawString(textX, cy + LIST_PAD + LIST_STAT_H, "LEFT", 12, "VAR",
							"^8" .. craft)
					end

					-- Row 3+: per-tier lines, LETools style "Tier N   a to b%"
					local tierLines = getAffixTierLines(entry)
					local selTier = nil
					if isSelected then
						local st = getSelectedSlotState(entry.statOrderKey)
						if st then selTier = st.tier end
					end
					local craftSkip = hasCraft and LIST_CRAFT_H or 0
					local lineY = cy + LIST_PAD + LIST_STAT_H + craftSkip

					-- Detect multi-modifier affix (2+ stat lines)
					local nMods = (tierLines[1] and tierLines[1].ranges) and #tierLines[1].ranges or 1
					if nMods >= 2 then
						-- Strip range tokens to get bare stat name
						local function statName(s)
							if not s or s == "" then return "" end
							s = s:gsub("%b()%%?", "")
							s = s:gsub("[%+%-]?[%d%.]+%%?", "")
							s = s:gsub("^%s+", ""):gsub("%s+$", "")
							s = s:gsub("%s+", " ")
							return s
						end
						local parts0 = tierLines[1].parts or {}
						local colW = m_floor((listCardW - (textX - cx1) - 8) / 2)
						local col1X = textX + 2
						local col2X = textX + 2 + colW
						-- Header: two stat names
						local n1 = statName(parts0[1] or "")
						local n2 = statName(parts0[2] or "")
						local nbudget = m_floor(colW / 6.8) - 1
						if #n1 > nbudget then n1 = n1:sub(1, nbudget - 2) .. ".." end
						if #n2 > nbudget then n2 = n2:sub(1, nbudget - 2) .. ".." end
						DrawString(col1X, lineY, "LEFT", 11, "VAR", "^8" .. n1)
						DrawString(col2X, lineY, "LEFT", 11, "VAR", "^8" .. n2)
						lineY = lineY + LIST_TIER_H
						for _, tl in ipairs(tierLines) do
							local tLabel = tierColor(tl.tier) .. "T" .. tostring(tl.tier + 1)
							local r1 = (tl.ranges and tl.ranges[1]) or ""
							local r2 = (tl.ranges and tl.ranges[2]) or ""
							local col = (selTier == tl.tier) and colorCodes.UNIQUE or tierColor(tl.tier)
							local marker = (selTier == tl.tier) and "  <<" or ""
							DrawString(col1X, lineY, "LEFT", 12, "VAR",
								tLabel .. " " .. col .. r1)
							DrawString(col2X, lineY, "LEFT", 12, "VAR", col .. r2 .. marker)
							lineY = lineY + LIST_TIER_H
						end
					else
						for _, tl in ipairs(tierLines) do
							local tLabel = tierColor(tl.tier) .. "Tier " .. tostring(tl.tier + 1)
							local txt = tl.range or tl.text or ""
							local budget = maxCh - 10
							if #txt > budget then txt = txt:sub(1, budget - 2) .. ".." end
							local marker = (selTier == tl.tier) and "  <<" or ""
							local col = (selTier == tl.tier) and colorCodes.UNIQUE or tierColor(tl.tier)
							DrawString(textX + 2, lineY, "LEFT", 13, "VAR",
								tLabel .. "   " .. col .. txt .. marker)
							lineY = lineY + LIST_TIER_H
						end
					end

					-- Selection right indicator
					if isSelected then
						local st, slotLabel = getSelectedSlotState(entry.statOrderKey)
						if st and st.modKey then
							local t1 = st.tier + 1
							local indicator = tierColor(st.tier) .. "T" .. tostring(t1)
							if slotLabel then indicator = indicator .. " ^8(" .. slotLabel .. ")" end
							DrawString(cx2 - 8, cy + LIST_PAD, "RIGHT", 12, "VAR",
								"^xFFCC44> " .. indicator)
						end
					end
				end
			end
		end
		if false and it.kind == "entry" then
			local entry = it.entry
			local entryH = it.h

			if cy < areaY + areaH and cy2 > areaY then
			t_insert(self.rightCards, { x1=areaX, y1=cy, x2=areaX+areaW, y2=cy2, entry=entry })

			local isSelected = isEntrySelected(entry.statOrderKey)
			local isHovered  = mx >= areaX and mx < areaX + areaW and my >= cy and my < cy2

			-- Card background
			if isSelected then
				SetDrawColor(0.18, 0.16, 0.08)
			elseif isHovered then
				SetDrawColor(0.14, 0.14, 0.14)
			else
				SetDrawColor(0.10, 0.10, 0.10)
			end
			DrawImage(nil, areaX, cy, areaW, entryH)

			-- Left accent bar: blue for Prefix, orange for Suffix
			local typeStr  = entry.type or ""
			if typeStr == "Prefix" then
				SetDrawColor(0.33, 0.60, 1.0)
			else
				SetDrawColor(1.0, 0.60, 0.33)
			end
			DrawImage(nil, areaX, cy, 3, entryH)

			-- Affix name
			local nameCol = isSelected and colorCodes.UNIQUE or "^7"
			local nameX   = areaX + 10
			local nameY   = cy + LIST_PAD
			DrawString(nameX, nameY, "LEFT", 14, "VAR",
				nameCol .. (entry.affix or entry.label or ""))

			-- Vertical tier list: "Tier N: <stat text>"
			local tierLines = getAffixTierLines(entry)
			local lineX   = areaX + 14
			local lineY   = cy + LIST_PAD + LIST_NAME_H
			local availW  = areaW - (lineX - areaX) - 10
			local maxCh   = m_floor(availW / 6.8)
			local selTier = nil
			if isSelected then
				local st = getSelectedSlotState(entry.statOrderKey)
				if st then selTier = st.tier end
			end
			for _, tl in ipairs(tierLines) do
				local tLabel = tierColor(tl.tier) .. "Tier " .. tostring(tl.tier + 1) .. ":"
				local txt = tl.text or ""
				if #txt > maxCh - 10 then txt = txt:sub(1, maxCh - 12) .. ".." end
				local marker = (selTier == tl.tier) and "  <<" or ""
				local col = (selTier == tl.tier) and colorCodes.UNIQUE or "^8"
				DrawString(lineX, lineY, "LEFT", 13, "VAR",
					tLabel .. " " .. col .. txt .. marker)
				lineY = lineY + LIST_TIER_H
			end

			-- Selection indicator bar
			if isSelected then
				SetDrawColor(0.8, 0.7, 0.3)
				DrawImage(nil, areaX, cy, 3, entryH)
				local st, slotLabel = getSelectedSlotState(entry.statOrderKey)
				if st and st.modKey then
					local t1 = st.tier + 1
					local indicator = tierColor(st.tier) .. "T" .. tostring(t1)
					if slotLabel then indicator = indicator .. " ^8(" .. slotLabel .. ")" end
					DrawString(areaX + areaW - 6, cy + LIST_PAD, "RIGHT", 13, "VAR", indicator)
				end
			end

			-- Row separator
			SetDrawColor(0.18, 0.18, 0.20)
			DrawImage(nil, areaX, cy2 - 1, areaW, 1)
		end
		end
	end

	-- Scrollbar on right border (visible when content overflows)
	if maxScroll > 0 then
		local sbX  = areaX + areaW + 2
		local sbH  = areaH
		local thH  = m_max(20, m_floor(areaH * areaH / totalH))
		local thY  = areaY + m_floor((sbH - thH) * self.rightScrollY / maxScroll)
		SetDrawColor(0.15, 0.15, 0.15)
		DrawImage(nil, sbX, areaY, 4, areaH)
		SetDrawColor(0.50, 0.45, 0.30)
		DrawImage(nil, sbX, thY, 4, thH)
	end
end

-- =============================================================================
-- Input handling
-- =============================================================================
function CraftingPopupClass:ProcessInput(inputEvents, viewPort)
	local mx, my = GetCursorPos()
	local px, py = self:GetPos()
	local pw, ph = self:GetSize()

	for id, event in ipairs(inputEvents) do
		if event.type == "KeyDown" then
			if event.key == "ESCAPE" then
				self:Close()
				return
			elseif event.key == "LEFTBUTTON" then
				-- Type list click
				local tlX = px + 4
				local tlY = py + TYPE_LIST_Y
				local tlW = LEFT_W - 8
				local tlH = TYPE_LIST_H
				if mx >= tlX and mx < tlX + tlW and my >= tlY and my < tlY + tlH then
					for _, card in ipairs(self.typeCards) do
						if my >= card.y1 and my < card.y2 then
							self.selectedTypeIndex = card.index
							self.rightScrollY = 0
							self.searchText   = ""
							if self.controls.rightSearch then
								self.controls.rightSearch:SetText("")
							end
							self:RefreshBaseList()
							break
						end
					end
				end

				-- Right panel card click
				local rpX = px + RP_X
				if mx >= rpX and mx < px + pw then
					for _, card in ipairs(self.rightCards) do
						if mx >= card.x1 and mx < card.x2 and my >= card.y1 and my < card.y2 then
							if card.isHeader then
								-- Toggle subcategory collapse state
								local slotKey = self.rightTab
								self.collapsedSubcats[slotKey] = self.collapsedSubcats[slotKey] or {}
								self.collapsedSubcats[slotKey][card.subcat] = not self.collapsedSubcats[slotKey][card.subcat]
							elseif self.rightTab == "item" then
								self:SelectBase(card.entry)
							else
								self:SelectAffixEntry(card.entry)
							end
							break
						end
					end
				end
			elseif event.key == "WHEELDOWN" then
				local tlX = px + 4
				local tlY = py + TYPE_LIST_Y
				local tlW = LEFT_W - 8
				local tlH = TYPE_LIST_H
				if mx >= tlX and mx < tlX + tlW and my >= tlY and my < tlY + tlH then
					self.typeScrollY = self.typeScrollY + TYPE_ROW_H * 3
				elseif mx >= px + RP_X and mx < px + pw then
					local rowStep = (self.rightTab ~= "item" and self.affixViewMode == "card") and 54 or AC_H
					self.rightScrollY = self.rightScrollY + rowStep * 3
				end
			elseif event.key == "WHEELUP" then
				local tlX = px + 4
				local tlY = py + TYPE_LIST_Y
				local tlW = LEFT_W - 8
				local tlH = TYPE_LIST_H
				if mx >= tlX and mx < tlX + tlW and my >= tlY and my < tlY + tlH then
					self.typeScrollY = self.typeScrollY - TYPE_ROW_H * 3
				elseif mx >= px + RP_X and mx < px + pw then
					local rowStep = (self.rightTab ~= "item" and self.affixViewMode == "card") and 54 or AC_H
					self.rightScrollY = self.rightScrollY - rowStep * 3
				end
			end
		end
	end

	self:ProcessControlsInput(inputEvents, viewPort)
end
