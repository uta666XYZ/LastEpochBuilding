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

--- Uploads a build code to Rentry.co (two-step: GET csrf token, then POST)
--- @param buildCode String The build code to upload
--- @return handle The subscript handle to pass to launch:RegisterSubScript
function buildSites.UploadToRentry(buildCode)
	return LaunchSubScript([[
		local code, connectionProtocol, proxyURL = ...
		local curl = require("lcurl.safe")

		local function urlencode(s)
			return s:gsub("[^%w%-_%.~]", function(c)
				return ("%%%02X"):format(c:byte())
			end)
		end

		-- Step 1: GET rentry.co to obtain the CSRF token cookie
		local csrftoken = ""
		local req1 = curl.easy()
		req1:setopt_url("https://rentry.co")
		req1:setopt(curl.OPT_USERAGENT, "Last Epoch Building/]] .. launch.versionNumber .. [[")
		req1:setopt(curl.OPT_ACCEPT_ENCODING, "")
		req1:setopt_headerfunction(function(header)
			local token = header:match("Set%-Cookie: csrftoken=([^;]+)")
			if token then csrftoken = token end
			return true
		end)
		req1:setopt_writefunction(function() return true end)
		if connectionProtocol then req1:setopt(curl.OPT_IPRESOLVE, connectionProtocol) end
		if proxyURL then req1:setopt(curl.OPT_PROXY, proxyURL) end
		req1:perform()
		req1:close()

		if csrftoken == "" then
			return nil, "Could not connect to Rentry.co"
		end

		-- Step 2: POST the build code to rentry.co/api
		local page = ""
		local req2 = curl.easy()
		req2:setopt_url("https://rentry.co/api")
		req2:setopt(curl.OPT_POST, true)
		req2:setopt(curl.OPT_USERAGENT, "Last Epoch Building/]] .. launch.versionNumber .. [[")
		req2:setopt(curl.OPT_ACCEPT_ENCODING, "")
		req2:setopt(curl.OPT_HTTPHEADER, {"Referer: https://rentry.co"})
		req2:setopt(curl.OPT_COOKIE, "csrftoken=" .. csrftoken)
		req2:setopt(curl.OPT_POSTFIELDS, "csrfmiddlewaretoken=" .. csrftoken .. "&text=" .. urlencode(code))
		req2:setopt_writefunction(function(data)
			page = page .. data
			return true
		end)
		if connectionProtocol then req2:setopt(curl.OPT_IPRESOLVE, connectionProtocol) end
		if proxyURL then req2:setopt(curl.OPT_PROXY, proxyURL) end
		req2:perform()
		local res = req2:getinfo_response_code()
		req2:close()

		if res == 200 then
			local url = page:match('"url"%s*:%s*"([^"]+)"')
			if url then
				return "https://rentry.co/" .. url
			end
			return nil, "Unexpected response from Rentry.co"
		else
			return nil, "Upload failed (HTTP " .. tostring(res) .. ")"
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
