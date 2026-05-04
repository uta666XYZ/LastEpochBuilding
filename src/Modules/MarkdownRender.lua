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
--   [label](url) external links (clickable)
--   [[Loadout: name]] loadout placeholders (clickable, currently inert)
--   `^xRRGGBB` / `^0-9` color codes pass through to DrawString.
--
-- Returns hotspot rectangles for click handling.

local MarkdownRender = {}

local LINE_HEIGHT_BODY = 16
-- Bitmap font has crisp glyphs only at certain sizes; 24/20/18 render cleanly
-- whereas 28/22 upscale blurs.
local HEADING_SIZES = { [1] = 24, [2] = 20, [3] = 18 }
local FONT = "VAR"
local BULLET_INDENT = 18
local PARAGRAPH_GAP = 4
local HEADING_GAP_TOP = 10
local HEADING_GAP_BOTTOM = 4

local LINK_COLOR = "^x4FA8FF"
local LOADOUT_COLOR = "^x71E87D"
local BOLD_COLOR = "^xFFFFFF"
-- Bitmap font has no italic glyphs; using a faint contrast tint instead of
-- a strong cyan keeps it readable next to body text.
local ITALIC_COLOR = "^xBFD6E0"
local BODY_COLOR = "^xCCCCCC"
local HEADING_COLOR = "^xFFFFFF"
local BULLET_GLYPH_COLOR = "^x888888"

-- Parse a single block into an AST node.
local function parseBlock(line)
	local heading = line:match("^(#+)%s+(.*)$")
	if heading then
		local level = math.min(#heading, 3)
		local _, _, text = line:find("^#+%s+(.*)$")
		return { kind = "heading", level = level, text = text or "" }
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

function MarkdownRender.parse(text)
	local nodes = {}
	for line in (text .. "\n"):gmatch("([^\n]*)\n") do
		nodes[#nodes + 1] = parseBlock(line)
	end
	return nodes
end

-- Tokenize an inline string into a list of spans.
-- Span types: text, bold, italic, link, loadout
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
		local c3 = str:sub(i, i + 1)
		if c2 == "[[" then
			-- Loadout placeholder
			local close = str:find("]]", i + 2, true)
			if close then
				local inner = str:sub(i + 2, close - 1)
				local target = inner:match("^[Ll]oadout%s*:%s*(.+)$") or inner:match("^[Tt]ree%s*:%s*(.+)$")
				if target then
					flushPlain()
					spans[#spans + 1] = { kind = "loadout", text = inner, target = target }
					i = close + 2
				else
					-- Not a loadout link; treat literally
					plain[#plain + 1] = c1
					i = i + 1
				end
			else
				plain[#plain + 1] = c1
				i = i + 1
			end
		elseif c1 == "[" then
			-- [label](url)
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
		else
			plain[#plain + 1] = c1
			i = i + 1
		end
	end
	flushPlain()
	return spans
end

-- Strip color codes for width measurement (DrawStringWidth respects ^x but we want raw).
local function spanColor(kind)
	if kind == "bold" then return BOLD_COLOR end
	if kind == "italic" then return ITALIC_COLOR end
	if kind == "link" then return LINK_COLOR end
	if kind == "loadout" then return LOADOUT_COLOR end
	return nil
end

-- Render a list of spans on one line, returning total width and a list of hotspots {x,y,w,h,kind,target}.
local function renderSpans(spans, x, y, height, defaultColor)
	local cursorX = x
	local hotspots = {}
	for _, span in ipairs(spans) do
		local color = spanColor(span.kind) or defaultColor
		local text = color .. span.text
		local w = DrawStringWidth(height, FONT, text)
		DrawString(cursorX, y, "LEFT", height, FONT, text)
		if span.kind == "link" or span.kind == "loadout" then
			-- Underline
			SetDrawColor(0.31, 0.66, 1.0)
			if span.kind == "loadout" then
				SetDrawColor(0.44, 0.91, 0.49)
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

-- Render the parsed nodes within (x, y, width).
-- scrollY shifts content upward (>=0).
-- Returns total content height and combined hotspot list.
function MarkdownRender.render(nodes, x, y, width, scrollY)
	scrollY = scrollY or 0
	local cursorY = y - scrollY
	local hotspots = {}
	for _, node in ipairs(nodes) do
		if node.kind == "blank" then
			cursorY = cursorY + LINE_HEIGHT_BODY
		elseif node.kind == "heading" then
			cursorY = cursorY + HEADING_GAP_TOP
			local size = HEADING_SIZES[node.level] or HEADING_SIZES[3]
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
		end
	end
	return cursorY - (y - scrollY), hotspots
end

-- Compute content height without drawing (used for scrollbar sizing).
function MarkdownRender.measure(nodes)
	local h = 0
	for _, node in ipairs(nodes) do
		if node.kind == "blank" then
			h = h + LINE_HEIGHT_BODY
		elseif node.kind == "heading" then
			local size = HEADING_SIZES[node.level] or HEADING_SIZES[3]
			h = h + HEADING_GAP_TOP + size + HEADING_GAP_BOTTOM
		elseif node.kind == "bullet" or node.kind == "paragraph" then
			h = h + LINE_HEIGHT_BODY + PARAGRAPH_GAP
		end
	end
	return h
end

return MarkdownRender
