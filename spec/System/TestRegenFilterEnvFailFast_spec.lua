-- @leb-regression-guard: regen-filter-env-fail-fast
-- Locks the contract in spec/RegenFilterEnv.lua: a regen filter env var that is
-- SET but unusable must error(), never fall back to "no filter". The fallback is
-- silent and expensive -- it turns a scoped regen of a few builds into a
-- full-corpus regen of 639 (hours), with the same exit status. See the module
-- header for the two incidents (unreadable /tmp path; a build NAME passed where a
-- FILE path was expected, 2026-07-16).
--
-- Establishing reference: see git log

describe("RegenFilterEnv fail-fast", function()
    local RegenFilterEnv = dofile("../spec/RegenFilterEnv.lua")

    local tmpDir = "../.tmp"
    local written = {}

    local function writeTmp(name, contents)
        lfs.mkdir(tmpDir)
        local path = tmpDir .. "/regenfilterenv_spec_" .. name
        local f = assert(io.open(path, "w+"), "cannot write " .. path)
        f:write(contents)
        f:close()
        table.insert(written, path)
        return path
    end

    teardown(function()
        for _, path in ipairs(written) do os.remove(path) end
    end)

    describe("LEB_ONLY_LIST", function()
        it("errors when set to a path that cannot be opened", function()
            -- The 2026-07-16 shape: a build NAME handed over as if it were a path.
            local ok, err = pcall(RegenFilterEnv.loadOnlyList, "1.4/Qqwv73q2 lv100 Warlock")
            assert.is_false(ok)
            assert.is_truthy(tostring(err):find("LEB_ONLY_LIST", 1, true))
            assert.is_truthy(tostring(err):find("full-corpus regen", 1, true))
        end)

        it("errors when the file exists but has no non-blank lines", function()
            local path = writeTmp("empty.txt", "\n   \n\n")
            local ok, err = pcall(RegenFilterEnv.loadOnlyList, path)
            assert.is_false(ok)
            assert.is_truthy(tostring(err):find("no non-blank lines", 1, true))
        end)

        it("returns nil (no filter) when unset -- the normal path", function()
            assert.is_nil(RegenFilterEnv.loadOnlyList(""))
            assert.is_nil(RegenFilterEnv.loadOnlyList(nil))
        end)

        it("loads trimmed, CR-LF-tolerant substrings from a real file", function()
            local path = writeTmp("list.txt", "Warlock\r\n  Beastmaster  \n\nFalconer\n")
            local list = RegenFilterEnv.loadOnlyList(path)
            assert.are.same({ "Warlock", "Beastmaster", "Falconer" }, list)
        end)
    end)

    describe("LEB_ONLY_FILE", function()
        it("errors when set to a path that cannot be opened", function()
            local ok, err = pcall(RegenFilterEnv.loadOnlyFile, "no/such/affected-builds.txt")
            assert.is_false(ok)
            assert.is_truthy(tostring(err):find("LEB_ONLY_FILE", 1, true))
            assert.is_truthy(tostring(err):find("full-corpus regen", 1, true))
        end)

        it("errors when the file is blank/comment-only", function()
            local path = writeTmp("comments.txt", "# only a comment\n\n")
            local ok, err = pcall(RegenFilterEnv.loadOnlyFile, path)
            assert.is_false(ok)
            assert.is_truthy(tostring(err):find("no build paths", 1, true))
        end)

        it("returns nil (no filter) when unset", function()
            assert.is_nil(RegenFilterEnv.loadOnlyFile(""))
        end)

        it("builds a suffix set, skipping comments", function()
            local path = writeTmp("paths.txt", "# affected\r\nspec/TestBuilds/1.4/A.xml\nspec/TestBuilds/1.4/B.xml\n")
            local set, count = RegenFilterEnv.loadOnlyFile(path)
            assert.are.equal(2, count)
            assert.is_true(set["spec/TestBuilds/1.4/A.xml"])
            assert.is_true(set["spec/TestBuilds/1.4/B.xml"])
        end)
    end)

    describe("LEB_SHARD", function()
        it("returns 0/1 when unset -- the normal path", function()
            local i, n = RegenFilterEnv.parseShard("")
            assert.are.equal(0, i)
            assert.are.equal(1, n)
        end)

        it("parses a well-formed i/N", function()
            local i, n = RegenFilterEnv.parseShard("2/4")
            assert.are.equal(2, i)
            assert.are.equal(4, n)
        end)

        -- Each of these used to degrade to 0/1 == the whole corpus.
        for _, bad in ipairs({ "1 of 4", "1/", "/4", "1/4/2", "one/four", "-1/4" }) do
            it('errors on malformed LEB_SHARD="' .. bad .. '" instead of falling back to 0/1', function()
                local ok, err = pcall(RegenFilterEnv.parseShard, bad)
                assert.is_false(ok)
                assert.is_truthy(tostring(err):find("malformed", 1, true))
            end)
        end

        it("errors on N=0 rather than dividing by zero", function()
            local ok = pcall(RegenFilterEnv.parseShard, "0/0")
            assert.is_false(ok)
        end)

        it("errors when i >= N (a shard that matches nothing)", function()
            local ok, err = pcall(RegenFilterEnv.parseShard, "4/4")
            assert.is_false(ok)
            assert.is_truthy(tostring(err):find("must be < N", 1, true))
        end)
    end)

    describe("LEB_ROOT / corpus discovery", function()
        it("errors when fetchBuilds returned nil", function()
            local ok, err = pcall(RegenFilterEnv.assertBuildsFound, nil, "../spec/TestBuilds/1.4", "boom")
            assert.is_false(ok)
            assert.is_truthy(tostring(err):find("could not be read", 1, true))
        end)

        it("errors when the root holds no .xml builds", function()
            local ok, err = pcall(RegenFilterEnv.assertBuildsFound, {}, "../spec/TestBuilds/nope")
            assert.is_false(ok)
            assert.is_truthy(tostring(err):find("no .xml builds", 1, true))
        end)

        it("passes a non-empty build list through", function()
            local list = { ["../spec/TestBuilds/1.4/A.xml"] = "<xml/>" }
            assert.are.equal(list, RegenFilterEnv.assertBuildsFound(list, "../spec/TestBuilds/1.4"))
        end)
    end)
end)
