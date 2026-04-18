-- Last Epoch Building
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
    -- Non-scalar % affixes (e.g. "18% increased Health") use round; flat and scalar affixes use floor
    local useRound = line:find("%%") ~= nil and valueScalar == 1.0
    line = line:gsub("(%+?)%((%-?%d+%.?%d*)%-(%-?%d+%.?%d*)%)",
            function(plus, min, max)
                min = min * valueScalar
                -- If min decimal part is exactly 0.5, round down
                if min * precision % 1 == 0.5 then
                    min = m_floor(min * precision) / precision
                else
                    min = m_floor(min * precision + 0.5) / precision
                end
                max = max * valueScalar
                max = m_floor(max * precision + 0.5) / precision
                numbers = numbers + 1
                local numVal = (tonumber(min) + range * (tonumber(max) - tonumber(min) + 1 / precision))
                if useRound then
                    numVal = m_floor(numVal * precision + 0.5) / precision
                else
                    numVal = m_floor(numVal * precision) / precision
                end
                if numVal > max then
                    numVal = max
                end
                return (numVal < 0 and "" or plus) .. tostring(numVal)
            end)
               :gsub("%-(%d+%.?%d*%%) (%a+)", antonymFunc)
    return line
end

function itemLib.hasRange(line)
    return line:find("%(%-?%d+%.?%d*%-%-?%d+%.?%d*%)");
end

function itemLib.formatModLine(modLine, dbMode)
    local line = (not dbMode and modLine.range and itemLib.applyRange(modLine.line, modLine.range, modLine.valueScalar, modLine.rounding)) or modLine.line
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