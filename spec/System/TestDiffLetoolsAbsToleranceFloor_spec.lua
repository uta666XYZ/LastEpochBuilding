-- @leb-regression-guard: diff-letools-abs-tolerance-floor
-- Locks the contract that `spec/tools/diff_letools.py` mirrors the
-- `TOL_ABS = 0.5` absolute-tolerance floor of its JS sibling
-- `scripts/letools-diff.js`. The floor absorbs LETools UI integer-display
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
        assert.is_truthy(block:find("scripts/letools%-diff%.js", 1, false),
            "Marker block must name the JS sibling to make the mirror-relation "
            .. "explicit for future maintainers")
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

    it("scripts/letools-diff.js still defines TOL_ABS = 0.5 (mirror integrity)", function()
        local f = io.open("scripts/letools-diff.js", "r")
            or io.open("../scripts/letools-diff.js", "r")
        assert.is_not_nil(f, "scripts/letools-diff.js missing")
        local js = f:read("*a")
        f:close()
        local val = js:match("TOL_ABS%s*=%s*([%d%.]+)")
        assert.is_not_nil(val, "scripts/letools-diff.js must define TOL_ABS")
        assert.are.equals("0.5", val,
            "JS sibling TOL_ABS must equal 0.5 — Python tool mirrors this "
            .. "value, so any change here must update both files in lock-step")
    end)
end)
