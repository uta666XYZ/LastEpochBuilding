-- @leb-regression-guard: unique-shared-rollids-not-independent
-- Locks the roll-grouping rule for unique/set items whose game source gives
-- EVERY rollable mod the same `rollID`: those mods roll TOGETHER off a single
-- saved roll value, so LEB's `rollIds` array must repeat that id, never
-- enumerate 0,1,2,3.
--
-- WHY THIS IS NOT COSMETIC
-- `rollID` is not a line index -- it is a roll-group id. The offline-save
-- importer reads `d[uniqueIDIndex + 2 + rollId]` (ImportTab.lua, guard
-- `unique-inherent-not-crafted` sits on the same loop) out of a FIXED 8-byte
-- roll region (see guard `import-fused-affix-overrun`, nbAffixesIndex =
-- uniqueIDIndex + 2 + 8). Enumerating 0,1,2,3 against a game that only ever
-- writes roll slot 0 therefore reads unwritten bytes -> `{range: 0}` -> every
-- mod after the first imports at its MINIMUM. Keplahan's Cryolith at a 0.60
-- roll imported as Dex 6 (should be 10), Health 60 (74), Crit Chance 25% (40%).
--
-- IN-GAME GROUNDING (this is the gate -- datamine alone is NOT sufficient here)
-- For each item below, every rolled mod sits at an IDENTICAL fraction within
-- its own range, and the fraction differs per item -- which is only possible if
-- one roll drives them all:
--   451 Doppelganger's Mimicry  f~0.22  (22/20-30, 6.7/6-9, 67/60-90, 17/14-28)
--   459 Artifice of Devastation f~0.79  (43/24-48, 36/20-40, 43/24-48, 2/1-2)
--   460 Laup's Path             f~0.75  (8/5-9, 21/10-25, 2/1-2)
--   467 Keplahan's Pyrolith     f~0.06  (32/30-60, 6/6-12, 21/20-40, 16/15-30)
--   468 Keplahan's Cryolith     f~0.60  (48/30-60, 10/6-12, 74/60-84, 40/25-50)
--
-- DO NOT extend CANONICAL from datamine alone. `mods[].rollID` is unreliable in
-- the export for some items: Apiarist's Suit (78) reports every rollID as 0 yet
-- its own tooltipDescriptions reference rollID 3 and 5, so the export has
-- collapsed real roll groups there. Only add an id after in-game roll-fraction
-- evidence says the mods move together.
--
-- ^ That collapse claim is now CONFIRMED in-game (2026-07-17), and it yielded the
-- general rule below. See IN_GAME_SOLVED.
--
-- THE COLLAPSE RULE (validated on 8 items: the 5 CANONICAL + 77/78/79)
-- For a unique whose export rollIDs are ALL-ZERO, the true rollIds are 0 for
-- every rolled mod EXCEPT those named by a `tooltipDescriptions` "[min,max,N]"
-- triple, which take rollID N -- and their hideInTooltip minion-mirror shares it.
-- The export collapses non-zero rollIDs to 0; the tooltipDescriptions preserve
-- them. Across all 471 exported uniques only 78 (cites 3,5), 79 (cites 1) and
-- 243 Dragonsong (cites 7) reference a rollID absent from their own mods.
-- N is a rollID, NOT a mod index: over all 162 exported triples the rollID
-- reading matches 152/162 vs 86/162 for mod-index (allowing the x100 percent
-- scale). Do not "simplify" it to a line index.
-- SCOPE: the "everything else is 0" half applies ONLY to all-zero export
-- entries. 243 Dragonsong is a PARTIAL collapse (export keeps {0,1,2,3}); items
-- with surviving structure already agree with LEB 393/410 on ranged mods.
--
-- See REGRESSION_GUARDS.md "unique-shared-rollids-not-independent".

local dkjson = require("dkjson")

describe("UniqueSharedRollIds", function()
    local function readFile(relPath)
        for _, p in ipairs({ relPath, "src/" .. relPath, "../src/" .. relPath }) do
            local f = io.open(p, "r")
            if f then
                local text = f:read("*a")
                f:close()
                return text
            end
        end
        error("must be able to open " .. relPath)
    end

    -- uniqueID -> in-game-confirmed single shared roll group.
    local CANONICAL = {
        [451] = "Doppelganger's Mimicry",
        [459] = "Artifice of Devastation",
        [460] = "Laup's Path",
        [467] = "Keplahan's Pyrolith",
        [468] = "Keplahan's Cryolith",
    }

    -- Validation provenance is retained in maintainer notes.
    local IN_GAME_SOLVED = {
        [77]  = { name = "Apiarist's Smoker", rollIds = { 0, 0, nil, 0, 0, 0 }, n = 6,
                  src = "Data/Set/set_1_4.json" },
        [78]  = { name = "Apiarist's Suit",   rollIds = { 0, 0, 0, 3, 3, 5, 5, 0, 0 }, n = 9,
                  src = "Data/Set/set_1_4.json" },
        [79]  = { name = "Apiarist's Comb",   rollIds = { 0, 1, 0, 0, 0 }, n = 5,
                  src = "Data/Set/set_1_4.json" },
        [175] = { name = "Omnis",             rollIds = { 0, 1, 2, 3, 4, 5, 6, 0 }, n = 8,
                  src = "Data/Uniques/uniques_1_4.json" },
        [454] = { name = "Abandoned Eyes of the Weaver", rollIds = { nil, nil, 0, 2, 3 }, n = 5,
                  src = "Data/Set/set_1_4.json" },
        [229] = { name = "Roots of Vithrasil", rollIds = { 0, 0, 0, nil, 0 }, n = 5,
                  src = "Data/Uniques/uniques_1_4.json" },
        [270] = { name = "Hive Mind", rollIds = { 0, 1, 2, nil, nil, nil, 0 }, n = 7,
                  src = "Data/Uniques/uniques_1_4.json" },
    }

    -- 77/78/79/454 are SET items and live ONLY in Data/Set/set_1_4.json; 175 is a plain
    -- unique in Data/Uniques/uniques_1_4.json. Each entry names its own live file rather
    -- than sweeping all SOURCES, because the entries under ids 77/78/79 in
    -- Data/Uniques/uniques.json are pre-rework STUBS of different items ("Bee Keeper
    -- Helmet/Armor/Belt", one rangeless mod each, rollIds [null]) -- deliberately NOT
    -- synced, so asserting there would drag a stale generation into the guard.

    -- Live data is uniques_<latestTreeVersion>.json merged with set_<ver>.json
    -- (Data.lua). uniques.json is the superset kept in sync so the two never
    -- disagree about a shared-roll item.
    local SOURCES = {
        { path = "Data/Uniques/uniques.json",     keyedByUniqueId = true },
        { path = "Data/Uniques/uniques_1_4.json", keyedByUniqueId = true },
        { path = "Data/Set/set_1_4.json",         keyedByUniqueId = false },
    }

    local function entriesFor(source)
        local decoded = dkjson.decode(readFile(source.path))
        assert.is_table(decoded)
        local out = {}
        for key, entry in pairs(decoded) do
            if type(entry) == "table" then
                local uid = source.keyedByUniqueId and tonumber(key) or entry.uniqueID
                if uid then
                    out[uid] = entry
                end
            end
        end
        return out
    end

    for _, source in ipairs(SOURCES) do
        describe(source.path, function()
            local entries = entriesFor(source)

            for uid, name in pairs(CANONICAL) do
                local entry = entries[uid]
                if entry then
                    it(("%d %s rolls as one group"):format(uid, name), function()
                        local seen = {}
                        for i, rollId in pairs(entry.rollIds or {}) do
                            if rollId ~= nil then
                                seen[rollId] = true
                                assert.message(("%s mods[%d] must use the shared roll id 0, got %s")
                                    :format(name, i, tostring(rollId)))
                                    .is_equal(0, rollId)
                            end
                        end
                        assert.message(name .. " must have at least one rolled mod")
                            .is_true(next(seen) ~= nil)
                    end)
                end
            end
        end)
    end

    describe("in-game solved rollIds", function()
        local cache = {}
        local function entryFor(want, uid)
            if not cache[want.src] then
                cache[want.src] = entriesFor({
                    path = want.src,
                    keyedByUniqueId = (want.src ~= "Data/Set/set_1_4.json"),
                })
            end
            return cache[want.src][uid]
        end

        for uid, want in pairs(IN_GAME_SOLVED) do
            it(("%d %s matches the in-game solved rollIds"):format(uid, want.name), function()
                local entry = entryFor(want, uid)
                assert.message(want.name .. " must exist in " .. want.src).is_table(entry)
                assert.message(("%s: mod count changed (%d -> %d); the solved rollIds are "
                    .. "positional and a re-scrape that adds/removes a mod INVALIDATES them "
                    .. "-- re-capture, do not re-index by hand")
                    :format(want.name, want.n, #entry.mods))
                    .is_equal(want.n, #entry.mods)
                for i = 1, want.n do
                    -- dkjson maps JSON null -> nil (no nullval passed), so a
                    -- rangeless mod's slot is simply absent. tostring() keeps the
                    -- nil-vs-0 distinction legible in the failure message.
                    assert.message(("%s rollIds[%d]: expected %s, got %s (in-game solved by "
                        .. "inverting the tooltip against the item's real roll bytes -- do "
                        .. "not change without a new capture)")
                        :format(want.name, i, tostring(want.rollIds[i]), tostring(entry.rollIds[i])))
                        .is_equal(tostring(want.rollIds[i]), tostring(entry.rollIds[i]))
                end
            end)
        end

        -- The pre-capture bug: LEB enumerated these per line (78 was
        -- 0,1,2,3,3,4,4,5,6), which imported Fehm's Suit armor as 395 instead of
        -- 260 and its Poison Res as 53% instead of 68%. Catch the shape itself.
        -- Omnis is the subtle one: 0,1,2,3,4,5,6,0 is ascending for SEVEN mods and
        -- only the eighth breaks it, so a lazy "restore the enumeration" edit lands
        -- exactly on the bug this catches.
        it("no solved entry enumerates independent roll ids", function()
            for uid, want in pairs(IN_GAME_SOLVED) do
                local entry = entryFor(want, uid)
                if entry then
                    local ascending = true
                    for i = 1, want.n do
                        if entry.rollIds[i] ~= i - 1 then
                            ascending = false
                            break
                        end
                    end
                    assert.message(("%s: rollIds is a bare 0..n-1 enumeration, which is the "
                        .. "exact bug this guard exists to stop"):format(want.name))
                        .is_false(ascending)
                end
            end
        end)
    end)

    -- The bug this guard replaces enumerated rollIds per line. Catch the shape
    -- directly so a regeneration that reintroduces it fails loudly, in the live
    -- files, regardless of which entry it lands on.
    it("no canonical entry enumerates independent roll ids", function()
        for _, source in ipairs(SOURCES) do
            for uid, name in pairs(CANONICAL) do
                local entry = entriesFor(source)[uid]
                if entry then
                    local maxRoll = -1
                    for _, rollId in pairs(entry.rollIds or {}) do
                        if rollId ~= nil and rollId > maxRoll then
                            maxRoll = rollId
                        end
                    end
                    assert.message(("%s in %s: rollIds must not exceed 0 (found %d)")
                        :format(name, source.path, maxRoll))
                        .is_true(maxRoll <= 0)
                end
            end
        end
    end)

    -- @leb-regression-guard: hive-mind-pen-tenth-rounding
    -- Data lock: Hive Mind (270) "+(4-6)% ... Penetration ... per Dexterity" must
    -- carry the {rounding:Tenth} tag. In-game it reads 4.4% (Tenth), but the pen
    -- affix branch in ItemTools defaults to Hundredth (whole 4%) without the tag.
    -- A datamine-driven regen of uniques_1_4.json could silently drop this manual
    -- annotation, re-introducing the 4% vs 4.4% mismatch. Behaviour is locked in
    -- TestItemTools_spec; this locks that the tag actually ships in the data.
    it("Hive Mind (270) Penetration-per-Dexterity mod carries {rounding:Tenth}", function()
        local entry = entriesFor({ path = "Data/Uniques/uniques_1_4.json", keyedByUniqueId = true })[270]
        assert.is_table(entry)
        local penMod
        for _, m in ipairs(entry.mods) do
            if m:find("Penetration for Bees per Dexterity") then penMod = m end
        end
        assert.message("Hive Mind must have the Penetration-per-Dexterity mod").is_string(penMod)
        assert.message("Hive Mind Pen mod must carry {rounding:Tenth} (in-game shows 4.4%, "
            .. "not 4%); a datamine regen may have dropped it: " .. tostring(penMod))
            .is_truthy(penMod:find("{rounding:Tenth}", 1, true))
    end)
end)
