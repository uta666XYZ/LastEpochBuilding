-- Last Epoch Building
--
-- Module: Notes Image Cache
-- Async download + on-disk caching of images embedded in Notes via `![alt](url)`.
-- Word-style auto-resize (display capped) is handled by the renderer; this module
-- just owns the URL -> ImageHandle lookup and download lifecycle.

local ImageCache = {}

local CACHE_DIR = "Data/NotesImageCache/"
local MAX_BYTES = 4 * 1024 * 1024
local MIN_BYTES = 32
local DIR_INITIALIZED = false

local function looksLikeImage(path)
	local f = io.open(path, "rb")
	if not f then return false end
	local head = f:read(12) or ""
	f:close()
	if #head < 4 then return false end
	-- PNG
	if head:sub(1, 8) == "\137PNG\r\n\26\n" then return true end
	-- JPEG (FF D8 FF)
	if head:byte(1) == 0xFF and head:byte(2) == 0xD8 and head:byte(3) == 0xFF then return true end
	-- GIF
	if head:sub(1, 6) == "GIF87a" or head:sub(1, 6) == "GIF89a" then return true end
	-- BMP
	if head:sub(1, 2) == "BM" then return true end
	-- TGA: no magic; accept by extension only
	local ext = path:match("%.([%w]+)$")
	if ext and ext:lower() == "tga" then return true end
	return false
end

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

-- Resolve a non-HTTP image reference to an absolute file path.
-- Supports `file:///abs/path`, absolute paths (`C:\...` / `/...`), and
-- relative paths resolved against the LEB script root so showcase templates
-- can reference bundled assets via e.g. `Data/NotesImages/foo.png`.
local function resolveLocalPath(ref)
	local p = ref:gsub("^file:///", ""):gsub("^file://", "")
	if p:match("^[A-Za-z]:[/\\]") or p:match("^[/\\]") then
		return p
	end
	local base = GetScriptPath() or ""
	if base ~= "" and not base:match("[/\\]$") then base = base .. "/" end
	return base .. p
end

function ImageCache.Get(url)
	if not url or url == "" then return nil end
	local entry = entries[url]
	if entry then return entry end

	-- Local file: load directly, skip the download/cache path.
	if not url:match("^https?://") then
		entry = { state = "pending", path = resolveLocalPath(url) }
		entries[url] = entry
		local f = io.open(entry.path, "rb")
		if not f then
			entry.state = "error"
			entry.errMsg = "Local file not found: " .. entry.path
			return entry
		end
		f:close()
		loadHandle(entry)
		return entry
	end

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

	-- Otherwise download asynchronously. Use DownloadFile so binary bytes never
	-- cross the subscript IPC boundary as a Lua string (which would truncate
	-- at the first NUL — PNG/JPG/GIF all contain embedded NULs).
	launch:DownloadFile(url, path, function(errMsg, bytes)
		if errMsg then
			entry.state = "error"
			entry.errMsg = errMsg
			notify()
			return
		end
		if not bytes or bytes < MIN_BYTES then
			os.remove(path)
			entry.state = "error"
			entry.errMsg = string.format("Download too small (%d bytes) — likely a redirect or HTML error page", bytes or 0)
			notify()
			return
		end
		if bytes > MAX_BYTES then
			os.remove(path)
			entry.state = "error"
			entry.errMsg = string.format("Image too large (%d KB, max %d KB)",
				math.floor(bytes / 1024), math.floor(MAX_BYTES / 1024))
			notify()
			return
		end
		if not looksLikeImage(path) then
			os.remove(path)
			entry.state = "error"
			entry.errMsg = "Downloaded data is not a recognized image (PNG/JPG/GIF/BMP/TGA)"
			notify()
			return
		end
		loadHandle(entry)
		notify()
	end)

	return entry
end

function ImageCache.OnInvalidation(cb)
	invalidationCallbacks[#invalidationCallbacks + 1] = cb
end

return ImageCache
