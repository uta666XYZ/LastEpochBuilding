-- @leb-regression-guard: dev-merge-guard-gate-matching
-- Locks how scripts/dev-merge.sh's Gate 2 LOOKS FOR the 3 layers of a guard.
--
-- Gate 2 is fail-closed: it blocks a merge when a newly registered guard in
-- REGRESSION_GUARDS.md has no Layer 1 (inline marker on the protected code) or
-- no Layer 2 (a *_spec.lua that actually fails). That only works if its lookup
-- can SEE a correctly written guard. As first landed it could not, in two ways
-- (both measured on dev <see git log>, both fixed by the commit that adds this spec):
--
--   1. It matched the literal "@leb-regression-guard:<id>" only. The tree spells
--      the marker three ways -- 1282 sites without a space after the colon, 404
--      WITH one, 55 with no colon at all. A guard written in either minority
--      style read as "Layer 1 missing" despite being well formed.
--   2. Layer 1 was searched under src/ only, and Layer 2 under all of spec/.
--      So a guard on spec/ driver code (spec/RegenFilterEnv.lua --
--      `regen-filter-env-fail-fast`, a real registered guard) was blocked
--      outright, while a guard whose Layer 1 comment sat anywhere in spec/
--      satisfied the Layer 2 check with no test at all.
--
-- Why this matters more than a normal bug: a false positive in a fail-closed
-- gate is worse than no gate. It blocks correct work, so people learn to pass
-- LEB_SKIP_CONVENTION_GATES=1 by reflex, and then the gate stops catching the
-- real violations it exists for. Keep the lookup tolerant of all three marker
-- spellings; keep Layer 1 = non-test code, Layer 2 = *_spec.lua.
--
-- This is a TEXT-level lock on the shell source (the repo idiom -- see
-- TestSilentFailureSweep_spec / TestPyramidalAltarCDR_spec), because busted
-- cannot execute the gate. scripts/ is tracked, so this runs everywhere.

local function readRepoRel(relPath)
    -- busted runs with cwd=src (.busted `directory = "src"`), so retry one up.
    local f = io.open(relPath, "r") or io.open("../" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("DevMergeGuardGateMatching", function()
    local gate, lookupLines

    setup(function()
        gate = readRepoRel("scripts/dev-merge.sh")
        -- Assert against the LOOKUP LINES, not the whole file. The gate's comments
        -- necessarily quote the broken forms to explain why they are broken, so a
        -- whole-file "must not contain X" check fails on its own documentation.
        lookupLines = {}
        for line in string.gmatch(gate, "[^\n]+") do
            if string.find(line, "git grep", 1, true) then
                table.insert(lookupLines, line)
            end
        end
        assert.is_true(#lookupLines > 0, "expected dev-merge.sh to contain git grep lookups")
    end)

    local function anyLookup(pattern)
        for _, line in ipairs(lookupLines) do
            if string.find(line, pattern) then return line end
        end
        return nil
    end

    it("tolerates all three inline marker spellings via an optional-colon pattern", function()
        -- The shared helper the two layer checks call.
        assert.is_truthy(string.find(gate, "guard_inline_re()", 1, true),
            "Gate 2 should build its marker regex through guard_inline_re()")
        assert.is_truthy(string.find(gate, "@leb%-regression%-guard:%? %*%%s"),
            "guard_inline_re must use an optional colon + optional spaces ('@leb-regression-guard:? *%s'), "
            .. "otherwise the 404 '<marker>: <id>' sites and 55 no-colon sites are invisible to the gate")
    end)

    it("does not regress to an exact-colon literal lookup", function()
        assert.is_nil(anyLookup('@leb%-regression%-guard:%$gid'),
            'a git grep for the literal "@leb-regression-guard:$gid" only sees one of the three '
            .. "marker spellings; call guard_inline_re instead")
    end)

    it("anchors the id so a truncated id cannot satisfy a lookup", function()
        assert.is_truthy(string.find(gate, "%[%^A%-Za%-z0%-9_%-%]|%$"),
            "guard_inline_re must require a non-id character after the id, else looking up "
            .. "'foo' would be satisfied by an unrelated 'foo-bar' marker")
    end)

    it("looks for Layer 1 on non-test code across src/, spec/, scripts/ and .gitignore", function()
        local layer1 = anyLookup("':%(exclude%)%*_spec%.lua'")
        assert.is_not_nil(layer1,
            "Layer 1 must exclude test files, so a guard cannot be 'protected' by its own spec")
        for _, dir in ipairs({ "src/", "spec/", "scripts/" }) do
            assert.is_truthy(string.find(layer1, dir, 1, true),
                "Layer 1 must search " .. dir .. ": guards legitimately live on non-src code "
                .. "(regen-filter-env-fail-fast is entirely in spec/; this gate itself is in scripts/)")
        end
        -- Validation provenance is retained in maintainer notes.
        assert.is_truthy(string.find(layer1, ".gitignore", 1, true),
            "Layer 1 must search .gitignore: an ignore rule has no consuming code in-tree, "
            .. "so the rule itself is where the marker belongs (handoffs-not-in-repo)")
    end)

    it("requires Layer 2 to be an actual *_spec.lua, not anything under spec/", function()
        local layer2 = anyLookup("%-%- '%*_spec%.lua'")
        assert.is_not_nil(layer2,
            "Layer 2 must be pinned to a '*_spec.lua' pathspec; matching all of spec/ lets a "
            .. "Layer 1 comment in a spec/ driver satisfy it, registering a 3-layer guard "
            .. "that has only 2")
    end)

    it("keeps both layer checks fail-closed", function()
        assert.is_truthy(string.find(gate, "Layer 1 missing", 1, true))
        assert.is_truthy(string.find(gate, "Layer 2 missing", 1, true))
        -- Each layer check must still exit non-zero rather than warn.
        local layerBlock = string.match(gate, "(Layer 1 missing.-Layer 2 missing.-exit 4)")
        assert.is_not_nil(layerBlock, "both layer checks must still end in `exit 4`")
    end)
end)
