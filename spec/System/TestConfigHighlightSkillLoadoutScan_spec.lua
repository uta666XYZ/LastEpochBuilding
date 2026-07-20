-- @leb-regression-guard:config-highlight-skill-loadout-scan
-- Phase 1.6 (2026-05-29) of the Config-highlight family. Extends
-- detectGrantedBuffs() in ConfigTab.lua to walk the active skill bar
-- (build.skillsTab.socketGroupList) for buff-named skills, alongside the
-- existing passive-tree pass.
--
-- Motivation: Phase 1.5 (commit <see git log> / merge <see git log>) added a
-- "profane veil" row to buffDetectPatterns for symmetry with the four
-- ConfigOptions entries that declared `suggestBuff = "X"` but had no
-- matching row in the patterns table. Three of the four new patterns
-- (FlameWard / EterrasBlessing / DreadShade) catch real grant phrasing in
-- the 1.4 passive tree, but ProfaneVeil has **zero** non-consumption hits
-- in any passive tree json — Profane Veil is a Warlock active skill, not a
-- passive-tree-granted buff. So the Phase 1.5 row was deliberately
-- registered dormant, with this Phase 1.6 pass intended to wake it up.
--
-- Three coupled invariants this spec locks:
--   (1) ConfigTab.lua's detectGrantedBuffs walks
--       build.skillsTab.socketGroupList AS WELL AS the passive tree, and
--       both paths share the same buffDetectPatterns table.
--   (2) The skill-loadout pass does NOT apply the existing
--       `while/if you have` exclusion filter — a skill's display name is
--       the buff itself, not consumption phrasing about it.
--   (3) The pre-existing passive-tree pass still applies the
--       `while/if you have` filter, and its 8 entries from Phase 1+1.5
--       still fire from passive tree alone (no regression).
--
-- See REGRESSION_GUARDS.md "config-highlight-skill-loadout-scan".

describe("ConfigHighlightSkillLoadoutScan", function()
    local function readFile(path)
        local f = io.open(path, "r")
        if not f then return nil end
        local s = f:read("*a"); f:close()
        return s
    end

    it("ConfigTab.lua holds the skill loadout scan path and the inline guard", function()
        local src = readFile("Classes/ConfigTab.lua")
        assert.is_not_nil(src, "must read Classes/ConfigTab.lua")
        assert.is_truthy(src:find("@leb%-regression%-guard:config%-highlight%-skill%-loadout%-scan", 1, false),
            "ConfigTab.lua must carry the Phase 1.6 inline guard marker")
        assert.is_truthy(src:find("self.build.skillsTab", 1, true),
            "skill loadout pass must access build.skillsTab")
        assert.is_truthy(src:find("socketGroupList", 1, true),
            "skill loadout pass must iterate socketGroupList")
        assert.is_truthy(src:find("displaySkillList", 1, true),
            "skill loadout pass must iterate displaySkillList per group")
        assert.is_truthy(src:find("activeEffect", 1, true) and src:find("grantedEffect", 1, true),
            "skill loadout pass must read activeEffect.grantedEffect (skill display name resolution)")
    end)

    it("the skill loadout pass shares buffDetectPatterns with the passive-tree pass", function()
        local src = readFile("Classes/ConfigTab.lua")
        assert.is_not_nil(src)
        -- The shared `buffDetectPatterns` table guarantees the Phase 1.5
        -- ProfaneVeil row becomes live in Pass 2 without re-declaring
        -- patterns. This assertion locks the SHARING contract — there must
        -- be at least 2 passes (passive tree + skill loadout). The exact
        -- total count is owned by the latest phase's spec (Phase 2 locks
        -- exactly 3 once items are walked), so Phase 1.6 deliberately uses
        -- `>= 2` to remain forward-compatible.
        local count = 0
        for _ in src:gmatch("for%s+_,%s+buff%s+in%s+ipairs%(buffDetectPatterns%)%s+do") do
            count = count + 1
        end
        assert.is_true(count >= 2,
            "buffDetectPatterns must be iterated by at least 2 passes (passive tree + skill loadout); got " .. tostring(count))
    end)

    it("the skill loadout pass does NOT apply the 'while/if you have' exclusion filter", function()
        local src = readFile("Classes/ConfigTab.lua")
        assert.is_not_nil(src)
        -- Isolate the skill loadout block only. Anchor the START on
        -- `if group.displaySkillList` (uniquely Pass 2's code path; the
        -- Phase 1.6 guard-marker comment block above it intentionally
        -- contains the phrase "while/if you have" as English prose
        -- explaining why the filter does NOT apply, which would otherwise
        -- create false positives). Phase 4 (2026-05-29) also added an
        -- earlier `self.build.skillsTab.socketGroupList` access inside
        -- getTreeIdToSkillName, so a bare `if self.build.skillsTab...`
        -- regex anchor would now match the wrong site first. Upper bound
        -- on the Phase 2 item-scan marker so Pass 3 / future passes don't
        -- bleed in.
        local skillLoadoutBlock = src:match(
            "if group%.displaySkillList(.-)@leb%-regression%-guard:config%-highlight%-item%-modlist%-scan")
        if not skillLoadoutBlock then
            skillLoadoutBlock = src:match(
                "if group%.displaySkillList(.-)self%.detectedBuffs%s*=")
        end
        assert.is_not_nil(skillLoadoutBlock, "skill loadout block must be locatable in detectGrantedBuffs")
        assert.falsy(skillLoadoutBlock:find('while you have', 1, true),
            "skill loadout block must NOT filter 'while you have' (skill names are not consumption phrasing)")
        assert.falsy(skillLoadoutBlock:find('if you have', 1, true),
            "skill loadout block must NOT filter 'if you have' (skill names are not consumption phrasing)")
    end)

    it("Phase 1.5 dormant ProfaneVeil pattern is the canonical case this pass wakes up", function()
        -- Cross-check that the row added in Phase 1.5 is still present in
        -- buffDetectPatterns AND that ConfigOptions still declares the
        -- corresponding suggestBuff. If a future refactor deletes either
        -- side, the Phase 1.6 path becomes pointless for the documented
        -- canonical case.
        local cfgTabSrc = readFile("Classes/ConfigTab.lua")
        assert.is_not_nil(cfgTabSrc)
        local patternsBlock = cfgTabSrc:match("local buffDetectPatterns%s*=%s*(%b{})")
        assert.is_not_nil(patternsBlock, "buffDetectPatterns table must exist")
        assert.is_truthy(patternsBlock:find('name%s*=%s*"ProfaneVeil"', 1, false),
            "buffDetectPatterns must keep the Phase 1.5 ProfaneVeil row")
        assert.is_truthy(patternsBlock:find('pat%s*=%s*"profane veil"', 1, false),
            "ProfaneVeil row must keep pat = 'profane veil'")

        local cfgOptsSrc = readFile("Modules/ConfigOptions.lua")
        assert.is_not_nil(cfgOptsSrc)
        assert.is_truthy(cfgOptsSrc:find('suggestBuff%s*=%s*"ProfaneVeil"', 1, false),
            "ConfigOptions must keep `suggestBuff = \"ProfaneVeil\"` on conditionDuringProfaneVeil")
    end)

    it("passive-tree pass still applies the 'while/if you have' filter (Phase 1 invariant preserved)", function()
        local src = readFile("Classes/ConfigTab.lua")
        assert.is_not_nil(src)
        -- The original Pass 1 filter must remain intact: a passive node
        -- saying "while you have Haste" is consumption, not grant, and the
        -- Phase 1 contract was to strip those. Phase 1.6 does NOT relax that.
        -- Phase 4 (2026-05-29): Pass 1 iteration switched to `for nodeId, node`
        -- to enable skill-subtree attribution via getNodeSourceLabel.
        local pass1Block = src:match("for nodeId, node in pairs%(self%.build%.spec%.allocNodes%) do.-if self%.build%.skillsTab")
        assert.is_not_nil(pass1Block, "passive-tree pass must precede the skill-loadout pass")
        assert.is_truthy(pass1Block:find('while you have', 1, true),
            "Pass 1 must still filter 'while you have' on passive tree text")
        assert.is_truthy(pass1Block:find('if you have', 1, true),
            "Pass 1 must still filter 'if you have' on passive tree text")
    end)

    it("game-data: 'Profane Veil' is reachable as an active skill name via skills.json", function()
        -- The Phase 1.6 path resolves skill display names via
        -- activeEffect.grantedEffect.name; that name comes from skills.json.
        -- If a future patch renames Profane Veil, this assertion forces
        -- revisit of the buffDetectPatterns pat.
        local skills = readFile("Data/skills.json")
        assert.is_not_nil(skills, "must read Data/skills.json")
        assert.is_truthy(skills:find('"Profane Veil"', 1, true),
            "skills.json must still expose a skill with name \"Profane Veil\" for the Phase 1.6 pattern to fire")
    end)
end)
