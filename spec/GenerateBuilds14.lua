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

-- Sharding & resume support via env vars:
--   LEB_SHARD="i/N" -> process only files where sortedIndex % N == i (0-based)
--   LEB_FORCE=1     -> regenerate even if .lua already exists
--   LEB_ONLY="<substr>" -> regenerate ONLY files whose path contains <substr>;
--                          skip everything else regardless of shard. Used by
--                          .tmp/regen-one14.sh to refresh a single build's
--                          snapshot without touching the other 116 builds.
--   LEB_ONLY_FILE=<path> -> regenerate ONLY files whose repo-relative path
--                          appears (as a suffix) in the listed file (one
--                          path per line; CR-LF tolerated). Enforces the
--                          build-group discipline mechanically: callers
--                          pass an affected-builds list and out-of-group
--                          snapshots are skipped even with --clean. Combines
--                          with LEB_SHARD so parallel shards still split
--                          the filtered list. Independent of LEB_ONLY; if
--                          both are set, BOTH must match.
--   LEB_ONLY_LIST="<path>" -> regenerate ONLY files whose path contains ANY of
--                             the newline-separated substrings in the given
--                             file. Useful for batching N specific builds in
--                             one Docker invocation. Combines with LEB_ONLY_FILE
--                             via AND when both are set.
local shardEnv = os.getenv("LEB_SHARD") or ""
local shardI, shardN = shardEnv:match("^(%d+)/(%d+)$")
shardI = tonumber(shardI) or 0
shardN = tonumber(shardN) or 1
local force = os.getenv("LEB_FORCE") == "1"
local onlySubstr = os.getenv("LEB_ONLY") or ""
local onlyListPath = os.getenv("LEB_ONLY_LIST") or ""
local onlyList = nil
if onlyListPath ~= "" then
    local lf = io.open(onlyListPath, "r")
    if lf then
        onlyList = {}
        for line in lf:lines() do
            line = line:gsub("^%s+", ""):gsub("%s+$", "")
            if line ~= "" then table.insert(onlyList, line) end
        end
        lf:close()
        print("[LEB_ONLY_LIST] loaded " .. #onlyList .. " filter entries from " .. onlyListPath)
    else
        print("[LEB_ONLY_LIST] WARN could not open " .. onlyListPath)
    end
end

local onlyFileSet = nil
local onlyFilePath = os.getenv("LEB_ONLY_FILE") or ""
if onlyFilePath ~= "" then
    -- The file is typically written from the worktree root (.tmp/...)
    -- while this script runs with cwd=src/, so resolve "../" prefix
    -- when the bare path doesn't open.
    local fh, err = io.open(onlyFilePath, "r")
    if not fh then
        local alt = "../" .. onlyFilePath
        fh = io.open(alt, "r")
        if not fh then
            error("LEB_ONLY_FILE: cannot open " .. onlyFilePath .. " or " .. alt .. " : " .. tostring(err))
        end
    end
    onlyFileSet = {}
    local count = 0
    for line in fh:lines() do
        line = line:gsub("\r$", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" and not line:match("^#") then
            onlyFileSet[line] = true
            count = count + 1
        end
    end
    fh:close()
    print(string.format("[gen14] LEB_ONLY_FILE=%s loaded %d build paths", onlyFilePath, count))
end

local sortedNames = {}
for filename in pairs(buildList) do table.insert(sortedNames, filename) end
table.sort(sortedNames)

for idx, filename in ipairs(sortedNames) do
    local importCode = buildList[filename]
    local luaPath = filename:gsub("%.xml$", ".lua")
    local skip = false
    if onlySubstr ~= "" and not filename:find(onlySubstr, 1, true) then
        skip = true
    end
    if not skip and onlyFileSet then
        -- Match by suffix: filename inside loader is "../spec/TestBuilds/1.4/X.xml"
        -- while list entries are repo-relative "spec/TestBuilds/1.4/X.xml".
        local matched = false
        for entry in pairs(onlyFileSet) do
            local n = #entry
            if filename:sub(-n) == entry then matched = true; break end
        end
        if not matched then skip = true end
    end
    if not skip and onlyList then
        local match = false
        for _, sub in ipairs(onlyList) do
            if filename:find(sub, 1, true) then match = true; break end
        end
        if not match then skip = true end
    end
    if not skip and ((idx - 1) % shardN) ~= shardI then
        skip = true
    end
    if not skip and not force then
        local existing = io.open(luaPath, "r")
        if existing then existing:close(); skip = true end
    end
    if skip then
        -- silent skip
    else
    print("Loading build " .. filename)
    loadBuildFromXML(importCode, filename)
    local fileHnd, errMsg = io.open(luaPath, "w+")
    if not fileHnd then
        print("ERROR opening " .. luaPath .. ": " .. tostring(errMsg))
    else
        fileHnd:write("return {\n    ")
        local outputBlock = buildTable("output", build.calcsTab.mainOutput)
        outputBlock = outputBlock:gsub("}\n$", "},\n")
        fileHnd:write(outputBlock .. "\n")

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
    end -- close skip-else
end
