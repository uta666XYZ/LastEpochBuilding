-- @leb-regression-guard:fire-aura-damage-per-uncapped-fire-res
-- "+X% Fire Aura Damage Per 1% Uncapped Fire Resistance" is the not-scaling stat
-- of the Mage-42 "Incinerating Aura" node (Spellblade Fire Aura tree, activates at
-- 5 points). Pre-fix the generic "+X% <skill> damage" path parsed the prefix to a
-- Fire-Aura-scoped MORE Damage but DROPPED "per 1% uncapped fire resistance" as
-- residue -- ModCache.lua:1899 baked
--   {{ ... value=1 ... }, "   Per 1% Uncapped  Resistance "}
-- i.e. a flat +1% more, silently losing the per-resistance scaling (a build with
-- ~86% uncapped fire resistance loses ~+86% more Fire Aura damage). The fix is an
-- anchored specialModList matcher (ModParser, scanned first) that keeps the
-- scaling as Multiplier:UncappedFireResist, auto-populated in CalcSetup.lua
-- (mirroring the existing UncappedResistTotal). No current corpus build allocates
-- the node, so this is verified at the parse + multiplier level (in-game DPS
-- ground truth exists only for builds that allocate it). See REGRESSION_GUARDS.md.
describe("TestFireAuraDamagePerUncappedFireRes", function()
    before_each(function() newBuild() end)

    local TEXT = "+1% Fire Aura Damage Per 1% Uncapped Fire Resistance"

    it("parses to Fire-Aura-scoped MORE Damage x Multiplier:UncappedFireResist, no residue", function()
        if modLib.parseModCache then modLib.parseModCache[TEXT] = nil end
        local mods, extra = modLib.parseMod(TEXT)
        assert.is_nil(extra, "must consume 'per 1% uncapped fire resistance' (residual='" .. tostring(extra) .. "')")
        assert.is_not_nil(mods)
        assert.are.equals(1, #mods)
        assert.are.equals("Damage", mods[1].name)
        assert.are.equals("MORE", mods[1].type)
        assert.are.equals(1, mods[1].value)
        local sawSkill, sawMult = false, false
        for _, tag in ipairs(mods[1]) do
            if tag.type == "SkillName" and tag.skillName == "Fire Aura" then sawSkill = true end
            if tag.type == "Multiplier" and tag.var == "UncappedFireResist" then sawMult = true end
        end
        assert.is_true(sawSkill, "expected SkillName=Fire Aura tag")
        assert.is_true(sawMult, "expected Multiplier=UncappedFireResist tag")
    end)

    it("ModCache row is re-baked (no stale residue)", function()
        -- The baked Data/ModCache.lua row must match the fresh parse (residue nil),
        -- else the runtime short-circuits to the broken pre-fix flat value.
        local cached = modLib.parseModCache and modLib.parseModCache[TEXT]
        assert.is_not_nil(cached, "ModCache must contain the row")
        assert.is_nil(cached[2], "baked residue must be nil (was '   Per 1% Uncapped  Resistance ')")
        assert.is_not_nil(cached[1] and cached[1][1], "baked mod must be present")
        local sawMult = false
        for _, tag in ipairs(cached[1][1]) do
            if tag.type == "Multiplier" and tag.var == "UncappedFireResist" then sawMult = true end
        end
        assert.is_true(sawMult, "baked mod must carry Multiplier:UncappedFireResist")
    end)

    it("the multiplier scales Fire Aura damage as MORE and is skill-scoped", function()
        local db = new("ModDB")
        for _, m in ipairs(modLib.parseMod(TEXT)) do db:AddMod(m) end
        db:NewMod("Multiplier:UncappedFireResist", "BASE", 86, "test")
        -- 1% more per 1% uncapped fire res x86 => +86% more => x1.86
        assert.are.equals(1.86, round(db:More({ skillName = "Fire Aura" }, "Damage"), 2))
        -- SkillName-scoped: other skills unaffected
        assert.are.equals(1, db:More({ skillName = "Shatter Strike" }, "Damage"))
    end)

    it("CalcSetup auto-populates Multiplier:UncappedFireResist from uncapped fire resistance", function()
        local xmlPath = "../spec/TestBuilds/1.4/ShutFackUp lv85 Spellblade.xml"
        local fh = io.open(xmlPath, "r")
        if not fh then pending("ShutFackUp build XML not present (spec/TestBuilds gitignored)"); return end
        local xml = fh:read("*a"); fh:close()
        loadBuildFromXML(xml)
        build.configTab:BuildModList()
        build.buildFlag = true
        build:OnFrame({})
        local env = build.calcsTab.mainEnv
        local uncappedFire = env.modDB:Sum("BASE", nil, "FireResist")
        local mult = env.modDB:Sum("BASE", nil, "Multiplier:UncappedFireResist")
        assert.is_true(uncappedFire > 0, "build should have uncapped fire resistance")
        assert.are.equals(uncappedFire, mult, "Multiplier:UncappedFireResist must equal Sum BASE FireResist")
    end)
end)
