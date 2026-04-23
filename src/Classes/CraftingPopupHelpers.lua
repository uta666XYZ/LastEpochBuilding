-- Last Epoch Building
--
-- Module: CraftingPopup Helpers
-- Pure constants and helper functions used by CraftingPopup.lua and its
-- companion modules (CraftingPopupDraw / CraftingPopupItem).
-- No class state. Loaded via LoadModule and returned as a table.
--
local t_insert = table.insert
local m_max = math.max
local m_min = math.min
local m_floor = math.floor
local m_ceil = math.ceil
local pairs = pairs
local ipairs = ipairs

local H = {}

H.MAX_MOD_LINES = 3

-- Item type -> 16x16 icon filename (in Assets/).
-- Mirrors ItemListControl.TYPE_ICON so the craft-popup left menu shows the same icons
-- used by the All Items list.
H.TYPE_ICON = {
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

local iconHandles = {}
function H.getTypeIcon(typeName)
	if not typeName then return nil end
	local f = H.TYPE_ICON[typeName]
	if not f and typeName:find("Idol") then f = "Icon_Idol.png" end
	if not f then return nil end
	if not iconHandles[f] then
		local h = NewImageHandle()
		h:Load("Assets/" .. f, "ASYNC")
		iconHandles[f] = h
	end
	return iconHandles[f]
end

-- Slot -> allowed item types (nil = show all)
H.SLOT_TYPE_FILTER = {
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
	-- Synthetic slot keys used by the paperdoll craft shortcut buttons.
	-- These don't correspond to real equip slots, they just scope the type list.
	["Idol"]       = {
		"Small Idol", "Minor Idol", "Humble Idol", "Stout Idol",
		"Grand Idol", "Large Idol", "Ornate Idol", "Huge Idol", "Adorned Idol",
	},
	["Idol Altar"] = { "Idol Altar" },
}

function H.filterTypeList(orderedList, slotName)
	local filter = H.SLOT_TYPE_FILTER[slotName]
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

-- Layout constants (single-panel Stage 2 popup)
H.LEFT_W        = 320
H.POPUP_W       = H.LEFT_W
H.PREVIEW_Y     = 38

-- Left panel control positions
H.LP_LABEL_X    = 15
H.LP_LINE_X     = 20
H.LP_LINE_W     = 118
H.LP_VAL_X      = 142
H.LP_VAL_W      = 50
H.LP_TIER_X     = 196
H.LP_TRUP_X     = 213
H.LP_TRDN_X     = 233
H.LP_REM_X      = 254
H.LP_REM_W      = 18

-- PoB-style inline slot row: [Label] [DropDown] / [Slider]
H.LP_SLOTLABEL_W = 65
H.LP_DD_X        = H.LP_LABEL_X + H.LP_SLOTLABEL_W + 5
H.LP_DD_W        = H.LEFT_W - H.LP_DD_X - 8
H.LP_DD_H        = 18
H.LP_SLIDER_W    = H.LEFT_W - H.LP_LINE_X - 8

H.SLOT_LABELS = {
	prefix1 = "Prefix",  prefix2 = "Prefix",
	suffix1 = "Suffix",  suffix2 = "Suffix",
	sealed  = "Sealed",  primordial = "Primordial",
	corrupted = "Corrupted",
}
H.SLOT_LABELS_IDOL = {
	sealed = "Enchant", primordial = "Enchant",
}

-- Slots where T8 is not allowed
H.NO_T8_SLOTS = { prefix1=true, prefix2=true, suffix1=true, suffix2=true, sealed=true, corrupted=true }
-- Fixed-tier slots
H.FIXED_TIER_SLOTS = { primordial=true }

-- Tier color codes: T1-T5 = Basic (magic blue), T6-T8 = Exalted (purple)
H.TIER_COLORS = {
	[1] = "^x36A3E2",  -- T1 basic
	[2] = "^x36A3E2",  -- T2 basic
	[3] = "^x36A3E2",  -- T3 basic
	[4] = "^x36A3E2",  -- T4 basic
	[5] = "^x36A3E2",  -- T5 basic
	[6] = "^xC184FF",  -- T6 exalted
	[7] = "^xC184FF",  -- T7 exalted
	[8] = "^xC184FF",  -- T8 exalted (primordial only)
}
function H.tierColor(tier0)
	return H.TIER_COLORS[tier0 + 1] or "^7"
end

-- Convert item display name to image filename
-- "Acolyte's Sceptre" -> "acolyte_s_sceptre.png"
function H.itemNameToFilename(name)
	return name:lower():gsub("'", "_"):gsub("[^%a%d]+", "_"):gsub("_+", "_"):gsub("^_",""):gsub("_$","") .. ".png"
end

-- Rarity for crafted items based on affix count and highest tier index (0-based)
function H.getRarityForAffixes(affixCount, maxTier)
	if affixCount == 0 then return "NORMAL" end
	if maxTier >= 5 then return "EXALTED" end
	if affixCount >= 3 then return "RARE" end
	return "MAGIC"
end

function H.cleanImplicitText(line)
	if line:find("%[UNKNOWN_STAT%]") then return nil end
	return line:gsub("{rounding:%w+}", ""):gsub("{[^}]+}", "")
end

-- Char-count-based word wrap. Reliable because DrawStringWidth with VAR
-- font has been observed to underestimate actual render width in practice.
-- Approximate per-char width for VAR at this size; conservative = more wrap.
function H.wrapByChars(str, maxChars)
	local out = {}
	if not str or str == "" then return out end
	local cur = ""
	for word in str:gmatch("%S+") do
		if cur == "" then
			cur = word
		elseif #cur + 1 + #word <= maxChars then
			cur = cur .. " " .. word
		else
			t_insert(out, cur)
			cur = word
		end
		while #cur > maxChars do
			t_insert(out, cur:sub(1, maxChars))
			cur = cur:sub(maxChars + 1)
		end
	end
	if cur ~= "" then t_insert(out, cur) end
	return out
end

-- Wrap raw text (strips leading color code, preserves it on each line) to a
-- multi-line string joined with "\n", plus returns line count.
-- Uses char-count heuristic: VAR font ~= size * 0.6 px per char (conservative).
function H.wrapForLabel(text, width, size)
	if not text or text == "" then return "", 1 end
	-- Consume ALL leading color codes (e.g. "^7^x8888FF") as the prefix so
	-- every wrapped line repeats the same leading color sequence.
	local colorPrefix = ""
	local rest = text
	while true do
		local cp = rest:match("^(%^x%x%x%x%x%x%x)") or rest:match("^(%^%d)")
		if not cp then break end
		colorPrefix = colorPrefix .. cp
		rest = rest:sub(#cp + 1)
	end
	local perChar = m_max(4, size * 0.6)
	local maxChars = m_max(10, m_floor(width / perChar))
	local wrapped = H.wrapByChars(rest, maxChars)
	if #wrapped <= 1 then return colorPrefix .. rest, 1 end
	for i = 1, #wrapped do wrapped[i] = colorPrefix .. wrapped[i] end
	return table.concat(wrapped, "\n"), #wrapped
end

function H.wrapTextLine(text, maxChars)
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

function H.hasRange(line)
	return line:match("%(%-?%d+%.?%d*%-%-?%d+%.?%d*%)") ~= nil
end

function H.getModPrecision(line)
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

function H.getRounding(line)
	if line:find("{rounding:Integer}") then return "Integer"
	elseif line:find("{rounding:Tenth}") then return "Tenth"
	elseif line:find("{rounding:Thousandth}") then return "Thousandth" end
	return nil
end

function H.extractMinMax(line)
	local min, max = line:match("%(([%-]?%d+%.?%d*)%-([%-]?%d+%.?%d*)%)")
	if min and max then return tonumber(min), tonumber(max) end
	return nil, nil
end

function H.computeModValue(line, range)
	local computed = itemLib.applyRange(line, range, nil, H.getRounding(line))
	if not computed then return nil end
	computed = computed:gsub("{rounding:%w+}", ""):gsub("{[^}]+}", "")
	local num = computed:match("([%-]?%d+%.?%d*)")
	return tonumber(num)
end

function H.reverseModRange(line, targetValue)
	local min, max = H.extractMinMax(line)
	if not min or not max then return 128 end
	local precision = H.getModPrecision(line)
	local rangeSize = max - min + 1 / precision
	if rangeSize == 0 then return 0 end
	local rawRange = (targetValue - min) / rangeSize * 255
	local range = m_max(0, m_min(256, m_ceil(rawRange)))
	local actual = H.computeModValue(line, range)
	if actual and actual < targetValue and range < 256 then range = range + 1 end
	return range
end

function H.clampModValue(line, value)
	local min, max = H.extractMinMax(line)
	if not min or not max then return value end
	if min <= max then return m_max(min, m_min(max, value))
	else return m_max(max, m_min(min, value)) end
end

function H.formatModValue(line, value)
	local precision = H.getModPrecision(line)
	if precision <= 1 then return tostring(m_floor(value + 0.5))
	elseif precision <= 10 then return string.format("%.1f", value)
	elseif precision <= 100 then return string.format("%.2f", value)
	else return string.format("%.3f", value) end
end

-- Class requirement bits (player class -> bit index used by base.classReq)
H.CLASS_REQ_BITS = { Primalist = 1, Mage = 2, Sentinel = 4, Acolyte = 8, Rogue = 16 }

function H.getClassReqBit(build)
	local spec = build and build.spec
	local name = spec and spec.curClassName
	return H.CLASS_REQ_BITS[name] or 0
end

-- Load set item data for the build's target version. Static (no self).
function H.loadSetData(build)
	local ver = (build and build.targetVersion) or "1_4"
	local setData = readJsonFile("Data/Set/set_" .. ver .. ".json")
	if not setData then setData = readJsonFile("Data/Set/set_1_4.json") end
	return setData or {}
end

-- Build a filtered list of base entries (same shape as CraftingPopup.currentItemList).
-- category: "basic" | "unique" | "set"
-- setItems: table returned by H.loadSetData
-- searchText/classReqBit optional.
function H.buildBaseList(build, setItems, typeName, category, searchText, classReqBit)
	local list = {}
	if not typeName or not build or not build.data then return list end
	local bases = build.data.itemBaseLists and build.data.itemBaseLists[typeName]
	classReqBit = classReqBit or 0

	if category == "basic" then
		if bases then
			for _, entry in ipairs(bases) do
				if not entry.base.legacy then
					local classReq = entry.base.classReq or 0
					if classReq == 0 or classReqBit == 0 or bit.band(classReq, classReqBit) ~= 0 then
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
	elseif category == "unique" then
		if bases and build.data.uniques then
			for uid, unique in pairs(build.data.uniques) do
				if unique.name and unique.name:lower():sub(1, 9) == "cocooned " then goto continueUID end
				local found = false
				for _, baseEntry in ipairs(bases) do
					if baseEntry.base.baseTypeID == unique.baseTypeID and
					   baseEntry.base.subTypeID  == unique.subTypeID then
						local classReq = baseEntry.base.classReq or 0
						if classReq == 0 or classReqBit == 0 or bit.band(classReq, classReqBit) ~= 0 then
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
				if not found and build.data.itemBases then
					for baseName, base in pairs(build.data.itemBases) do
						if base.hidden and base.type == typeName and
						   base.baseTypeID == unique.baseTypeID and
						   base.subTypeID  == unique.subTypeID then
							local classReq = base.classReq or 0
							if classReq == 0 or classReqBit == 0 or bit.band(classReq, classReqBit) ~= 0 then
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
	elseif category == "set" then
		if bases and setItems then
			for sid, setItem in pairs(setItems) do
				for _, baseEntry in ipairs(bases) do
					if baseEntry.base.baseTypeID == setItem.baseTypeID and
					   baseEntry.base.subTypeID  == setItem.subTypeID then
						local classReq = baseEntry.base.classReq or 0
						if classReq == 0 or classReqBit == 0 or bit.band(classReq, classReqBit) ~= 0 then
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

	local query = (searchText or ""):lower():gsub("^%s*(.-)%s*$", "%1")
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
					local cleaned = H.cleanImplicitText(implText)
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

	return list
end

function H.buildOrderedTypeList(dataTypeList)
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

return H
