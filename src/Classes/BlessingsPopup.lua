-- Last Epoch Building
-- Class: BlessingsPopup
-- maxroll/letools style blessing selection UI

local t_insert = table.insert
local m_floor  = math.floor
local m_ceil   = math.ceil
local m_max    = math.max
local m_min    = math.min

-- ============================================================
-- Layout constants

local POPUP_W   = 820
local POPUP_H   = 640
local LEFT_W    = 210   -- left panel width
local SLOT_SIZE = 44
local SLOT_GAP  = 6

local CARD_AREA_X  = LEFT_W + 8          -- 218
local CARD_AREA_Y  = 196
local CARD_AREA_W  = POPUP_W - LEFT_W - 8 - 16  -- 586 (16 reserved for scrollbar)
local CARD_AREA_H  = POPUP_H - CARD_AREA_Y - 8  -- 436
local CARD_COL_GAP = 8
local CARD_W       = m_floor((CARD_AREA_W - CARD_COL_GAP) / 2)  -- 289
local CARD_H       = 90
local CARD_ROW_GAP = 6

-- ============================================================
-- Timeline metadata

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

local TIMELINE_ORDER = {
	"Fall of the Outcasts",
	"The Stolen Lance",
	"The Black Sun",
	"Blood, Frost, and Death",
	"Ending the Storm",
	"Fall of the Empire",
	"Reign of Dragons",
	"The Last Ruin",
	"The Age of Winter",
	"Spirits of Fire",
}

-- Compute slot positions within left panel (relative to popup top-left)
local function computeSlotPositions()
	local rowSlots = {{}, {}, {}}
	for _, s in ipairs(SLOT_GRID) do
		t_insert(rowSlots[s.row], s)
	end
	local pos  = {}
	local rowY = {50, 100, 150}
	for r = 1, 3 do
		local slots = rowSlots[r]
		local n     = #slots
		local totalW = n * SLOT_SIZE + (n - 1) * SLOT_GAP
		local startX = m_floor((LEFT_W - totalW) / 2)
		for i, s in ipairs(slots) do
			pos[s.tl] = {
				x = startX + (i - 1) * (SLOT_SIZE + SLOT_GAP),
				y = rowY[r],
			}
		end
	end
	return pos
end

local SLOT_POS = computeSlotPositions()

-- ============================================================
-- Draw helpers

local function drawRect(x, y, w, h, r, g, b)
	SetDrawColor(r, g, b)
	DrawImage(nil, x, y, w, h)
end

local function drawBorder(x, y, w, h, r, g, b)
	SetDrawColor(r, g, b)
	DrawImage(nil, x,     y,     w, 1)
	DrawImage(nil, x,     y+h-1, w, 1)
	DrawImage(nil, x,     y,     1, h)
	DrawImage(nil, x+w-1, y,     1, h)
end

-- ============================================================
-- BlessingsPopup class

local BlessingsPopupClass = newClass("BlessingsPopup", "ControlHost", "Control",
	function(self, itemsTab)
		self.ControlHost()
		self.Control(nil, 0, 0, POPUP_W, POPUP_H)
		self.width  = function() return POPUP_W end
		self.height = function() return POPUP_H end
		self.x = function() return m_floor((main.screenW - POPUP_W) / 2) end
		self.y = function() return m_max(20, m_floor((main.screenH - POPUP_H) / 2)) end

		self.itemsTab     = itemsTab
		self.build        = itemsTab.build
		self.blessingData = itemsTab.blessingData

		-- UI state
		self.selectedTL  = TIMELINE_ORDER[1]
		self.searchText  = ""
		self.hoveredCard = nil  -- {entry, isGrand}

		-- Initialise blessing state from currently equipped items
		self.blessingState = {}
		for _, tl in ipairs(TIMELINE_ORDER) do
			local slot     = itemsTab.slots[tl]
			local entry    = nil
			local isGrand  = false
			local rollFrac = (itemsTab.blessingFracs and itemsTab.blessingFracs[tl]) or 1.0

			if slot and slot.selItemId and slot.selItemId < 0 then
				local item   = itemsTab.items[slot.selItemId]
				local tlData = item and self.blessingData[tl]
				if tlData and item then
					for _, b in ipairs(tlData.normal or {}) do
						if b.name == item.name then entry = b; break end
					end
					if not entry then
						isGrand = true
						for _, b in ipairs(tlData.grand or {}) do
							if b.name == item.name then entry = b; break end
						end
					end
				end
			end

			local rollVal
			if entry then
				rollVal = m_floor(entry.minVal + rollFrac * (entry.maxVal - entry.minVal) + 0.5)
				rollVal = m_max(m_floor(entry.minVal + 0.5), m_min(m_ceil(entry.maxVal), rollVal))
			end

			self.blessingState[tl] = {
				entry   = entry,
				isGrand = isGrand,
				rollVal = rollVal or (entry and m_ceil(entry.maxVal)),
			}
		end

		self:BuildControls()
	end
)

-- ============================================================
-- Control construction

function BlessingsPopupClass:BuildControls()
	-- Close button
	t_insert(self.controls, new("ButtonControl",
		{"TOPRIGHT", self, "TOPRIGHT"}, -6, 6, 60, 22,
		"Close", function() self:Close() end
	))

	-- Timeline list buttons (left panel, below slot grid)
	for i, tl in ipairs(TIMELINE_ORDER) do
		local tlRef = tl
		local btn = new("ButtonControl",
			{"TOPLEFT", self, "TOPLEFT"}, 4, 202 + (i - 1) * 26, LEFT_W - 8, 22,
			tl,
			function()
				self.selectedTL = tlRef
				if self.controls.cardScrollbar then
					self.controls.cardScrollbar:SetOffset(0)
				end
			end
		)
		btn.label = function()
			local st  = self.blessingState[tlRef]
			local col = (self.selectedTL == tlRef) and "^7" or "^8"
			local dot = (st and st.entry) and " *" or ""
			return col .. tlRef .. dot
		end
		t_insert(self.controls, btn)
	end

	-- Unequip button (right panel header, top-right area)
	local unequipBtn = new("ButtonControl",
		{"TOPLEFT", self, "TOPLEFT"}, POPUP_W - 105, 62, 90, 20,
		"X Unequip",
		function()
			local tl = self.selectedTL
			local st = self.blessingState[tl]
			st.entry   = nil
			st.isGrand = false
			st.rollVal = nil
			self.itemsTab:UpdateBlessingSlot(tl, nil, 1.0)
		end
	)
	unequipBtn.shown = function()
		local st = self.blessingState[self.selectedTL]
		return st ~= nil and st.entry ~= nil
	end
	t_insert(self.controls, unequipBtn)
	self.controls.unequipBtn = unequipBtn

	-- Value decrement button
	local valMinus = new("ButtonControl",
		{"TOPLEFT", self, "TOPLEFT"}, LEFT_W + 10, 136, 22, 18,
		"-", function() self:AdjustValue(-1) end
	)
	valMinus.shown = function()
		local st = self.blessingState[self.selectedTL]
		return st ~= nil and st.entry ~= nil
	end
	t_insert(self.controls, valMinus)
	self.controls.valMinus = valMinus

	-- Value increment button
	local valPlus = new("ButtonControl",
		{"TOPLEFT", self, "TOPLEFT"}, LEFT_W + 78, 136, 22, 18,
		"+", function() self:AdjustValue(1) end
	)
	valPlus.shown = function()
		local st = self.blessingState[self.selectedTL]
		return st ~= nil and st.entry ~= nil
	end
	t_insert(self.controls, valPlus)
	self.controls.valPlus = valPlus

	-- Search edit control
	local searchEdit = new("EditControl",
		{"TOPLEFT", self, "TOPLEFT"}, CARD_AREA_X, 170, CARD_AREA_W, 20,
		"", "Search blessings...", nil, nil,
		function(buf)
			self.searchText = buf:lower()
			if self.controls.cardScrollbar then
				self.controls.cardScrollbar:SetOffset(0)
			end
		end
	)
	t_insert(self.controls, searchEdit)
	self.controls.searchEdit = searchEdit

	-- Card area scrollbar
	local sb = new("ScrollBarControl",
		{"TOPLEFT", self, "TOPLEFT"},
		CARD_AREA_X + CARD_AREA_W + 2, CARD_AREA_Y,
		14, CARD_AREA_H, 30, "VERTICAL", true
	)
	t_insert(self.controls, sb)
	self.controls.cardScrollbar = sb
end

-- ============================================================
-- Helpers

function BlessingsPopupClass:GetRollFrac(entry, rollVal)
	if not entry then return 1.0 end
	local range = entry.maxVal - entry.minVal
	if range == 0 then return 1.0 end
	return m_max(0, m_min(1, (rollVal - entry.minVal) / range))
end

function BlessingsPopupClass:AdjustValue(delta)
	local tl = self.selectedTL
	local st = self.blessingState[tl]
	if not st or not st.entry then return end
	local b    = st.entry
	local minV = m_floor(b.minVal + 0.5)
	local maxV = m_ceil(b.maxVal)
	st.rollVal = m_max(minV, m_min(maxV, (st.rollVal or maxV) + delta))
	local frac = self:GetRollFrac(b, st.rollVal)
	self.itemsTab:UpdateBlessingSlot(tl, b, frac)
end

function BlessingsPopupClass:EquipBlessing(tl, blessEntry, isGrand)
	local st   = self.blessingState[tl]
	local minV = m_floor(blessEntry.minVal + 0.5)
	local maxV = m_ceil(blessEntry.maxVal)
	local rollVal = maxV
	if st and st.rollVal and st.rollVal >= minV and st.rollVal <= maxV then
		rollVal = st.rollVal
	end
	st.entry   = blessEntry
	st.isGrand = isGrand
	st.rollVal = rollVal
	local frac = self:GetRollFrac(blessEntry, rollVal)
	self.itemsTab:UpdateBlessingSlot(tl, blessEntry, frac)
end

function BlessingsPopupClass:GetFilteredCards()
	local tlData = self.blessingData[self.selectedTL]
	if not tlData then return {}, {} end
	local search = self.searchText
	local function match(b)
		if search == "" then return true end
		return b.name:lower():find(search, 1, true)
			or (b.impl1 or ""):lower():find(search, 1, true)
	end
	local normal, grand = {}, {}
	for _, b in ipairs(tlData.normal or {}) do if match(b) then t_insert(normal, b) end end
	for _, b in ipairs(tlData.grand  or {}) do if match(b) then t_insert(grand,  b) end end
	return normal, grand
end

function BlessingsPopupClass:GetCardRows()
	local normal, grand = self:GetFilteredCards()
	local n    = m_max(#normal, #grand)
	local rows = {}
	for i = 1, n do
		t_insert(rows, {normal = normal[i], grand = grand[i]})
	end
	return rows
end

function BlessingsPopupClass:Close()
	main:ClosePopup()
end

-- ============================================================
-- Card drawing

function BlessingsPopupClass:DrawCard(cx, cy, entry, isGrand, isEquipped, isHovered)
	local cw, ch = CARD_W, CARD_H

	-- Background
	if isEquipped then
		drawRect(cx, cy, cw, ch, 0.15, 0.08, 0.22)
	elseif isHovered then
		drawRect(cx, cy, cw, ch, 0.12, 0.09, 0.17)
	else
		drawRect(cx, cy, cw, ch, 0.07, 0.07, 0.10)
	end

	-- Border
	if isEquipped then
		drawBorder(cx, cy, cw, ch, 0.55, 0.25, 0.75)
	elseif isHovered then
		drawBorder(cx, cy, cw, ch, 0.38, 0.30, 0.52)
	elseif isGrand then
		drawBorder(cx, cy, cw, ch, 0.35, 0.28, 0.10)
	else
		drawBorder(cx, cy, cw, ch, 0.24, 0.20, 0.08)
	end

	-- Icon placeholder (40x40)
	local iconX = cx + 5
	local iconY = cy + m_floor((ch - 40) / 2)
	if isGrand then
		drawRect(iconX, iconY, 40, 40, 0.38, 0.26, 0.07)
	else
		drawRect(iconX, iconY, 40, 40, 0.22, 0.16, 0.05)
	end
	drawBorder(iconX, iconY, 40, 40, 0.52, 0.38, 0.14)

	-- Text (right of icon)
	local tx = cx + 52
	local ty = cy + 6

	-- Name (gold, uppercase)
	SetDrawColor(1, 1, 1)
	DrawString(tx, ty, "LEFT", 13, "VAR", "^xC8A040" .. entry.name:upper())

	-- Type + timeline (small grey)
	DrawString(tx, ty + 17, "LEFT", 10, "VAR",
		"^x666666BLESSING   ^x505050" .. self.selectedTL:upper())

	-- Stat text
	local stat1 = (entry.impl1 or ""):gsub("{[^}]+}", "")
	DrawString(tx, ty + 31, "LEFT", 12, "VAR", "^xBBBBBB" .. stat1)

	if entry.impl2 then
		local stat2 = entry.impl2:gsub("{[^}]+}", "")
		DrawString(tx, ty + 47, "LEFT", 11, "VAR", "^x9A9A70" .. stat2)
	end
end

-- ============================================================
-- Main draw

function BlessingsPopupClass:Draw(viewPort)
	local px, py = self:GetPos()

	-- === Background & border ===
	drawRect(px, py, POPUP_W, POPUP_H, 0.05, 0.05, 0.07)
	drawBorder(px, py, POPUP_W, POPUP_H, 0.40, 0.32, 0.12)

	-- Title
	SetDrawColor(1, 1, 1)
	DrawString(px + m_floor(POPUP_W / 2), py + 14, "CENTER_X", 16, "VAR", "^7BLESSINGS")

	-- Underline
	drawRect(px + 8, py + 36, POPUP_W - 16, 1, 0.25, 0.20, 0.08)

	-- Left | Right divider
	drawRect(px + LEFT_W + 2, py + 8, 1, POPUP_H - 16, 0.22, 0.18, 0.07)

	-- === SLOT GRID ===
	local bst = self.blessingState
	for _, sg in ipairs(SLOT_GRID) do
		local tl  = sg.tl
		local sp  = SLOT_POS[tl]
		local sx  = px + sp.x
		local sy  = py + sp.y
		local sel = (self.selectedTL == tl)
		local has = bst[tl] and bst[tl].entry ~= nil

		if sel then
			drawRect(sx, sy, SLOT_SIZE, SLOT_SIZE, 0.20, 0.11, 0.30)
			drawBorder(sx, sy, SLOT_SIZE, SLOT_SIZE, 0.58, 0.26, 0.78)
		elseif has then
			drawRect(sx, sy, SLOT_SIZE, SLOT_SIZE, 0.14, 0.10, 0.05)
			drawBorder(sx, sy, SLOT_SIZE, SLOT_SIZE, 0.50, 0.35, 0.12)
		else
			drawRect(sx, sy, SLOT_SIZE, SLOT_SIZE, 0.08, 0.07, 0.10)
			drawBorder(sx, sy, SLOT_SIZE, SLOT_SIZE, 0.25, 0.20, 0.08)
		end

		-- 2-letter abbreviation
		local abbr = tl:sub(1, 2):upper()
		SetDrawColor(1, 1, 1)
		DrawString(sx + m_floor(SLOT_SIZE / 2), sy + m_floor(SLOT_SIZE / 2) - 7,
			"CENTER_X", 11, "VAR",
			(has and "^xAACC88" or "^x555555") .. abbr)

		-- Filled indicator dot
		if has then
			drawRect(sx + m_floor(SLOT_SIZE / 2) - 3,
				sy + SLOT_SIZE - 8, 6, 5, 0.35, 0.75, 0.35)
		end
	end

	-- Slot grid / timeline-list separator
	drawRect(px + 4, py + 200, LEFT_W - 8, 1, 0.22, 0.18, 0.07)

	-- === RIGHT PANEL HEADER ===
	local rpx = px + LEFT_W + 10

	-- Timeline name
	SetDrawColor(1, 1, 1)
	DrawString(rpx, py + 48, "LEFT", 12, "VAR", "^x777777" .. self.selectedTL)

	local curSt = bst[self.selectedTL]
	if curSt and curSt.entry then
		local b = curSt.entry

		-- Blessing name (gold, large)
		DrawString(rpx, py + 65, "LEFT", 16, "VAR", "^xC8A040" .. b.name:upper())

		-- Stat lines
		local stat1 = (b.impl1 or ""):gsub("{[^}]+}", "")
		DrawString(rpx, py + 92, "LEFT", 13, "VAR", "^xCCCCCC" .. stat1)
		if b.impl2 then
			local stat2 = b.impl2:gsub("{[^}]+}", "")
			DrawString(rpx, py + 108, "LEFT", 12, "VAR", "^xAAAA88" .. stat2)
		end

		-- Range + value (value is drawn between the - and + buttons)
		if curSt.rollVal then
			local minV = m_floor(b.minVal + 0.5)
			local maxV = m_ceil(b.maxVal)
			DrawString(rpx, py + 128, "LEFT", 11, "VAR",
				string.format("^x666666Range: %d - %d", minV, maxV))
			-- Value text (between valMinus x=LEFT_W+10+22=242 and valPlus x=LEFT_W+78)
			DrawString(px + LEFT_W + 36, py + 138, "LEFT", 14, "VAR",
				"^7" .. tostring(curSt.rollVal))
		end
	else
		DrawString(rpx, py + 65, "LEFT", 16, "VAR", "^x444444EMPTY SLOT")
	end

	-- Header separator
	drawRect(rpx - 4, py + 162, POPUP_W - LEFT_W - 10, 1, 0.22, 0.18, 0.07)

	-- === CARD AREA ===
	local sb           = self.controls.cardScrollbar
	local scrollOffset = sb and sb.offset or 0
	local rows         = self:GetCardRows()
	local totalH       = #rows * (CARD_H + CARD_ROW_GAP)
	if sb then sb:SetContentDimension(totalH, CARD_AREA_H) end

	local areaX = px + CARD_AREA_X
	local areaY = py + CARD_AREA_Y
	local areaB = areaY + CARD_AREA_H
	local curSt2 = bst[self.selectedTL]

	for ri, row in ipairs(rows) do
		local cardRowY = areaY + (ri - 1) * (CARD_H + CARD_ROW_GAP) - scrollOffset
		if cardRowY + CARD_H >= areaY and cardRowY < areaB then

			if row.normal then
				local isEq  = curSt2 and curSt2.entry == row.normal
				local isHov = self.hoveredCard
					and self.hoveredCard.entry == row.normal
					and not self.hoveredCard.isGrand
				self:DrawCard(areaX, cardRowY, row.normal, false, isEq, isHov)
			end

			if row.grand then
				local cx    = areaX + CARD_W + CARD_COL_GAP
				local isEq  = curSt2 and curSt2.entry == row.grand
				local isHov = self.hoveredCard
					and self.hoveredCard.entry == row.grand
					and self.hoveredCard.isGrand
				self:DrawCard(cx, cardRowY, row.grand, true, isEq, isHov)
			end
		end
	end

	-- Card area top rule
	drawRect(px + CARD_AREA_X - 2, py + CARD_AREA_Y - 1, CARD_AREA_W + 20, 1, 0.22, 0.18, 0.07)

	-- Draw controls on top
	self:DrawControls(viewPort)
end

-- ============================================================
-- Input

function BlessingsPopupClass:ProcessInput(inputEvents, viewPort)
	local px, py = self:GetPos()
	local sb           = self.controls.cardScrollbar
	local scrollOffset = sb and sb.offset or 0

	local mx, my = GetCursorPos()
	local areaX  = px + CARD_AREA_X
	local areaY  = py + CARD_AREA_Y
	local areaB  = areaY + CARD_AREA_H

	-- Update hover state
	self.hoveredCard = nil
	if mx >= areaX and mx < areaX + CARD_AREA_W and my >= areaY and my < areaB then
		local rows  = self:GetCardRows()
		local relY  = my - areaY + scrollOffset
		local ri    = m_floor(relY / (CARD_H + CARD_ROW_GAP)) + 1
		local rowY0 = (ri - 1) * (CARD_H + CARD_ROW_GAP)
		if ri >= 1 and ri <= #rows and (relY - rowY0) < CARD_H then
			local row     = rows[ri]
			local isGrand = (mx - areaX) >= (CARD_W + CARD_COL_GAP)
			local entry   = isGrand and row.grand or row.normal
			if entry then
				self.hoveredCard = {entry = entry, isGrand = isGrand}
			end
		end
	end

	for _, event in ipairs(inputEvents) do
		if event.type == "KeyDown" then
			if event.key == "ESCAPE" then
				self:Close()
				return
			end

		elseif event.type == "mousewheel" then
			if mx >= areaX and mx < areaX + CARD_AREA_W + 20 and my >= areaY and my < areaB then
				if sb then sb:Scroll(-event.val) end
			end

		elseif event.type == "LButtonDown" then
			-- Slot grid clicks
			for _, sg in ipairs(SLOT_GRID) do
				local sp = SLOT_POS[sg.tl]
				local sx = px + sp.x
				local sy = py + sp.y
				if mx >= sx and mx < sx + SLOT_SIZE and my >= sy and my < sy + SLOT_SIZE then
					self.selectedTL = sg.tl
					if sb then sb:SetOffset(0) end
				end
			end

			-- Card clicks
			if mx >= areaX and mx < areaX + CARD_AREA_W and my >= areaY and my < areaB then
				local rows  = self:GetCardRows()
				local relY  = my - areaY + scrollOffset
				local ri    = m_floor(relY / (CARD_H + CARD_ROW_GAP)) + 1
				local rowY0 = (ri - 1) * (CARD_H + CARD_ROW_GAP)
				if ri >= 1 and ri <= #rows and (relY - rowY0) < CARD_H then
					local row     = rows[ri]
					local isGrand = (mx - areaX) >= (CARD_W + CARD_COL_GAP)
					local entry   = isGrand and row.grand or row.normal
					if entry then
						self:EquipBlessing(self.selectedTL, entry, isGrand)
					end
				end
			end
		end
	end

	self:ProcessControlsInput(inputEvents, viewPort)
end
