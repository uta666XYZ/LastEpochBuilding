-- @leb-regression-guard: elemental-nova-spec-tree-gated-damage-type
-- Locks the contract that Elemental Nova's three elemental damage types
-- (Fire / Cold / Lightning) are CONDITIONALLY enabled by the en6 skill
-- specialization tree, NOT all granted unconditionally as base.
--
-- LE behaviour (verified against game files at
-- <LE_datamining>/extracted/):
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
-- Bug as of 2026-05-05 (NOT YET FIXED):
--   src/Data/skills.json declares ElementalNova base stats as
--     spell_base_fire_damage:8, spell_base_cold_damage:8,
--     spell_base_lightning_damage:8
--   unconditionally, so LEB grants Fire damage even when en6-12 (Fire Nova)
--   is not allocated. LETools correctly shows only Cold + Lightning for
--   Bakbr2Ne (which allocates en6-2 + en6-8 but NOT en6-12); LEB shows
--   Fire + Cold + Lightning.
--
-- Establishing build: Bakbr2Ne lv86 Sorcerer (en6 allocations:
-- en6-0,2,4,5,6,8,18,21,24,25,26 — Ice + Lightning, no Fire). LE/LETools
-- expected Fire damage on Elemental Nova = 0; LEB current = 8 base.
--
-- Likely fix shape (for whoever picks this up):
--   - Move the three spell_base_*_damage entries out of skills.json's
--     ElementalNova base stats and into the en6-2 / en6-8 / en6-12 nodes'
--     stats lists in src/TreeData/1_4/tree_1.json (or attach as conditional
--     stats gated on node allocation).
--   - Honor skillTreeConversionDamageTags in the SkillStatMap pipeline so
--     the conversion-tagged damage types do not flow to the active skill
--     unless the matching tree node is taken.
--
-- See REGRESSION_GUARDS.md > "elemental-nova-spec-tree-gated-damage-type"
-- for the index entry.

describe("ElementalNovaSpecTreeGatedDamageType", function()
    before_each(function()
        newBuild()
    end)

    pending("Bakbr2Ne (no Fire Nova node allocated) does not include Fire damage type on Elemental Nova", function()
        -- This test is `pending` because the bug is not yet fixed in
        -- src/Data/skills.json. When the fix lands (move spell_base_*_damage
        -- onto the en6-2 / en6-8 / en6-12 tree nodes), flip `pending` to `it`
        -- and the assertion below should pass.
        local f = io.open("../spec/TestBuilds/1.4/Bakbr2Ne lv86 Sorcerer.xml", "r")
        assert(f, "Bakbr2Ne XML fixture missing")
        local xml = f:read("*a")
        f:close()
        loadBuildFromXML(xml, "Bakbr2Ne lv86 Sorcerer")
        runCallback("OnFrame")

        -- Locate the Elemental Nova socket group in the skills tab.
        local enSocketGroup
        for _, sg in ipairs(build.skillsTab.socketGroupList) do
            for _, gem in ipairs(sg.gemList or {}) do
                if gem.skillId == "ElementalNova" then
                    enSocketGroup = sg
                    break
                end
            end
            if enSocketGroup then break end
        end
        assert(enSocketGroup, "ElementalNova socket group not found in Bakbr2Ne fixture")

        local activeSkill = enSocketGroup.displaySkillList and enSocketGroup.displaySkillList[1]
        assert(activeSkill, "ElementalNova active skill not built")

        -- Damage flags on the active skill should include Cold + Lightning
        -- (en6-2, en6-8 allocated) but NOT Fire (en6-12 not allocated).
        local flags = activeSkill.skillFlags or {}
        assert.is_true(flags.cold == true, "expected Cold damage flag on Elemental Nova")
        assert.is_true(flags.lightning == true, "expected Lightning damage flag on Elemental Nova")
        assert.is_nil(flags.fire,
            "Fire damage flag must be absent on Elemental Nova when en6-12 (Fire Nova) is not allocated")
    end)
end)
