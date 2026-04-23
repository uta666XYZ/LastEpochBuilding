-- Last Epoch Building
--
-- Module: CraftingPopup Item State
-- Item-state methods for CraftingPopup: type predicates, class-req helpers,
-- RebuildEditItem, SaveItem, RestoreCraftState, Close.
-- Attaches methods to the CraftingPopupClass created by Classes/CraftingPopup.lua.
-- Loaded via: LoadModule("Classes/CraftingPopupItem", CraftingPopupClass, H)
--
local CraftingPopupClass, H = ...

local t_insert = table.insert
local t_remove = table.remove
local m_max = math.max
local m_min = math.min
local m_floor = math.floor
local m_ceil = math.ceil
local pairs = pairs
local ipairs = ipairs

local MAX_MOD_LINES      = H.MAX_MOD_LINES
local NO_T8_SLOTS        = H.NO_T8_SLOTS
local FIXED_TIER_SLOTS   = H.FIXED_TIER_SLOTS
local tierColor          = H.tierColor
local getRarityForAffixes = H.getRarityForAffixes
local cleanImplicitText  = H.cleanImplicitText
local hasRange           = H.hasRange
local getModPrecision    = H.getModPrecision
local getRounding        = H.getRounding
local extractMinMax      = H.extractMinMax
local computeModValue    = H.computeModValue
local reverseModRange    = H.reverseModRange
local clampModValue      = H.clampModValue
local formatModValue     = H.formatModValue

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
	local reforgedSetInfo  -- captured when a "<Name> Reforged" affix is applied
	local reforgedTitle
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
				-- Reforged Set affix: affix name like "<SetMemberName> Reforged".
				-- Resolve setInfo by matching stripped name against self.setItems.
				if mod.affix and mod.affix:sub(-9) == " Reforged" and self.setItems then
					local bareName = mod.affix:sub(1, -10)
					for _, si in pairs(self.setItems) do
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
		if reforgedSetInfo then
			-- Reforged Set item: force SET rarity + use "<memberName> Reforged" as title.
			item.rarity    = "SET"
			item.title     = reforgedTitle
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
	-- Reforged items: restore setInfo stripped by BuildAndParseRaw round-trip.
	if reforgedSetInfo then
		item.setInfo = reforgedSetInfo
	end

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
end

function CraftingPopupClass:Close()
	if self.itemsTab then
		self.itemsTab.craftingSlotName = nil
	end
	main:ClosePopup()
end
