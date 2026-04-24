-- Last Epoch Building
--
-- Module: ItemsTab Craft
-- Inline craft editor for ItemsTab (replaces the CraftingPopup modal).
-- Attaches craft methods to ItemsTabClass created by Classes/ItemsTab.lua.
-- Loaded via: LoadModule("Classes/ItemsTabCraft", ItemsTabClass, H)
--
local ItemsTabClass, H = ...

local t_insert = table.insert
local t_remove = table.remove
local m_max = math.max
local m_min = math.min
local m_floor = math.floor
local pairs = pairs
local ipairs = ipairs

local MAX_MOD_LINES       = H.MAX_MOD_LINES
local LEFT_W              = H.LEFT_W
local LP_LABEL_X          = H.LP_LABEL_X
local LP_LINE_X           = H.LP_LINE_X
local LP_SLOTLABEL_W      = H.LP_SLOTLABEL_W
local LP_DD_X             = H.LP_DD_X
local LP_DD_W             = H.LP_DD_W
local LP_DD_H             = H.LP_DD_H
local LP_SLIDER_W         = H.LP_SLIDER_W
local SLOT_LABELS         = H.SLOT_LABELS
local SLOT_LABELS_IDOL    = H.SLOT_LABELS_IDOL
local NO_T8_SLOTS         = H.NO_T8_SLOTS
local tierColor           = H.tierColor
local getRarityForAffixes = H.getRarityForAffixes
local hasRange            = H.hasRange
local extractMinMax       = H.extractMinMax
local computeModValue     = H.computeModValue
local formatModValue      = H.formatModValue
local wrapForLabel        = H.wrapForLabel

local t_insert = table.insert
local pairs = pairs
local ipairs = ipairs

local SLOT_ORDER = { "prefix1", "prefix2", "suffix1", "suffix2", "sealed", "primordial" }
local ALL_SLOTS  = { "prefix1", "prefix2", "suffix1", "suffix2", "sealed", "primordial", "corrupted" }

-- Cross-tier slider helpers: a slider's value (0..1) spans ALL tiers (1..N) of
-- the current affix, with each tier occupying an equal sub-range. Vertical
-- divider lines on the slider mark tier boundaries (PoB-style).
local function valToTierRange(val, tierCount)
	val = m_max(0, m_min(1, val or 0))
	if (tierCount or 1) <= 1 then
		return 0, m_floor(val * 255 + 0.5)
	end
	local f = val * tierCount
	local tier = m_floor(f)
	if tier >= tierCount then tier = tierCount - 1 end
	local inTier = (f - tier) * 255
	return tier, m_floor(inTier + 0.5)
end

local function tierRangeToVal(tier, range, tierCount)
	if (tierCount or 1) <= 1 then
		return m_max(0, m_min(1, (range or 128) / 255))
	end
	local v = ((tier or 0) + (range or 128) / 255) / tierCount
	return m_max(0, m_min(1, v))
end

-- =============================================================================
-- Type predicates
-- =============================================================================
function ItemsTabClass:CraftIsUniqueIdol()
	return self.craftEditBaseEntry and self.craftEditBaseEntry.category == "unique"
		and self.craftEditBaseEntry.type and self.craftEditBaseEntry.type:find("Idol") and true or false
end

function ItemsTabClass:CraftIsAnyIdol()
	return self.craftEditBaseEntry and self.craftEditBaseEntry.type
		and self.craftEditBaseEntry.type:find("Idol")
		and self.craftEditBaseEntry.type ~= "Idol Altar" and true or false
end

function ItemsTabClass:CraftIsIdolAltar()
	return self.craftEditBaseEntry and self.craftEditBaseEntry.type == "Idol Altar" and true or false
end

function ItemsTabClass:CraftIsUniqueItem()
	local cat = self.craftEditBaseEntry and self.craftEditBaseEntry.category
	return cat == "unique" or cat == "ww"
end

function ItemsTabClass:CraftIsSetItem()
	return self.craftEditBaseEntry and self.craftEditBaseEntry.category == "set"
end

function ItemsTabClass:CraftIsEnchantableIdol()
	if not self.craftEditBaseEntry or not self.craftEditBaseEntry.base then return false end
	local bt = self.craftEditBaseEntry.base.baseTypeID
	local st = self.craftEditBaseEntry.base.subTypeID or 0
	if bt == nil or bt < 29 then return false end
	if bt == 33 then return st >= 7 and st <= 11 end
	return st >= 5 and st <= 9
end

function ItemsTabClass:CraftIsOmenIdol()
	if not self.craftEditBaseEntry or not self.craftEditBaseEntry.base then return false end
	local bt = self.craftEditBaseEntry.base.baseTypeID
	local st = self.craftEditBaseEntry.base.subTypeID or 0
	return (bt == 29 or bt == 30) and st >= 10 and st <= 14
end

function ItemsTabClass:CraftIsWeaverIdol()
	if not self.craftEditBaseEntry or not self.craftEditBaseEntry.base then return false end
	local bt = self.craftEditBaseEntry.base.baseTypeID
	local st = self.craftEditBaseEntry.base.subTypeID
	if bt == 25 then return st == 2 end
	if bt == 26 or bt == 27 or bt == 28 then return st == 1 end
	return false
end

function ItemsTabClass:CraftIsWWItem()
	local r = self.craftEditItem and self.craftEditItem.rarity
	return r == "WWUNIQUE" or r == "WWLEGENDARY"
end

local CLASS_REQ_BITS = { Primalist = 1, Mage = 2, Sentinel = 4, Acolyte = 8, Rogue = 16 }
function ItemsTabClass:CraftGetCurrentClassReqBit()
	local spec = self.build and self.build.spec
	local name = spec and spec.curClassName
	return CLASS_REQ_BITS[name] or 0
end

local WW_CLASS_BITS = { Primalist = 2, Mage = 4, Sentinel = 8, Acolyte = 16, Rogue = 32 }
function ItemsTabClass:CraftGetWWClassBit()
	local title = self.craftEditItem and (self.craftEditItem.title or self.craftEditItem.name) or ""
	for class, bit in pairs(WW_CLASS_BITS) do
		if title:find(class) then return bit end
	end
	local spec = self.build and self.build.spec
	local name = spec and spec.curClassName
	return WW_CLASS_BITS[name] or 0
end

function ItemsTabClass:CraftGetMaxTier(statOrderKey)
	if self:CraftIsAnyIdol() then return 0 end
	local pool = self:CraftIsIdolAltar() and (data.itemMods["Idol Altar"] or {}) or (data.itemMods.Item or {})
	for tier = 7, 0, -1 do
		local key = tostring(statOrderKey) .. "_" .. tostring(tier)
		if pool[key] then return tier end
	end
	return 0
end

-- Slot-aware tier count (1..N) used by cross-tier sliders. Only the
-- primordial slot may hold tier 8 (index 7); all other slots cap at tier 7.
function ItemsTabClass:CraftGetSlotTierCount(slotKey, statOrderKey)
	local maxT = self:CraftGetMaxTier(statOrderKey) or 0
	if slotKey ~= "primordial" and maxT > 6 then maxT = 6 end
	return maxT + 1
end

function ItemsTabClass:CraftGetAffixTierName(slotKey)
	local st = self.craftAffixState[slotKey]
	if not st or not st.modKey then return nil end
	local modKey = tostring(st.modKey) .. "_" .. tostring(st.tier)
	local mod
	if self:CraftIsIdolAltar() then
		local altarMods = data.itemMods["Idol Altar"]
		mod = altarMods and altarMods[modKey]
	else
		mod = data.itemMods.Item and data.itemMods.Item[modKey]
		if not mod and data.modIdol and data.modIdol.flat then
			mod = data.modIdol.flat[modKey]
		end
	end
	return mod and mod.affix or nil
end

-- =============================================================================
-- Per-slot info helpers
-- =============================================================================
function ItemsTabClass:CraftUpdateSlotModInfo(slotKey)
	local info = { count = 0, lines = {}, hasAnyRange = false }
	local st = self.craftAffixState[slotKey]
	if st and st.modKey then
		local isAltar = self:CraftIsIdolAltar()
		local pool = isAltar and (data.itemMods["Idol Altar"] or {}) or (data.itemMods.Item or {})
		local idolPool = (not isAltar) and data.modIdol and data.modIdol.flat or nil
		local function lookup(tier)
			local k = tostring(st.modKey) .. "_" .. tostring(tier)
			local m = pool[k]
			if not m and idolPool then m = idolPool[k] end
			return m
		end
		local mod = lookup(st.tier)
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
		-- Scan all tiers so the slider stays visible even when the current
		-- tier has no mod entry (sparse tier coverage) or value-less lines.
		for tier = 0, 7 do
			local m = lookup(tier)
			if m then
				for k = 1, 10 do
					local line = m[k]
					if line and type(line) == "string" and hasRange(line) then
						info.hasAnyRange = true
						break
					end
				end
				if info.hasAnyRange then break end
			end
		end
	end
	self.craftSlotModInfo[slotKey] = info
end

function ItemsTabClass:CraftUpdateSlotValueEdits(slotKey)
	local info = self.craftSlotModInfo[slotKey]
	local st   = self.craftAffixState[slotKey]
	local tierCount = 1
	if st and st.modKey then
		tierCount = self:CraftGetSlotTierCount(slotKey, st.modKey)
	end
	for i = 1, MAX_MOD_LINES do
		local valCtrl = self.controls["craft_" .. slotKey .. "Val" .. i]
		if valCtrl then
			-- Show tier boundary marks only when more than 1 tier exists.
			valCtrl.divCount = tierCount > 1 and tierCount or nil
			if info and i <= info.count and hasRange(info.lines[i]) then
				local range = st.ranges[i] or 128
				valCtrl.val = tierRangeToVal(st.tier or 0, range, tierCount)
			else
				valCtrl.val = tierRangeToVal(st.tier or 0, 128, tierCount)
			end
		end
	end
end

-- =============================================================================
-- Layout (inline editor panel; origin = craftAnchor TOPLEFT)
-- =============================================================================
function ItemsTabClass:CraftRecalcLayout()
	local LINE_H = 18
	local GAP    = 4
	local DD_ROW_H     = LP_DD_H + 4
	local SLIDER_ROW_H = 24 + 4

	self.craftEditY = {}
	local y = 0

	local isUniqueIdol  = self:CraftIsUniqueIdol()
	local isAnyIdol     = self:CraftIsAnyIdol()
	local isEnchantable = self:CraftIsEnchantableIdol()
	local isUniqueItem  = self:CraftIsUniqueItem()
	local isSetItem     = self:CraftIsSetItem()

	local sectionOrder = {
		{ label = "prefixLabel",     slots = { "prefix1", "prefix2" } },
		{ label = "suffixLabel",     slots = { "suffix1", "suffix2" } },
		{ label = "sealedLabel",     slots = { "sealed" } },
		{ label = "primordialLabel", slots = { "primordial" } },
		{ label = "corruptedLabel",  slots = { "corrupted" } },
	}

	local function layoutSlots(slots)
		for _, slotKey in ipairs(slots) do
			local st = self.craftAffixState[slotKey]
			self.craftEditY[slotKey] = { ctrl = {} }
			self.craftEditY[slotKey].dd = y
			y = y + DD_ROW_H
			if st.modKey then
				local info = self.craftSlotModInfo[slotKey]
				for i = 1, MAX_MOD_LINES do
					self.craftEditY[slotKey].ctrl[i] = y
				end
				-- Single shared slider per affix: any mod line with a range
				-- (in any tier) contributes one SLIDER_ROW_H regardless of
				-- mod-line count.
				local hasAnyRange = false
				if info then
					if info.hasAnyRange then
						hasAnyRange = true
					else
						for i = 1, info.count do
							if info.lines[i] and hasRange(info.lines[i]) then hasAnyRange = true; break end
						end
					end
				end
				if hasAnyRange then y = y + SLIDER_ROW_H end
			end
			y = y + GAP
		end
	end

	-- Implicit / unique-mod slider sections (only shown for unique items).
	-- Implicits render ABOVE prefix; unique mods render BELOW corrupted.
	local IMPL_ROW_H = LINE_H + SLIDER_ROW_H
	self.craftEditY.implicitLabel = 0
	self.craftEditY.implicitRows  = {}
	self.craftEditY.uniqueLabel   = 0
	self.craftEditY.uniqueRows    = {}

	local implicitCount = 0
	if self.craftEditItem then
		for i, _ in ipairs(self.craftEditItem.implicitModLines or {}) do
			if self.craftImplicitRanges[i] then implicitCount = implicitCount + 1 end
		end
	end
	if implicitCount > 0 then
		self.craftEditY.implicitLabel = y
		y = y + LINE_H + GAP
		local rowIdx = 0
		for i, _ in ipairs(self.craftEditItem.implicitModLines or {}) do
			if self.craftImplicitRanges[i] then
				rowIdx = rowIdx + 1
				self.craftEditY.implicitRows[i] = { textY = y, sliderY = y + LINE_H }
				y = y + IMPL_ROW_H + GAP
			end
		end
		y = y + GAP
	end

	for _, sec in ipairs(sectionOrder) do
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
		if isAnyIdol and sec.label == "primordialLabel" then skip = true end
		if self:CraftIsIdolAltar()
			and (sec.label == "sealedLabel" or sec.label == "primordialLabel") then
			skip = true
		end
		if skip then
			for _, slotKey in ipairs(sec.slots) do self.craftEditY[slotKey] = {} end
			self.craftEditY[sec.label] = 0
		else
			self.craftEditY[sec.label] = y
			y = y + LINE_H + GAP
			if sec.label == "corruptedLabel" then
				if not self.craftCorrupted then
					self.craftEditY.corrupted = {}
				else
					layoutSlots(sec.slots)
				end
			else
				if isAnyIdol and (sec.label == "prefixLabel" or sec.label == "suffixLabel") then
					layoutSlots({ sec.slots[1] })
				else
					layoutSlots(sec.slots)
				end
			end
			y = y + GAP
		end
	end

	-- Unique / set mod sliders below the corrupted section.
	local modSrc
	if self.craftEditBaseEntry then
		if self.craftEditBaseEntry.uniqueData then
			modSrc = self.craftEditBaseEntry.uniqueData.mods
		elseif self.craftEditBaseEntry.setData then
			modSrc = self.craftEditBaseEntry.setData.mods
		end
	end
	if modSrc then
		local uniqueCount = 0
		for i, _ in ipairs(modSrc) do
			if self.craftUniqueRanges[i] then uniqueCount = uniqueCount + 1 end
		end
		if uniqueCount > 0 then
			self.craftEditY.uniqueLabel = y
			y = y + LINE_H + GAP
			for i, _ in ipairs(modSrc) do
				if self.craftUniqueRanges[i] then
					self.craftEditY.uniqueRows[i] = { textY = y, sliderY = y + LINE_H }
					y = y + IMPL_ROW_H + GAP
				end
			end
			y = y + GAP
		end
	end

	-- Set info block (members + bonuses) for set items OR for Reforged crafted
	-- basic items whose craftEditItem.setInfo has been populated.
	self.craftEditY.setInfoY = 0
	local layoutSetId, layoutBonus
	if isSetItem then
		local sd = self.craftEditBaseEntry and self.craftEditBaseEntry.setData
		layoutSetId = sd and sd.set and sd.set.setId
		layoutBonus = sd and sd.set and sd.set.bonus
	elseif self.craftEditItem and self.craftEditItem.setInfo and self.craftEditItem.setInfo.setId ~= nil then
		layoutSetId = self.craftEditItem.setInfo.setId
		layoutBonus = self.craftEditItem.setInfo.bonus
	end
	if layoutSetId ~= nil then
		self.craftEditY.setInfoY = y
		y = y + LINE_H + GAP  -- "ITEM SET" header
		y = y + LINE_H        -- set name line
		local memberCount = 0
		for _, si in pairs(self.craftSetItems or {}) do
			if si.set and si.set.setId == layoutSetId then memberCount = memberCount + 1 end
		end
		y = y + memberCount * LINE_H + GAP
		if layoutBonus and next(layoutBonus) then
			y = y + LINE_H + GAP  -- "SET BONUSES" header
			local bonusW = LEFT_W - LP_LINE_X - 4
			local WRAP_H = 15
			for k, v in pairs(layoutBonus) do
				local full = "^8" .. k .. " set: ^7" .. tostring(v)
				local _, n = H.wrapForLabel(full, bonusW, 13)
				y = y + (n > 0 and n or 1) * WRAP_H + 2
			end
		end
	end

	self.craftEditContentH = y
end

-- =============================================================================
-- Base selection
-- =============================================================================
function ItemsTabClass:CraftSelectBase(entry)
	if not entry or entry.isImplicitRow then return end

	for key, st in pairs(self.craftAffixState) do
		st.modKey = nil
		st.tier   = (key == "primordial") and 7 or 0
		st.ranges = {}
	end
	self.craftLastAffixSlot = {}
	self.craftImplicitRanges = {}
	self.craftUniqueRanges   = {}
	self.craftCorrupted = false
	if self.controls.craftCorruptedCheck then
		self.controls.craftCorruptedCheck.state = false
	end

	local item = new("Item")
	item.name     = entry.name
	item.baseName = entry.baseName or entry.name
	item.base     = entry.base
	item.buffModLines             = {}
	item.enchantModLines          = {}
	item.classRequirementModLines = {}
	item.implicitModLines         = {}
	item.explicitModLines         = {}
	item.quality = 0
	item.crafted = true

	if entry.category == "unique" then
		item.rarity   = "UNIQUE"
		item.title    = entry.uniqueData.name
		item.uniqueID = entry.uniqueID
		if entry.uniqueData.mods then
			for i, modText in ipairs(entry.uniqueData.mods) do
				local rollId  = entry.uniqueData.rollIds and entry.uniqueData.rollIds[i]
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
				local rollId  = entry.uniqueData.rollIds and entry.uniqueData.rollIds[i]
				local modLine = { line = modText }
				if rollId then modLine.range = 128 end
				t_insert(item.explicitModLines, modLine)
			end
		end
	elseif entry.category == "set" then
		item.rarity = "SET"
		item.title  = entry.setData.name
		item.setID  = entry.setID
		if entry.setData.set then
			item.setInfo = {
				setId = entry.setData.set.setId,
				name  = entry.setData.set.name,
				bonus = entry.setData.set.bonus,
			}
		end
		if entry.setData.mods then
			for i, modText in ipairs(entry.setData.mods) do
				local rollId  = entry.setData.rollIds and entry.setData.rollIds[i]
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

	-- Initialise per-line ranges for the implicit/unique slider UI. Any line
	-- with a (X-Y) pattern is eligible; unique/set mods are marked already.
	for i, ml in ipairs(item.implicitModLines) do
		if hasRange(ml.line) then
			self.craftImplicitRanges[i] = 128
			ml.range = 128
		end
	end
	for i, ml in ipairs(item.explicitModLines) do
		if ml.range or hasRange(ml.line) then
			self.craftUniqueRanges[i] = ml.range or 128
			ml.range = self.craftUniqueRanges[i]
		end
	end

	item:NormaliseQuality()
	item:BuildAndParseRaw()

	self.craftEditItem      = item
	self.craftEditBaseEntry = entry

	for _, k in ipairs(ALL_SLOTS) do self:CraftUpdateSlotModInfo(k) end
	if entry.category == "basic" then self:CraftRebuildItem() end
	self:CraftRecalcLayout()
	self:CraftRefreshAffixDropdowns()
	self:CraftUpdateRollSliderVals()
	self:SetDisplayItem(self.craftEditItem)
end

-- =============================================================================
-- Direct slot-specific affix selection (from inline DropDown)
-- =============================================================================
function ItemsTabClass:CraftSelectSlotAffix(slotKey, entry)
	if not self.craftAffixState[slotKey] then return end
	local st = self.craftAffixState[slotKey]
	if not entry or not entry.statOrderKey then
		st.modKey = nil
		st.tier   = (slotKey == "primordial") and 7 or 0
		st.ranges = {}
		local tabKey = slotKey:match("^(prefix)") or slotKey:match("^(suffix)")
		if tabKey and self.craftLastAffixSlot and self.craftLastAffixSlot[tabKey] == slotKey then
			local otherSlot = (slotKey == tabKey .. "1") and (tabKey .. "2") or (tabKey .. "1")
			local otherSt   = self.craftAffixState[otherSlot]
			self.craftLastAffixSlot[tabKey] = (otherSt and otherSt.modKey) and otherSlot or nil
		end
		self:CraftUpdateSlotModInfo(slotKey)
		self:CraftUpdateSlotValueEdits(slotKey)
		self:CraftRebuildItem()
		return
	end
	if st.modKey == entry.statOrderKey then return end
	local maxT = entry.maxTier or 0
	st.modKey = entry.statOrderKey
	if slotKey == "primordial" then
		st.tier = m_min(7, maxT)
	else
		st.tier = m_min(4, maxT)
		if NO_T8_SLOTS[slotKey] and st.tier > 6 then st.tier = 6 end
	end
	st.ranges = {}
	self:CraftUpdateSlotModInfo(slotKey)
	local info = self.craftSlotModInfo[slotKey]
	for i = 1, info.count do st.ranges[i] = 128 end
	self:CraftUpdateSlotValueEdits(slotKey)
	local tabKey = slotKey:match("^(prefix)") or slotKey:match("^(suffix)")
	if tabKey then
		self.craftLastAffixSlot = self.craftLastAffixSlot or {}
		self.craftLastAffixSlot[tabKey] = slotKey
	end
	self:CraftRebuildItem()
end

-- =============================================================================
-- Rebuild the edit item from current affix state (drives real-time DPS diff)
-- =============================================================================
function ItemsTabClass:CraftRebuildItem()
	if not self.craftEditItem then return end
	self.craftRebuilding = true

	local item        = self.craftEditItem
	local isAltarItem = self:CraftIsIdolAltar()
	local itemMods    = isAltarItem and (data.itemMods["Idol Altar"] or {}) or (data.itemMods.Item or {})

	wipeTable(item.explicitModLines)
	wipeTable(item.prefixes)
	wipeTable(item.suffixes)
	item.namePrefix = ""
	item.nameSuffix = ""

	-- Unique mods are held aside so craft prefix/suffix lines can be inserted
	-- ABOVE them and the corrupted line below them (matches LETools layout).
	local uniqueModLines = {}
	if self.craftEditBaseEntry and self.craftEditBaseEntry.category == "unique" and self.craftEditBaseEntry.uniqueData then
		for i, modText in ipairs(self.craftEditBaseEntry.uniqueData.mods) do
			local rollId  = self.craftEditBaseEntry.uniqueData.rollIds and self.craftEditBaseEntry.uniqueData.rollIds[i]
			local modLine = { line = modText }
			if rollId or hasRange(modText) then
				modLine.range = self.craftUniqueRanges[i] or 128
			end
			t_insert(uniqueModLines, modLine)
		end
	elseif self.craftEditBaseEntry and self.craftEditBaseEntry.category == "set" and self.craftEditBaseEntry.setData then
		for i, modText in ipairs(self.craftEditBaseEntry.setData.mods) do
			local rollId  = self.craftEditBaseEntry.setData.rollIds and self.craftEditBaseEntry.setData.rollIds[i]
			local modLine = { line = modText }
			if rollId or hasRange(modText) then
				modLine.range = self.craftUniqueRanges[i] or 128
			end
			t_insert(item.explicitModLines, modLine)
		end
	end

	-- Re-apply implicit line ranges (implicitModLines are persistent across
	-- rebuilds; only their .range may have changed via slider).
	for i, ml in ipairs(item.implicitModLines) do
		if self.craftImplicitRanges[i] then
			ml.range = self.craftImplicitRanges[i]
		end
	end

	local prefixIdx  = 0
	local suffixIdx  = 0
	local affixCount = 0
	local maxTier    = 0
	local hasAffix   = false
	local reforgedSetInfo
	local reforgedTitle

	for _, slotKey in ipairs(SLOT_ORDER) do
		local st = self.craftAffixState[slotKey]
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
				if mod.affix and mod.affix:sub(-9) == " Reforged" and self.craftSetItems then
					local bareName = mod.affix:sub(1, -10)
					for _, si in pairs(self.craftSetItems) do
						if si and si.set and si.name == bareName then
							reforgedSetInfo = {
								setId = si.set.setId,
								name  = si.set.name,
								bonus = si.set.bonus,
							}
							reforgedTitle = mod.affix
							break
						end
					end
				end
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

	-- Append unique mods AFTER craft prefix/suffix lines so unique mods appear
	-- below the craft-added affixes in the tooltip.
	for _, modLine in ipairs(uniqueModLines) do
		t_insert(item.explicitModLines, modLine)
	end

	if self.craftEditBaseEntry and self.craftEditBaseEntry.category == "basic" then
		if reforgedSetInfo then
			item.rarity     = "SET"
			item.title      = reforgedTitle
			item.namePrefix = ""
			item.nameSuffix = ""
		else
			item.rarity = getRarityForAffixes(affixCount, maxTier)
			if item.rarity == "RARE" or item.rarity == "EXALTED" then
				item.title = item.title or "New Item"
			else
				item.title = nil
			end
		end
	elseif self.craftEditBaseEntry and self.craftEditBaseEntry.category == "unique" and hasAffix then
		item.rarity = "LEGENDARY"
	elseif self.craftEditBaseEntry and self.craftEditBaseEntry.category == "ww" then
		item.rarity = hasAffix and "WWLEGENDARY" or "WWUNIQUE"
	end

	if self.craftCorrupted then
		local ca = self.craftAffixState.corrupted
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

	item.corrupted = self.craftCorrupted
	item:BuildAndParseRaw()
	-- For basic items the set state is driven purely by whether a Reforged
	-- set affix is currently picked. Always overwrite (with nil or table) so
	-- deselecting/replacing a set affix clears the stale preview.
	if self.craftEditBaseEntry and self.craftEditBaseEntry.category == "basic" then
		item.setInfo = reforgedSetInfo
	elseif reforgedSetInfo then
		item.setInfo = reforgedSetInfo
	end

	for _, k in ipairs(SLOT_ORDER) do self:CraftUpdateSlotModInfo(k) end
	self:CraftUpdateSlotModInfo("corrupted")
	self:CraftRecalcLayout()
	self:CraftRefreshAffixDropdowns()
	self:CraftUpdateRollSliderVals()

	-- Drive real-time DPS diff via the displayItem tooltip infrastructure.
	self:SetDisplayItem(item)

	self.craftRebuilding = false
end

-- =============================================================================
-- Slider tooltip
-- =============================================================================
function ItemsTabClass:CraftBuildSliderTooltip(tooltip, slotKey, li, hoverVal)
	local info = self.craftSlotModInfo[slotKey]
	if not info or li > info.count then return end
	local st = self.craftAffixState[slotKey]
	if not st or not st.modKey then return end

	-- Map hoverVal (0..1, full slider) -> (hoverTier, hoverRange 0..255)
	local tierCount = self:CraftGetSlotTierCount(slotKey, st.modKey)
	local hoverTier, hoverRange = valToTierRange(hoverVal, tierCount)

	-- Resolve the mod entry for the *hovered* tier (cross-tier preview).
	local function lookupMod(tier)
		local key = tostring(st.modKey) .. "_" .. tostring(tier)
		local m
		if self:CraftIsIdolAltar() then
			local altarMods = data.itemMods["Idol Altar"]
			m = altarMods and altarMods[key]
		else
			m = data.itemMods.Item and data.itemMods.Item[key]
			if not m and data.modIdol and data.modIdol.flat then
				m = data.modIdol.flat[key]
			end
		end
		return m
	end

	local hoverMod = lookupMod(hoverTier)

	-- Collect all mod lines for the hovered tier (single-slider drives them all).
	local lines = {}
	if hoverMod then
		for k = 1, 10 do
			local ln = hoverMod[k]
			if type(ln) == "string" then t_insert(lines, ln) end
		end
	end
	if #lines == 0 then
		for k = 1, info.count do
			local ln = info.lines[k]
			if type(ln) == "string" then t_insert(lines, ln) end
		end
	end
	if #lines == 0 then return end

	-- Top: substituted text for each mod line at hoverRange.
	for _, ln in ipairs(lines) do
		local rounding = H.getRounding and H.getRounding(ln) or nil
		local computed = itemLib.applyRange(ln, hoverRange, nil, rounding) or ln
		computed = computed:gsub("{rounding:%w+}", ""):gsub("{[^}]+}", "")
		tooltip:AddLine(16, "^7" .. computed)
	end
	tooltip:AddSeparator(8)

	-- Tier line (no affix name here).
	tooltip:AddLine(14, tierColor(hoverTier) .. "Affix: Tier " .. tostring(hoverTier + 1))

	-- Range lines: "(min-max) <affix name>" for each mod line.
	local hoverTierName = (hoverMod and hoverMod.affix) or ""
	for _, ln in ipairs(lines) do
		local min, max = extractMinMax(ln)
		if min and max then
			local txt = "^7(" .. tostring(min) .. "-" .. tostring(max) .. ")"
			if hoverTierName ~= "" then txt = txt .. " " .. hoverTierName end
			tooltip:AddLine(14, txt)
		end
	end

	if hoverMod and hoverMod.levelReq then
		tooltip:AddLine(14, "^xAAAAAALevel: " .. tostring(hoverMod.levelReq))
	end
end

-- =============================================================================
-- Affix list refresh (populates self.craftAffixLists)
-- =============================================================================
local SUBCAT_ORDER = { "general", "class_only", "set_only", "champion", "personal", "corrupted" }
local SUBCAT_LABEL = {
	general    = "General",
	class_only = "Class Only",
	set_only   = "Set Only",
	champion   = "Champion",
	personal   = "Personal",
	corrupted  = "Corrupted",
}

function ItemsTabClass:CraftRefreshSlotDropdowns()
	if not self.controls then return end
	for _, slotKey in ipairs(ALL_SLOTS) do
		local dd = self.controls["craft_" .. slotKey .. "DD"]
		if dd then
			local src = self.craftAffixLists[slotKey] or {}
			local ddList = { { label = "^8None", entry = nil } }
			local curKey = self.craftAffixState[slotKey] and self.craftAffixState[slotKey].modKey
			local selIdx = 1
			local foundCurrent = false

			-- Preserve existing collapse state across refreshes so dragging a
			-- slider or picking an affix doesn't reopen all groups.
			local prevCollapsed = {}
			if dd.list then
				for _, li in ipairs(dd.list) do
					if type(li) == "table" and li.isHeader then
						prevCollapsed[li.subcat] = li.collapsed
					end
				end
			end

			-- Partition affixes by subcategory (general/class_only/...).
			local bySubcat = {}
			local hasAnySubcat = false
			for _, e in ipairs(src) do
				local sc = e.subcategory or "general"
				bySubcat[sc] = bySubcat[sc] or {}
				t_insert(bySubcat[sc], e)
				hasAnySubcat = true
			end

			local function cleanLabel(s) return (s or ""):gsub("{rounding:%w+}", ""):gsub("{[^}]+}", "") end

			if hasAnySubcat then
				for _, sc in ipairs(SUBCAT_ORDER) do
					local group = bySubcat[sc]
					if group and #group > 0 then
						table.sort(group, function(a, b) return (a.label or "") < (b.label or "") end)
						local collapsed = prevCollapsed[sc] or false
						t_insert(ddList, {
							label = "^7" .. SUBCAT_LABEL[sc] .. "  (" .. tostring(#group) .. ")",
							isHeader = true, collapsed = collapsed, subcat = sc,
						})
						for _, e in ipairs(group) do
							t_insert(ddList, { label = "  " .. cleanLabel(e.label), entry = e })
							if curKey and e.statOrderKey == curKey then
								selIdx = #ddList
								foundCurrent = true
							end
						end
					end
				end
			else
				-- No subcategory info (e.g. idol / altar); flat list.
				for _, e in ipairs(src) do
					t_insert(ddList, { label = cleanLabel(e.label), entry = e })
					if curKey and e.statOrderKey == curKey then
						selIdx = #ddList
						foundCurrent = true
					end
				end
			end

			if curKey and not foundCurrent then
				local info = self.craftSlotModInfo[slotKey]
				local firstLine = info and info.lines and info.lines[1]
				local label = firstLine and cleanLabel(firstLine) or tostring(curKey)
				t_insert(ddList, { label = "^3" .. label, entry = { statOrderKey = curKey } })
				selIdx = #ddList
			end
			dd:SetList(ddList)
			dd.selIndex = selIdx
		end
	end
end

function ItemsTabClass:CraftRefreshAffixDropdowns()
	if not self.craftEditItem then return end
	if self:CraftIsAnyIdol() and data.modIdol and next(data.modIdol) then
		self:CraftRefreshIdolAffixDropdowns()
		return
	end
	if self:CraftIsSetItem() then
		for _, k in ipairs(ALL_SLOTS) do self.craftAffixLists[k] = {} end
		return
	end
	local isUniqueOrSet = self:CraftIsUniqueItem()

	local itemMods
	if self:CraftIsIdolAltar() then
		itemMods = data.itemMods["Idol Altar"] or {}
	else
		itemMods = self.craftEditItem.affixes or data.itemMods.Item
	end
	if not itemMods then return end

	local wwPool       = nil
	local wwClassBit   = 0
	local itemBaseTypeID = self.craftEditBaseEntry and self.craftEditBaseEntry.base and self.craftEditBaseEntry.base.baseTypeID
	if self:CraftIsWWItem() then
		wwPool     = itemBaseTypeID and data.wwMods and data.wwMods[tostring(itemBaseTypeID)]
		wwClassBit = self:CraftGetWWClassBit()
	end
	local playerCsBit = self:CraftGetCurrentClassReqBit() * 2

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
		return nil
	end

	for modId, mod in pairs(itemMods) do
		if mod.statOrderKey then
			local subcat = classifySubcategory(mod)
			if not subcat then goto continue end
			local cro = mod.canRollOn
			if cro and #cro > 0 and itemBaseTypeID then
				local canRoll = false
				for _, btid in ipairs(cro) do
					if btid == itemBaseTypeID then canRoll = true; break end
				end
				if not canRoll then goto continue end
			end
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

	local function flattenBuckets(buckets, includeSubcats)
		local out = {}
		for _, sc in ipairs(includeSubcats) do
			for _, g in pairs(buckets[sc]) do t_insert(out, g) end
		end
		return out
	end
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

	local prefixList     = {}
	local suffixList     = {}
	local sealedList     = {}
	local primordialList = {}

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

	local function copyCapped(g)
		return {
			label = g.label, statOrderKey = g.statOrderKey, affix = g.affix,
			type = g.type, maxTier = m_min(g.maxTier, 6), subcategory = g.subcategory,
		}
	end
	for _, g in ipairs(prefixIter) do t_insert(prefixList, copyCapped(g)) end
	for _, g in ipairs(suffixIter) do t_insert(suffixList, copyCapped(g)) end
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

	local p1Key = self.craftAffixState.prefix1.modKey
	local p2Key = self.craftAffixState.prefix2.modKey
	local s1Key = self.craftAffixState.suffix1.modKey
	local s2Key = self.craftAffixState.suffix2.modKey

	self.craftAffixLists.prefix1 = filterExclusions(prefixList, p2Key and { p2Key } or {})
	self.craftAffixLists.prefix2 = filterExclusions(prefixList, p1Key and { p1Key } or {})
	self.craftAffixLists.suffix1 = filterExclusions(suffixList, s2Key and { s2Key } or {})
	self.craftAffixLists.suffix2 = filterExclusions(suffixList, s1Key and { s1Key } or {})

	local sealedExclude = {}
	if p1Key then t_insert(sealedExclude, p1Key) end
	if p2Key then t_insert(sealedExclude, p2Key) end
	if s1Key then t_insert(sealedExclude, s1Key) end
	if s2Key then t_insert(sealedExclude, s2Key) end
	self.craftAffixLists.sealed     = filterExclusions(sealedList, sealedExclude)
	self.craftAffixLists.primordial = filterExclusions(primordialList, sealedExclude)

	local corruptedList = {}
	if self:CraftIsIdolAltar() then
		local corruptedGroups = {}
		for modId, mod in pairs(itemMods) do
			if mod.statOrderKey then
				local sat = mod.specialAffixType or 0
				local subcat = (sat == 6) and "corrupted" or "general"
				if not corruptedGroups[mod.statOrderKey] then
					local t0 = itemMods[tostring(mod.statOrderKey) .. "_0"] or mod
					local labelParts = {}
					for k = 1, 10 do if t0[k] then t_insert(labelParts, t0[k]) end end
					local label = table.concat(labelParts, " / "):gsub("{rounding:%w+}", ""):gsub("{[^}]+}", "")
					corruptedGroups[mod.statOrderKey] = {
						label = label, statOrderKey = mod.statOrderKey,
						affix = mod.affix, type = mod.type, maxTier = mod.tier or 0,
						subcategory = subcat,
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
	self.craftAffixLists.corrupted = corruptedList

	for _, slotKey in ipairs({ "prefix1", "prefix2", "suffix1", "suffix2", "sealed", "corrupted" }) do
		local st = self.craftAffixState[slotKey]
		if st.modKey and st.tier >= 7 then
			st.tier = 6
			self:CraftUpdateSlotModInfo(slotKey)
			self:CraftUpdateSlotValueEdits(slotKey)
		end
	end
	self:CraftRefreshSlotDropdowns()
end

function ItemsTabClass:CraftRefreshIdolAffixDropdowns()
	local baseTypeID = self.craftEditBaseEntry and self.craftEditBaseEntry.base and self.craftEditBaseEntry.base.baseTypeID
	if not baseTypeID then return end

	local general   = data.modIdol.general   or {}
	local enchanted = data.modIdol.enchanted or {}
	local corrupted = data.modIdol.corrupted or {}
	local weaver    = self:CraftIsWeaverIdol() and (data.modIdol.weaver or {}) or {}

	local function buildLabel(mod)
		local parts = {}
		for k = 1, 10 do if mod[k] then t_insert(parts, mod[k]) end end
		return table.concat(parts, " / "):gsub("{rounding:%w+}", ""):gsub("{[^}]+}", "")
	end

	local idolClassReq = self.craftEditBaseEntry and self.craftEditBaseEntry.base and self.craftEditBaseEntry.base.classReq or 0
	local idolCsBit    = idolClassReq * 2
	local isOmen       = self:CraftIsOmenIdol()
	local LARGE_IDS    = { [29] = true, [30] = true, [31] = true, [32] = true, [33] = true }

	local omenPool = nil
	if isOmen then
		if baseTypeID == 29 then omenPool = { [29] = true, [31] = true, [33] = true }
		elseif baseTypeID == 30 then omenPool = { [30] = true, [32] = true, [33] = true } end
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

	self.craftAffixLists.prefix1    = prefixList
	self.craftAffixLists.prefix2    = {}
	self.craftAffixLists.suffix1    = suffixList
	self.craftAffixLists.suffix2    = {}
	self.craftAffixLists.sealed     = filterExclusions(enchantedList, self.craftAffixState.primordial.modKey and { self.craftAffixState.primordial.modKey } or {})
	self.craftAffixLists.primordial = filterExclusions(enchantedList, self.craftAffixState.sealed.modKey and { self.craftAffixState.sealed.modKey } or {})
	self.craftAffixLists.corrupted  = corruptedList

	for _, slotKey in ipairs({ "prefix1", "suffix1", "sealed", "primordial", "corrupted" }) do
		local st = self.craftAffixState[slotKey]
		if st.modKey and st.tier ~= 0 then
			st.tier = 0
			self:CraftUpdateSlotModInfo(slotKey)
			self:CraftUpdateSlotValueEdits(slotKey)
		end
	end
	self:CraftRefreshSlotDropdowns()
end

-- =============================================================================
-- Editor lifecycle
-- =============================================================================
function ItemsTabClass:CraftResetState()
	self.craftAffixLists = {
		prefix1 = {}, prefix2 = {}, suffix1 = {}, suffix2 = {},
		sealed = {}, primordial = {}, corrupted = {},
	}
	self.craftAffixState = {
		prefix1    = { modKey = nil, tier = 0, ranges = {} },
		prefix2    = { modKey = nil, tier = 0, ranges = {} },
		suffix1    = { modKey = nil, tier = 0, ranges = {} },
		suffix2    = { modKey = nil, tier = 0, ranges = {} },
		sealed     = { modKey = nil, tier = 0, ranges = {} },
		primordial = { modKey = nil, tier = 7, ranges = {} },
		corrupted  = { modKey = nil, tier = 0, ranges = {} },
	}
	self.craftCorrupted   = false
	self.craftSlotModInfo = {}
	for _, k in ipairs(ALL_SLOTS) do
		self.craftSlotModInfo[k] = { count = 0, lines = {} }
	end
	self.craftEditY         = {}
	self.craftLastAffixSlot = {}
	self.craftEditItem      = nil
	self.craftEditBaseEntry = nil
	self.craftRebuilding    = false
	-- Per-line ranges for implicit and unique/set mods (0-255, nil = no slider).
	self.craftImplicitRanges = {}
	self.craftUniqueRanges   = {}
end

function ItemsTabClass:OpenCraftEditor(existingItem, slotName, presetEntry)
	self:CraftResetState()
	self.craftPrevDisplayItem = self.displayItem
	self.craftActive          = true
	self.craftSlotName        = slotName
	self.craftExistingItem    = existingItem
	self.craftingSlotName     = slotName
	self.craftSetItems        = self.craftSetItems or H.loadSetData(self.build)

	if self.controls.craftCorruptedCheck then
		self.controls.craftCorruptedCheck.state = false
	end

	if existingItem and existingItem.craftState then
		self:CraftRestoreState(existingItem)
	elseif presetEntry then
		self:CraftSelectBase(presetEntry)
	end

	self:CraftRecalcLayout()
end

function ItemsTabClass:CloseCraftEditor()
	local prev = self.craftPrevDisplayItem
	self:CraftResetState()
	self.craftActive          = false
	self.craftSlotName        = nil
	self.craftExistingItem    = nil
	self.craftingSlotName     = nil
	self.craftPrevDisplayItem = nil
	self:SetDisplayItem(prev)
end

function ItemsTabClass:CraftRestoreState(existingItem)
	local cs = existingItem.craftState
	self.craftEditBaseEntry = cs.baseEntry
	self.craftEditItem      = existingItem
	self.craftCorrupted     = cs.corrupted and true or false
	if self.controls.craftCorruptedCheck then
		self.controls.craftCorruptedCheck.state = self.craftCorrupted
	end
	for key, saved in pairs(cs.affixState) do
		local st = self.craftAffixState[key]
		if st then
			st.modKey = saved.modKey
			st.tier   = saved.tier
			st.ranges = {}
			for i, r in ipairs(saved.ranges) do st.ranges[i] = r end
		end
	end
	self.craftImplicitRanges = {}
	if cs.implicitRanges then
		for i, r in pairs(cs.implicitRanges) do self.craftImplicitRanges[i] = r end
	end
	self.craftUniqueRanges = {}
	if cs.uniqueRanges then
		for i, r in pairs(cs.uniqueRanges) do self.craftUniqueRanges[i] = r end
	end
	for _, k in ipairs(ALL_SLOTS) do
		self:CraftUpdateSlotModInfo(k)
		self:CraftUpdateSlotValueEdits(k)
	end
	self:CraftRecalcLayout()
	self:CraftRefreshAffixDropdowns()
	self:CraftUpdateRollSliderVals()
	self:SetDisplayItem(self.craftEditItem)
end

function ItemsTabClass:CraftSaveItem()
	if not self.craftEditItem then return end
	self:CraftRebuildItem()
	local savedState = {}
	for key, st in pairs(self.craftAffixState) do
		savedState[key] = { modKey = st.modKey, tier = st.tier, ranges = {} }
		for i, r in ipairs(st.ranges) do savedState[key].ranges[i] = r end
	end
	local savedImpl = {}
	for i, r in pairs(self.craftImplicitRanges) do savedImpl[i] = r end
	local savedUniq = {}
	for i, r in pairs(self.craftUniqueRanges) do savedUniq[i] = r end
	self.craftEditItem.craftState = {
		affixState     = savedState,
		corrupted      = self.craftCorrupted,
		baseEntry      = self.craftEditBaseEntry,
		implicitRanges = savedImpl,
		uniqueRanges   = savedUniq,
	}
	local finalItem = self.craftEditItem
	-- Preserve the crafted item for addDisplayItem (Add to build / Save).
	self:CraftResetState()
	self.craftActive          = false
	self.craftSlotName        = nil
	self.craftExistingItem    = nil
	self.craftingSlotName     = nil
	self.craftPrevDisplayItem = nil
	self:SetDisplayItem(finalItem)
end

-- =============================================================================
-- Inline UI: build the craft editor controls (call once from BuildItemsControls)
-- =============================================================================
-- =============================================================================
-- Set info panel (item set members + bonuses) — drawn under the inline editor
-- when editing a Set base or a Reforged crafted item with setInfo populated.
-- =============================================================================
function ItemsTabClass:CraftDrawSetInfo(viewPort)
	if not self.craftActive or not self.craftEditItem then return end
	local entry = self.craftEditBaseEntry
	local set
	if entry and entry.category == "set" and entry.setData and entry.setData.set then
		set = entry.setData.set
	elseif self.craftEditItem.setInfo and self.craftEditItem.setInfo.setId ~= nil then
		set = {
			setId = self.craftEditItem.setInfo.setId,
			name  = self.craftEditItem.setInfo.name,
			bonus = self.craftEditItem.setInfo.bonus,
		}
	end
	if not set then return end

	local anchor = self.controls.craftAnchor
	if not anchor then return end
	local px, py = anchor:GetPos()
	px = m_floor(px); py = m_floor(py)
	-- BuildCraftControls uses EDIT_BASE_Y = 24 baseline below the title
	local baseY = 24
	local y = self.craftEditY and self.craftEditY.setInfoY
	if not y or y <= 0 then return end
	y = baseY + y

	local setId  = set.setId
	local LINE_H = 18
	local GAP    = 4

	-- Build set of member names that are currently equipped (by slot selItemId)
	-- or currently being edited. Strip trailing " Reforged" so Reforged crafted
	-- items match the bare member name in the member list.
	local equippedNames = {}
	local function markName(s)
		if not s or s == "" then return end
		equippedNames[s] = true
		local stripped = s:gsub(" Reforged$", "")
		if stripped ~= s then equippedNames[stripped] = true end
	end
	for _, slot in pairs(self.slots or {}) do
		local eqItem = slot.selItemId and self.items and self.items[slot.selItemId]
		if eqItem and eqItem.setInfo and eqItem.setInfo.setId == setId then
			markName(eqItem.setInfo.name)
			markName(eqItem.title)
		elseif eqItem and eqItem.rarity == "SET" and eqItem.title then
			markName(eqItem.title)
		end
	end
	markName(self.craftEditItem.title)

	SetDrawColor(1, 1, 1)
	DrawString(px + LP_LABEL_X, py + y, "LEFT", 14, "VAR", colorCodes.SET .. "ITEM SET")
	y = y + LINE_H + GAP
	DrawString(px + LP_LINE_X, py + y, "LEFT", 13, "VAR", "^7" .. (set.name or ""))
	y = y + LINE_H

	local members = {}
	for _, si in pairs(self.craftSetItems or {}) do
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
	local ORANGE = "^xFF9933"
	for _, m in ipairs(members) do
		local col = equippedNames[m.name] and ORANGE or "^8"
		DrawString(px + LP_LINE_X + 8, py + y, "LEFT", 12, "VAR",
			col .. m.name .. (m.typeName ~= "" and ("  " .. m.typeName) or ""))
		y = y + LINE_H
	end
	y = y + GAP

	local bonus = set.bonus
	if bonus and next(bonus) then
		DrawString(px + LP_LABEL_X, py + y, "LEFT", 14, "VAR", colorCodes.SET .. "SET BONUSES")
		y = y + LINE_H + GAP
		local bonusKeys = {}
		for k in pairs(bonus) do t_insert(bonusKeys, k) end
		table.sort(bonusKeys, function(a, b) return tonumber(a) < tonumber(b) end)
		local bonusW = LEFT_W - LP_LINE_X - 4
		local WRAP_H = 15
		for _, k in ipairs(bonusKeys) do
			local full = "^8" .. k .. " set: ^7" .. tostring(bonus[k])
			local wrapped = wrapForLabel(full, bonusW, 13)
			for line in (wrapped .. "\n"):gmatch("([^\n]*)\n") do
				DrawString(px + LP_LINE_X, py + y, "LEFT", 13, "VAR", line)
				y = y + WRAP_H
			end
			y = y + 2
		end
	end
end

function ItemsTabClass:BuildCraftControls()
	local self_ref = self
	local controls = self.controls

	-- Anchor: directly below the Add to build / Edit / Cancel button row,
	-- so the right column reads top-down: action buttons → craft editor → preview.
	controls.craftAnchor = new("Control",
		{ "TOPLEFT", controls.addDisplayItem, "BOTTOMLEFT" }, 0, 12, LEFT_W, 0)
	controls.craftAnchor.shown = function() return self_ref.craftActive == true end

	-- Panel title
	controls.craftTitle = new("LabelControl",
		{ "TOPLEFT", controls.craftAnchor, "TOPLEFT" }, LP_LABEL_X, 0, 0, 16, "")
	controls.craftTitle.label = function()
		return "^7Craft - " .. (self_ref.craftEditItem and (self_ref.craftEditItem.baseName or "") or "...")
	end
	controls.craftTitle.shown = function() return self_ref.craftActive == true end

	-- Change Base button (hidden when editing an existing item)
	controls.craftChangeBase = new("ButtonControl",
		{ "TOPLEFT", controls.craftAnchor, "TOPLEFT" }, LP_LABEL_X + 200, -2, 110, 20,
		"Change Base...", function()
			local slotName = self_ref.craftSlotName
			self_ref:CloseCraftEditor()
			self_ref:OpenCraftItemSelector(slotName)
		end)
	controls.craftChangeBase.shown = function()
		return self_ref.craftActive == true and self_ref.craftEditItem ~= nil and self_ref.craftExistingItem == nil
	end

	local affixSections = {
		{ key = "prefix",     label = "PREFIXES",         slots = { "prefix1", "prefix2" } },
		{ key = "suffix",     label = "SUFFIXES",         slots = { "suffix1", "suffix2" } },
		{ key = "sealed",     label = "SEALED AFFIX",     slots = { "sealed" } },
		{ key = "primordial", label = "PRIMORDIAL AFFIX", slots = { "primordial" } },
		{ key = "corrupted",  label = "CORRUPTED",        slots = { "corrupted" } },
	}

	-- Editor controls baseline Y offset from craftAnchor (below title)
	local EDIT_BASE_Y = 24

	for _, section in ipairs(affixSections) do
		local labelKey            = section.key .. "Label"
		local ctlLabelKey         = "craft_" .. labelKey
		local capturedSectionKey  = section.key
		local capturedSectionLabel = section.label

		controls[ctlLabelKey] = new("LabelControl",
			{ "TOPLEFT", controls.craftAnchor, "TOPLEFT" }, LP_LABEL_X,
			function() return EDIT_BASE_Y + (self_ref.craftEditY[labelKey] or 0) end,
			0, 14, "")

		if capturedSectionKey == "sealed" then
			controls[ctlLabelKey].label = function()
				local base = self_ref:CraftIsAnyIdol() and "ENCHANT" or capturedSectionLabel
				local n = #(self_ref.craftAffixLists.sealed or {})
				return colorCodes.UNIQUE .. base .. " (" .. n .. ")"
			end
		elseif capturedSectionKey == "primordial" then
			controls[ctlLabelKey].label = function()
				local n = #(self_ref.craftAffixLists.primordial or {})
				return colorCodes.UNIQUE .. capturedSectionLabel .. " (" .. n .. ")"
			end
		else
			local sectionListKeyMap = { prefix = "prefix1", suffix = "suffix1", corrupted = "corrupted" }
			local capturedListKey = sectionListKeyMap[capturedSectionKey] or capturedSectionKey
			controls[ctlLabelKey].label = function()
				local n = #(self_ref.craftAffixLists[capturedListKey] or {})
				return colorCodes.UNIQUE .. capturedSectionLabel .. " (" .. n .. ")"
			end
		end

		controls[ctlLabelKey].shown = function()
			if not self_ref.craftActive or not self_ref.craftEditItem then return false end
			if capturedSectionKey ~= "corrupted" and self_ref:CraftIsUniqueIdol() then return false end
			if self_ref:CraftIsSetItem() then return false end
			if (capturedSectionKey == "sealed" or capturedSectionKey == "primordial")
				and self_ref:CraftIsUniqueItem() then return false end
			if (capturedSectionKey == "sealed" or capturedSectionKey == "primordial")
				and self_ref:CraftIsAnyIdol() and not self_ref:CraftIsEnchantableIdol() then return false end
			if capturedSectionKey == "primordial" and self_ref:CraftIsAnyIdol() then return false end
			if (capturedSectionKey == "sealed" or capturedSectionKey == "primordial")
				and self_ref:CraftIsIdolAltar() then return false end
			return true
		end

		if section.key == "corrupted" then
			controls.craftCorruptedCheck = new("CheckBoxControl",
				{ "TOPLEFT", controls.craftAnchor, "TOPLEFT" }, LP_LABEL_X + 110,
				function() return EDIT_BASE_Y + (self_ref.craftEditY[labelKey] or 0) end,
				18, "", function(state)
					self_ref.craftCorrupted = state
					if not state then
						self_ref.craftAffixState.corrupted.modKey = nil
						self_ref.craftAffixState.corrupted.tier   = 0
						self_ref.craftAffixState.corrupted.ranges = {}
						self_ref:CraftUpdateSlotModInfo("corrupted")
					end
					self_ref:CraftRebuildItem()
				end)
			controls.craftCorruptedCheck.shown = function()
				if not (self_ref.craftActive and self_ref.craftEditItem) then return false end
				-- Set items cannot be corrupted in LE; hide the toggle.
				if self_ref:CraftIsSetItem() then return false end
				return true
			end
		end

		for _, slotKey in ipairs(section.slots) do
			local capturedSlotKey = slotKey
			-- Use "Slot" suffix to avoid colliding with section header keys
			-- (e.g. slotKey "sealed" + "Label" would overwrite section header
			-- key "sealedLabel"). Section headers were silently disappearing
			-- for single-slot sections (sealed/primordial/corrupted).
			local slotLabelKey    = "craft_" .. slotKey .. "SlotLabel"
			local slotDDKey       = "craft_" .. slotKey .. "DD"

			controls[slotLabelKey] = new("LabelControl",
				{ "TOPLEFT", controls.craftAnchor, "TOPLEFT" }, LP_LABEL_X,
				function()
					local ey = self_ref.craftEditY[capturedSlotKey]
					return EDIT_BASE_Y + (ey and ey.dd or 0)
				end,
				LP_SLOTLABEL_W, 14,
				function()
					local base = self_ref:CraftIsAnyIdol() and SLOT_LABELS_IDOL[capturedSlotKey] or SLOT_LABELS[capturedSlotKey]
					return "^7" .. (base or "") .. ":"
				end)
			controls[slotLabelKey].shown = function()
				if not self_ref.craftActive or not self_ref.craftEditItem then return false end
				if capturedSlotKey == "corrupted" and not self_ref.craftCorrupted then return false end
				local ey = self_ref.craftEditY[capturedSlotKey]
				return ey ~= nil and ey.dd ~= nil
			end

			controls[slotDDKey] = new("DropDownControl",
				{ "TOPLEFT", controls.craftAnchor, "TOPLEFT" }, LP_DD_X,
				function()
					local ey = self_ref.craftEditY[capturedSlotKey]
					return EDIT_BASE_Y + (ey and ey.dd or 0)
				end,
				LP_DD_W, LP_DD_H, {}, function(index, value)
					self_ref:CraftSelectSlotAffix(capturedSlotKey, value and value.entry or nil)
				end)
			controls[slotDDKey].enableDroppedWidth = true
			controls[slotDDKey].maxDroppedWidth    = 520
			-- Show a tooltip with the full label on hover so long affix
			-- names clipped by the drop panel are still readable.
			controls[slotDDKey].tooltipFunc = function(tooltip, mode, index, value)
				tooltip:Clear()
				if mode ~= "HOVER" then return end
				if type(value) ~= "table" or value.isHeader then return end
				local label = value.label or ""
				label = label:gsub("^%s+", "")
				if label ~= "" then
					tooltip:AddLine(14, "^7" .. label)
				end
			end
			controls[slotDDKey].shown = function()
				if not self_ref.craftActive or not self_ref.craftEditItem then return false end
				if capturedSlotKey == "corrupted" and not self_ref.craftCorrupted then return false end
				-- UniqueItem: allow prefix/suffix/corrupted dropdowns (LP-style
				-- craft). Sealed/primordial are already filtered by layout.
				if self_ref:CraftIsSetItem() or self_ref:CraftIsUniqueIdol() then
					if capturedSlotKey ~= "corrupted" then return false end
				end
				local ey = self_ref.craftEditY[capturedSlotKey]
				return ey ~= nil and ey.dd ~= nil
			end

			for li = 1, MAX_MOD_LINES do
				local valKey = "craft_" .. slotKey .. "Val" .. li
				controls[valKey] = new("SliderControl",
					{ "TOPLEFT", controls.craftAnchor, "TOPLEFT" }, LP_LINE_X,
					function()
						local ey = self_ref.craftEditY[capturedSlotKey]
						local cy = ey and ey.ctrl and ey.ctrl[li]
						return cy and (EDIT_BASE_Y + cy + 3) or 0
					end,
					LP_SLIDER_W, 24,
					function(val)
						if self_ref.craftRebuilding then return end
						local info = self_ref.craftSlotModInfo[capturedSlotKey]
						if li > info.count then return end
						local st = self_ref.craftAffixState[capturedSlotKey]
						local tierCount = self_ref:CraftGetSlotTierCount(capturedSlotKey, st.modKey)
						local newTier, newRange = valToTierRange(val, tierCount)
						st.tier = newTier
						-- Single shared slider per affix: write the same range
						-- to all mod-line indices so multi-mod affixes stay
						-- locked to one position.
						for i = 1, info.count do st.ranges[i] = newRange end
						self_ref:CraftRebuildItem()
					end)
				controls[valKey].shown = function()
					if li ~= 1 then return false end
					if not self_ref.craftActive or not self_ref.craftEditItem then return false end
					if not self_ref.craftAffixState[capturedSlotKey].modKey then return false end
					if capturedSlotKey == "corrupted" and not self_ref.craftCorrupted then return false end
					local info = self_ref.craftSlotModInfo[capturedSlotKey]
					if not info then return false end
					-- hasAnyRange scans all tiers so dragging across sparse
					-- tier coverage doesn't flicker the slider off.
					if info.hasAnyRange then return true end
					for i = 1, info.count do
						if info.lines[i] and hasRange(info.lines[i]) then return true end
					end
					return false
				end
				controls[valKey].tooltipFunc = function(tooltip, hoverVal)
					tooltip:Clear()
					self_ref:CraftBuildSliderTooltip(tooltip, capturedSlotKey, li, hoverVal)
				end
			end
		end
	end

	-- Implicit / unique-mod roll sliders (unique items only). Fixed pool of
	-- label+slider pairs shown based on craftImplicitRanges / craftUniqueRanges.
	local MAX_IMPL_SLIDERS   = 5
	local MAX_UNIQUE_SLIDERS = 12

	controls.craftImplicitLabel = new("LabelControl",
		{ "TOPLEFT", controls.craftAnchor, "TOPLEFT" }, LP_LABEL_X,
		function() return EDIT_BASE_Y + (self_ref.craftEditY.implicitLabel or 0) end,
		0, 14, "")
	controls.craftImplicitLabel.label = function()
		return colorCodes.UNIQUE .. "IMPLICITS"
	end
	controls.craftImplicitLabel.shown = function()
		return self_ref.craftActive
			and self_ref.craftEditItem
			and (self_ref.craftEditY.implicitLabel or 0) > 0
	end

	controls.craftUniqueLabel = new("LabelControl",
		{ "TOPLEFT", controls.craftAnchor, "TOPLEFT" }, LP_LABEL_X,
		function() return EDIT_BASE_Y + (self_ref.craftEditY.uniqueLabel or 0) end,
		0, 14, "")
	controls.craftUniqueLabel.label = function()
		local be = self_ref.craftEditBaseEntry
		if be and be.category == "set" then
			return colorCodes.SET .. "SET MODS"
		end
		return colorCodes.UNIQUE .. "UNIQUE MODS"
	end
	controls.craftUniqueLabel.shown = function()
		return self_ref.craftActive
			and self_ref.craftEditItem
			and (self_ref.craftEditY.uniqueLabel or 0) > 0
	end

	-- Helper: build a mod-text + slider pair for either implicit or unique lines.
	-- `kind` = "impl" or "uniq". `modLinesGetter()` returns the source modLines.
	local function buildRollRow(kind, lineIdx, rangesKey, rowsKey, modLinesGetter)
		local labelCtrl = "craft_" .. kind .. "Text" .. lineIdx
		local sliderCtrl = "craft_" .. kind .. "Slider" .. lineIdx

		controls[labelCtrl] = new("LabelControl",
			{ "TOPLEFT", controls.craftAnchor, "TOPLEFT" }, LP_LINE_X,
			function()
				local row = self_ref.craftEditY[rowsKey] and self_ref.craftEditY[rowsKey][lineIdx]
				return row and (EDIT_BASE_Y + row.textY) or 0
			end,
			0, 13, "")
		labelCtrl = controls[labelCtrl]
		labelCtrl.label = function()
			local ml = modLinesGetter() and modLinesGetter()[lineIdx]
			if not ml then return "" end
			local rangedLine = itemLib.applyRange(ml.line, ml.range or 128, ml.valueScalar, ml.rounding)
			return "^7" .. rangedLine
		end
		labelCtrl.shown = function()
			if not self_ref.craftActive or not self_ref.craftEditItem then return false end
			local rows = self_ref.craftEditY[rowsKey]
			return rows ~= nil and rows[lineIdx] ~= nil
		end

		controls[sliderCtrl] = new("SliderControl",
			{ "TOPLEFT", controls.craftAnchor, "TOPLEFT" }, LP_LINE_X,
			function()
				local row = self_ref.craftEditY[rowsKey] and self_ref.craftEditY[rowsKey][lineIdx]
				return row and (EDIT_BASE_Y + row.sliderY + 3) or 0
			end,
			LP_SLIDER_W, 24,
			function(val)
				if self_ref.craftRebuilding then return end
				local newRange = m_floor(val * 255 + 0.5)
				if newRange < 0 then newRange = 0 end
				if newRange > 255 then newRange = 255 end
				self_ref[rangesKey][lineIdx] = newRange
				self_ref:CraftRebuildItem()
			end)
		controls[sliderCtrl].shown = function()
			if not self_ref.craftActive or not self_ref.craftEditItem then return false end
			local rows = self_ref.craftEditY[rowsKey]
			return rows ~= nil and rows[lineIdx] ~= nil
		end
	end

	for i = 1, MAX_IMPL_SLIDERS do
		buildRollRow("impl", i, "craftImplicitRanges", "implicitRows", function()
			return self_ref.craftEditItem and self_ref.craftEditItem.implicitModLines
		end)
	end
	for i = 1, MAX_UNIQUE_SLIDERS do
		buildRollRow("uniq", i, "craftUniqueRanges", "uniqueRows", function()
			-- Unique modLines aren't in craftEditItem.explicitModLines during
			-- rebuild (they're prepended to the buffer); pull from baseEntry.
			local be = self_ref.craftEditBaseEntry
			if not be then return nil end
			local src = (be.uniqueData and be.uniqueData.mods) or (be.setData and be.setData.mods)
			if not src then return nil end
			local out = {}
			for idx, text in ipairs(src) do
				out[idx] = { line = text, range = self_ref.craftUniqueRanges[idx] }
			end
			return out
		end)
	end

	-- Save / Cancel are handled by the outer Add to build / Cancel buttons
	-- (ItemsTab.lua) when craft is active, so no inline Save/Cancel here.
end

function ItemsTabClass:CraftUpdateRollSliderVals()
	-- Push craftImplicitRanges / craftUniqueRanges into the corresponding
	-- slider controls' .val so the UI reflects the stored state.
	for i, r in pairs(self.craftImplicitRanges) do
		local ctrl = self.controls["craft_implSlider" .. i]
		if ctrl then ctrl.val = (r or 128) / 255 end
	end
	for i, r in pairs(self.craftUniqueRanges) do
		local ctrl = self.controls["craft_uniqSlider" .. i]
		if ctrl then ctrl.val = (r or 128) / 255 end
	end
end
