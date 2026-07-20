-- @leb-regression-guard: build-output-wipes-global-cache
-- Locks the contract that CalcsTab:BuildOutput() starts from a CLEAN GlobalCache,
-- so a build's output never depends on what build was calculated before it.
--
-- GlobalCache.cachedData is keyed by cacheSkillUUID (Common.lua), which is
-- build-AGNOSTIC: for a skill with a socket group it is
-- "<skillName>_<slot>_<groupIdx>", and for a skill without one it is just the
-- skill name. No build identity is encoded. The interactive app keeps this safe
-- by wiping the cache on every rebuild (Build.lua buildFlag path). But the
-- snapshot harness (spec/System/TestBuilds_spec.lua) and the snapshot generator
-- (GenerateBuilds14.lua socket-group cycling) call BuildOutput directly and so
-- bypassed that wipe. Stale entries from a previous build then leaked in:
-- <private build>'s Frailty enemy-damage debuff read another build's cached MaxStacks,
-- dropping its TotalEHP 18053 -> 15852 depending on suite load order -- an
-- order-dependent flake across ~45 EHP / damage-taken keys.
--
-- BuildOutput now calls wipeGlobalCache() at its start, making each build
-- self-contained. See REGRESSION_GUARDS.md > "build-output-wipes-global-cache".

describe("BuildOutputCacheIsolation", function()
    before_each(function()
        newBuild()
    end)

    it("BuildOutput wipes stale cross-build GlobalCache entries before computing", function()
        -- Simulate a previous build having populated the global cache with an
        -- entry whose UUID would collide with / leak into another build.
        local sentinel = "__cross_build_sentinel__"
        for _, mode in ipairs({ "MAIN", "CALCS", "CALCULATOR", "CACHE" }) do
            GlobalCache.cachedData[mode][sentinel] = { Name = "stale", leaked = true }
        end

        build.calcsTab:BuildOutput()

        for _, mode in ipairs({ "MAIN", "CALCS", "CALCULATOR", "CACHE" }) do
            assert.is_nil(GlobalCache.cachedData[mode][sentinel],
                "BuildOutput must wipe stale GlobalCache['" .. mode .. "'] entries from a prior build")
        end
    end)
end)
