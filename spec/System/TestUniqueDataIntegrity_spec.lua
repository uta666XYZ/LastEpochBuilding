-- @leb-regression-guard: unique-data-integrity
-- Locks within-version invariants that hand-migrated unique data has
-- historically violated when a new LE patch ships and uniques are
-- re-extracted from the game files. Caught migrations:
--   2026-05-05 (1.4): Legends Entwined dup, Raindance MS dup,
--       Zeurial's Hunt copy-paste text duplication.
--   2026-05-09 (<private build> health +325): Aaron's Will (id=272) had
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
        -- Curated 2026-05-09 after Aaron's Will <private build> +325 health
        -- regression. Names verified against
        -- datamined game source
        assert.is_not_nil(data.uniques, "data.uniques must be loaded")
        local expected = {
            -- Aaron's Will: game has 8 mods. Buggy LEB had 10 (Health %
            --   and Minion Health % duplicated; gave <private build> +325 HP).
            ["Aaron's Will"]         = 8,
            -- Sunforged Greathelm: game has 4 mods. LEB 1_3/1_2 carried a
            --   trailing duplicate `(20-30)% increased Armor` (5 → 4).
            ["Sunforged Greathelm"]  = 4,
            -- Raindance: game has 6 mods. LEB previously had 7 (dup MS).
            ["Raindance"]            = 6,
            -- Legends Entwined: game has 5 (game splits AS/CS into two
            --   mods + 1 dup `Counts as part of every set`). LEB
            --   intentionally combines AS+CS into one row (commit
            --   <see git log>) → 5 in LEB.
            ["Legends Entwined"]     = 5,
            -- Zeurial's Hunt: game has 5 (Bow Lit Dmg, Throwing Lit Dmg,
            --   Throw→Bow direction, Bow→Throw direction, Haste).
            ["Zeurial's Hunt"]       = 5,
            -- Throne of Ambition: game data has ONE real mod (property 98,
            --   hideInTooltip) — all 6 visible lines are tooltipDescriptions
            --   (tooltipEntries modDisplay 128..133, i.e. all >= 128). LEB
            --   transcribes all 6 display lines. Audited 2026-07-16: LEB
            --   previously carried only 4, dropping the stack cap and decay
            --   lines. See displayOnlyModList in ModParser.lua.
            ["Throne of Ambition"]   = 6,
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

    -- @leb-regression-guard: unique-mod-text-tooltip-audit
    -- Pins mod-line text for uniques where in-game tooltips were confirmed
    -- by screenshot to differ from upstream regen / LETools / Musholic.
    -- Audited 2026-05-15:
    --   * Hand of Judgement: regen produced "Judgement Mana Cost" word
    --     order, but in-game tooltip reads "Mana cost for Judgement"
    --     (note lowercase "cost"). Override in unique_overrides.json.
    --   * Pearls of the Swine (Blood / Fire): LEB carried a spurious
    --     "+100% " prefix on the "Bone Curse also inflicts X" line that
    --     in-game tooltips do NOT show. Poison variant was already clean.
    -- Audited 2026-05-23:
    --   * Blade of the Forgotten Knight (set_1_4.json uniqueID=88): the
    --     1.4 game files / LETools DB "Game Version Changes" log raised
    --     both Cast Speed and Attack Speed from 7%-era → 15% → 20% in 1.4.
    --     set_1_4.json still carried the pre-1.4 "15%" values for both
    --     lines. Triple-confirmed (uniques_v3.json datamine + LETools
    --     tooltip + LETools 1.4 change log). Fixed in set_1_4.json.
    --     NOTE: the legacy uniques.json (no-suffix, pre-1.4 fallback) is
    --     intentionally left at the OLD values — current 1.4 builds read
    --     set_1_4.json (merged by Data.lua ~625), never uniques.json.
    --   * Ruby Fang Aegis (set_1_4.json uniqueID=174): in-game tooltip and
    --     datamine uniques_v3.json (id=174, base name "Ruby Tower Shield")
    --     both read "Ruby Venom for 10 seconds on Block"; set_1_4.json
    --     carried stale "8 seconds". Fixed in set_1_4.json.
    --   * Fragments of the Shattered Lance (set_1_4.json uniqueID=110): the
    --     3rd modifier slot in set_1_4.json carried "+(7-12) Health Regen"
    --     — but that value is the base Relic IMPLICIT (in-game "+10 Health
    --     Regen, Range 7 to 12"). The actual 3rd modifier is "(10-13)
    --     Health Gain on Freeze" (datamine uniques_v3.json id=110 property
    --     38 value=10/maxValue=13; in-game tooltip "10 Health Gain on
    --     Freeze, Range 10 to 13"; legacy uniques_1_2/1_3.json already had
    --     the correct text). set_1_4.json had copied the implicit into the
    --     modifier slot with wrong stat AND wrong value. Triple-confirmed
    --     (datamine + LETools + in-game screenshot 2026-05-23). Fixed in
    --     set_1_4.json.
    -- A future regen of upstream that re-introduces any pattern trips
    -- this spec instead of silently shifting tooltip text.
    it("tooltip-audited mod text is preserved (TOOLTIP_TEXT)", function()
        assert.is_not_nil(data.uniques, "data.uniques must be loaded")

        -- For uniques with a unique name we can match by entry.name.
        -- For Pearls of the Swine (3 variants share name), match the
        -- variant by a sentinel substring in another mod line.
        local cases = {
            {
                name        = "Hand of Judgement",
                require_any = { "-12 to -8 Mana cost for Judgement while Unarmed" },
                forbid_any  = { "Judgement Mana Cost while Unarmed" },
            },
            {
                name        = "Pearls of the Swine",
                variant_has = "increased Physical Damage",  -- Blood
                require_any = { "Bone Curse also inflicts Decrepify" },
                forbid_any  = { "+100% Bone Curse also inflicts Decrepify" },
            },
            {
                name        = "Pearls of the Swine",
                variant_has = "increased Fire Damage",      -- Fire
                require_any = { "Bone Curse also inflicts Penance" },
                forbid_any  = { "+100% Bone Curse also inflicts Penance" },
            },
            {
                name        = "Pearls of the Swine",
                variant_has = "increased Poison Damage",    -- Poison
                require_any = { "Bone Curse also inflicts Acid Skin" },
                forbid_any  = { "+100% Bone Curse also inflicts Acid Skin" },
            },
            {
                -- Blade of the Forgotten Knight (set_1_4.json id=88): 1.4
                -- raised Cast & Attack Speed to 20%; set_1_4.json carried
                -- stale 15%. Pin both at 20% and forbid the old 15%.
                name        = "Blade of the Forgotten Knight",
                require_any = { "20% increased Cast Speed", "20% increased Attack Speed" },
                forbid_any  = { "15% increased Cast Speed", "15% increased Attack Speed" },
            },
            {
                -- Ruby Fang Aegis (set_1_4.json id=174): in-game tooltip
                -- + datamine uniques_v3.json (id=174 "Ruby Tower Shield")
                -- both read "Ruby Venom for 10 seconds on Block"; set_1_4
                -- carried stale "8 seconds". Pin 10s, forbid 8s.
                name        = "Ruby Fang Aegis",
                require_any = { "Ruby Venom for 10 seconds on Block" },
                forbid_any  = { "Ruby Venom for 8 seconds on Block" },
            },
            {
                -- Fragments of the Shattered Lance (set_1_4.json id=110):
                -- the 3rd modifier is "(10-13) Health Gain on Freeze"
                -- (datamine prop38 + in-game). set_1_4.json had copied the
                -- base Relic implicit "+(7-12) Health Regen" into the
                -- modifier slot. Pin the Freeze line, forbid the implicit
                -- text appearing as a (Health Regen) modifier value.
                name        = "Fragments of the Shattered Lance",
                require_any = { "(10-13) Health Gain on Freeze" },
                forbid_any  = { "+(7-12) Health Regen" },
            },
            {
                -- Throne of Ambition (id=211): LEB paraphrased the stack-gain
                -- line as "100% Chance to gain a stack of Ambition ...", a
                -- wording that exists in neither the datamine nor the in-game
                -- tooltip, and dropped the "(1 second cooldown)" qualifier.
                -- Pinned to uniques_v3.json tooltipDescriptions[0] verbatim,
                -- confirmed against an in-game screenshot 2026-07-16. The
                -- cap/decay lines are pinned too — they were absent entirely.
                name        = "Throne of Ambition",
                require_any = {
                    "You gain a stack of Ambition when you hit a boss or rare enemy (1 second cooldown)",
                    "20 Maximum Stacks of Ambition",
                    "You lose all stacks of Ambition if you go 4 seconds without gaining a stack",
                },
                forbid_any  = { "100% Chance to gain a stack of Ambition" },
            },
        }

        local offenders = {}
        for _, case in ipairs(cases) do
            -- Collect all entries with this name; if variant_has is set,
            -- restrict to the entry whose mods include that substring.
            local matched
            for _, entry in pairs(data.uniques) do
                if type(entry) == "table" and entry.name == case.name and type(entry.mods) == "table" then
                    if case.variant_has then
                        for _, line in ipairs(entry.mods) do
                            if type(line) == "string" and string.find(line, case.variant_has, 1, true) then
                                matched = entry
                                break
                            end
                        end
                    else
                        matched = entry
                    end
                    if matched then break end
                end
            end
            if not matched then
                table.insert(offenders, string.format(
                    "name=%q variant=%q not found", case.name,
                    tostring(case.variant_has or "")))
            else
                local mods = matched.mods
                for _, want in ipairs(case.require_any or {}) do
                    local found = false
                    for _, line in ipairs(mods) do
                        if type(line) == "string" and string.find(line, want, 1, true) then
                            found = true
                            break
                        end
                    end
                    if not found then
                        table.insert(offenders, string.format(
                            "name=%q variant=%q missing required line %q",
                            case.name, tostring(case.variant_has or ""), want))
                    end
                end
                for _, bad in ipairs(case.forbid_any or {}) do
                    for _, line in ipairs(mods) do
                        if type(line) == "string" and string.find(line, bad, 1, true) then
                            table.insert(offenders, string.format(
                                "name=%q variant=%q contains forbidden line %q",
                                case.name, tostring(case.variant_has or ""), bad))
                        end
                    end
                end
            end
        end

        assert.are.equal(0, #offenders,
            "tooltip-audited mod text drifted:\n  " .. table.concat(offenders, "\n  "))
    end)

end)
