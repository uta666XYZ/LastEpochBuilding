-- Properties Loader
--
-- Exposes the LE PropertyList ScriptableObject (extracted from
-- resources.assets via TypeTreeGeneratorAPI; see
-- src/Data/Properties/property_list_<ver>.json) to runtime Lua code, so
-- that itemLib.applyRangeStrict callers can pick the correct rounding
-- (Hundredth / Integer / Tenth / Thousandth) per stat without
-- re-encoding the heuristic.
--
-- Usage:
--   local Properties = require("Data.Properties.Loader")
--   Properties.load("1.4")
--   local info = Properties.byName["Physical Resistance"]   -- exact name
--   info.roundingForAdded -- 0=Hundredth, 1=Integer, 2=Tenth, 3=Thousandth
--   info.property         -- SP (numeric)
--
-- The loader is intentionally minimal — it does NOT attempt
-- line-text -> propertyName matching; that responsibility belongs to
-- the caller (which already knows the parsed mod's name).
--
-- @leb-regression-guard: properties-loader-init
-- The loader caches the parsed table per version. Calling load() a
-- second time with the same version is a no-op; with a different
-- version it overwrites byName / bySP. Tests must call load() before
-- accessing tables.

local Properties = {
    version = nil,
    byName  = {},   -- propertyName (string)        -> entry
    bySP    = {},   -- property (numeric SP)        -> entry
    properties = {}, -- ordered list (preserves JSON order)
}

local function readJson(path)
    -- readJsonFile is provided by the LEB main module (Data.lua / Main.lua);
    -- spec/HeadlessWrapper.lua wires it in for headless runs too.
    if readJsonFile then
        return readJsonFile(path)
    end
    -- Fallback for environments without the helper (unlikely): use dkjson.
    local ok, dkjson = pcall(require, "dkjson")
    if not ok then return nil end
    local f = io.open(path, "r")
    if not f then return nil end
    local body = f:read("*a"); f:close()
    return dkjson.decode(body, 1, false)
end

function Properties.load(ver)
    ver = ver or "1_4"
    -- Accept "1.4" or "1_4" forms, normalize to underscore (matches filename).
    ver = (ver:gsub("%.", "_"))
    if Properties.version == ver and next(Properties.byName) then
        return true
    end
    local data = readJson("Data/Properties/property_list_" .. ver .. ".json")
    if not data or not data.properties then
        return false, "Failed to load property_list_" .. ver .. ".json"
    end
    Properties.version = ver
    Properties.byName  = {}
    Properties.bySP    = {}
    Properties.properties = data.properties
    for _, p in ipairs(data.properties) do
        if p.propertyName and p.propertyName ~= "" then
            Properties.byName[p.propertyName] = p
        end
        if p.property ~= nil then
            Properties.bySP[p.property] = p
        end
    end
    return true
end

-- Convenience: rounding enum lookup with fallback.
-- Returns 0/1/2/3 (PropertyRounding enum), defaults to 0=Hundredth.
function Properties.roundingForName(propName)
    local entry = Properties.byName[propName]
    if entry and entry.roundingForAdded ~= nil then
        return entry.roundingForAdded
    end
    return 0
end

function Properties.roundingForSP(sp)
    local entry = Properties.bySP[sp]
    if entry and entry.roundingForAdded ~= nil then
        return entry.roundingForAdded
    end
    return 0
end

return Properties
