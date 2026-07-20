-- @leb-regression-guard: idol-tooltip-game-presentation
-- Locks the in-game presentation of class-specific empowered idols: the
-- second header line is the localized class/base type and no separate
-- "Exalted Item" rarity line is shown.

describe("IdolTooltipPresentation", function()
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

    it("shows the Primalist idol type and omits the Exalted Item line", function()
        local item
        local lines
        local heights
        newBuild()
        item = new("Item", [[Rarity: EXALTED
Empowered Heretical Ornate Heorot Idol of the Tempest
Heretical Ornate Heorot Idol
Unique ID: 9002
Implicits: 0]])
        lines, heights = captureTooltipLines(item)

        assert.are.equals(colorCodes.IDOL .. "Primalist Ornate Idol", lines[2])
        assert.are.equals(16, heights[2])
        for _, line in ipairs(lines) do
            assert.is_nil(line:find("Exalted Item", 1, true))
        end
    end)

    it("keeps the Exalted Item line for non-idols", function()
        local item
        local lines
        local found
        newBuild()
        item = new("Item", [[Rarity: EXALTED
Exalted Wand
Ivory Wand
Unique ID: 9003
Implicits: 0]])
        lines = captureTooltipLines(item)

        for _, line in ipairs(lines) do
            if line:find("Exalted Item", 1, true) then
                found = true
            end
        end
        assert.is_true(found)
    end)
end)
