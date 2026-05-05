-- @leb-regression-guard: tooltip-mod-line-wrap
-- Locks the contract that long mod lines feeding through Tooltip:AddLine
-- (the path used by ItemsTab:AddItemTooltip) are word-wrapped to stay inside
-- the tooltip's maxWidth, so unique mod text such as Horn of the Bone Wisp's
-- "48% chance to cast Flame Ward after using a movement skill within 16
-- metres of a boss or rare enemy (max 2 per 16 seconds)" does not overflow
-- the tooltip box horizontally.

describe("TooltipWrap", function()
    it("AddLine wraps a long line at maxWidth into multiple visual rows", function()
        -- Override the headless DrawStringWidth (which always returns 1) with
        -- a char-count based stub so WrapString can actually decide to wrap.
        local origDSW = _G.DrawStringWidth
        _G.DrawStringWidth = function(_, _, text)
            return #(text or "")
        end

        local tooltip = new("Tooltip")
        tooltip.maxWidth = 60 -- 60 - H_PAD(12) = 48 char budget per line

        local longText = "48% chance to cast Flame Ward after using a movement skill within 16 metres of a boss or rare enemy (max 2 per 16 seconds)"
        tooltip:AddLine(16, longText)

        _G.DrawStringWidth = origDSW

        -- The single AddLine call should have produced strictly more than one
        -- visual line entry once wrapping kicks in.
        local n = 0
        for _, l in ipairs(tooltip.lines) do
            if l.text then n = n + 1 end
        end
        assert.is_true(n > 1, "expected long mod line to wrap into >1 visual rows, got " .. n)

        -- Block height must reflect every wrapped row (not just the source line)
        -- so the bottom tooltip border doesn't crop wrapped content.
        assert.is_true(tooltip.blocks[#tooltip.blocks].height >= (16 + 2) * n,
            "block height should account for every wrapped row")
    end)

    it("AddItemTooltip sets a default maxWidth so item tooltips wrap on hover", function()
        newBuild()
        local item = new("Item", [[Rarity: UNIQUE
Wrap Test Item
Ivory Wand
Unique ID: 9001
Implicits: 0
48% chance to cast Flame Ward after using a movement skill within 16 metres of a boss or rare enemy (max 2 per 16 seconds)]])

        local tooltip = new("Tooltip")
        -- Simulates hover-tooltip path (TooltipHost), which used to leave
        -- maxWidth unset and let long mod lines overflow.
        assert.is_nil(tooltip.maxWidth)
        build.itemsTab:AddItemTooltip(tooltip, item, nil, true)
        assert.is_truthy(tooltip.maxWidth, "AddItemTooltip should set a default maxWidth")
    end)
end)
