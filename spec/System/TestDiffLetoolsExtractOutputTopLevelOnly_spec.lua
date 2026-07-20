-- @leb-regression-guard: diff-letools-extract-output-top-level-only
-- Locks the contract that `spec/tools/diff_letools.py`'s extract_output() reads
-- ONLY the depth-1 (immediate) numeric keys of the `output = { ... }` table and
-- does NOT flat-scan into nested sub-tables.
--
-- Why this matters: the snapshot serializer (GenerateBuilds14.lua /
-- GenerateOneBuild.lua via buildTable) recurses into nested tables, so on
-- minion-MAIN builds output also contains `["Minion"] = { ... }`, whose keys
-- (Mana / Dex / Int / Life / EnduranceThreshold / resists) share names with the
-- player-level keys. The original extract_output brace-matched the whole output
-- body and ran NUM_RE.finditer over the flat text, so the LAST duplicate key
-- won and the nested Minion value (Mana=0, Dex=0, Int=0, Life=<minion life>)
-- clobbered the real player value. That produced a PHANTOM "systematic 0-ing"
-- of player Mana/Int/Dex/EnduranceThreshold on exactly the 145/575 minion-MAIN
-- snapshots that carry an output.Minion sub-table — a diagnostic-tool artifact,
-- NOT an LEB calc / snapshot / import bug. Ground truth: Lua
-- `loadfile(snapshot).output.Mana` (<private build>: player Mana=219, not 0).
--
-- See REGRESSION_GUARDS.md §diff-letools-extract-output-top-level-only.

local OptionalArtifact = dofile("../spec/OptionalArtifact.lua")
local toolsIt = OptionalArtifact.gatedIt(it, pending, "spec/tools")

-- Every test here reads spec/tools/diff_letools.py, which is gitignored (main repo
-- only), so the whole block skips rather than failing in a worktree/CI checkout.
describe("DiffLetoolsExtractOutputTopLevelOnly", function()
    local function readPython()
        local f = io.open("spec/tools/diff_letools.py", "r")
            or io.open("../spec/tools/diff_letools.py", "r")
        assert.is_not_nil(f, "diff_letools.py missing")
        local src = f:read("*a")
        f:close()
        return src
    end

    toolsIt("inline regression-guard marker precedes extract_output", function()
        local src = readPython()
        local block = src:match(
            "@leb%-regression%-guard:%s*diff%-letools%-extract%-output%-top%-level%-only"
            .. "(.-)def extract_output")
        assert.is_not_nil(block,
            "Inline @leb-regression-guard:diff-letools-extract-output-top-level-only "
            .. "comment must precede the def extract_output declaration")
    end)

    toolsIt("extract_output captures keys only at depth==1 (top level)", function()
        local src = readPython()
        -- Isolate the extract_output body so we don't match incidental text.
        local body = src:match("def extract_output%(path%):(.-)\ndef ")
        assert.is_not_nil(body, "extract_output function body must be present")
        assert.is_truthy(
            body:find("depth%s*==%s*1", 1, false),
            "extract_output must gate key capture on `depth == 1` so nested "
            .. "sub-tables (output.Minion / output.SkillDPS) are skipped")
    end)

    toolsIt("extract_output no longer flat-scans the whole body", function()
        local src = readPython()
        local body = src:match("def extract_output%(path%):(.-)\ndef ")
        assert.is_not_nil(body, "extract_output function body must be present")
        -- The buggy form ran NUM_RE.finditer(body) over the brace-matched text,
        -- which is exactly what let nested Minion keys clobber player keys.
        -- Reintroducing it would silently restore the phantom 0-ing.
        assert.is_nil(
            body:find("NUM_RE%.finditer", 1, false),
            "extract_output must NOT use NUM_RE.finditer over the flat body "
            .. "(that flat-scan is what clobbered player keys with nested "
            .. "output.Minion keys). Use the depth-aware walk instead.")
    end)
end)
