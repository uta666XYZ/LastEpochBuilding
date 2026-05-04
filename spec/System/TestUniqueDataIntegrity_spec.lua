-- @leb-regression-guard: unique-data-integrity
-- Locks two within-version invariants that hand-migrated unique data
-- has historically violated when a new LE patch ships and uniques are
-- re-extracted from the game files (1.4 migration on 2026-05-05 caught
-- three: Legends Entwined dup, Raindance MS dup, Zeurial's Hunt copy-paste
-- text duplication).
--
-- 1. DUP_LINE: no exact-string mod line should appear twice within a
--    single unique's `mods` array. The two real cases where this is
--    legitimate (Zeurial's Hunt direction-pair, Raindance dual-MS in
--    1_2/1_3) both differ in *text* (Bow→Throwing vs Throwing→Bow) or
--    *range* ((11-14)% vs (10-13)%), so exact-string equality is the
--    correct equivalence relation here.
--
-- ROLLID_LEN was attempted here but Lua's `#` operator on a sparse
-- array (rollIds with embedded JSON null -> nil) is unreliable, so
-- the parallel-length invariant cannot be checked safely from Lua.
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

end)
