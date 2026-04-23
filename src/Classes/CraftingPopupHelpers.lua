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

-- Layout constants
H.POPUP_W       = 1200
H.LEFT_W        = 320
H.DIVIDER_X     = H.LEFT_W
H.TYPE_LIST_Y   = 34
H.TYPE_LIST_H   = 190
H.TYPE_ROW_H    = 20
H.PREVIEW_Y     = H.TYPE_LIST_Y + H.TYPE_LIST_H + 6   -- ~230

-- Right panel layout
H.RP_X          = H.LEFT_W + 1
H.RP_W          = H.POPUP_W - H.LEFT_W - 1
H.RP_TAB_Y      = 34
H.RP_TAB_H      = 24
H.RP_FILTER_Y   = H.RP_TAB_Y + H.RP_TAB_H + 3
H.RP_FILTER_H   = 20
H.RP_CATTAB_Y   = H.RP_FILTER_Y + H.RP_FILTER_H + 3
H.RP_CATTAB_H   = 20
H.RP_CARD_Y     = H.RP_CATTAB_Y + H.RP_CATTAB_H + 4
H.RP_CARD_PAD   = 8

-- Item cards (item tab, right panel)
H.IC_COLS       = 2
H.IC_GAP        = 6
H.IC_W          = m_floor((H.RP_W - 2 * H.RP_CARD_PAD - (H.IC_COLS - 1) * H.IC_GAP) / H.IC_COLS)
H.IC_H          = 80

-- Affix cards (affix tabs, right panel) -- compact single-row cards
H.AC_H          = 24
H.AC_GAP        = 2

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
