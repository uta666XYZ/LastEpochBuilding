-- @leb-regression-guard:different-shape-idol-stat-effect
-- Locks the Wings of Discord legendary mod "100% increased effect of stats
-- on your Non-Unique Idols that are a different shape to all other equipped
-- Non-Unique Idols":
--   * parses to Multiplier:DifferentShapeIdolStatEffect BASE (was
--     LEB_NotSupported via a baked empty ModCache row),
--   * eligibility = non-unique (rarity not UNIQUE/SET, Reliquary Nest
--     convention) idol whose footprint shape (w x h) is unique among
--     equipped non-unique idols (three 1x1 Small idols disqualify each
--     other),
--   * composes ADDITIVELY with the altar refracted-slot boosts at the affix
--     value layer (1 + altar + wings), NOT multiplicatively at merge,
--   * unlike the altar boosts it applies to ALL affix subtypes (Heretical
--     weaver lines included).
-- Sheet-verified on StarSeaVnV (2026-06-10 3-layer ledger): Impaling Huge
-- Shadow pen prefix 8 -> 8 x (1 + 0.457 + 0.0998 + 1.0) = 20.48 (carried
-- pen 77.48 = tree 48 + LP 9 + 20.48; LEB integer-rounds the same chain to
-- 20, +-0.15% structural closure); weaver crit suffix 19 -> 38
-- (Wings only, altar-exempt); in-game cc 119% / multi-throwing 582% close
-- exactly. See REGRESSION_GUARDS.md "different-shape-idol-stat-effect".

describe("DifferentShapeIdolStatEffect parser", function()
    it("the Wings of Discord line parses to the marker multiplier", function()
        local mods, extra = modLib.parseMod("100% increased effect of stats on your Non-Unique Idols that are a different shape to all other equipped Non-Unique Idols")
        assert.is_nil(extra)
        assert.is_not_nil(mods)
        assert.are.equals(1, #mods)
        assert.are.equals("Multiplier:DifferentShapeIdolStatEffect", mods[1].name)
        assert.are.equals("BASE", mods[1].type)
        assert.are.equals(100, mods[1].value)
        assert.is_falsy(mods.notSupported)
    end)

    it("no stale ModCache row re-masks the parse", function()
        local f = assert(io.open("Data/ModCache.lua", "r"))
        local body = f:read("*a"); f:close()
        assert.is_nil(body:find("different shape to all other equipped Non%-Unique Idols\"%]={{}"),
            "baked empty row would short-circuit the new handler")
    end)
end)

describe("DifferentShapeIdolStatEffect CalcSetup wiring", function()
    it("pre-scan, per-idol shape eligibility, and additive composition are present", function()
        local f = assert(io.open("Modules/CalcSetup.lua", "r"))
        local text = f:read("*a"); f:close()
        assert.is_truthy(text:find("@leb%-regression%-guard:different%-shape%-idol%-stat%-effect"),
            "inline guard marker must be present in CalcSetup")
        assert.is_truthy(text:find('m.name == "Multiplier:DifferentShapeIdolStatEffect"', 1, true),
            "pre-scan must sum the marker multiplier")
        assert.is_truthy(text:find("local boost = altarPart + (wingsBoost or 0)", 1, true),
            "the wings boost must compose ADDITIVELY with the altar boost at the affix layer")
        assert.is_truthy(text:find('it.rarity ~= "UNIQUE"', 1, true)
            and text:find('it.rarity ~= "SET"', 1, true),
            "eligibility must follow the Reliquary Nest non-unique convention")
        assert.is_truthy(text:find("shapeCount[key] == 1", 1, true),
            "eligibility requires the idol's shape to be unique among equipped non-unique idols")
    end)
end)

describe("DifferentShapeIdolStatEffect end-to-end (StarSeaVnV)", function()
    it("doubles the different-shape idols' stats additively with the altar", function()
        local fh = io.open("../spec/TestBuilds/StarSeaVnV_LEB.xml", "r")
        if not fh then pending("StarSeaVnV_LEB.xml not present (spec/TestBuilds is gitignored)"); return end
        local xml = fh:read("*a"); fh:close()
        loadBuildFromXML(xml)
        local grp
        for i, g in ipairs(build.skillsTab.socketGroupList) do
            if not g.triggeredOnHit and not g.triggeredByTimer then
                for _, sk in ipairs(g.displaySkillList or {}) do
                    local nm = sk.activeEffect and sk.activeEffect.grantedEffect and sk.activeEffect.grantedEffect.name
                    if nm == "Shurikens" then grp = grp or i end
                end
            end
        end
        build.mainSocketGroup = grp
        build.calcsTab.input.skill_number = grp
        build.buildFlag = false
        build.calcsTab:BuildOutput()
        local ms = build.calcsTab.calcsEnv.player.mainSkill
        -- Ferret's Ornate Majasan (4x1, unique shape): 53/dagger x (1 + altar
        -- 0.557 + wings 1.0) = 135.52 -> 136 (round-half-up) x 2 daggers = 272
        -- at the default unlock rank 8 (its corner is rank-7-refracted).
        local ferret, loom, pen = 0, 0, 0
        for _, e in ipairs(ms.skillModList:Tabulate("INC", ms.skillCfg, "CritChance")) do
            if (e.mod.source or ""):find("Ferret") then ferret = e.value end
            if (e.mod.source or ""):find("Loom Walker") then loom = e.value end
        end
        assert.are.equals(272, ferret, "Ferret idol: (1 + altar + wings) additive, x2 daggers")
        -- Loom Walker's Small Weaver Idol shares its 1x1 shape with two other
        -- Small Weaver idols -> NOT eligible, stays unboosted.
        assert.are.equals(13, loom, "same-shape idols must not be doubled")
        pen = ms.skillModList:Sum("BASE", ms.skillCfg, "PhysicalPenetration")
        -- 9 (Xithara LP) + 48 (tree) + 20 (Impaling 8 x 2.557 round-half-up)
        assert.are.equals(77, pen, "pen prefix composes 1 + altar 0.557 + wings 1.0")
    end)
end)
