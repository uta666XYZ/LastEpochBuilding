-- Presence check for the GITIGNORED spec artifacts (`spec/TestBuilds/`, `spec/tools/`),
-- so specs that depend on them skip instead of failing where they cannot exist.
-- Load with `dofile("../spec/OptionalArtifact.lua")` -- specs run with cwd=src (see
-- `.busted` `directory = "src"`). Mirrors spec/RegenFilterEnv.lua's shape.
--
-- USAGE. Pick `it` or `pending` at DECLARATION time and use it for the artifact-dependent
-- tests only:
--
--     local OptionalArtifact = dofile("../spec/OptionalArtifact.lua")
--     local toolsIt = OptionalArtifact.gatedIt(it, pending, "spec/tools")
--
--     describe("Foo", function()
--         setup(function()
--             diffPy = OptionalArtifact.readOptional("spec/tools/diff_letools.py")  -- nil if absent
--             calcSrc = readFile("src/Modules/CalcSetup.lua")                       -- always
--         end)
--         toolsIt("diff_letools.py defines X", function() ... end)  -- pending when absent
--         it("CalcSetup still emits Y", function() ... end)         -- always runs
--     end)
--
-- This module deliberately calls NO busted functions. busted injects `describe`/`it`/
-- `pending` into each SPEC FILE's environment, not into _G, and a dofile'd chunk sees _G
-- -- so a helper that called `describe` itself died with "attempt to call global
-- 'describe' (a nil value)". Passing them in keeps them resolved in the caller's env.
--
-- @leb-regression-guard: optional-artifact-pending-not-silent
-- WHAT THIS IS FOR. `spec/TestBuilds/` and `spec/tools/` are gitignored and have ZERO
-- tracked files, so they exist ONLY in the main repo working tree. Every worktree and
-- every CI checkout is without them, where 9 specs that read them failed on
-- `assert.is_not_nil(f, ...)`. That is 16 red results that mean nothing, in every
-- worktree run, permanently. Noise on that scale is not cosmetic: it is exactly the
-- cover a real regression hides under, because "16 red, same as always" stops being read.
--
-- THE INVARIANT, AND WHY IT IS NARROW. Skip ONLY when the whole directory is absent
-- -- that, and only that, means "this checkout does not carry the optional artifacts".
-- If the directory IS present but a specific file inside it is missing, that is a real
-- defect (someone deleted a tool, or renamed a snapshot) and MUST still fail loudly.
-- Do not "simplify" this into a blanket `if not file then skip end`: that reads as green
-- in the main repo while silently testing nothing, which is strictly worse than the noise
-- it replaces. The failure mode being avoided is the same one `regen-filter-env-fail-fast`
-- guards: a fallback quieter than the real path, and therefore invisible.
--
-- Skips surface as busted `pending`, never as a silent pass -- a skipped test stays
-- visible in the summary and countable. Gate PER TEST, not per block, wherever a block
-- mixes artifact-dependent and src-only tests: a whole-block skip there would trade the
-- noise for real lost coverage.
local M = {}

-- Lua has no portable directory stat without lfs. `os.rename(path, path)` is the standard
-- idiom: a no-op on success, and it distinguishes "missing" from "exists but not
-- renameable" (EACCES=13), which still means present.
local function pathExists(path)
    local ok, _, code = os.rename(path, path)
    if ok then return true end
    if code == 13 then return true end
    return false
end

-- Specs run with cwd=src, but callers write repo-root-relative paths, so try both.
-- Returns the resolved path, or nil when it is absent from this checkout.
function M.resolveDir(repoRelDir)
    if pathExists(repoRelDir) then return repoRelDir end
    local up = "../" .. repoRelDir
    if pathExists(up) then return up end
    return nil
end

function M.isPresent(repoRelDir)
    return M.resolveDir(repoRelDir) ~= nil
end

function M.skipMessage(repoRelDir)
    return string.format(
        "(skipped: %s/ is an optional local artifact and is absent from this checkout)",
        repoRelDir)
end

-- Returns busted's `it` when the artifact directory is present, and a `pending` shim
-- naming the directory when it is not. Pass busted's own `it` and `pending` -- see the
-- environment note above.
function M.gatedIt(itFn, pendingFn, repoRelDir)
    if M.isPresent(repoRelDir) then return itFn end
    local suffix = " " .. M.skipMessage(repoRelDir)
    return function(name, _)
        return pendingFn(name .. suffix)
    end
end

-- Read a file that lives under a gitignored artifact directory.
-- Returns nil when the DIRECTORY is absent (this checkout has no artifacts -- callers
-- pair this with gatedIt on the tests that need the text). Raises when the directory IS
-- present but the file is not, because that is a genuinely deleted/renamed artifact and
-- must stay loud. Safe to call from setup().
function M.readOptional(repoRelPath)
    local dir = string.match(repoRelPath, "^(.*)/[^/]+$")
    assert(dir, "readOptional needs a path with a directory component: " .. repoRelPath)
    if not M.isPresent(dir) then return nil end
    local f = io.open(repoRelPath, "r") or io.open("../" .. repoRelPath, "r")
    assert(f, string.format(
        "%s is missing, but %s/ exists -- this is a real deletion, not an absent-artifact "
        .. "checkout. Fix the file or update the spec; do not skip it.", repoRelPath, dir))
    local text = f:read("*a")
    f:close()
    return text
end

return M
