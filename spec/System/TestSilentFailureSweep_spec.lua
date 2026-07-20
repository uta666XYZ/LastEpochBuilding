-- @leb-regression-guard: silent-failure-affix-sweep
-- Phase 1 lock for the Category B silent-failure affix sweep.
--
-- The tool `spec/tools/enumerate_silent_failures.py` walks
-- src/Data/ModCache.lua and emits spec/Data/silent-failure-affixes.json
-- listing every row of the form `c["..."]={{},"<residue>"}` -- an affix
-- string LEB attempted to parse, where ModParser returned an empty modList
-- yet emitted non-empty residue (i.e. the affix was silently swallowed
-- without surfacing into calculations and without raising an error).
--
-- This spec locks the Phase 1 baseline so any regression -- either:
--   (a) a new silent-failure regression growing the count back, or
--   (b) a successful Phase 3 wiring shrinking the count -- forces a
-- deliberate update of the JSON snapshot and this spec's baselines.
--
-- Phase 1 deliverables:
--   * tool   : spec/tools/enumerate_silent_failures.py
--   * data   : spec/Data/silent-failure-affixes.json
--   * spec   : this file
--   * index  : REGRESSION_GUARDS.md "silent-failure-affix-sweep"
--
-- Phase 2 (classification refinement via datamining cross-reference) and
-- Phase 3 (type-specific PRs neutralising / wiring / spawning / purging)
-- live behind their own tickets -- see TODO.md "Category B silent-failure
-- affix sweep".

local OptionalArtifact = dofile("../spec/OptionalArtifact.lua")
local toolsIt = OptionalArtifact.gatedIt(it, pending, "spec/tools")

local function readFile(relPath)
    local f = io.open(relPath, "r") or io.open("../" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("SilentFailureAffixSweep", function()
    local cjson_ok, cjson = pcall(require, "lua.dkjson")
    if not cjson_ok then cjson_ok, cjson = pcall(require, "dkjson") end

    local raw, data
    setup(function()
        raw = readFile("spec/Data/silent-failure-affixes.json")
        if cjson_ok and cjson.decode then
            data = cjson.decode(raw)
        end
    end)

    describe("JSON artefact freshness", function()
        it("exists and has the expected top-level shape", function()
            assert.is_string(raw)
            assert.is_truthy(string.find(raw, '"metadata"', 1, true))
            assert.is_truthy(string.find(raw, '"silent_failures"', 1, true))
            assert.is_truthy(string.find(raw, '"dm_gap"', 1, true))
        end)

        it("identifies itself as the enumerate_silent_failures tool", function()
            assert.is_truthy(string.find(raw, '"enumerate_silent_failures"', 1, true))
        end)

        it("declares Phase 2", function()
            assert.is_truthy(string.find(raw, '"phase": 2', 1, true))
        end)
    end)

    describe("baseline counts (Phase 3a lock)", function()
        -- These baselines are intentionally hard-coded. When you change
        -- ModCache.lua in a way that moves these numbers, RE-RUN the tool
        --   python spec/tools/enumerate_silent_failures.py
        -- and update both spec/Data/silent-failure-affixes.json AND the
        -- numbers below in the SAME commit. A drift here is your cue that
        -- a wiring/neutralisation actually landed and the baseline moved.
        --
        -- Phase 3a (a1-pure-flavor bulk neutralization) moved:
        --   neutralized  367 -> 1082  (+715)
        --   silent      2791 -> 2076  (-715)
        --   recognition 83.34% -> 87.61%
        -- deaths-door-lowlife-critmult moved (surgical -6: the six empty
        -- "Crit Multi"/"Crit Multiplier" rows un-baked from ModCache so the
        -- new modNameList aliases live-parse them):
        --   total  16749 -> 16743
        --   silent  2076 -> 2070
        -- 2026-06-12 discovery-debt refresh (re-ran the tool against current
        -- dev ModCache; #13 had bumped the metadata but the body had drifted
        -- stale through earlier un-bakes). 44 rows LEFT the silent set, 0
        -- entered it -- every removal attributes to a landed fix:
        --   trigger-subskill rollout un-baked the "chance to cast <skill>"
        --     procs (Fire Aura / Maelstrom-timer / Divine Bolt / Zap /
        --     Storm Bolt / Wind Tempest), the StarSea idol-3 fix
        --     (<see git log>) un-baked Pierce-w-Fireball + Pierce->CritMulti +
        --     the different-shape idol line, Apocrypha conversion +
        --     Chthonic Fissure un-baked the "X -> Y" arrows, recast-parse
        --     (<see git log>) un-baked the Recast rows.
        --   total  16743 -> 16537   parsed 13591 -> 13437
        --   neutralized 1082 -> 1074   silent 2070 -> 2026
        -- 2026-06-13 landing-order tail refresh (re-ran the tool after two
        -- ModCache-affecting merges that landed AFTER the prior refresh:
        -- Avalanche large-boulder <see git log> and minion ActorStats <see git log>).
        -- Exactly ONE row LEFT the silent set, 0 entered -- no regression:
        --   "5% Large Boulder Chance" was un-baked by Avalanche-B into
        --   DoubleDamageChance BASE 5 [Hit] (ModCache row now parses), so it
        --   moved silent -> parsed. minion-actorstats wrote minions.json +
        --   a SkillId-scoped ModParser entry (no silent-failure row change);
        --   adaptive-typing C touched only CalcOffence (0). total/neutralized
        --   and all dm baselines hold; only parsed/silent move by 1.
        --   parsed 13437 -> 13438   silent 2026 -> 2025
        --   (by_category: b-parser-gap 458 -> 457)
        -- 2026-07-06 aspect-effect-buff-scalar (this branch): the Beastmaster
        -- "(N)% Increased Aspect of the {Lynx,Shark,Viper,Boar} Effect" family
        -- (49 rolled ModCache rows) was un-baked so the new specialModList
        -- handlers live-parse them into per-buff INC effect scalars. Those rows
        -- leave the silent set AND leave ModCache entirely (deleted, not re-baked),
        -- so total and silent both drop by 49; parsed/neutralized are unchanged.
        -- Baselines were ALSO refreshed against the current worktree ModCache,
        -- which had drifted from the older hard-coded snapshot (the tool is the
        -- source of truth: re-run enumerate_silent_failures.py to reproduce).
        --   total  16452 -> 16403   silent 1994 -> 1945
        --   b-dm-numeric 114 -> 65  (49 aspect-effect rows removed)
        -- 2026-07-06 increased-healing-effectiveness-alias (this branch): the bare
        -- skill-tree node stat "(N)% Increased Healing" (NO "Effectiveness" word;
        -- Blossoming Garden / Blessed Springs / Improved Blessing / Violent Squall in
        -- TreeData tree_0, Redemption / Virtue of Patience in tree_2 -- each node's own
        -- description says it "increases healing effectiveness") was a silent failure:
        -- the generic "increased X" path found no modName for the remainder "healing"
        -- (only "healing effectiveness" -> HealingEffectiveness exists). A new whole-line
        -- specialModList handler live-parses it into INC HealingEffectiveness; the 6
        -- rolled ModCache rows were DELETED (not re-baked), so total/silent both drop by
        -- 6, parsed/neutralized unchanged. The "30% Totem Increased Healing" row (a
        -- different, Totem-prefixed string the handler does NOT match) is intentionally
        -- LEFT baked. Re-ran the tool against this worktree ModCache; the pristine dev
        -- ModCache actually enumerates to 16402/1944 (a 1-row drift from the older
        -- hard-coded 16403/1945 snapshot -- the tool is the source of truth), so the
        -- post-change numbers below are pristine-minus-6:
        --   total  16402 -> 16396   silent 1944 -> 1938
        --   a2-numeric-real 617 -> 611  (6 increased-healing rows removed)
        -- 2026-07-06 effect-of-buff-on-you-bare-alias (this branch): the bare
        -- "+N% Effect of {Haste,Frenzy} on You" affixes (NO "increased" word) were
        -- silent failures -- ModCache baked {{}," Effect of  on You "} (buff name
        -- stripped by the skill-name post-scan). The "increased" rendering already
        -- parsed to <Buff>Effect INC (ModCache: "14% increased Effect of Haste on You"
        -- -> HasteEffect INC 14). A new whole-line specialModList handler per buff
        -- live-parses the bare form into INC HasteEffect / FrenzyEffect (consumed at
        -- CalcPerform.lua:1216 / :1234). The 24 rolled bare-form ModCache rows were
        -- DELETED (not re-baked), so total/silent both drop by 24, parsed/neutralized
        -- unchanged. All 24 sat in c-dm-infra (their dm match is the range affix line),
        -- draining c-dm-infra 220 -> 196.
        --   total  16396 -> 16372   silent 1938 -> 1914
        --   c-dm-infra 220 -> 196  (24 effect-of-buff bare rows removed)
        -- 2026-07-06 aspect-effect-bare-alias + effect-of-buff-signed-value (this
        -- branch): surfaced by the cross-build save sweep (50 real .epoch builds run
        -- through parseMod). The bare "+N% Aspect Of The <Beast> Effect" rendering (NO
        -- "increased" word) and the signed "-N% Effect of <Buff> on You" rendering were
        -- silent failures the corpus never exercised. New handlers live-parse both; one
        -- stale bare-aspect ModCache row ("+10% Aspect Of The Shark Effect", an
        -- a2-numeric-real) was DELETED (not re-baked; no corpus build carries it), so
        -- total/silent both drop by 1, parsed/neutralized unchanged.
        --   total  16372 -> 16371   silent 1914 -> 1913
        --   a2-numeric-real 611 -> 610  (1 bare-aspect row removed)
        local EXPECTED_TOTAL          = 16371
        local EXPECTED_PARSED         = 13397
        local EXPECTED_NEUTRALIZED    = 1061
        local EXPECTED_SILENT         = 1913

        local function field(name)
            -- Cheap regex extraction so the spec runs even without dkjson.
            local v = raw:match('"' .. name .. '"%s*:%s*(%-?%d+)')
            assert.is_not_nil(v, "missing metadata field: " .. name)
            return tonumber(v)
        end

        it("total_rows matches baseline", function()
            assert.are.equal(EXPECTED_TOTAL, field("total_rows"))
        end)

        it("parsed_rows matches baseline", function()
            assert.are.equal(EXPECTED_PARSED, field("parsed_rows"))
        end)

        it("neutralized_rows matches baseline", function()
            assert.are.equal(EXPECTED_NEUTRALIZED, field("neutralized_rows"))
        end)

        it("silent_failure_rows matches baseline", function()
            assert.are.equal(EXPECTED_SILENT, field("silent_failure_rows"))
        end)

        it("malformed_rows is zero (parser stays sound)", function()
            assert.are.equal(0, field("malformed_rows"))
        end)

        it("parsed + neutralized + silent == total", function()
            assert.are.equal(field("total_rows"),
                field("parsed_rows") + field("neutralized_rows") + field("silent_failure_rows"))
        end)
    end)

    describe("category breakdown (Phase 3a post-neutralization)", function()
        -- Phase 2 classifier uses key + residue + datamining_match.
        -- Buckets and baselines (post 2026-06-12 discovery-debt refresh; the
        -- -44 above drained every bucket as those affixes left the silent
        -- set):
        -- (2026-07-06 aspect-effect-buff-scalar refresh, against current worktree
        -- ModCache; 49 aspect-effect rows drained b-dm-numeric.)
        -- (2026-07-06 increased-healing-effectiveness-alias: 6 bare "Increased Healing"
        -- rows un-baked -> INC HealingEffectiveness, draining a2-numeric-real 617 -> 611.)
        -- (2026-07-06 effect-of-buff-on-you-bare-alias: 24 bare "Effect of {Haste,Frenzy}
        -- on You" rows un-baked -> INC HasteEffect / FrenzyEffect, draining
        -- c-dm-infra 220 -> 196.)
        --   a1-pure-flavor : 0    (all promoted to neutralized rows)
        --   a2-numeric-real: 611
        --   b-dm-numeric   : 65   (dm-confirmed real numeric, parser gap)
        --   b-parser-gap   : 450
        --   c-dm-infra     : 196  (dm-confirmed real trigger/event)
        --   c-infra-gap    : 592
        local function catCount(cat)
            local n = raw:match('"' .. cat .. '"%s*:%s*(%-?%d+)')
            return tonumber(n)
        end

        it("emits the five remaining Phase 3a buckets", function()
            -- a1-pure-flavor is intentionally absent after Phase 3a.
            assert.is_nil(catCount("a1%-pure%-flavor"))
            assert.is_not_nil(catCount("a2%-numeric%-real"))
            assert.is_not_nil(catCount("b%-dm%-numeric"))
            assert.is_not_nil(catCount("b%-parser%-gap"))
            assert.is_not_nil(catCount("c%-dm%-infra"))
            assert.is_not_nil(catCount("c%-infra%-gap"))
        end)

        it("category counts sum to silent_failure_rows", function()
            local sum = (catCount("a2%-numeric%-real") or 0)
                + (catCount("b%-dm%-numeric") or 0)
                + (catCount("b%-parser%-gap") or 0)
                + (catCount("c%-dm%-infra") or 0)
                + (catCount("c%-infra%-gap") or 0)
            local silent = raw:match('"silent_failure_rows"%s*:%s*(%-?%d+)')
            assert.are.equal(tonumber(silent), sum)
        end)
    end)

    describe("Phase 2 datamining cross-reference", function()
        local function dmField(name)
            local v = raw:match('"' .. name .. '"%s*:%s*(%-?%d+)')
            return tonumber(v)
        end

        it("declares Phase 2", function()
            assert.is_truthy(string.find(raw, '"phase": 2', 1, true))
        end)

        -- These baselines move when ModItem_1_4.json or ModCache.lua
        -- change. Re-run the tool and update in the same commit.
        -- 2026-06-12 refresh: the un-baked procs/idol/conversion rows
        -- dropped their dm matches (374 -> 347) and their canonical range
        -- lines re-surfaced as dm_gap (283 -> 289); ModItem text edits moved
        -- the scanned/unique tallies (9525 -> 9516, 986 -> 974).
        -- 2026-07-06 aspect-effect-buff-scalar refresh (current worktree ModCache):
        -- the 49 un-baked aspect-effect rows dropped their dm matches
        -- (347 -> 285) and their canonical range lines re-surfaced as dm_gap
        -- (289 -> 294). ModItem_1_4.json is unchanged, so lines/unique hold.
        -- 2026-07-06 effect-of-buff-on-you-bare-alias refresh (current worktree ModCache):
        -- the 24 un-baked bare "Effect of {Haste,Frenzy} on You" rows dropped their dm
        -- matches (285 -> 261) and their canonical range lines re-surfaced as dm_gap
        -- (294 -> 296). ModItem_1_4.json is unchanged, so lines/unique hold.
        local EXPECTED_DM_LINES      = 9516
        local EXPECTED_DM_UNIQUE     = 974
        local EXPECTED_SF_MATCHED    = 261
        local EXPECTED_DM_GAP        = 296

        it("moditem_lines_scanned matches baseline", function()
            assert.are.equal(EXPECTED_DM_LINES, dmField("moditem_lines_scanned"))
        end)
        it("moditem_unique_norms matches baseline", function()
            assert.are.equal(EXPECTED_DM_UNIQUE, dmField("moditem_unique_norms"))
        end)
        it("silent_failure_matched matches baseline", function()
            assert.are.equal(EXPECTED_SF_MATCHED, dmField("silent_failure_matched"))
        end)
        it("dm_gap_count matches baseline", function()
            assert.are.equal(EXPECTED_DM_GAP, dmField("dm_gap_count"))
        end)
    end)

    describe("tool source carries the inline regression-guard marker", function()
        -- Validation provenance is retained in maintainer notes.
        toolsIt("enumerate_silent_failures.py keeps the guard ID", function()
            local toolText = readFile("spec/tools/enumerate_silent_failures.py")
            assert.is_truthy(string.find(toolText,
                "@leb-regression-guard: silent-failure-affix-sweep", 1, true),
                "tool must carry the inline guard ID")
        end)
    end)
end)
