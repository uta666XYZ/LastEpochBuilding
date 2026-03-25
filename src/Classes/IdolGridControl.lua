-- Last Epoch Building
--
-- Class: Idol Grid Control
-- Displays the idol inventory as a 2D grid matching the in-game layout.
-- Layout is configurable via IDOL_GRID_LAYOUT in ItemsTab, making it easy
-- to update when the Shattered Omens patch changes the inventory shape.
-- Pass cellW / cellH to override default cell dimensions (e.g. 2x for IdolsTab).
--
local t_insert = table.insert

local CELL_GAP = 2

-- Positions blocked in Default mode (no altar).
-- These cells exist as slots (Idol 21-25) but are hidden unless an altar enables them.
local DEFAULT_BLOCKED = {
	[1] = { [1] = true, [5] = true },
	[3] = { [3] = true },
	[5] = { [1] = true, [5] = true },
}

-- Numeric idol dimensions in cells {width, height}
local idolDims = {
	["Minor Idol"]  = {1, 1},
	["Small Idol"]  = {1, 1},
	["Humble Idol"] = {2, 1},
	["Stout Idol"]  = {1, 2},
	["Grand Idol"]  = {3, 1},
	["Large Idol"]  = {1, 3},
	["Ornate Idol"] = {4, 1},
	["Huge Idol"]   = {1, 4},
	["Adorned Idol"]= {2, 2},
}

-- Convert item name to sprite PNG filename
-- e.g. "Small Weaver Idol" -> "smallWeaverIdol.png"
-- e.g. "Unvar's Exile"     -> "unvarsExile.png"
local function nameToFilename(name)
	local result = ""
	local i = 0
	for word in name:gmatch("%S+") do
		i = i + 1
		word = word:gsub("'", "")
		if i == 1 then
			result = result .. word:sub(1,1):lower() .. word:sub(2):lower()
		else
			result = result .. word:sub(1,1):upper() .. word:sub(2):lower()
		end
	end
	return result .. ".png"
end

-- Rarity background fill colors (R, G, B)
local rarityBg = {
	NORMAL  = { 0.18, 0.18, 0.18 },
	MAGIC   = { 0.07, 0.13, 0.30 },
	RARE    = { 0.28, 0.22, 0.03 },
	UNIQUE  = { 0.28, 0.13, 0.03 },
	RELIC   = { 0.16, 0.07, 0.28 },
}

-- Rarity border colors (R, G, B)
local rarityBorder = {
	NORMAL  = { 0.55, 0.55, 0.55 },
	MAGIC   = { 0.35, 0.55, 1.00 },
	RARE    = { 1.00, 0.82, 0.20 },
	UNIQUE  = { 0.85, 0.45, 0.10 },
	RELIC   = { 0.70, 0.35, 1.00 },
}

-- Idol grid dimensions (width × height in cells), keyed on the base type string
local idolSizeHint = {
	["Minor Idol"]  = "1x1",
	["Small Idol"]  = "1x1",
	["Humble Idol"] = "2x1",
	["Stout Idol"]  = "1x2",
	["Grand Idol"]  = "3x1",
	["Large Idol"]  = "1x3",
	["Ornate Idol"] = "4x1",
	["Huge Idol"]   = "1x4",
	["Adorned Idol"]= "2x2",
}

-- cellW, cellH are optional; defaults to 68 x 46
local IdolGridControlClass = newClass("IdolGridControl", "Control", "ControlHost", function(self, anchor, x, y, itemsTab, layout, cellW, cellH)
	self.cw = cellW or 68
	self.ch = cellH or 46

	local numCols = #layout[1]
	local numRows = #layout
	local totalW = numCols * self.cw + (numCols - 1) * CELL_GAP
	local totalH = numRows * self.ch + (numRows - 1) * CELL_GAP

	self.Control(anchor, x, y, totalW, totalH)
	self.ControlHost()

	self.itemsTab = itemsTab
	self.layout = layout
	self.imageHandles = {}

	-- Create an ItemSlotControl for EVERY cell (all 25 positions).
	-- Cells blocked in Default mode (Idol 21-25) are hidden via slot.shown
	-- until an altar layout enables them.
	for row, rowData in ipairs(layout) do
		for col, slotName in ipairs(rowData) do
			local cx = (col - 1) * (self.cw + CELL_GAP)
			local cy = (row - 1) * (self.ch + CELL_GAP)
			-- slotLabel="" suppresses the left-side "Idol N:" label
			local slot = new("ItemSlotControl", {"TOPLEFT", self, "TOPLEFT"}, cx, cy, itemsTab, slotName, "", nil, self.cw, self.ch)
			slot.arrowH = self.ch / 4

			-- Show/hide based on active altar (or Default-blocked set)
			local r, c = row, col
			slot.shown = function()
				local altarName = itemsTab.activeAltarLayout
				if not altarName or altarName == "Default" then
					return not (DEFAULT_BLOCKED[r] and DEFAULT_BLOCKED[r][c])
				end
				local altar = itemsTab.altarLayouts and itemsTab.altarLayouts[altarName]
				if not altar or not altar.grid then
					return not (DEFAULT_BLOCKED[r] and DEFAULT_BLOCKED[r][c])
				end
				return altar.grid[r][c] ~= 0
			end

			t_insert(self.controls, slot)

			-- Register in itemsTab so all existing slot logic continues to work
			itemsTab.slots[slotName] = slot
			t_insert(itemsTab.orderedSlots, slot)
			itemsTab.slotOrder[slotName] = #itemsTab.orderedSlots
			itemsTab:RegisterLateSlot(slot)
		end
	end
end)

function IdolGridControlClass:GetImage(filename)
	if not filename then return nil end
	if not self.imageHandles[filename] then
		local h = NewImageHandle()
		h:Load("Assets/idol/" .. filename, "ASYNC")
		self.imageHandles[filename] = h
	end
	return self.imageHandles[filename]
end

-- Let IdolsTab's ProcessControlsInput find this control when the mouse is over it
function IdolGridControlClass:IsMouseOver()
	if not self:IsShown() then return false end
	return self:IsMouseInBounds() or (self:GetMouseOverControl() ~= nil)
end

-- Route key-down events to whichever child slot is under the mouse
function IdolGridControlClass:OnKeyDown(key, doubleClick)
	if not self:IsShown() then return end
	if self.selControl then
		local result = self.selControl:OnKeyDown(key, doubleClick)
		self.selControl = result and self.selControl or nil
		return result and self
	end
	local mOver = self:GetMouseOverControl()
	if mOver and mOver.OnKeyDown then
		self.selControl = mOver
		return mOver:OnKeyDown(key, doubleClick) and self
	end
end

-- Route key-up events to the currently-selected child slot
function IdolGridControlClass:OnKeyUp(key)
	if not self:IsShown() then return end
	if self.selControl then
		if self.selControl.OnKeyUp then
			local result = self.selControl:OnKeyUp(key)
			if not result then self.selControl = nil end
		end
		return self
	end
	local mOver = self:GetMouseOverControl()
	if mOver and mOver.OnKeyUp then
		return mOver:OnKeyUp(key) and self
	end
end

-- Forward character input (search-while-typing inside an open dropdown)
function IdolGridControlClass:OnChar(key)
	if not self:IsShown() then return end
	if self.selControl and self.selControl.OnChar then
		return self.selControl:OnChar(key) and self
	end
end

-- Forward hover-key-up (e.g. wiki open on hover)
function IdolGridControlClass:OnHoverKeyUp(key)
	if not self:IsShown() then return end
	local mOver = self:GetMouseOverControl()
	if mOver and mOver.OnHoverKeyUp then
		mOver:OnHoverKeyUp(key)
	end
end

local function drawBorder(cx, cy, w, h, r, g, b)
	SetDrawColor(r, g, b)
	DrawImage(nil, cx,         cy,         w,  1)
	DrawImage(nil, cx,         cy + h - 1, w,  1)
	DrawImage(nil, cx,         cy,         1,  h)
	DrawImage(nil, cx + w - 1, cy,         1,  h)
end

local function drawBlockedCell(cx, cy, cw, ch)
	SetDrawColor(0.07, 0.07, 0.07)
	DrawImage(nil, cx, cy, cw, ch)
	drawBorder(cx, cy, cw, ch, 0.17, 0.17, 0.17)
	SetDrawColor(0.22, 0.22, 0.22)
	DrawImageQuad(nil,
		cx + 4,      cy + 4,
		cx + 8,      cy + 4,
		cx + cw - 4, cy + ch - 4,
		cx + cw - 8, cy + ch - 4)
	DrawImageQuad(nil,
		cx + cw - 8, cy + 4,
		cx + cw - 4, cy + 4,
		cx + 8,      cy + ch - 4,
		cx + 4,      cy + ch - 4)
end

function IdolGridControlClass:Draw(viewPort)
	local x, y = self:GetPos()
	local cw, ch = self.cw, self.ch

	-- Get active altar grid (nil when "Default" or not found)
	local altarGrid = nil
	local activeAltarName = self.itemsTab.activeAltarLayout
	if activeAltarName and activeAltarName ~= "Default" then
		local altar = self.itemsTab.altarLayouts and self.itemsTab.altarLayouts[activeAltarName]
		if altar then altarGrid = altar.grid end
	end

	-- Determine if a cell is blocked (altar grid takes full priority over base layout)
	local function isBlocked(row, col)
		if altarGrid then
			return altarGrid[row][col] == 0
		end
		return DEFAULT_BLOCKED[row] and DEFAULT_BLOCKED[row][col] or false
	end

	-- Get altar cell value (0/1/2), nil if no altar active
	local function altarVal(row, col)
		return altarGrid and altarGrid[row] and altarGrid[row][col]
	end

	-- Pass 1: cell backgrounds (drawn under slot controls)
	for row, rowData in ipairs(self.layout) do
		for col, slotName in ipairs(rowData) do
			local cx = x + (col - 1) * (cw + CELL_GAP)
			local cy = y + (row - 1) * (ch + CELL_GAP)

			if isBlocked(row, col) then
				drawBlockedCell(cx, cy, cw, ch)
			else
				local slot = self.itemsTab.slots[slotName]
				local item = slot and self.itemsTab.items[slot.selItemId]
				local av = altarVal(row, col)
				if av == 2 and not item then
					SetDrawColor(0.15, 0.05, 0.28)  -- purple tint for empty refracted cell
				else
					local bg = item and rarityBg[item.rarity] or { 0.13, 0.13, 0.13 }
					SetDrawColor(bg[1], bg[2], bg[3])
				end
				DrawImage(nil, cx, cy, cw, ch)
			end
		end
	end

	-- Draw child slot controls (blocked slots have shown=false and are skipped automatically)
	self:DrawControls(viewPort)

	-- Pass 2: overlays on top of slot controls
	-- drawnItems tracks item IDs already rendered (to draw multi-cell idols only once)
	local drawnItems = {}
	for row, rowData in ipairs(self.layout) do
		for col, slotName in ipairs(rowData) do
			if not isBlocked(row, col) then
				local cx = x + (col - 1) * (cw + CELL_GAP)
				local cy = y + (row - 1) * (ch + CELL_GAP)
				local slot = self.itemsTab.slots[slotName]
				local item = slot and self.itemsTab.items[slot.selItemId]
				local av = altarVal(row, col)

				if item and not drawnItems[slot.selItemId] then
					drawnItems[slot.selItemId] = true
					-- Pixel size of the idol (may span multiple cells)
					local dims = idolDims[item.type] or {1, 1}
					local pw = dims[1] * cw + (dims[1] - 1) * CELL_GAP
					local ph = dims[2] * ch + (dims[2] - 1) * CELL_GAP
					-- Solid background to cover ItemSlotControl text beneath
					local bg = rarityBg[item.rarity] or rarityBg.NORMAL
					SetDrawColor(bg[1], bg[2], bg[3])
					DrawImage(nil, cx, cy, pw, ph)
					-- Draw idol image (PNG may have transparency; shows rarity bg through it)
					local handle = self:GetImage(nameToFilename(item.name))
					if handle and handle:IsValid() then
						SetDrawColor(1, 1, 1, 1)
						DrawImage(handle, cx, cy, pw, ph)
					end
					-- Rarity-coloured 2-px border spanning full idol area
					local bc = rarityBorder[item.rarity] or rarityBorder.NORMAL
					SetDrawColor(bc[1], bc[2], bc[3])
					DrawImage(nil, cx,          cy,          pw, 2)
					DrawImage(nil, cx,          cy + ph - 2, pw, 2)
					DrawImage(nil, cx,          cy,          2,  ph)
					DrawImage(nil, cx + pw - 2, cy,          2,  ph)
					-- Size hint badge (e.g. "2x1") in bottom-right corner of idol area
					local hint = idolSizeHint[item.type]
					if hint then
						local fs = math.max(10, math.floor(ch * 0.22))
						local tw = DrawStringWidth(fs, "VAR", hint)
						SetDrawColor(0, 0, 0, 0.60)
						DrawImage(nil, cx + pw - tw - 4, cy + ph - fs - 3, tw + 3, fs + 2)
						SetDrawColor(0.80, 0.80, 0.80)
						DrawString(cx + pw - tw - 3, cy + ph - fs - 3, "LEFT", fs, "VAR", hint)
					end
				elseif not item then
					-- Empty valid cell: border (purple for refracted, gray for normal)
					if av == 2 then
						drawBorder(cx, cy, cw, ch, 0.55, 0.25, 0.80)
					else
						drawBorder(cx, cy, cw, ch, 0.28, 0.28, 0.28)
					end
				end
			end
		end
	end
end
