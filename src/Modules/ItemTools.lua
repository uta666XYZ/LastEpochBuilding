-- Last Epoch Building
-- @leb-canary v1 / id:leb-2e7a08-itemtools-2026 / do-not-remove (see Development/リリース手順.md)
--
-- Module: Item Tools
-- Various functions for dealing with items.
--
local t_insert = table.insert
local t_remove = table.remove
local m_min = math.min
local m_max = math.max
local m_floor = math.floor

itemLib = { }

-- Influence info (unused in Last Epoch, kept as empty table for compatibility)
itemLib.influenceInfo = { }

-- ============================================================================
-- Shared icon cache (used by ItemListControl and ItemSlotControl).
-- Single NewImageHandle per Asset filename, shared across all controls.
-- Per-control caches were causing duplicate texture handles for the same file
-- and a non-deterministic C++ renderer crash when both controls rendered
-- simultaneously (see Bug Tracker: primordial-add crash, 2026-04-26).
-- ============================================================================
local sharedIconHandles = {}
itemLib._sharedIconHandles = sharedIconHandles

-- Item type -> 16x16 icon filename (in Assets/).
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
	["Blessing"]          = "blessings/body_of_obsidian.png",
}

function itemLib.iconFileForItem(item)
	if not item or not item.type then return nil end
	local t = item.type
	local f = TYPE_ICON[t]
	if f then return f end
	if t:find("Idol") then return "Icon_Idol.png" end
	return nil
end

function itemLib.getIconHandle(filename)
	if not filename then return nil end
	if not sharedIconHandles[filename] then
		local h = NewImageHandle()
		h:Load("Assets/" .. filename, "ASYNC")
		sharedIconHandles[filename] = h
	end
	return sharedIconHandles[filename]
end

-- Primordial detection: covers (a) currently-active craft editor state,
-- (b) explicitModLines flagged by CraftRebuildItem, and (c) any prefix/suffix
-- mod whose specialAffixType == 7 (covers imported items too).
function itemLib.itemHasPrimordial(item)
	if not item then return false end
	if item.primordial then return true end
	if item.craftState and item.craftState.affixState
		and item.craftState.affixState.primordial
		and item.craftState.affixState.primordial.modKey ~= nil then
		return true
	end
	if item.explicitModLines then
		for i, line in ipairs(item.explicitModLines) do
			if line.primordial then return true end
		end
	end
	if item.affixes then
		local lists = { item.prefixes, item.suffixes }
		for li = 1, 2 do
			local list = lists[li]
			if list then
				for si, slot in ipairs(list) do
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

-- Returns a list (table) of icon handles for this item, in display order:
-- [type, primordial?, corrupted?]. Returns nil if no icons resolvable.
function itemLib.getItemIcons(item)
	if not item then return nil end
	local list = {}
	local fname = itemLib.iconFileForItem(item)
	local h = itemLib.getIconHandle(fname)
	if h and h:IsValid() then t_insert(list, h) end
	if itemLib.itemHasPrimordial(item) then
		local p = itemLib.getIconHandle("Icon_Primordial.png")
		if p and p:IsValid() then t_insert(list, p) end
	end
	if item.corrupted then
		local c = itemLib.getIconHandle("Icon_Corrupted.png")
		if c and c:IsValid() then t_insert(list, c) end
	end
	if #list == 0 then return nil end
	return list
end

local antonyms = {
    ["increased"] = "reduced",
    ["reduced"] = "increased",
    ["more"] = "less",
    ["less"] = "more",
}

local function antonymFunc(num, word)
    local antonym = antonyms[word]
    return antonym and (num .. " " .. antonym) or ("-" .. num .. " " .. word)
end

-- Apply range value (0 to 256) to a modifier that has a range: "(x-x)" or "(x-x) to (x-x)"
function itemLib.applyRange(line, range, valueScalar, rounding)
    -- High precision for increased modifier
    local precision = 100
    if rounding == "Integer" then
        precision = 1
    elseif rounding == "Tenth" then
        precision = 10
    elseif rounding == "Thousandth" then
        precision = 1000
    end
    -- If there is a percent, we need to divide the precision by 100
    if line:find("%%") and precision >= 100 then
        precision = precision / 100
    end

    -- range is actually given as a roll (TODO:rename)
    range = range / 255.0

    local numbers = 0
    if not valueScalar then
        valueScalar = 1.0
    end
    -- Only "% increased/reduced/more/less" affixes use round; flat %, scalars, and flat values use floor
    local useRound = valueScalar == 1.0
        and (line:find("%% increased") ~= nil or line:find("%% reduced") ~= nil
             or line:find("%% more") ~= nil or line:find("%% less") ~= nil)
    local function roundHalfDownOnHalf(v)
        -- Round half-up, except x.5 rounds down (floor). Matches LE's endpoint rounding.
        if v * precision % 1 == 0.5 then
            return m_floor(v * precision) / precision
        end
        return m_floor(v * precision + 0.5) / precision
    end
    line = line:gsub("(%+?)%((%-?%d+%.?%d*)%-(%-?%d+%.?%d*)%)",
            function(plus, min, max)
                numbers = numbers + 1
                local minN = tonumber(min)
                local maxN = tonumber(max)
                -- Flat values (useRound=false) use (max-min+1/precision) span so the
                -- top byte (255) reaches max; percentage-with-word affixes (useRound=true)
                -- use the plain (max-min) span, matching LETools/Maxroll displays.
                local span = maxN - minN
                if not useRound then
                    span = span + 1 / precision
                end
                -- Interpolate first, THEN apply valueScalar, to match LE/LETools.
                -- Applying scalar to min/max before interpolation shifts the integer
                -- grid (e.g. Apiarist's Suit Str +(11-13)×1.5 at roll 57/255 should
                -- give round(11.447×1.5)=17, not interpolate within [16,19]→16).
                local numVal = (minN + range * span) * valueScalar
                if useRound then
                    numVal = m_floor(numVal * precision + 0.5) / precision
                else
                    numVal = m_floor(numVal * precision) / precision
                end
                local maxScaled = roundHalfDownOnHalf(maxN * valueScalar)
                if numVal > maxScaled then
                    numVal = maxScaled
                end
                return (numVal < 0 and "" or plus) .. tostring(numVal)
            end)
               :gsub("%-(%d+%.?%d*%%) (%a+)", antonymFunc)
    -- Single-value scaling: affixes like "+5% Critical Strike Multiplier" have no
    -- (x-x) range, but still need valueScalar applied when the affix scales with
    -- the base (e.g. Class-Specific Idol enchants). Only applied when scalar != 1.
    if valueScalar ~= 1.0 and numbers == 0 then
        line = line:gsub("^(%+?)(%-?%d+%.?%d*)", function(plus, num)
            local v = roundHalfDownOnHalf(tonumber(num) * valueScalar)
            return plus .. tostring(v)
        end, 1)
    end
    return line
end

function itemLib.hasRange(line)
    return line:find("%(%-?%d+%.?%d*%-%-?%d+%.?%d*%)");
end

-- Map ItemClass.type -> slotOverrides key (tunklab-style slug). Returns nil
-- for types without a distinct slot-variant table (e.g. Weapon, Idol).
local typeToSlotKey = {
    ["Helmet"]             = "helmet",
    ["Body Armor"]         = "body_armor",
    ["Belt"]               = "belt",
    ["Boots"]              = "boots",
    ["Gloves"]             = "gloves",
    ["Amulet"]             = "amulet",
    ["Ring"]               = "ring",
    ["Relic"]              = "relic",
    ["Shield"]             = "shield",
    ["Off-Hand Catalyst"]  = "catalyst",
}
function itemLib.slotKeyForType(itemType)
    return typeToSlotKey[itemType]
end

-- Pick the mod-line array that matches the item's slot. Falls back to the
-- default mod table when no override is defined.
function itemLib.modLinesForSlot(mod, slotKey)
    if slotKey and mod.slotOverrides and mod.slotOverrides[slotKey] then
        return mod.slotOverrides[slotKey]
    end
    return mod
end

function itemLib.formatModLine(modLine, dbMode, altarBoost)
    local displayScalar = modLine.displayValueScalar or modLine.valueScalar
    local line = (not dbMode and modLine.range and itemLib.applyRange(modLine.line, modLine.range, displayScalar, modLine.rounding)) or modLine.line
    if line:match("^%+?0%%? ") or (line:match(" %+?0%%? ") and not line:match("0 to [1-9]")) or line:match(" 0%-0 ") or line:match(" 0 to 0 ") then
        -- Hack to hide 0-value modifiers
        return
    end
    local colorCode
    if modLine.extra then
        colorCode = colorCodes.UNSUPPORTED
        if launch.devModeAlt then
            line = line .. "   ^1'" .. modLine.extra .. "'"
        end
    else
        colorCode = (modLine.crafted and colorCodes.CRAFTED) or (modLine.custom and colorCodes.CUSTOM) or colorCodes.MAGIC
    end
    if modLine.notSupported and not modLine.extra then
        line = line .. "  " .. colorCodes.NORMAL .. "(NOT SUPPORTED IN LEB YET)"
    end
    if altarBoost and altarBoost > 0 and not dbMode and modLine.range then
        local boostedScalar = (modLine.valueScalar or 1) * (1 + altarBoost)
        local boostedLine = itemLib.applyRange(modLine.line, modLine.range, boostedScalar, modLine.rounding)
        if boostedLine ~= line then
            line = line .. "  (-> " .. boostedLine .. " with Altar)"
        end
    end
    return colorCode .. line
end

itemLib.wiki = {
    key = "F1",
    openGem = function(gemData)
        local name
        if gemData.name then
            -- skill
            name = gemData.name
            if gemData.tags.support then
                name = name .. " Support"
            end
        else
            -- grantedEffect from item/passive
            name = gemData;
        end

        itemLib.wiki.open(name)
    end,
    openItem = function(item)
        local name = item.rarity == "UNIQUE" and item.title or item.baseName

        itemLib.wiki.open(name)
    end,
    open = function(name)
        OpenURL("https://www.lastepochtools.com/db/search?query=" .. name)
        itemLib.wiki.triggered = true
    end,
    matchesKey = function(key)
        return key == itemLib.wiki.key
    end,
    triggered = false
}