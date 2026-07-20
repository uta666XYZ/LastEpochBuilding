-- @leb-regression-guard:config-highlight-skill-subtree-scan
-- Phase 4 (2026-05-29) of the Config-highlight family. `self.build.spec
-- .allocNodes` is a single unified table containing BOTH player passive
-- tree nodes (UpperCamelCase / hex ids) AND skill subtree nodes (lower-
-- case treeId-prefixed ids such as `ch0fs-20`). Pass 1 of detectGranted-
-- Buffs already iterates them transparently, but Phase 1/1.5/3 silently
-- mislabelled subtree-node hits as `"passive node 'X'"`. Phase 4 adds
-- treeId → skill-name attribution so the source label correctly reads
-- `"skill subtree '<skill>' node '<name>'"` for those entries. The same
-- helper is reused by Source A of getAllocNodeTextCorpusLowered so the
-- suggestPattern path inherits the refinement.
--
-- Invariants this spec locks:
--   (1) ConfigTab.lua carries the Phase 4 inline guard marker.
--   (2) A `getTreeIdToSkillName` (or equivalent) closure builds the lookup
--       from `socketGroupList[*].grantedEffect.{treeId,name}` and caches
--       it on `self.treeIdToSkillName`.
--   (3) A `getNodeSourceLabel(nodeId, node)` helper returns "skill subtree
--       '<skill>' node '<name>'" when the node id is treeId-prefixed, and
--       "passive node '<name>'" otherwise.
--   (4) Pass 1 in detectGrantedBuffs iterates with `(nodeId, node)` keys
--       and calls `getNodeSourceLabel(nodeId, node)`.
--   (5) Source A in getAllocNodeTextCorpusLowered iterates with `(nodeId,
--       node)` keys and calls `getNodeSourceLabel(nodeId, node)`.
--   (6) `self.treeIdToSkillName` is invalidated alongside `self.detectedBuffs`
--       inside BuildModList so a skill loadout change doesn't keep a stale
--       lookup.
--   (7) Prefix matching uses `treeId .. "-"` so a treeId like `ch0` cannot
--       collide with an unrelated id starting with `ch0` but not `ch0-`.
--
-- See REGRESSION_GUARDS.md "config-highlight-skill-subtree-scan".

describe("ConfigHighlightSkillSubtreeScan", function()
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

    it("Phase 4 inline guard marker is present in ConfigTab.lua", function()
        assert.is_truthy(cfgTabSrc:find("@leb%-regression%-guard:config%-highlight%-skill%-subtree%-scan", 1, false),
            "Classes/ConfigTab.lua must carry the Phase 4 inline guard marker")
    end)

    it("getTreeIdToSkillName builds lookup from socketGroupList[*].grantedEffect", function()
        local startIdx = cfgTabSrc:find("local function getTreeIdToSkillName", 1, true)
        assert.is_not_nil(startIdx, "getTreeIdToSkillName must be declared")
        local nextFn = cfgTabSrc:find("\n%s*local function ", startIdx + 1)
        local fnBody = cfgTabSrc:sub(startIdx, nextFn or #cfgTabSrc)
        assert.is_truthy(fnBody:find("self%.build%.skillsTab%.socketGroupList", 1, false),
            "must read self.build.skillsTab.socketGroupList")
        assert.is_truthy(fnBody:find("group%.grantedEffect", 1, false),
            "must read group.grantedEffect")
        assert.is_truthy(fnBody:find("%.treeId", 1, false),
            "must read grantedEffect.treeId")
        assert.is_truthy(fnBody:find("self%.treeIdToSkillName", 1, false),
            "must cache the lookup on self.treeIdToSkillName")
    end)

    it("getNodeSourceLabel emits 'skill subtree' for treeId-prefixed ids, 'passive node' otherwise", function()
        local startIdx = cfgTabSrc:find("local function getNodeSourceLabel", 1, true)
        assert.is_not_nil(startIdx, "getNodeSourceLabel must be declared")
        local nextFn = cfgTabSrc:find("\n%s*local function ", startIdx + 1)
        local fnBody = cfgTabSrc:sub(startIdx, nextFn or #cfgTabSrc)
        assert.is_truthy(fnBody:find('"skill subtree \'"', 1, false),
            "must emit \"skill subtree '<skill>' node '<name>'\" label form")
        assert.is_truthy(fnBody:find('"passive node \'"', 1, false),
            "must preserve legacy \"passive node '<name>'\" label form for non-treeId ids")
        -- Prefix matching must use `treeId .. "-"` (NOT bare treeId) to
        -- avoid false positives. A treeId of "ch0" must not match a node
        -- id "ch0fs-1" which belongs to a different skill.
        assert.is_truthy(fnBody:find('treeId %.%. "%-"', 1, false),
            "prefix matching must use `treeId .. \"-\"`, not bare treeId")
        -- The user-facing label MUST NOT embed `tostring(node.id)` or the
        -- internal nodeId — the Phase 3 review explicitly removed that.
        assert.falsy(fnBody:find("tostring(node%.id)", 1, false),
            "internal nodeId must not be surfaced in the user-facing label")
        assert.falsy(fnBody:find("tostring(nodeId)", 1, false),
            "internal nodeId must not be surfaced in the user-facing label")
    end)

    it("Pass 1 iterates allocNodes with (nodeId, node) keys and calls getNodeSourceLabel", function()
        local pass1Block = cfgTabSrc:match(
            "for nodeId, node in pairs%(self%.build%.spec%.allocNodes%) do(.-)\n%s*end%s*\n%s*%-%- @leb%-regression%-guard:config%-highlight%-skill%-loadout%-scan")
        assert.is_not_nil(pass1Block,
            "Pass 1 must use `for nodeId, node in pairs(self.build.spec.allocNodes)` (keyed iteration)")
        assert.is_truthy(pass1Block:find("getNodeSourceLabel(nodeId, node)", 1, true),
            "Pass 1 must compute source via `getNodeSourceLabel(nodeId, node)`")
        -- The old direct `"passive node '" .. label .. "'"` write must be gone
        -- from Pass 1 (it now flows through the helper).
        assert.falsy(pass1Block:find('"passive node \'" %.%. label', 1, false),
            "Pass 1 must not write 'passive node' label directly — go through getNodeSourceLabel")
    end)

    it("Source A iterates allocNodes with (nodeId, node) keys and calls getNodeSourceLabel", function()
        local corpusBody = cfgTabSrc:match("local function getAllocNodeTextCorpusLowered.-self%.allocNodeTextCorpus%s*=%s*lines")
        assert.is_not_nil(corpusBody, "corpus builder body must be locatable")
        assert.is_truthy(corpusBody:find("for nodeId, node in pairs(self.build.spec.allocNodes)", 1, true),
            "Source A must iterate with `(nodeId, node)` keys")
        assert.is_truthy(corpusBody:find("getNodeSourceLabel(nodeId, node)", 1, true),
            "Source A must compute source via `getNodeSourceLabel(nodeId, node)`")
    end)

    it("BuildModList invalidates the treeIdToSkillName cache alongside detectedBuffs", function()
        local startIdx = cfgTabSrc:find("function ConfigTabClass:BuildModList", 1, true)
        assert.is_not_nil(startIdx, "ConfigTabClass:BuildModList must exist")
        -- Inspect only the first ~30 lines after the function head — the
        -- cache resets live there. A broader window would include unrelated
        -- nil-assignments and create false positives.
        local fnHead = cfgTabSrc:sub(startIdx, startIdx + 600)
        assert.is_truthy(fnHead:find("self%.detectedBuffs%s*=%s*nil", 1, false),
            "BuildModList must clear self.detectedBuffs (pre-existing contract)")
        assert.is_truthy(fnHead:find("self%.treeIdToSkillName%s*=%s*nil", 1, false),
            "BuildModList must clear self.treeIdToSkillName so a skill loadout change invalidates the lookup")
    end)
end)
