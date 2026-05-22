-- @leb-regression-guard: sidebar-ward-stat-removal
-- Locks the Build.lua sidebar `displayStats` list to NOT include the raw
-- `Ward` row. It was intentionally removed in favor of `StableWard`,
-- which exposes the same information without confusing users.
--
-- `NetWardRegen` was originally also removed, but was reintroduced by
-- a60057c1e to sit directly under `StableWard` as part of the Ward
-- recovery grouping. The guard tracks only the raw `Ward` row now.
--
-- See REGRESSION_GUARDS.md "sidebar-ward-stat-removal".

describe("SidebarWardStatRemoval", function()
    it("Build.lua sidebar displayStats does not declare stat=\"Ward\"", function()
        local f = io.open("Modules/Build.lua", "r") or io.open("src/Modules/Build.lua", "r")
        assert.is_not_nil(f, "must be able to open Modules/Build.lua")
        local text = f:read("*a")
        f:close()
        -- Match exactly the row form: `{ stat = "Ward",`
        -- StableWard, NetWardRegen, and other ward-prefixed stats are allowed.
        assert.is_falsy(string.find(text, '{ stat = "Ward"', 1, true),
            "Build.lua must NOT re-add a sidebar row for raw stat=\"Ward\"")
    end)

    it("TestBuilds snapshots reflect the removal (no Ward PlayerStat lines)", function()
        local snapshots = {
            "BjqdaPzE lv99 Sorcerer.xml",
            "o3Zlpkxd lv98 Necromancer.xml",
        }
        for _, name in ipairs(snapshots) do
            local p1 = "../spec/TestBuilds/1.4/" .. name
            local p2 = "spec/TestBuilds/1.4/" .. name
            local f = io.open(p1, "r") or io.open(p2, "r")
            assert.is_not_nil(f, "must be able to open " .. name)
            local text = f:read("*a")
            f:close()
            assert.is_falsy(string.find(text, 'stat="Ward"', 1, true),
                name .. " must not contain a Ward PlayerStat after removal")
        end
    end)
end)
