-- Last Epoch Building
--
-- Module: Notes Tab
-- Notes tab for the current build.
--
local t_insert = table.insert
local MarkdownRender = LoadModule("Modules/MarkdownRender")

local NotesTabClass = newClass("NotesTab", "ControlHost", "Control", function(self, build)
	self.ControlHost()
	self.Control()

	self.build = build

	self.lastContent = ""
	self.showColorCodes = false
	self.previewMode = false
	self.previewScroll = 0
	self.previewHotspots = {}

	local notesDesc = [[^7You can use Ctrl +/- (or Ctrl+Scroll) to zoom in and out and Ctrl+0 to reset.
This field also supports different colors.  Using the caret symbol (^) followed by a Hex code or a number (0-9) will set the color.
Below are some common color codes LEP uses:	]]
	self.controls.notesDesc = new("LabelControl", {"TOPLEFT",self,"TOPLEFT"}, 8, 8, 150, 16, notesDesc)

	-- Row 1: rarity colors
	local rarityRow = {
		{ key = "normal", label = "NORMAL", color = colorCodes.NORMAL },
		{ key = "magic",  label = "MAGIC",  color = colorCodes.MAGIC },
		{ key = "rare",   label = "RARE",   color = colorCodes.RARE },
		{ key = "set",    label = "SET",    color = colorCodes.SET },
		{ key = "unique", label = "UNIQUE", color = colorCodes.UNIQUE },
	}
	self.controls.normal = new("ButtonControl", {"TOPLEFT",self.controls.notesDesc,"TOPLEFT"}, 0, 64, 100, 18, rarityRow[1].color..rarityRow[1].label, function() self:SetColor(rarityRow[1].color) end)
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
	-- Preview / Color Codes toggles, placed below the attribute row (row 3 ends at y=54 from normal).
	self.controls.togglePreview = new("ButtonControl", {"TOPLEFT",self.controls.normal,"TOPLEFT"}, 0, 60, 120, 20, "Preview", function()
		self:SetPreviewMode(not self.previewMode)
	end)
	self.controls.toggleColorCodes = new("ButtonControl", {"TOPLEFT",self.controls.togglePreview,"TOPRIGHT"}, 8, 0, 160, 20, "Show Color Codes", function()
		self.showColorCodes = not self.showColorCodes
		self:SetShowColorCodes(self.showColorCodes)
	end)
	self.controls.markdownHelp = new("ButtonControl", {"TOPLEFT",self.controls.toggleColorCodes,"TOPRIGHT"}, 8, 0, 24, 20, "?", function() end)
	-- Show the guide tooltip even when the edit control has focus (DrawControls
	-- otherwise suppresses tooltips on non-focused controls).
	self.controls.markdownHelp.forceTooltip = true
	self.controls.markdownHelp.tooltipFunc = function(tooltip)
		tooltip:Clear()
		tooltip:AddLine(18, "^7Markdown Guide")
		tooltip:AddSeparator(8)
		tooltip:AddLine(16, "^7Headings")
		tooltip:AddLine(15, "^x888888# Heading 1")
		tooltip:AddLine(15, "^x888888## Heading 2")
		tooltip:AddLine(15, "^x888888### Heading 3")
		tooltip:AddSeparator(6)
		tooltip:AddLine(16, "^7Inline")
		tooltip:AddLine(15, "^x888888**bold**       ^7-> ^xFFFFFFbold")
		tooltip:AddLine(15, "^x888888*italic*       ^7-> not supported")
		tooltip:AddSeparator(6)
		tooltip:AddLine(16, "^7Lists")
		tooltip:AddLine(15, "^x888888- item        ^7or  ^x888888* item")
		tooltip:AddSeparator(6)
		tooltip:AddLine(16, "^7Links")
		tooltip:AddLine(15, "^x888888[label](https://...)   ^7-> opens in browser")
		tooltip:AddLine(15, "^x888888[[Loadout: Name]]      ^7-> switches to that loadout")
		tooltip:AddSeparator(6)
		tooltip:AddLine(16, "^7Color codes (work in Edit and Preview)")
		tooltip:AddLine(15, "^x888888^^xRRGGBB        ^7hex color, e.g. ^xFF6B6B^^xFF6B6Bred")
		tooltip:AddLine(15, "^x888888^^0..^^9          ^7preset palette (^^7 = default)")
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

function NotesTabClass:SetPreviewMode(setting)
	self.previewMode = setting
	if setting then
		self.controls.togglePreview.label = "Edit"
		self.controls.edit.shown = false
		self.previewScroll = 0
		self.previewHotspots = {}
	else
		self.controls.togglePreview.label = "Preview"
		self.controls.edit.shown = true
	end
end

-- Normalize toggle-form color codes (^_x... / ^_N) back to live form so the renderer
-- shows actual colors when the user has "Show Color Codes" enabled. Live ^x / ^N
-- are kept intact and pass through into DrawString unchanged.
local function normalizeColorCodes(s)
	return (s:gsub("%^_x(%x%x%x%x%x%x)", "^x%1"):gsub("%^_(%d)", "^%1"))
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
			if hs.kind == "link" and hs.target and hs.target:match("^[a-z]+://") then
				OpenURL(hs.target)
			elseif hs.kind == "loadout" then
				if self.build.SwitchLoadout and self.build:SwitchLoadout(hs.target) then
					self.build.viewMode = "TREE"
				else
					main:OpenMessagePopup("Loadout not found", "No loadout named '" .. hs.target .. "'.\nUse the Loadouts dropdown → New Loadout to create one, then reference it from Notes.")
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
	local source = normalizeColorCodes(self.controls.edit.buf or "")
	local nodes = MarkdownRender.parse(source)
	local contentH = MarkdownRender.measure(nodes)

	-- Clamp scroll.
	local maxScroll = math.max(0, contentH - (h - pad * 2))
	if self.previewScroll > maxScroll then self.previewScroll = maxScroll end
	if self.previewScroll < 0 then self.previewScroll = 0 end

	SetViewport(x + pad, y + pad, w - pad * 2, h - pad * 2)
	local _, hotspots = MarkdownRender.render(nodes, 0, 0, w - pad * 2, self.previewScroll)
	SetViewport()

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
			elseif self.previewMode and event.key == "WHEELUP" then
				self.previewScroll = math.max(0, (self.previewScroll or 0) - 32)
			elseif self.previewMode and event.key == "WHEELDOWN" then
				self.previewScroll = (self.previewScroll or 0) + 32
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
