-- Headless re-import of a Maxroll account/character build.
-- Usage:
--   LEB_MAXROLL_ACCOUNT=ROGER_FDC LEB_MAXROLL_CHAR=ROEGR_FDC-GG_002 busted --lua=luajit --run=importMaxroll
-- Or pre-fetched JSON:
--   LEB_MAXROLL_JSON=../roger_maxroll_api.json busted --lua=luajit --run=importMaxroll

local function readAll(path)
    local f, err = io.open(path, "rb")
    if not f then error("Cannot read " .. path .. ": " .. tostring(err)) end
    local body = f:read("*a"); f:close(); return body
end

local apiBody
local prefetched = os.getenv("LEB_MAXROLL_JSON")
if prefetched and prefetched ~= "" then
    print("[ImportMaxrollAccount] Using pre-fetched API JSON: " .. prefetched)
    apiBody = readAll(prefetched)
else
    local account = os.getenv("LEB_MAXROLL_ACCOUNT")
    local charName = os.getenv("LEB_MAXROLL_CHAR")
    if not account or account == "" or not charName or charName == "" then
        error("LEB_MAXROLL_ACCOUNT + LEB_MAXROLL_CHAR or LEB_MAXROLL_JSON env var is required")
    end
    local apiURL = "https://planners.maxroll.gg/lastepoch/characters/" .. account .. "/" .. charName
    local tmp = os.tmpname()
    if package.config:sub(1,1) == "\\" then
        local tdir = os.getenv("TEMP") or os.getenv("TMP") or "."
        if not tmp:find("[/\\]") or tmp:sub(1,1) == "\\" then
            tmp = tdir .. tmp
        end
    end
    local cmd = string.format('curl -sSL -o "%s" "%s"', tmp, apiURL)
    print("[ImportMaxrollAccount] " .. cmd)
    local ok = os.execute(cmd)
    if ok ~= 0 and ok ~= true then
        error("curl failed (rc=" .. tostring(ok) .. ") for " .. apiURL)
    end
    apiBody = readAll(tmp)
    os.remove(tmp)
end

newBuild()

local importTab = build.importTab
local ok, charOrErr = pcall(function() return importTab:ReadJsonSaveData(apiBody) end)
if not ok then error("ReadJsonSaveData failed: " .. tostring(charOrErr)) end

-- Mirror DownloadLEToolsProfileBuild: split blessings vs gear by cid.
local blessingItems, gearItems = {}, {}
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

for _, b in ipairs(blessingItems) do
    local info = importTab.currentBlessingLookup and importTab.currentBlessingLookup[b.name or ""]
    if info then
        importTab.build.itemsTab:UpdateBlessingSlot(info.tl, info.entry, b.blessingRollFrac or 1.0)
    end
end

print(string.format("[ImportMaxrollAccount] Done. _droppedAffixes=%d _parseErrors=%d",
    charOrErr._droppedAffixes or 0, charOrErr._parseErrors or 0))
