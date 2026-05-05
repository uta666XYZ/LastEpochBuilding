-- @leb-regression-guard: idol-altar-capacity-tooltip
-- Locks the contract that the Idol Altar item tooltip carries an
-- "Omen Idol capacity: N" line sourced from
-- IDOL_ALTAR_LAYOUTS[baseName].omenIdolCapacity. This is the base
-- capacity (no live sealed-affix bonuses) and matches the in-game
-- header rendered on Idol Altar bases.
-- See REGRESSION_GUARDS.md "idol-altar-capacity-tooltip".

describe("IdolAltarTooltip", function()
    local function captureTooltipLines(itemsTab, item)
        local lines = {}
        local fakeTooltip = {
            AddLine     = function(self, h, text) lines[#lines + 1] = text or "" end,
            AddSeparator = function() end,
            AddImage    = function() end,
            Clear       = function() end,
            center      = false,
            color       = nil,
        }
        itemsTab:AddItemTooltip(fakeTooltip, item, nil, true)
        return lines
    end

    local function findCapacityLine(lines)
        for _, line in ipairs(lines) do
            local n = line:match("Omen Idol capacity: %^?[xX]?%w*(%d+)")
                or line:match("Omen Idol capacity: (%d+)")
            if n then return tonumber(n) end
        end
        return nil
    end

    it("Archaic Altar tooltip shows base capacity 1", function()
        newBuild()
        build.itemsTab:CreateDisplayItemFromRaw([[Rarity: RARE
Test Archaic Altar
Archaic Altar
Unique ID: 100
LevelReq: 50
Implicits: 0]])
        local item = build.itemsTab.displayItem
        local lines = captureTooltipLines(build.itemsTab, item)
        assert.are.equals(1, findCapacityLine(lines))
    end)

    it("tooltip omits capacity line when baseName is unknown to layout", function()
        newBuild()
        -- Construct a fake item with type=Idol Altar but a baseName not in
        -- IDOL_ALTAR_LAYOUTS — should not crash and should not emit a line.
        local item = {
            type = "Idol Altar",
            baseName = "Nonexistent Altar 9999",
            base = { type = "Idol Altar" },
            title = "Fake",
            namePrefix = "",
            nameSuffix = "",
            rarity = "NORMAL",
            implicitModLines = {},
            explicitModLines = {},
            requirements = {},
            modList = {},
            buffModList = {},
            grantedSkills = {},
            sockets = {},
        }
        local lines = captureTooltipLines(build.itemsTab, item)
        assert.is_nil(findCapacityLine(lines))
    end)
end)
