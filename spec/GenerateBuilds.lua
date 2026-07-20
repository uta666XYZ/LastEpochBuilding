local function fetchBuilds(path, buildList)
    buildList = buildList or {}
    for file in lfs.dir(path) do
        if file ~= "." and file ~= ".." then
            local f = path..'/'..file
            local attr = lfs.attributes (f)
            assert(type(attr) == "table")
            if attr.mode == "directory" then
                fetchBuilds(f, buildList)
            else
                if file:match("^.+(%..+)$") == ".json" then
                    local fileHnd, errMsg = io.open(f, "r")
                    if not fileHnd then
                        return nil, errMsg
                    end
                    local fileText = fileHnd:read("*a")
                    fileHnd:close()
                    buildList[f] = fileText
                end
            end
        end
    end
    return buildList
end

local function formatXmlFile(filepath)
    local command = "xmllint --c14n " .. filepath
    local handle = io.popen(command, 'r')
    local result = handle and handle:read("*a") or ""
    if handle then handle:close() end

    if not result or result == "" then
        local srcHnd = io.open(filepath, "r")
        if srcHnd then
            result = srcHnd:read("*a")
            srcHnd:close()
        end
    end

    local fileHnd = io.open(filepath:gsub("-unformatted", ""), "w")
    if fileHnd then
        fileHnd:write(result)
        fileHnd:close()
    end
end

-- @leb-regression-guard:generatebuilds-nested-table-serializer
-- buildTable serializes a Lua value tree to the snapshot `.lua` format
-- (`["key"] = value,`). The NESTED-table branch must CAPTURE the recursive
-- result and emit it as `<keyRef> = {<body>},` -- the old code called
-- `buildTable(key, value, string)` and DISCARDED the return (Lua strings are
-- immutable, so passing `string` does not mutate the caller), silently DROPPING
-- every table-valued key. mainOutput carries real nested tables (a Beastmaster's
-- `output.Minion` has 701 entries, `output.SkillDPS` 2) -> minion snapshots lost
-- the entire Minion sub-output, and the #63/#70 regen corrupted Druid snapshots.
-- Format is preserved EXACTLY for flat string-keyed tables (byte-identical to the
-- old output: `["key"]` ref, round(v,4), lexical sort) so non-nested snapshots do
-- not churn; numeric keys (only in nested arrays) use `[n]` for correct round-trip,
-- and the sort comparator is type-aware so mixed-type nested tables don't error
-- (the old `table.sort(keys)` threw on number-vs-string keys). NOT switched to
-- Common.writeLuaTable: that emits a different format (bare `key=`, full precision,
-- no trailing comma) which would reformat the entire buildTable-format corpus.
-- See REGRESSION_GUARDS.md "generatebuilds-nested-table-serializer".
function buildTable(tableName, values, string)
    string = string or ""
    string = string .. tableName .. " = {"
    -- Sort by keys (type-aware so nested tables with mixed key types don't error)
    local keys = {}
    for k in pairs(values) do table.insert(keys, k) end
    table.sort(keys, function(a, b)
        if type(a) == type(b) then return a < b else return type(a) < type(b) end
    end)
    for _, key in pairs(keys) do
        local value = values[key]
        -- @leb-regression-guard:minion-skill-breakdown-display
        -- MinionSkillBreakdown is a DISPLAY-ONLY output sub-table (per-minion damaging
        -- sub-skill DPS for the Full DPS panel). It does not feed any total, so it is
        -- excluded from the snapshot to keep corpus snapshots byte-identical (the key is
        -- new -> skipping it is a no-op for every existing snapshot).
        if key == "MinionSkillBreakdown" then goto continue end
        local keyRef = type(key) == "number" and ("[" .. key .. "]") or ("[\"" .. key .. "\"]")
        if type(value) == "table" then
            -- Capture the recursive serialization (the old code discarded it ->
            -- dropped the whole nested table). Re-emit as `<keyRef> = {<body>},`.
            local nested = buildTable("", value):gsub("^ = ", ""):gsub("\n$", "")
            string = string .. keyRef .. " = " .. nested .. ",\n"
        elseif type(value) == "boolean" then
            string = string .. keyRef .. " = " .. (value and "true" or "false") .. ",\n"
        elseif type(value) == "string" then
            string = string .. keyRef .. " = \"" .. value .. "\",\n"
        else
            string = string .. keyRef .. " = " .. round(value, 4) .. ",\n"
        end
        ::continue::
    end
    string = string .. "}\n"
    return string
end

-- @leb-regression-guard:regen-root-equals-test-root
-- Regen root comes from the shared constant, never a literal: a regen driver that
-- roots at a narrower tree than spec/System/TestBuilds_spec.lua walks leaves builds
-- that are tested but unreachable by any regen. See spec/CorpusScope.lua.
local CorpusScope = dofile("../spec/CorpusScope.lua")

local buildList = fetchBuilds(CorpusScope.ROOT)
for filename, importCode in pairs(buildList) do
    print("Loading build " .. filename)
    loadBuildFromXML(importCode, filename)
    local fileHnd, errMsg = io.open(filename:gsub("^(.+)%..+$", "%1.lua"), "w+")
    fileHnd:write("return {\n    ")
    fileHnd:write(buildTable("output", build.calcsTab.mainOutput) .. "\n}")
    fileHnd:close()
    build.dbFileName = filename:gsub("^(.+)%..+$", "%1-unformatted.xml")
    build:SaveDBFile()
    -- Format/order the XML file to easily see differences with previous generations
    formatXmlFile(build.dbFileName)
end
