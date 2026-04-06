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

local SLOT_SIZE = 44
local SLOT_GAP  = 6

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

local BlessingGridControlClass = newClass("BlessingGridControl", "Control",
	function(self, anchor, x, y, itemsTab)
		-- Width wide enough for 4-slot row + padding
		local w = 4 * SLOT_SIZE + 3 * SLOT_GAP + 8  -- 202
		local h = 3 * SLOT_SIZE + 2 * SLOT_GAP + 8  -- 148
		self.Control(anchor, x, y, w, h)
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

function BlessingGridControlClass:Draw(viewPort)
	local cx, cy    = self:GetPos()
	local bst       = self.itemsTab.blessingData
	local slots     = self.itemsTab.slots
	local items     = self.itemsTab.items
	local hoveredTL = self:GetHoveredTL()

	for _, sg in ipairs(SLOT_GRID) do
		local tl = sg.tl
		local sp = self.slotPos[tl]
		local sx = cx + sp.x
		local sy = cy + sp.y

		-- Check if blessing is equipped
		local slot    = slots[tl]
		local hasBlessing = slot and slot.selItemId and slot.selItemId < 0

		local hov = (hoveredTL == tl)

		-- Outer circle (fake by drawing a square with rounded look via border)
		local bgR, bgG, bgB
		if hov then
			bgR, bgG, bgB = 0.22, 0.18, 0.08
		elseif hasBlessing then
			bgR, bgG, bgB = 0.18, 0.13, 0.05
		else
			bgR, bgG, bgB = 0.08, 0.08, 0.10
		end
		SetDrawColor(bgR, bgG, bgB)
		DrawImage(nil, sx, sy, SLOT_SIZE, SLOT_SIZE)

		-- Border (gold ring)
		if hov then
			SetDrawColor(0.65, 0.50, 0.18)
		elseif hasBlessing then
			SetDrawColor(0.50, 0.38, 0.12)
		else
			SetDrawColor(0.28, 0.23, 0.08)
		end
		-- Draw a thick-ish border by layering 2 rectangles
		DrawImage(nil, sx,              sy,              SLOT_SIZE, 2)
		DrawImage(nil, sx,              sy+SLOT_SIZE-2,  SLOT_SIZE, 2)
		DrawImage(nil, sx,              sy,              2, SLOT_SIZE)
		DrawImage(nil, sx+SLOT_SIZE-2,  sy,              2, SLOT_SIZE)
		-- Inner border line
		SetDrawColor(0.35, 0.28, 0.08)
		DrawImage(nil, sx+2,            sy+2,            SLOT_SIZE-4, 1)
		DrawImage(nil, sx+2,            sy+SLOT_SIZE-3,  SLOT_SIZE-4, 1)
		DrawImage(nil, sx+2,            sy+2,            1, SLOT_SIZE-4)
		DrawImage(nil, sx+SLOT_SIZE-3,  sy+2,            1, SLOT_SIZE-4)

		-- Icon content
		if hasBlessing then
			local item  = items[slot.selItemId]
			local iname = item and item.name
			local img   = iname and self:GetBlessingImage(iname)
			if img and img:IsValid() then
				local pad  = 5
				local isz  = SLOT_SIZE - pad * 2
				SetDrawColor(1, 1, 1)
				DrawImage(img, sx + pad, sy + pad, isz, isz)
				-- Circular mask overlay
				local mask = self:GetCircleMask()
				if mask and mask:IsValid() then
					SetDrawColor(bgR, bgG, bgB)
					DrawImage(mask, sx + pad, sy + pad, isz, isz)
				end
			else
				local abbr = iname and iname:sub(1, 2):upper() or "??"
				SetDrawColor(1, 1, 1)
				DrawString(sx + m_floor(SLOT_SIZE / 2), sy + m_floor(SLOT_SIZE / 2) - 7,
					"CENTER_X", 11, "VAR", "^xAACC88" .. abbr)
			end
		else
			-- "+" symbol
			local mid = m_floor(SLOT_SIZE / 2)
			local arm = 7
			local th  = 3
			if hov then
				SetDrawColor(0.55, 0.45, 0.18)
			else
				SetDrawColor(0.30, 0.28, 0.14)
			end
			DrawImage(nil, sx + mid - m_floor(th/2), sy + mid - arm, th, arm * 2)
			DrawImage(nil, sx + mid - arm,           sy + mid - m_floor(th/2), arm * 2, th)
		end
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
