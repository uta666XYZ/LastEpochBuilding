-- UILayout.lua
-- Simple UI Layout Engine for Last Epoch Building
-- Based on ChatGPT's advice: Vertical Layout, Auto Height, Viewport Auto Resize
--
-- Features:
--   1. Vertical Layout (items stack top to bottom)
--   2. Horizontal Layout (items stack left to right)
--   3. Auto-sizing viewports based on content
--   4. Clipping (don't draw outside viewport)
--   5. Scrolling support
--

local UILayout = {}
UILayout.__index = UILayout

--[[
================================================================================
  LAYOUT TYPES
================================================================================
--]]

UILayout.VERTICAL = "vertical"
UILayout.HORIZONTAL = "horizontal"

--[[
================================================================================
  CONSTRUCTOR
================================================================================
--]]

function UILayout.new(config)
    local self = setmetatable({}, UILayout)
    
    -- Viewport (the visible area)
    self.viewport = {
        x = config.x or 0,
        y = config.y or 0,
        width = config.width or 400,
        height = config.height or 300
    }
    
    -- Layout type
    self.layoutType = config.layoutType or UILayout.VERTICAL
    
    -- Padding (space between viewport edge and content)
    self.padding = config.padding or 10
    
    -- Gap (space between items)
    self.gap = config.gap or 8
    
    -- Items in this layout
    self.items = {}
    
    -- Scroll offset
    self.scrollOffset = 0
    self.maxScroll = 0
    
    -- Content size (calculated)
    self.contentWidth = 0
    self.contentHeight = 0
    
    return self
end

--[[
================================================================================
  ITEM MANAGEMENT
================================================================================
--]]

-- Add an item to the layout
-- item = { width, height, draw = function(x, y, w, h) }
function UILayout:addItem(item)
    table.insert(self.items, {
        width = item.width or 100,
        height = item.height or 50,
        draw = item.draw or function() end,
        data = item.data  -- Optional user data
    })
    self:calculateLayout()
end

-- Clear all items
function UILayout:clear()
    self.items = {}
    self.contentWidth = 0
    self.contentHeight = 0
    self.scrollOffset = 0
end

--[[
================================================================================
  LAYOUT CALCULATION
================================================================================
--]]

function UILayout:calculateLayout()
    if self.layoutType == UILayout.VERTICAL then
        self:calculateVerticalLayout()
    else
        self:calculateHorizontalLayout()
    end
end

-- Vertical layout: items stack top to bottom
function UILayout:calculateVerticalLayout()
    local currentY = self.padding
    local maxWidth = 0
    
    for i, item in ipairs(self.items) do
        -- Position
        item._x = self.padding
        item._y = currentY
        
        -- Track max width
        if item.width > maxWidth then
            maxWidth = item.width
        end
        
        -- Move to next position
        currentY = currentY + item.height + self.gap
    end
    
    -- Content size
    self.contentWidth = maxWidth + self.padding * 2
    self.contentHeight = currentY - self.gap + self.padding
    
    -- Max scroll
    self.maxScroll = math.max(0, self.contentHeight - self.viewport.height)
end

-- Horizontal layout: items stack left to right
function UILayout:calculateHorizontalLayout()
    local currentX = self.padding
    local maxHeight = 0
    
    for i, item in ipairs(self.items) do
        -- Position
        item._x = currentX
        item._y = self.padding
        
        -- Track max height
        if item.height > maxHeight then
            maxHeight = item.height
        end
        
        -- Move to next position
        currentX = currentX + item.width + self.gap
    end
    
    -- Content size
    self.contentWidth = currentX - self.gap + self.padding
    self.contentHeight = maxHeight + self.padding * 2
    
    -- Max scroll (horizontal)
    self.maxScroll = math.max(0, self.contentWidth - self.viewport.width)
end

--[[
================================================================================
  VIEWPORT AUTO-RESIZE
================================================================================
--]]

-- Resize viewport to fit content
function UILayout:fitToContent()
    self.viewport.width = self.contentWidth
    self.viewport.height = self.contentHeight
end

-- Resize viewport width to fit content (keep height)
function UILayout:fitWidthToContent()
    self.viewport.width = self.contentWidth
end

-- Resize viewport height to fit content (keep width)
function UILayout:fitHeightToContent()
    self.viewport.height = self.contentHeight
end

--[[
================================================================================
  SCROLLING
================================================================================
--]]

function UILayout:scroll(delta)
    self.scrollOffset = self.scrollOffset + delta
    
    -- Clamp
    if self.scrollOffset < 0 then
        self.scrollOffset = 0
    elseif self.scrollOffset > self.maxScroll then
        self.scrollOffset = self.maxScroll
    end
end

function UILayout:setScroll(offset)
    self.scrollOffset = math.max(0, math.min(offset, self.maxScroll))
end

function UILayout:getScrollPercent()
    if self.maxScroll <= 0 then return 0 end
    return self.scrollOffset / self.maxScroll
end

--[[
================================================================================
  CLIPPING HELPERS
================================================================================
--]]

-- Check if a rectangle is visible in viewport
function UILayout:isVisible(x, y, w, h)
    local vp = self.viewport
    local scrollY = (self.layoutType == UILayout.VERTICAL) and self.scrollOffset or 0
    local scrollX = (self.layoutType == UILayout.HORIZONTAL) and self.scrollOffset or 0
    
    local itemTop = y - scrollY
    local itemBottom = itemTop + h
    local itemLeft = x - scrollX
    local itemRight = itemLeft + w
    
    -- Check if item overlaps with viewport
    return itemRight > 0 and itemLeft < vp.width and
           itemBottom > 0 and itemTop < vp.height
end

-- Get clipped rectangle (portion visible in viewport)
function UILayout:getClippedRect(x, y, w, h)
    local vp = self.viewport
    local scrollY = (self.layoutType == UILayout.VERTICAL) and self.scrollOffset or 0
    local scrollX = (self.layoutType == UILayout.HORIZONTAL) and self.scrollOffset or 0
    
    local screenX = vp.x + x - scrollX
    local screenY = vp.y + y - scrollY
    
    -- Clip to viewport
    local clipLeft = math.max(screenX, vp.x)
    local clipTop = math.max(screenY, vp.y)
    local clipRight = math.min(screenX + w, vp.x + vp.width)
    local clipBottom = math.min(screenY + h, vp.y + vp.height)
    
    local clipWidth = clipRight - clipLeft
    local clipHeight = clipBottom - clipTop
    
    if clipWidth <= 0 or clipHeight <= 0 then
        return nil  -- Completely outside viewport
    end
    
    return {
        x = clipLeft,
        y = clipTop,
        width = clipWidth,
        height = clipHeight,
        -- Offset from original (for partial draws)
        offsetX = clipLeft - screenX,
        offsetY = clipTop - screenY
    }
end

--[[
================================================================================
  DRAWING
================================================================================
--]]

function UILayout:draw()
    local vp = self.viewport
    local scrollY = (self.layoutType == UILayout.VERTICAL) and self.scrollOffset or 0
    local scrollX = (self.layoutType == UILayout.HORIZONTAL) and self.scrollOffset or 0
    
    -- Draw each visible item
    for i, item in ipairs(self.items) do
        if self:isVisible(item._x, item._y, item.width, item.height) then
            -- Calculate screen position
            local screenX = vp.x + item._x - scrollX
            local screenY = vp.y + item._y - scrollY
            
            -- Call item's draw function
            item.draw(screenX, screenY, item.width, item.height, item.data)
        end
    end
end

-- Draw with background and border
function UILayout:drawWithFrame(bgColor, borderColor)
    local vp = self.viewport
    
    -- Background
    if bgColor then
        SetDrawColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 1)
        DrawImage(nil, vp.x, vp.y, vp.width, vp.height)
    end
    
    -- Draw items
    self:draw()
    
    -- Border
    if borderColor then
        SetDrawColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
        DrawImage(nil, vp.x, vp.y, vp.width, 1)  -- Top
        DrawImage(nil, vp.x, vp.y + vp.height - 1, vp.width, 1)  -- Bottom
        DrawImage(nil, vp.x, vp.y, 1, vp.height)  -- Left
        DrawImage(nil, vp.x + vp.width - 1, vp.y, 1, vp.height)  -- Right
    end
end

--[[
================================================================================
  HIT DETECTION
================================================================================
--]]

-- Get item at screen position
function UILayout:getItemAt(screenX, screenY)
    local vp = self.viewport
    
    -- Check if in viewport
    if screenX < vp.x or screenX >= vp.x + vp.width or
       screenY < vp.y or screenY >= vp.y + vp.height then
        return nil
    end
    
    local scrollY = (self.layoutType == UILayout.VERTICAL) and self.scrollOffset or 0
    local scrollX = (self.layoutType == UILayout.HORIZONTAL) and self.scrollOffset or 0
    
    -- Convert to content coordinates
    local contentX = screenX - vp.x + scrollX
    local contentY = screenY - vp.y + scrollY
    
    -- Find item
    for i, item in ipairs(self.items) do
        if contentX >= item._x and contentX < item._x + item.width and
           contentY >= item._y and contentY < item._y + item.height then
            return i, item
        end
    end
    
    return nil
end

--[[
================================================================================
  UTILITY FUNCTIONS
================================================================================
--]]

-- Set viewport position
function UILayout:setPosition(x, y)
    self.viewport.x = x
    self.viewport.y = y
end

-- Set viewport size
function UILayout:setSize(width, height)
    self.viewport.width = width
    self.viewport.height = height
    self:calculateLayout()  -- Recalculate max scroll
end

-- Get content size
function UILayout:getContentSize()
    return self.contentWidth, self.contentHeight
end

-- Check if content is larger than viewport (needs scrolling)
function UILayout:needsScroll()
    if self.layoutType == UILayout.VERTICAL then
        return self.contentHeight > self.viewport.height
    else
        return self.contentWidth > self.viewport.width
    end
end

--[[
================================================================================
  SKILL TREE LAYOUT HELPER
================================================================================

This is a specialized helper for skill tree layouts.
It creates a vertical layout with header + tree for each skill.

Usage:
    local skillLayout = UILayout.createSkillTreeLayout(viewport, skills, drawTreeFunc)
    skillLayout:draw()
--]]

function UILayout.createSkillTreeLayout(viewport, skills, drawTreeFunc, config)
    config = config or {}
    
    local layout = UILayout.new({
        x = viewport.x,
        y = viewport.y,
        width = viewport.width,
        height = viewport.height,
        layoutType = UILayout.VERTICAL,
        padding = config.padding or 10,
        gap = config.gap or 8
    })
    
    local headerHeight = config.headerHeight or 36
    local treeHeight = config.treeHeight or 350
    
    for i, skill in ipairs(skills) do
        -- Add combined header + tree as one item
        layout:addItem({
            width = viewport.width - layout.padding * 2,
            height = headerHeight + treeHeight,
            data = {
                index = i,
                skill = skill,
                headerHeight = headerHeight,
                treeHeight = treeHeight
            },
            draw = function(x, y, w, h, data)
                local hh = data.headerHeight
                local th = data.treeHeight
                
                -- Draw header
                SetDrawColor(0.10, 0.10, 0.12)
                DrawImage(nil, x, y, w, hh)
                SetDrawColor(0.30, 0.30, 0.35)
                DrawImage(nil, x, y, w, 1)
                DrawImage(nil, x, y + hh - 1, w, 1)
                DrawImage(nil, x, y, 1, hh)
                DrawImage(nil, x + w - 1, y, 1, hh)
                
                -- Skill name
                SetDrawColor(1, 0.85, 0.4)
                DrawString(x + 10, y + 8, "LEFT", 14, "VAR BOLD", data.skill.name or "Skill " .. data.index)
                
                -- Draw tree background
                local treeY = y + hh
                SetDrawColor(0.04, 0.04, 0.05)
                DrawImage(nil, x, treeY, w, th)
                SetDrawColor(0.20, 0.20, 0.25)
                DrawImage(nil, x, treeY + th - 1, w, 1)
                DrawImage(nil, x, treeY, 1, th)
                DrawImage(nil, x + w - 1, treeY, 1, th)
                
                -- Call custom tree draw function
                if drawTreeFunc then
                    local treeViewport = {
                        x = x,
                        y = treeY,
                        width = w,
                        height = th
                    }
                    drawTreeFunc(treeViewport, data.index, data.skill)
                end
            end
        })
    end
    
    return layout
end

return UILayout
