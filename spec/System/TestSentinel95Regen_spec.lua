-- @leb-regression-guard: sentinel-95-base-health-regen
-- Locks the contract that Paladin tree node Sentinel-95 (Covenant of
-- Protection) grants `+6 Health Regen` per allocated point in addition to
-- its armor stats. The LE node's internal name is
-- "Paladin Armor Health Regen And Armor Applies To DoT" (verified via
-- LE_datamining/extracted/items/globalTreeData.json).
--
-- Pre-fix tree_2.json (1_4) listed only the armor stats, so 5 allocated
-- points dropped +30 BASE Health Regen entirely; QDxZjL4J Paladin's
-- LETools snapshot showed +30 BASE Health Regen from this node.
--
-- See REGRESSION_GUARDS.md for the index entry.

describe("Sentinel95BaseHealthRegen", function()
    it("tree_2.json Sentinel-95 stats include '+6 Health Regen'", function()
        -- busted runs with cwd = src/ (.busted config); fall back to repo root.
        local f = io.open("TreeData/1_4/tree_2.json", "r")
            or io.open("src/TreeData/1_4/tree_2.json", "r")
        assert.is_not_nil(f, "tree_2.json missing")
        local raw = f:read("*a")
        f:close()
        -- Locate the Sentinel-95 block and its stats array.
        local block = raw:match('"Sentinel%-95"%s*:%s*{(.-)}%s*,%s*"Sentinel%-96"')
        assert.is_not_nil(block, "Sentinel-95 block not found")
        assert.is_truthy(block:find('"%+6 Health Regen"', 1, false),
            "Sentinel-95 stats must contain '+6 Health Regen'")
        assert.is_truthy(block:find('"8%% Increased Armor"', 1, false),
            "Sentinel-95 stats must retain '8% Increased Armor'")
    end)
end)
