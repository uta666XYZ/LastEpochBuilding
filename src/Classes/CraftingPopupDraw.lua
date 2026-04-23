-- Last Epoch Building
--
-- Module: CraftingPopup Draw/Input
-- Drawing and input handling for CraftingPopup. Attaches methods to the
-- CraftingPopupClass created by Classes/CraftingPopup.lua.
-- Loaded via: LoadModule("Classes/CraftingPopupDraw", CraftingPopupClass, H)
--
local CraftingPopupClass, H = ...

local t_insert = table.insert
local t_remove = table.remove
local m_max = math.max
local m_min = math.min
local m_floor = math.floor
local m_ceil = math.ceil
local pairs = pairs
local ipairs = ipairs

local MAX_MOD_LINES      = H.MAX_MOD_LINES
local getTypeIcon        = H.getTypeIcon
local POPUP_W            = H.POPUP_W
local LEFT_W             = H.LEFT_W
local DIVIDER_X          = H.DIVIDER_X
local TYPE_LIST_Y        = H.TYPE_LIST_Y
local TYPE_LIST_H        = H.TYPE_LIST_H
local TYPE_ROW_H         = H.TYPE_ROW_H
local PREVIEW_Y          = H.PREVIEW_Y
local RP_X               = H.RP_X
local RP_W               = H.RP_W
local RP_TAB_Y           = H.RP_TAB_Y
local RP_TAB_H           = H.RP_TAB_H
local RP_FILTER_Y        = H.RP_FILTER_Y
local RP_FILTER_H        = H.RP_FILTER_H
local RP_CATTAB_Y        = H.RP_CATTAB_Y
local RP_CATTAB_H        = H.RP_CATTAB_H
local RP_CARD_Y          = H.RP_CARD_Y
local RP_CARD_PAD        = H.RP_CARD_PAD
local IC_COLS            = H.IC_COLS
local IC_GAP             = H.IC_GAP
local IC_W               = H.IC_W
local IC_H               = H.IC_H
local AC_H               = H.AC_H
local AC_GAP             = H.AC_GAP
local LP_LABEL_X         = H.LP_LABEL_X
local LP_LINE_X          = H.LP_LINE_X
local LP_LINE_W          = H.LP_LINE_W
local LP_VAL_X           = H.LP_VAL_X
local LP_VAL_W           = H.LP_VAL_W
local LP_TIER_X          = H.LP_TIER_X
local LP_TRUP_X          = H.LP_TRUP_X
local LP_TRDN_X          = H.LP_TRDN_X
local LP_REM_X           = H.LP_REM_X
local LP_REM_W           = H.LP_REM_W
local NO_T8_SLOTS        = H.NO_T8_SLOTS
local FIXED_TIER_SLOTS   = H.FIXED_TIER_SLOTS
local TIER_COLORS        = H.TIER_COLORS
local tierColor          = H.tierColor
local itemNameToFilename = H.itemNameToFilename
local getRarityForAffixes = H.getRarityForAffixes
local cleanImplicitText  = H.cleanImplicitText
local wrapByChars        = H.wrapByChars
local wrapForLabel       = H.wrapForLabel
local wrapTextLine       = H.wrapTextLine
local hasRange           = H.hasRange
local getModPrecision    = H.getModPrecision
local getRounding        = H.getRounding
local extractMinMax      = H.extractMinMax
local computeModValue    = H.computeModValue
local reverseModRange    = H.reverseModRange
local clampModValue      = H.clampModValue
local formatModValue     = H.formatModValue

-- =============================================================================
-- Set info panel (item set members + bonuses)
-- =============================================================================
function CraftingPopupClass:DrawSetInfo(px, py)
	local entry = self.editBaseEntry
	local set
	if entry and entry.category == "set" and entry.setData and entry.setData.set then
		set = entry.setData.set
	elseif self.editItem and self.editItem.setInfo and self.editItem.setInfo.setId ~= nil then
		-- Reforged crafted basic item: synthesize a set view from setInfo.
		set = {
			setId = self.editItem.setInfo.setId,
			name  = self.editItem.setInfo.name,
			bonus = self.editItem.setInfo.bonus,
		}
	end
	if not set then return end

	local setId  = set.setId
	local LINE_H = 18
	local GAP    = 4
	local y      = self.editY.setInfoY
	if not y or y <= 0 then return end

	-- Build set of member names that are currently equipped (by slot selItemId)
	-- or currently being edited in this popup. Also register the title with any
	-- trailing " Reforged" suffix stripped so Reforged crafted items match the
	-- bare member name used in the member list.
	local equippedNames = {}
	local function markName(s)
		if not s or s == "" then return end
		equippedNames[s] = true
		local stripped = s:gsub(" Reforged$", "")
		if stripped ~= s then equippedNames[stripped] = true end
	end
	local itemsTab = self.itemsTab or (self.build and self.build.itemsTab)
	if itemsTab then
		for _, slot in pairs(itemsTab.slots or {}) do
			local eqItem = slot.selItemId and itemsTab.items and itemsTab.items[slot.selItemId]
			if eqItem and eqItem.setInfo and eqItem.setInfo.setId == setId then
				markName(eqItem.setInfo.name)
				markName(eqItem.title)
			elseif eqItem and eqItem.rarity == "SET" and eqItem.title then
				markName(eqItem.title)
			end
		end
	end
	-- Highlight the piece being crafted right now
	markName(self.editItem and self.editItem.title)

	SetDrawColor(1, 1, 1)
	DrawString(px + LP_LABEL_X, py + y, "LEFT", 14, "VAR", colorCodes.SET .. "ITEM SET")
	y = y + LINE_H + GAP
	DrawString(px + LP_LINE_X, py + y, "LEFT", 13, "VAR", "^7" .. (set.name or ""))
	y = y + LINE_H

	-- Collect and sort set members
	local members = {}
	for _, si in pairs(self.setItems or {}) do
		if si.set and si.set.setId == setId then
			local typeName = ""
			for tname, bases in pairs(self.build.data.itemBaseLists or {}) do
				for _, bEntry in ipairs(bases) do
					if bEntry.base.baseTypeID == si.baseTypeID and bEntry.base.subTypeID == si.subTypeID then
						typeName = bEntry.base.type or tname
						break
					end
				end
				if typeName ~= "" then break end
			end
			t_insert(members, { name = si.name, typeName = typeName })
		end
	end
	table.sort(members, function(a, b) return a.name < b.name end)
	-- Orange highlight for equipped / currently-edited members; dim grey otherwise
	local ORANGE = "^xFF9933"
	for _, m in ipairs(members) do
		local col = equippedNames[m.name] and ORANGE or "^8"
		DrawString(px + LP_LINE_X + 8, py + y, "LEFT", 12, "VAR",
			col .. m.name .. (m.typeName ~= "" and ("  " .. m.typeName) or ""))
		y = y + LINE_H
	end
	y = y + GAP

	-- Set bonuses (wrap to fit left panel width)
	local bonus = set.bonus
	if bonus and next(bonus) then
		DrawString(px + LP_LABEL_X, py + y, "LEFT", 14, "VAR", colorCodes.SET .. "SET BONUSES")
		y = y + LINE_H + GAP
		local bonusKeys = {}
		for k in pairs(bonus) do t_insert(bonusKeys, k) end
		table.sort(bonusKeys, function(a, b) return tonumber(a) < tonumber(b) end)
		local bonusW = LEFT_W - LP_LINE_X - 4
		local WRAP_H = 15
		for _, k in ipairs(bonusKeys) do
			local full = "^8" .. k .. " set: ^7" .. tostring(bonus[k])
			local wrapped, n = wrapForLabel(full, bonusW, 13)
			-- wrapForLabel keeps only the leading ^8; re-insert ^7 after key
			for line in (wrapped .. "\n"):gmatch("([^\n]*)\n") do
				DrawString(px + LP_LINE_X, py + y, "LEFT", 13, "VAR", line)
				y = y + WRAP_H
			end
			y = y + 2
		end
	end
end

-- =============================================================================
-- Draw
-- =============================================================================
function CraftingPopupClass:Draw(viewPort)
	-- Reset alpha to 1.0 in case the dim overlay (SetDrawColor 0,0,0,0.5) left a
	-- persistent alpha state in the rendering context.
	SetDrawColor(1, 1, 1, 1)
	local px, py = self:GetPos()
	px = m_floor(px); py = m_floor(py)
	local pw, ph = self:GetSize()
	pw = m_floor(pw); ph = m_floor(ph)

	-- Popup background
	SetDrawColor(0.05, 0.05, 0.05, 1)
	DrawImage(nil, px, py, pw, ph)

	-- Outer border
	SetDrawColor(0.4, 0.35, 0.2)
	DrawImage(nil, px,          py,          pw, 2)
	DrawImage(nil, px,          py + ph - 2, pw, 2)
	DrawImage(nil, px,          py,          2,  ph)
	DrawImage(nil, px + pw - 2, py,          2,  ph)

	-- Title
	SetDrawColor(1, 1, 1)
	DrawString(px + m_floor(LEFT_W / 2), py + 12, "CENTER_X", 16, "VAR",
		"^7" .. (self.editItem and ("Craft - " .. (self.editItem.baseName or "")) or "Craft Item"))

	-- -------------------------------------------------------------------------
	-- Vertical divider
	-- -------------------------------------------------------------------------
	SetDrawColor(0.25, 0.25, 0.25)
	DrawImage(nil, px + DIVIDER_X, py + 30, 1, ph - 32)

	-- Top horizontal separator
	SetDrawColor(0.3, 0.3, 0.3)
	DrawImage(nil, px + 4, py + 30, pw - 8, 1)

	-- -------------------------------------------------------------------------
	-- Left panel: type list
	-- -------------------------------------------------------------------------
	local tlX  = px + 4
	local tlY  = py + TYPE_LIST_Y
	local tlW  = LEFT_W - 8
	local tlH  = TYPE_LIST_H
	local rowH = TYPE_ROW_H

	-- Type list background
	SetDrawColor(0.08, 0.08, 0.08)
	DrawImage(nil, tlX, tlY, tlW, tlH)

	-- Compute visible range
	local mx, my = GetCursorPos()
	local isInTypeList = mx >= tlX and mx < tlX + tlW and my >= tlY and my < tlY + tlH

	-- Clamp scroll
	local totalTypeH = #self.orderedTypeList * rowH
	local maxScroll  = m_max(0, totalTypeH - tlH)
	self.typeScrollY = m_max(0, m_min(self.typeScrollY, maxScroll))

	-- Rebuild typeCards for hit-testing
	self.typeCards = {}
	local visY = tlY - self.typeScrollY
	for i, entry in ipairs(self.orderedTypeList) do
		local cardY = visY + (i - 1) * rowH
		if cardY >= tlY and cardY + rowH <= tlY + tlH then
			if not entry.isSeparator then
				t_insert(self.typeCards, { y1 = cardY, y2 = cardY + rowH, entry = entry, index = i })
			end
			-- Background highlight for selected type
			local isSelected = (i == self.selectedTypeIndex)
			local isHovered  = isInTypeList and mx >= tlX and mx < tlX + tlW
			              and my >= cardY and my < cardY + rowH

			if entry.isSeparator then
				-- Category header row
				SetDrawColor(0.12, 0.12, 0.12)
				DrawImage(nil, tlX, cardY, tlW, rowH)
				SetDrawColor(0.55, 0.55, 0.55)
				local headerText = entry.label:gsub("%^8", "")
				DrawString(tlX + 4, cardY + 3, "LEFT", 12, "VAR", "^8" .. headerText)
			else
				-- Row background for selected/hovered state
				if isSelected then
					SetDrawColor(0.20, 0.18, 0.10)
					DrawImage(nil, tlX, cardY, tlW, rowH)
					SetDrawColor(0.8, 0.75, 0.4)
					DrawImage(nil, tlX, cardY, 2, rowH)
				elseif isHovered then
					SetDrawColor(0.14, 0.14, 0.14)
					DrawImage(nil, tlX, cardY, tlW, rowH)
				end
				-- 16x16 type icon (leaves room for text to the right)
				local iconH = getTypeIcon(entry.typeName)
				local textX = tlX + 6
				if iconH then
					SetDrawColor(1, 1, 1)
					DrawImage(iconH, tlX + 6, cardY + 2, 16, 16)
					textX = tlX + 6 + 16 + 4
				end
				SetDrawColor(1, 1, 1)
				local color = isSelected and "^7" or "^8"
				DrawString(textX, cardY + 3, "LEFT", 13, "VAR", color .. (entry.typeName or entry.label))
			end
		end
	end

	-- Type list bottom border
	SetDrawColor(0.25, 0.25, 0.25)
	DrawImage(nil, tlX, tlY + tlH, tlW, 1)

	-- -------------------------------------------------------------------------
	-- Left panel: item preview header (below type list)
	-- -------------------------------------------------------------------------
	if self.editItem then
		local item = self.editItem
		-- Type and Lv req row
		local lvReq = item.base and item.base.req and item.base.req.level or 0
		local typeStr = (item.base and item.base.type or item.type or "") ..
			(lvReq > 0 and ("  Lv " .. tostring(lvReq)) or "")
		SetDrawColor(1, 1, 1)
		DrawString(px + LP_LABEL_X, py + PREVIEW_Y + 22, "LEFT", 12, "VAR", "^8" .. typeStr)

		-- Divider below item name area
		SetDrawColor(0.2, 0.2, 0.2)
		DrawImage(nil, px + 4, py + PREVIEW_Y + 38, LEFT_W - 8, 1)

		-- Alternating affix background bands in the preview
		if self.editY.affixBands and #self.editY.affixBands > 0 then
			local bandX = px + LP_LINE_X - 2
			local bandW = LEFT_W - LP_LINE_X - 2
			for i, band in ipairs(self.editY.affixBands) do
				if i % 2 == 1 then
					SetDrawColor(0.14, 0.14, 0.16)
				else
					SetDrawColor(0.09, 0.09, 0.11)
				end
				DrawImage(nil, bandX, py + band.y - 1, bandW, band.h)
			end
		end

		if self:IsSetItem() or (self.editItem and self.editItem.setInfo and self.editItem.setInfo.setId ~= nil) then
			self:DrawSetInfo(px, py)
		end
	end

	-- -------------------------------------------------------------------------
	-- Right panel: background
	-- -------------------------------------------------------------------------
	local rpX = px + RP_X
	local rpY = py
	SetDrawColor(0.06, 0.06, 0.06)
	DrawImage(nil, rpX, rpY + 30, RP_W - 1, ph - 32)

	-- -------------------------------------------------------------------------
	-- Right panel: card content area
	-- -------------------------------------------------------------------------
	local cardAreaX = rpX + RP_CARD_PAD
	local cardAreaY = py + RP_CARD_Y
	local cardAreaW = RP_W - 2 * RP_CARD_PAD
	local cardAreaH = ph - RP_CARD_Y - 8

	self.rightCards = {}

	if self.rightTab == "item" then
		self:DrawItemCards(cardAreaX, cardAreaY, cardAreaW, cardAreaH, mx, my)
	else
		self:DrawAffixCards(cardAreaX, cardAreaY, cardAreaW, cardAreaH, mx, my)
	end

	-- -------------------------------------------------------------------------
	-- Draw Controls (overlays drawn items)
	-- -------------------------------------------------------------------------
	self:DrawControls(viewPort)

	-- Hover tooltip for affix right-panel cards (both list and card modes)
	if self.rightTab ~= "item" then
		for _, card in ipairs(self.rightCards or {}) do
			if card.entry and mx >= card.x1 and mx < card.x2 and my >= card.y1 and my < card.y2 then
				if not self.affixCardTooltip then
					self.affixCardTooltip = new("Tooltip")
				end
				self.affixCardTooltip:Clear()
				self:BuildAffixTooltip(self.affixCardTooltip, card.entry.statOrderKey)
				-- Offset tooltip from cursor so the first character isn't covered by the pointer.
				-- Passing a cursor "box" (w,h) engages Tooltip's edge-clamping path.
				self.affixCardTooltip:Draw(mx, my, 12, 12, viewPort)
				break
			end
		end
	end
end

-- Draw item cards in the right panel
function CraftingPopupClass:DrawItemCards(areaX, areaY, areaW, areaH, mx, my)
	local list = self.currentItemList or {}
	if #list == 0 then
		SetDrawColor(1, 1, 1)
		DrawString(areaX + 4, areaY + 20, "LEFT", 14, "VAR", "^8No items found.")
		return
	end

	-- Category detection: unique/set/ww cards show full implicits + modifiers
	-- (single-column, variable-height). Basic cards keep the 2-col 80px grid.
	local firstCat = list[1] and list[1].category
	local isDetail = (firstCat == "unique" or firstCat == "set" or firstCat == "ww")

	local IMG = 46
	local DETAIL_FONT = 14       -- bumped from 12
	local DETAIL_LINE_H = 18     -- bumped from 16 to match font
	-- Approx char width for font size 14, VAR font (~7.2 px/char empirically)
	local DETAIL_CHAR_W = 7.2
	-- computeWrapLines returns the total number of visual lines after wrapping
	local function computeWrapLines(text, maxChars)
		if not text then return 0 end
		return #wrapTextLine(text, maxChars)
	end

	-- Helper: compute card height given entry (detail mode)
	local function computeCardH(entry)
		-- Card's text area width = cw - 12 (6px pad each side), chars = width / charW
		local lineW = IC_W - 12
		local maxLineChars = m_max(10, m_floor(lineW / DETAIL_CHAR_W))
		local nImplLines = 0
		if entry.base and entry.base.implicits then
			for _, implText in ipairs(entry.base.implicits) do
				local cleaned = cleanImplicitText(implText)
				if cleaned then
					nImplLines = nImplLines + computeWrapLines(cleaned, maxLineChars)
				end
			end
		end
		local mods
		if entry.category == "set" then
			mods = entry.setData and entry.setData.mods
		else
			mods = entry.uniqueData and entry.uniqueData.mods
		end
		local nModLines = 0
		if mods then
			for _, modText in ipairs(mods) do
				local cleaned = cleanImplicitText(modText)
				if cleaned then
					nModLines = nModLines + computeWrapLines(cleaned, maxLineChars)
				end
			end
		end
		local sep = (nImplLines > 0 and nModLines > 0) and 6 or 0
		-- Set info block (name + members + bonuses) for set items
		local setExtraH = 0
		if entry.category == "set" and entry.setData and entry.setData.set then
			local set = entry.setData.set
			-- "ItemSet Name" header (1 line) + members + "Set Bonuses" header + bonuses
			setExtraH = setExtraH + DETAIL_LINE_H    -- set name header
			local memberCount = 0
			for _, si in pairs(self.setItems or {}) do
				if si.set and si.set.setId == set.setId then memberCount = memberCount + 1 end
			end
			setExtraH = setExtraH + memberCount * DETAIL_LINE_H
			if set.bonus and next(set.bonus) then
				setExtraH = setExtraH + DETAIL_LINE_H  -- "Set Bonuses" header
				for k, v in pairs(set.bonus) do
					local bl = tostring(k) .. " set: " .. tostring(v)
					setExtraH = setExtraH + computeWrapLines(bl, maxLineChars) * DETAIL_LINE_H
				end
			end
			setExtraH = setExtraH + 6  -- top gap
		end
		-- Header: name(18) + type(16) + level(16) = ~58, then per-line DETAIL_LINE_H
		local h = 4 + 18 + 16 + 16 + 4 + (nImplLines + nModLines) * DETAIL_LINE_H + sep + setExtraH + 8
		return m_max(IC_H, h)
	end

	-- Precompute layout
	local cardHs, cardYs = {}, {}
	local totalH

	if isDetail then
		-- 2-column grid; each row shares the max height of its pair so the two
		-- cards on the same row are the same size.
		local y = 0
		for i = 1, #list, IC_COLS do
			local rowH = 0
			for j = 0, IC_COLS - 1 do
				local idx = i + j
				if list[idx] then
					local h = computeCardH(list[idx])
					if h > rowH then rowH = h end
				end
			end
			for j = 0, IC_COLS - 1 do
				local idx = i + j
				if list[idx] then
					cardHs[idx] = rowH
					cardYs[idx] = y
				end
			end
			y = y + rowH + IC_GAP
		end
		totalH = y
	else
		local rows = m_ceil(#list / IC_COLS)
		totalH     = rows * (IC_H + IC_GAP)
	end

	local maxScroll  = m_max(0, totalH - areaH)
	self.rightScrollY = m_max(0, m_min(self.rightScrollY, maxScroll))

	self.rightCards = {}
	local scrollY = self.rightScrollY

	-- Clip card rendering to the card area so cards that scroll above/below
	-- the area don't overlap the tab bar or other popup controls. SetViewport
	-- both clips and translates the origin, so all card draw coordinates
	-- below are relative to (areaX, areaY). Hit-test rects are still stored
	-- in absolute screen coordinates.
	SetViewport(areaX, areaY, areaW, areaH)

	for i, entry in ipairs(list) do
		local ax, ay, cw, ch         -- absolute screen coords (for hit-test)
		local col = (i - 1) % IC_COLS
		if isDetail then
			ax = areaX + col * (IC_W + IC_GAP)
			ay = areaY + cardYs[i] - scrollY
			cw = IC_W
			ch = cardHs[i]
		else
			local row = m_floor((i - 1) / IC_COLS)
			ax = areaX + col * (IC_W + IC_GAP)
			ay = areaY + row * (IC_H + IC_GAP) - scrollY
			cw = IC_W
			ch = IC_H
		end
		local ax2, ay2 = ax + cw, ay + ch
		-- Viewport-relative coords for drawing
		local cx = ax - areaX
		local cy = ay - areaY

		if ay2 > areaY and ay < areaY + areaH then
			t_insert(self.rightCards, { x1=ax, y1=ay, x2=ax2, y2=ay2, entry=entry })

			local isSelected = self.editBaseEntry and self.editBaseEntry.name == entry.name
			local isHovered  = mx >= ax and mx < ax2 and my >= ay and my < ay2

			-- Card background
			if isSelected then
				SetDrawColor(0.18, 0.16, 0.08)
			elseif isHovered then
				SetDrawColor(0.14, 0.14, 0.14)
			else
				SetDrawColor(0.10, 0.10, 0.10)
			end
			DrawImage(nil, cx, cy, cw, ch)

			-- Left accent bar (rarity color)
			local col3 = colorCodes[entry.rarity] or colorCodes.NORMAL
			local r, g, b = col3:match("%^x(%x%x)(%x%x)(%x%x)")
			if r then
				SetDrawColor(tonumber(r,16)/255, tonumber(g,16)/255, tonumber(b,16)/255)
			else
				SetDrawColor(0.5, 0.5, 0.5)
			end
			DrawImage(nil, cx, cy, 3, ch)

			-- Item image (46x46, left side)
			local imgHandle = self:GetItemImage(entry.name, entry.rarity)
			if imgHandle and imgHandle:IsValid() then
				SetDrawColor(1, 1, 1)
				DrawImage(imgHandle, cx + 4, cy + 4, IMG, IMG)
			end
			local textX = cx + IMG + 8
			local textW = cw - IMG - 12

			-- Item name (line 1)
			local maxChars = m_floor(textW / 7)
			local label = entry.label or entry.name
			local truncLabel = #label > maxChars and label:sub(1, maxChars - 2) .. ".." or label
			DrawString(textX, cy + 4, "LEFT", 16, "VAR", (col3 or "^7") .. truncLabel)

			-- Item type (line 2)
			local typeStr = "^8" .. (entry.displayType or "")
			DrawString(textX, cy + 24, "LEFT", 14, "VAR", typeStr)

			-- Level requirement (line 3)
			local lvReq = entry.base and entry.base.req and entry.base.req.level or 0
			if lvReq > 0 then
				DrawString(textX, cy + 40, "LEFT", 14, "VAR", "^8Lv. " .. tostring(lvReq))
			end

			if isDetail then
				-- Full implicits + modifiers list, spans full card width below header
				local lineX = cx + 6
				local lineW = cw - 12
				local maxLineChars = m_max(10, m_floor(lineW / DETAIL_CHAR_W))
				local ly = cy + 58
				-- Alternating affix background: each affix (implicit or modifier)
				-- gets its own bg band so wrapped lines visually group together.
				local affixIdx = 0
				local function drawAffix(text, color)
					if not text then return end
					local lines = wrapTextLine(text, maxLineChars)
					local blockH = #lines * DETAIL_LINE_H
					affixIdx = affixIdx + 1
					-- Alternating bands: darker/lighter based on affixIdx parity.
					if affixIdx % 2 == 1 then
						SetDrawColor(0.14, 0.14, 0.16)
					else
						SetDrawColor(0.09, 0.09, 0.11)
					end
					DrawImage(nil, lineX - 2, ly - 1, lineW + 4, blockH)
					for _, ln in ipairs(lines) do
						DrawString(lineX, ly, "LEFT", DETAIL_FONT, "VAR", (color or "^8") .. ln)
						ly = ly + DETAIL_LINE_H
					end
				end
				if entry.base and entry.base.implicits then
					for _, implText in ipairs(entry.base.implicits) do
						drawAffix(cleanImplicitText(implText), "^x8888FF")
					end
				end
				local mods
				if entry.category == "set" then
					mods = entry.setData and entry.setData.mods
				else
					mods = entry.uniqueData and entry.uniqueData.mods
				end
				if mods and #mods > 0 then
					if entry.base and entry.base.implicits and #entry.base.implicits > 0 then
						ly = ly + 6
					end
					for _, modText in ipairs(mods) do
						drawAffix(cleanImplicitText(modText), "^7")
					end
				end
				-- Set info block (set item only)
				if entry.category == "set" and entry.setData and entry.setData.set then
					local set = entry.setData.set
					ly = ly + 6
					-- Set name header
					DrawString(lineX, ly, "LEFT", DETAIL_FONT, "VAR",
						colorCodes.SET .. (set.name or "Set"))
					ly = ly + DETAIL_LINE_H
					-- Members (sorted by name)
					local members = {}
					for _, si in pairs(self.setItems or {}) do
						if si.set and si.set.setId == set.setId then
							t_insert(members, si)
						end
					end
					table.sort(members, function(a, b) return (a.name or "") < (b.name or "") end)
					for _, si in ipairs(members) do
						DrawString(lineX + 4, ly, "LEFT", DETAIL_FONT, "VAR",
							"^8" .. (si.name or ""))
						ly = ly + DETAIL_LINE_H
					end
					-- Bonuses
					if set.bonus and next(set.bonus) then
						DrawString(lineX, ly, "LEFT", DETAIL_FONT, "VAR",
							colorCodes.SET .. "Set Bonuses")
						ly = ly + DETAIL_LINE_H
						local bonusKeys = {}
						for k in pairs(set.bonus) do t_insert(bonusKeys, k) end
						table.sort(bonusKeys, function(a, b) return tonumber(a) < tonumber(b) end)
						for _, k in ipairs(bonusKeys) do
							local bl = tostring(k) .. " set: " .. tostring(set.bonus[k])
							for _, ln in ipairs(wrapTextLine(bl, maxLineChars)) do
								DrawString(lineX + 4, ly, "LEFT", DETAIL_FONT, "VAR", "^7" .. ln)
								ly = ly + DETAIL_LINE_H
							end
						end
					end
				end
			else
				-- Basic card: single implicit line
				local implText
				if entry.base and entry.base.implicits and entry.base.implicits[1] then
					implText = cleanImplicitText(entry.base.implicits[1])
				end
				if implText then
					local maxImpl = m_floor(textW / 6.5)
					local truncImpl = #implText > maxImpl and implText:sub(1, maxImpl - 2) .. ".." or implText
					DrawString(textX, cy + 58, "LEFT", 14, "VAR", "^8" .. truncImpl)
				end
			end

			-- Card border
			if isSelected then
				SetDrawColor(0.8, 0.7, 0.3)
			elseif isHovered then
				SetDrawColor(0.35, 0.35, 0.35)
			else
				SetDrawColor(0.2, 0.2, 0.2)
			end
			DrawImage(nil, cx,      cy,      cw, 1)
			DrawImage(nil, cx,      cy+ch-1, cw, 1)
			DrawImage(nil, cx,      cy,      1, ch)
			DrawImage(nil, cx+cw-1, cy,      1, ch)
		end
	end
	SetViewport()

	-- Scrollbar
	if maxScroll > 0 then
		local sbX = areaX + areaW + 2
		local thH = m_max(20, m_floor(areaH * areaH / totalH))
		local thY = areaY + m_floor((areaH - thH) * self.rightScrollY / maxScroll)
		SetDrawColor(0.15, 0.15, 0.15)
		DrawImage(nil, sbX, areaY, 4, areaH)
		SetDrawColor(0.50, 0.45, 0.30)
		DrawImage(nil, sbX, thY, 4, thH)
	end
end

-- Draw affix cards in the right panel (list or card view)
function CraftingPopupClass:DrawAffixCards(areaX, areaY, areaW, areaH, mx, my)
	local slotKey  = self.rightTab
	-- Consolidated Prefix/Suffix tabs use the unfiltered pool so an affix assigned
	-- to P2/S2 doesn't vanish from the tab (prefix1/suffix1 filter it out).
	local listKey  = (slotKey == "prefix") and "prefix"
	              or (slotKey == "suffix") and "suffix"
	              or slotKey
	local list     = self.affixLists[listKey] or self.affixLists[slotKey] or {}
	local cardMode = (self.affixViewMode == "card")
	local rowH     = cardMode and 72 or AC_H   -- taller card rows for larger text
	local gap      = cardMode and 6  or AC_GAP
	local nCols    = cardMode and 2 or 1        -- card mode: 2-column layout
	local colGap   = 6
	local cardW    = cardMode and m_floor((areaW - colGap) / 2) or areaW

	-- List-mode layout (2-col cards with stat_name / craft_name / Tier N lines)
	local LIST_STAT_H  = 18  -- stat name header
	local LIST_CRAFT_H = 16  -- craft name subheader
	local LIST_TIER_H  = 15  -- per-tier line
	local LIST_PAD     = 6
	local listColGap   = 6
	local listCardW    = m_floor((areaW - listColGap) / 2)
	-- Kept for legacy single-col path (no longer used but harmless if referenced)
	local LIST_NAME_H = LIST_STAT_H
	-- Fetch + cache tier stat lines for an entry (reused from BuildAffixTooltip logic).
	local self_ref = self
	local function getAffixTierLines(entry)
		if entry._tierLines then return entry._tierLines end
		local function getMod(key)
			if self_ref:IsIdolAltar() then
				local altarMods = data.itemMods["Idol Altar"]
				return altarMods and altarMods[key]
			end
			local m = data.itemMods.Item and data.itemMods.Item[key]
			if not m and data.modIdol and data.modIdol.flat then m = data.modIdol.flat[key] end
			return m
		end
		-- Extract LETools-style "a to b%" or "n%" range from a cleaned stat line.
		local function extractRange(text)
			if not text or text == "" then return text or "" end
			-- Range in parentheses: (a-b) optionally followed by %
			local a, b, pct = text:match("%((%-?[%d%.]+)%-(%-?[%d%.]+)%)(%%?)")
			if a and b then
				return a .. (pct or "") .. " to " .. b .. (pct or "")
			end
			-- Single value: +5% or 6 or -2
			local sign, n, pct2 = text:match("([%+%-]?)([%d%.]+)(%%?)")
			if n then
				return (sign or "") .. n .. (pct2 or "")
			end
			return text
		end
		local out  = {}
		local maxT = entry.maxTier or 0
		for tier = 0, maxT do
			local mod = getMod(tostring(entry.statOrderKey) .. "_" .. tostring(tier))
			if mod then
				local parts, ranges = {}, {}
				for k = 1, 10 do
					local line = mod[k]
					if line and type(line) == "string" then
						local s = line:gsub("{rounding:%w+}", ""):gsub("{[^}]+}", "")
						t_insert(parts, s)
						t_insert(ranges, extractRange(s))
					end
				end
				t_insert(out, {
					tier = tier,
					text = table.concat(parts, ", "),
					range = table.concat(ranges, ", "),
					parts = parts,
					ranges = ranges,
				})
			end
		end
		entry._tierLines = out
		return out
	end

	if not self.editItem then
		SetDrawColor(1, 1, 1)
		DrawString(areaX + 4, areaY + 20, "LEFT", 14, "VAR", "^8Select an item first.")
		return
	end
	if #list == 0 then
		SetDrawColor(1, 1, 1)
		DrawString(areaX + 4, areaY + 20, "LEFT", 14, "VAR", "^8No affixes available.")
		return
	end

	-- Apply search filter
	local query = (self.searchText or ""):lower():gsub("^%s*(.-)%s*$", "%1")
	local filteredList = list
	if query ~= "" then
		filteredList = {}
		for _, entry in ipairs(list) do
			if (entry.label or ""):lower():find(query, 1, true) or
			   (entry.affix or ""):lower():find(query, 1, true) then
				t_insert(filteredList, entry)
			end
		end
	end

	-- For consolidated prefix/suffix tabs, check both slots for selection
	local function isEntrySelected(statOrderKey)
		if slotKey == "prefix" then
			return (self.affixState.prefix1.modKey == statOrderKey)
			    or (self.affixState.prefix2.modKey == statOrderKey)
		elseif slotKey == "suffix" then
			return (self.affixState.suffix1.modKey == statOrderKey)
			    or (self.affixState.suffix2.modKey == statOrderKey)
		else
			return self.affixState[slotKey] and self.affixState[slotKey].modKey == statOrderKey
		end
	end

	-- For consolidated tabs, find the active selected slot (for tier display)
	local function getSelectedSlotState(statOrderKey)
		if slotKey == "prefix" then
			if self.affixState.prefix1.modKey == statOrderKey then return self.affixState.prefix1, "P1" end
			if self.affixState.prefix2.modKey == statOrderKey then return self.affixState.prefix2, "P2" end
		elseif slotKey == "suffix" then
			if self.affixState.suffix1.modKey == statOrderKey then return self.affixState.suffix1, "S1" end
			if self.affixState.suffix2.modKey == statOrderKey then return self.affixState.suffix2, "S2" end
		else
			return self.affixState[slotKey], nil
		end
	end

	-- Phase 2: group entries by subcategory
	local SUBCAT_ORDER = { "general", "class_only", "set_only", "champion", "personal", "corrupted" }
	local SUBCAT_LABELS = {
		general    = "General",
		class_only = "Class Specific",
		set_only   = "Reforged / Set",
		champion   = "Champion",
		personal   = "Personal",
		corrupted  = "Corrupted Only",
	}
	local groups = {}
	for _, sc in ipairs(SUBCAT_ORDER) do groups[sc] = {} end
	for _, entry in ipairs(filteredList) do
		local sc = entry.subcategory or "general"
		if not groups[sc] then groups[sc] = {}; t_insert(SUBCAT_ORDER, sc) end
		t_insert(groups[sc], entry)
	end

	-- Build a flat render plan (headers + entries), respecting collapse state
	self.collapsedSubcats[slotKey] = self.collapsedSubcats[slotKey] or {}
	local collapsed = self.collapsedSubcats[slotKey]
	local HEADER_H = 20
	local plan = {}  -- each item: { kind="header"|"entry", subcat=..., entry=..., h=... }
	for _, sc in ipairs(SUBCAT_ORDER) do
		local g = groups[sc]
		if g and #g > 0 then
			-- Always show header if there is more than one non-empty subcat total, or if it's non-general.
			local showHeader = (sc ~= "general") or false
			-- If general is the only group, skip its header; otherwise show a header for it too.
			if sc == "general" then
				local otherNonEmpty = false
				for _, sc2 in ipairs(SUBCAT_ORDER) do
					if sc2 ~= "general" and groups[sc2] and #groups[sc2] > 0 then
						otherNonEmpty = true; break
					end
				end
				showHeader = otherNonEmpty
			end
			if showHeader then
				t_insert(plan, { kind = "header", subcat = sc, h = HEADER_H, count = #g })
			end
			if not collapsed[sc] then
				if cardMode then
					-- Pack entries into rows of up to nCols
					for i = 1, #g, nCols do
						local rowEntries = {}
						for k = 0, nCols - 1 do
							if g[i + k] then t_insert(rowEntries, g[i + k]) end
						end
						t_insert(plan, { kind = "entryRow", entries = rowEntries, h = rowH })
					end
				else
					-- List mode: 2-col rows with dynamic per-row height
					for i = 1, #g, 2 do
						local rowEntries = {}
						local maxH = 0
						for k = 0, 1 do
							local e = g[i + k]
							if e then
								t_insert(rowEntries, e)
								local tls = getAffixTierLines(e)
								local nT = #tls
								if nT == 0 then nT = 1 end
								local function isCraftName(s)
									if not s or s == "" or s == "UNKNOWN" then return false end
									if #s > 25 then return false end
									if s:find("[%%%(%)%+]") then return false end
									if s:find("%d") then return false end
									return true
								end
								local craftH = isCraftName(e.affix or "") and LIST_CRAFT_H or 0
								local headerH = 0
								if tls[1] and tls[1].ranges and #tls[1].ranges >= 2 then
									local function statName(s)
										if not s or s == "" then return "" end
										s = s:gsub("%b()%%?", "")
										s = s:gsub("[%+%-]?[%d%.]+%%?", "")
										s = s:gsub("^%s+", ""):gsub("%s+$", "")
										s = s:gsub("%s+", " ")
										return s
									end
									local parts0 = tls[1].parts or {}
									local tierColW = 48
									local colW = m_floor((listCardW - 18 - tierColW) / 2)
									local n1 = statName(parts0[1] or "")
									local n2 = statName(parts0[2] or "")
									local l1 = #main:WrapString(n1, 12, colW - 4)
									-- WrapString reuses wrapTable; copy length before second call
									local l2 = #main:WrapString(n2, 12, colW - 4)
									local hl = m_max(l1, l2, 1)
									headerH = hl * 13 + 2
								end
								local eH = LIST_PAD * 2 + LIST_STAT_H + craftH + headerH + nT * LIST_TIER_H
								if eH > maxH then maxH = eH end
							end
						end
						if maxH == 0 then maxH = LIST_PAD * 2 + LIST_STAT_H + LIST_CRAFT_H + LIST_TIER_H end
						t_insert(plan, { kind = "listRow", entries = rowEntries, h = maxH })
					end
				end
			end
		end
	end

	-- Compute total height
	local totalH = 0
	for _, it in ipairs(plan) do totalH = totalH + it.h + gap end
	local maxScroll = m_max(0, totalH - areaH)
	self.rightScrollY = m_max(0, m_min(self.rightScrollY, maxScroll))

	self.rightCards = {}
	local scrollY   = self.rightScrollY
	local yCursor   = areaY - scrollY

	for _, it in ipairs(plan) do
		local cy  = yCursor
		local cy2 = cy + it.h
		yCursor = cy2 + gap

		if it.kind == "header" then
			if cy < areaY + areaH and cy2 > areaY then
				-- Header hit-test + background
				t_insert(self.rightCards, { x1=areaX, y1=cy, x2=areaX+areaW, y2=cy2, isHeader=true, subcat=it.subcat })
				local isHoveredH = mx >= areaX and mx < areaX + areaW and my >= cy and my < cy2
				if isHoveredH then
					SetDrawColor(0.20, 0.20, 0.22)
				else
					SetDrawColor(0.13, 0.13, 0.16)
				end
				DrawImage(nil, areaX, cy, areaW, it.h)
				SetDrawColor(0.35, 0.35, 0.40)
				DrawImage(nil, areaX, cy2 - 1, areaW, 1)
				local arrow = collapsed[it.subcat] and "^7> " or "^7v "
				local title = arrow .. "^xFFCC66" .. (SUBCAT_LABELS[it.subcat] or it.subcat)
				              .. " ^8(" .. tostring(it.count) .. ")"
				DrawString(areaX + 8, cy + 2, "LEFT", 14, "VAR", title)
			end
		end
		if it.kind == "entryRow" then
			-- 2-column card row
			for ci, entry in ipairs(it.entries) do
				local cx1 = areaX + (ci - 1) * (cardW + colGap)
				local cx2 = cx1 + cardW
				if cy >= areaY and cy2 <= areaY + areaH then
					t_insert(self.rightCards, { x1=cx1, y1=cy, x2=cx2, y2=cy2, entry=entry })
					local isSelected = isEntrySelected(entry.statOrderKey)
					local isHovered  = mx >= cx1 and mx < cx2 and my >= cy and my < cy2
					-- Card background + border (distinct card look)
					if isSelected then
						SetDrawColor(0.30, 0.26, 0.10)
					elseif isHovered then
						SetDrawColor(0.18, 0.18, 0.20)
					else
						SetDrawColor(0.12, 0.12, 0.14)
					end
					DrawImage(nil, cx1, cy, cardW, rowH)
					-- Outer border
					SetDrawColor(isSelected and 0.70 or 0.32, isSelected and 0.60 or 0.32, isSelected and 0.22 or 0.36)
					DrawImage(nil, cx1, cy, cardW, 1)
					DrawImage(nil, cx1, cy2 - 1, cardW, 1)
					DrawImage(nil, cx1, cy, 1, rowH)
					DrawImage(nil, cx2 - 1, cy, 1, rowH)
					-- Left accent bar: Prefix=blue, Suffix=orange
					local typeStr = entry.type or ""
					if typeStr == "Prefix" then
						SetDrawColor(0.33, 0.60, 1.0)
					else
						SetDrawColor(1.0, 0.60, 0.33)
					end
					DrawImage(nil, cx1 + 1, cy + 1, 4, rowH - 2)
					-- Affix name
					local nameCol = isSelected and colorCodes.UNIQUE or "^7"
					DrawString(cx1 + 10, cy + 6, "LEFT", 15, "VAR",
						nameCol .. (entry.affix or entry.label or ""))
					-- First stat (description)
					local desc = entry.label or ""
					desc = desc:gsub("{rounding:%w+}", ""):gsub("{[^}]+}", "")
					local firstPart = desc:match("^(.-)%s*/%s*.+$") or desc
					local maxChars = m_floor((cardW - 20) / 7)
					if #firstPart > maxChars then firstPart = firstPart:sub(1, maxChars - 2) .. ".." end
					DrawString(cx1 + 10, cy + 26, "LEFT", 13, "VAR", "^8" .. firstPart)
					-- Tier range inside card (bottom-right)
					local maxT = entry.maxTier or 0
					local tierStr = maxT > 0
						and (TIER_COLORS[1] .. "Tier 1^8-" .. tierColor(maxT) .. "Tier " .. tostring(maxT + 1))
						or  (TIER_COLORS[1] .. "Tier 1")
					DrawString(cx2 - 8, cy + rowH - 18, "RIGHT", 13, "VAR", tierStr)
					-- Selection indicator
					if isSelected then
						local st, slotLabel = getSelectedSlotState(entry.statOrderKey)
						if st and st.modKey then
							local t1 = st.tier + 1
							local indicator = tierColor(st.tier) .. "Tier " .. tostring(t1)
							if slotLabel then indicator = indicator .. " ^8(" .. slotLabel .. ")" end
							DrawString(cx1 + 10, cy + rowH - 18, "LEFT", 13, "VAR", "^xFFCC44> " .. indicator)
						end
					end
				end
			end
		end
		if it.kind == "listRow" then
			local rowEntryH = it.h
			for ci, entry in ipairs(it.entries) do
				local cx1 = areaX + (ci - 1) * (listCardW + listColGap)
				local cx2 = cx1 + listCardW
				if cy < areaY + areaH and cy2 > areaY then
					t_insert(self.rightCards, { x1=cx1, y1=cy, x2=cx2, y2=cy2, entry=entry })
					local isSelected = isEntrySelected(entry.statOrderKey)
					local isHovered  = mx >= cx1 and mx < cx2 and my >= cy and my < cy2
					-- Card background
					if isSelected then
						SetDrawColor(0.22, 0.18, 0.06)
					elseif isHovered then
						SetDrawColor(0.14, 0.14, 0.16)
					else
						SetDrawColor(0.10, 0.10, 0.12)
					end
					DrawImage(nil, cx1, cy, listCardW, rowEntryH)
					-- Border
					SetDrawColor(isSelected and 0.78 or 0.26, isSelected and 0.64 or 0.26, isSelected and 0.16 or 0.30)
					DrawImage(nil, cx1, cy, listCardW, 1)
					DrawImage(nil, cx1, cy2 - 1, listCardW, 1)
					DrawImage(nil, cx1, cy, 1, rowEntryH)
					DrawImage(nil, cx2 - 1, cy, 1, rowEntryH)
					-- Accent bar: Prefix=blue, Suffix=orange
					local typeStr = entry.type or ""
					if typeStr == "Prefix" then
						SetDrawColor(0.33, 0.60, 1.0)
					else
						SetDrawColor(1.0, 0.60, 0.33)
					end
					DrawImage(nil, cx1 + 1, cy + 1, 3, rowEntryH - 2)

					local textX  = cx1 + 10
					local availW = listCardW - (textX - cx1) - 8
					local maxCh  = m_floor(availW / 6.8)

					-- Row 1: stat name (stripped label)
					local stat = (entry.label or ""):gsub("{rounding:%w+}", ""):gsub("{[^}]+}", "")
					stat = stat:match("^(.-)%s*/%s*.+$") or stat
					if #stat > maxCh then stat = stat:sub(1, maxCh - 2) .. ".." end
					local statCol = isSelected and colorCodes.UNIQUE or "^7"
					DrawString(textX, cy + LIST_PAD, "LEFT", 14, "VAR", statCol .. stat)

					-- Row 2: craft name (entry.affix) — only when it looks like a real name
					local rawCraft = entry.affix or ""
					local function isName(s)
						if not s or s == "" or s == "UNKNOWN" then return false end
						if #s > 25 then return false end
						if s:find("[%%%(%)%+]") then return false end
						if s:find("%d") then return false end
						return true
					end
					local hasCraft = isName(rawCraft)
					if hasCraft then
						local craft = rawCraft
						if #craft > maxCh then craft = craft:sub(1, maxCh - 2) .. ".." end
						DrawString(textX, cy + LIST_PAD + LIST_STAT_H, "LEFT", 12, "VAR",
							"^8" .. craft)
					end

					-- Row 3+: per-tier lines, LETools style "Tier N   a to b%"
					local tierLines = getAffixTierLines(entry)
					local selTier = nil
					if isSelected then
						local st = getSelectedSlotState(entry.statOrderKey)
						if st then selTier = st.tier end
					end
					local craftSkip = hasCraft and LIST_CRAFT_H or 0
					local lineY = cy + LIST_PAD + LIST_STAT_H + craftSkip

					-- Detect multi-modifier affix (2+ stat lines)
					local nMods = (tierLines[1] and tierLines[1].ranges) and #tierLines[1].ranges or 1
					if nMods >= 2 then
						-- Strip range tokens to get bare stat name
						local function statName(s)
							if not s or s == "" then return "" end
							s = s:gsub("%b()%%?", "")
							s = s:gsub("[%+%-]?[%d%.]+%%?", "")
							s = s:gsub("^%s+", ""):gsub("%s+$", "")
							s = s:gsub("%s+", " ")
							return s
						end
						local parts0 = tierLines[1].parts or {}
						local tierColW = 48
						local availColW = listCardW - (textX - cx1) - 8 - tierColW
						local colW = m_floor(availColW / 2)
						local tierX = textX + 2
						local col1X = tierX + tierColW
						local col2X = col1X + colW
						-- Header: two stat names with word-wrap
						local n1 = statName(parts0[1] or "")
						local n2 = statName(parts0[2] or "")
						local w1 = main:WrapString(n1, 12, colW - 4)
						local h1 = {}
						for k = 1, #w1 do h1[k] = w1[k] end
						local w2 = main:WrapString(n2, 12, colW - 4)
						local h2 = {}
						for k = 1, #w2 do h2[k] = w2[k] end
						local headerLines = m_max(#h1, #h2, 1)
						for k = 1, headerLines do
							if h1[k] then DrawString(col1X, lineY + (k - 1) * 13, "LEFT", 12, "VAR", "^8" .. h1[k]) end
							if h2[k] then DrawString(col2X, lineY + (k - 1) * 13, "LEFT", 12, "VAR", "^8" .. h2[k]) end
						end
						lineY = lineY + headerLines * 13 + 2
						for _, tl in ipairs(tierLines) do
							local tLabel = tierColor(tl.tier) .. "Tier " .. tostring(tl.tier + 1)
							local r1 = (tl.ranges and tl.ranges[1]) or ""
							local r2 = (tl.ranges and tl.ranges[2]) or ""
							local col = (selTier == tl.tier) and colorCodes.UNIQUE or tierColor(tl.tier)
							local marker = (selTier == tl.tier) and "  <<" or ""
							DrawString(tierX, lineY, "LEFT", 12, "VAR", tLabel)
							DrawString(col1X, lineY, "LEFT", 12, "VAR", col .. r1)
							DrawString(col2X, lineY, "LEFT", 12, "VAR", col .. r2 .. marker)
							lineY = lineY + LIST_TIER_H
						end
					else
						for _, tl in ipairs(tierLines) do
							local tLabel = tierColor(tl.tier) .. "Tier " .. tostring(tl.tier + 1)
							local txt = tl.range or tl.text or ""
							local budget = maxCh - 10
							if #txt > budget then txt = txt:sub(1, budget - 2) .. ".." end
							local marker = (selTier == tl.tier) and "  <<" or ""
							local col = (selTier == tl.tier) and colorCodes.UNIQUE or tierColor(tl.tier)
							DrawString(textX + 2, lineY, "LEFT", 13, "VAR",
								tLabel .. "   " .. col .. txt .. marker)
							lineY = lineY + LIST_TIER_H
						end
					end

					-- Selection right indicator
					if isSelected then
						local st, slotLabel = getSelectedSlotState(entry.statOrderKey)
						if st and st.modKey then
							local t1 = st.tier + 1
							local indicator = tierColor(st.tier) .. "Tier " .. tostring(t1)
							if slotLabel then indicator = indicator .. " ^8(" .. slotLabel .. ")" end
							DrawString(cx2 - 8, cy + LIST_PAD, "RIGHT", 12, "VAR",
								"^xFFCC44> " .. indicator)
						end
					end
				end
			end
		end
		if false and it.kind == "entry" then
			local entry = it.entry
			local entryH = it.h

			if cy < areaY + areaH and cy2 > areaY then
			t_insert(self.rightCards, { x1=areaX, y1=cy, x2=areaX+areaW, y2=cy2, entry=entry })

			local isSelected = isEntrySelected(entry.statOrderKey)
			local isHovered  = mx >= areaX and mx < areaX + areaW and my >= cy and my < cy2

			-- Card background
			if isSelected then
				SetDrawColor(0.18, 0.16, 0.08)
			elseif isHovered then
				SetDrawColor(0.14, 0.14, 0.14)
			else
				SetDrawColor(0.10, 0.10, 0.10)
			end
			DrawImage(nil, areaX, cy, areaW, entryH)

			-- Left accent bar: blue for Prefix, orange for Suffix
			local typeStr  = entry.type or ""
			if typeStr == "Prefix" then
				SetDrawColor(0.33, 0.60, 1.0)
			else
				SetDrawColor(1.0, 0.60, 0.33)
			end
			DrawImage(nil, areaX, cy, 3, entryH)

			-- Affix name
			local nameCol = isSelected and colorCodes.UNIQUE or "^7"
			local nameX   = areaX + 10
			local nameY   = cy + LIST_PAD
			DrawString(nameX, nameY, "LEFT", 14, "VAR",
				nameCol .. (entry.affix or entry.label or ""))

			-- Vertical tier list: "Tier N: <stat text>"
			local tierLines = getAffixTierLines(entry)
			local lineX   = areaX + 14
			local lineY   = cy + LIST_PAD + LIST_NAME_H
			local availW  = areaW - (lineX - areaX) - 10
			local maxCh   = m_floor(availW / 6.8)
			local selTier = nil
			if isSelected then
				local st = getSelectedSlotState(entry.statOrderKey)
				if st then selTier = st.tier end
			end
			for _, tl in ipairs(tierLines) do
				local tLabel = tierColor(tl.tier) .. "Tier " .. tostring(tl.tier + 1) .. ":"
				local txt = tl.text or ""
				if #txt > maxCh - 10 then txt = txt:sub(1, maxCh - 12) .. ".." end
				local marker = (selTier == tl.tier) and "  <<" or ""
				local col = (selTier == tl.tier) and colorCodes.UNIQUE or "^8"
				DrawString(lineX, lineY, "LEFT", 13, "VAR",
					tLabel .. " " .. col .. txt .. marker)
				lineY = lineY + LIST_TIER_H
			end

			-- Selection indicator bar
			if isSelected then
				SetDrawColor(0.8, 0.7, 0.3)
				DrawImage(nil, areaX, cy, 3, entryH)
				local st, slotLabel = getSelectedSlotState(entry.statOrderKey)
				if st and st.modKey then
					local t1 = st.tier + 1
					local indicator = tierColor(st.tier) .. "Tier " .. tostring(t1)
					if slotLabel then indicator = indicator .. " ^8(" .. slotLabel .. ")" end
					DrawString(areaX + areaW - 6, cy + LIST_PAD, "RIGHT", 13, "VAR", indicator)
				end
			end

			-- Row separator
			SetDrawColor(0.18, 0.18, 0.20)
			DrawImage(nil, areaX, cy2 - 1, areaW, 1)
		end
		end
	end

	-- Scrollbar on right border (visible when content overflows)
	if maxScroll > 0 then
		local sbX  = areaX + areaW + 2
		local sbH  = areaH
		local thH  = m_max(20, m_floor(areaH * areaH / totalH))
		local thY  = areaY + m_floor((sbH - thH) * self.rightScrollY / maxScroll)
		SetDrawColor(0.15, 0.15, 0.15)
		DrawImage(nil, sbX, areaY, 4, areaH)
		SetDrawColor(0.50, 0.45, 0.30)
		DrawImage(nil, sbX, thY, 4, thH)
	end
end

-- =============================================================================
-- Input handling
-- =============================================================================
function CraftingPopupClass:ProcessInput(inputEvents, viewPort)
	local mx, my = GetCursorPos()
	local px, py = self:GetPos()
	local pw, ph = self:GetSize()

	for id, event in ipairs(inputEvents) do
		if event.type == "KeyDown" then
			if event.key == "ESCAPE" then
				self:Close()
				return
			elseif event.key == "LEFTBUTTON" then
				-- Type list click
				local tlX = px + 4
				local tlY = py + TYPE_LIST_Y
				local tlW = LEFT_W - 8
				local tlH = TYPE_LIST_H
				if mx >= tlX and mx < tlX + tlW and my >= tlY and my < tlY + tlH then
					for _, card in ipairs(self.typeCards) do
						if my >= card.y1 and my < card.y2 then
							self.selectedTypeIndex = card.index
							self.rightScrollY = 0
							self.searchText   = ""
							if self.controls.rightSearch then
								self.controls.rightSearch:SetText("")
							end
							self:RefreshBaseList()
							break
						end
					end
				end

				-- Right panel card click
				local rpX = px + RP_X
				if mx >= rpX and mx < px + pw then
					for _, card in ipairs(self.rightCards) do
						if mx >= card.x1 and mx < card.x2 and my >= card.y1 and my < card.y2 then
							if card.isHeader then
								-- Toggle subcategory collapse state
								local slotKey = self.rightTab
								self.collapsedSubcats[slotKey] = self.collapsedSubcats[slotKey] or {}
								self.collapsedSubcats[slotKey][card.subcat] = not self.collapsedSubcats[slotKey][card.subcat]
							elseif self.rightTab == "item" then
								self:SelectBase(card.entry)
							else
								self:SelectAffixEntry(card.entry)
							end
							break
						end
					end
				end
			elseif event.key == "WHEELDOWN" then
				local tlX = px + 4
				local tlY = py + TYPE_LIST_Y
				local tlW = LEFT_W - 8
				local tlH = TYPE_LIST_H
				if mx >= tlX and mx < tlX + tlW and my >= tlY and my < tlY + tlH then
					self.typeScrollY = self.typeScrollY + TYPE_ROW_H * 3
				elseif mx >= px + RP_X and mx < px + pw then
					local rowStep = (self.rightTab ~= "item" and self.affixViewMode == "card") and 54 or AC_H
					self.rightScrollY = self.rightScrollY + rowStep * 3
				end
			elseif event.key == "WHEELUP" then
				local tlX = px + 4
				local tlY = py + TYPE_LIST_Y
				local tlW = LEFT_W - 8
				local tlH = TYPE_LIST_H
				if mx >= tlX and mx < tlX + tlW and my >= tlY and my < tlY + tlH then
					self.typeScrollY = self.typeScrollY - TYPE_ROW_H * 3
				elseif mx >= px + RP_X and mx < px + pw then
					local rowStep = (self.rightTab ~= "item" and self.affixViewMode == "card") and 54 or AC_H
					self.rightScrollY = self.rightScrollY - rowStep * 3
				end
			end
		end
	end

	self:ProcessControlsInput(inputEvents, viewPort)
end
