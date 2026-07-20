-- @leb-regression-guard: tooltip-base-label-font-size
-- Locks the in-game presentation of a titled item's base/sub-type line: the
-- second header line ("Turquoise Ring", "Ivory Wand", ...) renders at height
-- 16, smaller than the height-20 title line above it.

describe("TooltipBaseLabelFontSize", function()
    local function captureTooltipLines(item)
        local lines = {}
        local heights = {}
        local fakeTooltip = {
            AddLine = function(self, h, text)
                lines[#lines + 1] = text or ""
                heights[#heights + 1] = h
            end,
            AddSeparator = function() end,
            AddImage = function() end,
            Clear = function() end,
            center = false,
            color = nil,
        }
        build.itemsTab:AddItemTooltip(fakeTooltip, item, nil, true)
        return lines, heights
    end

    it("renders the base label smaller than the title for a unique item", function()
        local item
        local lines
        local heights
        newBuild()
        item = new("Item", [[Rarity: UNIQUE
Hollow Finger
Turquoise Ring
Unique ID: 9010
Implicits: 0]])
        lines, heights = captureTooltipLines(item)

        -- Line 1 = title (large), Line 2 = base/sub-type label (small).
        assert.are.equals(20, heights[1])
        assert.are.equals(16, heights[2])
        assert.is_not_nil(lines[2]:find("Turquoise Ring", 1, true))
    end)

    it("renders the base label at 16 for an exalted item too", function()
        local item
        local lines
        local heights
        newBuild()
        item = new("Item", [[Rarity: EXALTED
Exalted Wand
Ivory Wand
Unique ID: 9011
Implicits: 0]])
        lines, heights = captureTooltipLines(item)

        assert.are.equals(20, heights[1])
        assert.are.equals(16, heights[2])
        assert.is_not_nil(lines[2]:find("Ivory Wand", 1, true))
    end)
end)
