-- @leb-regression-guard: optional-artifact-pending-not-silent
-- Locks spec/OptionalArtifact.lua's contract: a MISSING DIRECTORY is an environment
-- without the gitignored artifacts (skip, visibly); a missing FILE inside a directory
-- that IS present is a real defect (fail loudly).
--
-- The whole value of this helper is the narrowness of that distinction. A blanket
-- "if the file will not open, skip" would delete the noise AND the coverage: 9 specs
-- would report green in the main repo while asserting nothing, and nobody would notice
-- because green is what they expect. These tests exist to stop that simplification.

local OptionalArtifact = dofile("../spec/OptionalArtifact.lua")

describe("OptionalArtifact", function()
    describe("resolveDir", function()
        it("finds a directory that exists relative to the repo root", function()
            -- spec/ and src/ are tracked, so they are present in every checkout.
            assert.is_not_nil(OptionalArtifact.resolveDir("spec"))
            assert.is_not_nil(OptionalArtifact.resolveDir("src"))
        end)

        it("returns nil for a directory that does not exist", function()
            assert.is_nil(OptionalArtifact.resolveDir("spec/NoSuchDirectory_ZZZ"))
        end)

        it("resolves regardless of whether cwd is src/ or the repo root", function()
            -- busted runs with cwd=src (.busted `directory = "src"`), so a repo-root
            -- relative path only resolves via the "../" retry. If that retry is ever
            -- dropped, every caller silently decides the artifacts are absent and the
            -- whole suite quietly turns pending.
            local resolved = OptionalArtifact.resolveDir("spec")
            assert.is_true(resolved == "spec" or resolved == "../spec")
        end)
    end)

    describe("isPresent", function()
        it("is true for a tracked directory", function()
            assert.is_true(OptionalArtifact.isPresent("spec"))
        end)

        it("is false for an absent directory", function()
            assert.is_false(OptionalArtifact.isPresent("spec/NoSuchDirectory_ZZZ"))
        end)

        it("does not treat a FILE path as a present directory's contents", function()
            -- Guards the intent: presence is about the DIRECTORY. A caller must not be
            -- able to pass a file and have a missing sibling look like a missing dir.
            assert.is_true(OptionalArtifact.isPresent("spec/OptionalArtifact.lua"))
        end)
    end)

    -- The contract that actually protects coverage.
    describe("skip scope", function()
        it("skips only on a missing directory, never on a missing file within one", function()
            -- spec/ IS present; a missing file inside it must NOT read as "environment
            -- lacks the artifacts". Callers gate on the directory, then let their own
            -- io.open assert fire for a genuinely deleted file.
            assert.is_true(OptionalArtifact.isPresent("spec"),
                "precondition: spec/ is tracked and present")
            local f = io.open("spec/NoSuchFile_ZZZ.py", "r")
                or io.open("../spec/NoSuchFile_ZZZ.py", "r")
            assert.is_nil(f,
                "a missing file inside a present directory must stay a real failure "
                .. "for the caller -- OptionalArtifact must not absorb it")
        end)
    end)

    describe("gatedIt", function()
        it("returns the real `it` when the directory is present", function()
            local sentinel = function() end
            assert.are.equal(sentinel,
                OptionalArtifact.gatedIt(sentinel, error, "spec"))
        end)

        it("returns a pending shim, not the real `it`, when the directory is absent", function()
            local itCalls, pendingCalls = 0, 0
            local fakeIt = function() itCalls = itCalls + 1 end
            local fakePending = function() pendingCalls = pendingCalls + 1 end
            local gated = OptionalArtifact.gatedIt(fakeIt, fakePending, "spec/NoSuchDir_ZZZ")
            gated("some test", function() error("body must never run") end)
            assert.are.equal(0, itCalls, "the real test must not run without its artifact")
            assert.are.equal(1, pendingCalls,
                "the skip must register as busted `pending` -- a silent no-op would make "
                .. "the test vanish from the summary instead of being reported as skipped")
        end)

        it("names the directory in the pending test's name", function()
            local seen
            local gated = OptionalArtifact.gatedIt(
                function() end, function(name) seen = name end, "spec/NoSuchDir_ZZZ")
            gated("some test", function() end)
            assert.is_truthy(string.find(seen, "some test", 1, true),
                "the original test name must survive so it is still findable")
            assert.is_truthy(string.find(seen, "spec/NoSuchDir_ZZZ", 1, true),
                "the pending name must say WHY it skipped, or a suite skipped in the main "
                .. "repo (where it should have run) looks intentional")
        end)

        it("does not call busted functions from inside the module", function()
            -- busted injects describe/it/pending into each SPEC FILE's environment, not
            -- into _G, and this module is loaded with dofile (which sees _G). A helper
            -- that called `describe` itself died with "attempt to call global 'describe'
            -- (a nil value)". Passing them in is what keeps them resolved in the caller's
            -- env -- do not "tidy" the parameters away.
            local f = io.open("../spec/OptionalArtifact.lua", "r")
                or io.open("spec/OptionalArtifact.lua", "r")
            assert.is_not_nil(f)
            local src = f:read("*a")
            f:close()
            for _, bustedFn in ipairs({ "describe", "pending", "it" }) do
                assert.is_nil(string.find(src, "\n%s*" .. bustedFn .. "%("),
                    bustedFn .. "() must not be called from the module body; take it as a "
                    .. "parameter (see gatedIt) -- dofile'd chunks cannot see busted's globals")
            end
        end)
    end)

    describe("readOptional", function()
        it("returns nil when the artifact directory is absent", function()
            assert.is_nil(OptionalArtifact.readOptional("spec/NoSuchDir_ZZZ/whatever.py"))
        end)

        it("raises when the directory exists but the file does not", function()
            -- The distinction the whole guard rests on: a deleted tool is a real defect
            -- and must stay loud, not be absorbed as "environment lacks artifacts".
            assert.has_error(function()
                OptionalArtifact.readOptional("spec/NoSuchFile_ZZZ.py")
            end)
        end)

        it("reads a file that is present", function()
            local text = OptionalArtifact.readOptional("spec/OptionalArtifact.lua")
            assert.is_truthy(text and string.find(text, "gatedIt", 1, true))
        end)
    end)
end)
