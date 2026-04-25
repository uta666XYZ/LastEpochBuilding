#@ SimpleGraphic
-- Last Epoch Building
-- @leb-canary v1 / id:leb-7f3a9c-launch-2026 / do-not-remove (see Development/リリース手順.md)
--
-- Module: Launch
-- Program entry point; loads and runs the Main module within a protected environment
--

local startTime = GetTime()
APP_NAME = "Last Epoch Building"

-- Log file: writes all ConPrintf output to debug.log
-- Try worktree/repo root first (../), fall back to current dir
local _conPrintf = ConPrintf
local _logPath = (io.open("../manifest.xml", "r") and io.close(io.open("../manifest.xml", "r")) and "../debug.log") or "debug.log"
local _logFile = io.open(_logPath, "w")
-- In-memory ring buffer of ConPrintf output, used to build error reports
local _logBuffer = {}
local _logBufferMax = 500
if _logFile then
	function ConPrintf(fmt, ...)
		local ok, msg = pcall(string.format, fmt, ...)
		if ok then
			_conPrintf("%s", msg)
			if _logFile then
				_logFile:write(msg .. "\n")
				_logFile:flush()
			end
			table.insert(_logBuffer, msg)
			if #_logBuffer > _logBufferMax then
				table.remove(_logBuffer, 1)
			end
		else
			_conPrintf(fmt, ...)
		end
	end
end

-- Returns the recent ConPrintf output as a single string (up to _logBufferMax lines)
function GetDebugLogText()
	return table.concat(_logBuffer, "\n")
end

-- Clears debug.log and restarts logging (call at the start of each import)
function ResetDebugLog()
	if _logFile then
		_logFile:close()
	end
	_logFile = io.open(_logPath, "w")
end

SetWindowTitle(APP_NAME)
ConExecute("set vid_mode 8")
ConExecute("set vid_resizable 3")

launch = { }
SetMainObject(launch)

-- Action log: circular buffer of recent user-facing events, flushed on error
local ACTION_LOG_MAX = 20

function launch:LogAction(fmt, ...)
	if not self.actionLog then
		self.actionLog = {}
	end
	local ok, msg = pcall(string.format, fmt, ...)
	if not ok then
		msg = tostring(fmt)
	end
	local entry = string.format("[%.1fs] %s", (GetTime() - (self.startTime or 0)) / 1000, msg)
	table.insert(self.actionLog, entry)
	if #self.actionLog > ACTION_LOG_MAX then
		table.remove(self.actionLog, 1)
	end
end

function launch:DumpActionLog()
	if not self.actionLog or #self.actionLog == 0 then
		ConPrintf("Action log: (empty)")
		return
	end
	ConPrintf("Action log (last %d):", #self.actionLog)
	for _, entry in ipairs(self.actionLog) do
		ConPrintf("  %s", entry)
	end
end

function launch:OnInit()
	self.devMode = false
	self.installedMode = false
	self.versionNumber = "?"
	self.versionBranch = "?"
	self.versionPlatform = "?"
	self.lastUpdateCheck = GetTime()
	self.subScripts = { }
	self.startTime = startTime
	self.actionLog = {}
	local xml = require("xml")
	local localManXML = xml.LoadXMLFile("manifest.xml") or xml.LoadXMLFile("../manifest.xml")
	if localManXML and localManXML[1].elem == "LEPVersion" then
		for _, node in ipairs(localManXML[1]) do
			if type(node) == "table" then
				if node.elem == "Version" then
					self.versionNumber = node.attrib.number
					self.versionBranch = node.attrib.branch
					self.versionPlatform = node.attrib.platform
				end
			end
		end
	end
	local gitHead = io.open(".git/HEAD", "r") or io.open("../.git/HEAD", "r")
	if not gitHead then
		-- .git may be a file (git worktree) rather than a directory
		local gitFile = io.open(".git", "r") or io.open("../.git", "r")
		if gitFile then
			gitHead = gitFile
		end
	end
	if gitHead then
		-- Running from a git repository, enable dev mode
		self.devMode = true
		gitHead:close()
	elseif localManXML and not self.versionBranch and not self.versionPlatform then
		-- Looks like a remote manifest, so we're probably running from a repository
		-- Enable dev mode to disable updates and set user path to be the script path
		self.devMode = true
	end
	local installedFile = io.open("installed.cfg", "r")
	if installedFile then
		self.installedMode = true
		installedFile:close()
	end
	RenderInit()
	-- Log environment info for error reports
	ConPrintf("=== LEB Startup ===")
	ConPrintf("LEB version: v%s branch=%s platform=%s", tostring(self.versionNumber), tostring(self.versionBranch), tostring(self.versionPlatform))
	ConPrintf("devMode: %s, installedMode: %s", tostring(self.devMode), tostring(self.installedMode))
	local _sw, _sh = GetScreenSize()
	ConPrintf("Screen size: %dx%d", _sw or 0, _sh or 0)
	ConPrintf("===================")
	ConPrintf("Loading main script...")
	local errMsg
	errMsg, self.main = PLoadModule("Modules/Main")
	if errMsg then
		self:ShowErrMsg("Error loading main script: %s", errMsg)
	elseif not self.main then
		self:ShowErrMsg("Error loading main script: no object returned")
	elseif self.main.Init then
		errMsg = PCall(self.main.Init, self.main)
		if errMsg then
			self:ShowErrMsg("In 'Init': %s", errMsg)
		end
	end

	if not self.devMode and not firstRunFile then
		-- Run a background update check if developer mode is off
		self:CheckForUpdate(true)
	end
end

function launch:CanExit()
	if self.main and self.main.CanExit and not self.promptMsg then
		local errMsg, ret = PCall(self.main.CanExit, self.main)
		if errMsg then
			self:ShowErrMsg("In 'CanExit': %s", errMsg)
			return false
		else
			return ret
		end
	end
	return true
end

function launch:OnExit()
	if self.main and self.main.Shutdown then
		PCall(self.main.Shutdown, self.main)
	end
end

function launch:OnFrame()
	if self.main then
		if self.main.OnFrame then
			local errMsg = PCall(self.main.OnFrame, self.main)
			if errMsg then
				self:ShowErrMsg("In 'OnFrame': %s", errMsg)
			end
		end
	end
	self.devModeAlt = self.devMode and IsKeyDown("ALT")
	SetDrawLayer(1000)
	SetViewport()
	if self.promptMsg then
		local r, g, b = unpack(self.promptCol)
		self:DrawPopup(r, g, b, "^0%s", self.promptMsg)
	end
	if self.doRestart then
		local screenW, screenH = GetScreenSize()
		SetDrawColor(0, 0, 0, 0.75)
		DrawImage(nil, 0, 0, screenW, screenH)
		SetDrawColor(1, 1, 1)
		DrawString(0, screenH/2, "CENTER", 24, "FIXED", self.doRestart)
		Restart()
	end
	if not self.devMode and (GetTime() - self.lastUpdateCheck) > 1000*60*60*12 then
		-- Do an update check every 12 hours if the user keeps the program open
		self:CheckForUpdate(true)
	end
end

function launch:OnKeyDown(key, doubleClick)
	if key == "F5" then
		self.doRestart = "Restarting..."
	elseif key == "F6" and self.devMode then
		local before = collectgarbage("count")
		collectgarbage("collect")
		ConPrintf("%dkB => %dkB", before, collectgarbage("count"))
	elseif key == "PAUSE" and self.devMode and profiler then
		if profiling then
			profiler.stop()
			profiler.report("profiler.log")
			profiling = false
		else
			profiler.start()
			profiling = true
		end
	elseif key == "u" and IsKeyDown("CTRL") then
		if not self.devMode then
			self:CheckForUpdate()
		end
	elseif self.promptMsg then
		self:RunPromptFunc(key)
	else
		if self.main and self.main.OnKeyDown then
			local errMsg = PCall(self.main.OnKeyDown, self.main, key, doubleClick)
			if errMsg then
				self:ShowErrMsg("In 'OnKeyDown': %s", errMsg)
			end
		end
	end
end

function launch:OnKeyUp(key)
	if not self.promptMsg then
		if self.main and self.main.OnKeyUp then
			local errMsg = PCall(self.main.OnKeyUp, self.main, key)
			if errMsg then
				self:ShowErrMsg("In 'OnKeyUp': %s", errMsg)
			end
		end
	end
end

function launch:OnChar(key)
	if self.promptMsg then
		self:RunPromptFunc(key)
	else
		if self.main and self.main.OnChar then
			local errMsg = PCall(self.main.OnChar, self.main, key)
			if errMsg then
				self:ShowErrMsg("In 'OnChar': %s", errMsg)
			end
		end
	end
end

function launch:OnSubCall(func, ...)
	if func == "UpdateProgress" then
		self.updateProgress = string.format(...)
	end
	if _G[func] then
		return _G[func](...)
	end
end

function launch:OnSubError(id, errMsg)
	if self.subScripts[id].type == "UPDATE" then
		self:ShowErrMsg("In update thread: %s", errMsg)
		self.updateCheckRunning = false
	elseif self.subScripts[id].type == "DOWNLOAD" then
		local errMsg = PCall(self.subScripts[id].callback, nil, errMsg)
		if errMsg then
			self:ShowErrMsg("In download callback: %s", errMsg)
		end
	end
	self.subScripts[id] = nil
end

function launch:OnSubFinished(id, ...)
	if self.subScripts[id].type == "UPDATE" then
		self.updateAvailable, self.updateErrMsg = ...
		self.updateCheckRunning = false
		if self.updateCheckBackground and self.updateAvailable == "none" then
			self.updateAvailable = nil
		end
	elseif self.subScripts[id].type == "DOWNLOAD" then
		local errMsg = PCall(self.subScripts[id].callback, ...)
		if errMsg then
			self:ShowErrMsg("In download callback: %s", errMsg)
		end
	elseif self.subScripts[id].type == "CUSTOM" then
		if self.subScripts[id].callback then
			local errMsg = PCall(self.subScripts[id].callback, ...)
			if errMsg then
				self:ShowErrMsg("In subscript callback: %s", errMsg)
			end
		end
	end
	self.subScripts[id] = nil
end

function launch:RegisterSubScript(id, callback)
	if id then
		self.subScripts[id] = {
			type = "CUSTOM",
			callback = callback,
		}
	end
end

---Download the given page in the background, and calls the provided callback function when done:
---@param url string
---@param callback fun(response:table, errMsg:string) @ response = { header, body }
---@param params table @ params = { header, body }
function launch:DownloadPage(url, callback, params)
	params = params or {}
	local script = [[
		local url, requestHeader, requestBody, connectionProtocol, proxyURL = ...
		local responseHeader = ""
		local responseBody = ""
		ConPrintf("Downloading page at: %s", url)
		local curl = require("lcurl.safe")
		local easy = curl.easy()
		if requestHeader then
			local header = {}
			for s in requestHeader:gmatch("[^\r\n]+") do
    			table.insert(header, s)
			end
			easy:setopt(curl.OPT_HTTPHEADER, header)
		end
		easy:setopt_url(url)
		easy:setopt(curl.OPT_USERAGENT, "Last Epoch Building/]]..self.versionNumber..[[")
		easy:setopt(curl.OPT_ACCEPT_ENCODING, "")
		if requestBody then
			easy:setopt(curl.OPT_POST, true)
			easy:setopt(curl.OPT_POSTFIELDS, requestBody)
		end
		if connectionProtocol then
			easy:setopt(curl.OPT_IPRESOLVE, connectionProtocol)
		end
		if proxyURL then
			easy:setopt(curl.OPT_PROXY, proxyURL)
		end
		easy:setopt_headerfunction(function(data)
			responseHeader = responseHeader .. data
			return true
		end)
		easy:setopt_writefunction(function(data)
			responseBody = responseBody .. data
			return true
		end)
		local _, error = easy:perform()
		local code = easy:getinfo(curl.INFO_RESPONSE_CODE)
		easy:close()
		local errMsg
		if error then
			errMsg = error:msg()
		elseif code ~= 200 then
			errMsg = "Response code: "..code
		elseif #responseBody == 0 then
			errMsg = "No data returned"
		end
		ConPrintf("Download complete. Status: %s", errMsg or "OK")
		return responseHeader, responseBody, errMsg
	]]
	local id = LaunchSubScript(script, "", "ConPrintf", url, params.header, params.body, self.connectionProtocol, self.proxyURL)
	if id then
		self.subScripts[id] = {
			type = "DOWNLOAD",
			callback = function(responseHeader, responseBody, errMsg)
				callback({header=responseHeader, body=responseBody}, errMsg)
			end
		}
	end
end

function launch:ApplyUpdate(mode)
	if mode == "basic" then
		-- Need to revert to the basic environment to fully apply the update
		LoadModule("UpdateApply", "Update/opFile.txt")
		SpawnProcess(GetRuntimePath()..'/Update', 'UpdateApply.lua Update/opFileRuntime.txt')
		Exit()
	elseif mode == "normal" then
		-- Update can be applied while normal environment is running
		LoadModule("UpdateApply", "Update/opFile.txt")
		Restart()
		self.doRestart = "Updating..."
	end
end

function launch:CheckForUpdate(inBackground)
	if self.updateCheckRunning then
		return
	end
	self.updateCheckBackground = inBackground
	self.updateMsg = "Initialising..."
	self.updateProgress = "Checking..."
	self.lastUpdateCheck = GetTime()
	local update = io.open("UpdateCheck.lua", "r")
	local id = LaunchSubScript(update:read("*a"), "GetScriptPath,GetRuntimePath,GetWorkDir,MakeDir", "ConPrintf,UpdateProgress", self.connectionProtocol, self.proxyURL)
	if id then
		self.subScripts[id] = {
			type = "UPDATE"
		}
		self.updateCheckRunning = true
	end
	update:close()
end

function launch:ShowPrompt(r, g, b, str, func)
	self.promptMsg = str
	self.promptCol = {r, g, b}
	self.promptFunc = func or function(key)
		if key == "RETURN" or key == "ESCAPE" then
			return true
		elseif key == "F5" then
			self.doRestart = "Restarting..."
			return true
		end
	end
end

-- Builds a plain-text error report, optionally appending a build code/URL
function launch:BuildErrorReport(errText, buildUrl)
	local lines = {}
	table.insert(lines, "=== LEB Error Report ===")
	table.insert(lines, string.format("Version: v%s %s %s", tostring(self.versionNumber), tostring(self.versionBranch), tostring(self.versionPlatform)))
	table.insert(lines, "Error:")
	table.insert(lines, errText or "(unknown)")
	table.insert(lines, "")
	if self.actionLog and #self.actionLog > 0 then
		table.insert(lines, "Recent actions:")
		for _, entry in ipairs(self.actionLog) do
			table.insert(lines, "  " .. entry)
		end
		table.insert(lines, "")
	end
	if buildUrl then
		table.insert(lines, "Build: " .. buildUrl)
		table.insert(lines, "")
	end
	table.insert(lines, "--- debug.log ---")
	if GetDebugLogText then
		table.insert(lines, GetDebugLogText())
	end
	return table.concat(lines, "\n")
end

-- Copies the error report to the clipboard. If includeBuild is true and a build
-- is loaded, the build code is uploaded to bytebin asynchronously and the URL is
-- included. Updates self.promptMsg to reflect state (copying -> done / failed).
function launch:CopyErrorReport(errText, includeBuild)
	self._lastErrText = errText
	local function finalize(buildUrl, uploadErr)
		-- Clear any transient "Generating..." prompt before showing the result
		self.promptMsg = nil
		local report = self:BuildErrorReport(errText, buildUrl)
		if Copy then
			Copy(report)
		end
		local status
		if includeBuild and uploadErr then
			status = "^1Build URL upload failed: "..tostring(uploadErr).."\n^0Error report (without build URL) copied to clipboard."
		elseif includeBuild and buildUrl then
			status = "^2Error report copied to clipboard (build URL included)."
		else
			status = "^2Error report copied to clipboard."
		end
		self:ShowRichReportCopiedDialog(status)
	end

	if not includeBuild then
		finalize(nil, nil)
		return
	end

	-- Try to get a build code from the current build (requires main in BUILD mode)
	local ok, code = pcall(function()
		local buildMode = main and main.modes and main.mode and main.modes[main.mode]
		if buildMode and buildMode.SaveDB and buildMode.targetVersion and common and common.base85 and Deflate then
			local xml = buildMode:SaveDB("code")
			if xml then
				return "!" .. common.base85.encode(Deflate(xml))
			end
		end
		return nil
	end)
	if not ok or not code then
		finalize(nil, "No build available to include")
		return
	end

	-- Upload to bytebin in the background; show a progress prompt in the meantime
	self:ShowPrompt(1, 1, 0, "^0Generating build URL...\nPlease wait a moment.", function() return false end)
	local buildSites = _G.buildSites
	if not (buildSites and buildSites.UploadToBytebin) then
		finalize(nil, "Build sharing module not loaded")
		return
	end
	local id = buildSites.UploadToBytebin(code)
	if not id then
		finalize(nil, "Failed to launch upload")
		return
	end
	launch:RegisterSubScript(id, function(url, uploadErr)
		finalize(url, uploadErr)
	end)
end

-- Shows the "report copied" confirmation (fallback: keyboard-only prompt)
function launch:ShowReportCopiedPrompt(statusLine)
	local msg = (statusLine or "^2Error report copied to clipboard.") ..
		"\n\n^0Please paste it as a comment on the latest Reddit post:\n" ..
		"  https://reddit.com/user/ukunZ626\n" ..
		"Or open a GitHub issue at:\n" ..
		"  https://github.com/uta666XYZ/LastEpochBuilding/issues\n\n" ..
		"^0Press Enter/Escape to dismiss, or F5 to restart LEB."
	self:ShowPrompt(0, 0.5, 0, msg)
end

-- Rich confirmation dialog using main:OpenPopup
function launch:ShowRichReportCopiedDialog(statusLine)
	if not (main and main.OpenPopup) then
		self:ShowReportCopiedPrompt(statusLine)
		return
	end
	local controls = {}
	local y = 20
	local lines = {
		statusLine or "^2Error report has been copied to clipboard.",
		"",
		"^7Please paste it as a comment on the latest Reddit post:",
		"  ^x4080FFhttps://reddit.com/user/ukunZ626",
		"^7Or open a GitHub issue at:",
		"  ^x4080FFhttps://github.com/uta666XYZ/LastEpochBuilding/issues",
	}
	for _, line in ipairs(lines) do
		table.insert(controls, new("LabelControl", nil, 0, y, 0, 16, line))
		y = y + 18
	end
	y = y + 6
	table.insert(controls, new("LabelControl", nil, 0, y, 0, 14, "^8Press F5 to restart LEB"))
	y = y + 24
	controls.close = new("ButtonControl", nil, 0, y, 80, 20, "Close", function()
		main:ClosePopup()
	end)
	y = y + 30
	main:OpenPopup(560, y, "Report Copied", controls, "close", nil, "close")
end

-- Rich error dialog using main:OpenPopup (checkbox + buttons)
function launch:ShowRichErrorDialog(errText)
	if not (main and main.OpenPopup) then
		return false
	end
	local controls = {}
	local y = 20
	-- Error text (split by newlines)
	for line in (errText .. "\n"):gmatch("([^\n]*)\n") do
		table.insert(controls, new("LabelControl", nil, 0, y, 0, 16, "^1" .. line))
		y = y + 18
	end
	y = y + 6
	-- Version info
	local version = "^8v" .. tostring(self.versionNumber) ..
		(self.versionBranch and (" " .. tostring(self.versionBranch)) or "") ..
		(self.versionPlatform and (" " .. tostring(self.versionPlatform)) or "")
	table.insert(controls, new("LabelControl", nil, 0, y, 0, 14, version))
	y = y + 24
	-- Reporting instructions
	local intro = {
		"^7If this keeps happening, please help us fix it by reporting:",
		"  Reddit: ^x4080FFhttps://reddit.com/user/ukunZ626 ^7(comment on the latest post)",
		"  GitHub: ^x4080FFhttps://github.com/uta666XYZ/LastEpochBuilding/issues",
	}
	for _, line in ipairs(intro) do
		table.insert(controls, new("LabelControl", nil, 0, y, 0, 16, line))
		y = y + 18
	end
	y = y + 8
	-- Checkbox: include build (center the label+checkbox group within the popup)
	local includeBuildState = false
	local cbLabel = "^7I agree to include my build in the report (helps us improve LEB)"
	local popupW = 620
	local cbSize = 18
	local stringW = DrawStringWidth(cbSize - 4, "VAR", cbLabel)
	local cbX = math.floor((popupW + stringW - cbSize + 5) / 2)
	controls.includeBuild = new("CheckBoxControl", { "TOPLEFT", nil, "TOPLEFT" }, cbX, y, cbSize,
		cbLabel,
		function(state) includeBuildState = state end)
	controls.includeBuild.state = false
	y = y + 28
	-- Footer: F5 hint
	table.insert(controls, new("LabelControl", nil, 0, y, 0, 14, "^8Press F5 to restart LEB"))
	y = y + 24
	-- Buttons (bottom right)
	controls.copy = new("ButtonControl", nil, -55, y, 110, 20, "Copy Report", function()
		main:ClosePopup()
		self:CopyErrorReport(errText, includeBuildState)
	end)
	controls.close = new("ButtonControl", nil, 65, y, 80, 20, "Close", function()
		main:ClosePopup()
	end)
	y = y + 30
	main:OpenPopup(620, y, "Error", controls, "copy", nil, "close")
	return true
end

function launch:ShowErrMsg(fmt, ...)
	-- Always log the error to debug.log, even if a prompt is already shown
	local errText = string.format(fmt, ...)
	ConPrintf("=== ERROR ===")
	ConPrintf("LEB v%s %s %s", tostring(self.versionNumber), tostring(self.versionBranch), tostring(self.versionPlatform))
	self:DumpActionLog()
	ConPrintf("%s", errText)
	ConPrintf("=============")
	if self.promptMsg then return end
	-- Try rich UI first; fall back to keyboard-only prompt if main is unavailable
	local ok = pcall(function() return self:ShowRichErrorDialog(errText) end)
	if ok then
		-- Re-check after the pcall in case it swallowed a failure
		if main and main.popups and #main.popups > 0 then return end
	end
	-- Fallback: keyboard prompt (used when main is not initialized or OpenPopup fails)
	local version = self.versionNumber and
		"^8v"..self.versionNumber..(self.versionBranch and " "..self.versionBranch or "")
		or ""
	local msg = "^1Error:\n\n^0"..errText.."\n"..version..
		"\n\n^0If this keeps happening, please report it:\n"..
		"  Reddit: https://reddit.com/user/ukunZ626 (comment on the latest post)\n"..
		"  GitHub: https://github.com/uta666XYZ/LastEpochBuilding/issues\n\n"..
		"^0Press C to copy error report to clipboard.\n"..
		"Press B to copy with build code (requires Internet).\n"..
		"Press Enter/Escape to dismiss, or F5 to restart LEB."
	self:ShowPrompt(1, 0, 0, msg, function(key)
		if key == "RETURN" or key == "ESCAPE" then
			return true
		elseif key == "F5" then
			self.doRestart = "Restarting..."
			return true
		elseif key == "c" or key == "C" then
			self:CopyErrorReport(errText, false)
			return false
		elseif key == "b" or key == "B" then
			self:CopyErrorReport(errText, true)
			return false
		end
	end)
end

function launch:RunPromptFunc(key)
	local curMsg = self.promptMsg
	local errMsg, ret = PCall(self.promptFunc, key)
	if errMsg then
		self:ShowErrMsg("In prompt func: %s", errMsg)
	elseif ret and self.promptMsg == curMsg then
		self.promptMsg = nil
	end
end

function launch:DrawPopup(r, g, b, fmt, ...)
	local screenW, screenH = GetScreenSize()
	SetDrawColor(0, 0, 0, 0.5)
	DrawImage(nil, 0, 0, screenW, screenH)
	local txt = string.format(fmt, ...)
	local w = DrawStringWidth(20, "VAR", txt) + 20
	local h = (#txt:gsub("[^\n]","") + 2) * 20
	local ox = (screenW - w) / 2
	local oy = (screenH - h) / 2
	SetDrawColor(1, 1, 1)
	DrawImage(nil, ox, oy, w, h)
	SetDrawColor(r, g, b)
	DrawImage(nil, ox + 2, oy + 2, w - 4, h - 4)
	SetDrawColor(1, 1, 1)
	DrawImage(nil, ox + 4, oy + 4, w - 8, h - 8)
	DrawString(0, oy + 10, "CENTER", 20, "VAR", txt)
end
