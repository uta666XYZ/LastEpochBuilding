-- Last Epoch Building
-- Class: BlessingGridControl
-- Displays the 10 blessing timeline slots (3-4-3 grid) in the ItemsTab.
-- Clicking a slot opens BlessingsPopup.

local t_insert = table.insert
local m_floor  = math.floor
local m_max    = math.max
local m_min    = math.min

local function blessingIconFile(name)
	return (name:lower():gsub("[^a-z0-9]+", "_"):gsub("_+$", "")) .. ".png"
end

local SLOT_GRID = {
	{tl="Fall of the Outcasts",    row=1},
	{tl="The Stolen Lance",        row=1},
	{tl="The Black Sun",           row=1},
	{tl="Blood, Frost, and Death", row=2},
	{tl="Ending the Storm",        row=2},
	{tl="Fall of the Empire",      row=2},
	{tl="Reign of Dragons",        row=2},
	{tl="The Last Ruin",           row=3},
	{tl="The Age of Winter",       row=3},
	{tl="Spirits of Fire",         row=3},
}

local SLOT_SIZE = 65
local SLOT_GAP  = 8

-- Compute slot positions relative to this control's top-left
local function computeSlotPositions(controlW)
	local rowSlots = {{}, {}, {}}
	for _, s in ipairs(SLOT_GRID) do
		t_insert(rowSlots[s.row], s)
	end
	local pos  = {}
	local rowY = {4, 4 + SLOT_SIZE + SLOT_GAP, 4 + (SLOT_SIZE + SLOT_GAP) * 2}
	for r = 1, 3 do
		local slots  = rowSlots[r]
		local n      = #slots
		local totalW = n * SLOT_SIZE + (n - 1) * SLOT_GAP
		local startX = m_floor((controlW - totalW) / 2)
		for i, s in ipairs(slots) do
			pos[s.tl] = {
				x = startX + (i - 1) * (SLOT_SIZE + SLOT_GAP),
				y = rowY[r],
			}
		end
	end
	return pos
end

local BlessingGridControlClass = newClass("BlessingGridControl", "Control", "TooltipHost",
	function(self, anchor, x, y, itemsTab)
		-- Width wide enough for 4-slot row + padding
		local w = 4 * SLOT_SIZE + 3 * SLOT_GAP + 8
		local h = 3 * SLOT_SIZE + 2 * SLOT_GAP + 8
		self.Control(anchor, x, y, w, h)
		self.TooltipHost()
		self.itemsTab     = itemsTab
		self.slotPos      = computeSlotPositions(w)
		self.hovered      = nil
		self.imageHandles = {}
	end
)

function BlessingGridControlClass:GetBlessingImage(name)
	if not name then return nil end
	local fname = blessingIconFile(name)
	if not self.imageHandles[fname] then
		local h = NewImageHandle()
		h:Load("Assets/blessings/" .. fname, "ASYNC")
		self.imageHandles[fname] = h
	end
	return self.imageHandles[fname]
end

function BlessingGridControlClass:GetCircleMask()
	if not self.imageHandles["__mask"] then
		local h = NewImageHandle()
		h:Load("Assets/blessings/circle_mask.png", "ASYNC")
		self.imageHandles["__mask"] = h
	end
	return self.imageHandles["__mask"]
end

-- circle_fill.png: opaque circle, transparent corners (inverse of circle_mask)
-- Used to STAMP a colour only inside the circle area without touching outside
function BlessingGridControlClass:GetCircleFill()
	if not self.imageHandles["__fill"] then
		local h = NewImageHandle()
		h:Load("Assets/blessings/circle_fill.png", "ASYNC")
		self.imageHandles["__fill"] = h
	end
	return self.imageHandles["__fill"]
end

function BlessingGridControlClass:IsMouseOver()
	if not self:IsShown() then return false end
	return self:IsMouseInBounds()
end

function BlessingGridControlClass:GetHoveredTL()
	local cx, cy = self:GetPos()
	local mx, my = GetCursorPos()
	for _, sg in ipairs(SLOT_GRID) do
		local sp = self.slotPos[sg.tl]
		local sx = cx + sp.x
		local sy = cy + sp.y
		if mx >= sx and mx < sx + SLOT_SIZE and my >= sy and my < sy + SLOT_SIZE then
			return sg.tl
		end
	end
	return nil
end

-- Panel background colour (matches ItemsTab dark background)
local PANEL_BG_R, PANEL_BG_G, PANEL_BG_B = 0.05, 0.05, 0.07

-- Slot proportions matching lastepochtools.com (outer60, inner48, icon40)
-- Scaled to SLOT_SIZE=66: ring=7px each side, icon_pad=8
local RING_W   = 1   -- outer-to-inner gap (pixels each side)
local ICON_PAD = 1   -- icon inset from outer edge

-- Drawing strategy (two masks):
--   circle_mask.png : opaque corners, transparent circle  → erase corners of outer ring square
--   circle_fill.png : transparent corners, opaque circle  → stamp fill/icon only inside circle

function BlessingGridControlClass:Draw(viewPort)
	local cx, cy    = self:GetPos()
	local slots     = self.itemsTab.slots
	local items     = self.itemsTab.items
	local hoveredTL = self:GetHoveredTL()
	local cmask     = self:GetCircleMask()   -- corners=opaque, circle=transparent
	local cfill     = self:GetCircleFill()   -- corners=transparent, circle=opaque

	for _, sg in ipairs(SLOT_GRID) do
		local tl  = sg.tl
		local sp  = self.slotPos[tl]
		local sx  = cx + sp.x
		local sy  = cy + sp.y

		local slot        = slots[tl]
		local hasBlessing = slot and slot.selItemId and slot.selItemId < 0
		local hov         = (hoveredTL == tl)

		-- Ring colour (outer annulus)
		local brR, brG, brB
		if hov then
			brR, brG, brB = 0.70, 0.58, 0.22
		elseif hasBlessing then
			brR, brG, brB = 0.52, 0.40, 0.14
		else
			brR, brG, brB = 0.22, 0.20, 0.16   -- rgb(56,52,40) like letools
		end

		-- Inner fill: nearly black (#060606)
		local fillR, fillG, fillB = 0.024, 0.024, 0.024

		-- Step A: outer ring circle
		--   Draw ring-colour square, then erase corners with panel_bg → ring circle remains
		SetDrawColor(brR, brG, brB)
		DrawImage(nil, sx, sy, SLOT_SIZE, SLOT_SIZE)
		if cmask and cmask:IsValid() then
			SetDrawColor(PANEL_BG_R, PANEL_BG_G, PANEL_BG_B)
			DrawImage(cmask, sx, sy, SLOT_SIZE, SLOT_SIZE)
		end

		-- Step B: inner fill circle
		--   Use circle_fill to STAMP dark colour only inside the inner circle.
		--   This does NOT touch pixels outside the inner circle, so the outer ring is preserved.
		local fx  = sx + RING_W
		local fy  = sy + RING_W
		local fsz = SLOT_SIZE - RING_W * 2
		if cfill and cfill:IsValid() then
			SetDrawColor(fillR, fillG, fillB)
			DrawImage(cfill, fx, fy, fsz, fsz)
		else
			-- Fallback when fill not yet loaded: stamp with mask approach
			SetDrawColor(fillR, fillG, fillB)
			DrawImage(nil, fx, fy, fsz, fsz)
			if cmask and cmask:IsValid() then
				SetDrawColor(PANEL_BG_R, PANEL_BG_G, PANEL_BG_B)
				DrawImage(cmask, fx, fy, fsz, fsz)
			end
		end

		-- Step C: icon or placeholder
		if hasBlessing then
			local item  = items[slot.selItemId]
			local iname = item and item.name
			local img   = iname and self:GetBlessingImage(iname)
			local isz   = SLOT_SIZE - ICON_PAD * 2
			if img and img:IsValid() then
				SetDrawColor(1, 1, 1)
				DrawImage(img, sx + ICON_PAD, sy + ICON_PAD, isz, isz)
				-- Clip icon to circle using fill mask
				if cfill and cfill:IsValid() then
					-- Icon already inside inner circle area; no extra clip needed
				end
			else
				-- Fallback text
				local abbr = iname and iname:sub(1, 2):upper() or "??"
				SetDrawColor(1, 1, 1)
				DrawString(sx + m_floor(SLOT_SIZE / 2), sy + m_floor(SLOT_SIZE / 2) - 7,
					"CENTER_X", 11, "VAR", "^xAACC88" .. abbr)
			end
		else
			-- "+" symbol
			local mid = m_floor(SLOT_SIZE / 2)
			local arm = 8
			local th  = 2
			if hov then
				SetDrawColor(0.65, 0.52, 0.20)
			else
				SetDrawColor(0.30, 0.28, 0.18)
			end
			DrawImage(nil, sx + mid - m_floor(th / 2), sy + mid - arm, th, arm * 2)
			DrawImage(nil, sx + mid - arm, sy + mid - m_floor(th / 2), arm * 2, th)
		end

		-- Record hovered slot position for tooltip (drawn after loop)
		if hov then
			self._hovTooltipSX = sx
			self._hovTooltipSY = sy
			self._hovTooltipTL = tl
		end
	end

	-- Draw tooltip on top (after all slots, so it's not covered)
	local hsl = self._hovTooltipTL
	if hsl and hoveredTL == hsl then
		local blessingData = self.itemsTab.blessingData
		local tlData = blessingData and blessingData[hsl]
		local hslot = slots[hsl]
		local item2 = hslot and hslot.selItemId and hslot.selItemId < 0 and items[hslot.selItemId]
		self.tooltip:Clear()
		self.tooltip.maxWidth = 300
		if item2 then
			self.tooltip:AddLine(14, "^xC8A040" .. item2.name:upper())
			if item2.implicitModLines and #item2.implicitModLines > 0 then
				for _, modLine in ipairs(item2.implicitModLines) do
					local lineText = modLine.line or modLine.extra or ""
					self.tooltip:AddLine(14, "^xCCCCCC" .. lineText)
				end
			end
		else
			self.tooltip:AddLine(14, "^x888888" .. hsl)
			self.tooltip:AddLine(14, "^x555555Click to select a blessing")
		end
		SetDrawLayer(nil, 100)
		self.tooltip:Draw(self._hovTooltipSX, self._hovTooltipSY, SLOT_SIZE, SLOT_SIZE, viewPort)
		SetDrawLayer(nil, 0)
	else
		self._hovTooltipTL = nil
	end
end

function BlessingGridControlClass:OnKeyDown(key)
	if not self:IsShown() then return end
	if key == "LEFTBUTTON" then
		local tl = self:GetHoveredTL()
		if tl then
			self.itemsTab:EditBlessings(tl)
			return self
		end
	end
end

function BlessingGridControlClass:OnKeyUp(key)
end
