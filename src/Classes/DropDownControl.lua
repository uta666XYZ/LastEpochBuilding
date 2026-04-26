-- Last Epoch Building
--
-- Class: DropDown Control
-- Basic drop down control.
--
local ipairs = ipairs
local m_min = math.min
local m_max = math.max
local m_floor = math.floor

local DropDownClass = newClass("DropDownControl", "Control", "ControlHost", "TooltipHost", "SearchHost", function(self, anchor, x, y, width, height, list, selFunc, tooltipText)
	self.Control(anchor, x, y, width, height)
	self.ControlHost()
	self.TooltipHost(tooltipText)
	self.SearchHost(
			-- list to filter
			function()
				return self.list
			end,
			-- value mapping function
			function(listVal)
				return StripEscapes(type(listVal) == "table" and listVal.label or listVal)
			end
	)
	self.controls.scrollBar = new("ScrollBarControl", {"TOPRIGHT",self,"TOPRIGHT"}, -1, 0, 18, 0, (height - 4) * 4)
	self.controls.scrollBar.height = function()
		return self.dropHeight + 2
	end
	self.controls.scrollBar.shown = function()
		return self.dropped and self.controls.scrollBar.enabled
	end
	self.dropHeight = 0
	self:SetList(list or { })
	self.selIndex = 1
	self.selFunc = selFunc
	-- Current value of the width of the dropped component
	self.droppedWidth = self.width
	-- Set by the parent control. The maximum width of the dropped component will go to.
	self.maxDroppedWidth = m_max(self.width, 300)
	-- Set by the parent control. Activates the auto width of the dropped component.
	self.enableDroppedWidth = false
	-- Set by the parent control. Activates the auto width of the box component.
	self.enableChangeBoxWidth = false
	-- self.tag = "-"
end)

-- Collapsible group headers: a list entry with `isHeader = true` is rendered
-- distinctly and is not selectable; clicking it toggles `collapsed`, which
-- hides subsequent non-header entries until the next header.
function DropDownClass:IsListItemVisible(index)
	local item = self.list[index]
	if not item then return false end
	if type(item) == "table" and item.isHeader then return true end
	-- Scan back for the most recent header
	for i = index - 1, 1, -1 do
		local prev = self.list[i]
		if type(prev) == "table" and prev.isHeader then
			return not prev.collapsed
		end
	end
	return true
end

function DropDownClass:IsListItemDropped(index)
	if not self:IsListItemVisible(index) then return false end
	if self:IsSearchActive() then
		local item = self.list[index]
		if type(item) == "table" and item.isHeader then return true end
		local info = self.searchInfos[index]
		return info and info.matches
	end
	return true
end

-- maps the actual dropdown row index (after eventual filtering) to the original (unfiltered) list index
function DropDownClass:DropIndexToListIndex(dropIndex)
	if not dropIndex or dropIndex <= 0 then return nil end
	local n = 0
	for i = 1, #self.list do
		if self:IsListItemDropped(i) then
			n = n + 1
			if n == dropIndex then return i end
		end
	end
	return nil
end

-- maps the original (unfiltered) list index to the actual dropdown row index (after eventual filtering)
function DropDownClass:ListIndexToDropIndex(listIndex, default)
	if not listIndex or listIndex <= 0 or listIndex > #self.list then return nil end
	local n = 0
	for i = 1, #self.list do
		if self:IsListItemDropped(i) then
			n = n + 1
			if i == listIndex then return n end
		end
	end
	return default
end

function DropDownClass:GetDropCount()
	local n = 0
	for i = 1, #self.list do
		if self:IsListItemDropped(i) then n = n + 1 end
	end
	return n
end

function DropDownClass:DrawSearchHighlights(label, searchInfo, x, y, width, height)
	if searchInfo and searchInfo.matches then
		local startX = 0
		local endX = 0
		local last = 0
		SetDrawColor(1, 1, 0, 0.2)
		for _, range in ipairs(searchInfo.ranges) do
			if range.from - last - 1 > 0 then
				startX = DrawStringWidth(height, "VAR", label:sub(last + 1, range.from - 1)) + x + endX
			else
				startX = endX
			end
			endX = DrawStringWidth(height, "VAR", label:sub(range.from, range.to)) + x + startX
			last = range.to

			DrawImage(nil, startX, y, endX - startX, height)
		end
		SetDrawColor(1, 1, 1)
	end
end


function DropDownClass:SelByValue(value, key)
	for index, listVal in ipairs(self.list) do
		if type(listVal) == "table" then
			if listVal[key] == value then
				self.selIndex = index
				return
			end
		else
			if listVal == value then
				self.selIndex = index
				return
			end
		end
	end
end

function DropDownClass:GetSelValue(key)
	return self.list[self.selIndex][key]
end

function DropDownClass:SetSel(newSel, noCallSelFunc)
	local count = self:GetDropCount()
	if count == 0 then return end
	newSel = m_max(1, m_min(count, newSel))
	-- If target is a header, advance past it in the direction of motion so
	-- keyboard nav never stalls on a group divider.
	local curDrop = self:ListIndexToDropIndex(self.selIndex, 0) or 0
	local dir = (newSel >= curDrop) and 1 or -1
	for _ = 1, count do
		local listIdx = self:DropIndexToListIndex(newSel)
		local item = listIdx and self.list[listIdx]
		if not (type(item) == "table" and item.isHeader) then
			if listIdx and listIdx ~= self.selIndex then
				self.selIndex = listIdx
				if not noCallSelFunc and self.selFunc then
					self.selFunc(listIdx, self.list[listIdx])
				end
			end
			return
		end
		newSel = newSel + dir
		if newSel < 1 or newSel > count then return end
	end
end

function DropDownClass:ScrollSelIntoView()
	local width, height = self:GetSize()
	local itemLineH = 20
	local scrollBar = self.controls.scrollBar
	scrollBar:SetContentDimension(itemLineH * self:GetDropCount(), self.dropHeight)
	scrollBar:ScrollIntoView((self:ListIndexToDropIndex(self.selIndex, 1) - 2) * itemLineH, 3 * itemLineH)
end

function DropDownClass:IsMouseOver()
	if not self:IsShown() then
		return false
	end
	if self:GetMouseOverControl() then
		return true
	end
	local x, y = self:GetPos()
	local width, height = self:GetSize()
	local cursorX, cursorY = GetCursorPos()
	local dropExtra = self.dropped and self.dropHeight + 2 or 0
	local mOver

	if self.dropped then
		width = m_max(width, self.droppedWidth)
		if self.dropUp then
			mOver = cursorX >= x and cursorY >= y - dropExtra and cursorX < x + width and cursorY < y + height
		else
			mOver = cursorX >= x and cursorY >= y and cursorX < x + width and cursorY < y + height + dropExtra
		end
	else
		mOver = cursorX >= x and cursorY >= y and cursorX < x + width and cursorY < y + height
	end
	local mOverComp
	if mOver then
		if cursorY >= y and cursorY < y + height then
			mOverComp = "BODY"
		else
			mOverComp = "DROP"
		end
	end
	return mOver, mOverComp
end

function DropDownClass:Draw(viewPort, noTooltip)
	local x, y = self:GetPos()
	local width, height = self:GetSize()
	local enabled = self:IsEnabled()
	local scrollBar = self.controls.scrollBar
	local lineHeight = height - 4
	local itemLineH = 20  -- fixed item row height (font 16 + 4px padding)
	self.dropHeight = itemLineH * m_min(#self.list, 20)
	scrollBar.y = height + 1
	if y + height + self.dropHeight + 4 <= viewPort.y + viewPort.height then
		-- Drop fits below body
		self.dropUp = false
	else
		local linesAbove = m_floor((y - viewPort.y - 4) / itemLineH)
		local linesBelow = m_floor((viewPort.y + viewPort.height - y - height - 4) / itemLineH)
		if linesAbove > linesBelow then
			-- There's more room above the body than below
			self.dropUp = true
			if y - viewPort.y < self.dropHeight + 4 then
				-- Still doesn't fit, so clip it
				self.dropHeight = itemLineH * linesAbove
			end
			scrollBar.y = -self.dropHeight - 3
		else
			-- Doesn't fit below body, so clip it
			self.dropUp = false
			self.dropHeight = itemLineH * linesBelow
		end
	end

	if self:IsSearchActive() and not self.dropped then
		self:ResetSearch()
	end

	-- fit dropHeight to filtered content but keep initial orientation
	self.dropHeight = m_max(m_min(self.dropHeight, self:GetDropCount() * itemLineH), itemLineH)

	-- Clamp droppedWidth so the drop panel never extends past the viewport's
	-- right edge (prevents clipping on narrow windows). Long labels that no
	-- longer fit are shown via hover tooltip.
	local viewRight = viewPort.x + viewPort.width
	local availW = m_max(self.width, viewRight - x - 2)
	if self.droppedWidth > availW then
		self.droppedWidth = availW
		self.controls.scrollBar.x = self.droppedWidth - self.width - 1
	end

	local mOver, mOverComp = self:IsMouseOver()
	local dropExtra = self.dropHeight + 4
	scrollBar:SetContentDimension(itemLineH * self:GetDropCount(), self.dropHeight)
	local dropY = self.dropUp and y - dropExtra or y + height
	if not enabled then
		SetDrawColor(0.33, 0.33, 0.33)
	elseif mOver or self.dropped then
		SetDrawColor(1, 1, 1)
	elseif self.borderFunc then
		local r, g, b = self.borderFunc()
		SetDrawColor(r, g, b)
	else
		SetDrawColor(0.5, 0.5, 0.5)
	end
	DrawImage(nil, x, y, width, height)
	if self.dropped then
		SetDrawLayer(nil, 5)
		DrawImage(nil, x, dropY, self.droppedWidth, dropExtra)
		SetDrawLayer(nil, 0)
	end
	if not enabled then
		SetDrawColor(0, 0, 0)
	elseif self.dropped then
		SetDrawColor(0.5, 0.5, 0.5)
	elseif mOver then
		SetDrawColor(0.33, 0.33, 0.33)
	else
		SetDrawColor(0, 0, 0)
	end
	DrawImage(nil, x + 1, y + 1, width - 2, height - 2)
	if not enabled then
		SetDrawColor(0.33, 0.33, 0.33)
	elseif mOver or self.dropped then
		SetDrawColor(1, 1, 1)
	else
		SetDrawColor(0.5, 0.5, 0.5)
	end
	local arrowH = self.arrowH or (height / 2)
	if self.emptyPlusMarker then
		-- Centered "+" marker (used by idol grid cells to match blessing slot style)
		local cx = x + width / 2
		local cy = y + height / 2
		local len = arrowH
		DrawString(cx, cy - len / 2 - 1, "CENTER_X", len, "VAR", "+")
	else
		main:DrawArrow(x + width - height/2, y + height/2, arrowH, arrowH, "DOWN")
	end
	if self.dropped then
		SetDrawLayer(nil, 5)
		SetDrawColor(0, 0, 0)
		DrawImage(nil, x + 1, dropY + 1, self.droppedWidth - 2, dropExtra - 2)
		SetDrawLayer(nil, 0)
	end
	if self.otherDragSource then
		SetDrawColor(0, 1, 0, 0.25)
		DrawImage(nil, x, y, width, height)
	end

	-- draw dropdown bar
	if enabled then
		if (mOver or self.dropped) and mOverComp ~= "DROP" and not noTooltip then
			SetDrawLayer(nil, 100)
			self:DrawTooltip(
				x, y - (self.dropped and self.dropUp and dropExtra or 0), 
				width, height + (self.dropped and dropExtra or 0), 
				viewPort,
				mOver and "BODY" or "OUT", self.selIndex, self.list[self.selIndex])
			SetDrawLayer(nil, 0)
		end
		SetDrawColor(1, 1, 1)
	else
		SetDrawColor(0.66, 0.66, 0.66)
	end
	-- draw selected label or search term
	local selLabel
	if self:IsSearchActive() then
		selLabel = "Search: " .. self:GetSearchTermPretty()
	else
		selLabel = self.list[self.selIndex]
		if type(selLabel) == "table" then
			selLabel = selLabel.label
		end
	end
	-- For idol-style cells the "+" marker already conveys empty state; suppress
	-- the "None" label so its clipped left-edge pixels don't show as stray bars.
	if self.emptyPlusMarker and self.selIndex == 1 then
		selLabel = nil
	end
	local drawWidth = width - height/2 - arrowH  -- expands when arrowH < height/2 (e.g. idol grid cells)
	-- Optional leading 16x16 icon strip (e.g. ItemSlotControl uses this to show
	-- type / primordial / corrupted markers next to the equipped item name).
	local preIcons = self.preLabelIcons and self.preLabelIcons() or nil
	local iconStripW = 0
	if preIcons and #preIcons > 0 then
		SetDrawColor(1, 1, 1)
		for i, h in ipairs(preIcons) do
			DrawImage(h, x + 2 + (i - 1) * 18, y + (height - 16) / 2, 16, 16)
		end
		iconStripW = #preIcons * 18
	end
	local fontSize = 16
	if height >= 32 and selLabel and DrawStringWidth(fontSize, "VAR", selLabel) > drawWidth then
		-- Tall dropdown: word-wrap into 2 lines with fixed font size 16, top-aligned
		-- Find last space before pixel overflow
		local cutoff = DrawStringCursorIndex(fontSize, "VAR", selLabel, drawWidth, 0)
		local wrapAt = cutoff
		-- Walk back to find a space boundary
		for i = cutoff, 1, -1 do
			if selLabel:sub(i, i) == " " then
				wrapAt = i - 1
				break
			end
		end
		if wrapAt <= 0 then wrapAt = cutoff end  -- no space found, hard cut
		local line1 = selLabel:sub(1, wrapAt)
		local line2 = selLabel:sub(wrapAt + 2)  -- skip the space
		SetViewport(x + 2 + iconStripW, y + 2, drawWidth - iconStripW, height - 2)
		DrawString(0, 0, "LEFT", fontSize, "VAR", line1)
		DrawString(0, fontSize + 2, "LEFT", fontSize, "VAR", line2 or "")
	else
		-- Normal single-line: always use font size 16 regardless of control height
		SetViewport(x + 2 + iconStripW, y + 2, drawWidth - iconStripW, height - 2)
		if not selLabel and self.placeholder then
			SetDrawColor(0.5, 0.5, 0.5)
			DrawString(0, (height - 4 - fontSize) / 2, "LEFT", fontSize, "VAR", self.placeholder)
			SetDrawColor(1, 1, 1)
		else
			DrawString(0, (height - 4 - fontSize) / 2, "LEFT", fontSize, "VAR", selLabel or "")
		end
	end
	SetViewport()

	-- draw dropped down part with items
	if self.dropped then
		SetDrawLayer(nil, 5)
		self:DrawControls(viewPort)
		width = self.droppedWidth
		local itemFontSize = 16
		local itemLineH = itemFontSize + 4

		-- draw tooltip for hovered item
		local cursorX, cursorY = GetCursorPos()
		self.hoverSelDrop = mOver and not scrollBar:IsMouseOver() and math.floor((cursorY - dropY + scrollBar.offset) / itemLineH) + 1
		self.hoverSel = self:DropIndexToListIndex(self.hoverSelDrop)
		if self.hoverSel and not self.list[self.hoverSel] then
			self.hoverSel = nil
		end
		if self.hoverSel and not noTooltip then
			SetDrawLayer(nil, 100)
			self:DrawTooltip(
				x, dropY + 2 + (self.hoverSelDrop - 1) * itemLineH - scrollBar.offset,
				width, itemLineH,
				viewPort,
				"HOVER", self.hoverSel, self.list[self.hoverSel])
			SetDrawLayer(nil, 5)
		end

		-- draw dropdown items
		SetViewport(x + 2, dropY + 2, scrollBar.enabled and width - 22 or width - 4, self.dropHeight)
		local dropIndex = 0
		for index, listVal in ipairs(self.list) do
			local searchInfo = self.searchInfos[index]
			if self:IsListItemDropped(index) then
				dropIndex = dropIndex + 1
				local y = (dropIndex - 1) * itemLineH - scrollBar.offset
				local isHeader = type(listVal) == "table" and listVal.isHeader
				if isHeader then
					-- Distinct tinted band for group headers.
					SetDrawColor(0.2, 0.2, 0.28)
					DrawImage(nil, 0, y, width - 4, itemLineH)
					if index == self.hoverSel then
						SetDrawColor(0.33, 0.33, 0.40)
						DrawImage(nil, 0, y, width - 4, itemLineH)
					end
					SetDrawColor(1, 1, 1)
					local marker = listVal.collapsed and "[+] " or "[-] "
					local label = marker .. (listVal.label or "")
					DrawString(0, y, "LEFT", itemFontSize, "VAR", label)
				else
					-- highlight background if hovered
					if index == self.hoverSel then
						SetDrawColor(0.33, 0.33, 0.33)
						DrawImage(nil, 0, y, width - 4, itemLineH)
					end
					-- highlight font color if hovered or selected
					if index == self.hoverSel or index == self.selIndex then
						SetDrawColor(1, 1, 1)
					else
						SetDrawColor(0.66, 0.66, 0.66)
					end
					-- draw actual item label with search match highlight if available
					local label = type(listVal) == "table" and listVal.label or listVal
					DrawString(0, y, "LEFT", itemFontSize, "VAR", label)
					self:DrawSearchHighlights(label, searchInfo, 0, y, width - 4, itemFontSize)
				end
			end
		end
		SetDrawColor(1, 1, 1)
		if self:IsSearchActive() and self:GetMatchCount() == 0 then
			DrawString(0, 0 , "LEFT", lineHeight, "VAR", "<No matches>")
		end
		SetViewport()
		SetDrawLayer(nil, 0)
	end
end

function DropDownClass:OnChar(key)
	if not self:IsShown() or not self:IsEnabled() or not self.dropped then
		return
	end
	return self:OnSearchChar(key)
end

function DropDownClass:OnKeyDown(key)
	if not self:IsShown() or not self:IsEnabled() then
		return
	end
	if self.dropped then
		if self:OnSearchKeyDown(key) then
			return self
		end
	end
	local mOverControl = self:GetMouseOverControl()
	if mOverControl and mOverControl.OnKeyDown then
		self.selControl = mOverControl
		return mOverControl:OnKeyDown(key) and self
	else
		self.selControl = nil
	end
	if key == "LEFTBUTTON" or key == "RIGHTBUTTON" then
		local mOver, mOverComp = self:IsMouseOver()
		if not mOver or (self.dropped and mOverComp == "BODY") then
			self.dropped = false
			return self
		end
		if not self.dropped then
			self.dropped = true
			self:ScrollSelIntoView()
		end
	elseif key == "ESCAPE" then
		self.dropped = false
	end
	return self.dropped and self
end

function DropDownClass:OnKeyUp(key)
	if not self:IsShown() or not self:IsEnabled() then
		return
	end
	if self.selControl then
		local newSel = self.selControl:OnKeyUp(key)
		if newSel then
			return self
		else
			self.selControl = nil
		end
		return self
	end
	if key == "LEFTBUTTON" or key == "RIGHTBUTTON" then
		local mOver, mOverComp = self:IsMouseOver()
		if not mOver then
			self.dropped = false
		elseif mOverComp == "DROP" then
			local x, y = self:GetPos()
			local width, height = self:GetSize()
			local cursorX, cursorY = GetCursorPos()
			local dropExtra = self.dropHeight + 4
			local dropY = self.dropUp and y - dropExtra or y + height
			local dropIdx = math.floor((cursorY - dropY + self.controls.scrollBar.offset) / 20) + 1
			local listIdx = self:DropIndexToListIndex(dropIdx)
			local item = listIdx and self.list[listIdx]
			if type(item) == "table" and item.isHeader then
				-- Toggle group collapse; keep dropdown open.
				item.collapsed = not item.collapsed
				self.controls.scrollBar:SetContentDimension(20 * self:GetDropCount(), self.dropHeight)
			else
				self:SetSel(dropIdx)
				self.dropped = false
			end
		end
	elseif self.controls.scrollBar:IsScrollDownKey(key) then
		if self.dropped and self.controls.scrollBar.enabled then
			self.controls.scrollBar:Scroll(1)
		else
			self:SetSel(self:ListIndexToDropIndex(self.selIndex, 0) + 1)
		end
		return self
	elseif key == "DOWN" then
		self:SetSel(self:ListIndexToDropIndex(self.selIndex, 0) + 1)
		self:ScrollSelIntoView()
		return self
	elseif self.controls.scrollBar:IsScrollUpKey(key) then
		if self.dropped and self.controls.scrollBar.enabled then
			self.controls.scrollBar:Scroll(-1)
		else
			self:SetSel(self:ListIndexToDropIndex(self.selIndex, 0) - 1)
		end
		return self
	elseif key == "UP" then
		self:SetSel(self:ListIndexToDropIndex(self.selIndex, 0) - 1)
		self:ScrollSelIntoView()
		return self
	end
	return self.dropped and self
end

function DropDownClass:GetHoverIndex(key)
	return self.hoverSel or self.selIndex
end

function DropDownClass:SetList(textList)
	if textList then
		wipeTable(self.list)
		self.list = textList
		  --check width on new list
		self:CheckDroppedWidth(self.enableDroppedWidth)
	end
end

function DropDownClass:CheckDroppedWidth(enable)
	self.enableDroppedWidth = enable
	if self.enableDroppedWidth and self.list then
		local scrollWidth = 0
		if self.dropped and self.controls.scrollBar.enabled then
			scrollWidth = self.controls.scrollBar.width
		end
		local lineHeight = self.height - 4

		  -- do not be smaller than the created width
		local dWidth = self.width
		for _, line in ipairs(self.list) do
			if type(line) == "table" then
				line = line.label or ""
			end
			  -- +10 to stop clipping
			dWidth = m_max(dWidth, DrawStringWidth(lineHeight, "VAR", line) + 10)
		end
		  -- no greater than self.maxDroppedWidth
		self.droppedWidth = m_min(dWidth + scrollWidth, self.maxDroppedWidth)
		if self.enableChangeBoxWidth then
			local line = self.list[self.selIndex]
			if type(line) == "table" then
				line = line.label
			end
			-- add 20 to account for the 'down arrow' in the box
			local boxWidth
			boxWidth = DrawStringWidth(lineHeight, "VAR", line or "") + 20
			self.width = m_max(m_min(boxWidth, 390), 190)
		end
		
		self.controls.scrollBar.x = self.droppedWidth - self.width - 1
	else
		self.droppedWidth = self.width
		self.controls.scrollBar.x = -1
	end
end