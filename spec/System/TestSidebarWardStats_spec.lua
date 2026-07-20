-- @leb-regression-guard: sidebar-ward-stat-removal
-- Locks the Build.lua sidebar `displayStats` list to NOT include the raw
-- `Ward` row. It was intentionally removed in favor of `StableWard`,
-- which exposes the same information without confusing users.
--
-- `NetWardRegen` was originally also removed, but was reintroduced by
-- <see git log> to sit directly under `StableWard` as part of the Ward
-- recovery grouping. The guard tracks only the raw `Ward` row now.
--
-- 2026-06-10 (user-requested): the NetWardRegen row HIDES when the displayed
-- value would round to +0.0 (fmt +.1f -> |v| < 0.05). Net Ward Recovery =
-- ward gain/s - decay/s, which is ~0 by construction at the stable-ward
-- equilibrium (and exactly 0 with no per-second ward generation), so a "+0.0"
-- row carries no information -- mirroring how the Mana Regen row hides at 0.
-- A real net drift (ward ramping/bleeding) still shows.
--
-- See REGRESSION_GUARDS.md "sidebar-ward-stat-removal".

local OptionalArtifact = dofile("../spec/OptionalArtifact.lua")
local buildsIt = OptionalArtifact.gatedIt(it, pending, "spec/TestBuilds")

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

    it("the NetWardRegen row hides when the displayed value rounds to +0.0", function()
        local f = io.open("Modules/Build.lua", "r") or io.open("src/Modules/Build.lua", "r")
        assert.is_not_nil(f, "must be able to open Modules/Build.lua")
        local text = f:read("*a")
        f:close()
        local rowAt = string.find(text, 'stat = "NetWardRegen"', 1, true)
        assert.is_not_nil(rowAt, "NetWardRegen row must exist (reintroduced by a60057c1e)")
        local rowEnd = string.find(text, "\n", rowAt)
        local row = string.sub(text, rowAt, rowEnd or #text)
        -- the display-threshold gate: hide when |v| < 0.05 (fmt +.1f rounds to +0.0)
        assert.is_truthy(string.find(row, "v >= 0.05 or v <= -0.05", 1, true),
            "NetWardRegen row must gate on the +.1f display threshold (|v| < 0.05 hides)")
    end)

    -- Validation provenance is retained in maintainer notes.
    buildsIt("TestBuilds snapshots reflect the removal (no Ward PlayerStat lines)", function()
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
