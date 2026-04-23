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
local POPUP_W            = H.POPUP_W
local LEFT_W             = H.LEFT_W
local PREVIEW_Y          = H.PREVIEW_Y
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

	-- Top horizontal separator
	SetDrawColor(0.3, 0.3, 0.3)
	DrawImage(nil, px + 4, py + 30, pw - 8, 1)

	local mx, my = GetCursorPos()

	-- -------------------------------------------------------------------------
	-- Item preview
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
	-- Draw Controls (overlays drawn items)
	-- -------------------------------------------------------------------------
	self:DrawControls(viewPort)

	-- Hover tooltip: DPS/stat diff preview over the item preview header.
	if self.editItem then
		local hx1, hx2 = px + 4, px + LEFT_W - 4
		local hy1, hy2 = py + PREVIEW_Y, py + PREVIEW_Y + 38
		if mx >= hx1 and mx < hx2 and my >= hy1 and my < hy2 then
			if not self.previewDiffTooltip then
				self.previewDiffTooltip = new("Tooltip")
			end
			self.previewDiffTooltip:Clear()
			self:BuildPreviewDiffTooltip(self.previewDiffTooltip)
			self.previewDiffTooltip:Draw(mx, my, 12, 12, viewPort)
		end
	end
end

-- =============================================================================
-- Input handling
-- =============================================================================
function CraftingPopupClass:ProcessInput(inputEvents, viewPort)
	for id, event in ipairs(inputEvents) do
		if event.type == "KeyDown" and event.key == "ESCAPE" then
			self:Close()
			return
		end
	end
	self:ProcessControlsInput(inputEvents, viewPort)
end
