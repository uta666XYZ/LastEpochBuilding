-- @leb-regression-guard: diff-letools-abs-tolerance-floor
-- Locks the contract that `spec/tools/diff_letools.py` keeps the
-- `TOL_ABS = 0.5` absolute-tolerance floor. (Earlier docs referenced a JS
-- sibling `scripts/letools-diff.js` — that file never actually existed in
-- repo history, the Python tool is the sole owner.) The floor absorbs
-- LETools UI integer-display
-- rounding (Ward Regen, Block Chance, Endurance, …) so a sub-1.0 float
-- delta doesn't inflate to a fake double-digit percentage drift on
-- small-magnitude integer-rounded stats. Establishing case:
-- BgRrP5rr lv98 Paladin WardPerSecond LEB=3.712 (exact: Throne of
-- Ambition LifeRegenAppliesToWard=2 × LifeRegen=185.6 / 100) vs LETools
-- "4" → |D|=0.288 ≤ TOL_ABS → row dropped.
--
-- See REGRESSION_GUARDS.md §diff-letools-abs-tolerance-floor and
-- §ward-regen-passive-vs-event-split post-fix residual #2.

describe("DiffLetoolsAbsToleranceFloor", function()
    local function readPython()
        local f = io.open("spec/tools/diff_letools.py", "r")
            or io.open("../spec/tools/diff_letools.py", "r")
        assert.is_not_nil(f, "diff_letools.py missing")
        local src = f:read("*a")
        f:close()
        return src
    end

    it("TOL_ABS constant equals 0.5", function()
        local src = readPython()
        local val = src:match("TOL_ABS%s*=%s*([%d%.]+)")
        assert.is_not_nil(val, "TOL_ABS constant must be defined")
        assert.are.equals("0.5", val,
            "TOL_ABS must equal 0.5 to mirror scripts/letools-diff.js")
    end)

    it("inline regression-guard marker block present at TOL_ABS", function()
        local src = readPython()
        local block = src:match(
            "@leb%-regression%-guard:%s*diff%-letools%-abs%-tolerance%-floor(.-)TOL_ABS")
        assert.is_not_nil(block,
            "Inline @leb-regression-guard:diff-letools-abs-tolerance-floor "
            .. "comment must precede TOL_ABS = 0.5 declaration")
    end)

    it("filter loop drops rows with |D| <= TOL_ABS", function()
        local src = readPython()
        assert.is_truthy(
            src:find("abs%(d%)%s*<=%s*TOL_ABS", 1, false),
            "Main filter loop must contain `abs(d) <= TOL_ABS` check so "
            .. "sub-floor rows are dropped before being added to `rows`")
    end)

    it("--all bypass preserved (consume-site has `not args.all` guard)", function()
        -- The user can intentionally widen with --all to see sub-floor rows.
        -- This guards against a refactor accidentally hardcoding the floor.
        local src = readPython()
        assert.is_truthy(
            src:find("not args%.all and abs%(d%)%s*<=%s*TOL_ABS", 1, false),
            "TOL_ABS check must be gated on `not args.all` so the --all flag "
            .. "preserves access to sub-floor rows for triangulation")
    end)

    -- Removed: "scripts/letools-diff.js still defines TOL_ABS = 0.5" assertion.
    -- That JS sibling was claimed by the original commit (b8ce4d826) but never
    -- actually existed in the repo's git history at any ref. The Python tool
    -- (spec/tools/diff_letools.py) is the single source of truth for TOL_ABS.
    -- The 4 tests above already pin the Python TOL_ABS=0.5 constant, the
    -- filter loop, and the --all bypass — full mirror integrity for the only
    -- real artifact.
end)
