-- Dump scalar stats from mainOutput for each build listed in
-- ../.tmp/altar_builds.txt to ../.tmp/altar_stats_<tag>.csv.
-- The <tag> is read from env LEB_TAG (e.g. "post" / "pre").
--
-- Run twice (with ItemTools.lua at post-fix and pre-fix states) to diff.

local listPath = "../.tmp/altar_builds.txt"
local tag = os.getenv("LEB_TAG") or "out"
local outPath = "../.tmp/altar_stats_" .. tag .. ".csv"

local listFh = assert(io.open(listPath, "r"), "missing " .. listPath)
local builds = {}
for line in listFh:lines() do
    if line and line ~= "" then table.insert(builds, "../" .. line) end
end
listFh:close()
print(string.format("[gen-list] %d builds queued; tag=%s", #builds, tag))

local out = assert(io.open(outPath, "w+"))
out:write("build,stat,value\n")

for i, path in ipairs(builds) do
    local fh = io.open(path, "r")
    if fh then
        local xml = fh:read("*a"); fh:close()
        local name = path:match("([^/]+)%.xml$") or path
        local ok, err = pcall(function()
            newBuild()
            loadBuildFromXML(xml, path)
            build.buildFlag = true
            runCallback("OnFrame")
            build.calcsTab:BuildOutput()
        end)
        if not ok then
            out:write(string.format("%q,ERROR,%q\n", name, tostring(err):sub(1, 200)))
        else
            local mainOutput = build.calcsTab and build.calcsTab.mainOutput
            if mainOutput then
                local keys = {}
                for k in pairs(mainOutput) do table.insert(keys, k) end
                table.sort(keys)
                for _, k in ipairs(keys) do
                    local v = mainOutput[k]
                    if type(v) == "number" then
                        out:write(string.format("%q,%s,%.6f\n", name, k, v))
                    end
                end
            end
        end
        if i % 10 == 0 then
            print(string.format("[gen-list] %d/%d done", i, #builds))
            io.flush()
        end
    end
end
out:close()
print("[gen-list] done -> " .. outPath)
