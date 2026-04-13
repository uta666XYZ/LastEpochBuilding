-- Last Epoch Building
--
-- Module: Build Site Tools
-- Functions used to import and export LEP build codes from external websites
--

buildSites = { }

-- Import/Export websites list used in dropdowns
buildSites.websiteList = {
	{
		label = "lastepochtools.com", id = "lastepochtools", matchURL = "lastepochtools.com/planner/.+", regexURL = "lastepochtools.com/planner/(.+)$", downloadURL = "lastepochtools.com/planner/%1"
	},
	{
		label = "Pastebin.com", id = "pastebin", matchURL = "pastebin%.com/%w+", regexURL = "pastebin%.com/(%w+)%s*$", downloadURL = "pastebin.com/raw/%1",
	},
	{ label = "PastebinP.com", id = "pastebinProxy", matchURL = "pastebinp%.com/%w+", regexURL = "pastebinp%.com/(%w+)%s*$", downloadURL = "pastebinp.com/raw/%1" },
	{ label = "Rentry.co", id = "rentry", matchURL = "rentry%.co/%w+", regexURL = "rentry%.co/(%w+)%s*$", downloadURL = "rentry.co/paste/%1/raw" },
	{ label = "bytebin", id = "bytebin", matchURL = "bytebin%.lucko%.me/%w+", regexURL = "bytebin%.lucko%.me/(%w+)%s*$", downloadURL = "bytebin.lucko.me/%1" },
	{ label = "maxroll.gg Planner", id = "maxroll", matchURL = "maxroll%.gg/last%-epoch/planner/%w+", regexURL = "maxroll%.gg/last%-epoch/planner/(%w+)", downloadURL = "maxroll.gg/last-epoch/planner/%1" },
}

--- Uploads a LEP build code to a website
--- @param websiteInfo Table Contains the postUrl, any postParams, and a prefix to add to the response
--- @param buildCode String The build code that will be uploaded
function buildSites.UploadBuild(buildCode, websiteInfo)
	local response
	if websiteInfo then
		response = LaunchSubScript([[
			local code, connectionProtocol, proxyURL = ...
			local curl = require("lcurl.safe")
			local page = ""
			local easy = curl.easy()
			easy:setopt_url(']]..websiteInfo.postUrl..[[')
			easy:setopt(curl.OPT_POST, true)
			easy:setopt(curl.OPT_USERAGENT, "Last Epoch Building/]]..launch.versionNumber..[[")
			easy:setopt(curl.OPT_POSTFIELDS, ']]..websiteInfo.postFields..[['..code)
			easy:setopt(curl.OPT_ACCEPT_ENCODING, "")
			if connectionProtocol then
				easy:setopt(curl.OPT_IPRESOLVE, connectionProtocol)
			end
			if proxyURL then
				easy:setopt(curl.OPT_PROXY, proxyURL)
			end
			easy:setopt_writefunction(function(data)
				page = page..data
				return true
			end)
			easy:perform()
			local res = easy:getinfo_response_code()
			easy:close()
			if (res == 200) then
				return page
			else
				return nil, page
			end
		]], "", "", buildCode, launch.connectionProtocol, launch.proxyURL)
	end
	return response
end


--- Uploads a build code to bytebin.lucko.me (no auth required)
--- @param buildCode String The build code to upload
--- @return handle The subscript handle to pass to launch:RegisterSubScript
function buildSites.UploadToBytebin(buildCode)
	return LaunchSubScript([[
		local code, connectionProtocol, proxyURL = ...
		local curl = require("lcurl.safe")
		local page = ""
		local easy = curl.easy()
		easy:setopt_url("https://bytebin.lucko.me/post")
		easy:setopt(curl.OPT_POST, true)
		easy:setopt(curl.OPT_USERAGENT, "Last Epoch Building/]] .. launch.versionNumber .. [[")
		easy:setopt(curl.OPT_ACCEPT_ENCODING, "")
		easy:setopt(curl.OPT_HTTPHEADER, {"Content-Type: text/plain; charset=utf-8"})
		easy:setopt(curl.OPT_POSTFIELDS, code)
		easy:setopt_writefunction(function(data)
			page = page .. data
			return true
		end)
		if connectionProtocol then easy:setopt(curl.OPT_IPRESOLVE, connectionProtocol) end
		if proxyURL then easy:setopt(curl.OPT_PROXY, proxyURL) end
		local _, curlErr = easy:perform()
		local res = easy:getinfo_response_code()
		easy:close()
		if curlErr then
			return nil, "Connection error: " .. tostring(curlErr:msg()) .. " (code " .. tostring(curlErr:no()) .. ")"
		end
		if res == 200 or res == 201 then
			local key = page:match('"key"%s*:%s*"([^"]+)"')
			if key then
				return "https://bytebin.lucko.me/" .. key
			end
			return nil, "Unexpected response (HTTP " .. tostring(res) .. "): " .. page:sub(1, 200)
		else
			return nil, "Upload failed (HTTP " .. tostring(res) .. "): " .. page:sub(1, 200)
		end
	]], "", "", buildCode, launch.connectionProtocol, launch.proxyURL)
end

--- Downloads a LEP build code from a website
--- @param link String A link to the site that contains the link to the raw build code
--- @param websiteInfo Table Contains the downloadUrl
--- @param callback Function The function to call when the download is complete
function buildSites.DownloadBuild(link, websiteInfo, callback)
	local siteCodeURL
	-- Only called on program start via protocol handler
	if not websiteInfo then
		for _, siteInfo in ipairs(buildSites.websiteList) do
			if link:match("^pob:[/\\]*" .. siteInfo.id:lower() .. "[/\\]+(.+)") then
				siteCodeURL = link:gsub("^pob:[/\\]*" .. siteInfo.id:lower() .. "[/\\]+(.+)", "https://" .. siteInfo.downloadURL)
				websiteInfo = siteInfo
				break
			end
		end
	else -- called via the ImportTab
		siteCodeURL = link:gsub(websiteInfo.regexURL, websiteInfo.downloadURL)
	end
	if websiteInfo then
		launch:DownloadPage(siteCodeURL, function(response, errMsg)
			if errMsg then
				callback(false, errMsg)
			else
				callback(true, response.body)
			end
		end)
	else
		callback(false, "Download information not found")
	end
end
