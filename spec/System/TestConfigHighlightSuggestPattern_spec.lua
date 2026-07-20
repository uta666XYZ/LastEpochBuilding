-- @leb-regression-guard:config-highlight-suggest-pattern
-- See REGRESSION_GUARDS.md "config-highlight-suggest-pattern".
-- Validation provenance is retained in maintainer notes.

describe("ConfigHighlightSuggestPattern", function()
    local function readFile(path)
        local f = io.open(path, "r")
        if not f then return nil end
        local s = f:read("*a"); f:close()
        return s
    end

    it("ConfigTab.lua holds the corpus walker, the plain-substring matcher and the inline guard", function()
        local src = readFile("Classes/ConfigTab.lua")
        assert.is_not_nil(src, "must be able to read Classes/ConfigTab.lua")
        assert.is_truthy(src:find("@leb%-regression%-guard:config%-highlight%-suggest%-pattern", 1, false),
            "ConfigTab.lua must carry the inline guard marker")
        assert.is_truthy(src:find("local function getAllocNodeTextCorpusLowered", 1, true),
            "ConfigTab.lua must define the corpus walker")
        assert.is_truthy(src:find("local function detectMatchingPattern", 1, true),
            "ConfigTab.lua must define the matcher")
        -- Plain (non-regex) substring matching: the `,1, true` third arg to
        -- string:find is what locks the contract. The variable name on the
        -- LHS was `line` in Phase 1 and is `entry.text` post-Phase-3 (the
        -- corpus entry shape gained `text` / `line` / `source` fields for
        -- attribution). Match the invariant tail rather than the LHS.
        assert.is_truthy(src:find(':find(lp, 1, true)', 1, true),
            "matcher must use plain (non-regex), case-insensitive substring matching (find(needle, 1, true))")
        assert.is_truthy(src:find("statText:lower()", 1, true),
            "corpus must be lowercased once at gather time so per-pattern matching is cheap")
    end)

    it("the render block highlights with the same orange ^xFFAA00 as suggestBuff", function()
        local src = readFile("Classes/ConfigTab.lua")
        assert.is_not_nil(src)
        -- Locate the suggestPattern render block specifically (avoids matching the
        -- suggestBuff block by also requiring detectMatchingPattern in scope).
        local block = src:match("if varData%.suggestPattern then.-end%s*\n%s*end%s*\n")
        assert.is_not_nil(block, "ConfigTab.lua must contain the suggestPattern render block")
        assert.is_truthy(block:find("^xFFAA00", 1, true),
            "suggestPattern block must paint the label in the shared orange ^xFFAA00")
        assert.is_truthy(block:find("detectMatchingPattern(pattern)", 1, true),
            "suggestPattern block must drive the orange via detectMatchingPattern")
    end)

    it("the suggestPattern render block is read-only (never assigns to self.input[varData.var])", function()
        local src = readFile("Classes/ConfigTab.lua")
        assert.is_not_nil(src)
        local block = src:match("if varData%.suggestPattern then.-end%s*\n%s*end%s*\n")
        assert.is_not_nil(block)
        -- The whole point of the highlight pivot is "never auto-on". Any
        -- assignment to self.input[...] in this block would re-introduce the
        -- fake-DPS risk and must fail this assertion.
        assert.falsy(block:find("self.input%[varData.var%]%s*="),
            "suggestPattern block must NOT assign to self.input[varData.var] — highlight only")
    end)

    it("five immediately-targeted ConfigOptions entries declare suggestPattern with the audited phrases", function()
        local src = readFile("Modules/ConfigOptions.lua")
        assert.is_not_nil(src, "must read Modules/ConfigOptions.lua")

        local function entrySuggest(varName)
            -- Capture the single-line entry that starts with `{ var = "<name>"`
            -- and extract its suggestPattern table literal text (if any).
            local pattern = '{%s*var%s*=%s*"' .. varName .. '"[^\n]-suggestPattern%s*=%s*(%b{})'
            return src:match(pattern)
        end

        local cursed = entrySuggest("conditionCursed")
        assert.is_not_nil(cursed, "conditionCursed must declare suggestPattern")
        assert.is_truthy(cursed:find("doubled if cursed", 1, true),
            "conditionCursed suggestPattern must include 'doubled if cursed' (ch0fs-20 Death from Below)")

        local selfCount = entrySuggest("multiplierCurseOnSelf")
        assert.is_not_nil(selfCount, "multiplierCurseOnSelf must declare suggestPattern")

        local enemyCursed = entrySuggest("conditionEnemyCursed")
        assert.is_not_nil(enemyCursed, "conditionEnemyCursed must declare suggestPattern")
        assert.is_truthy(enemyCursed:find("doubled if cursed", 1, true),
            "conditionEnemyCursed must also flag on 'doubled if cursed' (ch0fs-14 Eradication OR-semantics)")

        local enemyStacks = entrySuggest("multiplierEnemyCurseStacks")
        assert.is_not_nil(enemyStacks, "multiplierEnemyCurseStacks must declare suggestPattern")

        local kr = entrySuggest("conditionKilledRecently")
        assert.is_not_nil(kr, "conditionKilledRecently must declare suggestPattern")
        assert.is_truthy(kr:find("doubled if killed recently", 1, true),
            "conditionKilledRecently must include 'doubled if killed recently' (srtor-11 Taste for Flesh)")
    end)

    it("game-file: 1.4 trees still carry the audited 'Doubled if X' notScalingStats this feature depends on", function()
        -- If a future tree update renames the phrasing, suggestPattern needs
        -- updating too — fail loudly here rather than silently lose the
        -- highlight on the canonical nodes.
        local tree3 = readFile("TreeData/1_4/tree_3.json")
        assert.is_not_nil(tree3, "must read TreeData/1_4/tree_3.json")
        assert.is_truthy(tree3:find(" Doubled if Cursed", 1, true),
            "1.4 tree_3.json must still contain ' Doubled if Cursed' for the suggestPattern to match")

        local foundKR = false
        for _, p in ipairs({"TreeData/1_4/tree_0.json","TreeData/1_4/tree_1.json","TreeData/1_4/tree_2.json","TreeData/1_4/tree_3.json","TreeData/1_4/tree_4.json"}) do
            local s = readFile(p)
            if s and s:find(" Doubled If Killed Recently", 1, true) then foundKR = true; break end
        end
        assert.is_true(foundKR, "some 1.4 tree json must still contain ' Doubled If Killed Recently'")
    end)

    -- Phase 1.5: lock the buffDetectPatterns gap fix (2026-05-29).
    -- Before the fix, four ConfigOptions entries had a suggestBuff value
    -- (FlameWard / EterrasBlessing / DreadShade / ProfaneVeil) but no
    -- matching entry in buffDetectPatterns, so detectGrantedBuffs() could
    -- never return them and the orange-highlight never fired for those
    -- four configs. The fix is data-only — append four rows to the
    -- buffDetectPatterns table — but a regression must fail this spec
    -- rather than silently re-introduce the latent gap.
    it("Phase 1.5: buffDetectPatterns contains rows for every suggestBuff value declared in ConfigOptions", function()
        local cfgTabSrc = readFile("Classes/ConfigTab.lua")
        assert.is_not_nil(cfgTabSrc, "must read Classes/ConfigTab.lua")
        local cfgOptsSrc = readFile("Modules/ConfigOptions.lua")
        assert.is_not_nil(cfgOptsSrc, "must read Modules/ConfigOptions.lua")

        -- Collect every suggestBuff = "X" value declared in ConfigOptions.
        local declaredBuffs = {}
        for buff in cfgOptsSrc:gmatch('suggestBuff%s*=%s*"([^"]+)"') do
            declaredBuffs[buff] = true
        end
        -- Sanity: each of the four Phase-1.5 targets must still be declared
        -- (otherwise the gap may have been "fixed" by deleting the entry).
        for _, expected in ipairs({"FlameWard", "EterrasBlessing", "DreadShade", "ProfaneVeil"}) do
            assert.is_true(declaredBuffs[expected] == true,
                "ConfigOptions must still declare suggestBuff = \"" .. expected .. "\"")
        end

        -- Extract the buffDetectPatterns table block from ConfigTab.lua.
        -- `%b{}` is the balanced-braces operator, so nested `{ name = ... }`
        -- rows are walked correctly instead of stopping at the first `}`.
        local block = cfgTabSrc:match("local buffDetectPatterns%s*=%s*(%b{})")
        assert.is_not_nil(block, "ConfigTab.lua must define local buffDetectPatterns")

        -- Every declared suggestBuff must have a matching `name = "<X>"` row
        -- in buffDetectPatterns; otherwise detectGrantedBuffs() can never
        -- return it and the highlight is structurally dead.
        for buff, _ in pairs(declaredBuffs) do
            local needle = 'name%s*=%s*"' .. buff:gsub("%W", "%%%1") .. '"'
            assert.is_truthy(block:find(needle),
                "buffDetectPatterns must contain a row for suggestBuff value \"" .. buff
                    .. "\" — otherwise detectGrantedBuffs() returns nil and the highlight is dead")
        end
    end)

    it("Phase 1.5: each new pattern actually matches grant phrasing in 1.4 tree json (not just consumption)", function()
        -- The new patterns target real grant phrasing audited in 1.4 trees;
        -- detectGrantedBuffs strips lines containing "while/if you have" so
        -- the matches we care about must be in non-consumption sentences.
        -- Profane Veil is the documented exception (zero non-consumption
        -- mentions in 1.4 — registered for symmetry / forward-compat only).
        local function anyTreeContainsGrant(needle)
            for _, p in ipairs({"TreeData/1_4/tree_0.json","TreeData/1_4/tree_1.json","TreeData/1_4/tree_2.json","TreeData/1_4/tree_3.json","TreeData/1_4/tree_4.json"}) do
                local s = readFile(p)
                if s then
                    -- crude line walk: lowercase and reject if "while/if you have" precedes the needle
                    local lower = s:lower()
                    local searchPos = 1
                    while true do
                        local hitStart, hitEnd = lower:find(needle, searchPos, true)
                        if not hitStart then break end
                        -- look back ~30 chars for the exclusion phrases
                        local backStart = math.max(1, hitStart - 30)
                        local prefix = lower:sub(backStart, hitStart - 1)
                        if not prefix:find("while you have", 1, true) and not prefix:find("if you have", 1, true) then
                            return true
                        end
                        searchPos = hitEnd + 1
                    end
                end
            end
            return false
        end

        assert.is_true(anyTreeContainsGrant("flame ward"),
            "1.4 trees must contain at least one grant-phrasing mention of 'flame ward'")
        assert.is_true(anyTreeContainsGrant("eterra's blessing"),
            "1.4 trees must contain at least one grant-phrasing mention of \"eterra's blessing\"")
        assert.is_true(anyTreeContainsGrant("dread shade"),
            "1.4 trees must contain at least one grant-phrasing mention of 'dread shade'")
        -- ProfaneVeil intentionally NOT asserted: zero non-consumption hits
        -- in 1.4 passive trees (documented in the inline comment on
        -- buffDetectPatterns). Future Phase 1.6 will add skill-loadout
        -- scanning to fire the highlight for builds that equip Profane Veil
        -- as an active skill.
    end)
end)
