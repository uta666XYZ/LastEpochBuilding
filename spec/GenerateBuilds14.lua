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

local function sanitizeLabel(s)
    s = tostring(s or ""):gsub('[^%w%s%-_]', ''):gsub('%s+', '_')
    if s == "" then s = "unnamed" end
    return s
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
        fileHnd:write(buildTable("output", build.calcsTab.mainOutput) .. "\n")

        -- Per-socket-group output: cycle mainSocketGroup through every slot
        local socketGroupList = build.skillsTab and build.skillsTab.socketGroupList or {}
        local originalMain = build.mainSocketGroup or 1
        fileHnd:write("    skills = {\n")
        for i = 1, #socketGroupList do
            local ok, err = pcall(function()
                build.mainSocketGroup = i
                build.calcsTab:BuildOutput()
            end)
            local group = socketGroupList[i]
            local label = sanitizeLabel(group and group.displayLabel or ("slot"..i))
            local slotName = "slot" .. i .. "_" .. label
            fileHnd:write("        [\"" .. slotName .. "\"] = ")
            if ok and build.calcsTab and build.calcsTab.mainOutput then
                local inner = buildTable("_", build.calcsTab.mainOutput)
                inner = inner:gsub("^_ = ", "")
                inner = inner:gsub("}\n$", "},\n")
                fileHnd:write(inner)
            else
                fileHnd:write("{ __err = \"" .. tostring(err):gsub('"','\'') .. "\" },\n")
            end
        end
        fileHnd:write("    },\n}")
        -- restore
        pcall(function()
            build.mainSocketGroup = originalMain
            build.calcsTab:BuildOutput()
        end)
        fileHnd:close()
    end
end
