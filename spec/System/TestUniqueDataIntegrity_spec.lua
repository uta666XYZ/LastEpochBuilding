-- @leb-regression-guard: unique-data-integrity
-- Locks within-version invariants that hand-migrated unique data has
-- historically violated when a new LE patch ships and uniques are
-- re-extracted from the game files. Caught migrations:
--   2026-05-05 (1.4): Legends Entwined dup, Raindance MS dup,
--       Zeurial's Hunt copy-paste text duplication.
--   2026-05-09 (Q9J4w8PE health +325): Aaron's Will (id=272) had
--       extra `(10-24)% increased Health` + `(100-240)% increased
--       Minion Health` lines (mods=10 vs game data's 8). The exact-
--       string DUP_LINE caught it once the audit ran. Same bug
--       existed in datamining `unique_overrides.json` for 5 uniques
--       (Aaron's Will, Sunforged Greathelm, Raindance, Legends
--       Entwined, Zeurial's Hunt typo) and was scrubbed at the
--       upstream too.
--
-- 1. DUP_LINE: no exact-string mod line should appear twice within a
--    single unique's `mods` array. The two real cases where this is
--    legitimate (Zeurial's Hunt direction-pair, Raindance dual-MS in
--    1_2/1_3) both differ in *text* (Bow→Throwing vs Throwing→Bow) or
--    *range* ((11-14)% vs (10-13)%), so exact-string equality is the
--    correct equivalence relation here.
--
-- 2. EXPECTED_COUNT: a hand-curated allow-list of uniques whose mod
--    array length has been audited against the game data
--    (`uniques_v3.json`). Pinning the count means a future regen that
--    re-introduces upstream dups (e.g. the 2026-05-09 Aaron's Will
--    +325 health regression where mods drifted from 8 → 10) trips the
--    spec instead of silently shifting downstream snapshots. Add a
--    new entry whenever you fix a unique whose row count was wrong.
--
-- ROLLID_LEN was attempted but Lua's `#` operator on a sparse array
-- (rollIds with embedded JSON null -> nil) is unreliable, so the
-- parallel-length invariant cannot be checked safely from Lua.
-- That check lives in .tmp/audit_uniques_1_4_regression.py instead.
--
-- Cross-version (1_3 -> 1_4) ROW_DROP / RANGE_COLLAPSE checks are
-- deliberately NOT in this spec — they require both version files to be
-- loaded simultaneously, and they're false-positive heavy because LE
-- 1.4 moved boots base implicits from each unique into bases_1_4.json.
-- Run them as one-shot checks during migration, not in CI.
--
-- See REGRESSION_GUARDS.md "unique-data-integrity".

describe("TestUniqueDataIntegrity #uniqueData", function()
    setup(function()
        newBuild()
    end)

    it("no unique has duplicate mod lines (DUP_LINE)", function()
        assert.is_not_nil(data.uniques, "data.uniques must be loaded")
        local offenders = {}
        for uid, entry in pairs(data.uniques) do
            local mods = entry.mods
            if type(mods) == "table" then
                local seen = {}
                for _, line in ipairs(mods) do
                    if seen[line] then
                        table.insert(offenders, string.format(
                            "id=%s name=%q dup=%q",
                            tostring(uid), tostring(entry.name or "?"), tostring(line)))
                        break
                    end
                    seen[line] = true
                end
            end
        end
        assert.are.equal(0, #offenders,
            "duplicate mod lines found:\n  " .. table.concat(offenders, "\n  "))
    end)

    it("expected mod counts match game data (EXPECTED_COUNT)", function()
        -- Hand-curated allow-list of uniques where the override-vs-game
        -- mod-count delta has been audited at least once. Each entry is
        -- the LEB `mods` array length we expect; if it drifts (either the
        -- regen pipeline re-introduces dups or someone manually deletes a
        -- legitimate row), this trips and forces a re-audit.
        --
        -- Curated 2026-05-09 after Aaron's Will Q9J4w8PE +325 health
        -- regression. Names verified against
        -- LE_datamining/extracted/items/uniques_v3.json.
        assert.is_not_nil(data.uniques, "data.uniques must be loaded")
        local expected = {
            -- Aaron's Will: game has 8 mods. Buggy LEB had 10 (Health %
            --   and Minion Health % duplicated; gave Q9J4w8PE +325 HP).
            ["Aaron's Will"]         = 8,
            -- Sunforged Greathelm: game has 4 mods. LEB 1_3/1_2 carried a
            --   trailing duplicate `(20-30)% increased Armor` (5 → 4).
            ["Sunforged Greathelm"]  = 4,
            -- Raindance: game has 6 mods. LEB previously had 7 (dup MS).
            ["Raindance"]            = 6,
            -- Legends Entwined: game has 5 (game splits AS/CS into two
            --   mods + 1 dup `Counts as part of every set`). LEB
            --   intentionally combines AS+CS into one row (commit
            --   e16040093) → 5 in LEB.
            ["Legends Entwined"]     = 5,
            -- Zeurial's Hunt: game has 5 (Bow Lit Dmg, Throwing Lit Dmg,
            --   Throw→Bow direction, Bow→Throw direction, Haste).
            ["Zeurial's Hunt"]       = 5,
        }
        local byName = {}
        for _, entry in pairs(data.uniques) do
            if type(entry) == "table" and entry.name then
                byName[entry.name] = entry
            end
        end
        local offenders = {}
        for name, want in pairs(expected) do
            local entry = byName[name]
            if not entry then
                -- Not present in this version's file (e.g. Sunforged is
                -- only in 1_3) — silently skip.
            else
                local got = entry.mods and #entry.mods or 0
                if got ~= want then
                    table.insert(offenders, string.format(
                        "name=%q expected=%d got=%d", name, want, got))
                end
            end
        end
        assert.are.equal(0, #offenders,
            "audited unique mod count drifted:\n  " .. table.concat(offenders, "\n  "))
    end)

end)
