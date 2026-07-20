-- @leb-regression-guard:config-highlight-item-modlist-scan
-- Phase 2 (2026-05-29) of the Config-highlight family. Extends both detection
-- mechanisms to ALSO walk equipped items' explicit affix text:
--
--   * detectGrantedBuffs (suggestBuff path): adds a 3rd pass over
--     `build.itemsTab.orderedSlots[*].selItemId → items[id].explicitModLines[*].line`
--     using the same buffDetectPatterns table, no while/if-you-have filter
--     (item affixes that *mention* a buff are themselves the relevance signal,
--     same logic as the Phase 1.6 skill-loadout pass).
--
--   * getAllocNodeTextCorpusLowered (suggestPattern path): widens the corpus
--     from passive-tree-only to passive tree + equipped item modList lines.
--     suggestPattern declarations in ConfigOptions don't change — they are
--     simply matched against a strictly larger corpus, so anything that
--     fired pre-Phase-2 still fires identically.
--
-- Motivation: prior to Phase 2, a build whose curse-relevance signal lives
-- on an item affix ("+12% Damage Against Cursed Enemies" / "Damage Per Curse
-- Stack" / "while you have Haste …") was not flagged by the highlight
-- because the corpus only contained passive-tree node.sd text. Phase 2
-- closes that gap. Both detection paths share the same equipped-only slot
-- iteration (`orderedSlots[*].selItemId`) — walking `itemsTab.items`
-- directly would over-include inventory items the build is not wearing.
--
-- Six coupled invariants this spec locks:
--   (1) ConfigTab.lua holds the item-scan path on the suggestBuff side
--       (third for-loop iterating buffDetectPatterns).
--   (2) ConfigTab.lua holds the item-scan path on the suggestPattern side
--       (corpus extension: explicitModLines walked in
--       getAllocNodeTextCorpusLowered).
--   (3) Both new paths iterate via `orderedSlots[*].selItemId` (equipped-
--       only), NOT via `itemsTab.items` directly (which would include
--       inventory).
--   (4) The suggestBuff item-scan block does NOT apply the `while/if you
--       have` exclusion filter — consumption phrasing on an item affix IS
--       a relevance signal.
--   (5) Pre-existing Phase 1 / 1.5 / 1.6 invariants survive: the passive-
--       tree pass still applies the filter, buffDetectPatterns is now
--       iterated by 3 passes (was 2), and the corpus cache key
--       `self.allocNodeTextCorpus` is unchanged so the Phase 1 single-
--       corpus-per-session contract holds.
--   (6) Source B addition to the corpus uses `explicitModLines[*].line`
--       (the canonical raw-text source built by the import pipeline).
--
-- See REGRESSION_GUARDS.md "config-highlight-item-modlist-scan".

describe("ConfigHighlightItemModListScan", function()
    local function readFile(path)
        local f = io.open(path, "r")
        if not f then return nil end
        local s = f:read("*a"); f:close()
        return s
    end

    it("ConfigTab.lua holds the suggestBuff item-scan path and the inline guard", function()
        local src = readFile("Classes/ConfigTab.lua")
        assert.is_not_nil(src, "must read Classes/ConfigTab.lua")
        assert.is_truthy(src:find("@leb%-regression%-guard:config%-highlight%-item%-modlist%-scan", 1, false),
            "ConfigTab.lua must carry the Phase 2 inline guard marker")
        -- The suggestBuff Pass 3 lives in detectGrantedBuffs and reads
        -- explicitModLines off equipped items. Locate the block bounded by
        -- the closing `end` that precedes the final `self.detectedBuffs = detected`
        -- assignment.
        assert.is_truthy(src:find("self%.build%.itemsTab", 1, false),
            "Pass 3 must access build.itemsTab")
        assert.is_truthy(src:find("orderedSlots", 1, true),
            "Pass 3 must iterate orderedSlots (equipped-only) for slot resolution")
        assert.is_truthy(src:find("explicitModLines", 1, true),
            "Pass 3 must read explicitModLines from each equipped item")
    end)

    it("buffDetectPatterns is now iterated by exactly 3 passes (passive tree + skill loadout + items)", function()
        local src = readFile("Classes/ConfigTab.lua")
        assert.is_not_nil(src)
        local count = 0
        for _ in src:gmatch("for%s+_,%s+buff%s+in%s+ipairs%(buffDetectPatterns%)%s+do") do
            count = count + 1
        end
        assert.are.equals(3, count,
            "buffDetectPatterns must be iterated by exactly 3 passes (passive tree + skill loadout + items)")
    end)

    it("the suggestBuff item-scan block does NOT apply the 'while/if you have' exclusion filter", function()
        local src = readFile("Classes/ConfigTab.lua")
        assert.is_not_nil(src)
        -- Isolate the item-scan block by matching from the itemsTab guard to
        -- the closing of detectGrantedBuffs (the next `self.detectedBuffs = `
        -- assignment).
        local itemScanBlock = src:match("if self%.build%.itemsTab and self%.build%.itemsTab%.orderedSlots.-self%.detectedBuffs%s*=")
        assert.is_not_nil(itemScanBlock, "item-scan block must be locatable in detectGrantedBuffs")
        assert.falsy(itemScanBlock:find('while you have', 1, true),
            "item-scan block must NOT filter 'while you have' (consumption phrasing on items IS a relevance signal)")
        assert.falsy(itemScanBlock:find('if you have', 1, true),
            "item-scan block must NOT filter 'if you have' (consumption phrasing on items IS a relevance signal)")
    end)

    it("Phase 2 widens the suggestPattern corpus with equipped item modList text", function()
        local src = readFile("Classes/ConfigTab.lua")
        assert.is_not_nil(src)
        -- The corpus builder now walks both passive tree and items. Spec
        -- locks both sources by name AND ensures the cache key is unchanged
        -- so the Phase 1 single-corpus-per-session contract is preserved.
        local corpusFn = src:match("local function getAllocNodeTextCorpusLowered.-end%s*\n%s*\n%s*local function detectMatchingPattern")
        assert.is_not_nil(corpusFn,
            "getAllocNodeTextCorpusLowered must still exist (Phase 1 spec depends on the literal name)")
        assert.is_truthy(corpusFn:find("self%.build%.spec%.allocNodes", 1, false),
            "corpus must still walk passive tree allocNodes (Source A, Phase 1)")
        assert.is_truthy(corpusFn:find("orderedSlots", 1, true),
            "corpus must now also walk equipped items via orderedSlots (Source B, Phase 2)")
        assert.is_truthy(corpusFn:find("explicitModLines", 1, true),
            "Source B must read explicitModLines per equipped item")
        assert.is_truthy(corpusFn:find("self%.allocNodeTextCorpus", 1, false),
            "cache key self.allocNodeTextCorpus must be preserved (Phase 1 invariant)")
    end)

    it("passive-tree pass still applies the 'while/if you have' filter (Phase 1 invariant)", function()
        local src = readFile("Classes/ConfigTab.lua")
        assert.is_not_nil(src)
        -- The first pass (passive tree) inside detectGrantedBuffs must still
        -- strip consumption lines. Phase 2 does NOT relax that — only Pass 2
        -- (skill loadout) and Pass 3 (items) skip the filter.
        -- Phase 4 (2026-05-29): Pass 1 iteration switched to `for nodeId, node`
        -- for skill-subtree attribution via getNodeSourceLabel.
        local pass1Block = src:match("for nodeId, node in pairs%(self%.build%.spec%.allocNodes%) do.-if self%.build%.skillsTab")
        assert.is_not_nil(pass1Block, "passive-tree pass must precede the skill-loadout pass")
        assert.is_truthy(pass1Block:find('while you have', 1, true),
            "passive-tree pass must still filter 'while you have'")
        assert.is_truthy(pass1Block:find('if you have', 1, true),
            "passive-tree pass must still filter 'if you have'")
    end)

    it("equipped-only iteration: both new paths use orderedSlots[*].selItemId, not itemsTab.items directly", function()
        local src = readFile("Classes/ConfigTab.lua")
        assert.is_not_nil(src)
        -- Each item-scan site must resolve item via `slot.selItemId →
        -- itemsTab.items[id]` rather than iterating `itemsTab.items`
        -- directly (which would over-include inventory items). Verify both
        -- sites do this by checking the pattern is present on the same line
        -- as `for _, slot in pairs(... .orderedSlots) do`.
        local _, count = src:gsub("for%s+_,%s+slot%s+in%s+pairs%(self%.build%.itemsTab%.orderedSlots%)%s+do", "")
        assert.are.equals(2, count,
            "both Phase 2 paths (suggestBuff Pass 3 + suggestPattern corpus Source B) must iterate orderedSlots")
        assert.is_truthy(src:find("slot%.selItemId and self%.build%.itemsTab%.items", 1, false),
            "item must be resolved via slot.selItemId → items[id] (equipped-only)")
    end)
end)
