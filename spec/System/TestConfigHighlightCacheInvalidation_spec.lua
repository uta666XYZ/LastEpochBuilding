-- @leb-regression-guard:config-highlight-cache-invalidation
-- @leb-regression-guard:config-highlight-persistent
-- Phase 7 (2026-05-30) of the Config-highlight family. Two user-reported
-- fixes from in-game testing:
--
--   (1) CACHE INVALIDATION BUG. The suggestPattern corpus cache
--       (self.allocNodeTextCorpus) was introduced in Phase 1/2 with a lazy
--       `if self.allocNodeTextCorpus then return it` guard but was NEVER
--       reset in BuildModList — only detectedBuffs / treeIdToSkillName were.
--       So after importing a different build into the same file, every
--       suggestPattern highlight (Cursed / Low Life / Ward / Overload)
--       stayed frozen on the PREVIOUS build's passive-tree + item text.
--       Fix: clear self.allocNodeTextCorpus in BuildModList too, so the
--       corpus rebuilds from the current build each rebuild cycle (exactly
--       like detectedBuffs). detectGrantedBuffs (suggestBuff) already
--       refreshed correctly — only the corpus leaked.
--
--   (2) PERSISTENT HIGHLIGHT. Previously the orange label was gated on
--       `and not isSuggestActive()` / `and not isPatternSuggestActive()`,
--       so checking the box made the highlight vanish — users read it as a
--       transient "enable me" prompt and lost the build-relevance signal
--       once enabled. Fix: the label is now a bare truthy check on the
--       detection result, so the orange persists regardless of on/off. The
--       tooltip still shows source attribution always, and appends the
--       "Consider enabling this option" call-to-action only while OFF.
--
-- See REGRESSION_GUARDS.md "config-highlight-cache-invalidation" +
-- "config-highlight-persistent".

describe("ConfigHighlightPhase7", function()
    local function readFile(path)
        local f = io.open(path, "r")
        if not f then return nil end
        local s = f:read("*a"); f:close()
        return s
    end

    -- ===== Fix (1): cache invalidation — behavioral + structural =====
    describe("corpus cache invalidation", function()
        before_each(function()
            newBuild()
        end)

        it("BuildModList clears the suggestPattern corpus cache (allocNodeTextCorpus)", function()
            local ct = build.configTab
            -- Simulate a populated corpus from a previously-loaded build.
            ct.allocNodeTextCorpus = { { text = "stale text", line = "Stale Text", source = "passive node 'Old'" } }
            ct:BuildModList()
            assert.is_nil(ct.allocNodeTextCorpus,
                "BuildModList must reset self.allocNodeTextCorpus so the corpus rebuilds for the current build")
        end)

        it("BuildModList also clears detectedBuffs and treeIdToSkillName (full highlight cache reset)", function()
            local ct = build.configTab
            ct.detectedBuffs = { Haste = { source = "stale", line = "stale", sources = {} } }
            ct.treeIdToSkillName = { ch0fs = "Stale Skill" }
            ct:BuildModList()
            assert.is_nil(ct.detectedBuffs, "BuildModList must reset detectedBuffs")
            assert.is_nil(ct.treeIdToSkillName, "BuildModList must reset treeIdToSkillName")
        end)
    end)

    describe("source invariants", function()
        local cfgTabSrc
        setup(function()
            cfgTabSrc = readFile("Classes/ConfigTab.lua")
            assert.is_not_nil(cfgTabSrc, "must read Classes/ConfigTab.lua")
        end)

        it("Phase 7 guard markers are present", function()
            assert.is_truthy(cfgTabSrc:find("@leb%-regression%-guard:config%-highlight%-cache%-invalidation", 1, false),
                "ConfigTab.lua must carry the cache-invalidation guard marker")
            assert.is_truthy(cfgTabSrc:find("@leb%-regression%-guard:config%-highlight%-persistent", 1, false),
                "ConfigTab.lua must carry the persistent-highlight guard marker")
        end)

        it("BuildModList nils all three highlight caches together", function()
            -- Scope to the BuildModList head so we lock the reset trio.
            local startIdx = cfgTabSrc:find("function ConfigTabClass:BuildModList", 1, true)
            assert.is_not_nil(startIdx, "BuildModList must exist")
            local head = cfgTabSrc:sub(startIdx, startIdx + 1200)
            assert.is_truthy(head:find("self.detectedBuffs = nil", 1, true),
                "BuildModList must clear detectedBuffs")
            assert.is_truthy(head:find("self.treeIdToSkillName = nil", 1, true),
                "BuildModList must clear treeIdToSkillName")
            assert.is_truthy(head:find("self.allocNodeTextCorpus = nil", 1, true),
                "BuildModList must clear allocNodeTextCorpus (Phase 7 fix)")
        end)

        -- ===== Fix (2): persistent highlight =====
        it("label hooks highlight on a bare truthy check (no active gate)", function()
            assert.is_truthy(cfgTabSrc:find("if detectGrantedBuffs()[buffName] then", 1, true),
                "suggestBuff label must highlight on a bare detectGrantedBuffs()[buffName] check")
            assert.is_truthy(cfgTabSrc:find("if detectMatchingPattern(pattern) then", 1, true),
                "suggestPattern label must highlight on a bare detectMatchingPattern(pattern) check")
            assert.falsy(cfgTabSrc:find("detectGrantedBuffs()[buffName] and not isSuggestActive()", 1, true),
                "suggestBuff label must NOT gate on `and not isSuggestActive()` (Phase 7)")
            assert.falsy(cfgTabSrc:find("detectMatchingPattern(pattern) and not isPatternSuggestActive()", 1, true),
                "suggestPattern label must NOT gate on `and not isPatternSuggestActive()` (Phase 7)")
        end)

        it("tooltips show attribution whenever detected, gating only the CTA on active state", function()
            -- Both tooltip closures must build the source trailer when the
            -- detection is truthy (bare `if attrib then`), and append the
            -- "Consider enabling" CTA only when NOT active (cta var).
            local _, bareAttribCount = cfgTabSrc:gsub("if attrib and not is", "")
            assert.are.equal(0, bareAttribCount,
                "Phase 7: tooltips must NOT gate the whole block on `if attrib and not isXActive()` anymore")
            -- The CTA is now conditional via an `isSuggestActive()`/
            -- `isPatternSuggestActive()`-driven local.
            assert.is_truthy(cfgTabSrc:find("isSuggestActive() and \"\" or \" Consider enabling this option.\"", 1, true),
                "suggestBuff tooltip must gate the CTA on isSuggestActive()")
            assert.is_truthy(cfgTabSrc:find("isPatternSuggestActive() and \"\" or \" Consider enabling this option", 1, true),
                "suggestPattern tooltip must gate the CTA on isPatternSuggestActive()")
        end)
    end)
end)
