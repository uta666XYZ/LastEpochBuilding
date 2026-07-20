-- Last Epoch Building
--
-- Class: Calc Section Control
-- Section control used in the Calcs tab
--
local t_insert = table.insert

local CalcSectionClass = newClass("CalcSectionControl", "Control", "ControlHost", function(self, calcsTab, width, id, group, colour, subSection, updateFunc)
	self.Control(nil, 0, 0, width, 0)
	self.ControlHost()
	self.calcsTab = calcsTab
	self.id = id
	self.group = group
	self.colour = colour
	self.width = width
	self.subSection = subSection
	self.flag = subSection[1].data.flag
	self.notFlag = subSection[1].data.notFlag
	self.updateFunc = updateFunc

	for i, subSec in ipairs(self.subSection) do
		subSec.id = subSec.label:gsub("%W", "")

		for _, data in ipairs(subSec.data) do
			for _, colData in ipairs(data) do
				if colData.control then
					-- Add control to the section's control list and set show/hide function
					self.controls[colData.controlName] = colData.control
					colData.control.shown = function()
						return self.enabled and not self.subSection[1].collapsed and not subSec.collapsed and data.enabled
					end
				end
			end
		end
		subSec.collapsed = subSec.defaultCollapsed
		self.controls["toggle"..i] = new("ButtonControl", {"TOPRIGHT",self,"TOPRIGHT"}, -3, -13 + (16 * i), 16, 16, function()
			return subSec.collapsed and "+" or "-"
		end, function()
			subSec.collapsed = not subSec.collapsed
			self.calcsTab.modFlag = true
		end)
		if i == 1 then
			self.controls["toggle"..i].shown = function()
				return self.enabled
			end
		else
			self.controls["toggle"..i].shown = function()
				return self.enabled and not self.subSection[1].collapsed
			end
		end
	end
	self.shown = function()
		return self.enabled
	end
end)

function CalcSectionClass:IsMouseOver()
	if not self:IsShown() then
		return
	end
	if self:GetMouseOverControl() then
		return true
	end
	local mOver = self:IsMouseInBounds()
	for _, subSec in ipairs(self.subSection) do
		if mOver and not subSec.collapsed and self.enabled then
			-- Check if mouse is over one of the cells
			local cursorX, cursorY = GetCursorPos()
			for _, data in ipairs(subSec.data) do
				if data.enabled then
					for _, colData in ipairs(data) do
						if colData.control then
						if colData.control:IsMouseOver() then
							return mOver, colData
						end
					elseif cursorX >= colData.x and cursorY >= colData.y and cursorX < colData.x + colData.width and cursorY < colData.y + colData.height then
						return mOver, colData
					end
				end
				end
			end
		end
	end
	return mOver
end

function CalcSectionClass:UpdateSize()
	self.enabled = self.calcsTab:CheckFlag(self)
	if not self.enabled then
		self.height = 22
		return
	end
	local x, y = self:GetPos()
	local width = self:GetSize()
	self.height = 2
	self.enabled = false
	local yOffset = 0
	for i, subSec in ipairs(self.subSection) do
		self.controls["toggle"..i].y = yOffset + 3
		local tempHeight = 0
		yOffset = yOffset + 22
		for _, rowData in ipairs(subSec.data) do
			rowData.enabled = self.calcsTab:CheckFlag(rowData) and (self.id == "SkillSelect" or self.calcsTab:SearchMatch(rowData))
			if rowData.enabled then
				self.enabled = true
				-- Wrap long labels that don't fit the 128px label area onto a 2nd line.
				local rowHeight = 18
				if rowData.label and DrawStringWidth(16, "VAR", rowData.label..":") > 128 then
					rowHeight = 32
				end
				rowData._rowHeight = rowHeight
				local xOffset = 134
				for colour, colData in ipairs(rowData) do
					colData.xOffset = xOffset
					colData.yOffset = yOffset
					colData.width = subSec.data.colWidth or width - 136
					colData.height = rowHeight
					xOffset = xOffset + colData.width
				end
				yOffset = yOffset + rowHeight
				self.height = self.height + rowHeight
				tempHeight = tempHeight + rowHeight
			end
			if subSec.collapsed then
				rowData.enabled = false
			end
		end
		if self.enabled and not subSec.collapsed then
			-- @leb-regression-guard: calc-section-last-row-frame-gap
			-- 22 = the subsection header; +2 = a bottom gap so the last row does
			-- not touch the section frame / next header border below it (matches
			-- the "lineY = lineY + 2" after the rows in Draw).
			-- Test: spec/System/TestCalcSectionRowLayout_spec.lua "reserves a 2px bottom gap after the last row (2 rows)"
			self.height = self.height + 22 + 2
		else
			self.height = self.height - tempHeight + 20
			yOffset = yOffset - tempHeight - 2
		end
	end
	if self.enabled and not self.subSection[1].collapsed then
		if self.updateFunc then
			self:updateFunc()
		end
	else
		self.height = 22
	end
end

function CalcSectionClass:UpdatePos()
	if not self.enabled then
		return
	end
	local x, y = self:GetPos()
	for _, subSec in ipairs(self.subSection) do
		for _, rowData in ipairs(subSec.data) do
			if rowData.enabled then
				for colour, colData in ipairs(rowData) do
					-- Update the real coordinates of this cell
					colData.x = x + colData.xOffset
					colData.y = y + colData.yOffset
				if colData.control then
					colData.control.x = colData.x + 4
					colData.control.y = colData.y + 9 - colData.control.height/2
				end
			end
			end
		end
	end
end

function CalcSectionClass:FormatVal(val, p)
	return formatNumSep(tostring(round(val, p)))
end

function CalcSectionClass:FormatStr(str, actor, colData)
	-- @leb-regression-guard: calc-section-output-key-underscore
	-- Output keys may contain underscores/digits (e.g. BurningDaggerChanceOnMeleeFire_RateLimit),
	-- so the key class must include %w and _, not just letters -- otherwise the
	-- placeholder never matches and the raw "{0:output:...}" text is shown.
	-- Test: spec/System/TestCalcSectionOutputKeyUnderscore_spec.lua "substitutes output keys that contain underscores"
	str = str:gsub("{output:([%w_%.:]+)}", function(c)
		local ns, var = c:match("^(%a+)%.(%a+)$")
		if ns then
			return actor.output[ns] and actor.output[ns][var] or ""
		else
			return actor.output[c] or ""
		end
	end)
	str = str:gsub("{(%d+):output:([%w_%.:]+)}", function(p, c)
		local ns, var = c:match("^(%a+)%.(%a+)$")
		if ns then
			return self:FormatVal(actor.output[ns] and actor.output[ns][var] or 0, tonumber(p))
		else
			return self:FormatVal(actor.output[c] or 0, tonumber(p))
		end
	end)
	str = str:gsub("{(%d+):mod:([%d,]+)}", function(p, n)
		local numList = { }
		for num in n:gmatch("%d+") do
			t_insert(numList, tonumber(num))
		end
		local modType = colData[numList[1]].modType
		local modTotal = modType == "MORE" and 1 or 0
		for _, num in ipairs(numList) do
			local sectionData = colData[num]
			local modCfg = (sectionData.cfg and actor.mainSkill[sectionData.cfg.."Cfg"]) or { }
			if sectionData.modSource then
				modCfg.source = sectionData.modSource
			end
			if sectionData.actor then
				modCfg.actor = sectionData.actor
			end
			local modVal
			local modStore = (sectionData.enemy and actor.enemy.modDB) or (sectionData.cfg and actor.mainSkill.skillModList) or actor.modDB
			if type(sectionData.modName) == "table" then
				modVal = modStore:Combine(sectionData.modType, modCfg, unpack(sectionData.modName))
			else
				modVal = modStore:Combine(sectionData.modType, modCfg, sectionData.modName)
			end
			if modType == "MORE" then
				modTotal = modTotal * modVal
			else
				modTotal = modTotal + modVal
			end
		end
		if modType == "MORE" then
			modTotal = (modTotal - 1) * 100
		end
		return self:FormatVal(modTotal, tonumber(p)) 
	end)
	return str
end

function CalcSectionClass:Draw(viewPort, noTooltip)
	local x, y = self:GetPos()
	local width, height = self:GetSize()
	local cursorX, cursorY = GetCursorPos()
	local actor = self.calcsTab.input.showMinion and self.calcsTab.calcsEnv.minion or self.calcsTab.calcsEnv.player
	-- Draw border and background
	SetDrawLayer(nil, -10)
	SetDrawColor(self.colour)
	DrawImage(nil, x, y, width, height)
	SetDrawColor(0.10, 0.10, 0.10)
	DrawImage(nil, x + 2, y + 2, width - 4, height - 4)
	
	local primary = true
	local lineY = y
	for _, subSec in ipairs(self.subSection) do
		-- Draw line above label
		SetDrawColor(self.colour)
		DrawImage(nil, x + 2, lineY, width - 4, 2)
		SetDrawColor(0.10, 0.10, 0.10)
		-- Draw label
		if not self.enabled then
			DrawString(x + 3, lineY + 3, "LEFT", 16, "VAR BOLD", "^8"..subSec.label)
		else
			DrawString(x + 3, lineY + 3, "LEFT", 16, "VAR BOLD", "^7"..subSec.label..":")
			if subSec.data.extra then
				local x = x + 3 + DrawStringWidth(16, "VAR BOLD", subSec.label) + 10
				DrawString(x, lineY + 3, "LEFT", 16, "VAR", self:FormatStr(subSec.data.extra, actor))
			end
		end
		-- Draw line below label
		SetDrawColor(self.colour)
		DrawImage(nil, x + 2, lineY + 20, width - 4, 2)
		-- Draw controls
		SetDrawLayer(nil, 0)
		self:DrawControls(viewPort, noTooltip and self.calcsTab.selControl)
		if subSec.collapsed or not self.enabled then
			if primary then
				return
			else
				lineY = lineY + 20
				primary = false
			end
		else
			lineY = lineY + 22
			primary = false
			for _, rowData in ipairs(subSec.data) do
				if rowData.enabled then
					local textColor = "^7"
					if rowData.color then
						textColor = rowData.color
					end
					if rowData.label then
						local rowHeight = rowData._rowHeight or 18
						-- Draw row label with background
						SetDrawColor(rowData.bgCol or "^0")
						DrawImage(nil, x + 2, lineY, 130, rowHeight)
						-- Clip the label text to its 130px column so an over-long label
						-- can never spill onto the section border (left) or the line
						-- above (top). Coords below are viewport-relative; 130 = the
						-- column's right edge (was x+132 in absolute coords).
						SetViewport(x + 2, lineY, 130, rowHeight)
						if rowHeight > 18 then
							-- Wrap onto two lines, splitting at last word that fits.
							local words = { }
							for w in rowData.label:gmatch("%S+") do t_insert(words, w) end
							local line1, line2 = "", ""
							-- Fill line 1 with as many words as fit the 128px label
							-- column, measured at the SAME 14px size the text is drawn
							-- at (measuring at 16px underfilled line 1 and pushed the
							-- overflow onto line 2, which then stuck out past the border).
							for i, w in ipairs(words) do
								local trial = (line1 == "") and w or (line1 .. " " .. w)
								if DrawStringWidth(14, "VAR", trial) <= 128 and line2 == "" then
									line1 = trial
								else
									line2 = (line2 == "") and w or (line2 .. " " .. w)
								end
							end
							if line2 == "" then line2 = line1; line1 = "" end
							-- +2 keeps the top line clear of the section/header border
							-- line above it; the 2nd line carries the ":" so the value
							-- (drawn below) aligns to it.
							DrawString(130, 2,  "RIGHT_X", 14, "VAR", textColor..line1)
							DrawString(130, 17, "RIGHT_X", 14, "VAR", textColor..line2.."^7:")
						else
							DrawString(130, 2, "RIGHT_X", 16, "VAR", textColor..rowData.label.."^7:")
						end
						SetViewport()
					end
					for colour, colData in ipairs(rowData) do
						-- Draw column separator at the left end of the cell
						SetDrawColor(self.colour)
						DrawImage(nil, colData.x, lineY, 2, colData.height)
						if colData.format and self.calcsTab:CheckFlag(colData) then
							if cursorY >= viewPort.y and cursorY < viewPort.y + viewPort.height and cursorX >= colData.x and cursorY >= colData.y and cursorX < colData.x + colData.width and cursorY < colData.y + colData.height then
						self.calcsTab:SetDisplayStat(colData)
					end
					if self.calcsTab.displayData == colData then
						-- This is the display stat, draw a green border around this cell
						SetDrawColor(0.25, 1, 0.25)
						DrawImage(nil, colData.x + 2, colData.y, colData.width - 2, colData.height)
						SetDrawColor(rowData.bgCol or "^0")
						DrawImage(nil, colData.x + 3, colData.y + 1, colData.width - 4, colData.height - 2)
					else
						SetDrawColor(rowData.bgCol or "^0")
						DrawImage(nil, colData.x + 2, colData.y, colData.width - 2, colData.height)
					end
					local textSize = rowData.textSize or 14
					-- For a wrapped (2-line) label the ":" sits on the 2nd line
					-- (drawn at +17), so align the value to that line instead of
					-- the cell centre; single-line rows stay vertically centred.
					local valueY = (colData.height > 18) and (17 + (14 - textSize) / 2) or (colData.height / 2 - textSize / 2)
					SetViewport(colData.x + 3, colData.y, colData.width - 4, colData.height)
					DrawString(1, valueY, "LEFT", textSize, "VAR", "^7"..self:FormatStr(colData.format, actor, colData))
					SetViewport()
				end
			end
			lineY = lineY + (rowData._rowHeight or 18)
				end
			end
			-- @leb-regression-guard: calc-section-last-row-frame-gap
			-- 2px gap after this subsection's rows so the last row clears the
			-- section frame (or the next subsection's header border) below it.
			-- Must match the "+ 22 + 2" in UpdateSize or height and draw diverge.
			lineY = lineY + 2
		end
	end
end

function CalcSectionClass:OnKeyDown(key, doubleClick)
	if not self:IsShown() or not self:IsEnabled() then
		return
	end
	local mOverControl = self:GetMouseOverControl()
	if mOverControl and mOverControl.OnKeyDown then
		return mOverControl:OnKeyDown(key)
	end
	local mOver, mOverComp = self:IsMouseOver()
	if key:match("BUTTON") then
		if not mOver then
			return
		end
		if mOverComp then
			-- Pin the stat breakdown
			self.calcsTab:SetDisplayStat(mOverComp, true)
			return self.calcsTab.controls.breakdown
		end
	end
	return
end

function CalcSectionClass:OnKeyUp(key)
	if not self:IsShown() or not self:IsEnabled() then
		return
	end
	local mOverControl = self:GetMouseOverControl()
	if mOverControl and mOverControl.OnKeyUp then
		return mOverControl:OnKeyUp(key)
	end
	return
end