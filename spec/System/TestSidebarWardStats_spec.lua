-- @leb-regression-guard: sidebar-ward-stat-removal
-- Locks the Build.lua sidebar `displayStats` list to NOT include the raw
-- `Ward` row or `NetWardRegen` row. They were intentionally removed in
-- favor of StableWard + the Net Recovery breakdown. TestBuilds snapshots
-- (BjqdaPzE Sorcerer, o3Zlpkxd Necromancer) were regenerated after the
-- removal — re-adding either row will silently drift those snapshots.
--
-- See REGRESSION_GUARDS.md "sidebar-ward-stat-removal".

describe("SidebarWardStatRemoval", function()
    it("Build.lua sidebar displayStats does not declare stat=\"Ward\"", function()
        local f = io.open("src/Modules/Build.lua", "r")
        assert.is_not_nil(f, "must be able to open src/Modules/Build.lua")
        local text = f:read("*a")
        f:close()
        -- Match exactly the row form: `{ stat = "Ward",`
        -- StableWard and other ward-prefixed stats must remain allowed.
        assert.is_falsy(string.find(text, '{ stat = "Ward"', 1, true),
            "Build.lua must NOT re-add a sidebar row for raw stat=\"Ward\"")
        assert.is_falsy(string.find(text, '{ stat = "NetWardRegen"', 1, true),
            "Build.lua must NOT re-add a sidebar row for stat=\"NetWardRegen\"")
    end)

    it("TestBuilds snapshots reflect the removal (no Ward / NetWardRegen PlayerStat lines)", function()
        local snapshots = {
            "spec/TestBuilds/1.4/BjqdaPzE lv99 Sorcerer.xml",
            "spec/TestBuilds/1.4/o3Zlpkxd lv98 Necromancer.xml",
        }
        for _, path in ipairs(snapshots) do
            local f = io.open(path, "r")
            assert.is_not_nil(f, "must be able to open " .. path)
            local text = f:read("*a")
            f:close()
            assert.is_falsy(string.find(text, 'stat="Ward"', 1, true),
                path .. " must not contain a Ward PlayerStat after removal")
            assert.is_falsy(string.find(text, 'stat="NetWardRegen"', 1, true),
                path .. " must not contain a NetWardRegen PlayerStat after removal")
        end
    end)
end)
