-- Last Epoch Building
--
-- Module: Skills Tab
-- Skills tab for the current build.
--
local pairs = pairs
local ipairs = ipairs
local t_insert = table.insert
local t_remove = table.remove
local m_min = math.min
local m_max = math.max

local sortGemTypeList = {
	{ label = "Full DPS", type = "FullDPS" },
	{ label = "Combined DPS", type = "CombinedDPS" },
	{ label = "Hit DPS", type = "TotalDPS" },
	{ label = "Average Hit", type = "AverageDamage" },
	{ label = "DoT DPS", type = "TotalDot" },
	{ label = "Bleed DPS", type = "BleedDPS" },
	{ label = "Ignite DPS", type = "IgniteDPS" },
	{ label = "Poison DPS", type = "TotalPoisonDPS" },
	{ label = "Effective Hit Pool", type = "TotalEHP" },
}

local SkillsTabClass = newClass("SkillsTab", "UndoHandler", "ControlHost", "Control", function(self, build)
	self.UndoHandler()
	self.ControlHost()
	self.Control()

	self.build = build

	self.socketGroupList = { }

	self.sortGemsByDPS = true
	self.sortGemsByDPSField = "CombinedDPS"
	self.showSupportGemTypes = "ALL"
	self.showAltQualityGems = false
	self.defaultGemLevel = "normalMaximum"
	self.defaultGemQuality = main.defaultGemQuality

	-- Create a single Skill Tree Viewer for all skill trees (combined view)
	self.skillTreeViewer = new("PassiveTreeView")
	self.skillTreeViewer.filterMode = "skill"
	self.skillTreeViewer.selectedSkillIndex = nil  -- nil = show all trees in one viewport
	self.selectedSkillTreeIndex = nil

	-- Set selector
	self.controls.setSelect = new("DropDownControl", { "TOPLEFT", self, "TOPLEFT" }, 76, 8, 210, 20, nil, function(index, value)
		self:SetActiveSkillSet(self.skillSetOrderList[index])
		self:AddUndoState()
	end)
	self.controls.setSelect.enableDroppedWidth = true
	self.controls.setSelect.enabled = function()
		return #self.skillSetOrderList > 1
	end
	self.controls.setLabel = new("LabelControl", { "RIGHT", self.controls.setSelect, "LEFT" }, -2, 0, 0, 16, "^7Skill set:")
	self.controls.setManage = new("ButtonControl", { "LEFT", self.controls.setSelect, "RIGHT" }, 4, 0, 90, 20, "Manage...", function()
		self:OpenSkillSetManagePopup()
	end)

	-- Socket group list (fixed height for 5 skills)
	self.controls.skillsSection = new("SectionControl", { "TOPLEFT", self, "TOPLEFT" }, 20, 54, 720, 150, "Skills")
	self.controls.skillsSection.height = function()
		return 40 + 24 * 5  -- Fixed: 5 skills only
	end

	-- Socket group details
	if main.portraitMode then
		self.anchorGroupDetail = new("Control", { "TOPLEFT", self.controls.optionSection, "BOTTOMLEFT" }, 0, 20, 0, 0)
	else
		self.anchorGroupDetail = new("Control", { "TOPLEFT", self.controls.skillsSection, "TOPRIGHT" }, 20, 0, 0, 0)
	end
	self.anchorGroupDetail.shown = function()
		return self.displayGroup ~= nil
	end
	self.controls.groupLabel = new("EditControl", { "TOPLEFT", self.anchorGroupDetail, "TOPLEFT" }, 0, 0, 380, 20, nil, "Label", "%c", 50, function(buf)
		self.displayGroup.label = buf
		self:ProcessSocketGroup(self.displayGroup)
		self:AddUndoState()
		self.build.buildFlag = true
	end)
	self.controls.groupSlotLabel = new("LabelControl", { "TOPLEFT", self.anchorGroupDetail, "TOPLEFT" }, 0, 30, 0, 16, "^7Socketed in:")
	self.controls.groupSlot = new("DropDownControl", { "TOPLEFT", self.anchorGroupDetail, "TOPLEFT" }, 85, 28, 130, 20, groupSlotDropList, function(index, value)
		self.displayGroup.slot = value.slotName
		self:AddUndoState()
		self.build.buildFlag = true
	end)
	self.controls.groupSlot.tooltipFunc = function(tooltip, mode, index, value)
		tooltip:Clear()
		if mode == "OUT" or index == 1 then
			tooltip:AddLine(16, "Select the item in which this skill is socketed.")
			tooltip:AddLine(16, "This will allow the skill to benefit from modifiers on the item that affect socketed gems.")
		else
			local slot = self.build.itemsTab.slots[value.slotName]
			local ttItem = self.build.itemsTab.items[slot.selItemId]
			if ttItem then
				self.build.itemsTab:AddItemTooltip(tooltip, ttItem, slot)
			else
				tooltip:AddLine(16, "No item is equipped in this slot.")
			end
		end
	end
	self.controls.groupSlot.enabled = function()
		return self.displayGroup.source == nil
	end
	self.controls.sourceNote = new("LabelControl", { "TOPLEFT", self.controls.groupSlotLabel, "TOPLEFT" }, 0, 30, 0, 16)
	self.controls.sourceNote.shown = function()
		return self.displayGroup.source ~= nil
	end
	self.controls.sourceNote.label = function()
		local label
		if self.displayGroup.explodeSources then
			label = [[^7This is a special group created for the enemy explosion effect,
which comes from the following sources:]]
			for _, source in ipairs(self.displayGroup.explodeSources) do
				label = label .. "\n\t" .. colorCodes[source.rarity or "NORMAL"] .. (source.name or source.dn or "???")
			end
			label = label .. "^7\nYou cannot delete this group, but it will disappear if you lose the above sources."
		else
			local activeGem = self.displayGroup.gemList[1]
			local sourceName
			if self.displayGroup.sourceItem then
				sourceName = "'" .. colorCodes[self.displayGroup.sourceItem.rarity] .. self.displayGroup.sourceItem.name
			elseif self.displayGroup.sourceNode then
				sourceName = "'" .. colorCodes["NORMAL"] .. self.displayGroup.sourceNode.name
			else
				sourceName = "'" .. colorCodes["NORMAL"] .. "?"
			end
			sourceName = sourceName .. "^7'"
			label = [[^7This is a special group created for the ']] .. activeGem.color .. (activeGem.grantedEffect and activeGem.grantedEffect.name or activeGem.nameSpec) .. [[^7' skill,
which is being provided by ]] .. sourceName .. [[.
You cannot delete this group, but it will disappear if you ]] .. (self.displayGroup.sourceNode and [[un-allocate the node.]] or [[un-equip the item.]])
			if not self.displayGroup.noSupports then
				label = label .. "\n\n" .. [[You cannot add support gems to this group, but support gems in
any other group socketed into ]] .. sourceName .. [[
will automatically apply to the skill.]]
			end
		end
		return label
	end

	-- Scroll bar (horizontal - for existing content)
	self.controls.scrollBarH = new("ScrollBarControl", nil, 0, 0, 0, 18, 100, "HORIZONTAL", true)
	
	-- Vertical scroll bar for skill trees
	self.controls.scrollBarV = new("ScrollBarControl", nil, 0, 0, 18, 0, 100, "VERTICAL", true)

	-- Initialise skill sets
	self.skillSets = { }
	self.skillSetOrderList = { 1 }
	self:NewSkillSet(1)
	self:SetActiveSkillSet(1)
end)

function SkillsTabClass:InitSkillControl(i)
    if i <= 5 then
		-- "Skill #:" label
		self.controls['skillLabel-' .. i] = new("LabelControl", { "TOPLEFT", self.controls.skillsSection, "TOPLEFT" }, 20, 24 * i, 0, 16, "^7Skill " .. i .. ":")
		-- Skill name dropdown
		self.controls['skill-' .. i] = new("DropDownControl", { "LEFT", self.controls['skillLabel-' .. i], "RIGHT" }, 4, 0, 140, 20, nil, function(index, value)
			self:SelSkill(i, value.name)
			self.build.spec:BuildAllDependsAndPaths()
		end)
	else
		self.controls['skill-' .. i] = new("LabelControl", { "TOPLEFT", self.controls.skillsSection, "TOPLEFT" }, 20, 24 * i, 0, 16, "^7Skill " .. i .. ":")
		self.controls['skill-' .. i].shown = function()
				return self.socketGroupList[i] ~= nil
		end
		self.controls['skill-' .. i].label = function()
			return (colorCodes.SOURCE .. self.socketGroupList[i].displayLabel) or ""
		end
	end
	-- Level label (shown after skill dropdown, before Enabled)
	self.controls['skillLevel-'..i] = new("LabelControl", { "LEFT", self.controls['skill-' .. i], "RIGHT" }, 6, 0, 38, 16)
	self.controls['skillLevel-'..i].shown = function()
		return self.socketGroupList[i] ~= nil
	end
	self.controls['skillLevel-'..i].label = function()
		local lvl = self:GetSkillLevel(i)
		return "^7Lv " .. lvl
	end
	-- Points label (always shown with fixed width to keep Enabled checkbox anchored correctly)
	self.controls['skillPts-'..i] = new("LabelControl", { "LEFT", self.controls['skillLevel-'..i], "RIGHT" }, 4, 0, 80, 16)
	-- Note: always shown (even if empty) so groupEnabled anchor position is stable
	self.controls['skillPts-'..i].shown = function()
		return self.socketGroupList[i] ~= nil
	end
	self.controls['skillPts-'..i].label = function()
		local sg = self.socketGroupList[i]
		if not sg or not sg.grantedEffect or not sg.grantedEffect.treeId then
			return ""  -- Empty but width still reserved, keeping Enabled in place
		end
		local used = self:GetUsedSkillPoints(i)
		local maxPts = self:GetMaxSkillPoints(i)
		local rem = maxPts - used
		if rem > 0 then
			return "^x4DD9FF" .. rem .. " pts left"
		elseif rem == 0 then
			return "^70 pts left"
		else
			return "^xFF6666" .. math.abs(rem) .. " pts over"
		end
	end
	-- Enabled checkbox
	-- NOTE: CheckBoxControl draws its label to the LEFT of the box (RIGHT_X aligned at x-5).
	-- So we must add the label width to the x-offset to prevent overlap with skillPts.
	-- labelWidth = DrawStringWidth(size-4=16, "VAR", "Enabled:") + 5 ≈ 70px
	local enabledLabelW = 70
	self.controls['groupEnabled-'..i] = new("CheckBoxControl", { "LEFT", self.controls['skillPts-'..i], "RIGHT" }, enabledLabelW + 6, 0, 20, "Enabled:", function(state)
		self.socketGroupList[i].enabled = state
		self:AddUndoState()
		self.build.buildFlag = true
	end)
	self.controls['groupEnabled-'..i].shown = function()
			return self.socketGroupList[i] ~= nil
	end
	self.controls['includeInFullDPS-'..i] = new("CheckBoxControl", { "LEFT", self.controls['groupEnabled-'..i], "RIGHT" }, 145, 0, 20, "Include in Full DPS:", function(state)
		self.socketGroupList[i].includeInFullDPS = state
		self:AddUndoState()
		self.build.buildFlag = true
	end)
	self.controls['includeInFullDPS-'..i].shown = function()
			return self.socketGroupList[i] ~= nil
	end
	if i > 5 then
		self.controls['includeInFullDPS-'..i].enabled = false
	end
end

-- parse real gem name and quality by omitting the first word if alt qual is set
function SkillsTabClass:GetBaseNameAndQuality(gemTypeLine, quality)
	gemTypeLine = sanitiseText(gemTypeLine)
	-- if quality is default or nil check the gem type line if we have alt qual by comparing to the existing list
	if gemTypeLine and (quality == nil or quality == "" or quality == "Default") then
		local firstword, otherwords = gemTypeLine:match("(%w+)%s(.+)")
		if firstword and otherwords then
			for _, entry in ipairs(alternateGemQualityList) do
				if firstword == entry.label then
					-- return the gem name minus <altqual> without a leading space and the new resolved type
					if entry.type == nil or entry.type == "" then
						entry.type = "Default"
					end
					return otherwords, entry.type
				end
			end
		end
	end
	-- no alt qual found, return gemTypeLine as is and either existing quality or Default if none is set
	return gemTypeLine, quality or "Default"
end

function SkillsTabClass:LoadSkill(node, skillSetId)
	if node.elem ~= "Skill" then
		return
	end

	local socketGroup = { }
	socketGroup.enabled = node.attrib.active == "true" or node.attrib.enabled == "true"
	socketGroup.includeInFullDPS = node.attrib.includeInFullDPS and node.attrib.includeInFullDPS == "true"
	socketGroup.groupCount = tonumber(node.attrib.groupCount)
	socketGroup.label = node.attrib.label
	socketGroup.slot = node.attrib.slot
	socketGroup.source = node.attrib.source
	socketGroup.mainActiveSkill = tonumber(node.attrib.mainActiveSkill) or 1
	socketGroup.mainActiveSkillCalcs = tonumber(node.attrib.mainActiveSkillCalcs) or 1
	socketGroup.gemList = { }
	local skillId = node.attrib.skillId
	local grantedEffect = self.build.data.skills[skillId]
	socketGroup.skillId = skillId
	socketGroup.grantedEffect = grantedEffect
	self:ProcessSocketGroup(socketGroup)
	if node.attrib.index then
	    self.skillSets[skillSetId].socketGroupList[tonumber(node.attrib.index)] = socketGroup
	else
		t_insert(self.skillSets[skillSetId].socketGroupList, socketGroup)
	end
end

function SkillsTabClass:Load(xml, fileName)
	self.activeSkillSetId = 0
	self.skillSets = { }
	self.skillSetOrderList = { }
	for _, node in ipairs(xml) do
		if node.elem == "Skill" then
			-- Old format, initialize skill sets if needed
			if not self.skillSetOrderList[1] then
				self.skillSetOrderList[1] = 1
				self:NewSkillSet(1)
			end
			self:LoadSkill(node, 1)
		end

		if node.elem == "SkillSet" then
			local skillSet = self:NewSkillSet(tonumber(node.attrib.id))
			skillSet.title = node.attrib.title
			t_insert(self.skillSetOrderList, skillSet.id)
			for _, subNode in ipairs(node) do
				self:LoadSkill(subNode, skillSet.id)
			end
		end
	end
	self:SetActiveSkillSet(tonumber(xml.attrib.activeSkillSet) or 1)
	self:ResetUndo()
end

function SkillsTabClass:Save(xml)
	xml.attrib = {
		activeSkillSet = tostring(self.activeSkillSetId),
		defaultGemLevel = self.defaultGemLevel,
		defaultGemQuality = tostring(self.defaultGemQuality),
		sortGemsByDPS = tostring(self.sortGemsByDPS),
		showSupportGemTypes = self.showSupportGemTypes,
		sortGemsByDPSField = self.sortGemsByDPSField,
		showAltQualityGems = tostring(self.showAltQualityGems)
	}
	for _, skillSetId in ipairs(self.skillSetOrderList) do
		local skillSet = self.skillSets[skillSetId]
		local child = { elem = "SkillSet", attrib = { id = tostring(skillSetId), title = skillSet.title } }
		t_insert(xml, child)

		for index, socketGroup in pairsSortByKey(skillSet.socketGroupList) do
			local node = { elem = "Skill", attrib = {
				index = tostring(index),
				enabled = tostring(socketGroup.enabled),
				includeInFullDPS = tostring(socketGroup.includeInFullDPS),
				groupCount = socketGroup.groupCount ~= nil and tostring(socketGroup.groupCount),
				label = socketGroup.label,
				slot = socketGroup.slot,
				source = socketGroup.source,
				mainActiveSkill = tostring(socketGroup.mainActiveSkill),
				mainActiveSkillCalcs = tostring(socketGroup.mainActiveSkillCalcs),
				skillId = socketGroup.skillId,
			} }
			t_insert(child, node)
		end
	end
end

function SkillsTabClass:Draw(viewPort, inputEvents)
	self.x = viewPort.x
	self.y = viewPort.y
	self.width = viewPort.width
	self.height = viewPort.height
	
	-- Horizontal scroll bar
	self.controls.scrollBarH.width = viewPort.width
	self.controls.scrollBarH.x = viewPort.x
	self.controls.scrollBarH.y = viewPort.y + viewPort.height - 18

	-- Vertical scroll bar (right side)
	self.controls.scrollBarV.x = viewPort.x + viewPort.width - 18
	self.controls.scrollBarV.y = viewPort.y
	self.controls.scrollBarV.height = viewPort.height - 18

	-- Calculate content height for scrolling
	local skillsSectionHeight = self.controls.skillsSection.height()
	
	-- Content height: skills section + unified tree area (fills viewport)
	local contentHeight = 54 + skillsSectionHeight + 20
	
	-- Set scroll dimensions
	self.controls.scrollBarV:SetContentDimension(contentHeight, viewPort.height)
	
	-- Apply scroll offset to self.y
	self.x = self.x - self.controls.scrollBarH.offset
	self.y = self.y - self.controls.scrollBarV.offset

	for _, event in ipairs(inputEvents) do
		if event.type == "KeyDown" then
			if event.key == "z" and IsKeyDown("CTRL") then
				self:Undo()
				self.build.buildFlag = true
			elseif event.key == "y" and IsKeyDown("CTRL") then
				self:Redo()
				self.build.buildFlag = true
			end
		end
	end
	self:ProcessControlsInput(inputEvents, viewPort)
	
	-- Handle scroll events (keyboard and mouse wheel)
	-- If cursor is over the skill tree area, let PassiveTreeView handle wheel for zoom
	local cursorX, cursorY = GetCursorPos()
	local treeSectionStartY_check = 54 + self.controls.skillsSection.height()
	local treeAreaTop = viewPort.y + treeSectionStartY_check + 20
	local mouseOverTree = cursorX >= viewPort.x and cursorX < viewPort.x + viewPort.width
		and cursorY >= treeAreaTop and cursorY < viewPort.y + viewPort.height

	for _, event in ipairs(inputEvents) do
		if event.type == "KeyUp" then
			if not mouseOverTree then
				if self.controls.scrollBarV:IsScrollDownKey(event.key) then
					self.controls.scrollBarV:Scroll(1)
				elseif self.controls.scrollBarV:IsScrollUpKey(event.key) then
					self.controls.scrollBarV:Scroll(-1)
				end
			end
		elseif event.type == "KeyDown" then
			if not mouseOverTree then
				if event.key == "WHEELDOWN" then
					self.controls.scrollBarV:Scroll(3)
				elseif event.key == "WHEELUP" then
					self.controls.scrollBarV:Scroll(-3)
				end
			end
		end
	end

	main:DrawBackground(viewPort)

	local newSetList = { }
	for index, skillSetId in ipairs(self.skillSetOrderList) do
		local skillSet = self.skillSets[skillSetId]
		t_insert(newSetList, skillSet.title or "Default")
		if skillSetId == self.activeSkillSetId then
			self.controls.setSelect.selIndex = index
		end
	end
	self.controls.setSelect:SetList(newSetList)

	if main.portraitMode then
		self.anchorGroupDetail:SetAnchor("TOPLEFT",self.controls.optionSection,"BOTTOMLEFT", 0, 20)
	else
		self.anchorGroupDetail:SetAnchor("TOPLEFT",self.controls.skillsSection,"TOPRIGHT", 20, 0)
	end

	local skillList = { { label = "None"}}
	for k,v in ipairs(self.build.spec.curClass.skills) do
		table.insert(skillList, v)
	end
	-- Only display 5 skills (hide ailments like Shred Armor, Blind, Chill, etc.)
	local nbDisplayedSkills = 5
	for i = 1, nbDisplayedSkills do
		local socketGroup = self.socketGroupList[i]
		if not self.controls['skill-' .. i] then
			self:InitSkillControl(i)
		end
		self.controls['skill-' .. i].list = skillList
		self.controls["skill-"..i]:SelByValue(socketGroup and socketGroup.skillId, "name")
		if socketGroup then
			self.controls['groupEnabled-'..i].state = socketGroup.enabled
			self.controls['includeInFullDPS-'..i].state = socketGroup.includeInFullDPS and socketGroup.enabled
		end
	end

	-- ===== SKILL TREES SECTION - Single unified viewport =====
	local treeSectionStartY = 54 + skillsSectionHeight + 20
	local PADDING = 10
	local TREE_WIDTH = viewPort.width - PADDING * 2 - 20

	-- Count how many skills have trees
	local numSkillTrees = 0
	for i = 1, 5 do
		local sg = self.socketGroupList[i]
		if sg and ((sg.grantedEffect and sg.grantedEffect.treeId) or sg.skillId) then
			numSkillTrees = numSkillTrees + 1
		end
	end

	if numSkillTrees > 0 then
		-- Draw a single unified tree viewport that fills remaining space
		local treeAreaY = self.y + treeSectionStartY
		local treeAreaHeight = math.max(400, viewPort.height - treeSectionStartY - 10)
		local drawX = viewPort.x + PADDING

		-- Background
		SetDrawColor(0.04, 0.04, 0.05)
		DrawImage(nil, drawX, treeAreaY, TREE_WIDTH, treeAreaHeight)
		-- Border
		SetDrawColor(0.20, 0.20, 0.25)
		DrawImage(nil, drawX, treeAreaY, TREE_WIDTH, 1)
		DrawImage(nil, drawX, treeAreaY + treeAreaHeight - 1, TREE_WIDTH, 1)
		DrawImage(nil, drawX, treeAreaY, 1, treeAreaHeight)
		DrawImage(nil, drawX + TREE_WIDTH - 1, treeAreaY, 1, treeAreaHeight)

		-- Unified tree viewport: show all skill trees stacked
		local treeVP = {
			x = drawX + 2,
			y = treeAreaY + 2,
			width = TREE_WIDTH - 4,
			height = treeAreaHeight - 4,
		}

		-- Use "all trees" mode: selectedSkillIndex = nil
		self.skillTreeViewer.selectedSkillIndex = nil
		self.skillTreeViewer:Draw(self.build, treeVP, inputEvents)
	end

	self:DrawControls(viewPort)
end

function SkillsTabClass:getGemAltQualityList(gemData)
	local altQualList = { }

	for indx, entry in ipairs(alternateGemQualityList) do
		if gemData and (gemData.grantedEffect.qualityStats and gemData.grantedEffect.qualityStats[entry.type] or (gemData.secondaryGrantedEffect and gemData.secondaryGrantedEffect.qualityStats and gemData.secondaryGrantedEffect.qualityStats[entry.type])) then
			t_insert(altQualList, entry)
		end
	end
	return #altQualList > 0 and altQualList or {{ label = "Default", type = "Default" }}
end

-- Find the skill gem matching the given specification
function SkillsTabClass:FindSkillGem(nameSpec)
	-- Search for gem name using increasingly broad search patterns
	local patternList = {
		"^ "..nameSpec:gsub("%a", function(a) return "["..a:upper()..a:lower().."]" end).."$", -- Exact match (case-insensitive)
		"^"..nameSpec:gsub("%a", " %0%%l+").."$", -- Simple abbreviation ("CtF" -> "Cold to Fire")
		"^ "..nameSpec:gsub(" ",""):gsub("%l", "%%l*%0").."%l+$", -- Abbreviated words ("CldFr" -> "Cold to Fire")
		"^"..nameSpec:gsub(" ",""):gsub("%a", ".*%0"), -- Global abbreviation ("CtoF" -> "Cold to Fire")
		"^"..nameSpec:gsub(" ",""):gsub("%a", function(a) return ".*".."["..a:upper()..a:lower().."]" end), -- Case insensitive global abbreviation ("ctof" -> "Cold to Fire")
	}
	for i, pattern in ipairs(patternList) do
		local foundGemData
		for gemId, gemData in pairs(self.build.data.gems) do
			if (" "..gemData.name):match(pattern) then
				if foundGemData then
					return "Ambiguous gem name '" .. nameSpec .. "': matches '" .. foundGemData.name .. "', '" .. gemData.name .. "'"
				end
				foundGemData = gemData
			end
		end
		if foundGemData then
			return nil, foundGemData
		end
	end
	return "Unrecognised gem name '" .. nameSpec .. "'"
end

function SkillsTabClass:ProcessGemLevel(gemData)
	local grantedEffect = gemData.grantedEffect
	local naturalMaxLevel = gemData.naturalMaxLevel
	if self.defaultGemLevel == "awakenedMaximum" then
		return naturalMaxLevel + 1
	elseif self.defaultGemLevel == "corruptedMaximum" then
		if grantedEffect.plusVersionOf then
			return naturalMaxLevel
		else
			return naturalMaxLevel + 1
		end
	elseif self.defaultGemLevel == "normalMaximum" then
		return naturalMaxLevel
	else -- self.defaultGemLevel == "characterLevel"
		local maxGemLevel = naturalMaxLevel
		if not grantedEffect.levels[maxGemLevel] then
			maxGemLevel = #grantedEffect.levels
		end
		local characterLevel = self.build and self.build.characterLevel or 1
		for gemLevel = maxGemLevel, 1, -1 do
			if grantedEffect.levels[gemLevel].levelRequirement <= characterLevel then
				return gemLevel
			end
		end
		return 1
	end
end

-- Processes the given socket group, filling in information that will be used for display or calculations
function SkillsTabClass:ProcessSocketGroup(socketGroup)
	-- Loop through the skill gem list
	local data = self.build.data
	local gemInstance = socketGroup
	gemInstance.color = "^8"
	gemInstance.nameSpec = gemInstance.nameSpec or ""
	local prevDefaultLevel = gemInstance.gemData and gemInstance.gemData.naturalMaxLevel or (gemInstance.new and 20)
	gemInstance.gemData, gemInstance.grantedEffect = nil
	if gemInstance.gemId then
		-- Specified by gem ID
		-- Used for skills granted by skill gems
		gemInstance.errMsg = nil
		gemInstance.gemData = data.gems[gemInstance.gemId]
		if gemInstance.gemData then
			gemInstance.nameSpec = gemInstance.gemData.name
			gemInstance.skillId = gemInstance.gemData.grantedEffectId
		end
	elseif gemInstance.skillId then
		-- Specified by skill ID
		-- Used for skills granted by items
		gemInstance.errMsg = nil
		gemInstance.grantedEffect = data.skills[gemInstance.skillId]
	elseif gemInstance.nameSpec:match("%S") then
		-- Specified by gem/skill name, try to match it
		-- Used to migrate pre-1.4.20 builds
		gemInstance.errMsg, gemInstance.gemData = self:FindSkillGem(gemInstance.nameSpec)
		gemInstance.gemId = gemInstance.gemData and gemInstance.gemData.id
		gemInstance.skillId = gemInstance.gemData and gemInstance.gemData.grantedEffectId
		if gemInstance.gemData then
			gemInstance.nameSpec = gemInstance.gemData.name
		end
	else
		gemInstance.errMsg, gemInstance.gemData, gemInstance.skillId = nil
	end
	if gemInstance.gemData and gemInstance.gemData.grantedEffect.unsupported then
		gemInstance.errMsg = gemInstance.nameSpec .. " is not supported yet"
		gemInstance.gemData = nil
	end
	if gemInstance.gemData or gemInstance.grantedEffect then
		gemInstance.new = nil
		local grantedEffect = gemInstance.grantedEffect or gemInstance.gemData.grantedEffect
		if grantedEffect.color == 1 then
			gemInstance.color = colorCodes.STRENGTH
		elseif grantedEffect.color == 2 then
			gemInstance.color = colorCodes.DEXTERITY
		elseif grantedEffect.color == 3 then
			gemInstance.color = colorCodes.INTELLIGENCE
		else
			gemInstance.color = colorCodes.NORMAL
		end
		if prevDefaultLevel and gemInstance.gemData and gemInstance.gemData.naturalMaxLevel ~= prevDefaultLevel then
			gemInstance.level = gemInstance.gemData.naturalMaxLevel
			gemInstance.naturalMaxLevel = gemInstance.level
		end
		if gemInstance.gemData then
			gemInstance.reqLevel = grantedEffect.levels[gemInstance.level].levelRequirement
			gemInstance.reqStr = calcLib.getGemStatRequirement(gemInstance.reqLevel, grantedEffect.support, gemInstance.gemData.reqStr)
			gemInstance.reqDex = calcLib.getGemStatRequirement(gemInstance.reqLevel, grantedEffect.support, gemInstance.gemData.reqDex)
			gemInstance.reqInt = calcLib.getGemStatRequirement(gemInstance.reqLevel, grantedEffect.support, gemInstance.gemData.reqInt)
		end
	end
end

function SkillsTabClass:CreateUndoState()
	local state = { }
	state.activeSkillSetId = self.activeSkillSetId
	state.skillSets = { }
	for skillSetIndex, skillSet in pairs(self.skillSets) do
		local newSkillSet = copyTable(skillSet, true)
		newSkillSet.socketGroupList = { }
		for socketGroupIndex, socketGroup in pairs(skillSet.socketGroupList) do
			local newGroup = copyTable(socketGroup, true)
			newSkillSet.socketGroupList[socketGroupIndex] = newGroup
		end
		state.skillSets[skillSetIndex] = newSkillSet
	end
	state.skillSetOrderList = copyTable(self.skillSetOrderList)
	-- Save active socket group for both skillsTab and calcsTab to UndoState
	state.activeSocketGroup = self.build.mainSocketGroup
	state.activeSocketGroup2 = self.build.calcsTab.input.skill_number
	return state
end

function SkillsTabClass:RestoreUndoState(state)
	local displayId = isValueInArray(self.socketGroupList, self.displayGroup)
	wipeTable(self.skillSets)
	for k, v in pairs(state.skillSets) do
		self.skillSets[k] = v
	end
	wipeTable(self.skillSetOrderList)
	for k, v in ipairs(state.skillSetOrderList) do
		self.skillSetOrderList[k] = v
	end
	self:SetActiveSkillSet(state.activeSkillSetId)
	-- Load active socket group for both skillsTab and calcsTab from UndoState
	self.build.mainSocketGroup = state.activeSocketGroup
	self.build.calcsTab.input.skill_number = state.activeSocketGroup2
end

-- Opens the skill set manager
function SkillsTabClass:OpenSkillSetManagePopup()
	main:OpenPopup(370, 290, "Manage Skill Sets", {
		new("SkillSetListControl", nil, 0, 50, 350, 200, self),
		new("ButtonControl", nil, 0, 260, 90, 20, "Done", function()
			main:ClosePopup()
		end),
	})
end

-- Creates a new skill set
function SkillsTabClass:NewSkillSet(skillSetId)
	local skillSet = { id = skillSetId, socketGroupList = {} }
	if not skillSetId then
		skillSet.id = 1
		while self.skillSets[skillSet.id] do
			skillSet.id = skillSet.id + 1
		end
	end
	self.skillSets[skillSet.id] = skillSet
	return skillSet
end

-- Changes the active skill set
function SkillsTabClass:SetActiveSkillSet(skillSetId)
	-- Initialize skill sets if needed
	if not self.skillSetOrderList[1] then
		self.skillSetOrderList[1] = 1
		self:NewSkillSet(1)
	end

	if not skillSetId then
		skillSetId = self.activeSkillSetId
	end

	if not self.skillSets[skillSetId] then
		skillSetId = self.skillSetOrderList[1]
	end

	self.socketGroupList = self.skillSets[skillSetId].socketGroupList
	self.activeSkillSetId = skillSetId
	self.build.buildFlag = true
end

function SkillsTabClass:SelSkill(index, skillId)
	self.build.spec:ResetSkill(index)
	if skillId then
		self.socketGroupList[index] = {
			grantedEffect = self.build.data.skills[skillId] or {
				id = skillId,
				name = skillId,
				skillTypes = {},
				baseFlags = {},
				stats = {},
			},
			skillId = skillId,
			slot = "Skill " .. index,
			enabled = true
		}
	else
		self.socketGroupList[index] = nil
	end
	-- Reset the zoom cache so the tree re-fits when skills change
	self.skillTreeViewer.skillBaseScale = nil
	self.skillTreeViewer.skillRefZoom = nil
	self:AddUndoState()
	self.build.buildFlag = true
end

-- Get skill level for a given skill slot
-- In Last Epoch, skill level = total allocated points in that skill's tree
function SkillsTabClass:GetSkillLevel(index)
	local socketGroup = self.socketGroupList[index]
	if not socketGroup or not socketGroup.grantedEffect then
		return 0
	end
	-- Skill level equals the number of points spent in the skill tree
	return self:GetUsedSkillPoints(index)
end

-- Get the maximum skill points available for a skill tree
-- In Last Epoch, each skill has a hard cap of 20 points (skill level 20).
-- Equipment can push beyond 20 but base is always 20.
function SkillsTabClass:GetMaxSkillPoints(index)
	return 20
end

-- Get the number of skill points used in a skill tree
function SkillsTabClass:GetUsedSkillPoints(index)
	local socketGroup = self.socketGroupList[index]
	if not socketGroup or not socketGroup.grantedEffect or not socketGroup.grantedEffect.treeId then
		return 0
	end
	
	local treeId = socketGroup.grantedEffect.treeId
	local usedPoints = 0
	
	-- Count allocated nodes in this skill's tree, excluding the root node (maxPoints=0)
	for nodeId, node in pairs(self.build.spec.allocNodes) do
		if nodeId:match("^" .. treeId) and (node.maxPoints or 0) > 0 then
			usedPoints = usedPoints + (node.alloc or 0)
		end
	end
	
	return usedPoints
end