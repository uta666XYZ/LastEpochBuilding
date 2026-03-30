-- Last Epoch Planner
--
-- Class: Passive Tree View
-- Passive skill tree viewer.
-- Draws the passive skill tree, and also maintains the current view settings (zoom level, position, etc)
--
local pairs = pairs
local ipairs = ipairs
local t_insert = table.insert
local t_remove = table.remove
local m_min = math.min
local m_max = math.max
local m_floor = math.floor
local band = bit.band
local b_rshift = bit.rshift

local PassiveTreeViewClass = newClass("PassiveTreeView", function(self)
	self.tooltip = new("Tooltip")

	-- Default zoom level (higher = more zoomed in)
	-- LE trees are much smaller than PoE, so we need much higher zoom
	self.zoomLevel = 22  -- Increased from 18
	self.zoom = 1.2 ^ self.zoomLevel
	self.zoomX = 0
	self.zoomY = 0

	self.searchStr = ""
	self.searchStrSaved = ""
	self.searchStrCached = ""
	self.searchStrResults = {}
	self.showStatDifferences = true
	self.hoverNode = nil
	
	-- Filter mode: "all" (default), "passive" (passive tree only), "skill" (skill trees only)
	self.filterMode = "all"
	-- Selected skill index for skill tree view (1-5)
	self.selectedSkillIndex = nil
	
	-- Fixed size mode (like LETools): tree size doesn't change with window size
	self.fixedSizeMode = false
	self.fixedTreeSize = 400  -- Fixed tree viewport size in pixels
	
	-- Load reqPoints gate dot image
	self.dotFilled = NewImageHandle()
	self.dotFilled:Load("TreeData/PassiveBonusFilled.png")

	-- Disable dragging (for LE-style fixed position trees)
	self.disableDragging = false
	
	-- Disable zooming (for fixed-size skill trees)
	self.disableZooming = false
	
	-- Anchor position: "center" (default), "left", "top-left"
	self.anchorPosition = "center"
end)

function PassiveTreeViewClass:Load(xml, fileName)
	if xml.attrib.zoomLevel then
		self.zoomLevel = tonumber(xml.attrib.zoomLevel)
		self.zoom = 1.2 ^ self.zoomLevel
	end
	if xml.attrib.zoomX and xml.attrib.zoomY then
		self.zoomX = tonumber(xml.attrib.zoomX)
		self.zoomY = tonumber(xml.attrib.zoomY)
	end
	if xml.attrib.searchStr then
		self.searchStr = xml.attrib.searchStr
		self.searchStrSaved = xml.attrib.searchStr
	end
	if xml.attrib.showStatDifferences then
		self.showStatDifferences = xml.attrib.showStatDifferences == "true"
	end
end

function PassiveTreeViewClass:Save(xml)
	self.searchStrSaved = self.searchStr
	xml.attrib = {
		zoomLevel = tostring(self.zoomLevel),
		zoomX = tostring(self.zoomX),
		zoomY = tostring(self.zoomY),
		searchStr = self.searchStr,
		showStatDifferences = tostring(self.showStatDifferences),
	}
end

function PassiveTreeViewClass:Draw(build, viewPort, inputEvents)
	local spec = build.spec
	local tree = spec.tree

	-- NOTE: SetViewport removed because it conflicts with scrolling
	-- The viewport position changes when scrolling, but SetViewport uses fixed screen coordinates
	-- Instead, we rely on proper scale/offset calculation to fit tree in viewport

	-- Helper function to check if a node should be visible based on filterMode
	local function shouldShowNode(nodeId, node)
		if self.filterMode == "all" then
			return true
		elseif self.filterMode == "passive" then
			-- Show only passive tree nodes (class-based nodes)
			return nodeId:match("^" .. spec.curClassName) ~= nil
		elseif self.filterMode == "skill" then
			-- Show only skill tree nodes
			if self.selectedSkillIndex then
				-- Show only the selected skill's tree
				local ability = build.skillsTab.socketGroupList[self.selectedSkillIndex]
				if ability then
					-- Try treeId first, then skillId (for compatibility with original code)
					local treeId = (ability.grantedEffect and ability.grantedEffect.treeId) or ability.skillId
					if treeId then
						return nodeId:match("^" .. treeId) ~= nil
					end
				end
				return false
			else
				-- Show all skill trees
				for id, ability in pairs(build.skillsTab.socketGroupList) do
					local treeId = (ability.grantedEffect and ability.grantedEffect.treeId) or ability.skillId
					if treeId and nodeId:match("^" .. treeId) then
						return true
					end
				end
				return false
			end
		end
		return true
	end

	-- Helper function to check if a connector should be visible
	local function shouldShowConnector(connectorNodeId1)
		if self.filterMode == "all" then
			return true
		elseif self.filterMode == "passive" then
			return connectorNodeId1:match("^" .. spec.curClassName) ~= nil
		elseif self.filterMode == "skill" then
			if self.selectedSkillIndex then
				local ability = build.skillsTab.socketGroupList[self.selectedSkillIndex]
				if ability then
					-- Try treeId first, then skillId (for compatibility with original code)
					local treeId = (ability.grantedEffect and ability.grantedEffect.treeId) or ability.skillId
					if treeId then
						return connectorNodeId1:match("^" .. treeId) ~= nil
					end
				end
				return false
			else
				for id, ability in pairs(build.skillsTab.socketGroupList) do
					local treeId = (ability.grantedEffect and ability.grantedEffect.treeId) or ability.skillId
					if treeId and connectorNodeId1:match("^" .. treeId) then
						return true
					end
				end
				return false
			end
		end
		return true
	end

	local cursorX, cursorY = GetCursorPos()
	local mOver = cursorX >= viewPort.x and cursorX < viewPort.x + viewPort.width and cursorY >= viewPort.y and cursorY < viewPort.y + viewPort.height
	
	-- Process input events
	local treeClick
	for id, event in ipairs(inputEvents) do
		if event.type == "KeyDown" then
			if event.key == "LEFTBUTTON" then
				if mOver and not self.disableDragging then
					-- Record starting coords of mouse drag (only if dragging is enabled)
					self.dragX, self.dragY = cursorX, cursorY
				end
			elseif event.key == "p" then
				self.showHeatMap = not self.showHeatMap
			elseif event.key == "d" and IsKeyDown("CTRL") then
				self.showStatDifferences = not self.showStatDifferences
			elseif event.key == "PAGEUP" and not self.disableZooming then
				self:Zoom(IsKeyDown("SHIFT") and 3 or 1, viewPort)
			elseif event.key == "PAGEDOWN" and not self.disableZooming then
				self:Zoom(IsKeyDown("SHIFT") and -3 or -1, viewPort)
			elseif itemLib.wiki.matchesKey(event.key) and self.hoverNode then
				itemLib.wiki.open(self.hoverNode.name or self.hoverNode.dn)
			end
		elseif event.type == "KeyUp" then
			if event.key == "LEFTBUTTON" then
				if self.dragX and not self.dragging then
					-- Mouse button went down, but didn't move far enough to trigger drag, so register a normal click
					treeClick = "LEFT"
				elseif not self.dragX and mOver then
					-- Dragging disabled, treat as click
					treeClick = "LEFT"
				end
			elseif mOver then
				if event.key == "RIGHTBUTTON" then
					treeClick = "RIGHT"
				-- Zoom is handled separately, don't process wheel events here if zooming is disabled
				elseif event.key == "WHEELUP" and not self.disableZooming then
					self:Zoom(IsKeyDown("SHIFT") and 3 or 1, viewPort)
				elseif event.key == "WHEELDOWN" and not self.disableZooming then
					self:Zoom(IsKeyDown("SHIFT") and -3 or -1, viewPort)
				end	
			end
		end
	end

	if not IsKeyDown("LEFTBUTTON") then
		-- Left mouse button isn't down, stop dragging if dragging was in progress
		if self.dragging then
			self.dragging = false
		end
		self.dragX, self.dragY = nil, nil
	end

	-- Drag handling: use IsKeyDown directly so it works even if inputEvents was consumed
	-- by ProcessControlsInput earlier in the frame.
	-- We intentionally do NOT require mOver here so that drag continues even if cursor
	-- briefly leaves the viewport during fast mouse movement.
	if not self.disableDragging then
		if IsKeyDown("LEFTBUTTON") then
			if not self.dragX then
				-- Only start a new drag if cursor is inside the viewport
				if mOver then
					self.dragX, self.dragY = cursorX, cursorY
				end
			else
				-- Drag already started — continue regardless of mOver
				if not self.dragging then
					if math.abs(cursorX - self.dragX) > 5 or math.abs(cursorY - self.dragY) > 5 then
						self.dragging = true
					end
				end
				if self.dragging then
					self.zoomX = self.zoomX + cursorX - self.dragX
					self.zoomY = self.zoomY + cursorY - self.dragY
					self.dragX, self.dragY = cursorX, cursorY
				end
			end
		end
	end

	-- Ctrl-click to zoom
	if treeClick and IsKeyDown("CTRL") then
		self:Zoom(treeClick == "RIGHT" and -2 or 2, viewPort)
		treeClick = nil
	end

	-- Clamp zoom offset
	local clampFactor
	if self.filterMode == "skill" and self.selectedSkillIndex then
		-- Single skill tree: tight clamp (small tree, not much panning needed)
		clampFactor = self.zoom * 0.08
	elseif self.filterMode == "skill" then
		-- All-trees mode: generous clamp to allow panning across all trees
		clampFactor = self.zoom * 2.0
	else
		-- Passive tree (filterMode "all" or "passive"): original clamp
		clampFactor = self.zoom * 2 / 3
	end
	self.zoomX = self.zoomX ~= nil and m_min(m_max(self.zoomX, -viewPort.width * clampFactor), viewPort.width * clampFactor) or 1
	self.zoomY = self.zoomY ~= nil and m_min(m_max(self.zoomY, -viewPort.height * clampFactor), viewPort.height * clampFactor) or 1

	-- Create functions that will convert coordinates between the screen and tree coordinate spaces
	local scale
	local offsetX, offsetY
	
	-- For skill trees
	if self.filterMode == "skill" then
		-- Check if showing a single tree or all trees
		if self.selectedSkillIndex then
			-- SINGLE TREE MODE: Show only the selected skill's tree
			local ability = build.skillsTab.socketGroupList[self.selectedSkillIndex]
			-- Try treeId first, then skillId (for compatibility with original code)
			local treeId = ability and ((ability.grantedEffect and ability.grantedEffect.treeId) or ability.skillId)
			if treeId then
				local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
				local hasNodes = false
				local maxNodeRadius = 50  -- Default node radius estimate
				
				for nodeId, node in pairs(spec.visibleNodes) do
					if nodeId:match("^" .. treeId) then
						hasNodes = true
						-- Account for node radius
						local nodeRadius = node.rsq and math.sqrt(node.rsq) or 50
						if nodeRadius > maxNodeRadius then maxNodeRadius = nodeRadius end
						
						if node.x < minX then minX = node.x end
						if node.x > maxX then maxX = node.x end
						if node.y < minY then minY = node.y end
						if node.y > maxY then maxY = node.y end
					end
				end
				
				if hasNodes then
					-- Add node radius to bounds
					minX = minX - maxNodeRadius
					maxX = maxX + maxNodeRadius
					minY = minY - maxNodeRadius
					maxY = maxY + maxNodeRadius
					
					local treeWidth = maxX - minX
					local treeHeight = maxY - minY
					
					-- Padding from viewport edges
					local padding = 8
					local vpW = viewPort.width - padding * 2
					local vpH = viewPort.height - padding * 2
					
					-- Calculate scale to fit viewport (responsive)
					local scaleX = vpW / treeWidth
					local scaleY = vpH / treeHeight
					scale = m_min(scaleX, scaleY)
					
					-- Clamp scale to reasonable range (allow up to 1.0 for larger viewports)
					scale = m_max(0.1, m_min(scale, 1.0))
					
					-- Left-top aligned
					offsetX = viewPort.x + padding - minX * scale
					offsetY = viewPort.y + padding - minY * scale
					
					self.lastTreeWidth = treeWidth * scale
					self.lastTreeHeight = treeHeight * scale
				else
					scale = 0.4
					offsetX = viewPort.x + 10
					offsetY = viewPort.y + 10
					self.lastTreeWidth = 100
					self.lastTreeHeight = 100
				end
			else
				scale = 0.4
				offsetX = viewPort.x + 10
				offsetY = viewPort.y + 10
				self.lastTreeWidth = 100
				self.lastTreeHeight = 100
			end
			self.treeOffsets = nil
		else
			-- ALL TREES MODE: Show all 5 skill trees stacked vertically with zoom/pan support
			local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
			local hasNodes = false
			local treeOffsets = {}
			local currentYOffset = 0
			local TREE_GAP = 300
			
			for i = 1, 5 do
				local ability = build.skillsTab.socketGroupList[i]
				-- Try treeId first, then skillId (for compatibility with original code)
				local treeId = ability and ((ability.grantedEffect and ability.grantedEffect.treeId) or ability.skillId)
				if treeId then
					local treeMinX, treeMaxX, treeMinY, treeMaxY = math.huge, -math.huge, math.huge, -math.huge
					local treeHasNodes = false
					
					for nodeId, node in pairs(spec.visibleNodes) do
						if nodeId:match("^" .. treeId) then
							treeHasNodes = true
							if node.x < treeMinX then treeMinX = node.x end
							if node.x > treeMaxX then treeMaxX = node.x end
							if node.y < treeMinY then treeMinY = node.y end
							if node.y > treeMaxY then treeMaxY = node.y end
						end
					end
					
					if treeHasNodes then
						hasNodes = true
						local treeHeight = treeMaxY - treeMinY
						
						treeOffsets[i] = {
							yOffset = currentYOffset - treeMinY,
							treeId = treeId,
							name = ability.grantedEffect.name or ("Skill " .. i)
						}
						
						if treeMinX < minX then minX = treeMinX end
						if treeMaxX > maxX then maxX = treeMaxX end
						if currentYOffset < minY then minY = currentYOffset end
						
						currentYOffset = currentYOffset + treeHeight + TREE_GAP
						if currentYOffset - TREE_GAP > maxY then maxY = currentYOffset - TREE_GAP end
					end
				end
			end
			
			self.treeOffsets = treeOffsets
			
			if hasNodes then
				local treeWidth = maxX - minX
				local treeHeight = maxY - minY
				
				local padding = 40
				local vpW = viewPort.width - padding * 2
				local vpH = viewPort.height - padding * 2
				
				-- Calculate base scale to fit all trees in viewport
				local baseScaleX = vpW / treeWidth
				local baseScaleY = vpH / treeHeight
				local baseScale = m_min(baseScaleX, baseScaleY)
				baseScale = m_max(0.05, m_min(baseScale, 0.8))
				
				-- Apply zoom multiplier (self.zoom starts at 1.2^22 but we use relative ratio)
				-- We store the reference zoom level when first computed
				if not self.skillBaseScale then
					self.skillBaseScale = baseScale
					self.skillRefZoom = self.zoom
				end
				-- Scale with zoom: multiply baseScale by zoom ratio
				scale = self.skillBaseScale * (self.zoom / self.skillRefZoom)
				scale = m_max(0.04, m_min(scale, 12.0))
				
				-- Center the tree in the viewport, then apply pan offset
				local treeCenterX = (minX + maxX) / 2
				local treeCenterY = (minY + maxY) / 2
				offsetX = self.zoomX + viewPort.x + viewPort.width / 2 - treeCenterX * scale
				offsetY = self.zoomY + viewPort.y + viewPort.height / 2 - treeCenterY * scale
				
				self.lastTreeWidth = treeWidth * scale + padding * 2
				self.lastTreeHeight = treeHeight * scale + padding * 2
			else
				scale = 0.5
				offsetX = viewPort.x + 30
				offsetY = viewPort.y + 30
				self.lastTreeWidth = 300
				self.lastTreeHeight = 200
				self.treeOffsets = {}
			end
		end
	else
		-- For passive tree: use original calculation with zoom (centered)
		self.treeOffsets = nil
		local referenceSize
		if self.fixedSizeMode then
			referenceSize = self.fixedTreeSize or 600
		else
			referenceSize = m_min(viewPort.width, viewPort.height)
		end
		scale = referenceSize / tree.size * self.zoom
		offsetX = self.zoomX + viewPort.x + viewPort.width / 2
		offsetY = self.zoomY + viewPort.y + viewPort.height / 2
	end
	
	-- Store scale for use in helper functions
	self.currentScale = scale
	self.currentTreeOffsets = self.treeOffsets
	
	-- Helper function to get Y offset for a node based on its tree
	local function getNodeYOffset(nodeId)
		if self.filterMode == "skill" and self.treeOffsets then
			for i, treeData in pairs(self.treeOffsets) do
				if treeData and treeData.treeId and nodeId:match("^" .. treeData.treeId) then
					return treeData.yOffset or 0
				end
			end
		elseif self.filterMode == "all" then
			for id, ability in pairs(build.skillsTab.socketGroupList) do
				if ability.grantedEffect and ability.grantedEffect.treeId and not ability.triggered and nodeId:match("^" .. ability.grantedEffect.treeId) then
					return (id - 1) * (tree.decAbilityPosY + 1000)
				end
			end
		end
		return 0
	end
	
	local function treeToScreen(x, y)
		return x * scale + offsetX,
		       y * scale + offsetY
	end
	
	-- Version that applies node-specific Y offset
	local function treeToScreenWithOffset(x, y, nodeId)
		local yOff = getNodeYOffset(nodeId)
		return x * scale + offsetX,
		       (y + yOff) * scale + offsetY
	end
	
	local function screenToTree(x, y)
		return (x - offsetX) / scale,
		       (y - offsetY) / scale
	end

	if IsKeyDown("SHIFT") then
		-- Enable path tracing mode
		self.traceMode = true
		self.tracePath = self.tracePath or { }
	else
		self.traceMode = false
		self.tracePath = nil
	end

	local hoverNode
	if mOver then
		-- Cursor is over the tree, check if it is over a node
		local curTreeX, curTreeY = screenToTree(cursorX, cursorY)
		for nodeId, node in pairs(spec.visibleNodes) do
			if shouldShowNode(nodeId, node) and node.rsq and not node.isProxy then
				-- Node has a defined size (i.e. has artwork)
				local vX = curTreeX - node.x
				local nodeY = node.y + getNodeYOffset(nodeId)
				local vY = curTreeY - nodeY
				if vX * vX + vY * vY <= node.rsq then
					hoverNode = node
					break
				end
			end
		end
	end

	self.hoverNode = hoverNode
	-- If hovering over a node, find the path to it (if unallocated) or the list of dependent nodes (if allocated)
	local hoverPath, hoverDep
	if self.traceMode then
		-- Path tracing mode is enabled
		if hoverNode then
			if not hoverNode.path then
				-- Don't highlight the node if it can't be pathed to
				hoverNode = nil
			elseif not self.tracePath[1] then
				-- Initialise the trace path using this node's path
				for _, pathNode in ipairs(hoverNode.path) do
					t_insert(self.tracePath, 1, pathNode)
				end
			else
				local lastPathNode = self.tracePath[#self.tracePath]
				if hoverNode ~= lastPathNode then
					-- If node is directly linked to the last node in the path, add it
					if isValueInArray(hoverNode.linked, lastPathNode) then
						local index = isValueInArray(self.tracePath, hoverNode)
						if index then
							-- Node is already in the trace path, remove it first
							t_remove(self.tracePath, index)
							t_insert(self.tracePath, hoverNode)
						elseif lastPathNode.type == "Mastery" then
							hoverNode = nil
						else
							t_insert(self.tracePath, hoverNode)
						end
					else
						hoverNode = nil
					end
				end
			end
		end
		-- Use the trace path as the path 
		hoverPath = { }
		for _, pathNode in pairs(self.tracePath) do
			hoverPath[pathNode] = true
		end
	elseif hoverNode and hoverNode.path then
		-- Use the node's own path and dependence list
		hoverPath = { }
		if not hoverNode.dependsOnIntuitiveLeapLike then
			for _, pathNode in pairs(hoverNode.path) do
				hoverPath[pathNode] = true
			end
		end
		hoverDep = { }
		for _, depNode in pairs(hoverNode.depends) do
			hoverDep[depNode] = true
		end
	end

	if treeClick == "LEFT" then
		if hoverNode then
			-- User left-clicked on a node
			if IsKeyDown("ALT") then
				build.treeTab:ModifyNodePopup(hoverNode, viewPort)
			else
				if hoverNode.alloc > 0 then
					if hoverNode.alloc < hoverNode.maxPoints then
						hoverNode.alloc = hoverNode.alloc + 1
						tree:ProcessStats(hoverNode)
						spec:BuildAllDependsAndPaths()
						spec:AddUndoState()
						build.buildFlag = true
					end
				else
					spec:AllocNode(hoverNode, self.tracePath and hoverNode == self.tracePath[#self.tracePath] and self.tracePath)
					spec:AddUndoState()
					build.buildFlag = true
				end
			end
		end
	elseif treeClick == "RIGHT" then
		if hoverNode and hoverNode.maxPoints > 0 then
			-- User right-clicked on a node
			if hoverNode.alloc > 1 then
				hoverNode.alloc = hoverNode.alloc - 1
				tree:ProcessStats(hoverNode)
				spec:BuildAllDependsAndPaths()
				spec:AddUndoState()
				build.buildFlag = true
			else
				spec:DeallocNode(hoverNode)
				spec:AddUndoState()
				build.buildFlag = true
			end
		end
	end

	-- Draw classes background art for the main class and the three ascension classes
	-- Only draw if showing passive tree
	if self.filterMode ~= "skill" then
		for i = 0, 3 do
			local scrX, scrY = treeToScreen(-220, i * 1000)
			self:DrawAsset(tree.assets.ClassBackground, scrX, scrY, scale)
		end
	end

	-- Draw skills background art for all selected skills
	-- Only draw if showing skill trees
	if self.filterMode ~= "passive" then
		if self.filterMode == "skill" and self.selectedSkillIndex then
			-- Draw only the selected skill's background
			local ability = build.skillsTab.socketGroupList[self.selectedSkillIndex]
			if ability and ability.grantedEffect and ability.grantedEffect.treeId then
				local scrX, scrY = treeToScreen(3000, 150)
				self:DrawAsset(tree.assets.SkillBackground, scrX, scrY, scale)
			end
		elseif self.filterMode == "skill" and self.treeOffsets then
			-- All-trees mode: draw each skill background at its Y offset
			for i, treeData in pairs(self.treeOffsets) do
				local ability = build.skillsTab.socketGroupList[i]
				if ability and ability.grantedEffect and ability.grantedEffect.treeId then
					local scrX, scrY = treeToScreen(3000, 150 + (treeData.yOffset or 0))
					self:DrawAsset(tree.assets.SkillBackground, scrX, scrY, scale)
				end
			end
		else
			-- Draw all skill backgrounds (filterMode == "all")
			for id,ability in pairs(build.skillsTab.socketGroupList) do
				if ability.grantedEffect and ability.grantedEffect.treeId then
					local scrX, scrY = treeToScreen(3000, 150 + (id - 1) * (tree.decAbilityPosY + 1000))
					self:DrawAsset(tree.assets.SkillBackground, scrX, scrY, scale)
				end
			end
		end
	end

	local connectorColor = { 1, 1, 1 }
	local function setConnectorColor(r, g, b)
		connectorColor[1], connectorColor[2], connectorColor[3] = r, g, b
	end
	local function getState(n1, n2)
		-- Determine the connector state
		local state = "Normal"
		if n1.alloc > 0 and n2.alloc > 0 then
			state = "Active"
		elseif hoverPath then
			if (n1.alloc > 0 or n1 == hoverNode or hoverPath[n1]) and (n2.alloc > 0 or n2 == hoverNode or hoverPath[n2]) then
				state = "Intermediate"
			end
		end
		return state
	end
	-- Returns true if the edge between n1 and n2 has an unmet reqPoints gate
	local function isGatedUnmet(n1, n2)
		local req = n2.reqFromParent and n2.reqFromParent[n1.id]
		if req and n1.alloc < req then return true end
		req = n1.reqFromParent and n1.reqFromParent[n2.id]
		if req and n2.alloc < req then return true end
		return false
	end

	-- Get the reqPoints gate info for a connector (returns reqPts, parentAlloc or nil)
	local function getGateInfo(n1, n2)
		local req = n2.reqFromParent and n2.reqFromParent[n1.id]
		if req then return req, n1.alloc end
		req = n1.reqFromParent and n1.reqFromParent[n2.id]
		if req then return req, n2.alloc end
		return nil
	end

	-- Dot layout patterns per reqPoints count (game-style)
	-- Each entry is a list of {along, perp} offsets from center, in spacing units
	-- req 1:   *         req 2: * *       req 3: * * *
	-- req 4: * *         req 5:   *
	--        * *                * * *
	--                            *
	local dotLayouts = {
		[1] = { {0, 0} },
		[2] = { {0, -0.5}, {0, 0.5} },
		[3] = { {-1, 0}, {0, 0}, {1, 0} },
		[4] = { {-0.5, -0.5}, {0.5, -0.5}, {-0.5, 0.5}, {0.5, 0.5} },
		[5] = { {0, -1}, {-1, 0}, {0, 0}, {1, 0}, {0, 1} },
	}

	-- Draw reqPoints gate dots along a connector line (LETools/Maxroll style)
	-- screenCoords: the connector.c array with screen-space vertex coords (1-8)
	local function drawGateDots(screenCoords, reqPts, parentAlloc)
		if not reqPts or reqPts < 1 then return end
		local layout = dotLayouts[reqPts]
		if not layout then return end
		-- Midpoints of the two long edges of the connector quad
		local mx1 = (screenCoords[1] + screenCoords[7]) / 2
		local my1 = (screenCoords[2] + screenCoords[8]) / 2
		local mx2 = (screenCoords[3] + screenCoords[5]) / 2
		local my2 = (screenCoords[4] + screenCoords[6]) / 2
		-- Center of the connector
		local cx = (mx1 + mx2) / 2
		local cy = (my1 + my2) / 2
		-- Direction along the connector (from node1 side to node2 side)
		local dx = (screenCoords[7] - screenCoords[1] + screenCoords[5] - screenCoords[3]) / 2
		local dy = (screenCoords[8] - screenCoords[2] + screenCoords[6] - screenCoords[4]) / 2
		local len = m_max((dx * dx + dy * dy) ^ 0.5, 1)
		dx = dx / len
		dy = dy / len
		-- Perpendicular direction (rotated 90 degrees)
		local px_dir, py_dir = -dy, dx
		local dotRadius = m_max(25 * scale, 3)
		local spacing = dotRadius * 1.5
		for i, offsets in ipairs(layout) do
			local along, perp = offsets[1], offsets[2]
			local dotX = cx + dx * along * spacing + px_dir * perp * spacing
			local dotY = cy + dy * along * spacing + py_dir * perp * spacing
			if i <= parentAlloc then
				-- Filled: gold cream (#f0e6cd)
				SetDrawColor(0.94, 0.90, 0.80)
			else
				-- Unfilled: dark (#444)
				SetDrawColor(0.27, 0.27, 0.27)
			end
			DrawImage(self.dotFilled, dotX - dotRadius, dotY - dotRadius, dotRadius * 2, dotRadius * 2)
		end
		SetDrawColor(1, 1, 1)
	end

	local function renderConnector(connector)
		local node1, node2 = spec.nodes[connector.nodeId1], spec.nodes[connector.nodeId2]
		if not node1 or not node2 then return end
		setConnectorColor(1, 1, 1)
		local state = getState(node1, node2)
		local baseState = state
		if self.compareSpec then
			local cNode1, cNode2 = self.compareSpec.nodes[connector.nodeId1], self.compareSpec.nodes[connector.nodeId2]
			if cNode1 and cNode2 then
				baseState = getState(cNode1,cNode2)
			end
		end

		if baseState == "Active" and state ~= "Active" then
			state = "Active"
			setConnectorColor(0, 1, 0)
		end
		if baseState ~= "Active" and state == "Active" then
			setConnectorColor(1, 0, 0)
		end

		-- Convert vertex coordinates to screen-space and add them to the coordinate array
		local decY = 0
		-- Apply Y offset for skill trees or all mode
		if self.filterMode == "skill" and self.treeOffsets then
			for i, treeData in pairs(self.treeOffsets) do
				if treeData and treeData.treeId and connector.nodeId1:match("^" .. treeData.treeId) then
					decY = treeData.yOffset or 0
					break
				end
			end
		elseif self.filterMode == "all" or self.filterMode == "passive" then
			for id,ability in pairs(build.skillsTab.socketGroupList) do
				if ability.grantedEffect and ability.grantedEffect.treeId and not ability.triggered and connector.nodeId1:match("^" .. ability.grantedEffect.treeId) then
					decY = (id - 1) * (tree.decAbilityPosY + 1000)
				end
			end
		end
		local vert = connector.vert and connector.vert[state]
		if vert and tree.assets[connector.type..state] then
			connector.c[1], connector.c[2] = treeToScreen(vert[1], vert[2] + decY)
			connector.c[3], connector.c[4] = treeToScreen(vert[3], vert[4] + decY)
			connector.c[5], connector.c[6] = treeToScreen(vert[5], vert[6] + decY)
			connector.c[7], connector.c[8] = treeToScreen(vert[7], vert[8] + decY)

			if hoverDep and hoverDep[node1] and hoverDep[node2] then
				-- Both nodes depend on the node currently being hovered over, so color the line red
				setConnectorColor(1, 0, 0)
			elseif connector.ascendancyName and connector.ascendancyName ~= spec.curAscendClassName then
				-- Fade out lines in ascendancy classes other than the current one
				setConnectorColor(0.75, 0.75, 0.75)
			elseif state ~= "Active" and isGatedUnmet(node1, node2) then
				-- Unmet reqPoints gate: dark brown (#342a27) - LETools reference
				setConnectorColor(0.20, 0.16, 0.15)
			end
			SetDrawColor(unpack(connectorColor))
			DrawImageQuad(tree.assets[connector.type..state].handle, unpack(connector.c))
			-- Draw reqPoints gate dots on top of the connector
			local reqPts, parentAlloc = getGateInfo(node1, node2)
			if reqPts then
				drawGateDots(connector.c, reqPts, parentAlloc)
			end
		end
	end

	-- Draw the connecting lines between nodes
	SetDrawLayer(nil, 20)
	for _, connector in pairs(tree.connectors) do
		if shouldShowConnector(connector.nodeId1) then
			-- For skill mode with a single selected skill: use simple path (no Y offset needed)
			if self.filterMode == "skill" and self.selectedSkillIndex then
				local node1, node2 = spec.nodes[connector.nodeId1], spec.nodes[connector.nodeId2]
				if node1 and node2 then
					setConnectorColor(1, 1, 1)
					local state = getState(node1, node2)
					local baseState = state
					if self.compareSpec then
						local cNode1, cNode2 = self.compareSpec.nodes[connector.nodeId1], self.compareSpec.nodes[connector.nodeId2]
						if cNode1 and cNode2 then
							baseState = getState(cNode1,cNode2)
						end
					end

					if baseState == "Active" and state ~= "Active" then
						state = "Active"
						setConnectorColor(0, 1, 0)
					end
					if baseState ~= "Active" and state == "Active" then
						setConnectorColor(1, 0, 0)
					end

					-- Check if vert data exists for this state
					local vert = connector.vert and connector.vert[state]
					if not vert then
						-- Try fallback states
						vert = connector.vert and (connector.vert["Normal"] or connector.vert["Active"] or connector.vert["Intermediate"])
					end
					
					if vert and tree.assets[connector.type..state] then
						connector.c[1], connector.c[2] = treeToScreen(vert[1], vert[2])
						connector.c[3], connector.c[4] = treeToScreen(vert[3], vert[4])
						connector.c[5], connector.c[6] = treeToScreen(vert[5], vert[6])
						connector.c[7], connector.c[8] = treeToScreen(vert[7], vert[8])

						if hoverDep and hoverDep[node1] and hoverDep[node2] then
							setConnectorColor(1, 0, 0)
						elseif connector.ascendancyName and connector.ascendancyName ~= spec.curAscendClassName then
							setConnectorColor(0.75, 0.75, 0.75)
						elseif state ~= "Active" and isGatedUnmet(node1, node2) then
							setConnectorColor(1, 0.6, 0)
						end
						SetDrawColor(unpack(connectorColor))
						DrawImageQuad(tree.assets[connector.type..state].handle, unpack(connector.c))
						-- Draw reqPoints gate dots on top of the connector
						local reqPts, parentAlloc = getGateInfo(node1, node2)
						if reqPts then
							drawGateDots(connector.c, reqPts, parentAlloc)
						end
					end
				end
			else
				-- All-trees mode or passive mode: use renderConnector (applies treeOffsets Y)
				renderConnector(connector)
			end
		end
	end

	if self.showHeatMap then
		-- Build the power numbers if needed
		build.calcsTab:BuildPower()
		self.heatMapStat = build.calcsTab.powerStat
	end

	-- Update cached node data
	if self.searchStrCached ~= self.searchStr then
		self.searchStrCached = self.searchStr

		local function prepSearch(search)
			search = search:lower()
			--gsub("([%[%]%%])", "%%%1")
			local searchWords = {}
			for matchstring, v in search:gmatch('"([^"]*)"') do
				searchWords[#searchWords+1] = matchstring
				search = search:gsub('"'..matchstring:gsub("([%(%)])", "%%%1")..'"', "")
			end
			for matchstring, v in search:gmatch("(%S*)") do
				if matchstring:match("%S") ~= nil then
					searchWords[#searchWords+1] = matchstring
				end
			end
			return searchWords
		end
		self.searchParams = prepSearch(self.searchStr)

		for nodeId, node in pairs(spec.visibleNodes) do
			self.searchStrResults[nodeId] = #self.searchParams > 0 and self:DoesNodeMatchSearchParams(node)
		end
	end

	-- Draw the nodes
	for nodeId, node in pairs(spec.visibleNodes) do
		-- Skip nodes that don't match the filter
		if not shouldShowNode(nodeId, node) then
			goto continue_node_loop
		end

		-- Determine the base and overlay images for this node based on type and state
		local compareNode = self.compareSpec and self.compareSpec.nodes[nodeId] or nil

		local base, overlay, effect
		local isAlloc = node.alloc > 0 or build.calcsTab.mainEnv.grantedPassives[nodeId] or (compareNode and compareNode.alloc)
		SetDrawLayer(nil, 25)

		local state
		if self.showHeatMap or isAlloc or node == hoverNode or (self.traceMode and node == self.tracePath[#self.tracePath])then
			-- Show node as allocated if it is being hovered over
			-- Also if the heat map is turned on (makes the nodes more visible)
			state = "alloc"
		elseif hoverPath and hoverPath[node] then
			state = "path"
		else
			state = "unalloc"
		end
		-- Normal node (includes keystones and notables)
		if node.icon and not node.sprites then
			if not tree.spriteMap[node.icon] then
				local sheet = {}
				sheet.handle = NewImageHandle()
				sheet.handle:Load("TreeData/sprites/" .. node.icon .. ".png")
				sheet.width, sheet.height = sheet.handle:ImageSize()

				tree.spriteMap[node.icon] = {
					handle = sheet.handle,
					width = sheet.width,
					height = sheet.height,
					[1] = 0,
					[2] = 0,
					[3] = 1,
					[4] = 1
				}
			end
			node.sprites = tree.spriteMap[node.icon]
		end
		base = node.sprites

		-- Convert node position to screen-space
		local nodeY = node.y
		-- Apply Y offset for skill trees (filterMode == "skill") or all mode
		if self.filterMode == "skill" and self.treeOffsets then
			for i, treeData in pairs(self.treeOffsets) do
				if treeData and treeData.treeId and nodeId:match("^" .. treeData.treeId) then
					nodeY = nodeY + (treeData.yOffset or 0)
					break
				end
			end
		elseif self.filterMode == "all" then
			for id,ability in pairs(build.skillsTab.socketGroupList) do
				if ability.grantedEffect and ability.grantedEffect.treeId and not ability.triggered and nodeId:match("^" .. ability.grantedEffect.treeId) then
					nodeY = nodeY + (id - 1) * (tree.decAbilityPosY + 1000)
				end
			end
		end
		local scrX, scrY = treeToScreen(node.x, nodeY)
	
		-- Determine color for the base artwork
		if self.showHeatMap then
			if not isAlloc and node.type ~= "ClassStart" and node.type ~= "AscendClassStart" then
				if self.heatMapStat and self.heatMapStat.stat then
					-- Calculate color based on a single stat
					local stat = m_max(node.power.singleStat or 0, 0)
					local statCol = (stat / build.calcsTab.powerMax.singleStat * 1.5) ^ 0.5
					if main.nodePowerTheme == "RED/BLUE" then
						SetDrawColor(statCol, 0, 0)
					elseif main.nodePowerTheme == "RED/GREEN" then
						SetDrawColor(0, statCol, 0)
					elseif main.nodePowerTheme == "GREEN/BLUE" then
						SetDrawColor(0, 0, statCol)
					end
				else
					-- Calculate color based on DPS and defensive powers
					local offence = m_max(node.power.offence or 0, 0)
					local defence = m_max(node.power.defence or 0, 0)
					local dpsCol = (offence / build.calcsTab.powerMax.offence * 1.5) ^ 0.5
					local defCol = (defence / build.calcsTab.powerMax.defence * 1.5) ^ 0.5
					local mixCol = (m_max(dpsCol - 0.5, 0) + m_max(defCol - 0.5, 0)) / 2
					if main.nodePowerTheme == "RED/BLUE" then
						SetDrawColor(dpsCol, mixCol, defCol)
					elseif main.nodePowerTheme == "RED/GREEN" then
						SetDrawColor(dpsCol, defCol, mixCol)
					elseif main.nodePowerTheme == "GREEN/BLUE" then
						SetDrawColor(mixCol, dpsCol, defCol)
					end
				end
			else
				if compareNode then
					if compareNode.alloc > 0 and node.alloc == 0 then
						-- Base has, current has not, color green (take these nodes to match)
						SetDrawColor(0, 1, 0)
					elseif compareNode.alloc == 0 and node.alloc > 0 then
						-- Base has not, current has, color red (Remove nodes to match)
						SetDrawColor(1, 0, 0)
					else
						-- Both have or both have not, use white
						SetDrawColor(1, 1, 1)
					end
				else
					SetDrawColor(1, 1, 1)
				end
			end
		elseif launch.devModeAlt then
			-- Debug display
			if node.extra then
				SetDrawColor(1, 0, 0)
			elseif node.unknown then
				SetDrawColor(0, 1, 1)
			else
				SetDrawColor(0, 0, 0)
			end
		else
			if compareNode then
				if compareNode.alloc > 0 and node.alloc == 0 then
					-- Base has, current has not, color green (take these nodes to match)
					SetDrawColor(0, 1, 0)
				elseif compareNode.alloc == 0 and node.alloc > 0 then
					-- Base has not, current has, color red (Remove nodes to match)
					SetDrawColor(1, 0, 0)
				else
					-- Both have or both have not, use white
					SetDrawColor(1, 1, 1)
				end
			elseif isAlloc or node.maxPoints == 0 then
				SetDrawColor(1, 1, 1)
			else
				SetDrawColor(0.3, 0.3, 0.3)
			end
		end

		-- Draw mastery/tattoo effect artwork
		if effect then
			SetDrawLayer(nil, 15)
			self:DrawAsset(effect, scrX, scrY, scale)
			SetDrawLayer(nil, 25)
		end

		-- Draw base artwork
		if base then
			self:DrawAsset(base, scrX, scrY, scale)
			-- Draw the allocated number
			if node.maxPoints > 0 then
				DrawString(scrX, scrY + 48 * scale, "CENTER_X", round(50 * scale), "VAR", "^7" .. node.alloc .. "/" .. node.maxPoints)
			end
		end

		-- Draw "not scaling stats" indicators
		if node.noScalingPointThreshold and node.noScalingPointThreshold > 0 then
			if node.alloc >= node.noScalingPointThreshold then
		        self:DrawAsset(tree.assets.PassiveBonusFilled, scrX, scrY - 46 * scale, scale * 1.33)
			else
		        self:DrawAsset(tree.assets.PassiveBonusEmpty, scrX, scrY - 46 * scale, scale * 1.33)
			end
		end

		if overlay then
			-- Draw overlay
			if node.type ~= "ClassStart" and node.type ~= "AscendClassStart" then
				if hoverNode and hoverNode ~= node then
					-- Mouse is hovering over a different node
					if hoverDep and hoverDep[node] then
						-- This node depends on the hover node, turn it red
						SetDrawColor(1, 0, 0)
					end
				end
			end
			self:DrawAsset(tree.spriteMap[overlay], scrX, scrY, scale)
			SetDrawColor(1, 1, 1)
		end
		if self.searchStrResults[nodeId] then
			-- Node matches the search string, show the highlight circle
			SetDrawLayer(nil, 30)
			local rgbColor = rgbColor or {1, 0, 0}
			SetDrawColor(rgbColor[1], rgbColor[2], rgbColor[3])
			local size = 175 * scale / self.zoom ^ 0.4
			DrawImage(self.highlightRing, scrX - size, scrY - size, size * 2, size * 2)
		end
		if node == hoverNode and (node.type ~= "Socket" or not IsKeyDown("SHIFT")) and (node.type ~= "Mastery" or node.masteryEffects) and not IsKeyDown("CTRL") and not main.popups[1] then
			-- Draw tooltip
			SetDrawLayer(nil, 100)
			local size = m_floor(node.size * scale)
			if self.tooltip:CheckForUpdate(node, self.showStatDifferences, self.tracePath, launch.devModeAlt, build.outputRevision) then
				self:AddNodeTooltip(self.tooltip, node, build)
			end
			self.tooltip:Draw(m_floor(scrX - size), m_floor(scrY - size), size * 2, size * 2, viewPort)
		end

		::continue_node_loop::
	end
end

-- Draws the given asset at the given position
function PassiveTreeViewClass:DrawAsset(data, x, y, scale, isHalf)
	if not data then
		return
	end
	if data.width == 0 then
		data.width, data.height = data.handle:ImageSize()
		if data.width == 0 then
			return
		end
	end
	local width = data.width * scale * 1.33
	local height = data.height * scale * 1.33
	if isHalf then
		DrawImage(data.handle, x - width, y - height * 2, width * 2, height * 2)
		DrawImage(data.handle, x - width, y, width * 2, height * 2, 0, 1, 1, 0)
	else
		DrawImage(data.handle, x - width, y - height, width * 2, height * 2, unpack(data))
	end
end

-- Zoom the tree in or out
function PassiveTreeViewClass:Zoom(level, viewPort)
	local minLevel = (self.filterMode == "skill") and 0 or 14
	local maxLevel = (self.filterMode == "skill") and 38 or 24
	self.zoomLevel = m_max(minLevel, m_min(maxLevel, self.zoomLevel + level))
	local oldZoom = self.zoom
	self.zoom = 1.2 ^ self.zoomLevel

	-- Adjust zoom center position so that the point on the tree that is currently under the mouse will remain under it
	local factor = self.zoom / oldZoom
	local cursorX, cursorY = GetCursorPos()
	local relX = cursorX - viewPort.x - viewPort.width/2
	local relY = cursorY - viewPort.y - viewPort.height/2
	self.zoomX = relX + (self.zoomX - relX) * factor
	self.zoomY = relY + (self.zoomY - relY) * factor
end

function PassiveTreeViewClass:Focus(x, y, viewPort, build)
	self.zoomLevel = 12
	self.zoom = 1.2 ^ self.zoomLevel

	local tree = build.spec.tree
	local scale = m_min(viewPort.width, viewPort.height) / tree.size * self.zoom
	
	self.zoomX = -x * scale
	self.zoomY = -y * scale
end

function PassiveTreeViewClass:DoesNodeMatchSearchParams(node)
	if node.type == "ClassStart" or (node.type == "Mastery" and not node.masteryEffects) then
		return
	end

	local needMatches = copyTable(self.searchParams)
	local err

	local function search(haystack, need)
		for i=#need, 1, -1 do
			if haystack:matchOrPattern(need[i]) then
				table.remove(need, i)
			end
		end
		return need
	end

	-- Check node name
	err, needMatches = PCall(search, node.dn:lower(), needMatches)
	if err then return false end
	if #needMatches == 0 then
		return true
	end

	-- Check node description
	for index, line in ipairs(node.sd) do
		-- Check display text first
		err, needMatches = PCall(search, line:lower(), needMatches)
		if err then return false end
		if #needMatches == 0 then
			return true
		end
		if #needMatches > 0 and node.mods[index].list then
			-- Then check modifiers
			for _, mod in ipairs(node.mods[index].list) do
				err, needMatches = PCall(search, mod.name, needMatches)
				if err then return false end
				if #needMatches == 0 then
					return true
				end
			end
		end
	end

	-- Check node type
	err, needMatches = PCall(search, node.type:lower(), needMatches)
	if err then return false end
	if #needMatches == 0 then
		return true
	end

	-- Check node id for devs
	if launch.devMode then
		err, needMatches = PCall(search, tostring(node.id), needMatches)
		if err then return false end
		if #needMatches == 0 then
			return true
		end
	end
end

function PassiveTreeViewClass:AddNodeName(tooltip, node, build)
	local customized = ""
	if build.spec.hashOverrides[node.id] then
		customized = colorCodes.WARNING .. " (CUSTOMIZED)"
	end
	tooltip:AddLine(24, "^7"..node.dn..(launch.devModeAlt and " ["..node.id.."]" or "") .. customized)
end

function PassiveTreeViewClass:AddNodeTooltip(tooltip, node, build)
	-- Node name
	self:AddNodeName(tooltip, node, build)

	-- Show unmet reqPoints requirements
	if node.reqFromParent then
		for parentId, req in pairs(node.reqFromParent) do
			local parentNode = build.spec.nodes[parentId]
			if parentNode then
				local cur = parentNode.alloc or 0
				if cur < req then
					tooltip:AddLine(16, colorCodes.WARNING .. "Requires " .. req .. " points in " .. parentNode.dn .. " (" .. cur .. "/" .. req .. " allocated)")
				end
			end
		end
	end

	if launch.devModeAlt then
		if node.power and node.power.offence then
			-- Power debugging info
			tooltip:AddLine(16, string.format("DPS power: %g   Defence power: %g", node.power.offence, node.power.defence))
		end
	end

	local function addModInfoToTooltip(node, i, line)
		if node.mods[i] then
			if launch.devModeAlt and node.mods[i].list then
				-- Modifier debugging info
				local modStr
				for _, mod in pairs(node.mods[i].list) do
					modStr = (modStr and modStr..", " or "^2") .. modLib.formatMod(mod)
				end
				if node.mods[i].extra then
					modStr = (modStr and modStr.."  " or "") .. colorCodes.NEGATIVE .. node.mods[i].extra
				end
				if modStr then
					line = line .. "  " .. modStr
				end
			end
			tooltip:AddLine(16, ((node.mods[i].extra or not node.mods[i].list) and colorCodes.UNSUPPORTED or colorCodes.MAGIC)..line)
		end
	end

	if node.sd[1] then
		tooltip:AddLine(16, "")
		for i, line in ipairs(node.sd) do
			addModInfoToTooltip(node, i, line)
		end
	end

	-- Description
	if node.description then
		tooltip:AddSeparator(14)
		for _, line in ipairs(node.description) do
			line = line:gsub("{%[%d%]=(.-)}", "^xFFFFFF%1^xBCB199")
			line = line:gsub("{(.-)}", "^xFFFFFF%1^xBCB199")
			tooltip:AddLine(14, "^xBCB199".. line)
		end
	end

	-- Reminder text
	if node.reminderText then
		tooltip:AddSeparator(14)
		for _, line in ipairs(node.reminderText) do
			line = line:gsub("{%[%d%]=(.-)}", "^xFFFFFF%1^x808080")
			line = line:gsub("{(.-)}", "^xFFFFFF%1^x808080")
			tooltip:AddLine(14, "^x808080"..line)
		end
	end

	-- Mod differences
	if self.showStatDifferences then
		local calcFunc, calcBase = build.calcsTab:GetMiscCalculator(build)
		tooltip:AddSeparator(14)
		local path = (node.alloc > 0 and node.depends) or self.tracePath or node.path or { }
		local pathLength = #path
		local pathNodes = { }
		for _, node in pairs(path) do
			pathNodes[node] = true
		end
		local nodeOutput, pathOutput
		local isGranted = build.calcsTab.mainEnv.grantedPassives[node.id]
		local realloc = false
		if node.alloc > 0 then
			-- Calculate the differences caused by deallocating this node and its dependent nodes
			nodeOutput = calcFunc({ removeNodes = { [node] = true } })
			if not node.dependsOnIntuitiveLeapLike and pathLength > 1 then
				pathOutput = calcFunc({ removeNodes = pathNodes })
			end
		elseif isGranted then
			-- Calculate the differences caused by deallocating this node
			nodeOutput = calcFunc({ removeNodes = { [node.id] = true } })
		else
			-- Calculated the differences caused by allocating this node and all nodes along the path to it
			if node.type == "Mastery" and node.allMasteryOptions then
				pathNodes[node] = nil
				nodeOutput = calcFunc({})
			else
				nodeOutput = calcFunc({ addNodes = { [node] = true } })
			end
			if not node.dependsOnIntuitiveLeapLike and pathLength > 1 then
				pathOutput = calcFunc({ addNodes = pathNodes })
			end
		end
		local count = build:AddStatComparesToTooltip(tooltip, calcBase, nodeOutput, realloc and "^7Reallocating this node will give you:" or node.alloc > 0 and "^7Unallocating this node will give you:" or isGranted and "^7This node is granted by an item. Removing it will give you:" or "^7Allocating this node will give you:")
		if not node.dependsOnIntuitiveLeapLike and pathLength > 1 and not isGranted then
			count = count + build:AddStatComparesToTooltip(tooltip, calcBase, pathOutput, node.alloc > 0 and "^7Unallocating this node and all nodes depending on it will give you:" or "^7Allocating this node and all nodes leading to it will give you:", pathLength)
		end
		if node.maxPoints > 0 and count == 0 then
			if isGranted then
				tooltip:AddLine(14, string.format("^7This node is granted by an item. Removing it will cause no changes"))
			else
				tooltip:AddLine(14, string.format("^7No changes from %s this node%s.", node.alloc > 0 and "unallocating" or "allocating", not node.dependsOnIntuitiveLeapLike and pathLength > 1 and " or the nodes leading to it" or ""))
			end
		end
		if node.alloc and node.alloc > 0 and node.alloc < node.maxPoints then
			tooltip:AddSeparator(14)
			node.alloc = node.alloc + 1
			build.spec.tree:ProcessStats(node)
			nodeOutput = calcFunc()
			build:AddStatComparesToTooltip(tooltip, calcBase, nodeOutput, "^7Allocating one more point to this node will give you:")
			node.alloc = node.alloc - 1
			build.spec.tree:ProcessStats(node)
		end
		tooltip:AddLine(14, colorCodes.TIP.."Tip: Press Ctrl+D to disable the display of stat differences.")
	else
		tooltip:AddSeparator(14)
		tooltip:AddLine(14, colorCodes.TIP.."Tip: Press Ctrl+D to enable the display of stat differences.")
	end

	-- Pathing distance
	tooltip:AddSeparator(14)
	if node.path and #node.path > 0 then
		if self.traceMode and isValueInArray(self.tracePath, node) then
			tooltip:AddLine(14, "^7"..#self.tracePath .. " nodes in trace path")
			tooltip:AddLine(14, colorCodes.TIP)
		else
			tooltip:AddLine(14, "^7"..#node.path .. " points to node" .. (node.dependsOnIntuitiveLeapLike and " ^8(Can be allocated without pathing to it)" or ""))
			tooltip:AddLine(14, colorCodes.TIP)
			if #node.path > 1 then
				-- Handy hint!
				tooltip:AddLine(14, "Tip: To reach this node by a different path, hold Shift, then trace the path and click this node")
			end
		end
	end
	if node.depends and #node.depends > 1 then
		tooltip:AddSeparator(14)
		tooltip:AddLine(14, "^7"..#node.depends .. " points gained from unallocating these nodes")
		tooltip:AddLine(14, colorCodes.TIP)
	end
	tooltip:AddLine(14, colorCodes.TIP.."Tip: Hold Ctrl to hide this tooltip.")
	tooltip:AddLine(14, colorCodes.TIP.."Tip: Right click to remove allocated points.")
	tooltip:AddLine(14, colorCodes.TIP.."Tip: Hold Alt and left click to edit this node.")
end