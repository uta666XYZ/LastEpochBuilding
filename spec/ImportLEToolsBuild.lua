-- Headless re-import of an LETools planner build.
-- Mirrors ImportTabClass:DownloadLEToolsPlannerBuild but uses curl (Cloudflare
-- requires a real browser User-Agent) and saves the resulting build as
--    spec/TestBuilds/1.4/<plannerCode> lv<level> <ascendency>.xml
-- Usage (from worktree root):
--    LEB_PLANNER=QeY7m5Xq busted --lua=luajit --run=importOne
--    LEB_PLANNER=https://www.lastepochtools.com/planner/QeY7m5Xq busted --lua=luajit --run=importOne
--
-- If running in an environment where Cloudflare blocks the curl request (Docker
-- containers commonly get 403 even with a browser User-Agent), pre-fetch the
-- API JSON manually with the LEB app (it dumps to ../letools_raw.json on
-- import) or by other means and pass it via:
--    LEB_PLANNER=QeY7m5Xq LEB_PLANNER_JSON=../letools_raw.json busted --lua=luajit --run=importOne

local plannerArg = os.getenv("LEB_PLANNER")
if not plannerArg or plannerArg == "" then
    error("LEB_PLANNER env var is required (planner code or full URL)")
end
local buildId = plannerArg:match("planner/([%w_%-]+)") or plannerArg

local browserUA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36"
local plannerURL = "https://www.lastepochtools.com/planner/" .. buildId

local function readAll(path)
    local f, err = io.open(path, "rb")
    if not f then error("Cannot read " .. path .. ": " .. tostring(err)) end
    local body = f:read("*a"); f:close(); return body
end

local function fetch(url)
    local tmp = os.tmpname()
    -- On Windows, os.tmpname() returns a relative path like "\s2j5.tmp" — prefix
    -- with TEMP if available so curl doesn't choke on directory permissions.
    if package.config:sub(1,1) == "\\" then
        local tdir = os.getenv("TEMP") or os.getenv("TMP") or "."
        tmp = tdir .. tmp
    end
    local cmd = string.format('curl -sSL -A "%s" -o "%s" "%s"', browserUA, tmp, url)
    local ok = os.execute(cmd)
    if ok ~= 0 and ok ~= true then
        error("curl failed (rc=" .. tostring(ok) .. ") for " .. url)
    end
    local body = readAll(tmp)
    os.remove(tmp)
    return body
end

-- Allow a pre-fetched API response so this script works even when the running
-- environment is blocked by Cloudflare (e.g. inside Docker — LETools returns
-- 403 to non-browser TLS fingerprints). Set LEB_PLANNER_JSON to the path of a
-- file that contains the body of /api/internal/planner_data/<token>.
local apiBody
local prefetched = os.getenv("LEB_PLANNER_JSON")
if prefetched and prefetched ~= "" then
    print("[ImportLEToolsBuild] Using pre-fetched API JSON: " .. prefetched)
    apiBody = readAll(prefetched)
else
    print("[ImportLEToolsBuild] Fetching planner page: " .. plannerURL)
    local html = fetch(plannerURL)
    local token = html:match("var%s+[%w_]+%s*=%s*'([0-9a-f]+)'")
    if not token or #token < 16 then
        error("Could not extract token from planner page (got " .. #html .. " bytes)")
    end
    local apiURL = "https://www.lastepochtools.com/api/internal/planner_data/" .. token
    print("[ImportLEToolsBuild] Fetching API: " .. apiURL)
    apiBody = fetch(apiURL)
end

-- Reset to a fresh build so import populates a clean state.
newBuild()

local jsonData, _, parseErr = dkjson.decode(apiBody, 1, false)
if parseErr or type(jsonData) ~= "table" then
    error("JSON decode failed: " .. tostring(parseErr))
end
local data = jsonData.data
if type(data) ~= "table" then
    error("LETools API response missing .data field")
end

local importTab = build.importTab
local char = importTab:BuildCharFromLETools(jsonData, data, buildId)
if not char then error("BuildCharFromLETools returned nil") end
importTab:BuildItemsFromLETools(data, char)
importTab:ImportPassiveTreeAndJewels(char)
importTab:ImportItemsAndSkills(char)
importTab:ImportBlessingsFromLETools(data)

-- Quest reward defaults match the in-app DownloadLEToolsPlannerBuild flow.
build.configTab.input.questApophisMajasa = true
build.configTab.input.questTempleOfEterra = false
build.configTab:BuildModList()
build.configTab:UpdateControls()
build.buildFlag = true
runCallback("OnFrame")
build.calcsTab:BuildOutput()

local level = build.characterLevel or char.level or 0
local ascend = (build.spec and build.spec.curAscendClassName) or "Unknown"
local outDir = (io.open("../manifest.xml", "r") and "../spec/TestBuilds/1.4/") or "spec/TestBuilds/1.4/"
local outName = string.format("%s%s lv%d %s.xml", outDir, buildId, level, ascend)

local xmlText = build:SaveDB(outName)
if not xmlText then error("build:SaveDB returned nil") end

local now = os.date("!%Y-%m-%dT%H:%M:%SZ")
local sourceTag = string.format(
    '\t\t<Source url=%q plannerCode=%q importedAt=%q lebVersion=%q/>\n',
    "https://www.lastepochtools.com/planner/" .. buildId,
    buildId, now, "v0.13.0")

-- Strip an existing <Source .../> line (if any) so re-import always refreshes
-- importedAt without leaving a stale entry. Then inject after the <Build ...>
-- opening tag.
xmlText = xmlText:gsub("\n\t*<Source [^/]-/>", "")
local replaced
xmlText, replaced = xmlText:gsub("(<Build [^>]*>\n)", "%1" .. sourceTag, 1)
if replaced == 0 then
    error("Could not locate <Build> tag in saved XML")
end

local outF, err = io.open(outName, "w+")
if not outF then error("Cannot write " .. outName .. ": " .. tostring(err)) end
outF:write(xmlText); outF:close()
print(string.format("[ImportLEToolsBuild] Wrote %s (%d bytes)", outName, #xmlText))
