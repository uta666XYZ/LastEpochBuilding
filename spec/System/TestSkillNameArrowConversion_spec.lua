-- @leb-regression-guard:skill-name-arrow-conversion
-- Two coupled invariants (mirrors @leb-regression-guard:conversion-extra-nil-not-empty):
-- See REGRESSION_GUARDS.md > "skill-name-arrow-conversion".
-- Validation provenance is retained in maintainer notes.

describe("SkillNameArrowConversion", function()
    before_each(function()
        newBuild()
    end)

    it("live-parse 'Volcanic Orb -> Cold' emits skill-scoped FireDamageConvertToCold (nil extra)", function()
        -- No leading space => not a ModCache key => exercises the live parser branch.
        local mods, extra = modLib.parseMod("Volcanic Orb -> Cold")
        assert.is_nil(extra)
        assert.is_not_nil(mods)
        -- One conversion per non-Cold damage type (6 of the 7 DamageTypes).
        assert.are.equals(6, #mods)
        local fireToCold
        for _, m in ipairs(mods) do
            if m.name == "FireDamageConvertToCold" then fireToCold = m end
            -- Cold->Cold must never be emitted.
            assert.are_not.equals("ColdDamageConvertToCold", m.name)
            assert.are.equals("BASE", m.type)
            assert.are.equals(100, m.value)
            -- Every emitted conversion is scoped to the skill via a SkillName tag.
            assert.is_not_nil(m[1], "conversion mod must carry a tag")
            assert.are.equals("SkillName", m[1].type)
            assert.are.equals("Volcanic Orb", m[1].skillName)
        end
        assert.is_not_nil(fireToCold, "must emit FireDamageConvertToCold (Volcanic Orb base is Fire)")
    end)

    it("live-parse 'Lightning Blast -> Cold' scopes to Lightning Blast", function()
        local mods, extra = modLib.parseMod("Lightning Blast -> Cold")
        assert.is_nil(extra)
        assert.are.equals(6, #mods)
        local lightToCold
        for _, m in ipairs(mods) do
            if m.name == "LightningDamageConvertToCold" then lightToCold = m end
            assert.are.equals("Lightning Blast", m[1].skillName)
        end
        assert.is_not_nil(lightToCold)
    end)

    it("does NOT match non-skill arrows ('Ward -> Health')", function()
        -- "ward" is not a skill and "health" is not a damage type => must drop
        -- (mods empty, extra = the residue) exactly as before the fix.
        local mods, extra = modLib.parseMod("Ward -> Health")
        assert.are.equals(0, #mods)
        assert.is_truthy(extra)
    end)

    it("does NOT match skill->skill arrows ('Volcanic Orb -> Frozen Orb')", function()
        -- dst "Frozen Orb" is not a damage type => skill-name branch returns nil,
        -- the whole line drops (behaviour swap node, out of scope for damage calc).
        local mods, extra = modLib.parseMod("Volcanic Orb -> Frozen Orb")
        assert.are.equals(0, #mods)
        assert.is_truthy(extra)
    end)

    it("does NOT recolour pure type arrows ('Fire -> Cold' stays unscoped/global)", function()
        -- The plain damage-type arrow must still be handled by parseArrowConversion
        -- (single global mod, no SkillName tag) so the Fire Aura precedent is intact.
        local mods, extra = modLib.parseMod("Fire -> Cold")
        assert.is_nil(extra)
        assert.are.equals(1, #mods)
        assert.are.equals("FireDamageConvertToCold", mods[1].name)
        assert.is_nil(mods[1][1], "global type arrow must NOT carry a SkillName tag")
    end)

    it("tree node ' Volcanic Orb -> Cold' applies the skill-scoped conversion (regen-gated)", function()
        -- Leading-space stat is served from the regenerated ModCache. Confirms the
        -- conversion reaches node.modList scoped to Volcanic Orb.
        local node = { id = "test-skill-arrow-conv", stats = { " Volcanic Orb -> Cold" }, alloc = 1 }
        build.spec.tree:ProcessStats(node)
        local sum = node.modList:Sum("BASE", { skillName = "Volcanic Orb" }, "FireDamageConvertToCold")
        assert.are.equals(100, sum,
            "tree-node ' Volcanic Orb -> Cold' must add FireDamageConvertToCold BASE 100 scoped to Volcanic Orb")
        -- Scope check: querying a different skill must NOT see the conversion.
        local otherSum = node.modList:Sum("BASE", { skillName = "Meteor" }, "FireDamageConvertToCold")
        assert.are.equals(0, otherSum,
            "conversion must be scoped to Volcanic Orb, not leak to Meteor")
    end)
end)
