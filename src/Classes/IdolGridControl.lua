-- Last Epoch Building
--
-- Class: Idol Grid Control
-- Displays the idol inventory as a 2D grid matching the in-game layout.
-- Layout is configurable via IDOL_GRID_LAYOUT in ItemsTab, making it easy
-- to update when the Shattered Omens patch changes the inventory shape.
-- Pass cellW / cellH to override default cell dimensions (e.g. 2x for IdolsTab).
--
local t_insert = table.insert
local m_floor  = math.floor

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

-- Rarity background fill colors (R, G, B) — dimmed versions of LE rarity hex
local rarityBg = {
	NORMAL    = { 0.18, 0.18, 0.18 },
	MAGIC     = { 0.04, 0.13, 0.18 },
	RARE      = { 0.18, 0.16, 0.07 },
	UNIQUE    = { 0.18, 0.09, 0.01 },
	EXALTED   = { 0.15, 0.08, 0.25 },
	LEGENDARY = { 0.25, 0.03, 0.09 },
	SET       = { 0.05, 0.18, 0.08 },
	IDOL      = { 0.04, 0.15, 0.15 },
}

-- Rarity border colors (R, G, B) — match LE color hex values
local rarityBorder = {
	NORMAL    = { 0.55, 0.55, 0.55 },
	MAGIC     = { 0.21, 0.64, 0.89 },
	RARE      = { 0.89, 0.82, 0.34 },
	UNIQUE    = { 0.92, 0.45, 0.04 },
	EXALTED   = { 0.76, 0.52, 1.00 },
	LEGENDARY = { 1.00, 0.15, 0.45 },
	SET       = { 0.44, 0.91, 0.49 },
	IDOL      = { 0.21, 0.78, 0.78 },
}

-- Idol grid dimensions in cells {width, height}, keyed on the base type string
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

	-- Maps slotName -> {row, col} for secondary-slot tooltip redirect
	self.slotToCell = {}

	-- Maps [row][col] -> primary ItemSlotControl for multi-cell idols; rebuilt each Draw
	self.cellPrimary = {}

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
			local gridRef = self  -- capture grid reference for closure
			slot.shown = function()
				local altarName = itemsTab.activeAltarLayout
				local blocked
				if not altarName or altarName == "Default" then
					blocked = DEFAULT_BLOCKED[r] and DEFAULT_BLOCKED[r][c]
				else
					local altar = itemsTab.altarLayouts and itemsTab.altarLayouts[altarName]
					if not altar or not altar.grid then
						blocked = DEFAULT_BLOCKED[r] and DEFAULT_BLOCKED[r][c]
					else
						blocked = altar.grid[r][c] == 0
					end
				end
				if not blocked then return true end
				-- Blocked cells are normally hidden, but keep them shown when
				-- covered by a placed idol so hover tooltips work on all cells.
				local cp = gridRef.cellPrimary
				if cp[r] and cp[r][c] then return true end
				return false
			end

			t_insert(self.controls, slot)

			-- Register in itemsTab so all existing slot logic continues to work
			itemsTab.slots[slotName] = slot
			t_insert(itemsTab.orderedSlots, slot)
			itemsTab.slotOrder[slotName] = #itemsTab.orderedSlots
			itemsTab:RegisterLateSlot(slot)

			self.slotToCell[slotName] = {row, col}

			-- Override tooltipFunc so secondary cells of multi-slot idols show
			-- the primary slot's item tooltip when hovered.
			-- cellPrimary is rebuilt each Draw; primary == slot means "I am the primary".
			local gridSelf = self
			local origTooltipFunc = slot.tooltipFunc
			slot.tooltipFunc = function(tooltip, mode, index, itemId)
				local cp = gridSelf.cellPrimary
				local primarySlot = cp[r] and cp[r][c]
				if primarySlot and primarySlot ~= slot then
					-- Secondary cell: delegate to the primary slot's item
					local item = itemsTab.items[primarySlot.selItemId]
					if main.popups[1] or mode == "OUT" or not item then
						tooltip:Clear()
					elseif tooltip:CheckForUpdate(item, launch.devModeAlt, itemsTab.build.outputRevision) then
						itemsTab:AddItemTooltip(tooltip, item, primarySlot)
					end
				else
					origTooltipFunc(tooltip, mode, index, itemId)
				end
			end
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

-- Determine whether a cell is blocked (altar layout or default blocked set).
function IdolGridControlClass:IsBlockedCell(row, col)
	local altarName = self.itemsTab.activeAltarLayout
	if altarName and altarName ~= "Default" then
		local altar = self.itemsTab.altarLayouts and self.itemsTab.altarLayouts[altarName]
		if altar and altar.grid then
			return altar.grid[row][col] == 0
		end
	end
	return DEFAULT_BLOCKED[row] and DEFAULT_BLOCKED[row][col] or false
end

-- Build/rebuild the cellPrimary map. Called at the start of Draw() and also
-- in IsMouseOver() so tooltips work on secondary cells before the first draw.
function IdolGridControlClass:RebuildCellPrimary()
	self.cellPrimary = {}
	for row, rowData in ipairs(self.layout) do
		for col, slotName in ipairs(rowData) do
			if not self:IsBlockedCell(row, col) then
				local slot = self.itemsTab.slots[slotName]
				local item = slot and self.itemsTab.items[slot.selItemId]
				if item then
					local dims = idolDims[item.type] or {1, 1}
					for dr = 0, dims[2] - 1 do
						if not self.cellPrimary[row + dr] then
							self.cellPrimary[row + dr] = {}
						end
						for dc = 0, dims[1] - 1 do
							if not self.cellPrimary[row + dr][col + dc] then
								self.cellPrimary[row + dr][col + dc] = slot
							end
						end
					end
				end
			end
		end
	end
end

-- Let IdolsTab's ProcessControlsInput find this control when the mouse is over it.
-- Also ensures cellPrimary is ready so secondary-cell tooltips work before the
-- first Draw() call (e.g. when an idol is placed and the mouse is already over it).
function IdolGridControlClass:IsMouseOver()
	if not self:IsShown() then return false end
	if not next(self.cellPrimary) then
		self:RebuildCellPrimary()
	end
	return self:IsMouseInBounds() or (self:GetMouseOverControl() ~= nil)
end

-- Redirect mouse-over for secondary cells of multi-slot idols to the primary slot,
-- so that tooltips and key events work from any cell the idol occupies.
function IdolGridControlClass:GetMouseOverControl()
	local ctrl = self.ControlHost:GetMouseOverControl()
	if ctrl and ctrl.slotName and ctrl.selItemId == 0 then
		local pos = self.slotToCell[ctrl.slotName]
		if pos then
			local cp = self.cellPrimary
			local primarySlot = cp[pos[1]] and cp[pos[1]][pos[2]]
			if primarySlot and primarySlot ~= ctrl then
				return primarySlot
			end
		end
	end
	return ctrl
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

-- Blocked cell texture handle (lazy-loaded)
local blockedCellImage

local function drawBlockedCell(cx, cy, cw, ch)
	if not blockedCellImage then
		blockedCellImage = NewImageHandle()
		blockedCellImage:Load("Assets/idol/idols_blocked.png", "ASYNC")
	end
	SetDrawColor(1, 1, 1)
	DrawImage(blockedCellImage, cx, cy, cw, ch)
end

-- Container/frame image constants
-- idol_container.png is 268x324; circle occupies rows 0-60, grid area rows 61-324
local CONTAINER_NATIVE_W = 268
local CONTAINER_NATIVE_H = 324
local CONTAINER_CIRCLE_ROWS = 61   -- rows 0-60 = circle area
-- idol_altar_empty.png is 128x121
local ALTAR_EMPTY_SIZE = 54  -- draw size (square) for the altar circle icon

function IdolGridControlClass:GetContainerImage()
	if not self.imageHandles["__container"] then
		local h = NewImageHandle()
		h:Load("Assets/idol/idol_container.png", "ASYNC")
		self.imageHandles["__container"] = h
	end
	return self.imageHandles["__container"]
end

function IdolGridControlClass:GetAltarEmptyImage()
	if not self.imageHandles["__altarEmpty"] then
		local h = NewImageHandle()
		h:Load("Assets/idol/idol_altar_empty.png", "ASYNC")
		self.imageHandles["__altarEmpty"] = h
	end
	return self.imageHandles["__altarEmpty"]
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

	-- Pre-pass: build cellPrimary BEFORE DrawControls so tooltipFunc can use it.
	self:RebuildCellPrimary()

	-- Container frame: draw idol_container.png behind the grid.
	-- Scale to match grid width; circle area extends above the grid.
	do
		local numCols  = #self.layout[1]
		local numRows  = #self.layout
		local gridW    = numCols * cw + (numCols - 1) * CELL_GAP
		local gridH    = numRows * ch + (numRows - 1) * CELL_GAP
		local scale    = gridW / CONTAINER_NATIVE_W
		local contH    = m_floor(CONTAINER_NATIVE_H * scale)
		local circleH  = m_floor(CONTAINER_CIRCLE_ROWS * scale)
		-- Draw container so its grid area (below circle) aligns with the idol grid
		local cimg = self:GetContainerImage()
		if cimg and cimg:IsValid() then
			SetDrawColor(1, 1, 1)
			DrawImage(cimg, x, y - circleH, gridW, contH)
		end
		-- Draw altar-empty icon in circle center when no altar is equipped
		local hasAltar = activeAltarName and activeAltarName ~= "Default"
		if not hasAltar then
			local aimg = self:GetAltarEmptyImage()
			if aimg and aimg:IsValid() then
				local iconX = x + m_floor((gridW - ALTAR_EMPTY_SIZE) / 2)
				local iconY = y - circleH + m_floor((circleH - ALTAR_EMPTY_SIZE) / 2)
				SetDrawColor(1, 1, 1)
				DrawImage(aimg, iconX, iconY, ALTAR_EMPTY_SIZE, ALTAR_EMPTY_SIZE)
			end
		end
	end

	-- Pass 1: cell backgrounds (drawn under slot controls)
	for row, rowData in ipairs(self.layout) do
		for col, slotName in ipairs(rowData) do
			local cx = x + (col - 1) * (cw + CELL_GAP)
			local cy = y + (row - 1) * (ch + CELL_GAP)

			if isBlocked(row, col) and not (self.cellPrimary[row] and self.cellPrimary[row][col]) then
				drawBlockedCell(cx, cy, cw, ch)
			elseif isBlocked(row, col) then
				-- Blocked cell covered by a placed idol: draw idol background
				local bg = rarityBg.IDOL
				local primarySlot = self.cellPrimary[row] and self.cellPrimary[row][col]
				if primarySlot then
					local placedItem = self.itemsTab.items[primarySlot.selItemId]
					if placedItem then
						bg = rarityBg[placedItem.rarity] or rarityBg.IDOL
					end
				end
				SetDrawColor(bg[1], bg[2], bg[3])
				DrawImage(nil, cx, cy, cw, ch)
			else
				local slot = self.itemsTab.slots[slotName]
				local item = slot and self.itemsTab.items[slot.selItemId]
				local av = altarVal(row, col)
				if av == 2 and not item then
					SetDrawColor(0.15, 0.05, 0.28)  -- purple tint for empty fractured cell
				else
					local bg = item and (rarityBg[item.rarity] or rarityBg.IDOL) or { 0.13, 0.13, 0.13 }
					SetDrawColor(bg[1], bg[2], bg[3])
				end
				DrawImage(nil, cx, cy, cw, ch)
			end
		end
	end

	-- Draw child slot controls (tooltipFunc now has correct cellPrimary data)
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

					-- Check whether ANY covered cell is a fractured slot (altarVal == 2)
					local hasFractured = false
					for dr = 0, dims[2] - 1 do
						for dc = 0, dims[1] - 1 do
							if altarVal(row + dr, col + dc) == 2 then
								hasFractured = true
								break
							end
						end
						if hasFractured then break end
					end

					-- Solid background to cover ItemSlotControl text beneath
					local bg = rarityBg[item.rarity] or rarityBg.IDOL
					SetDrawColor(bg[1], bg[2], bg[3])
					DrawImage(nil, cx, cy, pw, ph)
					-- Erase CELL_GAP seam lines between cells of the same idol
					for dc = 1, dims[1] - 1 do
						DrawImage(nil, cx + dc * (cw + CELL_GAP) - CELL_GAP, cy, CELL_GAP, ph)
					end
					for dr = 1, dims[2] - 1 do
						DrawImage(nil, cx, cy + dr * (ch + CELL_GAP) - CELL_GAP, pw, CELL_GAP)
					end

					-- Draw idol image (PNG may have transparency; shows rarity bg through it)
					local iconName = item.baseName or item.name
					if (item.rarity == "UNIQUE" or item.rarity == "SET" or item.rarity == "LEGENDARY") and item.title then
						iconName = item.title
					end
					local handle = self:GetImage(nameToFilename(iconName))
					if handle and handle:IsValid() then
						SetDrawColor(1, 1, 1, 1)
						DrawImage(handle, cx, cy, pw, ph)
					end

					-- Rarity-coloured 2-px border spanning full idol area
					local bc = (item.rarity == "UNIQUE") and rarityBorder.UNIQUE or rarityBorder.IDOL
					SetDrawColor(bc[1], bc[2], bc[3])
					DrawImage(nil, cx,          cy,          pw, 2)
					DrawImage(nil, cx,          cy + ph - 2, pw, 2)
					DrawImage(nil, cx,          cy,          2,  ph)
					DrawImage(nil, cx + pw - 2, cy,          2,  ph)

					-- Fractured (Shattered) slot highlight: bright purple border over the
					-- entire idol area so it remains visible even when an idol is placed.
					-- Drawn on top of the rarity border.
					if hasFractured then
						SetDrawColor(0.62, 0.22, 0.92)
						DrawImage(nil, cx,          cy,          pw, 2)
						DrawImage(nil, cx,          cy + ph - 2, pw, 2)
						DrawImage(nil, cx,          cy,          2,  ph)
						DrawImage(nil, cx + pw - 2, cy,          2,  ph)
						-- Inner purple line for a double-border glow effect
						SetDrawColor(0.45, 0.10, 0.70, 0.70)
						DrawImage(nil, cx + 2,      cy + 2,      pw - 4, 1)
						DrawImage(nil, cx + 2,      cy + ph - 3, pw - 4, 1)
						DrawImage(nil, cx + 2,      cy + 2,      1,      ph - 4)
						DrawImage(nil, cx + pw - 3, cy + 2,      1,      ph - 4)
					end

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
					-- Empty valid cell: border (purple for fractured, gray for normal)
					if av == 2 then
						drawBorder(cx, cy, cw, ch, 0.62, 0.22, 0.92)
					else
						drawBorder(cx, cy, cw, ch, 0.28, 0.28, 0.28)
					end
				end
			end
		end
	end
end
