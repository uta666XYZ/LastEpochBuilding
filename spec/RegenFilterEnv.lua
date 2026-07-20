-- Env-filter parsing shared by the snapshot-regen drivers (spec/GenerateBuilds*.lua,
-- spec/RegenOneBuild.lua). Load with `dofile("../spec/RegenFilterEnv.lua")` -- those
-- drivers run with cwd=src (see `.busted` `directory = "src"`).
--
-- @leb-regression-guard: regen-filter-env-fail-fast
-- Every var parsed here NARROWS which builds get regenerated, so a parse failure
-- that falls back to "no filter" WIDENS the run to the whole corpus (639 builds,
-- hours) instead of the handful the caller asked for. It is silent: the caller's
-- intent (narrow) and the fallback (wide) differ in runtime, not in exit status.
-- This has fired twice on LEB_ONLY_LIST -- once on a /tmp path native LuaJIT could
-- not open, once (2026-07-16) on a build NAME passed where a FILE path was
-- expected. Both printed a WARN and regenerated everything anyway.
--
-- Contract: a filter var that is SET but unusable must error(). Never continue
-- with a wider selection than the caller asked for. Unset ("") stays the normal
-- path and means "no filter". The mirror-image failure -- a filter that parses to
-- something matching NOTHING -- also errors, because it exits 0 having silently
-- regenerated nothing, which reads as success.
local M = {}

-- Callers write these paths from the worktree root while the drivers run with
-- cwd=src, so a bare relative path needs a "../" retry before it counts missing.
local function openWithParentFallback(path)
    local fh, err = io.open(path, "r")
    if fh then return fh, path end
    local alt = "../" .. path
    local altFh = io.open(alt, "r")
    if altFh then return altFh, alt end
    return nil, nil, err
end
M.openWithParentFallback = openWithParentFallback

local function readEntries(fh, skipComments)
    local entries = {}
    for line in fh:lines() do
        -- CR-LF tolerated: a trailing \r survives into the substring otherwise and
        -- then matches no build path -- the silent-nothing half of the same trap.
        line = line:gsub("\r$", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" and not (skipComments and line:match("^#")) then
            table.insert(entries, line)
        end
    end
    return entries
end

-- LEB_SHARD="i/N" -> keep builds whose 0-based sorted index % N == i.
-- Unset -> 0/1 (the whole set), which is the only widening this function may do.
function M.parseShard(shardEnv)
    shardEnv = shardEnv or ""
    if shardEnv == "" then return 0, 1 end
    local i, n = shardEnv:match("^(%d+)/(%d+)$")
    i, n = tonumber(i), tonumber(n)
    if not i or not n then
        error('LEB_SHARD="' .. shardEnv .. '" is malformed. Expected "i/N" with 0 <= i < N (e.g. "0/4"). '
            .. 'Aborting: a malformed shard used to fall back to 0/1, silently regenerating the WHOLE corpus.')
    end
    if n < 1 then
        error('LEB_SHARD="' .. shardEnv .. '" has N=' .. n .. '; N must be >= 1.')
    end
    if i >= n then
        error('LEB_SHARD="' .. shardEnv .. '" has i=' .. i .. ' >= N=' .. n .. '. The shard index is 0-based, so i must be < N; '
            .. 'this shard would match no build and regenerate nothing.')
    end
    return i, n
end

-- LEB_ONLY_LIST=<path> -> array of SUBSTRINGS; a build is kept when its path
-- contains any of them. Unset -> nil (no filter).
function M.loadOnlyList(path)
    path = path or ""
    if path == "" then return nil end
    local fh, resolved, err = openWithParentFallback(path)
    if not fh then
        error('LEB_ONLY_LIST=' .. path .. ' could not be opened (tried "' .. path .. '" and "../' .. path .. '"): '
            .. tostring(err) .. '. It must be a path to a newline-separated filter FILE (not a build name). '
            .. 'Aborting to avoid an unintended full-corpus regen. Use LEB_ONLY="<substr>" to filter by substring.')
    end
    local list = readEntries(fh, false)
    fh:close()
    if #list == 0 then
        error('LEB_ONLY_LIST=' .. resolved .. ' has no non-blank lines. Aborting: an empty filter matches NO build, '
            .. 'so the run would exit 0 having regenerated nothing. Unset LEB_ONLY_LIST to regenerate the whole corpus on purpose.')
    end
    return list, resolved
end

-- LEB_ONLY_FILE=<path> -> set of repo-relative build paths, matched by suffix.
-- '#' comments allowed. Unset -> nil (no filter).
function M.loadOnlyFile(path)
    path = path or ""
    if path == "" then return nil end
    local fh, resolved, err = openWithParentFallback(path)
    if not fh then
        error('LEB_ONLY_FILE=' .. path .. ' could not be opened (tried "' .. path .. '" and "../' .. path .. '"): '
            .. tostring(err) .. '. It must be a path to a file listing one repo-relative build path per line. '
            .. 'Aborting to avoid an unintended full-corpus regen.')
    end
    local entries = readEntries(fh, true)
    fh:close()
    if #entries == 0 then
        error('LEB_ONLY_FILE=' .. resolved .. ' lists no build paths (blank/comment-only). Aborting: it matches NO build, '
            .. 'so the run would exit 0 having regenerated nothing.')
    end
    local set = {}
    for _, entry in ipairs(entries) do set[entry] = true end
    return set, #entries, resolved
end

-- fetchBuilds() yields nil (unreadable file) or {} (no .xml under LEB_ROOT). Both
-- reach the regen loop as "zero builds" and exit 0 without regenerating anything.
function M.assertBuildsFound(buildList, root, err)
    if not buildList then
        error('LEB_ROOT=' .. tostring(root) .. ' could not be read: ' .. tostring(err) .. '. Aborting.')
    end
    if next(buildList) == nil then
        error('LEB_ROOT=' .. tostring(root) .. ' contains no .xml builds. Aborting: the run would exit 0 having regenerated nothing.')
    end
    return buildList
end

return M
