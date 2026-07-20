-- @leb-regression-guard:tree-conversion-target-skill
-- Locks the limited-scope contract for buff-tree damage conversions: a
-- conversion advertised on a "while-active" buff tree may belong to a SINGLE
-- granted skill rather than the whole character.
--
-- Concretely: Flame Ward's fw3d-6 "Frost Ward" node carries " Fire -> Cold"
-- and its in-game description reads "globally converts {Fire Aura} to cold"
-- (datamined game source FireAuraMutator.coldConversionFromFlameWard). Active buff-tree
-- nodes are added to env.modDB with their SkillId tags STRIPPED so the buff's
-- defensive/utility mods apply globally — but that would also leak this
-- conversion onto every fire skill. CalcSetup.lua re-tags ONLY the conversion
-- mods (name contains "DamageConvertTo") with a SkillName tag for the
-- registered target skill, so the conversion lands on that skill's cfg alone.
--
-- Three coupled invariants:
--   (1) registry (Global.lua): LE_TREE_CONVERSION_TARGET_SKILL.fw3d == "Fire Aura".
--   (2) scoping semantics: a conversion mod tagged SkillName="Fire Aura" sums
--       only under a cfg whose skillName matches — NOT globally (nil cfg) and
--       NOT under another skill's cfg.
--   (3) wiring (CalcSetup.lua): applyBuffPrefix consults the registry and
--       re-tags DamageConvertTo mods with a SkillName tag.
--
-- Establishing observation (headless _FireAuraTest, Flame Ward forced active):
--   pre-fix  global env.modDB FireDamageConvertToCold = 100 (leaks to all fire skills)
--   post-fix global env.modDB FireDamageConvertToCold = 0,
--            Fire Aura skillModList FireDamageConvertToCold = 100 (scoped)
-- See REGRESSION_GUARDS.md > "tree-conversion-target-skill".

describe("TreeConversionTargetSkill", function()
    it("LE_TREE_CONVERSION_TARGET_SKILL maps fw3d to Fire Aura", function()
        assert.is_table(LE_TREE_CONVERSION_TARGET_SKILL,
            "LE_TREE_CONVERSION_TARGET_SKILL must be defined in Global.lua")
        assert.are.equal("Fire Aura", LE_TREE_CONVERSION_TARGET_SKILL["fw3d"])
        local f = io.open("Data/Global.lua", "r")
        assert.is_not_nil(f, "must be able to open Global.lua")
        local text = f:read("*a")
        f:close()
        assert.is_truthy(
            string.find(text, '%["fw3d"%]%s*=%s*"Fire Aura"'),
            "Global.lua LE_TREE_CONVERSION_TARGET_SKILL must include fw3d -> Fire Aura")
    end)

    it("a SkillName-tagged conversion applies only to that skill's cfg", function()
        -- Mirror the post-re-tag shape CalcSetup produces: a global conversion
        -- mod carrying a single SkillName tag for the target skill.
        local db = new("ModDB")
        db:NewMod("FireDamageConvertToCold", "BASE", 100, "Tree:fw3d-6",
            0, 0, { type = "SkillName", skillName = "Fire Aura" })

        local fireAuraCfg = { skillName = "Fire Aura" }
        local otherCfg = { skillName = "Fireball" }

        assert.are.equals(100, db:Sum("BASE", fireAuraCfg, "FireDamageConvertToCold"),
            "conversion must apply under the Fire Aura cfg")
        assert.are.equals(0, db:Sum("BASE", otherCfg, "FireDamageConvertToCold"),
            "conversion must NOT apply to a different skill (no leak)")
        assert.are.equals(0, db:Sum("BASE", nil, "FireDamageConvertToCold"),
            "conversion must NOT apply globally (nil cfg)")
    end)

    it("CalcSetup.lua re-tags buff-tree conversion mods with the target SkillName", function()
        -- Wiring safety net: if applyBuffPrefix stops consulting the registry
        -- or stops adding the SkillName tag, the scoping silently reverts to a
        -- global leak. Lock the source shape.
        local f = io.open("Modules/CalcSetup.lua", "r")
        assert.is_not_nil(f, "must be able to open CalcSetup.lua")
        local text = f:read("*a")
        f:close()
        assert.is_truthy(string.find(text, "LE_TREE_CONVERSION_TARGET_SKILL", 1, true),
            "CalcSetup must consult LE_TREE_CONVERSION_TARGET_SKILL")
        assert.is_truthy(string.find(text, "DamageConvertTo", 1, true),
            "CalcSetup must match conversion mods by DamageConvertTo")
        assert.is_truthy(string.find(text, 'type = "SkillName"', 1, true),
            "CalcSetup must add a SkillName tag to scope the conversion")
    end)

    -- FORM/transform trees: the conversion is scoped to the form's own attacks
    -- via a SkillId tag (value `true` in the registry). The buff-strip path
    -- (buildModListForNodeList stripSkillId) removes the SkillId that
    -- ProcessStats set, so without this re-tag the conversion leaks globally.
    -- Ground truth (probe <private build> lv97 Druid, pre-fix): wb8fo-26's
    -- PhysicalDamageConvertToLightning was UNTAGGED in env.modDB and the main
    -- Swarmblade Form skill's conversionTable showed Physical->Lightning = 1.0
    -- (a leak from the Werebear tree onto a different form's attack).
    it("registers FORM trees as SkillId-scoped (true) and EXCLUDES Symbols of Hope", function()
        local R = LE_TREE_CONVERSION_TARGET_SKILL
        assert.are.equal(true, R["wb8fo"],  "Werebear Form wb8fo must be SkillId-scoped (true)")
        assert.are.equal(true, R["sbf4m"],  "Swarmblade Form sbf4m must be SkillId-scoped (true)")
        assert.are.equal(true, R["sf5rd"],  "Spriggan Form sf5rd must be SkillId-scoped (true)")
        assert.are.equal(true, R["ds34l"],  "Death Seal ds34l must be SkillId-scoped (true)")
        assert.are.equal(true, R["rf1azz"], "Reaper Form rf1azz must be SkillId-scoped (true)")
        -- Symbols of Hope is a GENUINE player-global aura conversion (converts
        -- typed added too, validated in-game) — it must NOT be registered here.
        assert.is_nil(R["si4lgl"],
            "Symbols of Hope si4lgl must stay player-global (not registered)")
    end)

    it("a SkillId-tagged form conversion applies to the form AND its granted sub-skills, not others", function()
        -- Mirror the post-re-tag shape CalcSetup produces for a form: a global
        -- conversion mod carrying a single SkillId tag for the form's grantedEffect.id.
        local db = new("ModDB")
        db:NewMod("PhysicalDamageConvertToLightning", "BASE", 100, "Tree:wb8fo-26",
            0, 0, { type = "SkillId", skillId = "WerebearForm" })

        -- The form skill itself: cfg carries the matching grantedEffect.id.
        local formCfg = { skillGrantedEffect = { id = "WerebearForm" } }
        -- A sub-ability the form GRANTS: matches via groupSource "SkillId:<form id>".
        local grantedSubCfg = { skillGrantedEffect = { id = "Maul" }, groupSource = "SkillId:WerebearForm" }
        -- An unrelated skill in the same build (the leak victim).
        local otherCfg = { skillGrantedEffect = { id = "Swarmblade Form" } }

        assert.are.equals(100, db:Sum("BASE", formCfg, "PhysicalDamageConvertToLightning"),
            "conversion must apply to the form skill itself")
        assert.are.equals(100, db:Sum("BASE", grantedSubCfg, "PhysicalDamageConvertToLightning"),
            "conversion must apply to a sub-ability the form grants (via groupSource)")
        assert.are.equals(0, db:Sum("BASE", otherCfg, "PhysicalDamageConvertToLightning"),
            "conversion must NOT leak to an unrelated skill (the pre-fix bug)")
        assert.are.equals(0, db:Sum("BASE", nil, "PhysicalDamageConvertToLightning"),
            "conversion must NOT apply globally (nil cfg)")
    end)

    it("CalcSetup.lua re-tags form-tree conversions with a SkillId tag", function()
        local f = io.open("Modules/CalcSetup.lua", "r")
        assert.is_not_nil(f, "must be able to open CalcSetup.lua")
        local text = f:read("*a")
        f:close()
        assert.is_truthy(string.find(text, 'type = "SkillId"', 1, true),
            "CalcSetup must add a SkillId tag for form-scoped (true) conversions")
        assert.is_truthy(string.find(text, "buffSkillTreePrefixes[prefix].skillId", 1, true),
            "CalcSetup must scope form conversions to the buff group's own grantedEffect.id")
    end)
end)
