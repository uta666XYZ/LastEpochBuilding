-- Single source of truth for "what IS the test-build corpus, and how is a build
-- identified". Shared by the corpus test (spec/System/TestBuilds_spec.lua) and the
-- snapshot-regen drivers (spec/GenerateBuilds.lua, and the gitignored
-- spec/GenerateBuilds14.lua). Load with `dofile("../spec/CorpusScope.lua")` -- both
-- run with cwd=src (see `.busted` `directory = "src"`). Mirrors the shape of
-- spec/RegenFilterEnv.lua and spec/OptionalArtifact.lua.
--
-- This module exists because the walk was previously copy-pasted per consumer, and
-- the copies silently disagreed on BOTH of the things a corpus is made of: which
-- tree it covers, and what names a build by. Each disagreement cost real coverage
-- (see the two guards below). One implementation, called by everyone, is what keeps
-- them from drifting apart again.
local M = {}

-- @leb-regression-guard:regen-root-equals-test-root
-- The corpus root is ONE constant because the regen scope and the test scope must be
-- the same tree. They were not: the regen driver defaulted to `../spec/TestBuilds/1.4`
-- (639 builds) while the test walked `../spec/TestBuilds` (644). The 5 builds outside
-- 1.4/ (1.2/ x3, 1.3/ x1, StarSeaVnV_LEB.xml) were therefore TESTED BUT NEVER
-- REGENERATED -- for the entire life of the corpus, not since some recent addition.
-- The failure is invisible: both scopes exit 0, and the gap only shows up as a stale
-- snapshot that nobody can explain (measured: warpath_channel in 1.2/ drifted and no
-- regen could reach it, because the default root excluded it).
--
-- Do NOT reintroduce a version-pinned default anywhere. Narrowing on PURPOSE is still
-- fine and is what LEB_ROOT is for -- see resolveBuildRoot: an explicit env override
-- narrows a single run, while the DEFAULT stays the whole tree. That asymmetry is the
-- invariant; a narrow default is the bug.
M.ROOT = "../spec/TestBuilds"

-- LEB_ROOT=<path> -> regenerate only that subtree, for a targeted regen.
-- Unset -> M.ROOT, i.e. exactly the tree the corpus test walks.
--
-- An explicit override is deliberately NOT validated against M.ROOT: pointing a regen
-- at one directory is a legitimate, routine narrowing. Only the default is load-bearing.
function M.resolveBuildRoot(envRoot)
    if envRoot == nil or envRoot == "" then return M.ROOT end
    return envRoot
end

-- @leb-regression-guard:corpus-build-key-is-path-not-basename
-- Builds are keyed by their FULL PATH, never by basename. `spec/TestBuilds/1.4/` and
-- `spec/TestBuilds/1.4/bin/` hold 6 pairs of same-named, DIFFERENT builds (verified by
-- md5: e.g. `VoidCleaver lv84 VK.xml` differs between the two). The corpus test used to
-- key its build map by basename (`buildList[file]`) while the regen driver keyed by path
-- (`buildList[f]`), so each colliding pair collapsed to ONE entry and 6 builds were
-- silently untested -- with WHICH copy survived decided by directory-walk order, not by
-- anything meaningful. The suite still reported success, because a build that is never
-- enumerated cannot fail.
--
-- Return a SORTED ARRAY, not a set keyed by name: an array cannot collide by
-- construction, and sorting makes enumeration order deterministic across runs
-- (`pairs()` order is not). Callers do their own IO -- this walker only decides
-- membership and identity.
function M.listBuildFiles(root, ext, out)
    out = out or {}
    for entry in lfs.dir(root) do
        if entry ~= "." and entry ~= ".." then
            local path = root .. "/" .. entry
            local attr = lfs.attributes(path)
            assert(type(attr) == "table", "cannot stat " .. path)
            if attr.mode == "directory" then
                M.listBuildFiles(path, ext, out)
            elseif entry:match("^.+(%..+)$") == ext then
                table.insert(out, path)
            end
        end
    end
    table.sort(out)
    return out
end

-- A build's display name = its path relative to the corpus root ("1.4/bin/X.lua").
-- Unique across the corpus (unlike a basename) and still readable in test output.
function M.buildName(path, root)
    root = root or M.ROOT
    local prefix = root .. "/"
    if path:sub(1, #prefix) == prefix then return path:sub(#prefix + 1) end
    return path
end

return M
