-- One-time script to regenerate .lua snapshots from 1.4 XML builds
local function fetchBuilds(path, buildList)
    buildList = buildList or {}
    for file in lfs.dir(path) do
        if file ~= "." and file ~= ".." then
            local f = path..'/'..file
            local attr = lfs.attributes(f)
            assert(type(attr) == "table")
            if attr.mode == "directory" then
                fetchBuilds(f, buildList)
            else
                if file:match("^.+(%..+)$") == ".xml" and not file:match("%-unformatted%.xml$") then
                    local luaPath = f:gsub("%.xml$", ".lua")
                    local luaHnd = io.open(luaPath, "r")
                    if luaHnd then
                        luaHnd:close()
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
    end
    return buildList
end

function buildTable(tableName, values, string)
    string = string or ""
    string = string .. tableName .. " = {"
    local keys = {}
    for k in pairs(values) do table.insert(keys, k) end
    table.sort(keys)
    for _, key in pairs(keys) do
        local value = values[key]
        if type(value) == "table" then
            buildTable(key, value, string)
        elseif type(value) == "boolean" then
            string = string .. "[\"" .. key .. "\"] = " .. (value and "true" or "false") .. ",\n"
        elseif type(value) == "string" then
            string = string .. "[\"" .. key .. "\"] = \"" .. value .. "\",\n"
        else
            string = string .. "[\"" .. key .. "\"] = " .. round(value, 4) .. ",\n"
        end
    end
    string = string .. "}\n"
    return string
end

local buildList = fetchBuilds("../spec/TestBuilds/1.4")
for filename, importCode in pairs(buildList) do
    print("Loading build " .. filename)
    loadBuildFromXML(importCode, filename)
    local luaPath = filename:gsub("%.xml$", ".lua")
    local fileHnd, errMsg = io.open(luaPath, "w+")
    if not fileHnd then
        print("ERROR opening " .. luaPath .. ": " .. tostring(errMsg))
    else
        fileHnd:write("return {\n    ")
        fileHnd:write(buildTable("output", build.calcsTab.mainOutput) .. "\n}")
        fileHnd:close()
    end
end
