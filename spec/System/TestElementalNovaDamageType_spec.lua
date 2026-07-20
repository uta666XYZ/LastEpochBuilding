-- @leb-regression-guard: elemental-nova-spec-tree-gated-damage-type
-- See REGRESSION_GUARDS.md > "elemental-nova-spec-tree-gated-damage-type"
-- Validation provenance is retained in maintainer notes.

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
