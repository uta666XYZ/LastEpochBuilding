-- @leb-regression-guard:tree-rank-per-stat-divisor
-- Locks that PassiveTree rank-scaling multiplies LEADING values by node.alloc
-- but NEVER scales divisors inside "per N <attr>" clauses.
--
-- Bug pre-fix: PassiveTree.lua used `stat:gsub("(%d[%d.]*)", value * node.alloc)`
-- which scaled EVERY number in the stat string. For Mage-51 "Prodigy"
-- ("+3 Ward Per Second Per 15 Intelligence", rank 5) the divisor 15 became 75,
-- so the parsed mod ended up as `BASE 15, PerStat Int div=75` instead of
-- `BASE 15, PerStat Int div=15` — a 5x under-count of the contribution.
--
-- Same protection applies to any "per N <anything>" tail (e.g. "per 10 stacks").
--
-- Establishing build: BgRrekaR lv100 Spellblade
--   pre-fix  WardPerSecond=182 (LE 323, Δ=-141; Mage-51 Prodigy under-counted ~122)
--   post-fix WardPerSecond=304 (LE 323, Δ=-19;  residual is fw3d-14 Energize etc, separate)
--
-- See REGRESSION_GUARDS.md > tree-rank-per-stat-divisor.

describe("TreeRankPerStatDivisor", function()

    describe("PassiveTree.lua rank-scaling source", function()
        local source
        setup(function()
            local f = io.open("Classes/PassiveTree.lua", "r")
            assert.is_not_nil(f, "must be able to open Classes/PassiveTree.lua")
            source = f:read("*a")
            f:close()
        end)

        it("regression-guard comment is present", function()
            assert.is_truthy(string.find(source, "tree%-rank%-per%-stat%-divisor"),
                "PassiveTree.lua must keep the @leb-regression-guard comment")
        end)

        it("rank-scaling protects 'per N <attr>' divisors via [Pp]er pattern split", function()
            -- The fix splits stat strings around `[Pp]er%s+%d[%d.]*` and applies
            -- gsub scaling only to the segment BEFORE the "per N ..." clause.
            -- A naive single gsub over `(%d[%d.]*)` would scale the divisor too,
            -- which is the bug we're locking against.
            assert.is_truthy(string.find(source, '%[Pp%]er%%s%+%%d%[%%d%.%]%*', 1),
                "rank-scaling must use a split that anchors on '[Pp]er%s+%d[%d.]*' "
                .. "so divisors stay un-scaled")
        end)

        it("does NOT apply a bare `stat:gsub(\"(%d[%d.]*)\", value * node.alloc)` over the whole string", function()
            -- The naive single-pass gsub is the original bug. Catching it requires
            -- ensuring the gsub is only applied piecewise (via a local helper) or
            -- guarded by the "per N" split.
            local bad = 'stat = stat:gsub%("%(%%d%[%%d%%.%]%*%)"'
            assert.is_falsy(string.find(source, bad),
                "the naive whole-string gsub form must be removed; rank scaling "
                .. "must run on the non-divisor segments only")
        end)
    end)

    describe("parser still returns div=N for the post-rank text", function()
        -- After the fix, a rank-5 "+3 Ward Per Second Per 15 Intelligence" becomes
        -- "+15 Ward Per Second Per 15 Intelligence". The parser must produce
        -- BASE 15 with PerStat Int div=15 (matching the in-game text).
        it("'+15 Ward Per Second Per 15 Intelligence' parses to PerStat Int div=15", function()
            local mods, extra = modLib.parseMod("+15 Ward Per Second Per 15 Intelligence")
            assert.is_nil(extra, "must have no unparsed leftover")
            assert.is_not_nil(mods, "must carry a parsed mod")
            local m = mods[1]
            assert.are.equals("WardPerSecond", m.name)
            assert.are.equals("BASE", m.type)
            assert.are.equals(15, m.value)
            assert.are.equals("PerStat", m[1].type)
            assert.are.equals("Int", m[1].stat)
            assert.are.equals(15, m[1].div,
                "divisor must be 15 (the in-game 'per 15 Int'), not rank-scaled")
        end)

        -- And just to lock the contrast: if the bug were to come back, the parsed
        -- mod would carry div=75 (rank-scaled divisor) and the contribution from
        -- a 152-Int build would be 15*152/75 = 30.4 instead of the expected 152.
        it("'+15 Ward Per Second Per 75 Intelligence' (bugged form) parses to div=75", function()
            local mods, extra = modLib.parseMod("+15 Ward Per Second Per 75 Intelligence")
            assert.is_nil(extra)
            local m = mods[1]
            assert.are.equals(75, m[1].div,
                "sanity check: the bugged input does parse to div=75, "
                .. "which is what motivates the rank-scaler fix")
        end)
    end)
end)
