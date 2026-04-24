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

local dkjson = require "dkjson"

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
    self.controls.charImportStatusLabel = new("LabelControl", { "TOPLEFT", self.controls.sectionCharImport, "TOPLEFT" }, 6, 14, 400, 16, function()
        return "^7Character import status: " .. self.charImportStatus
    end)
    self.controls.charImportStatusLabel.shown = function()
        return self.charImportStatus ~= "Idle"
    end

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
    self.controls.generateCode = new("ButtonControl", { "TOPLEFT", self.controls.generateCodeByLink, "BOTTOMLEFT" }, 0, 8, 150, 20, "Generate Offline Code", function()
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
    self.controls.importCodeHeader = new("LabelControl", { "TOPLEFT", self.controls.sectionCharImport, "TOPLEFT" }, 6, 152, 0, 16, "^73. Import using the code/link from LEB, Last Epoch Tools, or Maxroll")
    self.controls.importCodeHeader.shown = function()
        return self.charImportMode == "GETACCOUNTNAME" and self.activeImportSection ~= 1 and self.activeImportSection ~= 2
    end
    self.controls.importCodeNoteLabel = new("LabelControl", { "TOPLEFT", self.controls.importCodeHeader, "BOTTOMLEFT" }, 0, 4, 720, 14, "^7Note: e.g. ^x4080FFhttps://bytebin.lucko.me/XXXXXX^7,\n^x4080FFhttps://www.maxroll.gg/last-epoch/planner/XXXXX^7, or ^x4080FF!XXXXX...^7 (offline code)")
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

    self.controls.importCodeIn = new("EditControl", { "TOPLEFT", self.controls.importCodeNoteLabel, "BOTTOMLEFT" }, 0, 22, 328, 20, "", nil, nil, nil, importCodeHandle, nil, nil, true)
    self.controls.importCodeIn.placeholder = "Enter Code or Link"
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
            if selectedWebsite.id == "lastepochtools" then
                self:DownloadLEToolsPlannerBuild(self.controls.importCodeIn.buf)
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
                    if not self.importCodeXML then
                        if data:find("Just a moment", 1, true) or data:find("Enable JavaScript and cookies", 1, true) then
                            self.importCodeDetail = colorCodes.NEGATIVE .. "Import failed: site requires browser authentication (Cloudflare)"
                        elseif self.importCodeDetail == "" or not self.importCodeValid then
                            self.importCodeDetail = colorCodes.NEGATIVE .. "Import failed: could not extract build data from page"
                        end
                        self.importCodeValid = false
                        return
                    end
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
    -- Close button: clears the code/link input and restores sections 1 & 2.
    -- Without this the user can't get back to the realm download flow once
    -- anything has been typed into the code field.
    self.controls.importCodeClose = new("ButtonControl", { "LEFT", self.controls.importCodeGo, "RIGHT" }, 8, 0, 60, 20, "Close", function()
        self.controls.importCodeIn:SetText("", true)
        self.importCodeSite = nil
        self.importCodeDetail = ""
        self.importCodeXML = nil
        self.importCodeValid = false
        self.activeImportSection = nil
    end)
    self.controls.importCodeClose.shown = function()
        return self.charImportMode == "GETACCOUNTNAME" and self.activeImportSection ~= 1 and self.activeImportSection ~= 2
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

        local jsonData, _, parseErr = dkjson.decode(response.body, 1, false)
        if parseErr or type(jsonData) ~= "table" then
            self.importCodeDetail = colorCodes.NEGATIVE .. "Failed to parse maxroll response"
            return
        end

        local profile = jsonData.profile
        if not profile or not profile.data then
            self.importCodeDetail = colorCodes.NEGATIVE .. "No build data in maxroll response"
            return
        end

        local buildData, _, parseErr2 = dkjson.decode(profile.data, 1, false)
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
        -- skillTrees may be an array [{treeID, slot, history}] or a dict {treeId: {slot, history}}
        if profileData.skillTrees then
            local skillTreeList = {}
            if type(profileData.skillTrees[1]) == "table" then
                -- Array format: elements have treeID/treeId field
                for i, treeData in ipairs(profileData.skillTrees) do
                    local treeId = treeData.treeID or treeData.treeId
                    local slot = treeData.slot or treeData.slotIndex or (i - 1)
                    if treeId then
                        table.insert(skillTreeList, { treeId = tostring(treeId), treeData = treeData, slot = slot })
                    end
                end
            else
                -- Dict format: key is treeId string
                for treeId, treeData in pairs(profileData.skillTrees) do
                    local slot = type(treeData) == "table" and (treeData.slot or treeData.slotIndex or 99) or 99
                    table.insert(skillTreeList, { treeId = tostring(treeId), treeData = treeData, slot = slot })
                end
            end
            table.sort(skillTreeList, function(a, b) return a.slot < b.slot end)

            for _, entry in ipairs(skillTreeList) do
                local treeIdStr = entry.treeId
                local treeData = entry.treeData
                local skillName
                for _, class in pairs(self.build.latestTree.classes) do
                    for _, skill in ipairs(class.skills or {}) do
                        if skill.treeId == treeIdStr then
                            skillName = skill.name
                            break
                        end
                    end
                    if skillName then break end
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
                else
                    ConPrintf("[IMPORT-SKILL] No match for Maxroll treeId: %s", tostring(treeIdStr))
                end
            end
        end

        self:BuildItemsFromMaxroll(buildData, profileData, char)
        self:ImportPassiveTreeAndJewels(char)
        self:ImportItemsAndSkills(char)
        self:ImportBlessingsFromMaxroll(profileData)
        self.importCodeDetail = colorCodes.POSITIVE .. "Maxroll build imported."
    end)
end

function ImportTabClass:DownloadLEToolsPlannerBuild(url)
    self.importCodeFetching = true
    self.importCodeDetail = colorCodes.NORMAL .. "Downloading from lastepochtools.com..."

    local buildId = url:match("lastepochtools%.com/planner/([%w_%-]+)")
    if not buildId then
        self.importCodeFetching = false
        self.importCodeDetail = colorCodes.NEGATIVE .. "Could not parse LETools URL"
        return
    end

    -- Cloudflare on LETools rejects the default LEB UA; pretend to be a browser.
    local browserUA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36"
    local plannerURL = "https://www.lastepochtools.com/planner/" .. buildId

    launch:DownloadPage(plannerURL, function(response, errMsg)
        if errMsg then
            self.importCodeFetching = false
            self.importCodeDetail = colorCodes.NEGATIVE .. "Download failed: " .. errMsg:gsub("\n", " ")
            return
        end
        local token = response.body:match("var%s+[%w_]+%s*=%s*'([0-9a-f]+)'")
        if not token or #token < 16 then
            self.importCodeFetching = false
            self.importCodeDetail = colorCodes.NEGATIVE .. "Could not extract token from LETools page"
            return
        end
        local apiURL = "https://www.lastepochtools.com/api/internal/planner_data/" .. token
        launch:DownloadPage(apiURL, function(apiResponse, apiErr)
            self.importCodeFetching = false
            if apiErr then
                self.importCodeDetail = colorCodes.NEGATIVE .. "API fetch failed: " .. apiErr:gsub("\n", " ")
                return
            end
            -- DEBUG: dump raw LETools API response for affix tier inspection.
            -- Use same path-resolution as debug.log (worktree/repo root if manifest.xml
            -- is one level up, otherwise current directory).
            local _dumpPath = (io.open("../manifest.xml", "r") and "../letools_raw.json") or "letools_raw.json"
            local _dumpF = io.open(_dumpPath, "w")
            if _dumpF then
                _dumpF:write(apiResponse.body)
                _dumpF:close()
                ConPrintf("[LETOOLS-DUMP] wrote %d bytes to %s", #apiResponse.body, _dumpPath)
            else
                ConPrintf("[LETOOLS-DUMP] failed to open %s", _dumpPath)
            end
            local jsonData, _, parseErr = dkjson.decode(apiResponse.body, 1, false)
            if parseErr or type(jsonData) ~= "table" then
                self.importCodeDetail = colorCodes.NEGATIVE .. "Failed to parse LETools response"
                return
            end
            local data = jsonData.data
            if type(data) ~= "table" then
                self.importCodeDetail = colorCodes.NEGATIVE .. "No data field in LETools response"
                return
            end
            local char = self:BuildCharFromLETools(jsonData, data, buildId)
            if not char then return end
            self:BuildItemsFromLETools(data, char)
            self:ImportPassiveTreeAndJewels(char)
            self:ImportItemsAndSkills(char)
            self:ImportBlessingsFromLETools(data)
            -- LETools' planner UI always displays stats with both quest
            -- rewards included (confirmed via "Quest Reward: +2 Dexterity"
            -- breakdown label on 2026-04-22). The API JSON itself carries
            -- no quest flag, so auto-enable both to match LETools numbers.
            self.build.configTab.input.questApophisMajasa = true
            self.build.configTab.input.questTempleOfEterra = true
            self.build.configTab:BuildModList()
            self.build.configTab:UpdateControls()
            self.build.buildFlag = true
            local msg = "LETools build imported."
            if char._parseErrors and char._parseErrors > 0 then
                msg = msg .. " (" .. char._parseErrors .. " items skipped)"
            end
            self.importCodeDetail = colorCodes.POSITIVE .. msg
        end, { header = "User-Agent: " .. browserUA })
    end, { header = "User-Agent: " .. browserUA })
end

function ImportTabClass:BuildCharFromLETools(jsonData, data, buildId)
    local bio = data.bio or {}
    local classId = bio.characterClass or jsonData["class"] or 0
    local mastery = bio.chosenMastery or jsonData.mastery or 0
    local level = bio.level or jsonData.level or 1

    if not self.build.latestTree.classes[classId] then
        self.importCodeDetail = colorCodes.NEGATIVE .. "Unknown class: " .. tostring(classId)
        return nil
    end
    local className = self.build.latestTree.classes[classId].name
    local ascendancyData = self.build.latestTree.classes[classId].ascendancies[mastery]
    if not ascendancyData then
        self.importCodeDetail = colorCodes.NEGATIVE .. "Unknown mastery: " .. tostring(mastery)
        return nil
    end

    local char = {
        name = "LETools " .. buildId,
        level = level,
        class = className,
        classId = classId,
        ascendancy = mastery,
        ascendancyName = ascendancyData.name,
        league = "LETools",
        abilities = {},
        items = {},
        hashes = {},
        _parseErrors = 0,
    }

    -- Passive hashes from charTree.selected (dict: nodeId string -> points)
    local charTree = data.charTree
    if type(charTree) == "table" and type(charTree.selected) == "table" then
        for nodeId, points in pairs(charTree.selected) do
            if type(points) == "number" and points > 0 then
                table.insert(char.hashes, className .. "-" .. nodeId .. "#" .. points)
            end
        end
    end

    -- Skill hashes from skillTrees array (each entry: {treeID, selected, slotNumber, level})
    if type(data.skillTrees) == "table" then
        local entries = {}
        for i, tree in ipairs(data.skillTrees) do
            local treeId = tree.treeID or tree.treeId
            local slot = tree.slotNumber or tree.slot or (i - 1)
            if treeId then
                table.insert(entries, { treeId = tostring(treeId), treeData = tree, slot = slot })
            end
        end
        table.sort(entries, function(a, b) return a.slot < b.slot end)

        for _, entry in ipairs(entries) do
            local treeIdStr = entry.treeId
            local treeData = entry.treeData
            local skillName
            for _, class in pairs(self.build.latestTree.classes) do
                for _, skill in ipairs(class.skills or {}) do
                    if skill.treeId == treeIdStr then
                        skillName = skill.name
                        break
                    end
                end
                if skillName then break end
            end
            if skillName then
                table.insert(char.abilities, skillName)
                table.insert(char.hashes, treeIdStr .. "-0#1")
                if type(treeData.selected) == "table" then
                    for nodeId, points in pairs(treeData.selected) do
                        if type(points) == "number" and points > 0 then
                            table.insert(char.hashes, treeIdStr .. "-" .. nodeId .. "#" .. points)
                        end
                    end
                end
            else
                ConPrintf("[IMPORT-SKILL] No match for LETools treeId: %s", tostring(treeIdStr))
            end
        end
    end

    return char
end

-- Lazy-loaded LETools id -> {b,s,u?,lt?} and affix-id-string -> affixId-int maps
function ImportTabClass:LoadLEToolsMaps()
    if self._letoolsItemMap and self._letoolsAffixMap then
        return self._letoolsItemMap, self._letoolsAffixMap
    end
    local function readJson(path)
        local f = io.open(path, "r")
        if not f then return nil end
        local body = f:read("*a"); f:close()
        local t = dkjson.decode(body, 1, false)
        return t
    end
    local base = "Data/LEToolsImport/"
    self._letoolsItemMap  = readJson(base .. "letools_item_map.json") or {}
    self._letoolsAffixMap = readJson(base .. "letools_affix_map.json") or {}
    return self._letoolsItemMap, self._letoolsAffixMap
end

-- Convert one LETools equipment/idol item into a Maxroll-shaped item so the
-- existing BuildItemsFromMaxroll / parseItem pipeline can consume it unchanged.
function ImportTabClass:ConvertLEToolsItem(letoolsItem, itemMap, affixMap)
    if type(letoolsItem) ~= "table" or not letoolsItem.id then return nil end
    local entry = itemMap[letoolsItem.id]
    if not entry then
        return nil
    end
    local subType
    if type(entry.s) == "table" then
        subType = entry.s[1]
    else
        subType = entry.s
    end
    local mx = {
        itemType = entry.b,
        subType  = subType,
        corrupted = false,
        implicits = letoolsItem.ir or {},
        affixes = {},
    }
    if entry.u and entry.u > 0 then
        mx.uniqueID    = entry.u
        mx.uniqueRolls = letoolsItem.ur or {}
    end
    local function pushAffix(a, kind)
        if type(a) ~= "table" or a.id == nil then return end
        local affixInt = affixMap[a.id]
        if affixInt ~= nil then
            -- LETools tiers are user-facing 1-indexed (T1..T7); LEB
            -- ModItem keys and save-format tiers are 0-indexed.
            local tier0 = (a.tier or 1) - 1
            if tier0 < 0 then tier0 = 0 end
            ConPrintf("[LETOOLS-AFFIX] base=" .. tostring(entry.b)
                .. " kind=" .. tostring(kind)
                .. " extId=" .. tostring(a.id)
                .. " affixInt=" .. tostring(affixInt)
                .. " rawTier=" .. tostring(a.tier)
                .. " tier0=" .. tostring(tier0)
                .. " roll=" .. tostring(a.r))
            t_insert(mx.affixes, { id = affixInt, tier = tier0, roll = a.r or 0 })
        end
    end
    if type(letoolsItem.affixes) == "table" then
        for _, a in ipairs(letoolsItem.affixes) do pushAffix(a, "normal") end
    end
    -- Extra affix slots returned as standalone fields rather than in affixes[]
    pushAffix(letoolsItem.sealedAffix, "sealed")
    pushAffix(letoolsItem.primordialAffix, "primordial")
    pushAffix(letoolsItem.corruptedAffix, "corrupted")
    return mx
end

-- Populate char.items from LETools data.equipment + data.idols by reshaping
-- the entries into Maxroll format and delegating to BuildItemsFromMaxroll.
function ImportTabClass:BuildItemsFromLETools(data, char)
    local itemMap, affixMap = self:LoadLEToolsMaps()
    local letoolsSlotToMaxroll = {
        head = "head", chest = "body", weapon1 = "weapon", weapon2 = "offhand",
        hands = "hands", waist = "waist", feet = "feet",
        ring1 = "finger1", ring2 = "finger2", amulet = "neck",
        relic = "relic", idol_altar = "altar",
    }
    local profileData = { items = {}, idols = {} }
    -- Prefill idol grid so ipairs in BuildItemsFromMaxroll walks all 25 slots.
    for i = 1, 25 do profileData.idols[i] = false end
    if type(data.equipment) == "table" then
        for slotKey, letoolsItem in pairs(data.equipment) do
            local mxKey = letoolsSlotToMaxroll[slotKey]
            if mxKey then
                local mx = self:ConvertLEToolsItem(letoolsItem, itemMap, affixMap)
                if mx then profileData.items[mxKey] = mx end
            end
        end
    end
    -- Idols: LETools provides x,y (1-indexed, top-left origin; observed
    -- range 1..5 on each axis). Maxroll expects a 25-slot array in row-major
    -- order with idolGridSlots[i] giving the slot name.
    if type(data.idols) == "table" then
        for _, idol in ipairs(data.idols) do
            if type(idol) == "table" and idol.id and type(idol.x) == "number" and type(idol.y) == "number" then
                local idx = (idol.y - 1) * 5 + idol.x
                if idx >= 1 and idx <= 25 then
                    local mx = self:ConvertLEToolsItem(idol, itemMap, affixMap)
                    if mx then profileData.idols[idx] = mx end
                end
            end
        end
    end
    self:BuildItemsFromMaxroll({}, profileData, char)
end

-- Apply LETools blessings via the shared itemsTab.UpdateBlessingSlot path.
function ImportTabClass:ImportBlessingsFromLETools(data)
    local blessings = data.blessings
    if type(blessings) ~= "table" then return end
    local itemMap = self:LoadLEToolsMaps()
    for _, bl in pairs(blessings) do
        if type(bl) == "table" and bl.id then
            local entry = itemMap[bl.id]
            if entry and entry.b == 34 then
                local subType = type(entry.s) == "table" and entry.s[1] or entry.s
                local blessingName
                for name, base in pairs(self.build.data.itemBases) do
                    if base.baseTypeID == 34 and base.subTypeID == subType then
                        blessingName = name; break
                    end
                end
                if blessingName and self.currentBlessingLookup then
                    local info = self.currentBlessingLookup[blessingName]
                    if info then
                        local ir = bl.ir or {}
                        local roll = ir[1] or 255
                        local rollFrac = roll / 255.0
                        self.build.itemsTab:UpdateBlessingSlot(info.tl, info.entry, rollFrac)
                    end
                end
            end
        end
    end
end

function ImportTabClass:BuildItemsFromMaxroll(buildData, profileData, char)
    -- buildData.items is the shared item dictionary keyed by numeric string ("20", "21", ...)
    -- profileData.items slots may contain inline item objects OR numeric references into this dict
    local sharedItems = type(buildData.items) == "table" and buildData.items or {}

    local maxrollSlotToInventoryId = {
        weapon = 4, offhand = 5, head = 2, body = 3, hands = 6, feet = 8,
        neck = 11, finger1 = 9, finger2 = 10, waist = 7, relic = 12,
    }
    -- 5x5 idol grid in row-major order; index i (1-based) → slot name
    local idolGridSlots = {
        "Idol 21","Idol 1","Idol 2","Idol 3","Idol 22",
        "Idol 4","Idol 5","Idol 6","Idol 7","Idol 8",
        "Idol 9","Idol 10","Idol 23","Idol 11","Idol 12",
        "Idol 13","Idol 14","Idol 15","Idol 16","Idol 17",
        "Idol 24","Idol 18","Idol 19","Idol 20","Idol 25",
    }

    local function parseItem(maxrollItem, inventoryId)
        if not maxrollItem or not maxrollItem.itemType then return nil end
        local baseTypeID = maxrollItem.itemType
        local subTypeID  = maxrollItem.subType
        local itemBaseName, itemBase
        for name, base in pairs(self.build.data.itemBases) do
            if base.baseTypeID == baseTypeID and base.subTypeID == subTypeID then
                itemBaseName = name
                itemBase = base
                break
            end
        end
        if not itemBase then
            char._parseErrors = char._parseErrors + 1
            return nil
        end

        local item = {
            inventoryId = inventoryId,
            baseName    = itemBaseName,
            base        = itemBase,
            corrupted   = maxrollItem.corrupted or false,
            implicitMods = {},
            explicitMods = {},
            prefixes     = {},
            suffixes     = {},
        }

        -- Implicits
        for i, implicit in ipairs(itemBase.implicits or {}) do
            local range = (type(maxrollItem.implicits) == "table" and maxrollItem.implicits[i]) or 128
            table.insert(item.implicitMods, "{range: " .. range .. "}" .. implicit)
        end

        local uniqueID = maxrollItem.uniqueID
        if uniqueID and uniqueID > 0 then
            -- Unique or Legendary
            local uniqueBase = self.build.data.uniques[uniqueID]
            if not uniqueBase then
                char._parseErrors = char._parseErrors + 1
                return nil
            end
            item.name = uniqueBase.name
            local uniqueRolls = type(maxrollItem.uniqueRolls) == "table" and maxrollItem.uniqueRolls or {}
            for i, modLine in ipairs(uniqueBase.mods) do
                if itemLib.hasRange(modLine) then
                    local rollId = uniqueBase.rollIds[i]
                    if rollId then
                        local range = uniqueRolls[rollId + 1] or 0
                        table.insert(item.explicitMods, "{crafted}{range: " .. range .. "}" .. modLine)
                    else
                        table.insert(item.explicitMods, "{crafted}" .. modLine)
                    end
                else
                    table.insert(item.explicitMods, "{crafted}" .. modLine)
                end
            end
            -- Legendary: unique base + extra forged affixes
            local legendAffixes = type(maxrollItem.affixes) == "table" and maxrollItem.affixes or {}
            if #legendAffixes > 0 then
                item.rarity = "LEGENDARY"
                for _, affix in ipairs(legendAffixes) do
                    local modId   = affix.id .. "_" .. affix.tier
                    local modData = data.itemMods.Item[modId]
                    if modData then
                        if modData.type == "Prefix" then
                            table.insert(item.prefixes, { range = affix.roll, modId = modId })
                        else
                            table.insert(item.suffixes, { range = affix.roll, modId = modId })
                        end
                    end
                end
            else
                item.rarity = "UNIQUE"
            end
        else
            -- Magic / Rare / Exalted / Normal
            local allAffixes = {}
            if type(maxrollItem.affixes) == "table" then
                for _, a in ipairs(maxrollItem.affixes) do table.insert(allAffixes, a) end
            end
            if type(maxrollItem.corruptedAffixes) == "table" then
                for _, a in ipairs(maxrollItem.corruptedAffixes) do table.insert(allAffixes, a) end
            end

            local affixCount, maxTier = 0, 0
            for i, affix in ipairs(allAffixes) do
                local modId   = affix.id .. "_" .. affix.tier
                local modData = data.itemMods.Item[modId]
                if modData then
                    affixCount = affixCount + 1
                    if affix.tier > maxTier then maxTier = affix.tier end
                    if modData.type == "Prefix" then
                        table.insert(item.prefixes, { range = affix.roll, modId = modId })
                    else
                        table.insert(item.suffixes, { range = affix.roll, modId = modId })
                    end
                end
            end

            local isIdol = itemBaseName:find("Idol") or itemBaseName:find("Altar")
            if maxTier >= 5 then
                item.rarity = "EXALTED"
            elseif isIdol then
                item.rarity = affixCount >= 2 and "RARE" or (affixCount >= 1 and "MAGIC" or "NORMAL")
            else
                item.rarity = affixCount >= 3 and "RARE" or (affixCount >= 1 and "MAGIC" or "NORMAL")
            end

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
            item.name = (forename ~= "" and forename .. " " or "") .. itemBaseName .. (surname ~= "" and " " .. surname or "")
        end

        return item
    end

    -- Resolve a slot value: inline object or numeric reference into sharedItems
    local function resolveItem(v)
        if type(v) == "number" then return sharedItems[tostring(v)] end
        return v
    end

    -- Main equipment slots
    if type(profileData.items) == "table" then
        for slotKey, inventoryId in pairs(maxrollSlotToInventoryId) do
            local mi = resolveItem(profileData.items[slotKey])
            if mi and type(mi) == "table" and mi.itemType then
                local item = parseItem(mi, inventoryId)
                if item then table.insert(char.items, item) end
            end
        end
    end

    -- Idol grid (array of up to 25, null entries are false after nullval=false decode)
    if type(profileData.idols) == "table" then
        for i, idol in ipairs(profileData.idols) do
            local mi = resolveItem(idol)
            if mi and type(mi) == "table" and mi.itemType then
                local slotName = idolGridSlots[i]
                if slotName then
                    local item = parseItem(mi, slotName)
                    if item then
                        table.insert(char.items, item)
                    end
                end
            end
        end
    end

    -- Altar (Idol Altar slot, inventoryId=123)
    if type(profileData.items) == "table" and profileData.items.altar then
        local mi = resolveItem(profileData.items.altar)
        if mi and type(mi) == "table" and mi.itemType then
            local item = parseItem(mi, 123)
            if item then table.insert(char.items, item) end
        end
    end
end

function ImportTabClass:ImportBlessingsFromMaxroll(profileData)
    local blessings = profileData.blessings
    if type(blessings) ~= "table" then return end
    for _, blessing in ipairs(blessings) do
        if blessing and type(blessing) == "table" and blessing.itemType == 34 then
            local blessingName
            for name, base in pairs(self.build.data.itemBases) do
                if base.baseTypeID == 34 and base.subTypeID == blessing.subType then
                    blessingName = name
                    break
                end
            end
            if blessingName and self.currentBlessingLookup then
                local info = self.currentBlessingLookup[blessingName]
                if info then
                    local roll = (type(blessing.implicits) == "table" and blessing.implicits[1]) or 255
                    local rollFrac = roll / 255.0
                    self.build.itemsTab:UpdateBlessingSlot(info.tl, info.entry, rollFrac)
                end
            end
        end
    end
end

function ImportTabClass:DownloadFromMaxroll()
    if launch.LogAction then launch:LogAction("Import: DownloadFromMaxroll") end
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
        for _, class in pairs(self.build.latestTree.classes) do
            for _, skill in ipairs(class.skills or {}) do
                if skill.treeId == skillTree['treeID'] then
                    skillName = skill.name
                    break
                end
            end
            if skillName then break end
        end
        if not skillName then
            ConPrintf("[IMPORT-SKILL] No match for treeID: %s", tostring(skillTree['treeID']))
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
                    -- Weaver's Will items have bit 6 set in the rarity byte (e.g. 64+9=73 for Legendary)
                    local isWeaversWill = rarity >= 64
                    local effectiveRarity = isWeaversWill and (rarity - 64) or rarity
                    item["explicitMods"] = {}
                    item["prefixes"] = {}
                    item["suffixes"] = {}
                    if effectiveRarity >= 7 and effectiveRarity <= 9 then
                        -- 7 = Unique, 8 = Set, 9 = Legendary
                        if effectiveRarity == 8 then
                            item["rarity"] = "SET"
                        elseif effectiveRarity == 9 then
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
                        if effectiveRarity == 9 then
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
end

function ImportTabClass:DownloadFullImport()
    if launch.LogAction then launch:LogAction("Import: DownloadFullImport") end
    local charSelect = self.controls.charSelect
    local charData = charSelect.list[charSelect.selIndex].char
    self:ImportPassiveTreeAndJewels(charData)
    self:ImportItemsAndSkills(charData)
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
    self.build.configTab:BuildModList()
    self.build.configTab:UpdateControls()
    self.build.buildFlag = true

    main:SetWindowTitleSubtext(string.format("%s (%s, %s, %s)", self.build.buildName, tostring(charData.name), tostring(charData.class), tostring(charData.league)))

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

            -- Idol Altar "increased Effect of [Prefixes/Suffixes] for Idols in
            -- Refracted Slots" is applied at calc time by CalcSetup.cloneWithAltarBoost.
            -- Do NOT bake the boost into the imported idol here, or it would be
            -- applied twice (once in XML-baked valueScalar, once in the clone).
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