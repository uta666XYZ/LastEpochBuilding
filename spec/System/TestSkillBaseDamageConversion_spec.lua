-- @leb-regression-guard:skill-base-damage-conversion
-- Locks the parser contract that a skill-scoped base-damage type conversion
-- "X% of <Skill> Base Damage converted to <DamageType>" emits a SKILL-SCOPED
-- <srcType>DamageConvertTo<dst> BASE % for every non-dst damage type, so the
-- skill's base damage actually changes element instead of being silently
-- dropped as recognition-only (LEB_NotSupported).
--
-- Ground truth: Vial of Volatile Ice (uniques_1_4.json #331, Glass Catalyst)
-- "100% of Acid Flask Base Damage converted to Cold". The in-game tooltip
-- (2026-05-30 user SS) and datamine tooltipDescriptions both carry it; LEB had
-- it transcribed but the parser routed "% of <skill> base damage converted to
-- <type>" to nsAny (LEB_NotSupported) so NO conversion reached the calc.
--
-- Critical invariant — the conversion is SKILL-SCOPED (SkillName tag): only the
-- named skill converts. This mirrors @leb-regression-guard:skill-name-arrow-conversion
-- (the "<Skill> -> <Type>" arrow form) and reuses the SAME CalcOffence consumer
-- (conversionTable, CalcOffence.lua globalConv path, which removes the converted
-- fraction from the source via mult = 1 - converted — no double-counting).
--
-- ModCache note: the exact unique strings are baked in Data/ModCache.lua, so
-- modLib.parseMod short-circuits them. The Acid Flask row was updated from the
-- stale notSupported entry to the functional skill-scoped conversion; other
-- skills using this form (Fury Leap/Meteor/Shurikens/etc.) stay baked as
-- notSupported until their rows are removed/regenerated (no corpus build uses
-- any of them, so zero snapshot impact).
--
-- See REGRESSION_GUARDS.md > "skill-base-damage-conversion".

describe("SkillBaseDamageConversion", function()
    before_each(function()
        newBuild()
    end)

    it("live-parse '<n>% of <Skill> Base Damage converted to <Type>' emits skill-scoped conversion (nil extra)", function()
        -- Non-cached string => exercises the live parser branch (skillBaseDamageConversionHandler).
        local mods, extra = modLib.parseMod("77% of Acid Flask Base Damage converted to Fire")
        assert.is_nil(extra)
        -- One conversion per non-Fire damage type (6 of the 7 DamageTypes).
        assert.are.equals(6, #mods)
        local coldToFire
        for _, m in ipairs(mods) do
            if m.name == "ColdDamageConvertToFire" then coldToFire = m end
            -- Fire->Fire must never be emitted (destination type is skipped).
            assert.are_not.equals("FireDamageConvertToFire", m.name)
            assert.are.equals("BASE", m.type)
            assert.are.equals(77, m.value)
            -- Every emitted conversion is scoped to the skill via a SkillName tag.
            assert.is_not_nil(m[1], "conversion mod must carry a tag")
            assert.are.equals("SkillName", m[1].type)
            assert.are.equals("Acid Flask", m[1].skillName)
        end
        assert.is_not_nil(coldToFire, "must emit ColdDamageConvertToFire")
    end)

    it("non-skill source falls back to recognition-only (LEB_NotSupported)", function()
        -- "nonexistentskill" is not a canonical skill => must NOT produce a
        -- conversion; the previous nsAny behaviour for global "base damage" is kept.
        local mods, extra = modLib.parseMod("100% of nonexistentskillxyz Base Damage converted to Cold")
        assert.is_nil(extra)
        assert.are.equals(1, #mods)
        assert.are.equals("LEB_NotSupported", mods[1].name)
    end)

    it("Vial of Volatile Ice cached string resolves to functional Acid Flask->Cold conversion", function()
        -- Exact unique string => served from the updated ModCache row.
        local mods, extra = modLib.parseMod("100% of Acid Flask Base Damage converted to Cold")
        assert.is_nil(extra)
        assert.are.equals(6, #mods)
        local found = {}
        for _, m in ipairs(mods) do
            found[m.name] = true
            assert.are.equals("Acid Flask", m[1].skillName)
            assert.are.equals(100, m.value)
            assert.are.equals("BASE", m.type)
        end
        -- Acid Flask's physical/poison base damage converts to Cold; Cold->Cold absent.
        assert.is_true(found.PhysicalDamageConvertToCold, "Physical base -> Cold")
        assert.is_true(found.PoisonDamageConvertToCold, "Poison base -> Cold")
        assert.is_nil(found.ColdDamageConvertToCold)
    end)

    it("conversion is scoped: a different skill does not see Acid Flask's conversion", function()
        local mods = modLib.parseMod("100% of Acid Flask Base Damage converted to Cold")
        local node = { modList = new("ModList") }
        for _, m in ipairs(mods) do node.modList:AddMod(m) end
        local acidSum = node.modList:Sum("BASE", { skillName = "Acid Flask" }, "PhysicalDamageConvertToCold")
        assert.are.equals(100, acidSum, "Acid Flask sees its own base->Cold conversion")
        local otherSum = node.modList:Sum("BASE", { skillName = "Meteor" }, "PhysicalDamageConvertToCold")
        assert.are.equals(0, otherSum, "conversion must not leak to other skills")
    end)

    -- Liath's Machinations (uniques_1_4.json #276): the amulet carries
    -- "50% of Fireball Base Damage Converted to Lightning" (a PARTIAL,
    -- skill-scoped base-damage conversion). The exact unique string was baked in
    -- ModCache.lua as LEB_NotSupported; that row is removed so it live-parses.
    -- This locks both the partial value (50, NOT renormalised to 100) and the
    -- Fireball SkillName scope, mirroring Vial's 100% Acid Flask->Cold above.
    it("Liath's: '50% of Fireball Base Damage converted to Lightning' live-parses to Fireball-scoped 50% conversion", function()
        local mods, extra = modLib.parseMod("50% of Fireball Base Damage Converted to Lightning")
        assert.is_nil(extra, "a fully-parsed Liath's base-damage conversion must leave no residue")
        -- One conversion per non-Lightning damage type (6 of the 7 DamageTypes).
        assert.are.equals(6, #mods)
        local fireToLightning
        for _, m in ipairs(mods) do
            if m.name == "FireDamageConvertToLightning" then fireToLightning = m end
            -- Lightning->Lightning must never be emitted (destination type is skipped).
            assert.are_not.equals("LightningDamageConvertToLightning", m.name)
            assert.are.equals("BASE", m.type)
            -- PARTIAL: the 50 must survive verbatim (it sets conversionTable mult = 1 - 0.5).
            assert.are.equals(50, m.value)
            assert.is_not_nil(m[1], "conversion mod must carry a tag")
            assert.are.equals("SkillName", m[1].type)
            assert.are.equals("Fireball", m[1].skillName)
        end
        assert.is_not_nil(fireToLightning, "Fireball's Fire base damage must convert to Lightning")
    end)

    it("Liath's: NOT baked as LEB_NotSupported in ModCache (live-parses)", function()
        local mods = modLib.parseMod("50% of Fireball Base Damage Converted to Lightning")
        assert.is_not_nil(mods)
        for _, m in ipairs(mods) do
            assert.are_not.equals("LEB_NotSupported", m.name,
                "the ModCache notSupported row must be removed so the handler live-parses")
        end
    end)

    it("Liath's: the 50% Fireball->Lightning conversion is skill-scoped (no global leak)", function()
        local mods = modLib.parseMod("50% of Fireball Base Damage Converted to Lightning")
        local node = { modList = new("ModList") }
        for _, m in ipairs(mods) do node.modList:AddMod(m) end
        assert.are.equals(50, node.modList:Sum("BASE", { skillName = "Fireball" }, "FireDamageConvertToLightning"),
            "Fireball sees its own 50% Fire->Lightning conversion")
        assert.are.equals(0, node.modList:Sum("BASE", { skillName = "Meteor" }, "FireDamageConvertToLightning"),
            "another fire skill must NOT inherit Fireball's base-damage conversion")
    end)

    -- Yulia's Path (Heoborean Boots, uniques.json #218) carries
    -- "100% of Maelstrom base damage converted to Necrotic". Investigated
    -- 2026-07-14 on a suspected model gap: this exact string is NOT baked in
    -- ModCache.lua (grep-confirmed absent), so parseMod's cache-miss path
    -- live-parses it through skillBaseDamageConversionHandler -- it is ALREADY
    -- MODELED, no parser/ModCache change was needed. Maelstrom's base is Cold
    -- (skills.json spell_base_cold_damage 8), so ColdDamageConvertToNecrotic is
    -- the conversion that actually fires; the 100% recolours its base Cold hit to
    -- Necrotic so it scales with Necrotic INC/pen. These cases lock that state so
    -- a future ModCache regen cannot silently re-bake the string as an empty
    -- LEB_NotSupported row (the exact failure mode of the sibling Meteor/Shurikens
    -- forms that DO have baked notSupported rows). No corpus build uses Maelstrom
    -- as a Yulia-scaled damage skill (<private build> equips Yulia but runs Maelstrom as
    -- a buff, includeInFullDPS="false"), so there is zero snapshot impact.
    it("Yulia: '100% of Maelstrom base damage converted to Necrotic' live-parses to Maelstrom-scoped conversion", function()
        local mods, extra = modLib.parseMod("100% of Maelstrom base damage converted to Necrotic")
        assert.is_nil(extra, "the exact Yulia's Path string must leave no residue")
        -- One conversion per non-Necrotic damage type (6 of the 7 DamageTypes).
        assert.are.equals(6, #mods)
        local coldToNecrotic
        for _, m in ipairs(mods) do
            if m.name == "ColdDamageConvertToNecrotic" then coldToNecrotic = m end
            -- Necrotic->Necrotic must never be emitted (destination type is skipped).
            assert.are_not.equals("NecroticDamageConvertToNecrotic", m.name)
            assert.are.equals("BASE", m.type)
            assert.are.equals(100, m.value)
            assert.is_not_nil(m[1], "conversion mod must carry a tag")
            assert.are.equals("SkillName", m[1].type)
            assert.are.equals("Maelstrom", m[1].skillName)
        end
        -- Maelstrom's base is Cold, so this is the conversion that materially fires.
        assert.is_not_nil(coldToNecrotic, "Maelstrom's Cold base damage must convert to Necrotic")
    end)

    it("Yulia: NOT baked as LEB_NotSupported in ModCache (guards against a future empty re-bake)", function()
        local mods = modLib.parseMod("100% of Maelstrom base damage converted to Necrotic")
        assert.is_not_nil(mods)
        assert.are_not.equals(0, #mods, "must not resolve to an empty modList")
        for _, m in ipairs(mods) do
            assert.are_not.equals("LEB_NotSupported", m.name,
                "the Yulia/Maelstrom string must live-parse, never bake to notSupported")
        end
    end)

    it("Yulia: the Maelstrom->Necrotic conversion is skill-scoped (no global leak)", function()
        local mods = modLib.parseMod("100% of Maelstrom base damage converted to Necrotic")
        local node = { modList = new("ModList") }
        for _, m in ipairs(mods) do node.modList:AddMod(m) end
        assert.are.equals(100, node.modList:Sum("BASE", { skillName = "Maelstrom" }, "ColdDamageConvertToNecrotic"),
            "Maelstrom sees its own Cold->Necrotic conversion")
        assert.are.equals(0, node.modList:Sum("BASE", { skillName = "Tornado" }, "ColdDamageConvertToNecrotic"),
            "another Primalist skill must NOT inherit Maelstrom's base-damage conversion")
    end)
end)
