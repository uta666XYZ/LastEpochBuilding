-- @leb-regression-guard: corpus-build-key-is-path-not-basename
-- @leb-regression-guard: regen-root-equals-test-root
-- Locks the two contracts in spec/CorpusScope.lua that decide how much of the corpus
-- actually gets tested and regenerated:
--   1. builds are identified by PATH, so the 6 same-named-but-different pairs in
--      1.4/ vs 1.4/bin/ are both enumerated (basename keying silently dropped one of
--      each -- 6 builds never tested, and the suite still reported success);
--   2. the DEFAULT regen root is the same tree the corpus test walks (a version-pinned
--      default left the 5 builds outside 1.4/ tested but unreachable by any regen).
--
-- Both failures are invisible by construction -- a build that is never enumerated
-- cannot fail, and a build that is never regenerated just goes quietly stale -- so
-- there is no natural red to notice. These assertions are the only red.
--
-- Runs on a SYNTHETIC fixture tree, not the real corpus: spec/TestBuilds/ is gitignored
-- and absent from every worktree and CI checkout (see `optional-artifact-pending-not-silent`),
-- and a guard that no-ops wherever the artifact is missing is not a guard.
--
-- Establishing reference: see git log

describe("CorpusScope", function()
    local CorpusScope = dofile("../spec/CorpusScope.lua")

    local fixture = "../.tmp/corpusscope_spec"

    local function write(path, text)
        local f = assert(io.open(path, "w+"), "cannot write " .. path)
        f:write(text)
        f:close()
    end

    -- Mirrors the real shape: a duplicate basename across a directory and its subdirectory.
    setup(function()
        lfs.mkdir("../.tmp")
        lfs.mkdir(fixture)
        lfs.mkdir(fixture .. "/1.4")
        lfs.mkdir(fixture .. "/1.4/bin")
        write(fixture .. "/1.4/Dup lv84 VK.lua", "return {}")
        write(fixture .. "/1.4/bin/Dup lv84 VK.lua", "return {}")
        write(fixture .. "/1.4/Solo lv90 Druid.lua", "return {}")
        write(fixture .. "/1.4/Solo lv90 Druid.xml", "<xml/>")
    end)

    teardown(function()
        os.remove(fixture .. "/1.4/bin/Dup lv84 VK.lua")
        os.remove(fixture .. "/1.4/Dup lv84 VK.lua")
        os.remove(fixture .. "/1.4/Solo lv90 Druid.lua")
        os.remove(fixture .. "/1.4/Solo lv90 Druid.xml")
        lfs.rmdir(fixture .. "/1.4/bin")
        lfs.rmdir(fixture .. "/1.4")
        lfs.rmdir(fixture)
    end)

    describe("listBuildFiles -- identity is the path, not the basename", function()
        it("enumerates BOTH copies of a duplicated basename", function()
            local files = CorpusScope.listBuildFiles(fixture, ".lua")
            assert.are.equal(3, #files)
            local found = {}
            for _, f in ipairs(files) do found[f] = true end
            -- The whole point: these two are different builds that share a name.
            assert.is_true(found[fixture .. "/1.4/Dup lv84 VK.lua"])
            assert.is_true(found[fixture .. "/1.4/bin/Dup lv84 VK.lua"])
        end)

        it("keys a build map by path without collapsing the colliding pair", function()
            -- The exact shape TestBuilds_spec builds. Under the old basename keying
            -- this map had 2 entries, not 3, and which Dup survived depended on walk order.
            local map = {}
            for _, f in ipairs(CorpusScope.listBuildFiles(fixture, ".lua")) do
                map[CorpusScope.buildName(f, fixture)] = true
            end
            local n = 0
            for _ in pairs(map) do n = n + 1 end
            assert.are.equal(3, n)
            assert.is_true(map["1.4/Dup lv84 VK.lua"])
            assert.is_true(map["1.4/bin/Dup lv84 VK.lua"])
        end)

        it("filters by extension", function()
            local xml = CorpusScope.listBuildFiles(fixture, ".xml")
            assert.are.same({ fixture .. "/1.4/Solo lv90 Druid.xml" }, xml)
        end)

        it("returns a sorted array, so enumeration order is deterministic", function()
            local a = CorpusScope.listBuildFiles(fixture, ".lua")
            local b = CorpusScope.listBuildFiles(fixture, ".lua")
            assert.are.same(a, b)
            local sorted = {}
            for _, v in ipairs(a) do table.insert(sorted, v) end
            table.sort(sorted)
            assert.are.same(sorted, a)
        end)
    end)

    describe("buildName", function()
        it("is root-relative, so the colliding pair gets distinct names", function()
            assert.are.equal("1.4/bin/Dup lv84 VK.lua",
                CorpusScope.buildName(fixture .. "/1.4/bin/Dup lv84 VK.lua", fixture))
            assert.are.equal("1.4/Dup lv84 VK.lua",
                CorpusScope.buildName(fixture .. "/1.4/Dup lv84 VK.lua", fixture))
        end)

        it("passes a path outside the root through unchanged", function()
            assert.are.equal("/elsewhere/X.lua", CorpusScope.buildName("/elsewhere/X.lua", fixture))
        end)
    end)

    describe("resolveBuildRoot -- the DEFAULT root is the whole corpus", function()
        it("defaults to CorpusScope.ROOT when LEB_ROOT is unset", function()
            assert.are.equal(CorpusScope.ROOT, CorpusScope.resolveBuildRoot(nil))
            assert.are.equal(CorpusScope.ROOT, CorpusScope.resolveBuildRoot(""))
        end)

        it("honours an explicit override -- narrowing on purpose stays allowed", function()
            -- LEB_ROOT is the supported way to scope a targeted regen; only the
            -- DEFAULT is load-bearing.
            assert.are.equal("../spec/TestBuilds/1.4",
                CorpusScope.resolveBuildRoot("../spec/TestBuilds/1.4"))
        end)

        it("has a ROOT that is not pinned to a game version", function()
            -- `../spec/TestBuilds/1.4` as a DEFAULT is the exact bug: it excludes
            -- 1.2/, 1.3/ and StarSeaVnV_LEB from every regen while the test still
            -- walks them.
            assert.is_nil(CorpusScope.ROOT:match("/%d+%.%d+$"),
                "CorpusScope.ROOT must be the whole corpus tree, not a version subdirectory")
            assert.are.equal("../spec/TestBuilds", CorpusScope.ROOT)
        end)
    end)

    describe("consumers go through CorpusScope rather than a literal", function()
        -- Both files are TRACKED, so this runs everywhere including CI. The gitignored
        -- driver spec/GenerateBuilds14.lua cannot be checked here (absent from every
        -- checkout but the main repo); it takes its root from resolveBuildRoot, which
        -- is why the default lives in tracked code at all.
        local function read(path)
            local f = io.open(path, "r") or io.open("../" .. path, "r")
            assert(f, "cannot read " .. path)
            local text = f:read("*a")
            f:close()
            return text
        end

        for _, path in ipairs({ "spec/System/TestBuilds_spec.lua", "spec/GenerateBuilds.lua" }) do
            it(path .. " roots at CorpusScope.ROOT, not a hardcoded corpus path", function()
                local src = read(path)
                assert.is_truthy(src:find("CorpusScope.ROOT", 1, true),
                    path .. " must take its corpus root from CorpusScope.ROOT")
                -- A literal here is how the two scopes drifted apart in the first place.
                assert.is_nil(src:match('"%.%./spec/TestBuilds[^"]*"'),
                    path .. " hardcodes a corpus root literal; use CorpusScope.ROOT so the "
                    .. "regen scope and the test scope cannot diverge")
            end)
        end
    end)
end)
