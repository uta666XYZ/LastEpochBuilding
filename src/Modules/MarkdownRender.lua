-- Last Epoch Building
--
-- Module: Markdown Render
-- Lightweight Markdown renderer for the Notes tab preview mode.
--
-- Supports:
--   # / ## / ### headings
--   - / * bullet lists (single level)
--   **bold** (rendered as bright white)
--   *italic* (rendered with a soft cyan tint)
--   `inline code` (rendered with subtle bg highlight)
--   ```fenced``` code blocks (monospace with bg)
--   > blockquote
--   | a | b | tables (header + separator + rows)
--   [label](url) external links (clickable)
--   [[Loadout: name]] loadout placeholders (clickable, currently inert)
--   `^xRRGGBB` / `^0-9` color codes pass through to DrawString.
--
-- Returns hotspot rectangles for click handling.

local MarkdownRender = {}

local ImageCache = LoadModule("Modules/NotesImageCache")

-- Word-style auto-resize: cap displayed image size so a 4K asset doesn't
-- blow up layout or per-frame draw cost. The renderer downsamples; we never
-- mutate the cached file.
local IMAGE_MAX_W = 800
local IMAGE_MAX_H = 400
local IMAGE_PLACEHOLDER_H = 120

local TOC_HEADER_TEXT = "Contents"
local TOC_HEADER_SIZE = 18
local TOC_LINE_HEIGHT = 16
local TOC_INDENT_PER_LEVEL = 14
local TOC_PAD = 8

local LINE_HEIGHT_BODY = 16
-- Bitmap font has crisp glyphs only at certain sizes; 24/20/18 render cleanly
-- whereas 28/22 upscale blurs.
local HEADING_SIZES = { [1] = 24, [2] = 20, [3] = 18 }
local FONT = "VAR"
local CODE_FONT = "FIXED"
local BULLET_INDENT = 18
local PARAGRAPH_GAP = 4
local HEADING_GAP_TOP = 10
local HEADING_GAP_BOTTOM = 4
local CODE_LINE_HEIGHT = 14
local CODE_PADDING = 6
local QUOTE_INDENT = 12
local TABLE_CELL_PAD = 8
local TABLE_BORDER_THICKNESS = 1

local LINK_COLOR = "^x4FA8FF"
local LOADOUT_COLOR = "^x71E87D"
local BOLD_COLOR = "^xFFFFFF"
-- Bitmap font has no italic glyphs; using a faint contrast tint instead of
-- a strong cyan keeps it readable next to body text.
local ITALIC_COLOR = "^xBFD6E0"
local BODY_COLOR = "^xCCCCCC"
local HEADING_COLOR = "^xFFFFFF"
local BULLET_GLYPH_COLOR = "^x888888"
local CODE_TEXT_COLOR = "^xE0D8B0"
local QUOTE_TEXT_COLOR = "^xA8B8C8"
local TABLE_HEADER_COLOR = "^xFFFFFF"

local CODE_BG = { 0.10, 0.10, 0.12 }
local INLINE_CODE_BG = { 0.18, 0.18, 0.22 }
local QUOTE_BAR = { 0.40, 0.55, 0.70 }
local TABLE_BORDER = { 0.35, 0.35, 0.35 }

-- Substitute Unicode glyphs the bitmap font lacks (em dash, en dash, smart
-- quotes, ellipsis, bullet) with ASCII equivalents so they render instead of
-- showing as `[U+xxxx]` placeholders.
local UNICODE_FALLBACKS = {
	["\xE2\x80\x94"] = "-",   -- em dash
	["\xE2\x80\x93"] = "-",   -- en dash
	["\xE2\x80\x98"] = "'",   -- left single quote
	["\xE2\x80\x99"] = "'",   -- right single quote
	["\xE2\x80\x9C"] = '"',   -- left double quote
	["\xE2\x80\x9D"] = '"',   -- right double quote
	["\xE2\x80\xA6"] = "...", -- ellipsis
	["\xE2\x80\xA2"] = "*",   -- bullet
	["\xC2\xA0"]     = " ",   -- non-breaking space
}

local function applyUnicodeFallbacks(s)
	return (s:gsub("\xE2\x80[\x93\x94\x98\x99\x9C\x9D\xA2\xA6]", UNICODE_FALLBACKS):gsub("\xC2\xA0", UNICODE_FALLBACKS))
end

-- Lowercase, replace runs of non-alphanumerics with `-`, trim. Used for
-- internal anchor links: `## Some Heading` -> `some-heading`.
local function slugify(text)
	-- Strip inline markup so the slug derives from visible text only.
	local plain = text:gsub("%*%*(.-)%*%*", "%1"):gsub("%*(.-)%*", "%1"):gsub("`(.-)`", "%1")
	plain = plain:gsub("%[%[(.-)%]%]", "%1"):gsub("%[(.-)%]%(.-%)", "%1")
	plain = plain:gsub("%^x%x%x%x%x%x%x", ""):gsub("%^%d", "")
	plain = plain:lower():gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
	return plain
end
MarkdownRender.slugify = slugify

-- Parse a single block-level line that doesn't need multi-line awareness.
local function parseSimpleBlock(line)
	if line:match("^%s*%[%[[Tt][Oo][Cc]%]%]%s*$") then
		return { kind = "toc" }
	end
	local heading = line:match("^(#+)%s+(.*)$")
	if heading then
		local level = math.min(#heading, 3)
		local _, _, text = line:find("^#+%s+(.*)$")
		text = text or ""
		return { kind = "heading", level = level, text = text, slug = slugify(text) }
	end
	local imgAlt, imgURL = line:match("^!%[(.-)%]%((.-)%)%s*$")
	if imgURL and imgURL:match("^https?://") then
		return { kind = "image", alt = imgAlt or "", url = imgURL }
	end
	local bullet = line:match("^[%-%*]%s+(.*)$")
	if bullet then
		return { kind = "bullet", text = bullet }
	end
	if line:match("^%s*$") then
		return { kind = "blank" }
	end
	return { kind = "paragraph", text = line }
end

-- Split a `| a | b |` row into trimmed cells.
local function parseTableRow(line)
	local body = line:match("^|(.*)|%s*$") or line:match("^|(.*)$") or line
	local cells = {}
	for cell in (body .. "|"):gmatch("([^|]*)|") do
		cells[#cells + 1] = cell:match("^%s*(.-)%s*$") or cell
	end
	-- Trailing empty cell from the closing pipe; strip when caused by `| a | b |`.
	if cells[#cells] == "" then cells[#cells] = nil end
	return cells
end

local function isTableSeparator(line)
	return line and line:match("^|?[%s%-:|]+|?%s*$") and line:find("%-")
end

function MarkdownRender.parse(text)
	text = applyUnicodeFallbacks(text)
	local lines = {}
	for line in (text .. "\n"):gmatch("([^\n]*)\n") do
		lines[#lines + 1] = line
	end
	local nodes = {}
	local i = 1
	while i <= #lines do
		local line = lines[i]
		if line:match("^```") then
			-- Fenced code block
			local body = {}
			i = i + 1
			while i <= #lines and not lines[i]:match("^```") do
				body[#body + 1] = lines[i]
				i = i + 1
			end
			nodes[#nodes + 1] = { kind = "code", lines = body }
			i = i + 1 -- skip closing fence (or EOF)
		elseif line:match("^|") and isTableSeparator(lines[i + 1]) then
			-- Table: header, separator, then rows
			local header = parseTableRow(line)
			i = i + 2
			local rows = {}
			while i <= #lines and lines[i]:match("^|") do
				rows[#rows + 1] = parseTableRow(lines[i])
				i = i + 1
			end
			nodes[#nodes + 1] = { kind = "table", header = header, rows = rows }
		elseif line:match("^>") then
			-- Blockquote: consecutive `>` lines
			local body = {}
			while i <= #lines and lines[i]:match("^>") do
				body[#body + 1] = lines[i]:match("^>%s?(.*)$") or ""
				i = i + 1
			end
			nodes[#nodes + 1] = { kind = "quote", lines = body }
		else
			nodes[#nodes + 1] = parseSimpleBlock(line)
			i = i + 1
		end
	end
	-- Stash a flat heading list so [[TOC]] nodes can render the index without
	-- re-traversing parsed nodes per frame.
	local headings = {}
	for _, node in ipairs(nodes) do
		if node.kind == "heading" and node.slug and node.slug ~= "" then
			headings[#headings + 1] = node
		end
	end
	nodes.headings = headings
	return nodes
end

-- Tokenize an inline string into a list of spans.
-- Span types: text, bold, italic, code, link, loadout
local function tokenizeInline(str)
	local spans = {}
	local i = 1
	local n = #str
	local plain = {}
	local function flushPlain()
		if #plain > 0 then
			spans[#spans + 1] = { kind = "text", text = table.concat(plain) }
			plain = {}
		end
	end
	while i <= n do
		local c1 = str:sub(i, i)
		local c2 = str:sub(i, i + 1)
		if c2 == "[[" then
			local close = str:find("]]", i + 2, true)
			if close then
				local inner = str:sub(i + 2, close - 1)
				local target = inner:match("^[Ll]oadout%s*:%s*(.+)$") or inner:match("^[Tt]ree%s*:%s*(.+)$")
				if target then
					flushPlain()
					spans[#spans + 1] = { kind = "loadout", text = inner, target = target }
					i = close + 2
				else
					plain[#plain + 1] = c1
					i = i + 1
				end
			else
				plain[#plain + 1] = c1
				i = i + 1
			end
		elseif c1 == "[" then
			local labelEnd = str:find("]", i + 1, true)
			if labelEnd and str:sub(labelEnd + 1, labelEnd + 1) == "(" then
				local urlEnd = str:find(")", labelEnd + 2, true)
				if urlEnd then
					local label = str:sub(i + 1, labelEnd - 1)
					local url = str:sub(labelEnd + 2, urlEnd - 1)
					flushPlain()
					spans[#spans + 1] = { kind = "link", text = label, target = url }
					i = urlEnd + 1
				else
					plain[#plain + 1] = c1
					i = i + 1
				end
			else
				plain[#plain + 1] = c1
				i = i + 1
			end
		elseif c2 == "**" then
			local close = str:find("**", i + 2, true)
			if close then
				flushPlain()
				spans[#spans + 1] = { kind = "bold", text = str:sub(i + 2, close - 1) }
				i = close + 2
			else
				plain[#plain + 1] = c1
				i = i + 1
			end
		elseif c1 == "*" and str:sub(i + 1, i + 1) ~= "*" then
			local close = str:find("*", i + 1, true)
			if close and str:sub(close + 1, close + 1) ~= "*" then
				flushPlain()
				spans[#spans + 1] = { kind = "italic", text = str:sub(i + 1, close - 1) }
				i = close + 1
			else
				plain[#plain + 1] = c1
				i = i + 1
			end
		elseif c1 == "`" then
			local close = str:find("`", i + 1, true)
			if close then
				flushPlain()
				spans[#spans + 1] = { kind = "code", text = str:sub(i + 1, close - 1) }
				i = close + 1
			else
				plain[#plain + 1] = c1
				i = i + 1
			end
		else
			plain[#plain + 1] = c1
			i = i + 1
		end
	end
	flushPlain()
	return spans
end

local function spanColor(kind)
	if kind == "bold" then return BOLD_COLOR end
	if kind == "italic" then return ITALIC_COLOR end
	if kind == "code" then return CODE_TEXT_COLOR end
	if kind == "link" then return LINK_COLOR end
	if kind == "loadout" then return LOADOUT_COLOR end
	return nil
end

-- Render a list of spans on one line. Returns total width and hotspot list.
local function renderSpans(spans, x, y, height, defaultColor)
	local cursorX = x
	local hotspots = {}
	for _, span in ipairs(spans) do
		local color = spanColor(span.kind) or defaultColor
		local text = color .. span.text
		local w = DrawStringWidth(height, FONT, text)
		if span.kind == "code" then
			SetDrawColor(INLINE_CODE_BG[1], INLINE_CODE_BG[2], INLINE_CODE_BG[3])
			DrawImage(nil, cursorX - 1, y, w + 2, height)
		end
		DrawString(cursorX, y, "LEFT", height, FONT, text)
		if span.kind == "link" or span.kind == "loadout" then
			if span.kind == "loadout" then
				SetDrawColor(0.44, 0.91, 0.49)
			else
				SetDrawColor(0.31, 0.66, 1.0)
			end
			DrawImage(nil, cursorX, y + height - 1, w, 1)
			hotspots[#hotspots + 1] = {
				x = cursorX, y = y, w = w, h = height,
				kind = span.kind, target = span.target,
			}
		end
		cursorX = cursorX + w
	end
	return cursorX - x, hotspots
end

-- Compute table column widths (in pixels). Width includes cell padding.
local function tableColumnWidths(node)
	local cols = #node.header
	for _, row in ipairs(node.rows) do
		if #row > cols then cols = #row end
	end
	local widths = {}
	for ci = 1, cols do widths[ci] = 0 end
	local function consider(row)
		for ci, cell in ipairs(row) do
			local w = DrawStringWidth(LINE_HEIGHT_BODY, FONT, cell)
			if w > widths[ci] then widths[ci] = w end
		end
	end
	consider(node.header)
	for _, row in ipairs(node.rows) do consider(row) end
	for ci = 1, cols do
		widths[ci] = widths[ci] + TABLE_CELL_PAD * 2
	end
	return widths, cols
end

-- Compute the displayed (width, height) for an image given its natural
-- dimensions and the available render width. Maintains aspect ratio,
-- clamped to IMAGE_MAX_W / IMAGE_MAX_H.
local function imageDisplaySize(natW, natH, availW)
	if not natW or not natH or natW <= 0 or natH <= 0 then
		return availW, IMAGE_PLACEHOLDER_H
	end
	local maxW = math.min(IMAGE_MAX_W, availW)
	local w, h = natW, natH
	if w > maxW then
		h = h * (maxW / w)
		w = maxW
	end
	if h > IMAGE_MAX_H then
		w = w * (IMAGE_MAX_H / h)
		h = IMAGE_MAX_H
	end
	return math.floor(w), math.floor(h)
end

-- Render the parsed nodes within (x, y, width). scrollY shifts content upward.
-- Returns total content height, hotspot list, and an anchors map (slug -> y
-- offset relative to content origin) for internal anchor link navigation.
function MarkdownRender.render(nodes, x, y, width, scrollY)
	scrollY = scrollY or 0
	local cursorY = y - scrollY
	local contentOriginY = y - scrollY
	local hotspots = {}
	local anchors = {}
	for _, node in ipairs(nodes) do
		if node.kind == "blank" then
			cursorY = cursorY + LINE_HEIGHT_BODY
		elseif node.kind == "heading" then
			cursorY = cursorY + HEADING_GAP_TOP
			local size = HEADING_SIZES[node.level] or HEADING_SIZES[3]
			if node.slug and node.slug ~= "" then
				anchors[node.slug] = cursorY - contentOriginY
			end
			local spans = tokenizeInline(node.text)
			local _, h = renderSpans(spans, x, cursorY, size, HEADING_COLOR)
			for _, hs in ipairs(h) do hotspots[#hotspots + 1] = hs end
			cursorY = cursorY + size + HEADING_GAP_BOTTOM
		elseif node.kind == "bullet" then
			SetDrawColor(0.53, 0.53, 0.53)
			DrawString(x, cursorY, "LEFT", LINE_HEIGHT_BODY, FONT, BULLET_GLYPH_COLOR .. "-")
			local spans = tokenizeInline(node.text)
			local _, h = renderSpans(spans, x + BULLET_INDENT, cursorY, LINE_HEIGHT_BODY, BODY_COLOR)
			for _, hs in ipairs(h) do hotspots[#hotspots + 1] = hs end
			cursorY = cursorY + LINE_HEIGHT_BODY
		elseif node.kind == "paragraph" then
			local spans = tokenizeInline(node.text)
			local _, h = renderSpans(spans, x, cursorY, LINE_HEIGHT_BODY, BODY_COLOR)
			for _, hs in ipairs(h) do hotspots[#hotspots + 1] = hs end
			cursorY = cursorY + LINE_HEIGHT_BODY + PARAGRAPH_GAP
		elseif node.kind == "code" then
			local lineCount = #node.lines
			local blockH = lineCount * CODE_LINE_HEIGHT + CODE_PADDING * 2
			SetDrawColor(CODE_BG[1], CODE_BG[2], CODE_BG[3])
			DrawImage(nil, x, cursorY, width, blockH)
			for li, codeLine in ipairs(node.lines) do
				DrawString(x + CODE_PADDING, cursorY + CODE_PADDING + (li - 1) * CODE_LINE_HEIGHT,
					"LEFT", CODE_LINE_HEIGHT, CODE_FONT, CODE_TEXT_COLOR .. codeLine)
			end
			cursorY = cursorY + blockH + PARAGRAPH_GAP
		elseif node.kind == "quote" then
			local lineCount = #node.lines
			local blockH = lineCount * LINE_HEIGHT_BODY
			SetDrawColor(QUOTE_BAR[1], QUOTE_BAR[2], QUOTE_BAR[3])
			DrawImage(nil, x, cursorY, 3, blockH)
			for li, qLine in ipairs(node.lines) do
				local spans = tokenizeInline(qLine)
				local _, hsList = renderSpans(spans, x + QUOTE_INDENT, cursorY + (li - 1) * LINE_HEIGHT_BODY,
					LINE_HEIGHT_BODY, QUOTE_TEXT_COLOR)
				for _, hs in ipairs(hsList) do hotspots[#hotspots + 1] = hs end
			end
			cursorY = cursorY + blockH + PARAGRAPH_GAP
		elseif node.kind == "toc" then
			local headings = nodes.headings or {}
			if #headings > 0 then
				local blockH = TOC_PAD * 2 + TOC_HEADER_SIZE + 2 + #headings * TOC_LINE_HEIGHT
				SetDrawColor(0.08, 0.10, 0.14)
				DrawImage(nil, x, cursorY, width, blockH)
				SetDrawColor(0.30, 0.35, 0.45)
				DrawImage(nil, x, cursorY, 3, blockH)
				DrawString(x + TOC_PAD, cursorY + TOC_PAD, "LEFT", TOC_HEADER_SIZE, FONT,
					HEADING_COLOR .. TOC_HEADER_TEXT)
				local lineY = cursorY + TOC_PAD + TOC_HEADER_SIZE + 2
				for _, hn in ipairs(headings) do
					local indent = (math.max(hn.level, 1) - 1) * TOC_INDENT_PER_LEVEL
					local label = LINK_COLOR .. hn.text
					local lineX = x + TOC_PAD + indent
					local w = DrawStringWidth(TOC_LINE_HEIGHT, FONT, label)
					DrawString(lineX, lineY, "LEFT", TOC_LINE_HEIGHT, FONT, label)
					SetDrawColor(0.31, 0.66, 1.0)
					DrawImage(nil, lineX, lineY + TOC_LINE_HEIGHT - 1, w, 1)
					hotspots[#hotspots + 1] = {
						x = lineX, y = lineY, w = w, h = TOC_LINE_HEIGHT,
						kind = "link", target = "#" .. hn.slug,
					}
					lineY = lineY + TOC_LINE_HEIGHT
				end
				cursorY = cursorY + blockH + PARAGRAPH_GAP
			end
		elseif node.kind == "image" then
			local entry = ImageCache.Get(node.url)
			local dispW, dispH
			if entry and entry.state == "loaded" then
				dispW, dispH = imageDisplaySize(entry.w, entry.h, width)
				SetDrawColor(1, 1, 1)
				DrawImage(entry.handle, x, cursorY, dispW, dispH)
			elseif entry and entry.state == "error" then
				dispW, dispH = width, LINE_HEIGHT_BODY * 2
				SetDrawColor(0.20, 0.10, 0.10)
				DrawImage(nil, x, cursorY, dispW, dispH)
				DrawString(x + 8, cursorY + 4, "LEFT", LINE_HEIGHT_BODY, FONT,
					"^xFF8888[image error] " .. (entry.errMsg or "unknown") .. "  " .. node.url)
			else
				dispW, dispH = width, IMAGE_PLACEHOLDER_H
				SetDrawColor(0.12, 0.12, 0.14)
				DrawImage(nil, x, cursorY, dispW, dispH)
				SetDrawColor(0.30, 0.30, 0.35)
				DrawImage(nil, x, cursorY, dispW, 1)
				DrawImage(nil, x, cursorY + dispH - 1, dispW, 1)
				DrawImage(nil, x, cursorY, 1, dispH)
				DrawImage(nil, x + dispW - 1, cursorY, 1, dispH)
				DrawString(x + 8, cursorY + 4, "LEFT", LINE_HEIGHT_BODY, FONT,
					"^x888888Loading image... " .. node.url)
			end
			cursorY = cursorY + dispH + PARAGRAPH_GAP
		elseif node.kind == "table" then
			local widths, cols = tableColumnWidths(node)
			local totalW = 0
			for ci = 1, cols do totalW = totalW + widths[ci] end
			-- Top border
			SetDrawColor(TABLE_BORDER[1], TABLE_BORDER[2], TABLE_BORDER[3])
			DrawImage(nil, x, cursorY, totalW, TABLE_BORDER_THICKNESS)
			cursorY = cursorY + TABLE_BORDER_THICKNESS
			-- Header row
			local cx = x
			for ci = 1, cols do
				local cell = node.header[ci] or ""
				local spans = tokenizeInline(cell)
				renderSpans(spans, cx + TABLE_CELL_PAD, cursorY, LINE_HEIGHT_BODY, TABLE_HEADER_COLOR)
				cx = cx + widths[ci]
			end
			cursorY = cursorY + LINE_HEIGHT_BODY
			-- Header separator
			SetDrawColor(TABLE_BORDER[1], TABLE_BORDER[2], TABLE_BORDER[3])
			DrawImage(nil, x, cursorY, totalW, TABLE_BORDER_THICKNESS)
			cursorY = cursorY + TABLE_BORDER_THICKNESS
			-- Body rows
			for _, row in ipairs(node.rows) do
				cx = x
				for ci = 1, cols do
					local cell = row[ci] or ""
					local spans = tokenizeInline(cell)
					local _, hsList = renderSpans(spans, cx + TABLE_CELL_PAD, cursorY,
						LINE_HEIGHT_BODY, BODY_COLOR)
					for _, hs in ipairs(hsList) do hotspots[#hotspots + 1] = hs end
					cx = cx + widths[ci]
				end
				cursorY = cursorY + LINE_HEIGHT_BODY
			end
			-- Bottom border
			SetDrawColor(TABLE_BORDER[1], TABLE_BORDER[2], TABLE_BORDER[3])
			DrawImage(nil, x, cursorY, totalW, TABLE_BORDER_THICKNESS)
			cursorY = cursorY + TABLE_BORDER_THICKNESS + PARAGRAPH_GAP
		end
	end
	return cursorY - (y - scrollY), hotspots, anchors
end

-- Compute content height + heading anchors map without drawing.
-- Used for scrollbar sizing and `[label](#slug)` navigation.
function MarkdownRender.measure(nodes, availW)
	availW = availW or IMAGE_MAX_W
	local h = 0
	local anchors = {}
	for _, node in ipairs(nodes) do
		if node.kind == "blank" then
			h = h + LINE_HEIGHT_BODY
		elseif node.kind == "heading" then
			local size = HEADING_SIZES[node.level] or HEADING_SIZES[3]
			h = h + HEADING_GAP_TOP
			if node.slug and node.slug ~= "" then anchors[node.slug] = h end
			h = h + size + HEADING_GAP_BOTTOM
		elseif node.kind == "bullet" or node.kind == "paragraph" then
			h = h + LINE_HEIGHT_BODY + PARAGRAPH_GAP
		elseif node.kind == "code" then
			h = h + #node.lines * CODE_LINE_HEIGHT + CODE_PADDING * 2 + PARAGRAPH_GAP
		elseif node.kind == "quote" then
			h = h + #node.lines * LINE_HEIGHT_BODY + PARAGRAPH_GAP
		elseif node.kind == "toc" then
			local hs = nodes.headings or {}
			if #hs > 0 then
				h = h + TOC_PAD * 2 + TOC_HEADER_SIZE + 2 + #hs * TOC_LINE_HEIGHT + PARAGRAPH_GAP
			end
		elseif node.kind == "image" then
			local entry = ImageCache.Get(node.url)
			if entry and entry.state == "loaded" then
				local _, dispH = imageDisplaySize(entry.w, entry.h, availW)
				h = h + dispH + PARAGRAPH_GAP
			elseif entry and entry.state == "error" then
				h = h + LINE_HEIGHT_BODY * 2 + PARAGRAPH_GAP
			else
				h = h + IMAGE_PLACEHOLDER_H + PARAGRAPH_GAP
			end
		elseif node.kind == "table" then
			h = h + TABLE_BORDER_THICKNESS * 3 + LINE_HEIGHT_BODY + #node.rows * LINE_HEIGHT_BODY + PARAGRAPH_GAP
		end
	end
	return h, anchors
end

return MarkdownRender
