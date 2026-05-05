-- Last Epoch Building
--
-- Module: Notes Image Cache
-- Async download + on-disk caching of images embedded in Notes via `![alt](url)`.
-- Word-style auto-resize (display capped) is handled by the renderer; this module
-- just owns the URL -> ImageHandle lookup and download lifecycle.

local ImageCache = {}

local CACHE_DIR = "Data/NotesImageCache/"
local MAX_BYTES = 4 * 1024 * 1024
local DIR_INITIALIZED = false

-- url -> { state="pending"|"loaded"|"error", handle, w, h, errMsg, path }
local entries = {}
local invalidationCallbacks = {}

local function fnv1a(s)
	local h = 2166136261
	for i = 1, #s do
		h = bit.band(bit.bxor(h, s:byte(i)) * 16777619, 0xFFFFFFFF)
	end
	return string.format("%08x", h)
end

local function extFromURL(url)
	local stripped = url:gsub("[?#].*$", "")
	local ext = stripped:match("%.([%w]+)$")
	if ext then
		ext = ext:lower()
		if ext == "jpg" or ext == "jpeg" or ext == "png" or ext == "gif" or ext == "bmp" or ext == "tga" then
			return ext == "jpeg" and "jpg" or ext
		end
	end
	return "png"
end

local function ensureDir()
	if not DIR_INITIALIZED then
		MakeDir(CACHE_DIR)
		DIR_INITIALIZED = true
	end
end

local function notify()
	for _, cb in ipairs(invalidationCallbacks) do cb() end
end

local function loadHandle(entry)
	local handle = NewImageHandle()
	handle:Load(entry.path, "MIPMAP")
	if handle:IsValid() then
		entry.handle = handle
		entry.w, entry.h = handle:ImageSize()
		entry.state = "loaded"
	else
		entry.state = "error"
		entry.errMsg = "Failed to decode image"
	end
end

function ImageCache.Get(url)
	if not url or url == "" then return nil end
	local entry = entries[url]
	if entry then return entry end

	ensureDir()
	local hash = fnv1a(url)
	local ext = extFromURL(url)
	local path = CACHE_DIR .. hash .. "." .. ext

	entry = { state = "pending", path = path }
	entries[url] = entry

	-- Try disk cache first.
	local f = io.open(path, "rb")
	if f then
		f:close()
		loadHandle(entry)
		return entry
	end

	-- Otherwise download asynchronously.
	launch:DownloadPage(url, function(response, errMsg)
		if errMsg or not response or not response.body or #response.body == 0 then
			entry.state = "error"
			entry.errMsg = errMsg or "Empty response"
			notify()
			return
		end
		if #response.body > MAX_BYTES then
			entry.state = "error"
			entry.errMsg = string.format("Image too large (%d KB, max %d KB)",
				math.floor(#response.body / 1024), math.floor(MAX_BYTES / 1024))
			notify()
			return
		end
		local out = io.open(path, "wb")
		if not out then
			entry.state = "error"
			entry.errMsg = "Could not write cache file"
			notify()
			return
		end
		out:write(response.body)
		out:close()
		loadHandle(entry)
		notify()
	end)

	return entry
end

function ImageCache.OnInvalidation(cb)
	invalidationCallbacks[#invalidationCallbacks + 1] = cb
end

return ImageCache
