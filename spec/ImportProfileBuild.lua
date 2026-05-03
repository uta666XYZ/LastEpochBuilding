-- Headless re-import of an LETools profile URL (Maxroll-backed).
-- Mirrors ImportTabClass:DownloadLEToolsProfileBuild but uses curl to fetch the
-- Maxroll account API and saves the resulting build as
--   <outDir>/<account>_<character>_lv<level>_<subclass>_maxroll.xml
-- Usage (from worktree root):
--   LEB_PROFILE=https://www.lastepochtools.com/profile/Zoobie/character/Ghost \
--     busted --lua=luajit --run=importProfile
--
-- Optional:
--   LEB_PROFILE_JSON=path  -- pre-fetched Maxroll API JSON (skips curl)
--   LEB_OUT_DIR=path       -- defaults to ../src/Builds/1.4 v0.13.0/

local profileArg = os.getenv("LEB_PROFILE")
if not profileArg or profileArg == "" then
    error("LEB_PROFILE env var is required (LETools profile URL)")
end

local accountName, charName = profileArg:match("lastepochtools%.com/profile/([^/]+)/character/([^/?#]+)")
if not accountName or not charName then
    -- Allow shorthand "Account/Character" too.
    accountName, charName = profileArg:match("^([^/]+)/([^/?#]+)$")
end
if not accountName or not charName then
    error("Could not parse LETools profile URL: " .. profileArg)
end

local browserUA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36"
local apiURL = "https://planners.maxroll.gg/lastepoch/characters/" .. accountName .. "/" .. charName

local function readAll(path)
    local f, err = io.open(path, "rb")
    if not f then error("Cannot read " .. path .. ": " .. tostring(err)) end
    local body = f:read("*a"); f:close(); return body
end

local function fetch(url)
    local tmp = os.tmpname()
    if package.config:sub(1,1) == "\\" then
        local tdir = os.getenv("TEMP") or os.getenv("TMP") or "."
        tmp = tdir .. tmp
    end
    local cmd = string.format('curl -sSL -A "%s" -o "%s" -w "%%{http_code}" "%s"', browserUA, tmp, url)
    local p = io.popen(cmd, "r")
    local httpCode = p and p:read("*a") or ""
    if p then p:close() end
    if httpCode ~= "200" then
        local body = ""
        local f = io.open(tmp, "rb")
        if f then body = f:read("*a"); f:close() end
        os.remove(tmp)
        error(string.format("curl http=%s for %s\nbody=%s", tostring(httpCode), url, body:sub(1, 400)))
    end
    local body = readAll(tmp)
    os.remove(tmp)
    return body
end

local apiBody
local prefetched = os.getenv("LEB_PROFILE_JSON")
if prefetched and prefetched ~= "" then
    print("[ImportProfileBuild] Using pre-fetched Maxroll JSON: " .. prefetched)
    apiBody = readAll(prefetched)
else
    print("[ImportProfileBuild] Fetching Maxroll API: " .. apiURL)
    apiBody = fetch(apiURL)
end

newBuild()

local importTab = build.importTab

local ok, charOrErr = pcall(function() return importTab:ReadJsonSaveData(apiBody) end)
if not ok then
    error("ReadJsonSaveData failed: " .. tostring(charOrErr))
end

-- Mirror DownloadLEToolsProfileBuild: partition blessings (cid 33-45) from gear
local blessingItems = {}
local gearItems = {}
for _, item in ipairs(charOrErr.items or {}) do
    local cid = item.inventoryId
    if type(cid) == "number" and cid >= 33 and cid <= 45 then
        table.insert(blessingItems, item)
    else
        table.insert(gearItems, item)
    end
end
charOrErr.items = gearItems

importTab:ImportPassiveTreeAndJewels(charOrErr)
importTab:ImportItemsAndSkills(charOrErr)

local appliedBlessings = 0
for _, b in ipairs(blessingItems) do
    local blessingName = b.name or ""
    local info = importTab.currentBlessingLookup and importTab.currentBlessingLookup[blessingName]
    if info then
        local rollFrac = b.blessingRollFrac or 1.0
        build.itemsTab:UpdateBlessingSlot(info.tl, info.entry, rollFrac)
        appliedBlessings = appliedBlessings + 1
    end
end
print(string.format("[ImportProfileBuild] Blessings applied: %d", appliedBlessings))

build.configTab.input.questApophisMajasa = true
build.configTab.input.questTempleOfEterra = true
build.configTab:BuildModList()
build.configTab:UpdateControls()
build.buildFlag = true
runCallback("OnFrame")
build.calcsTab:BuildOutput()

local level = build.characterLevel or charOrErr.level or 0
local ascend = (build.spec and build.spec.curAscendClassName) or "Unknown"
-- Sanitize ascend for filename (strip whitespace/slashes)
local ascendSafe = (ascend or "Unknown"):gsub("[^%w]", "")

local outDir = os.getenv("LEB_OUT_DIR")
if not outDir or outDir == "" then
    outDir = (io.open("../manifest.xml", "r") and "../src/Builds/1.4 v0.13.0/") or "src/Builds/1.4 v0.13.0/"
end
if outDir:sub(-1) ~= "/" and outDir:sub(-1) ~= "\\" then
    outDir = outDir .. "/"
end

local outName = string.format("%s%s_%s_lv%d_%s_maxroll.xml", outDir, accountName, charName, level, ascendSafe)

local xmlText = build:SaveDB(outName)
if not xmlText then error("build:SaveDB returned nil") end

local now = os.date("!%Y-%m-%dT%H:%M:%SZ")
local profileURL = string.format("https://www.lastepochtools.com/profile/%s/character/%s", accountName, charName)
local sourceTag = string.format(
    '\t\t<Source url=%q account=%q character=%q importedAt=%q lebVersion=%q/>\n',
    profileURL, accountName, charName, now, "v0.13.0")

xmlText = xmlText:gsub("\n\t*<Source [^/]-/>", "")
local replaced
xmlText, replaced = xmlText:gsub("(<Build [^>]*>\n)", "%1" .. sourceTag, 1)
if replaced == 0 then
    error("Could not locate <Build> tag in saved XML")
end

local outF, err = io.open(outName, "w+")
if not outF then error("Cannot write " .. outName .. ": " .. tostring(err)) end
outF:write(xmlText); outF:close()
print(string.format("[ImportProfileBuild] Wrote %s (%d bytes)", outName, #xmlText))
