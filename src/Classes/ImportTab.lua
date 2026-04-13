-- Last Epoch Building
--
-- Module: Import Tab
-- Import/Export tab for the current build.
--
local ipairs = ipairs
local t_insert = table.insert
local t_remove = table.remove
local b_rshift = bit.rshift
local band = bit.band

local influenceInfo = itemLib.influenceInfo

local ImportTabClass = newClass("ImportTab", "ControlHost", "Control", function(self, build)
    self.ControlHost()
    self.Control()

    self.build = build

    self.isOnlineMode = false
    self.charImportMode = "GETACCOUNTNAME"
    self.charImportStatus = "Idle"
    self.activeImportSection = nil
    self.controls.sectionCharImport = new("SectionControl", { "TOPLEFT", self, "TOPLEFT" }, 10, 18, 750, 320, "Character Import")
    self.controls.charImportStatusLabel = new("LabelControl", { "TOPLEFT", self.controls.sectionCharImport, "TOPLEFT" }, 6, 14, 200, 16, function()
        return "^7Character import status: " .. self.charImportStatus
    end)

    -- Stage: input account name
    self.controls.accountNameHeaderOffline = new("LabelControl", { "TOPLEFT", self.controls.sectionCharImport, "TOPLEFT" }, 6, 40, 400, 16, "^71. Offline Import")
    self.controls.accountNameHeaderOffline.shown = function()
        return self.charImportMode == "GETACCOUNTNAME" and self.activeImportSection ~= 2 and self.activeImportSection ~= 3
    end
    self.controls.accountNameGoOffline = new("ButtonControl", { "TOPLEFT", self.controls.accountNameHeaderOffline, "BOTTOMLEFT" }, 0, 4, 180, 20, "Import Offline Character", function()
        self.isOnlineMode = false
        self.activeImportSection = 1
        self:DownloadCharacterList()
    end)
    self.controls.accountNameGoOffline.shown = function()
        return self.charImportMode == "GETACCOUNTNAME" and self.activeImportSection ~= 2 and self.activeImportSection ~= 3
    end
    -- Stage: input account name (Online)
    self.controls.accountNameHeader = new("LabelControl", { "TOPLEFT", self.controls.accountNameGoOffline, "BOTTOMLEFT" }, 0, 10, 450, 16, "^72. Online Import (via Maxroll)")
    self.controls.accountNameHeader.shown = function()
        return self.charImportMode == "GETACCOUNTNAME" and self.activeImportSection ~= 1 and self.activeImportSection ~= 3
    end
    self.controls.accountName = new("EditControl", { "TOPLEFT", self.controls.accountNameHeader, "BOTTOMLEFT" }, 0, 4, 200, 20, main.lastAccountName or "", nil, "%c", nil, nil, nil, nil, true)
    self.controls.accountName.placeholder = "Account name"
    self.controls.accountName.shown = function()
        return self.charImportMode == "GETACCOUNTNAME" and self.activeImportSection ~= 1 and self.activeImportSection ~= 3
    end
    self.controls.accountName.pasteFilter = function(text)
        return text:gsub("[\128-\255]", function(c)
            return codePointToUTF8(c:byte(1)):gsub(".", function(c)
                return string.format("%%%X", c:byte(1))
            end)
        end)
    end
    -- accountHistory Control
    if not historyList then
        historyList = { }
        for accountName, account in pairs(main.gameAccounts) do
            t_insert(historyList, accountName)
            historyList[accountName] = true
        end
        table.sort(historyList, function(a, b)
            return a:lower() < b:lower()
        end)
    end -- don't load the list many times
    self.controls.accountNameGo = new("ButtonControl", { "LEFT", self.controls.accountName, "RIGHT" }, 8, 0, 100, 20, "Start Import", function()
        self.isOnlineMode = true
        self.activeImportSection = 2
        self:DownloadCharacterListOnline()
    end)
    self.controls.accountNameGo.shown = function()
        return self.charImportMode == "GETACCOUNTNAME" and self.activeImportSection ~= 1 and self.activeImportSection ~= 3
    end
    self.controls.accountNameGo.enabled = function()
        return self.controls.accountName.buf:match("%S")
    end

    self.controls.accountHistory = new("DropDownControl", { "LEFT", self.controls.accountNameGo, "RIGHT" }, 8, 0, 200, 20, historyList, function()
        self.controls.accountName.buf = self.controls.accountHistory.list[self.controls.accountHistory.selIndex]
    end)
    self.controls.accountHistory.placeholder = "History"
    self.controls.accountHistory.shown = function()
        return self.charImportMode == "GETACCOUNTNAME" and self.activeImportSection ~= 1 and self.activeImportSection ~= 3
    end
    self.controls.accountHistory:SelByValue(main.lastAccountName)
    self.controls.accountHistory:CheckDroppedWidth(true)

    self.controls.removeAccount = new("ButtonControl", { "LEFT", self.controls.accountHistory, "RIGHT" }, 8, 0, 20, 20, "X", function()
        local accountName = self.controls.accountHistory.list[self.controls.accountHistory.selIndex]
        if (accountName ~= nil) then
            t_remove(self.controls.accountHistory.list, self.controls.accountHistory.selIndex)
            self.controls.accountHistory.list[accountName] = nil
            main.gameAccounts[accountName] = nil
        end
    end)
    self.controls.removeAccount.shown = function()
        return self.charImportMode == "GETACCOUNTNAME" and self.activeImportSection ~= 1 and self.activeImportSection ~= 3
    end

    self.controls.removeAccount.tooltipFunc = function(tooltip)
        tooltip:Clear()
        tooltip:AddLine(16, "^7Removes account from the dropdown list")
    end

    -- Stage: select character and import data
    self.controls.source = new("ButtonControl", { "TOPLEFT", self.controls.sectionCharImport, "TOPLEFT" }, 6, 50, 438, 18, "^7Source: ^x4040FFhttps://planners.maxroll.gg")
    self.controls.source.shown = function()
        if self.charImportMode == "SELECTCHAR" then
            return self.isOnlineMode
        end
        return false
    end
    self.controls.charSelectHeader = new("LabelControl", { "TOPLEFT", self.controls.sectionCharImport, "TOPLEFT" }, 6, 70, 200, 16, "^7Choose character to import data from:")
    self.controls.charSelectHeader.shown = function()
        return self.charImportMode == "SELECTCHAR" or self.charImportMode == "IMPORTING"
    end
    self.controls.charSelectLeagueLabel = new("LabelControl", { "TOPLEFT", self.controls.charSelectHeader, "BOTTOMLEFT" }, 0, 6, 0, 14, "^7League:")
    self.controls.charSelectLeague = new("DropDownControl", { "LEFT", self.controls.charSelectLeagueLabel, "RIGHT" }, 4, 0, 150, 18, nil, function(index, value)
        self:BuildCharacterList(value.league)
    end)
    self.controls.charSelect = new("DropDownControl", { "TOPLEFT", self.controls.charSelectHeader, "BOTTOMLEFT" }, 0, 24, 400, 18)
    self.controls.charSelect.enabled = function()
        return self.charImportMode == "SELECTCHAR"
    end
    self.controls.charDownload = new("ButtonControl", { "TOPLEFT", self.controls.charSelect, "BOTTOMLEFT" }, 0, 8, 100, 20, "Download", function()
        self:DownloadFromMaxroll()
    end)
    self.controls.charDownload.shown = function()
        local charSelect = self.controls.charSelect
        return self.isOnlineMode and #charSelect.list > 0
    end
    self.controls.charImportHeader = new("LabelControl", { "TOPLEFT", self.controls.charSelect, "BOTTOMLEFT" }, 0, 40, 200, 16, "Import:")
    self.controls.charImportHeader.shown = function()
        local charSelect = self.controls.charSelect
        if #charSelect.list > 0 then
            local charData = charSelect.list[charSelect.selIndex].char
            return charData.hashes
        end
        return false
    end
    self.controls.charImportFull = new("ButtonControl", { "LEFT", self.controls.charImportHeader, "RIGHT" }, 8, 0, 80, 20, "Full Import", function()
        if self.build.spec:CountAllocNodes() > 0 then
            main:OpenConfirmPopup("Character Import", "Full import will overwrite your current passive tree and replace items/skills.", "Import", function()
                self:DownloadFullImport()
            end)
        else
            self:DownloadFullImport()
        end
    end)
    self.controls.charImportFullOptions = new("LabelControl", { "LEFT", self.controls.charImportFull, "RIGHT" }, 8, 0, 200, 16, "(uses below options)")
    self.controls.charImportFull.enabled = function()
        return self.charImportMode == "SELECTCHAR"
    end
    self.controls.charImportTree = new("ButtonControl", { "LEFT", self.controls.charImportHeader, "LEFT" }, 8, 36, 200, 20, "Only Passive Tree and Skills", function()
        if self.build.spec:CountAllocNodes() > 0 then
            main:OpenConfirmPopup("Character Import", "Importing the passive tree will overwrite your current tree.", "Import", function()
                self:DownloadPassiveTree()
            end)
        else
            self:DownloadPassiveTree()
        end
    end)
    self.controls.charImportTree.enabled = function()
        return self.charImportMode == "SELECTCHAR"
    end
    self.controls.charImportItems = new("ButtonControl", { "LEFT", self.controls.charImportTree, "LEFT" }, 0, 24, 140, 20, "Only Items", function()
        self:DownloadItems()
    end)
    self.controls.charImportItems.enabled = function()
        return self.charImportMode == "SELECTCHAR"
    end
    self.controls.charImportItemsClearItems = new("CheckBoxControl", { "LEFT", self.controls.charImportItems, "RIGHT" }, 120, 0, 18, "Delete equipment:", nil, "Delete all equipped items when importing.", true)
    self.controls.charImportUnusedItemsClearItems = new("CheckBoxControl", { "LEFT", self.controls.charImportItems, "RIGHT" }, 280, 0, 18, "Delete unused items:", nil, "Delete all unused items when importing.", false)

    self.controls.charClose = new("ButtonControl", { "TOPLEFT", self.controls.charSelect, "BOTTOMLEFT" }, 0, 136, 60, 20, "Close", function()
        self.charImportMode = "GETACCOUNTNAME"
        self.charImportStatus = "Idle"
        self.activeImportSection = nil
    end)

    -- Build import/export
    self.controls.sectionBuild = new("SectionControl", { "TOPLEFT", self.controls.sectionCharImport, "BOTTOMLEFT" }, 0, 18, 650, 140, "Build Sharing")
    self.controls.generateCodeLabel = new("LabelControl", { "TOPLEFT", self.controls.sectionBuild, "TOPLEFT" }, 6, 14, 0, 16, "^7Generate a code to share this build with other Last Epoch Building users:")

    -- Online sharing (primary)
    self.controls.generateCodeByLink = new("ButtonControl", { "TOPLEFT", self.controls.generateCodeLabel, "BOTTOMLEFT" }, 0, 6, 110, 20, "Get Short Link", function()
        local code = self.controls.generateCodeOut.buf
        if #code == 0 then
            code = "!" .. common.base85.encode(Deflate(self.build:SaveDB("code")))
            self.controls.generateCodeOut:SetText(code)
        end
        self.controls.generateCodeByLink.label = "Uploading..."
        local response = buildSites.UploadToBytebin(code)
        if response then
            launch:RegisterSubScript(response, function(url, errMsg)
                self.controls.generateCodeByLink.label = "Get Short Link"
                if errMsg then
                    main:OpenMessagePopup("bytebin", "Error uploading to bytebin:\n" .. errMsg)
                else
                    self.controls.generateURLOut:SetText(url)
                end
            end)
        end
    end)
    self.controls.generateCodeByLink.tooltipFunc = function(tooltip)
        tooltip:Clear()
        tooltip:AddLine(14, "^7Generate code and upload to bytebin to get a short link.")
        tooltip:AddLine(14, "^7Requires an internet connection.")
    end
    self.controls.generateURLOut = new("EditControl", { "LEFT", self.controls.generateCodeByLink, "RIGHT" }, 8, 0, 220, 20, "", "Link (Requires Internet)", "%Z")
    self.controls.generateURLOut.enabled = function()
        return #self.controls.generateURLOut.buf > 0
    end
    self.controls.generateURLCopy = new("ButtonControl", { "LEFT", self.controls.generateURLOut, "RIGHT" }, 8, 0, 60, 20, "Copy", function()
        Copy(self.controls.generateURLOut.buf)
        self.controls.generateURLOut:SetText("")
    end)
    self.controls.generateURLCopy.enabled = function()
        return #self.controls.generateURLOut.buf > 0
    end

    -- Code sharing (secondary)
    self.controls.generateCode = new("ButtonControl", { "TOPLEFT", self.controls.generateCodeByLink, "BOTTOMLEFT" }, 0, 8, 110, 20, "Generate Code", function()
        self.controls.generateCodeOut:SetText("!" .. common.base85.encode(Deflate(self.build:SaveDB("code"))))
    end)
    self.controls.enablePartyExportBuffs = new("CheckBoxControl", { "LEFT", self.controls.generateCode, "RIGHT" }, 8, 0, 18, "Export Support", function(state)
        self.build.partyTab.enableExportBuffs = state
        self.build.buildFlag = true
    end, "This is for party play, to export support character, it enables the exporting of auras, curses and modifiers to the enemy", false)
    self.controls.enablePartyExportBuffs.shown = false
    self.controls.generateCodeOut = new("EditControl", { "LEFT", self.controls.generateCode, "RIGHT" }, 8, 0, 220, 20, "", "Offline Code", "%Z")
    self.controls.generateCodeOut.enabled = function()
        return #self.controls.generateCodeOut.buf > 0
    end
    self.controls.generateCodeCopy = new("ButtonControl", { "LEFT", self.controls.generateCodeOut, "RIGHT" }, 8, 0, 60, 20, "Copy", function()
        Copy(self.controls.generateCodeOut.buf)
        self.controls.generateCodeOut:SetText("")
    end)
    self.controls.generateCodeCopy.enabled = function()
        return #self.controls.generateCodeOut.buf > 0
    end
    self.controls.generateCodeNote = new("LabelControl", { "TOPLEFT", self.controls.generateCode, "BOTTOMLEFT" }, 0, 8, 0, 14, "^7Paste the code in chat or Discord.")
    self.controls.importCodeHeader = new("LabelControl", { "TOPLEFT", self.controls.accountName, "BOTTOMLEFT" }, 0, 14, 0, 16, "^73. Import using the code/link from LEB, Last Epoch Tools, or Maxroll")
    self.controls.importCodeHeader.shown = function()
        return self.charImportMode == "GETACCOUNTNAME" and self.activeImportSection ~= 1 and self.activeImportSection ~= 2
    end
    self.controls.importCodeNoteLabel = new("LabelControl", { "TOPLEFT", self.controls.importCodeHeader, "BOTTOMLEFT" }, 0, 4, 720, 14, "^7Note: e.g. ^x4080FFhttps://bytebin.lucko.me/XXXXXX^7, ^x4080FFhttps://www.lastepochtools.com/planner/XXXXXX^7,\n^x4080FFhttps://www.maxroll.gg/last-epoch/planner/XXXXX^7, or ^x4080FF!XXXXX...^7 (offline code)")
    self.controls.importCodeNoteLabel.shown = function()
        return self.charImportMode == "GETACCOUNTNAME" and self.activeImportSection ~= 1 and self.activeImportSection ~= 2
    end

    local importCodeHandle = function(buf)
        self.importCodeSite = nil
        self.importCodeDetail = ""
        self.importCodeXML = nil
        self.importCodeValid = false

        if #buf == 0 then
            self.activeImportSection = nil
            return
        end
        self.activeImportSection = 3

        if not self.build.dbFileName then
            self.controls.importCodeMode.selIndex = 2
        end

        self.importCodeDetail = colorCodes.NEGATIVE .. "Invalid input"
        local urlText = buf:gsub("^[%s?]+", ""):gsub("[%s?]+$", "") -- Quick Trim
        if urlText:match("youtube%.com/redirect%?") or urlText:match("google%.com/url%?") then
            local nested_url = urlText:gsub(".*[?&]q=([^&]+).*", "%1")
            urlText = UrlDecode(nested_url)
        end

        for j = 1, #buildSites.websiteList do
            if urlText:match(buildSites.websiteList[j].matchURL) then
                self.controls.importCodeIn.text = urlText
                self.importCodeValid = true
                self.importCodeDetail = colorCodes.POSITIVE .. "URL is valid (" .. buildSites.websiteList[j].label .. ")"
                self.importCodeSite = j
                if buf ~= urlText then
                    self.controls.importCodeIn:SetText(urlText, false)
                end
                if buildSites.websiteList[j].id == "lastepochtools" then
                    -- Extract XOR key (short lowercase hex) and encrypted data (long base64).
                    -- Variable names are random per-page; match by value shape, not by name.
                    local keyHex
                    for candidate in buf:gmatch("\tvar%s+[%w_]+%s*=%s*'([0-9a-f]+)'") do
                        if #candidate >= 8 and #candidate <= 64 then
                            keyHex = candidate
                            break
                        end
                    end
                    local b64
                    for candidate in buf:gmatch("\tvar%s+[%w_]+%s*=%s*'([A-Za-z0-9+/=]+)'") do
                        if #candidate >= 200 then
                            b64 = candidate
                            break
                        end
                    end
                    if keyHex and b64 then
                        local keyBytes = {}
                        for hex in keyHex:gmatch("..") do
                            table.insert(keyBytes, tonumber(hex, 16))
                        end
                        local keyLen = #keyBytes
                        local csvText = common.base64.decode(b64)
                        local chars = {}
                        local i = 0
                        for numStr in csvText:gmatch("[^,]+") do
                            local byte = tonumber(numStr) or 0
                            local keyByte = keyBytes[(i % keyLen) + 1]
                            table.insert(chars, string.char(bit.bxor(byte, keyByte)))
                            i = i + 1
                        end
                        self.importCodeXML = table.concat(chars)
                    end
                end
                return
            end
        end

        local xmlText
        if buf:sub(1, 1) == "!" then
            -- Base85 format (prefix "!")
            xmlText = Inflate(common.base85.decode(buf:sub(2)))
        else
            -- Base64 URL-safe format (legacy)
            xmlText = Inflate(common.base64.decode(buf:gsub("-", "+"):gsub("_", "/")))
        end
        if not xmlText then
            return
        end
        if launch.devMode and IsKeyDown("SHIFT") then
            Copy(xmlText)
        end
        self.importCodeValid = true
        self.importCodeDetail = colorCodes.POSITIVE .. "Code is valid"
        self.importCodeXML = xmlText
    end

    local importSelectedBuild = function()
        if not self.importCodeValid or self.importCodeFetching then
            return
        end

        if self.controls.importCodeMode.selIndex == 1 then
            main:OpenConfirmPopup("Build Import", colorCodes.WARNING .. "Warning:^7 Importing to the current build will erase ALL existing data for this build.", "Import", function()
                self.build:Shutdown()
                self.build:Init(self.build.dbFileName, self.build.buildName, self.importCodeXML)
                self.build.viewMode = "TREE"
            end)
        else
            self.build:Shutdown()
            self.build:Init(false, "Imported build", self.importCodeXML)
            self.build.viewMode = "TREE"
        end
    end

    self.controls.importCodeIn = new("EditControl", { "TOPLEFT", self.controls.importCodeNoteLabel, "BOTTOMLEFT" }, 0, 6, 328, 20, "", nil, nil, nil, importCodeHandle, nil, nil, true)
    self.controls.importCodeIn.placeholder = "Enter code or link here"
    self.controls.importCodeIn.shown = function()
        return self.charImportMode == "GETACCOUNTNAME" and self.activeImportSection ~= 1 and self.activeImportSection ~= 2
    end
    self.controls.importCodeIn.enterFunc = function()
        if self.importCodeValid then
            self.controls.importCodeGo.onClick()
        end
    end
    self.controls.importCodeState = new("LabelControl", { "LEFT", self.controls.importCodeIn, "RIGHT" }, 8, 0, 0, 16)
    self.controls.importCodeState.label = function()
        return self.importCodeDetail or ""
    end
    self.controls.importCodeState.shown = function()
        return self.charImportMode == "GETACCOUNTNAME" and self.activeImportSection ~= 1 and self.activeImportSection ~= 2
    end
    self.controls.importCodeMode = new("DropDownControl", { "TOPLEFT", self.controls.importCodeIn, "BOTTOMLEFT" }, 0, 4, 160, 20, { "Import to this build", "Import to a new build" })
    self.controls.importCodeMode.shown = function()
        return self.charImportMode == "GETACCOUNTNAME" and self.activeImportSection ~= 1 and self.activeImportSection ~= 2
    end
    self.controls.importCodeMode.enabled = function()
        return self.build.dbFileName and self.importCodeValid
    end
    self.controls.importCodeGo = new("ButtonControl", { "LEFT", self.controls.importCodeMode, "RIGHT" }, 8, 0, 160, 20, "Import", function()
        if self.importCodeSite and not self.importCodeXML then
            local selectedWebsite = buildSites.websiteList[self.importCodeSite]
            if selectedWebsite.id == "maxroll" then
                self:DownloadMaxrollPlannerBuild(self.controls.importCodeIn.buf)
                return
            end
            self.importCodeFetching = true
            buildSites.DownloadBuild(self.controls.importCodeIn.buf, selectedWebsite, function(isSuccess, data)
                self.importCodeFetching = false
                if not isSuccess then
                    self.importCodeDetail = colorCodes.NEGATIVE .. data
                    self.importCodeValid = false
                else
                    importCodeHandle(data)
                    importSelectedBuild()
                end
            end)
            return
        end

        importSelectedBuild()
    end)
    self.controls.importCodeGo.label = function()
        return self.importCodeFetching and "Retrieving paste.." or "Import"
    end
    self.controls.importCodeGo.shown = function()
        return self.charImportMode == "GETACCOUNTNAME" and self.activeImportSection ~= 1 and self.activeImportSection ~= 2
    end
    self.controls.importCodeGo.enabled = function()
        return self.importCodeValid and not self.importCodeFetching
    end
    self.controls.importCodeGo.enterFunc = function()
        if self.importCodeValid then
            self.controls.importCodeGo.onClick()
        end
    end
end)

function ImportTabClass:Load(xml, fileName)
    self.lastRealm = xml.attrib.lastRealm
    self.lastAccountHash = xml.attrib.lastAccountHash
    self.controls.enablePartyExportBuffs.state = xml.attrib.exportParty == "true"
    self.build.partyTab.enableExportBuffs = self.controls.enablePartyExportBuffs.state
    if self.lastAccountHash then
        for accountName in pairs(main.gameAccounts) do
            if common.sha1(accountName) == self.lastAccountHash then
                self.controls.accountName:SetText(accountName)
            end
        end
    end
    self.lastCharacterHash = xml.attrib.lastCharacterHash
end

function ImportTabClass:Save(xml)
    xml.attrib = {
        lastRealm = self.lastRealm,
        lastAccountHash = self.lastAccountHash,
        lastCharacterHash = self.lastCharacterHash,
        exportParty = tostring(self.controls.enablePartyExportBuffs.state),
    }
end

function ImportTabClass:Draw(viewPort, inputEvents)
    self.x = viewPort.x
    self.y = viewPort.y
    self.width = viewPort.width
    self.height = viewPort.height

    self:ProcessControlsInput(inputEvents, viewPort)

    main:DrawBackground(viewPort)

    self:DrawControls(viewPort)
end

function ImportTabClass:DownloadCharacterListOnline()
    self.charImportMode = "DOWNLOADCHARLIST"
    self.charImportStatus = "Retrieving character list..."
    -- Trim Trailing/Leading spaces
    local accountName = self.controls.accountName.buf:gsub('%s+', '')
    launch:DownloadPage("https://planners.maxroll.gg/lastepoch/characters/" .. accountName, function(response, errMsg)
        if errMsg == "Response code: 404" then
            self.charImportStatus = colorCodes.NEGATIVE .. "Account not found. Check the account name and ensure the profile is public on Maxroll."
            self.charImportMode = "GETACCOUNTNAME"
            return
        elseif errMsg then
            self.charImportStatus = colorCodes.NEGATIVE .. "Error retrieving character list, try again (" .. errMsg:gsub("\n", " ") .. ")"
            self.charImportMode = "GETACCOUNTNAME"
            return
        end
        local charList, parseErr = processJson(response.body)
        if parseErr or type(charList) ~= "table" then
            self.charImportStatus = colorCodes.NEGATIVE .. "Error processing character list, try again."
            self.charImportMode = "GETACCOUNTNAME"
            return
        end
        if #charList == 0 then
            self.charImportStatus = colorCodes.NEGATIVE .. "The account has no characters to import."
        else
            self.charImportStatus = "Character list successfully retrieved."
        end
        self.charImportMode = "SELECTCHAR"
        self.controls.source.label = "^7Source: ^x4040FFhttps://planners.maxroll.gg/lastepoch/characters/" .. accountName
        self.controls.source.onClick = function()
            OpenURL("https://planners.maxroll.gg/lastepoch/characters/" .. accountName)
        end
        self.lastAccountHash = common.sha1(accountName)
        main.lastAccountName = accountName
        main.gameAccounts[accountName] = main.gameAccounts[accountName] or { }
        local maxCycle = 0
        for _, char in ipairs(charList) do
            if (char.cycle or 0) > maxCycle then maxCycle = char.cycle end
        end
        local leagueList = { }
        for i, char in ipairs(charList) do
            local classId = char.characterClass
            char.league = (char.cycle or 0) == maxCycle and maxCycle > 0 and "Cycle" or "Legacy"
            char.ascendancy = char.chosenMastery
            char.ascendancyName = self.build.latestTree.classes[classId].ascendancies[char.chosenMastery].name
            char.name = char.characterName
            char.class = self.build.latestTree.classes[classId].name
            if not isValueInArray(leagueList, char.league) then
                t_insert(leagueList, char.league)
            end
        end
        table.sort(leagueList)
        wipeTable(self.controls.charSelectLeague.list)
        for _, league in ipairs(leagueList) do
            t_insert(self.controls.charSelectLeague.list, {
                label = league,
                league = league,
            })
        end
        t_insert(self.controls.charSelectLeague.list, {
            label = "All",
        })
        if self.controls.charSelectLeague.selIndex > #self.controls.charSelectLeague.list then
            self.controls.charSelectLeague.selIndex = 1
        end
        self.lastCharList = charList
        self:BuildCharacterList(self.controls.charSelectLeague:GetSelValue("league"))
        self:SaveAccountHistory()
    end)
end

function ImportTabClass:DownloadCharacterList()
    self.charImportMode = "DOWNLOADCHARLIST"
    self.charImportStatus = "Retrieving character list..."

    local saveFolderSuffix = "\\AppData\\LocalLow\\Eleventh Hour Games\\Last Epoch\\Saves\\"
    local localSaveFolders = {}
    if os.getenv("UserProfile") then
        -- For Windows
        t_insert(localSaveFolders, os.getenv('UserProfile') .. saveFolderSuffix)
    end
    if os.getenv("USER") then
        -- For Linux
        t_insert(localSaveFolders, "/home/" .. os.getenv("USER")
            .. "/.local/share/Steam/steamapps/compatdata/899770/pfx/drive_c/users/steamuser/"
            .. saveFolderSuffix)
    end
    local saves = {}
    for _, localSaveFolder in ipairs(localSaveFolders) do
        local handle = NewFileSearch(localSaveFolder .. "1CHARACTERSLOT_BETA_*")
        while handle do
            local fileName = handle:GetFileName()

            if fileName:sub(-4) ~= ".bak" then
                table.insert(saves, localSaveFolder .. "\\" .. fileName)
            end

            if not handle:NextFile() then
                break
            end
        end
    end

    local charList = {}
    local maxCycle = 0
    for _, save in ipairs(saves) do
        local saveFile = io.open(save, "r")
        local saveFileContent = saveFile:read("*a")
        saveFile:close()
        local ok, charOrErr = pcall(function() return self:ReadJsonSaveData(saveFileContent:sub(6)) end)
        if ok then
            ConPrintf("[OFFLINE] char=%s cycle=%s", tostring(charOrErr.name), tostring(charOrErr.cycle))
            if (charOrErr.cycle or 0) > maxCycle then maxCycle = charOrErr.cycle end
            table.insert(charList, charOrErr)
        else
            ConPrintf("SAVE ERR: %s error=%s", save, tostring(charOrErr))
        end
    end
    for _, char in ipairs(charList) do
        char.league = (char.cycle or 0) == maxCycle and maxCycle > 0 and "Cycle" or "Legacy"
    end

    self.charImportStatus = "Character list successfully retrieved."
    self.charImportMode = "SELECTCHAR"
    local leagueList = { }
    for i, char in ipairs(charList) do
        if not isValueInArray(leagueList, char.league) then
            t_insert(leagueList, char.league)
        end
    end
    table.sort(leagueList)
    wipeTable(self.controls.charSelectLeague.list)
    for _, league in ipairs(leagueList) do
        t_insert(self.controls.charSelectLeague.list, {
            label = league,
            league = league,
        })
    end
    t_insert(self.controls.charSelectLeague.list, {
        label = "All",
    })
    if self.controls.charSelectLeague.selIndex > #self.controls.charSelectLeague.list then
        self.controls.charSelectLeague.selIndex = 1
    end
    self.lastCharList = charList
    self:BuildCharacterList(self.controls.charSelectLeague:GetSelValue("league"))
end

function ImportTabClass:BuildCharacterList(league)
    wipeTable(self.controls.charSelect.list)
    for i, char in ipairs(self.lastCharList) do
        if not league or char.league == league then
            local class = char.ascendancy > 0 and char.ascendancyName or char.class or "?"
            t_insert(self.controls.charSelect.list, {
                label = string.format("%s: Level %d %s in %s", char.name or "?", char.level or 0, class, char.league or "?"),
                char = char,
            })
        end
    end
    table.sort(self.controls.charSelect.list, function(a, b)
        return a.char.name:lower() < b.char.name:lower()
    end)
    self.controls.charSelect.selIndex = 1
    if self.lastCharacterHash then
        for i, char in ipairs(self.controls.charSelect.list) do
            if common.sha1(char.char.name) == self.lastCharacterHash then
                self.controls.charSelect.selIndex = i
                break
            end
        end
    end
end

function ImportTabClass:SaveAccountHistory()
    if not historyList[self.controls.accountName.buf] then
        t_insert(historyList, self.controls.accountName.buf)
        historyList[self.controls.accountName.buf] = true
        self.controls.accountHistory:SelByValue(self.controls.accountName.buf)
        table.sort(historyList, function(a, b)
            return a:lower() < b:lower()
        end)
        self.controls.accountHistory:CheckDroppedWidth(true)
    end
end

function ImportTabClass:DownloadMaxrollPlannerBuild(url)
    self.importCodeFetching = true
    self.importCodeDetail = colorCodes.NORMAL .. "Downloading from maxroll.gg..."

    local plannerCode = url:match("maxroll%.gg/last%-epoch/planner/(%w+)")
    if not plannerCode then
        self.importCodeFetching = false
        self.importCodeDetail = colorCodes.NEGATIVE .. "Could not parse maxroll URL"
        return
    end

    local dataParam = "last-epoch-planner-by-id"
    local apiURL = "https://maxroll.gg/last-epoch/planner/" .. plannerCode .. "?_data=" .. dataParam
    launch:DownloadPage(apiURL, function(response, errMsg)
        self.importCodeFetching = false
        if errMsg then
            self.importCodeDetail = colorCodes.NEGATIVE .. "Download failed: " .. errMsg:gsub("\n", " ")
            return
        end

        local jsonData, parseErr = processJson(response.body)
        if parseErr or type(jsonData) ~= "table" then
            self.importCodeDetail = colorCodes.NEGATIVE .. "Failed to parse maxroll response"
            return
        end

        local profile = jsonData.profile
        if not profile or not profile.data then
            self.importCodeDetail = colorCodes.NEGATIVE .. "No build data in maxroll response"
            return
        end

        local buildData, parseErr2 = processJson(profile.data)
        if parseErr2 or type(buildData) ~= "table" or not buildData.profiles then
            self.importCodeDetail = colorCodes.NEGATIVE .. "Failed to parse maxroll build data"
            return
        end

        local profileData = buildData.profiles[1]
        if not profileData then
            self.importCodeDetail = colorCodes.NEGATIVE .. "No profile found in maxroll build data"
            return
        end

        local classId = profileData["class"] or 0
        if not self.build.latestTree.classes[classId] then
            self.importCodeDetail = colorCodes.NEGATIVE .. "Unknown class: " .. tostring(classId)
            return
        end
        local className = self.build.latestTree.classes[classId].name
        local mastery = profileData.mastery or 0
        local ascendancyData = self.build.latestTree.classes[classId].ascendancies[mastery]
        if not ascendancyData then
            self.importCodeDetail = colorCodes.NEGATIVE .. "Unknown mastery: " .. tostring(mastery)
            return
        end

        local char = {
            name = profile.name or "Maxroll Build",
            level = profileData.level or 1,
            class = className,
            classId = classId,
            ascendancy = mastery,
            ascendancyName = ascendancyData.name,
            league = "Maxroll",
            abilities = {},
            items = {},
            hashes = {},
            _parseErrors = 0,
        }

        -- Build passive hashes from allocation history
        if profileData.passives and profileData.passives.history then
            local nodeCount = {}
            for _, nodeId in ipairs(profileData.passives.history) do
                nodeCount[nodeId] = (nodeCount[nodeId] or 0) + 1
            end
            for nodeId, count in pairs(nodeCount) do
                table.insert(char.hashes, className .. "-" .. nodeId .. "#" .. count)
            end
        end

        -- Build skill hashes from skillTrees
        if profileData.skillTrees then
            local skillList = self.build.latestTree.classes[classId].skills or {}
            for treeIdStr, treeData in pairs(profileData.skillTrees) do
                local treeIdNum = tonumber(treeIdStr)
                if treeIdNum then
                    local skillName
                    for _, skill in ipairs(skillList) do
                        if skill.treeId == treeIdNum then
                            skillName = skill.name
                            break
                        end
                    end
                    if skillName then
                        table.insert(char.abilities, skillName)
                        table.insert(char.hashes, treeIdStr .. "-0#1")
                        if treeData.history then
                            local nodeCount = {}
                            for _, nodeId in ipairs(treeData.history) do
                                nodeCount[nodeId] = (nodeCount[nodeId] or 0) + 1
                            end
                            for nodeId, count in pairs(nodeCount) do
                                if count > 0 then
                                    table.insert(char.hashes, treeIdStr .. "-" .. nodeId .. "#" .. count)
                                end
                            end
                        end
                    end
                end
            end
        end

        self:ImportPassiveTreeAndJewels(char)
        self.importCodeDetail = colorCodes.POSITIVE .. "Maxroll build imported."
    end)
end

function ImportTabClass:DownloadFromMaxroll()
    self.charImportStatus = "Downloading build data from Maxroll..."
    local charSelect = self.controls.charSelect
    local charData = charSelect.list[charSelect.selIndex].char
    local accountName = self.controls.accountName.buf:gsub('%s+', '')
    launch:DownloadPage("https://planners.maxroll.gg/lastepoch/characters/" .. accountName .. "/" .. charData.name, function(response, errMsg)
        self.charImportMode = "SELECTCHAR"
        if errMsg then
            self.charImportStatus = colorCodes.NEGATIVE .. "Error downloading character data, try again (" .. errMsg:gsub("\n", " ") .. ")"
            return
        end
        local ok, charOrErr = pcall(function() return self:ReadJsonSaveData(response.body) end)
        if not ok then
            ConPrintf("[IMPORT-ERR] Failed to parse character data: %s", tostring(charOrErr))
            self.charImportStatus = colorCodes.NEGATIVE .. "Failed to parse character data, try again."
            return
        end
        local lastUpdated = ""
        if charData.lastUpdated then
            lastUpdated = colorCodes.NORMAL .. " Last updated: " .. os.date("%c", charData.lastUpdated)
        end
        charSelect.list[charSelect.selIndex].char = charOrErr
        self.charImportStatus = colorCodes.POSITIVE .. "Build data successfully downloaded." .. lastUpdated
    end)
end

function ImportTabClass:DownloadPassiveTree()
    self.charImportStatus = "Retrieving character passive tree..."
    local charSelect = self.controls.charSelect
    local charData = charSelect.list[charSelect.selIndex].char
    self:ImportPassiveTreeAndJewels(charData)
    self.charImportMode = "GETACCOUNTNAME"
end

function ImportTabClass:ReadJsonSaveData(saveFileContent)
    local saveContent = processJson(saveFileContent)
    if not saveContent or type(saveContent) ~= "table" then
        error("Invalid JSON response")
    end
    local classId = saveContent["characterClass"]
    if not classId or not self.build.latestTree.classes[classId] then
        error("Unknown character class: " .. tostring(classId))
    end
    local className = self.build.latestTree.classes[classId].name
    local chosenMastery = saveContent['chosenMastery'] or 0
    local ascendancyData = self.build.latestTree.classes[classId].ascendancies[chosenMastery]
    if not ascendancyData then
        error("Unknown mastery: " .. tostring(chosenMastery) .. " for class " .. tostring(classId))
    end
    local char = {
        ["name"] = saveContent["characterName"],
        ["level"] = saveContent["level"],
        ["class"] = className,
        ["ascendancy"] = chosenMastery,
        ["ascendancyName"] = ascendancyData.name,
        ["classId"] = classId,
        ["abilities"] = {},
        ["items"] = {},
        ["hashes"] = { },
        ["_parseErrors"] = 0,
    }
    char.cycle = saveContent["cycle"] or 0
    for passiveIdx, passive in pairs(saveContent["savedCharacterTree"]["nodeIDs"]) do
        local nbPoints = saveContent["savedCharacterTree"]["nodePoints"][passiveIdx]
        table.insert(char["hashes"], className .. "-" .. passive .. "#" .. nbPoints)
    end
    for _, skillTree in pairs(saveContent["savedSkillTrees"] or {}) do
        local skillName

        local skillList = self.build.latestTree.classes[classId].skills
        for _, skill in ipairs(skillList) do
            if skill.treeId == skillTree['treeID'] then
               skillName = skill.name
            end
        end

        if skillName then
            table.insert(char["hashes"], skillTree['treeID'] .. "-" .. 0 .. "#1")
            table.insert(char["abilities"], skillName)
            for skillIdx, skill in pairs(skillTree["nodeIDs"]) do
                local nbPoints = skillTree["nodePoints"][skillIdx]
                if nbPoints > 0 then
                    table.insert(char["hashes"], skillTree['treeID'] .. "-" .. skill .. "#" .. nbPoints)
                end
            end
        end
    end
    -- Altar detection: baseTypeID=41 in any slot
    local altarSubTypeNames = {
        [0]="Twisted Altar", [1]="Jagged Altar", [2]="Skyward Altar",
        [3]="Spire Altar", [4]="Carcinised Altar", [5]="Visage Altar",
        [6]="Lunar Altar", [7]="Ocular Altar", [8]="Archair Altar",
        [9]="Impervious Altar", [10]="Prophesied Altar", [11]="Pyramidal Altar",
        [12]="Auric Altar",
    }
    for _, itemData in pairsSortByKey(saveContent["savedItems"]) do
        local d = itemData["data"]
        if d then
            local altarBase = (d[1] == 2) and 2 or 4
            if d[altarBase] == 41 then
                char.altarName = altarSubTypeNames[d[altarBase + 1]]
                break
            end
        end
    end

    for _, itemData in pairsSortByKey(saveContent["savedItems"]) do
        if itemData["containerID"] <= 12 or
                itemData["containerID"] == 29 or
                itemData["containerID"] >= 33 and itemData["containerID"] <= 45 or
                itemData["containerID"] == 123 then
            local item = {
                ["inventoryId"] = itemData["containerID"],
            }
            local d = itemData["data"]
            -- Format version 2 (older seasons) has no seed bytes, so all offsets shift by -2.
            -- Format version 3/5 (current) has a 2-byte seed before baseTypeID.
            local BASE = (d and d[1] == 2) and 2 or 4
            local baseTypeID = d[BASE]
            local subTypeID = d[BASE + 1]
            if itemData["containerID"] == 29 then
                item._idolPosX = itemData["inventoryPosition"]["x"]
                item._idolPosY = itemData["inventoryPosition"]["y"]
            end
            local matchedBase = false
            for itemBaseName, itemBase in pairs(self.build.data.itemBases) do
                if itemBase.baseTypeID == baseTypeID and itemBase.subTypeID == subTypeID then
                    matchedBase = true
                    item.baseName = itemBaseName
                    -- Assign idol slot after base match so we know idol height
                    if itemData["containerID"] == 29 and item._idolPosX then
                        local posX = item._idolPosX
                        local posY = item._idolPosY
                        -- Idol height lookup from base name pattern
                        local idolHeight = 1
                        if itemBaseName:find("Stout") or itemBaseName:find("Adorned") then
                            idolHeight = 2
                        elseif itemBaseName:find("Large") then
                            idolHeight = 3
                        elseif itemBaseName:find("Huge") then
                            idolHeight = 4
                        end
                        -- Game uses y=0 at bottom; anchor is bottom-left of idol.
                        -- UI anchor is top-left. Convert: UI_row = 6 - posY - idolHeight
                        local idolGrid = {
                            { "Idol 21", "Idol 1",  "Idol 2",  "Idol 3",  "Idol 22" }, -- UI row 1 (top)
                            { "Idol 4",  "Idol 5",  "Idol 6",  "Idol 7",  "Idol 8"  }, -- UI row 2
                            { "Idol 9",  "Idol 10", "Idol 23", "Idol 11", "Idol 12" }, -- UI row 3
                            { "Idol 13", "Idol 14", "Idol 15", "Idol 16", "Idol 17" }, -- UI row 4
                            { "Idol 24", "Idol 18", "Idol 19", "Idol 20", "Idol 25" }, -- UI row 5 (bottom)
                        }
                        local uiRow = 6 - posY - idolHeight
                        local row = idolGrid[uiRow]
                        item["inventoryId"] = row and row[posX + 1] or ("Idol " .. (posX + posY * 5))
                        ConPrintf("[IDOL] posX=%d posY=%d height=%d uiRow=%d -> slot=%s base=%s", posX, posY, idolHeight, uiRow, tostring(item["inventoryId"]), itemBaseName)
                        item._idolPosX = nil
                        item._idolPosY = nil
                    end
                    item.base = itemBase
                    item.implicitMods = {}
                    for i, implicit in ipairs(itemBase.implicits or {}) do
                        local range = d[BASE + 3 + i] or 128
                        table.insert(item.implicitMods, "{range: " .. range .. "}" .. implicit)
                    end
                    -- For blessing slots, set the roll fraction from the first implicit roll byte
                    if itemData["containerID"] >= 33 and itemData["containerID"] <= 45 then
                        item.blessingRollFrac = d[BASE + 4] and (d[BASE + 4] / 255.0) or 1.0
                    end
                    local rarity = d[BASE + 2]
                    item["explicitMods"] = {}
                    item["prefixes"] = {}
                    item["suffixes"] = {}
                    if rarity >= 7 and rarity <= 9 then
                        -- 7 = Unique, 8 = Set, 9 = Legendary
                        if rarity == 8 then
                            item["rarity"] = "SET"
                        elseif rarity == 9 then
                            item["rarity"] = "LEGENDARY"
                        else
                            item["rarity"] = "UNIQUE"
                        end
                        -- uniqueID is at BASE+7, BASE+8 (after 3 implicits + 1 flags byte)
                        local uniqueIDIndex = BASE + 7
                        local uniqueID = d[uniqueIDIndex] * 256 + d[uniqueIDIndex + 1]
                        local uniqueBase = self.build.data.uniques[uniqueID]
                        if not uniqueBase then
                            ConPrintf("[ITEM-ERR] Unknown uniqueID=%d cid=%d baseTypeID=%d subTypeID=%d", uniqueID, itemData["containerID"], baseTypeID, subTypeID)
                            char._parseErrors = char._parseErrors + 1
                            break
                        end
                        item["name"] = uniqueBase.name
                        for i, modLine in ipairs(uniqueBase.mods) do
                            if itemLib.hasRange(modLine) then
                                local rollId = uniqueBase.rollIds[i]
                                if rollId then
                                    local range = d[uniqueIDIndex + 2 + rollId]
                                    -- TODO: avoid using crafted
                                    table.insert(item.explicitMods, "{crafted}{range: " .. (range or 0) .. "}".. modLine)
                                else
                                    table.insert(item.explicitMods, "{crafted}".. modLine)
                                end
                            else
                                table.insert(item.explicitMods, "{crafted}".. modLine)
                            end
                        end
                        if rarity == 9 then
                            -- 8 is the maximum amount of unique mod roll bytes
                            local nbAffixesIndex = uniqueIDIndex + 2 + 8
                            local nbMods = d[nbAffixesIndex]
                            for i = 0, nbMods - 1 do
                                local dataId = nbAffixesIndex + 1 + 3 * i
                                -- There are cases where the "nbAffixesIndex" value is wrong, not sure why but
                                -- we should at least prevent a crash when it's higher than expected (could it be lower?)
                                if d[dataId] then
                                    local affixId = d[dataId + 1] + (d[dataId] % 16) * 256
                                    local affixTier = math.floor(d[dataId] / 16)
                                    local modId = affixId .. "_" .. affixTier
                                    local modData = data.itemMods.Item[modId]
                                    local range = d[dataId + 2]
                                    if modData then
                                        if modData.type == "Prefix" then
                                            table.insert(item.prefixes, { ["range"] = range, ["modId"] = modId })
                                        else
                                            table.insert(item.suffixes, { ["range"] = range, ["modId"] = modId })
                                        end
                                    end
                                end
                            end
                        end
                    else
                        local maxTier = 0
                        local affixCount = 0
                        -- Read up to 5 affix slots: 4 regular + 1 sealed affix slot
                        -- Affixes start at BASE+9 (byte0/tierByte), BASE+10 (byte1/idByte)
                        for i = 0, 4 do
                            local dataId = BASE + 10 + i * 3
                            if #d > dataId then
                                local affixId = d[dataId] + (d[dataId - 1] % 16) * 256
                                if affixId and affixId > 0 then
                                    local affixTier = math.floor(d[dataId - 1] / 16)
                                    local modId = affixId .. "_" .. affixTier
                                    local modData = data.itemMods.Item[modId]
                                    local range = d[dataId + 1]

                                    ConPrintf("[AFFIX] base=%s slot=%d affixId=%d tier=%d modId=%s valid=%s", itemBaseName, i, affixId, affixTier, modId, tostring(modData ~= nil))
                                    if modData then
                                        affixCount = affixCount + 1
                                        if affixTier > maxTier then
                                            maxTier = affixTier
                                        end
                                        if modData.type == "Prefix" then
                                            table.insert(item.prefixes, { ["range"] = range, ["modId"] = modId })
                                        else
                                            table.insert(item.suffixes, { ["range"] = range, ["modId"] = modId })
                                        end
                                    end
                                end
                            end
                        end
                        -- Determine rarity: T6+ affix = Exalted, otherwise by affix count
                        -- Tiers are 0-indexed in save data: stored 5 = T6, stored 6 = T7
                        -- Idols max out at 2 affixes (1 prefix + 1 suffix), so 2 = fully affixed
                        local isIdol = itemBaseName:find("Idol") or itemBaseName:find("Altar")
                        if maxTier >= 5 then
                            item["rarity"] = "EXALTED"
                        elseif isIdol then
                            if affixCount >= 2 then
                                item["rarity"] = "RARE"
                            elseif affixCount >= 1 then
                                item["rarity"] = "MAGIC"
                            else
                                item["rarity"] = "NORMAL"
                            end
                        else
                            if affixCount >= 3 then
                                item["rarity"] = "RARE"
                            elseif affixCount >= 1 then
                                item["rarity"] = "MAGIC"
                            else
                                item["rarity"] = "NORMAL"
                            end
                        end
                        ConPrintf("[RARITY] base=%s rarityByte=%d affixCount=%d maxTier=%d idol=%s -> %s", itemBaseName, rarity, affixCount, maxTier, tostring(isIdol), item["rarity"])
                        -- Build generated name: [forename] + baseName + [surname]
                        local forename, surname = "", ""
                        for _, p in ipairs(item.prefixes) do
                            local md = data.itemMods.Item[p.modId]
                            if md and md.affix and md.affix ~= "" then
                                if md.affix:sub(1,3) == "of " then surname = surname ~= "" and surname or md.affix
                                else forename = forename ~= "" and forename or md.affix end
                            end
                        end
                        for _, s in ipairs(item.suffixes) do
                            local md = data.itemMods.Item[s.modId]
                            if md and md.affix and md.affix ~= "" then
                                if md.affix:sub(1,3) == "of " then surname = surname ~= "" and surname or md.affix
                                else forename = forename ~= "" and forename or md.affix end
                            end
                        end
                        item["name"] = (forename ~= "" and forename .. " " or "") .. itemBaseName .. (surname ~= "" and " " .. surname or "")
                    end
                    table.insert(char["items"], item)
                end
            end
            if not matchedBase then
                local tag = (itemData["containerID"] >= 33 and itemData["containerID"] <= 45) and "[BLESS]" or "[ITEM]"
                ConPrintf("%s no base match: cid=%d baseTypeID=%s subTypeID=%s", tag, itemData["containerID"], tostring(baseTypeID), tostring(subTypeID))
                char._parseErrors = char._parseErrors + 1
            end
        end
    end

    return char
end

function ImportTabClass:DownloadItems()
    self.charImportStatus = "Retrieving character items..."
    local charSelect = self.controls.charSelect
    local charData = charSelect.list[charSelect.selIndex].char
    self:ImportItemsAndSkills(charData)
    self.charImportMode = "GETACCOUNTNAME"
end

function ImportTabClass:DownloadFullImport()
    local charSelect = self.controls.charSelect
    local charData = charSelect.list[charSelect.selIndex].char
    self:ImportPassiveTreeAndJewels(charData)
    self:ImportItemsAndSkills(charData)
    self.charImportMode = "GETACCOUNTNAME"
    self.charImportStatus = colorCodes.POSITIVE.."Full import successful."
end

function ImportTabClass:ImportPassiveTreeAndJewels(charData)
    self.build.spec:ImportFromNodeList(charData.classId, charData.ascendancy, charData.abilities, charData.hashes, charData.skill_overrides, latestTreeVersion)
    self.build.spec:AddUndoState()
    self.build.characterLevel = charData.level
    self.build.characterLevelAutoMode = false
    self.build.configTab:UpdateLevel()
    self.build.controls.characterLevel:SetText(charData.level)
    self.build:EstimatePlayerProgress()
    self.build.configTab.input["campaignBonuses"] = true
    self.build.configTab:BuildModList()
    self.build.configTab:UpdateControls()
    self.build.buildFlag = true

    main:SetWindowTitleSubtext(string.format("%s (%s, %s, %s)", self.build.buildName, charData.name, charData.class, charData.league))

    self.charImportStatus = colorCodes.POSITIVE .. "Passive tree successfully imported."
end

function ImportTabClass:ImportItemsAndSkills(charData)
    -- Reset debug.log so it only contains data from the most recent import
    if ResetDebugLog then ResetDebugLog() end
    ConPrintf("[IMPORT] === Character Import Start: %s (level %s) ===", tostring(charData.name), tostring(charData.level))
    -- Use the latest non-empty itemBases and itemMods for ParseRaw compatibility
    local savedItemBases = data.itemBases
    local savedItemMods = data.itemMods
    for i = #treeVersionList, 1, -1 do
        local vd = data.versionData[treeVersionList[i]]
        if vd and next(vd.itemBases) then
            data.itemBases = vd.itemBases
            data.itemMods = vd.itemMods
            break
        end
    end

    -- Build a lookup table: blessingName → {tl, entry, isGrand}
    -- Uses blessingData directly so import works without ConfigTab dropdown controls.
    local blessingLookup = {}
    local blessingData = self.build.itemsTab.blessingData or {}
    for tl, tlData in pairs(blessingData) do
        for _, b in ipairs(tlData.normal or {}) do
            blessingLookup[b.name] = {tl=tl, entry=b, isGrand=false}
        end
        for _, b in ipairs(tlData.grand or {}) do
            blessingLookup[b.name] = {tl=tl, entry=b, isGrand=true}
        end
    end
    self.currentBlessingLookup = blessingLookup

    if self.controls.charImportItemsClearItems.state then
        for _, slot in pairs(self.build.itemsTab.slots) do
            if slot.selItemId ~= 0 and not slot.nodeId then
                self.build.itemsTab:DeleteItem(self.build.itemsTab.items[slot.selItemId])
            end
        end
    end
    if self.controls.charImportUnusedItemsClearItems.state then
        self.build.itemsTab:DeleteUnused()
    end

    -- Altar layout is now auto-detected from the equipped Idol Altar item
    -- via the SetSelItemId wrapper on the Idol Altar slot

    local importOk, importFail, importSkip = 0, 0, 0
    for _, itemData in pairsSortByKey(charData.items) do
        local status = self:ImportItem(itemData)
        if status == "ok" or status == "bless_ok" then
            importOk = importOk + 1
        elseif status == "fail" or status == "bless_fail" then
            importFail = importFail + 1
        else
            importSkip = importSkip + 1
        end
    end

    -- Auto-populate Omen Idol (Fractured) slots from idols on fractured cells
    local itemsTab = self.build.itemsTab
    local altarName = itemsTab.activeAltarLayout
    local altarLayouts = itemsTab.altarLayouts
    if altarName and altarName ~= "Default" and altarLayouts and altarLayouts[altarName] then
        local altarGrid = altarLayouts[altarName].grid
        if altarGrid then
            local idolGridSlots = {
                { "Idol 21", "Idol 1",  "Idol 2",  "Idol 3",  "Idol 22" },
                { "Idol 4",  "Idol 5",  "Idol 6",  "Idol 7",  "Idol 8"  },
                { "Idol 9",  "Idol 10", "Idol 23", "Idol 11", "Idol 12" },
                { "Idol 13", "Idol 14", "Idol 15", "Idol 16", "Idol 17" },
                { "Idol 24", "Idol 18", "Idol 19", "Idol 20", "Idol 25" },
            }
            -- Build cell coverage map: for each cell, find which idol (if any) covers it
            -- A multi-cell idol anchored at (anchorRow, anchorCol) covers multiple cells
            local idolDims = {
                ["Minor Idol"] = {1,1}, ["Small Idol"] = {1,1}, ["Humble Idol"] = {2,1},
                ["Stout Idol"] = {1,2}, ["Grand Idol"] = {3,1}, ["Large Idol"] = {1,3},
                ["Ornate Idol"] = {4,1}, ["Huge Idol"] = {1,4}, ["Adorned Idol"] = {2,2},
            }
            local cellCoveredBy = {} -- cellCoveredBy[row][col] = { slotName, itemId }
            for row = 1, 5 do
                cellCoveredBy[row] = {}
            end
            for row = 1, 5 do
                for col = 1, 5 do
                    local slotName = idolGridSlots[row][col]
                    local slot = itemsTab.slots[slotName]
                    if slot and slot.selItemId and slot.selItemId ~= 0 then
                        local item = itemsTab.items[slot.selItemId]
                        local dims = item and idolDims[item.type] or {1, 1}
                        for dr = 0, dims[2] - 1 do
                            for dc = 0, dims[1] - 1 do
                                local cr, cc = row + dr, col + dc
                                if cr <= 5 and cc <= 5 and not cellCoveredBy[cr][cc] then
                                    cellCoveredBy[cr][cc] = { slotName = slotName, itemId = slot.selItemId }
                                end
                            end
                        end
                    end
                end
            end
            -- Collect idols covering fractured cells, deduplicated, sorted by slot number
            local fracturedIdols = {}
            local seen = {}
            for row = 1, 5 do
                for col = 1, 5 do
                    if altarGrid[row] and altarGrid[row][col] == 2 and cellCoveredBy[row][col] then
                        local info = cellCoveredBy[row][col]
                        if not seen[info.itemId] then
                            seen[info.itemId] = true
                            local slotNum = tonumber(info.slotName:match("%d+"))
                            table.insert(fracturedIdols, { slotNum = slotNum, itemId = info.itemId })
                        end
                    end
                end
            end
            table.sort(fracturedIdols, function(a, b) return a.slotNum < b.slotNum end)
            for i, fi in ipairs(fracturedIdols) do
                local omenSlot = itemsTab.slots["Omen Idol " .. i]
                if omenSlot then
                    omenSlot:SetSelItemId(fi.itemId)
                end
            end
        end
    end

    -- Restore original data pointers
    data.itemBases = savedItemBases
    data.itemMods = savedItemMods

    self.build.itemsTab:PopulateSlots()
    self.build.itemsTab:AddUndoState()
    self.build.characterLevel = charData.level
    self.build.configTab:UpdateLevel()
    self.build.controls.characterLevel:SetText(charData.level)
    self.build.buildFlag = true


    -- Guess main skill if there is no skill included in full DPS
    local anySkillIncludedInFullDPS = false
    for _, socketGroup in pairs(self.build.skillsTab.socketGroupList) do
        if socketGroup.includeInFullDPS then
            anySkillIncludedInFullDPS = true
            break
        end
    end
    if not anySkillIncludedInFullDPS then
        local mainSocketGroup = self:GuessMainSocketGroup()
        if mainSocketGroup then
            self.build.calcsTab.input.skill_number = mainSocketGroup
            self.build.mainSocketGroup = mainSocketGroup
            self.build.skillsTab.socketGroupList[mainSocketGroup].includeInFullDPS = true
        end
    end

    -- Log equipped blessings summary
    ConPrintf("[IMPORT] === Blessing Summary ===")
    local blessingData = self.build.itemsTab.blessingData or {}
    local slots = self.build.itemsTab.slots
    local items = self.build.itemsTab.items
    for tl, _ in pairs(blessingData) do
        local slot = slots[tl]
        local hasBlessing = slot and slot.selItemId and slot.selItemId < 0
        if hasBlessing then
            local item = items[slot.selItemId]
            ConPrintf("[IMPORT]   %-30s -> %s", tl, item and item.name or "(unknown)")
        end
    end
    ConPrintf("[IMPORT] === Import Summary ===")
    ConPrintf("[IMPORT]   Parse errors (no base/unknown unique): %d", charData._parseErrors or 0)
    ConPrintf("[IMPORT]   Items imported OK:  %d", importOk)
    ConPrintf("[IMPORT]   Items failed:       %d", importFail)
    ConPrintf("[IMPORT]   Items skipped:      %d", importSkip)
    if (charData._parseErrors or 0) > 0 or importFail > 0 then
        ConPrintf("[IMPORT]   !! %d issue(s) detected - check [ITEM-ERR]/[BLESS ERR] lines above", (charData._parseErrors or 0) + importFail)
    end
    ConPrintf("[IMPORT] === Import End ===")

    self.charImportStatus = colorCodes.POSITIVE .. "Items and skills successfully imported."
    return charData -- For the wrapper
end

local slotMap = { [4] = "Weapon 1", [5] = "Weapon 2", [2] = "Helmet", [3] = "Body Armor", [6] = "Gloves", [8] = "Boots", [11] = "Amulet", [9] = "Ring 1", [10] = "Ring 2", [7] = "Belt", [12] = "Relic" }

for i = 1, 25 do
    slotMap["Idol " .. i] = "Idol " .. i
end

slotMap[33] = "Fall of the Outcasts"
slotMap[34] = "The Stolen Lance"
slotMap[35] = "The Black Sun"
slotMap[36] = "Blood, Frost, and Death"
slotMap[37] = "Ending the Storm"
slotMap[38] = "Fall of the Empire"
slotMap[39] = "Reign of Dragons"
-- cid=40,41,42 are unused/unknown in observed save files
slotMap[43] = "The Last Ruin"
slotMap[44] = "The Age of Winter"
slotMap[45] = "Spirits of Fire"
slotMap[123] = "Idol Altar"


function ImportTabClass:ImportItem(itemData, slotName)
    if not slotName then
        slotName = slotMap[itemData.inventoryId]
    end

    -- Blessing timeline slots are handled directly via UpdateBlessingSlot.
    if slotName and self.build.itemsTab.blessingData and self.build.itemsTab.blessingData[slotName] then
        local blessingName = itemData.name or ""
        local info = self.currentBlessingLookup and self.currentBlessingLookup[blessingName]
        if info then
            local rollFrac = itemData.blessingRollFrac or 1.0
            ConPrintf("[BLESS] OK  cid=%-3d slot=%-30s name=%s  roll=%.3f", itemData.inventoryId, slotName, blessingName, rollFrac)
            self.build.itemsTab:UpdateBlessingSlot(slotName, info.entry, rollFrac)
            return "bless_ok"
        else
            ConPrintf("[BLESS] ERR cid=%-3d slot=%-30s name=%s  (not in blessingLookup)", itemData.inventoryId, slotName, tostring(blessingName))
            return "bless_fail"
        end
    end

    local item = self:BuildItem(itemData)

    if not item or not item.base then
        ConPrintf("[ITEM-ERR] BuildItem returned nil: cid=%s inventoryId=%s", tostring(itemData.inventoryId), tostring(itemData.inventoryId))
        return "fail"
    end

    -- Add and equip the new item
    ConPrintf("%s", item.raw)
    local repIndex, repItem
    if itemData.id ~= nil then
        for index, existingItem in pairs(self.build.itemsTab.items) do
            if existingItem.uniqueID == itemData.id then
                repIndex = index
                repItem = existingItem
                break
            end
        end
    end
    if repIndex then
        -- Item already exists in the build, overwrite it
        item.id = repItem.id
        self.build.itemsTab.items[item.id] = item
        item:BuildModList()
    else
        self.build.itemsTab:AddItem(item, true)
    end
    if slotName and self.build.itemsTab.slots[slotName] then
        self.build.itemsTab.slots[slotName]:SetSelItemId(item.id)
        return "ok"
    else
        if not slotName then
            ConPrintf("[ITEM] no slot mapping: inventoryId=%s name=%s", tostring(itemData.inventoryId), tostring(item.title or item.baseName))
        end
        return "skip"
    end
end

function ImportTabClass:BuildItem(itemData)
    local item = new("Item")

    -- Determine rarity, display name and base type of the item
    item.rarity = itemData.rarity
    if #itemData.name > 0 then
        item.title = itemData.name
        item.baseName = itemData.baseName
        item.base = itemData.base
        if item.base then
            item.type = item.base.type
        else
            ConPrintf("Unrecognised base in imported item: %s", item.baseName)
        end
    end
    if not item.base or not item.rarity then
        return
    end

    -- Import item data
    item.uniqueID = itemData.inventoryId
    itemData.ilvl = 0
    if itemData.ilvl > 0 then
        item.itemLevel = itemData.ilvl
    end
    if item.base.weapon or item.base.armour or item.base.flask then
        item.quality = 0
    end
    if itemData.properties then
        for _, property in pairs(itemData.properties) do
            if property.name == "Quality" then
                item.quality = tonumber(property.values[1][1]:match("%d+"))
            elseif property.name == "Limited to" then
                item.limit = tonumber(property.values[1][1])
            end
            if property.name == "Ward" or property.name == "Armour" or property.name == "Evasion Rating" then
                item.armourData = item.armourData or { }
                for _, value in ipairs(property.values) do
                    item.armourData[property.name:gsub(" Rating", ""):gsub(" ", "")] = (item.armourData[property.name:gsub(" Rating", ""):gsub(" ", "")] or 0) + tonumber(value[1])
                end
            end
        end
    end
    item.split = itemData.split
    item.mirrored = itemData.mirrored
    item.corrupted = itemData.corrupted
    item.fractured = itemData.fractured
    item.synthesised = itemData.synthesised
    if itemData.requirements and (not itemData.socketedItems or not itemData.socketedItems[1]) then
        -- Requirements cannot be trusted if there are socketed gems, as they may override the item's natural requirements
        item.requirements = { }
        for _, req in ipairs(itemData.requirements) do
            if req.name == "Level" then
                item.requirements.level = req.values[1][1]
            elseif req.name == "Class:" then
                item.classRestriction = req.values[1][1]
            end
        end
    end
    item.enchantModLines = { }
    item.classRequirementModLines = { }
    item.implicitModLines = { }
    item.explicitModLines = { }
    if itemData.implicitMods then
        for _, line in ipairs(itemData.implicitMods) do
            for line in line:gmatch("[^\n]+") do
                t_insert(item.implicitModLines, { line = line})
            end
        end
    end
    if itemData.explicitMods then
        for _, line in ipairs(itemData.explicitMods) do
            for line in line:gmatch("[^\n]+") do
                t_insert(item.explicitModLines, { line = line })
            end
        end
    end
    item.prefixes = itemData.prefixes;
    item.suffixes = itemData.suffixes;
    item.crafted = true

    local rarityBefore = item.rarity
    item:BuildAndParseRaw()
    -- Craft the item since we only added the prefixes and suffixes and not their mod lines
    item:Craft()
    ConPrintf("[BUILDITEM] name=%s rarity: %s -> %s (after BuildAndParseRaw+Craft)", tostring(item.title or item.baseName), tostring(rarityBefore), tostring(item.rarity))

    return item
end

-- Return the index of the group with the most gems
function ImportTabClass:GuessMainSocketGroup()
    local bestDps = 0
    local bestSocketGroup = nil
    for i, socketGroup in pairs(self.build.skillsTab.socketGroupList) do
        self.build.mainSocketGroup = i
        socketGroup.includeInFullDPS = true
        local mainOutput = self.build.calcsTab.calcs.buildOutput(self.build, "MAIN").player.output
        socketGroup.includeInFullDPS = false
        local dps = mainOutput.FullDPS
        if dps > bestDps then
            bestDps = dps
            bestSocketGroup = i
        end
    end
    return bestSocketGroup
end

function HexToChar(x)
    return string.char(tonumber(x, 16))
end

function UrlDecode(url)
    if url == nil then
        return
    end
    url = url:gsub("+", " ")
    url = url:gsub("%%(%x%x)", HexToChar)
    return url
end