-- @leb-regression-guard:bulwark-of-the-last-abyss-apocalypse
-- Bulwark of the Last Abyss (Ironglass Shield, uniques_1_4.json) self-applies the
-- Apocalypse buff (3s, every 3s on high health, costs 25% current health). Per the
-- item's altText "The only effects of the Apocalypse buff are the ones listed on
-- this item" — those effects are two damage mods that live in the datamine
-- tooltipDescriptions (display-only, NOT the structured roll table) and were
-- dropped on transcription (same class as Frozen Ire / Hammer of Lorent):
--   "70% increased Void Damage during Apocalypse"
--   "+70% Melee Critical Strike Multiplier during Apocalypse"
-- Three coupled sites lock together:
--   (1) ModParser.lua conditions table: "during apocalypse" -> Condition:DuringApocalypse.
--   (2) ConfigOptions.lua: conditionDuringApocalypse check sets the Condition FLAG
--       (default OFF — Apocalypse is a self-damaging conditional buff, like other
--       conditional damage buffs; corpus builds stay inert so it is corpus-neutral).
--   (3) uniques_1_4.json Bulwark mods: the two transcribed strings.
-- See REGRESSION_GUARDS.md "bulwark-of-the-last-abyss-apocalypse".

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("BulwarkApocalypse", function()
    before_each(function()
        newBuild()
    end)

    it("'increased Void Damage during Apocalypse' parses to VoidDamage INC gated on DuringApocalypse", function()
        local mods, extra = modLib.parseMod("70% increased Void Damage during Apocalypse")
        assert.is_nil(extra, "must fully parse, no residue")
        assert.is_not_nil(mods)
        assert.are.equals(1, #mods)
        assert.are.equals("VoidDamage", mods[1].name)
        assert.are.equals("INC", mods[1].type)
        assert.are.equals(70, mods[1].value)
        local cond = mods[1][1]
        assert.is_not_nil(cond, "must carry a condition tag")
        assert.are.equals("Condition", cond.type)
        assert.are.equals("DuringApocalypse", cond.var)
    end)

    it("'Melee Critical Strike Multiplier during Apocalypse' parses to CritMultiplier gated on DuringApocalypse", function()
        local mods, extra = modLib.parseMod("+70% Melee Critical Strike Multiplier during Apocalypse")
        assert.is_nil(extra)
        assert.is_not_nil(mods)
        assert.are.equals(1, #mods)
        assert.are.equals("CritMultiplier", mods[1].name)
        assert.are.equals(70, mods[1].value)
        local cond = mods[1][1]
        assert.is_not_nil(cond)
        assert.are.equals("DuringApocalypse", cond.var)
    end)

    -- Behavioral gating: the Void Damage INC contributes ONLY when the
    -- conditionDuringApocalypse config is enabled (default OFF = inert).
    local function voidInc(condOn)
        build.configTab.input.conditionDuringApocalypse = condOn or false
        build.configTab.input.customMods = "70% increased Void Damage during Apocalypse"
        build.configTab:BuildModList()
        runCallback("OnFrame")
        return build.calcsTab.mainEnv.modDB:Sum("INC", { }, "VoidDamage")
    end

    it("default OFF -> the Apocalypse mod is inert (0 Void INC)", function()
        assert.are.equals(0, voidInc(false))
    end)

    it("conditionDuringApocalypse ON -> the Apocalypse mod applies (+70 Void INC)", function()
        assert.are.equals(70, voidInc(true))
    end)

    it("ModParser carries the guard marker and the 'during apocalypse' condition", function()
        local t = readSource("Modules/ModParser.lua")
        assert.is_truthy(string.find(t, "@leb-regression-guard:bulwark-of-the-last-abyss-apocalypse", 1, true))
        assert.is_truthy(string.find(t, '["during apocalypse"]', 1, true))
        assert.is_truthy(string.find(t, "DuringApocalypse", 1, true))
    end)

    it("ConfigOptions carries the guard marker and the conditionDuringApocalypse check", function()
        local t = readSource("Modules/ConfigOptions.lua")
        assert.is_truthy(string.find(t, "@leb-regression-guard:bulwark-of-the-last-abyss-apocalypse", 1, true))
        assert.is_truthy(string.find(t, "conditionDuringApocalypse", 1, true))
        assert.is_truthy(string.find(t, "Condition:DuringApocalypse", 1, true))
    end)

    it("uniques_1_4.json Bulwark carries both transcribed Apocalypse damage mods", function()
        local t = readSource("Data/Uniques/uniques_1_4.json")
        assert.is_truthy(string.find(t, "70% increased Void Damage during Apocalypse", 1, true),
            "Bulwark must carry the Void Damage Apocalypse mod")
        assert.is_truthy(string.find(t, "+70% Melee Critical Strike Multiplier during Apocalypse", 1, true),
            "Bulwark must carry the Melee Crit Multi Apocalypse mod")
    end)
end)
