-- @leb-regression-guard: elemental-nova-spec-tree-gated-damage-type
-- Locks the contract that Elemental Nova's three elemental damage types
-- (Fire / Cold / Lightning) are CONDITIONALLY enabled by the en6 skill
-- specialization tree, NOT all granted unconditionally as base.
--
-- LE behaviour (verified against extracted LE game files; the
-- LE_datamining tree lives outside the repo — set $LEB_DATAMINING_ROOT
-- to point at your local copy, or see the Obsidian "GameData解析 INDEX"
-- note for the canonical layout):
--   - prefab_damage.json ElementalNova baseDamage = [Phys=0, Fire=8, Cold=8,
--     Light=8, Necro=0, Void=0, Poison=0]   (the "all-enabled" template)
--   - skills.json field skillTreeConversionDamageTags = 14 = Fire(2) + Cold(4)
--     + Lightning(8). This is the LE flag indicating that those damage types
--     are tree-gated, not base.
--   - en6 specialization tree (src/TreeData/1_4/tree_1.json):
--       en6-2  "Ice Nova"       — Enables Ice Nova       (Cold)
--       en6-8  "Lightning Nova" — Enables Lightning Nova (Lightning)
--       en6-12 "Fire Nova"      — Enables Fire Nova      (Fire)
--     A damage type is granted ONLY when its corresponding "Enables X Nova"
--     node is allocated.
--
-- Fix (2026-05-05):
--   - Removed spell_base_fire/cold/lightning_damage from
--     src/Data/skills.json `ElementalNova.stats`.
--   - Added "+8 Spell {Cold,Lightning,Fire} Damage" to en6-2 / en6-8 /
--     en6-12 nodes' `stats` in src/TreeData/1_4/tree_1.json.
--   - Cleared TREE_ID_DAMAGE_TYPES["en6"] in src/Classes/SkillsTab.lua so
--     spec-slot damage-type icons resolve via the dynamic resolver
--     (which detects "+N Spell <Type> Damage" stats on allocated nodes).
--
-- Establishing build: Bakbr2Ne lv86 Sorcerer (en6 allocations:
-- en6-0,2,4,5,6,8,18,21,24,25,26 — Ice + Lightning, no Fire). After fix,
-- Elemental Nova damage type icons match LE/LETools: Cold + Lightning,
-- no Fire.
--
-- See REGRESSION_GUARDS.md > "elemental-nova-spec-tree-gated-damage-type"
-- for the index entry.

describe("ElementalNovaSpecTreeGatedDamageType", function()
    before_each(function()
        newBuild()
    end)

    it("Bakbr2Ne (no Fire Nova node allocated) does not include Fire damage type on Elemental Nova", function()
        -- The fix moved spell_base_fire/cold/lightning_damage out of
        -- src/Data/skills.json `ElementalNova.stats` and onto the
        -- en6-2 / en6-8 / en6-12 specialization-tree nodes' `stats`
        -- ("+8 Spell {Cold,Lightning,Fire} Damage"), so each damage type
        -- only applies when its enabling node is allocated.
        local f = io.open("../spec/TestBuilds/1.4/Bakbr2Ne lv86 Sorcerer.xml", "r")
        if not f then
            pending("Bakbr2Ne XML fixture missing in this worktree; covered in determined-hawking worktree")
            return
        end
        local xml = f:read("*a")
        f:close()
        loadBuildFromXML(xml, "Bakbr2Ne lv86 Sorcerer")
        runCallback("OnFrame")

        -- Resolve damage types via the same code path the SkillsTab UI uses
        -- (LETools-style icons under the spec slot). This is tree-allocation-
        -- aware: addSet picks up "+8 Spell <Type> Damage" stats only from
        -- nodes the build actually allocates.
        local types = build.skillsTab:GetDynamicDamageTypesByTreeId("en6", "Elemental Nova")
        assert(types, "GetDynamicDamageTypesByTreeId returned nil for en6")

        local present = {}
        for _, dt in ipairs(types) do present[dt.type] = dt.isBase end

        assert.is_true(present.cold == true,
            "expected Cold damage type on Elemental Nova (en6-2 Ice Nova allocated)")
        assert.is_true(present.lightning == true,
            "expected Lightning damage type on Elemental Nova (en6-8 Lightning Nova allocated)")
        assert.is_nil(present.fire,
            "Fire damage type must be absent on Elemental Nova when en6-12 (Fire Nova) is not allocated")
    end)
end)
