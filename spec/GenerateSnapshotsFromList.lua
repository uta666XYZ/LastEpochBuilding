-- Regenerate .lua snapshots for the builds listed in
-- ../.tmp/affected_builds.txt (one repo-relative .xml path per line).
--
-- Mirrors spec/GenerateBuilds14.lua's snapshot format (output + per-socket
-- skills tables) so the regenerated .lua files drop in next to the existing
-- 1.4 snapshots without format drift. Use this when a fix affects a known
-- subset of builds and a full regen-shards run would touch out-of-scope
-- snapshots (build-group discipline: never regen builds outside the
-- group under investigation).

local function sanitizeLabel(s)
    s = tostring(s or ""):gsub('[^%w%s%-_]', ''):gsub('%s+', '_')
    if s == "" then s = "unnamed" end
    return s
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

local listPath = "../.tmp/affected_builds.txt"
local listFh = assert(io.open(listPath, "r"), "missing " .. listPath)
local builds = {}
for line in listFh:lines() do
    if line then line = line:gsub("\r$", "") end
    if line and line ~= "" then table.insert(builds, "../" .. line) end
end
listFh:close()
print(string.format("[gen-snap-list] %d builds queued", #builds))

for idx, filename in ipairs(builds) do
    local fh, ferr = io.open(filename, "r")
    if not fh then
        print("[gen-snap-list] SKIP (cannot open): " .. filename .. " : " .. tostring(ferr))
    else
        local importCode = fh:read("*a"); fh:close()
        local luaPath = filename:gsub("%.xml$", ".lua")
        print(string.format("[gen-snap-list] %d/%d %s", idx, #builds, filename))
        local ok, err = pcall(function()
            newBuild()
            loadBuildFromXML(importCode, filename)
            build.buildFlag = true
            runCallback("OnFrame")
            build.calcsTab:BuildOutput()
        end)
        if not ok then
            print("[gen-snap-list] LOAD ERROR: " .. tostring(err))
        else
            local outFh, oerr = io.open(luaPath, "w+")
            if not outFh then
                print("[gen-snap-list] WRITE ERROR " .. luaPath .. " : " .. tostring(oerr))
            else
                outFh:write("return {\n    ")
                local outputBlock = buildTable("output", build.calcsTab.mainOutput)
                outputBlock = outputBlock:gsub("}\n$", "},\n")
                outFh:write(outputBlock .. "\n")

                local socketGroupList = build.skillsTab and build.skillsTab.socketGroupList or {}
                local originalMain = build.mainSocketGroup or 1
                outFh:write("    skills = {\n")
                for i = 1, #socketGroupList do
                    local sok, serr = pcall(function()
                        build.mainSocketGroup = i
                        build.calcsTab:BuildOutput()
                    end)
                    local group = socketGroupList[i]
                    local label = sanitizeLabel(group and group.displayLabel or ("slot"..i))
                    local slotName = "slot" .. i .. "_" .. label
                    outFh:write("        [\"" .. slotName .. "\"] = ")
                    if sok and build.calcsTab and build.calcsTab.mainOutput then
                        local inner = buildTable("_", build.calcsTab.mainOutput)
                        inner = inner:gsub("^_ = ", "")
                        inner = inner:gsub("}\n$", "},\n")
                        outFh:write(inner)
                    else
                        outFh:write("{ __err = \"" .. tostring(serr):gsub('"','\'') .. "\" },\n")
                    end
                end
                outFh:write("    },\n}")
                pcall(function()
                    build.mainSocketGroup = originalMain
                    build.calcsTab:BuildOutput()
                end)
                outFh:close()
            end
        end
        if idx % 10 == 0 then io.flush() end
    end
end
print("[gen-snap-list] done")
