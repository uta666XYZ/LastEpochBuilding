-- Last Epoch Building
--
-- Module: Notes Tab
-- Notes tab for the current build.
--
local t_insert = table.insert
local MarkdownRender = LoadModule("Modules/MarkdownRender")
local NotesImageCache = LoadModule("Modules/NotesImageCache")

local NotesTabClass = newClass("NotesTab", "ControlHost", "Control", function(self, build)
	self.ControlHost()
	self.Control()

	self.build = build

	self.lastContent = ""
	self.showColorCodes = false
	self.previewMode = false
	self.previewScroll = 0
	self.previewHotspots = {}
	self.previewAnchors = {}

	-- Async image loads change content height; invalidate the parse cache so
	-- measure() runs again and the scrollbar picks up the new dimensions.
	NotesImageCache.OnInvalidation(function()
		self.cachedPreviewSource = nil
	end)

	-- Row 1: rarity colors
	local rarityRow = {
		{ key = "normal", label = "NORMAL", color = colorCodes.NORMAL },
		{ key = "magic",  label = "MAGIC",  color = colorCodes.MAGIC },
		{ key = "rare",   label = "RARE",   color = colorCodes.RARE },
		{ key = "set",    label = "SET",    color = colorCodes.SET },
		{ key = "unique", label = "UNIQUE", color = colorCodes.UNIQUE },
	}
	self.controls.normal = new("ButtonControl", {"TOPLEFT",self,"TOPLEFT"}, 8, 8, 100, 18, rarityRow[1].color..rarityRow[1].label, function() self:SetColor(rarityRow[1].color) end)
	for i = 2, #rarityRow do
		local entry = rarityRow[i]
		self.controls[entry.key] = new("ButtonControl", {"TOPLEFT",self.controls.normal,"TOPLEFT"}, 120 * (i - 1), 0, 100, 18, entry.color..entry.label, function() self:SetColor(entry.color) end)
	end

	-- Row 2: damage types
	for i, damageType in ipairs(DamageTypes) do
		self.controls[damageType:lower()] = new("ButtonControl", {"TOPLEFT",self.controls.normal,"TOPLEFT"}, 120 * (i - 1), 18, 100, 18, DamageTypesColored[i]:upper(), function() self:SetColor(DamageTypeColors[i]) end)
	end

	-- Row 3: attributes + default
	for i, longAttr in ipairs(LongAttributes) do
		local color = colorCodes[longAttr:upper()]
		self.controls[longAttr:lower()] = new("ButtonControl", {"TOPLEFT",self.controls.normal,"TOPLEFT"}, 120 * (i - 1), 36, 100, 18, color..longAttr:upper(), function() self:SetColor(color) end)
	end
	self.controls.default = new("ButtonControl", {"TOPLEFT",self.controls.normal,"TOPLEFT"}, 120 * #LongAttributes, 36, 100, 18, "^7DEFAULT", function() self:SetColor("^7") end)

	self.controls.edit = new("EditControl", {"TOPLEFT",self.controls.normal,"TOPLEFT"}, 0, 92, 0, 0, "", nil, "^%C\t\n", nil, nil, 16, true)
	self.controls.edit.width = function()
		return self.width - 16
	end
	self.controls.edit.height = function()
		return self.height - 170
	end
	-- Default 3-line wheel step feels sluggish on long Notes; bump to ~6 lines.
	self.controls.edit.controls.scrollBarV.step = 96
	-- Apply persisted user font scale (Ctrl+Wheel / Ctrl+/-/0 zoom). Wrap ZoomText
	-- so any zoom (from EditControl's own wheel/key bindings or our preview-mode
	-- forwarding) writes back to main.notesFontScale on the next save.
	local edit = self.controls.edit
	local savedScale = main.notesFontScale or 1.0
	if savedScale ~= 1.0 and edit.defaultLineHeight then
		edit.lineHeight = math.floor(edit.defaultLineHeight * savedScale + 0.5)
	end
	local origZoom = edit.ZoomText
	edit.ZoomText = function(ctrl, zoom)
		origZoom(ctrl, zoom)
		if ctrl.defaultLineHeight and ctrl.defaultLineHeight > 0 then
			main.notesFontScale = ctrl.lineHeight / ctrl.defaultLineHeight
		end
		self.cachedPreviewSource = nil
	end
	-- Preview-mode scrollbar lives on the right border of the preview rect
	-- (which mirrors the edit rect). Anchored to edit so position tracks
	-- edit's geometry, but IsShown is overridden to bypass the parent-visibility
	-- propagation in Control:IsShown — edit is hidden in preview mode, otherwise
	-- the scrollbar would never appear. We can't use anchor.collapse because
	-- GetPos's collapse branch shortcuts to parent's TOPLEFT, breaking TOPRIGHT
	-- placement.
	self.controls.previewScrollBar = new("ScrollBarControl", {"TOPRIGHT",self.controls.edit,"TOPRIGHT"}, -1, 1, 14, 0, 96, "VERTICAL", true)
	self.controls.previewScrollBar.height = function()
		local _, h = self.controls.edit:GetSize()
		return h - 2 - (self.controls.previewScrollBarH.enabled and 14 or 0)
	end
	self.controls.previewScrollBar.shown = function()
		return self.previewMode and self.controls.previewScrollBar.enabled
	end
	self.controls.previewScrollBar.IsShown = function(ctrl)
		-- Skip parent.IsShown() chain (edit becomes hidden in preview mode).
		return ctrl:GetProperty("shown")
	end
	-- Horizontal counterpart for preview mode: shown when content (e.g. wide
	-- ASCII art in code blocks) overflows the viewport horizontally.
	self.controls.previewScrollBarH = new("ScrollBarControl", {"BOTTOMLEFT",self.controls.edit,"BOTTOMLEFT"}, 1, -1, 0, 14, 60, "HORIZONTAL", true)
	self.controls.previewScrollBarH.width = function()
		local w, _ = self.controls.edit:GetSize()
		return w - 2 - (self.controls.previewScrollBar.enabled and 14 or 0)
	end
	self.controls.previewScrollBarH.shown = function()
		return self.previewMode and self.controls.previewScrollBarH.enabled
	end
	self.controls.previewScrollBarH.IsShown = function(ctrl)
		return ctrl:GetProperty("shown")
	end
	-- Preview / Color Codes toggles, placed below the attribute row (row 3 ends at y=54 from normal).
	self.controls.togglePreview = new("ButtonControl", {"TOPLEFT",self.controls.normal,"TOPLEFT"}, 0, 60, 120, 20, "Preview", function()
		self:SetPreviewMode(not self.previewMode)
	end)
	self.controls.toggleColorCodes = new("ButtonControl", {"TOPLEFT",self.controls.togglePreview,"TOPRIGHT"}, 8, 0, 160, 20, "Show Color Codes", function()
		self.showColorCodes = not self.showColorCodes
		self:SetShowColorCodes(self.showColorCodes)
	end)
	self.controls.markdownHelp = new("ButtonControl", {"TOPLEFT",self.controls.toggleColorCodes,"TOPRIGHT"}, 8, 0, 24, 20, "?", function() end)
	-- Template dropdown — discovers .md files under both built-in
	-- src/Data/NotesTemplates AND the user's NotesTemplates dir, and inserts the
	-- chosen one into the edit buffer. The first row is a no-op label so the
	-- dropdown reads as a menu trigger rather than a current selection.
	self.userTemplateDir = main.userPath .. "NotesTemplates/"
	MakeDir(self.userTemplateDir)
	self:RebuildTemplateList()
	self.controls.templateDrop = new("DropDownControl", {"TOPLEFT",self.controls.markdownHelp,"TOPRIGHT"}, 8, 0, 160, 20, self.templateList, function(index, value)
		if not value.file then return end
		local f = io.open(value.file, "r")
		if not f then
			main:OpenMessagePopup("Template", "Could not read " .. value.file)
			self.controls.templateDrop.selIndex = 1
			return
		end
		local body = f:read("*a")
		f:close()
		local apply = function()
			self.controls.edit:SetText(body)
		end
		if self.controls.edit.buf and self.controls.edit.buf:match("%S") then
			main:OpenConfirmPopup("Replace Notes?", "This will replace the current Notes with the selected template.\nUndo (Ctrl+Z) is available.", "Replace", apply)
		else
			apply()
		end
		-- Reset selection so the dropdown stays on "Insert Template...".
		self.controls.templateDrop.selIndex = 1
	end)
	self.controls.saveTemplate = new("ButtonControl", {"TOPLEFT",self.controls.templateDrop,"TOPRIGHT"}, 8, 0, 130, 20, "Save as Template...", function()
		self:OpenSaveTemplatePopup()
	end)
	-- Show the guide tooltip even when the edit control has focus (DrawControls
	-- otherwise suppresses tooltips on non-focused controls).
	self.controls.markdownHelp.forceTooltip = true
	self.controls.markdownHelp.tooltipFunc = function(tooltip)
		tooltip:Clear()
		tooltip:AddLine(18, "^7Markdown Guide")
		tooltip:AddSeparator(8)
		tooltip:AddLine(16, "^7Headings")
		tooltip:AddLine(15, "^x888888# Heading 1   ## Heading 2   ### Heading 3")
		tooltip:AddSeparator(6)
		tooltip:AddLine(16, "^7Inline")
		tooltip:AddLine(15, "^x888888**bold**       ^7-> ^xFFFFFFbold")
		tooltip:AddLine(15, "^x888888*italic*       ^7-> ^xBFD6E0italic^x888888 (soft tint)")
		tooltip:AddLine(15, "^x888888`inline code`  ^7-> highlighted monospace")
		tooltip:AddSeparator(6)
		tooltip:AddLine(16, "^7Lists / Quotes")
		tooltip:AddLine(15, "^x888888- item        ^7or  ^x888888* item")
		tooltip:AddLine(15, "^x888888> blockquote  ^7-> bordered side bar")
		tooltip:AddSeparator(6)
		tooltip:AddLine(16, "^7Code blocks (preserves whitespace; no Markdown parsing inside)")
		tooltip:AddLine(15, "^x888888```")
		tooltip:AddLine(15, "^x888888ASCII art / multi-line code")
		tooltip:AddLine(15, "^x888888```")
		tooltip:AddSeparator(6)
		tooltip:AddLine(16, "^7Tables")
		tooltip:AddLine(15, "^x888888| Col A | Col B |")
		tooltip:AddLine(15, "^x888888|-------|-------|")
		tooltip:AddLine(15, "^x888888| cell  | cell  |")
		tooltip:AddSeparator(6)
		tooltip:AddLine(16, "^7Links")
		tooltip:AddLine(15, "^x888888[label](https://...)   ^7-> opens in browser")
		tooltip:AddLine(15, "^x888888[label](#section-slug) ^7-> jumps to heading in preview")
		tooltip:AddLine(15, "^x888888[[Loadout: Name]]      ^7-> switches to that loadout (Tree+Items+Skills+Config)")
		tooltip:AddLine(15, "^x888888[[Tree: Name]]         ^7-> switches passive tree spec only")
		tooltip:AddLine(15, "^x888888[[TOC]]               ^7-> auto index of all headings")
		tooltip:AddSeparator(6)
		tooltip:AddLine(16, "^7Images (auto-cached + downsized to fit)")
		tooltip:AddLine(15, "^x888888![alt](https://...png)        ^7-> remote (cached on disk)")
		tooltip:AddLine(15, "^x888888![alt](file:///C:/path/x.png) ^7-> local absolute")
		tooltip:AddLine(15, "^x888888![alt](docs/Pointing.jpg)     ^7-> relative to LEB script root")
		tooltip:AddSeparator(6)
		tooltip:AddLine(16, "^7Color codes (work in Edit and Preview)")
		tooltip:AddLine(15, "^x888888^^xRRGGBB        ^7hex color, e.g. ^xFF6B6B^^xFF6B6Bred")
		tooltip:AddLine(15, "^x888888^^0..^^9          ^7preset palette (^^7 = default)")
		tooltip:AddSeparator(6)
		tooltip:AddLine(16, "^7Preview controls")
		tooltip:AddLine(15, "^x888888Wheel              ^7-> scroll vertically")
		tooltip:AddLine(15, "^x888888Shift+Wheel        ^7-> scroll horizontally")
		tooltip:AddLine(15, "^x888888Ctrl+Wheel / Ctrl+/-/0 ^7-> font zoom (persisted)")
		tooltip:AddLine(15, "^x888888Edit <-> Preview   ^7-> scroll position is preserved")
		tooltip:AddSeparator(6)
		tooltip:AddLine(16, "^x888888Tip: toggle ^7Preview^x888888 to render. ^7Show Color Codes^x888888 reveals raw ^^x markers for editing.")
	end
	-- Place the tooltip to the upper-right of the button so it doesn't overlap
	-- the edit area below where the user is typing.
	self.controls.markdownHelp.DrawTooltip = function(ctrl, x, y, width, height, viewPort)
		if not ctrl.tooltipFunc then return end
		ctrl.tooltipFunc(ctrl.tooltip)
		local ttW, ttH = ctrl.tooltip:GetSize()
		local ttX = x + width + 5
		if ttX + ttW > viewPort.x + viewPort.width then
			ttX = math.max(viewPort.x, viewPort.x + viewPort.width - ttW)
		end
		local ttY = y - ttH - 2
		if ttY < viewPort.y then ttY = viewPort.y end
		ctrl.tooltip:Draw(ttX, ttY, nil, nil, viewPort)
	end
	self:SelectControl(self.controls.edit)
end)

-- Normalize toggle-form color codes (^_x... / ^_N) back to live form so the renderer
-- shows actual colors when the user has "Show Color Codes" enabled. Live ^x / ^N
-- are kept intact and pass through into DrawString unchanged.
local function normalizeColorCodes(s)
	return (s:gsub("%^_x(%x%x%x%x%x%x)", "^x%1"):gsub("%^_(%d)", "^%1"))
end

-- Build the preview cache (parse + measure) without drawing. Needed when the
-- mode toggle wants to compute scroll mappings before the next DrawPreview pass.
function NotesTabClass:EnsurePreviewCache()
	local edit = self.controls.edit
	local source = normalizeColorCodes(edit.buf or "")
	local scale = 1.0
	if edit.defaultLineHeight and edit.defaultLineHeight > 0 and edit.lineHeight then
		scale = edit.lineHeight / edit.defaultLineHeight
	end
	local _, _, w, h = self:GetPreviewArea()
	local availW = (w or 0) - 12
	if availW <= 0 then availW = 400 end
	if source ~= self.cachedPreviewSource or scale ~= self.cachedPreviewScale then
		self.cachedPreviewSource = source
		self.cachedPreviewScale = scale
		self.cachedPreviewNodes = MarkdownRender.parse(source)
		self.cachedPreviewContentH, self.cachedPreviewAnchors, self.cachedPreviewContentW, self.cachedPreviewNodeYs =
			MarkdownRender.measure(self.cachedPreviewNodes, availW, scale)
	end
end

-- Find the index of the node whose source range covers `line` (1-based).
-- Returns the last node with srcLine <= line; falls back to 1.
local function nodeIndexForSrcLine(nodes, line)
	if not nodes or #nodes == 0 then return 1 end
	local best = 1
	for idx, node in ipairs(nodes) do
		if node.srcLine and node.srcLine <= line then
			best = idx
		else
			break
		end
	end
	return best
end

-- Inverse: find the node currently at the top of the preview viewport.
local function nodeIndexForY(nodeYs, y)
	if not nodeYs or #nodeYs == 0 then return 1 end
	local best = 1
	for idx, ny in ipairs(nodeYs) do
		if ny <= y then
			best = idx
		else
			break
		end
	end
	return best
end

function NotesTabClass:SetPreviewMode(setting)
	if setting == self.previewMode then return end
	-- Geometry-dependent scroll mapping only works after NotesTab has been
	-- drawn at least once (so self.width / edit:GetSize() are valid).
	-- Toggling at Load time (previewOnLoad="true") happens before that — fall
	-- back to the simple top-of-document behavior in that case.
	local geometryReady = self.width and self.height
	if setting then
		local topLine, edit, lh
		if geometryReady then
			edit = self.controls.edit
			lh = edit.lineHeight or edit.defaultLineHeight or 16
			topLine = math.floor((edit.controls.scrollBarV.offset or 0) / lh) + 1
		end
		self.previewMode = true
		self.controls.togglePreview.label = "Edit"
		self.controls.edit.shown = false
		self.previewHotspots = {}
		if geometryReady then
			self:EnsurePreviewCache()
			local idx = nodeIndexForSrcLine(self.cachedPreviewNodes, topLine)
			local targetY = (self.cachedPreviewNodeYs and self.cachedPreviewNodeYs[idx]) or 0
			local _, _, _, ph = self:GetPreviewArea()
			local viewH = (ph or 0) - 12
			if viewH < 1 then viewH = 1 end
			self.controls.previewScrollBar:SetContentDimension(self.cachedPreviewContentH or 0, viewH)
			self.controls.previewScrollBar:SetOffset(targetY)
			self.previewScroll = self.controls.previewScrollBar.offset
		else
			self.previewScroll = 0
		end
	else
		local srcLine = 1
		if geometryReady and self.cachedPreviewNodeYs and self.cachedPreviewNodes then
			local topY = self.previewScroll or 0
			local idx = nodeIndexForY(self.cachedPreviewNodeYs, topY)
			local node = self.cachedPreviewNodes[idx]
			srcLine = (node and node.srcLine) or 1
		end
		self.previewMode = false
		self.controls.togglePreview.label = "Preview"
		self.controls.edit.shown = true
		if geometryReady then
			local edit = self.controls.edit
			local lh = edit.lineHeight or edit.defaultLineHeight or 16
			edit.controls.scrollBarV.offset = (srcLine - 1) * lh
		end
	end
end

function NotesTabClass:GetPreviewArea()
	-- Match the EditControl rectangle so toggling between modes doesn't shift layout.
	local edit = self.controls.edit
	local x, y = edit:GetPos()
	local w, h = edit:GetSize()
	return x, y, w, h
end

function NotesTabClass:HandlePreviewClick(cursorX, cursorY)
	for _, hs in ipairs(self.previewHotspots) do
		if cursorX >= hs.x and cursorX < hs.x + hs.w and cursorY >= hs.y and cursorY < hs.y + hs.h then
			if hs.kind == "link" and hs.target and hs.target:sub(1, 1) == "#" then
				local slug = hs.target:sub(2)
				local targetY = self.previewAnchors and self.previewAnchors[slug]
				if targetY then
					self.controls.previewScrollBar:SetOffset(targetY)
				end
			elseif hs.kind == "link" and hs.target and hs.target:match("^[a-z]+://") then
				OpenURL(hs.target)
			elseif hs.kind == "loadout" then
				if self.build.SwitchLoadout and self.build:SwitchLoadout(hs.target) then
					self.build.viewMode = "TREE"
				else
					main:OpenMessagePopup("Loadout not found", "No loadout named '" .. hs.target .. "'.\nUse the Loadouts dropdown → New Loadout to create one, then reference it from Notes.")
				end
			elseif hs.kind == "tree" then
				local treeTab = self.build and self.build.treeTab
				if treeTab and treeTab.SetActiveSpecByName and treeTab:SetActiveSpecByName(hs.target) then
					self.build.viewMode = "TREE"
				else
					main:OpenMessagePopup("Tree spec not found", "No passive tree spec named '" .. hs.target .. "'.\nGo to the Tree tab and use the spec dropdown → Manage... to create one.")
				end
			end
			return true
		end
	end
	return false
end

function NotesTabClass:DrawPreview(viewPort)
	local x, y, w, h = self:GetPreviewArea()
	-- Border + background to match EditControl visual.
	SetDrawColor(0.5, 0.5, 0.5)
	DrawImage(nil, x, y, w, h)
	SetDrawColor(0, 0, 0)
	DrawImage(nil, x + 1, y + 1, w - 2, h - 2)

	local pad = 6
	local availW = w - pad * 2
	local source = normalizeColorCodes(self.controls.edit.buf or "")
	local scale = 1.0
	local edit = self.controls.edit
	if edit.defaultLineHeight and edit.defaultLineHeight > 0 and edit.lineHeight then
		scale = edit.lineHeight / edit.defaultLineHeight
	end
	-- Reparse only when the source actually changes; per-frame parse becomes
	-- expensive at 1000+ lines. See Obsidian: Development/軽量性維持の原則.md
	-- Also rebuild on scale change so measure() reflects new font size.
	if source ~= self.cachedPreviewSource or scale ~= self.cachedPreviewScale then
		self.cachedPreviewSource = source
		self.cachedPreviewScale = scale
		self.cachedPreviewNodes = MarkdownRender.parse(source)
		self.cachedPreviewContentH, self.cachedPreviewAnchors, self.cachedPreviewContentW, self.cachedPreviewNodeYs =
			MarkdownRender.measure(self.cachedPreviewNodes, availW, scale)
	end
	local nodes = self.cachedPreviewNodes
	local contentH = self.cachedPreviewContentH
	local contentW = self.cachedPreviewContentW or 0
	self.previewAnchors = self.cachedPreviewAnchors or {}

	-- Drive scroll via the scrollbar so wheel + drag share state. Account
	-- for the H bar reserving a slice at the bottom (and vice-versa).
	local hBarShown = contentW > availW
	local viewH = h - pad * 2 - (hBarShown and 14 or 0)
	local vBarShown = contentH > viewH
	local viewW = availW - (vBarShown and 14 or 0)
	-- Recompute hBar with adjusted view to handle the case where the V bar
	-- appearing causes horizontal overflow that wasn't there before.
	hBarShown = contentW > viewW
	viewH = h - pad * 2 - (hBarShown and 14 or 0)
	self.controls.previewScrollBar:SetContentDimension(contentH, viewH)
	self.controls.previewScrollBarH:SetContentDimension(contentW, viewW)
	self.previewScroll = self.controls.previewScrollBar.offset
	local scrollX = self.controls.previewScrollBarH.offset

	SetViewport(x + pad, y + pad, viewW, viewH)
	local _, hotspots = MarkdownRender.render(nodes, 0, 0, viewW, self.previewScroll, scale, scrollX)
	SetViewport()

	-- DrawControls already drew the scrollbars earlier, but the preview's
	-- background rect above overpainted them. Redraw on top so they stay visible.
	if self.controls.previewScrollBar:IsShown() then
		self.controls.previewScrollBar:Draw(viewPort)
	end
	if self.controls.previewScrollBarH:IsShown() then
		self.controls.previewScrollBarH:Draw(viewPort)
	end

	-- Translate hotspot rects from viewport-local to absolute screen coords.
	self.previewHotspots = {}
	for _, hs in ipairs(hotspots) do
		local absY = hs.y + y + pad
		if absY + hs.h > y + pad and absY < y + h - pad then
			self.previewHotspots[#self.previewHotspots + 1] = {
				x = hs.x + x + pad, y = absY, w = hs.w, h = hs.h,
				kind = hs.kind, target = hs.target,
			}
		end
	end

	-- Hover cursor feedback.
	local cx, cy = GetCursorPos()
	for _, hs in ipairs(self.previewHotspots) do
		if cx >= hs.x and cx < hs.x + hs.w and cy >= hs.y and cy < hs.y + hs.h then
			SetDrawLayer(nil, 100)
			SetDrawColor(1, 1, 1, 0.08)
			DrawImage(nil, hs.x, hs.y, hs.w, hs.h)
			SetDrawLayer(nil, 0)
			break
		end
	end
end

function NotesTabClass:SetShowColorCodes(setting)
	self.showColorCodes = setting
	if setting then
		self.controls.toggleColorCodes.label = "Hide Color Codes"
		self.controls.edit.buf = self.controls.edit.buf:gsub("%^x(%x%x%x%x%x%x)","^_x%1"):gsub("%^(%d)","^_%1")
	else
		self.controls.toggleColorCodes.label = "Show Color Codes"
		self.controls.edit.buf = self.controls.edit.buf:gsub("%^_x(%x%x%x%x%x%x)","^x%1"):gsub("%^_(%d)","^%1")
	end
end

function NotesTabClass:SetColor(color)
	local text = color
	if self.showColorCodes then text = color:gsub("%^x(%x%x%x%x%x%x)","^_x%1"):gsub("%^(%d)","^_%1") end
	if self.controls.edit.sel == nil or self.controls.edit.sel == self.controls.edit.caret then
		self.controls.edit:Insert(text)
	else
		local lastColor = self.controls.edit:GetSelText():match(self.showColorCodes and "^.*(%^_x%x%x%x%x%x%x)" or "^.*(%^x%x%x%x%x%x%x)") or "^7"
		self.controls.edit:ReplaceSel(text..self.controls.edit:GetSelText():gsub(self.showColorCodes and "%^_x%x%x%x%x%x%x" or "%^x%x%x%x%x%x%x", "")..lastColor)
	end
end

function NotesTabClass:Load(xml, fileName)
	for _, node in ipairs(xml) do
		if type(node) == "string" then
			self.controls.edit:SetText(node)
		end
	end
	self.lastContent = self.controls.edit.buf
	-- Open in Preview when the build was saved that way and notes have content,
	-- so a recipient sees the rendered guide first instead of raw markdown.
	local previewOnLoad = xml.attrib and xml.attrib.previewOnLoad == "true"
	if previewOnLoad and self.controls.edit.buf and self.controls.edit.buf:match("%S") then
		self:SetPreviewMode(true)
	end
end

function NotesTabClass:Save(xml)
	self:SetShowColorCodes(false)
	xml.attrib = xml.attrib or {}
	xml.attrib.previewOnLoad = self.previewMode and "true" or "false"
	t_insert(xml, self.controls.edit.buf)
	self.lastContent = self.controls.edit.buf
end

function NotesTabClass:Draw(viewPort, inputEvents)
	self.x = viewPort.x
	self.y = viewPort.y
	self.width = viewPort.width
	self.height = viewPort.height

	for id, event in ipairs(inputEvents) do
		if event.type == "KeyDown" then
			if not self.previewMode and event.key == "z" and IsKeyDown("CTRL") then
				self.controls.edit:Undo()
			elseif not self.previewMode and event.key == "y" and IsKeyDown("CTRL") then
				self.controls.edit:Redo()
			elseif self.previewMode and IsKeyDown("CTRL") and (event.key == "+" or event.key == "=") then
				self.controls.edit:ZoomText("+")
			elseif self.previewMode and IsKeyDown("CTRL") and event.key == "-" then
				self.controls.edit:ZoomText("-")
			elseif self.previewMode and IsKeyDown("CTRL") and event.key == "0" then
				self.controls.edit:ZoomText("0")
			elseif self.previewMode and event.key == "WHEELUP" then
				if IsKeyDown("CTRL") then
					self.controls.edit:ZoomText("+")
				elseif IsKeyDown("SHIFT") then
					self.controls.previewScrollBarH:Scroll(-1)
				else
					self.controls.previewScrollBar:Scroll(-1)
				end
			elseif self.previewMode and event.key == "WHEELDOWN" then
				if IsKeyDown("CTRL") then
					self.controls.edit:ZoomText("-")
				elseif IsKeyDown("SHIFT") then
					self.controls.previewScrollBarH:Scroll(1)
				else
					self.controls.previewScrollBar:Scroll(1)
				end
			end
		elseif event.type == "KeyUp" and self.previewMode and event.key == "LEFTBUTTON" then
			local cx, cy = GetCursorPos()
			self:HandlePreviewClick(cx, cy)
		end
	end
	self:ProcessControlsInput(inputEvents, viewPort)

	main:DrawBackground(viewPort)

	self:DrawControls(viewPort)

	if self.previewMode then
		self:DrawPreview(viewPort)
	end

	self.modFlag = (self.lastContent ~= self.controls.edit.buf)
end

-- Build the dropdown list from built-in templates (Data/NotesTemplates) and user
-- templates (main.userPath/NotesTemplates). User templates are prefixed with
-- "[User] " so the source is obvious in the dropdown.
function NotesTabClass:RebuildTemplateList()
	self.templateList = { { label = "Insert Template...", file = nil } }
	-- User templates first so the user's own work surfaces before built-ins.
	local userHandle = NewFileSearch(self.userTemplateDir .. "*.md")
	while userHandle do
		local fileName = userHandle:GetFileName()
		local label = "[User] " .. fileName:gsub("%.md$", "")
		t_insert(self.templateList, { label = label, file = self.userTemplateDir .. fileName })
		if not userHandle:NextFile() then break end
	end
	local handle = NewFileSearch("Data/NotesTemplates/*.md")
	while handle do
		local fileName = handle:GetFileName()
		local label = fileName:gsub("%.md$", ""):gsub("^%l", string.upper)
		t_insert(self.templateList, { label = label, file = "Data/NotesTemplates/" .. fileName })
		if not handle:NextFile() then break end
	end
	if self.controls and self.controls.templateDrop then
		self.controls.templateDrop:SetList(self.templateList)
		self.controls.templateDrop.selIndex = 1
	end
end

-- Save the current Notes buffer as a custom template under main.userPath/NotesTemplates.
-- Always reports the absolute saved path so the user can find / edit / share it.
function NotesTabClass:OpenSaveTemplatePopup()
	local body = self.controls.edit.buf or ""
	if not body:match("%S") then
		main:OpenMessagePopup("Save Template", "Notes are empty. Type something before saving as a template.")
		return
	end
	-- Size the popup to comfortably fit the absolute save path so it never overflows.
	local pathStr = self.userTemplateDir
	local pathW = DrawStringWidth(13, "VAR", pathStr)
	local popupW = math.max(420, pathW + 60)
	local editW = popupW - 40
	local controls = { }
	controls.label = new("LabelControl", nil, 0, 20, 0, 16, "^7Template name:")
	controls.edit = new("EditControl", nil, 0, 40, editW, 22, nil, nil, "\\/:%*%?\"<>|%c", 80, function(buf)
		controls.save.enabled = buf:match("%S") ~= nil
	end)
	controls.pathLabel = new("LabelControl", nil, 0, 72, 0, 13, "^x888888Will save to:")
	controls.path = new("LabelControl", nil, 0, 90, 0, 13, "^x888888" .. pathStr)
	controls.save = new("ButtonControl", nil, -50, 120, 90, 22, "Save", function()
		local name = controls.edit.buf:gsub("^%s+", ""):gsub("%s+$", "")
		if name == "" then return end
		if not name:match("%.md$") then name = name .. ".md" end
		local fullPath = self.userTemplateDir .. name
		local existing = io.open(fullPath, "rb")
		local writeIt = function()
			local f, err = io.open(fullPath, "wb")
			if not f then
				main:OpenMessagePopup("Save Template", "Failed to write template:\n" .. tostring(err))
				return
			end
			f:write(body)
			f:close()
			self:RebuildTemplateList()
			main:OpenMessagePopup("Template Saved", "Saved to:\n" .. fullPath .. "\n\nIt now appears in the Insert Template dropdown as [User] " .. name:gsub("%.md$", "") .. ".")
		end
		main:ClosePopup()
		if existing then
			existing:close()
			main:OpenConfirmPopup("Overwrite?", "A template named '" .. name .. "' already exists.\nOverwrite it?", "Overwrite", writeIt)
		else
			writeIt()
		end
	end)
	controls.save.enabled = false
	controls.cancel = new("ButtonControl", nil, 50, 120, 90, 22, "Cancel", function()
		main:ClosePopup()
	end)
	main:OpenPopup(popupW, 155, "Save as Template", controls, "save", "edit", "cancel")
end
