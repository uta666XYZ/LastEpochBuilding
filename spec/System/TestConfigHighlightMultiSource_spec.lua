-- @leb-regression-guard:config-highlight-multi-source
-- Phase 4 (2026-05-29, multi-source extension): the canonical first-match-
-- wins shape established in Phase 3 hid additional contributors. A single
-- buff can be evidenced by multiple build elements — two skill subtree
-- nodes both mentioning "you have haste", a passive node + an item
-- affix both granting Frenzy, etc. Phase 4's multi-source extension
-- changes the attribution shape to collect ALL hits while preserving
-- the Phase 3 `attrib.source` / `attrib.line` canonical-first mirrors
-- for backward compatibility.
--
-- API shape (backward-compatible):
--   detected[buffName] = {
--       source  = <first hit's source>,    -- mirror of sources[1].source
--       line    = <first hit's line>,      -- mirror of sources[1].line
--       sources = {                        -- ALL hits, append order
--           { source = "passive node 'A'",            line = "..." },
--           { source = "skill subtree 'X' node 'Y'",  line = "..." },
--           ...
--       },
--   }
--
-- detectMatchingPattern returns the same shape on hit, nil on miss.
--
-- Invariants this spec locks:
--   (1) ConfigTab.lua carries the Phase 4 multi-source inline guard marker.
--   (2) An `addBuffSource(detected, buffName, source, line)` helper is the
--       single write site for Pass 1 / 2 / 3 of detectGrantedBuffs.
--   (3) Pass 1 / 2 / 3 each call addBuffSource and DO NOT carry the
--       Phase 3 `if not detected[buff.name]` first-match-wins guard.
--   (4) Initial detected[buffName] is `{ source = <first>, line = <first>,
--       sources = {} }` then the first source is appended — locking the
--       sources[1] / source / line mirror invariant.
--   (5) detectMatchingPattern accumulates `result.sources` rather than
--       returning on first hit; result init mirrors entry.source / entry.line.
--   (6) Both tooltip render hooks (suggestBuff + suggestPattern) branch on
--       `#attrib.sources >= 2` to emit a "Sources:" multi-line trailer and
--       fall back to the Phase 3 single-line "Source: ..." form otherwise.
--   (7) Multi-source trailer uses ASCII hyphen (NOT em-dash) — the same
--       LEB-tooltip-font constraint from Phase 3 still applies.
--
-- See REGRESSION_GUARDS.md "config-highlight-multi-source".

describe("ConfigHighlightMultiSource", function()
    local function readFile(path)
        local f = io.open(path, "r")
        if not f then return nil end
        local s = f:read("*a"); f:close()
        return s
    end

    local cfgTabSrc
    setup(function()
        cfgTabSrc = readFile("Classes/ConfigTab.lua")
        assert.is_not_nil(cfgTabSrc, "must read Classes/ConfigTab.lua")
    end)

    it("Phase 4 multi-source inline guard marker is present", function()
        assert.is_truthy(cfgTabSrc:find("@leb%-regression%-guard:config%-highlight%-multi%-source", 1, false),
            "Classes/ConfigTab.lua must carry the Phase 4 multi-source inline guard marker")
    end)

    it("addBuffSource helper exists and initialises canonical-first mirrors", function()
        local startIdx = cfgTabSrc:find("local function addBuffSource", 1, true)
        assert.is_not_nil(startIdx, "addBuffSource helper must be declared")
        local nextFn = cfgTabSrc:find("\n%s*local function ", startIdx + 1)
        local fnBody = cfgTabSrc:sub(startIdx, nextFn or #cfgTabSrc)
        -- Signature: (detected, buffName, source, line)
        assert.is_truthy(fnBody:find("addBuffSource(detected, buffName, source, line)", 1, true),
            "addBuffSource signature must be `(detected, buffName, source, line)`")
        -- Init shape: { source, line, sources = {} } on first call.
        assert.is_truthy(fnBody:find("source%s*=%s*source", 1, false),
            "addBuffSource init must mirror first call's `source`")
        assert.is_truthy(fnBody:find("line%s*=%s*line", 1, false),
            "addBuffSource init must mirror first call's `line`")
        assert.is_truthy(fnBody:find("sources%s*=%s*{%s*}", 1, false),
            "addBuffSource init must create an empty `sources` array")
        -- Append on every call (including the first).
        assert.is_truthy(fnBody:find("t_insert(entry.sources", 1, true),
            "addBuffSource must append to entry.sources via t_insert")
    end)

    it("Pass 1 calls addBuffSource and DROPS the first-match-wins guard", function()
        local pass1Block = cfgTabSrc:match(
            "for nodeId, node in pairs%(self%.build%.spec%.allocNodes%) do(.-)\n%s*end%s*\n%s*%-%- @leb%-regression%-guard:config%-highlight%-skill%-loadout%-scan")
        assert.is_not_nil(pass1Block, "Pass 1 loop must be locatable")
        assert.is_truthy(pass1Block:find("addBuffSource(detected, buff.name", 1, true),
            "Pass 1 must call addBuffSource (single write site)")
        -- The Phase 3 first-match-wins guard `if not detected[buff.name]
        -- and lower:match(buff.pat) then` must be GONE — Phase 4 multi-
        -- source requires every hit to be appended.
        assert.falsy(pass1Block:find("not detected[buff.name]", 1, true),
            "Pass 1 must NOT carry the first-match-wins `not detected[buff.name]` guard anymore")
    end)

    it("Pass 2 (skill loadout) calls addBuffSource and DROPS first-match guard", function()
        -- Anchor on Pass 2's unique code path (if group.displaySkillList).
        local pass2Block = cfgTabSrc:match(
            "if group%.displaySkillList(.-)@leb%-regression%-guard:config%-highlight%-item%-modlist%-scan")
        assert.is_not_nil(pass2Block, "Pass 2 block must be locatable")
        assert.is_truthy(pass2Block:find("addBuffSource(detected, buff.name", 1, true),
            "Pass 2 must call addBuffSource")
        assert.falsy(pass2Block:find("not detected[buff.name]", 1, true),
            "Pass 2 must NOT carry the first-match-wins guard")
    end)

    it("Pass 3 (items) calls addBuffSource and DROPS first-match guard", function()
        local pass3Block = cfgTabSrc:match(
            "if self%.build%.itemsTab and self%.build%.itemsTab%.orderedSlots(.-)self%.detectedBuffs%s*=")
        assert.is_not_nil(pass3Block, "Pass 3 block must be locatable")
        assert.is_truthy(pass3Block:find("addBuffSource(detected, buff.name", 1, true),
            "Pass 3 must call addBuffSource")
        assert.falsy(pass3Block:find("not detected[buff.name]", 1, true),
            "Pass 3 must NOT carry the first-match-wins guard")
    end)

    it("detectMatchingPattern accumulates result.sources and does not return on first hit", function()
        local startIdx = cfgTabSrc:find("local function detectMatchingPattern", 1, true)
        assert.is_not_nil(startIdx, "detectMatchingPattern must be declared")
        local nextFn = cfgTabSrc:find("\n%s*local function ", startIdx + 1)
        local fnBody = cfgTabSrc:sub(startIdx, nextFn or #cfgTabSrc)
        -- Init shape matches detected entry: source / line mirrors + sources array
        assert.is_truthy(fnBody:find("result%s*=%s*{%s*source%s*=%s*entry%.source", 1, false),
            "detectMatchingPattern must initialise `result = { source = entry.source, line = entry.line, sources = {} }`")
        assert.is_truthy(fnBody:find("sources%s*=%s*{%s*}", 1, false),
            "result init must include `sources = {}`")
        assert.is_truthy(fnBody:find("t_insert(result.sources", 1, true),
            "detectMatchingPattern must append to result.sources via t_insert")
        -- The Phase 3 `return { source = entry.source, ... }` inside the
        -- loop must be GONE — accumulation is the contract now.
        assert.falsy(fnBody:find("return%s+{%s*source%s*=%s*entry%.source", 1, false),
            "detectMatchingPattern must NOT return inside the for-loop (accumulation, not first-match)")
        -- Final return is `return result` (nil on miss, table on hit).
        assert.is_truthy(fnBody:find("return%s+result", 1, false),
            "detectMatchingPattern must `return result` after the accumulation loop")
    end)

    it("both tooltip closures branch on #attrib.sources >= 2 for multi-source rendering", function()
        local _, multiBranchCount = cfgTabSrc:gsub("#attrib%.sources%s*>=%s*2", "")
        assert.is_true(multiBranchCount >= 2,
            "Both tooltip closures (suggestBuff + suggestPattern) must branch on `#attrib.sources >= 2`; found " .. tostring(multiBranchCount))
        -- The multi-source branch must emit a "Sources:" header (plural).
        local _, sourcesHeaderCount = cfgTabSrc:gsub('"\\n%^xFFAA00Sources:"', "")
        assert.is_true(sourcesHeaderCount >= 2,
            "Both tooltip closures must emit a `\\n^xFFAA00Sources:` header in the multi-source branch; found "
                .. tostring(sourcesHeaderCount))
        -- And iterate `attrib.sources` with `for _, s in ipairs(...)`.
        local _, iterCount = cfgTabSrc:gsub("for _, s in ipairs%(attrib%.sources%) do", "")
        assert.is_true(iterCount >= 2,
            "Both tooltip closures must iterate `attrib.sources` with `for _, s in ipairs(attrib.sources)`; found "
                .. tostring(iterCount))
    end)

    it("single-source fallback (Phase 3 form) is preserved for #sources == 1 and legacy callers", function()
        -- The single-source branch is the `elseif` arm reading attrib.source
        -- / attrib.line. This guarantees the Phase 3 tooltip behaviour when
        -- only one source exists (most common case) AND covers the edge
        -- case of a legacy code path producing the older shape.
        local _, singleSourceCount = cfgTabSrc:gsub('"\\n%^xFFAA00Source: " %.%. attrib%.source', "")
        assert.is_true(singleSourceCount >= 2,
            "Both tooltip closures must keep the Phase 3 `\\n^xFFAA00Source: ` single-line trailer as fallback; found "
                .. tostring(singleSourceCount))
    end)

    it("multi-source trailer must use ASCII hyphen / colon separators, NOT em-dash (LEB font U+2014 trap)", function()
        -- The Phase 3 review caught U+2014 rendering as the literal fallback
        -- "[U+2014]" because LEB tooltip font has no em-dash glyph. The
        -- Phase 4 multi-source code MUST inherit the same constraint.
        for line in cfgTabSrc:gmatch("[^\n]+") do
            if line:find("trailer", 1, true) and line:find("%.%.") then
                assert.falsy(line:find("\xe2\x80\x94", 1, true),
                    "tooltip trailer expression must not contain em-dash U+2014; offending line: " .. line)
            end
        end
    end)

    it("Phase 3 single-source render contract is intact for the 1-source case", function()
        -- This is the Phase 3 assertion: when only one source exists, the
        -- tooltip MUST render `\n^xFFAA00Source: <source> - '<line>'`.
        -- The literal `" - '" .. <line> .. "'"` form is locked. Phase 4
        -- multi-source uses different iteration variable name (`s.line`
        -- vs `attrib.line`); we check the legacy form survives in the
        -- single-source `elseif` arm.
        local _, hyphenCount = cfgTabSrc:gsub('%.%. " %- \'" %.%. attrib%.line %.%. "\'"', "")
        assert.is_true(hyphenCount >= 2,
            "Single-source fallback must keep `\" - '\" .. attrib.line .. \"'\"` form (ASCII hyphen); found "
                .. tostring(hyphenCount))
    end)
end)
