-- @leb-regression-guard:thornshell-flat-reflect-per-attunement
-- See REGRESSION_GUARDS.md "thornshell-flat-reflect-per-attunement".
-- Validation provenance is retained in maintainer notes.

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("ThornshellFlatReflectPerAttunement", function()
    before_each(function()
        newBuild()
    end)

    it("live-parse '6% increased flat damage reflected to attackers per attunement' emits a clean INC mod", function()
        -- lowercase / 6% roll is NOT a ModCache key -> exercises the live parser
        local mods, extra = modLib.parseMod("6% increased flat damage reflected to attackers per attunement")
        assert.is_nil(extra, "the 'flat' prefix must be consumed, not left as residue")
        assert.is_not_nil(mods)
        assert.are.equals(1, #mods)
        assert.are.equals("DamageReflectedToAttackers", mods[1].name)
        assert.are.equals("INC", mods[1].type)
        assert.are.equals(6, mods[1].value)
        assert.are.equals("PerStat", mods[1][1].type)
        assert.are.equals("Att", mods[1][1].stat)
    end)

    it("BASE form '+50 damage reflected to attackers' still parses as BASE (no regression)", function()
        local mods = modLib.parseMod("+50 damage reflected to attackers")
        assert.is_not_nil(mods)
        assert.are.equals(1, #mods)
        assert.are.equals("DamageReflectedToAttackers", mods[1].name)
        assert.are.equals("BASE", mods[1].type)
        assert.are.equals(50, mods[1].value)
    end)

    it("output.DamageReflectedToAttackers scales by 5% per Attunement", function()
        -- baseline: flat 100 + attunement, no per-Att INC
        build.configTab.input.customMods = "+100 Damage Reflected to Attackers\n+100 Attunement"
        build.configTab:BuildModList()
        runCallback("OnFrame")
        local base = build.calcsTab.calcsOutput.DamageReflectedToAttackers
        local att = build.calcsTab.calcsOutput.Att
        assert.is_true(att > 0, "test needs Attunement > 0 to exercise the PerStat scaling")

        build.configTab.input.customMods =
            "+100 Damage Reflected to Attackers\n+100 Attunement\n" ..
            "5% increased flat damage reflected to attackers per attunement"
        build.configTab:BuildModList()
        runCallback("OnFrame")
        local withInc = build.calcsTab.calcsOutput.DamageReflectedToAttackers

        -- INC = 5 * Att (PerStat); the flat is multiplied by (1 + INC/100)
        assert.are.equals(base * (1 + 5 * att / 100), withInc,
            "flat reflect must gain 5% per point of Attunement")
    end)

    it("ModParser parse site carries the named guard marker and the flat modName key", function()
        local parserText = readSource("Modules/ModParser.lua")
        assert.is_truthy(string.find(parserText,
            "@leb-regression-guard: thornshell-flat-reflect-per-attunement", 1, true),
            "parse site must carry the named guard marker")
        assert.is_truthy(string.find(parserText,
            '["flat damage reflected to attackers"] = "DamageReflectedToAttackers"', 1, true),
            "parser must map the 'flat' prefixed name to DamageReflectedToAttackers")
    end)

    it("CalcDefence calc site carries the named guard marker and applies INC/MORE", function()
        local calcText = readSource("Modules/CalcDefence.lua")
        assert.is_truthy(string.find(calcText,
            "@leb-regression-guard: thornshell-flat-reflect-per-attunement", 1, true),
            "calc site must carry the named guard marker")
        assert.is_truthy(string.find(calcText,
            'modDB:Sum("BASE", nil, "DamageReflectedToAttackers") * calcLib.mod(modDB, nil, "DamageReflectedToAttackers")', 1, true),
            "calc must multiply the flat by (1 + INC/100) * MORE")
    end)

    it("ModCache entry for the 5% node text is residue-free (not a ' Flat ' stub)", function()
        local cacheText = readSource("Data/ModCache.lua")
        assert.is_truthy(string.find(cacheText,
            'c["5% Increased Flat Damage Reflected to Attackers per Attunement"]={{[1]={[1]={stat="Att",type="PerStat"},flags=0,keywordFlags=0,name="DamageReflectedToAttackers",type="INC",value=5}},nil}', 1, true),
            "ModCache must carry the clean parsed INC mod for the 5% Thornshell text")
        assert.is_nil(string.find(cacheText,
            'name="DamageReflectedToAttackers",type="INC",value=5}}," Flat', 1, true),
            "the stale ' Flat ' residue stub must not remain")
    end)
end)
