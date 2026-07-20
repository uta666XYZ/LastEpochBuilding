-- @leb-regression-guard:config-highlight-source-attribution
-- Phase 3 (2026-05-29) of the Config-highlight family. Enriches every
-- detection-positive entry with the source that produced the match — which
-- passive node, which equipped skill, or which equipped item — plus the
-- actual line text that hit.
--
-- API shape changes (backward-compatible because truthy checks still work):
--   * detectGrantedBuffs()[buffName] : boolean true → table { source, line }
--   * detectMatchingPattern(pattern) : boolean       → nil | table { source, line }
--   * getAllocNodeTextCorpusLowered() entries : "lowered string" →
--                                              { text = <lowered>, line = <original>, source = <label> }
--
-- Source label convention (uniform across all 5 detection sites, uses only
-- in-game display names — no internal node ids surfaced to the user):
--   * "passive node 'X'" — Pass 1 of detectGrantedBuffs + Source A of corpus
--   * "skill 'X'"        — Pass 2 of detectGrantedBuffs
--   * "item 'X'"         — Pass 3 of detectGrantedBuffs + Source B of corpus
--
-- The tooltip render hooks on both suggestBuff and suggestPattern read the
-- attribution table and append a "\nSource: <label> — '<line>'" trailer so
-- the user can see exactly which build element triggered the highlight.
--
-- Six coupled invariants this spec locks:
--   (1) detectGrantedBuffs Pass 1 records "passive node '..'" source.
--   (2) detectGrantedBuffs Pass 2 records "skill '..'" source.
--   (3) detectGrantedBuffs Pass 3 records "item '..'" source.
--   (4) detectMatchingPattern returns nil on no match, and `{ source, line }`
--       table on a match (no bare `true` left).
--   (5) Both tooltip render hooks (suggestBuff + suggestPattern) read
--       `attrib.source` / `attrib.line` and emit a "Source: ..." trailer.
--   (6) Backward compatibility: label render hooks still use a plain truthy
--       check on the detection result (table truthy in Lua), and the Phase 1
--       cache key `self.allocNodeTextCorpus` is unchanged so memoization
--       contract holds.
--
-- See REGRESSION_GUARDS.md "config-highlight-source-attribution".

describe("ConfigHighlightSourceAttribution", function()
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

    it("the Phase 3 inline guard marker is present in detectGrantedBuffs", function()
        assert.is_truthy(cfgTabSrc:find("@leb%-regression%-guard:config%-highlight%-source%-attribution", 1, false),
            "Classes/ConfigTab.lua must carry the Phase 3 inline guard marker")
    end)

    it("Pass 1 (passive tree) writes source via getNodeSourceLabel + addBuffSource", function()
        -- Phase 4 multi-source (2026-05-29) moved the actual `detected[buff]
        -- = { ... }` write into the shared `addBuffSource` helper. Pass 1
        -- now calls `addBuffSource(detected, buff.name, <source>, <line>)`
        -- where <source> is `getNodeSourceLabel(nodeId, node)` (Phase 4
        -- skill-subtree attribution) and <line> is `statText` (the original
        -- non-lowered text). The label still uses the in-game node name
        -- only — no internal id like `ch0fs-20` should be surfaced to the
        -- user (Phase 3 review finding 2026-05-29).
        local pass1Block = cfgTabSrc:match(
            "for nodeId, node in pairs%(self%.build%.spec%.allocNodes%) do(.-)\n%s*end%s*\n%s*%-%- @leb%-regression%-guard:config%-highlight%-skill%-loadout%-scan")
        assert.is_not_nil(pass1Block,
            "Pass 1 (passive tree) loop must be locatable in detectGrantedBuffs and use keyed iteration")
        assert.is_truthy(pass1Block:find("addBuffSource(detected, buff.name, getNodeSourceLabel(nodeId, node), statText)", 1, true),
            "Pass 1 must call `addBuffSource(detected, buff.name, getNodeSourceLabel(nodeId, node), statText)`")
        -- Lock the user-facing label format: no `(<id>)` suffix should be
        -- emitted. A regression that re-introduces `tostring(node.id)` into
        -- the source string would surface internal ids to the tooltip.
        assert.falsy(pass1Block:find("tostring(node.id)", 1, true),
            "Pass 1 source label must NOT include `tostring(node.id)` — internal ids are not user-facing")
    end)

    it("Pass 2 (skill loadout) writes a 'skill' source label via addBuffSource", function()
        -- Anchor on Pass 2's unique code path `if group.displaySkillList`
        -- (Phase 4 introduced a second `self.build.skillsTab.socketGroupList`
        -- access in the earlier getTreeIdToSkillName helper which a bare
        -- `if self.build.skillsTab...` regex would otherwise match first).
        local pass2Block = cfgTabSrc:match(
            "if group%.displaySkillList(.-)@leb%-regression%-guard:config%-highlight%-item%-modlist%-scan")
        assert.is_not_nil(pass2Block, "Pass 2 (skill loadout) block must be locatable")
        assert.is_truthy(pass2Block:find('"skill \'"', 1, false),
            "Pass 2 must pass `\"skill '<name>'\"` as the source label arg to addBuffSource")
        assert.is_truthy(pass2Block:find("addBuffSource(detected, buff.name", 1, true),
            "Pass 2 must call addBuffSource (single write site)")
        -- The skillName must be passed as the `line` (4th arg). Locked via
        -- the literal `, skillName)` tail of the call.
        assert.is_truthy(pass2Block:find('"skill \'" .. skillName .. "\'", skillName)', 1, true),
            "Pass 2 must call addBuffSource(..., \"skill '\" .. skillName .. \"'\", skillName)")
    end)

    it("Pass 3 (items) writes a slot-specific source label via addBuffSource", function()
        -- Phase 6 (2026-05-29): the source label is no longer the generic
        -- hardcoded "item '<name>'"; it now flows through getItemSourceKind
        -- (deriving ring / helmet / idol / idol altar / blessing / ... from
        -- item.type). The label is precomputed once per item as `sourceLabel`
        -- and handed to addBuffSource.
        local pass3Block = cfgTabSrc:match(
            "if self%.build%.itemsTab and self%.build%.itemsTab%.orderedSlots(.-)self%.detectedBuffs%s*=")
        assert.is_not_nil(pass3Block, "Pass 3 (items) block must be locatable")
        assert.is_truthy(pass3Block:find("getItemSourceKind(item, slot.slotName)", 1, true),
            "Pass 3 must derive the source kind via getItemSourceKind(item, slot.slotName)")
        assert.is_truthy(pass3Block:find("addBuffSource(detected, buff.name, sourceLabel, modLine.line)", 1, true),
            "Pass 3 must call addBuffSource(..., sourceLabel, modLine.line) with the slot-specific label")
        -- The old hardcoded generic "item '" literal must be gone from Pass 3.
        assert.falsy(pass3Block:find('"item \'" .. itemName', 1, true),
            "Pass 3 must NOT hardcode the generic \"item '\" .. itemName label anymore (Phase 6)")
    end)

    it("detectMatchingPattern returns nil on miss, attribution table on hit", function()
        -- Phase 4 multi-source (2026-05-29) changed the function body from
        -- "return on first hit" to "accumulate into result.sources and
        -- return at the end". The canonical first-source mirrors live in
        -- `result = { source = entry.source, line = entry.line, ... }`.
        -- That initialiser still satisfies the Phase 3 invariant that
        -- the return shape carries `source = entry.source`. Locate the
        -- function start, then scan forward only until the next `local
        -- function` declaration so nested for-loops don't confuse the
        -- lazy `.-` anchor.
        local startIdx = cfgTabSrc:find("local function detectMatchingPattern", 1, true)
        assert.is_not_nil(startIdx, "detectMatchingPattern must be declared")
        -- Cap the search window at the next `local function` (or EOF).
        local nextFn = cfgTabSrc:find("\n%s*local function ", startIdx + 1)
        local fnBody = cfgTabSrc:sub(startIdx, nextFn or #cfgTabSrc)

        -- The result init must carry source = entry.source (Phase 3 inv).
        assert.is_truthy(fnBody:find("source%s*=%s*entry%.source", 1, false),
            "detectMatchingPattern must init result with `source = entry.source`")
        -- And the final return must propagate it (Phase 4: `return result`,
        -- where result is nil on miss or the accumulator table on hit).
        assert.is_truthy(fnBody:find("return%s+result", 1, false),
            "detectMatchingPattern must `return result` (nil on miss, table on hit)")
        -- The Phase 1 boolean `true` literal must NOT remain as a return.
        assert.falsy(fnBody:find("return%s+true[%s\n]", 1, false),
            "detectMatchingPattern must no longer return bare boolean true")
        -- The Phase 3 `return { ... }` from inside the for-loop must be
        -- GONE — Phase 4 multi-source accumulates instead.
        assert.falsy(fnBody:find("return%s+{%s*source%s*=%s*entry%.source", 1, false),
            "detectMatchingPattern must NOT return `{ source = entry.source, ... }` from inside the loop (Phase 4 accumulates)")
    end)

    it("getAllocNodeTextCorpusLowered entries carry `text` + `line` + `source` fields", function()
        local fnBody = cfgTabSrc:match("local function getAllocNodeTextCorpusLowered.-self%.allocNodeTextCorpus%s*=%s*lines")
        assert.is_not_nil(fnBody, "corpus builder body must be locatable")
        assert.is_truthy(fnBody:find("text%s*=%s*statText:lower", 1, false),
            "Source A entries must store `text = statText:lower()`")
        assert.is_truthy(fnBody:find("line%s*=%s*statText", 1, false),
            "Source A entries must store the original (non-lowered) `line = statText`")
        assert.is_truthy(fnBody:find('source%s*=%s*sourceLabel', 1, false) or fnBody:find('"passive node', 1, true),
            "Source A entries must store a source label including 'passive node'")
        assert.is_truthy(fnBody:find("text%s*=%s*modLine%.line:lower", 1, false),
            "Source B entries must store `text = modLine.line:lower()`")
        assert.is_truthy(fnBody:find("line%s*=%s*modLine%.line", 1, false),
            "Source B entries must store the original `line = modLine.line`")
        -- Phase 6: Source B label now flows through getItemSourceKind
        -- (slot-specific) instead of a hardcoded "item '" literal.
        assert.is_truthy(fnBody:find("getItemSourceKind(item, slot.slotName)", 1, true),
            "Source B must derive the source kind via getItemSourceKind(item, slot.slotName)")
        assert.is_truthy(fnBody:find("self%.allocNodeTextCorpus%s*=%s*lines", 1, false),
            "Phase 1 cache key `self.allocNodeTextCorpus` must be preserved")
    end)

    it("both tooltip render hooks read attribution and emit a 'Source:' trailer", function()
        -- The suggestBuff and suggestPattern tooltip closures must both
        -- consult the attribution table to build a "\nSource: <label>"
        -- trailer when one is available.
        local _, sourceCount = cfgTabSrc:gsub('"\\nSource: " %.%.', "")
        -- Fallback for differing escape: Lua string literal `\nSource: `
        local plainCount = 0
        for _ in cfgTabSrc:gmatch("Source: ") do plainCount = plainCount + 1 end
        assert.is_true(plainCount >= 2,
            "both tooltip closures (suggestBuff + suggestPattern) must emit a 'Source: ' trailer; found " .. tostring(plainCount))
        -- The trailer must come from the attribution table, not a hardcoded
        -- string — verify both closures read .source.
        local sourceReads = 0
        for _ in cfgTabSrc:gmatch("attrib%.source") do sourceReads = sourceReads + 1 end
        assert.is_true(sourceReads >= 2,
            "both tooltip closures must read attrib.source; found " .. tostring(sourceReads))
    end)

    it("tooltip trailer uses ASCII hyphen, NOT em-dash (LEB font has no U+2014 glyph)", function()
        -- LEB's tooltip font does not include U+2014 (em-dash) — using it
        -- causes the user to see the literal fallback text "[U+2014]" in
        -- the rendered tooltip. The Phase 3 review caught this immediately
        -- after the first in-game test. This assertion locks the ASCII
        -- hyphen `-` in the runtime trailer construction so a future
        -- "let's pretty up the dash" refactor doesn't silently re-break
        -- the tooltip render.
        -- Both render hooks must use the same separator pattern
        -- `" - '" .. attrib.line .. "'"`.
        local sep = " .. \" - '\" .. attrib.line .. \"'\""
        local _, hyphenCount = cfgTabSrc:gsub("%.%. \" %- '\" %.%. attrib%.line %.%. \"'\"", "")
        assert.is_true(hyphenCount >= 2,
            "Both tooltip closures (suggestBuff + suggestPattern) must use ASCII hyphen separator `\" - '\" .. attrib.line .. \"'\"`; found "
                .. tostring(hyphenCount))
        -- And the em-dash form must NOT appear in trailer construction
        -- expressions (em-dashes are still fine in lua source-code comments
        -- that aren't emitted to the runtime tooltip, so we restrict the
        -- check to lines containing `trailer` to avoid false positives).
        for line in cfgTabSrc:gmatch("[^\n]+") do
            if line:find("trailer", 1, true) and line:find("%.%.") then
                assert.falsy(line:find("\xe2\x80\x94", 1, true),
                    "tooltip trailer expression must not contain em-dash U+2014; offending line: " .. line)
            end
        end
    end)

    it("label render hooks use a plain truthy check on the detection result (backward compat)", function()
        -- The label closure for suggestBuff and suggestPattern must not
        -- assume a boolean — they treat the detection result as truthy/falsy.
        -- A table return from detectGrantedBuffs / nil-or-table return from
        -- detectMatchingPattern both satisfy this.
        --
        -- Phase 7 (2026-05-30): the `and not isSuggestActive()` /
        -- `and not isPatternSuggestActive()` gate was REMOVED from the label
        -- closures so the orange highlight persists even when the config is
        -- enabled (see config-highlight-persistent guard). The label is now
        -- a bare truthy check on the detection result.
        assert.is_truthy(cfgTabSrc:find("if detectGrantedBuffs()[buffName] then", 1, true),
            "suggestBuff label hook must highlight on a bare `detectGrantedBuffs()[buffName]` truthy check (Phase 7: no active gate)")
        assert.is_truthy(cfgTabSrc:find("if detectMatchingPattern(pattern) then", 1, true),
            "suggestPattern label hook must highlight on a bare `detectMatchingPattern(pattern)` truthy check (Phase 7: no active gate)")
        -- The old active-gated label form must be gone.
        assert.falsy(cfgTabSrc:find("detectGrantedBuffs()[buffName] and not isSuggestActive()", 1, true),
            "Phase 7: suggestBuff label must NOT gate on `and not isSuggestActive()` anymore")
        assert.falsy(cfgTabSrc:find("detectMatchingPattern(pattern) and not isPatternSuggestActive()", 1, true),
            "Phase 7: suggestPattern label must NOT gate on `and not isPatternSuggestActive()` anymore")
    end)
end)
