-- @leb-regression-guard:apocrypha-incregen-to-armour
-- Locks the Warlock passive Apocrypha (Acolyte-58, tree_3.json, maxPoints 10)
-- cross-stat increased-conversion: its notScalingStat
--   "50% Increased Mana Regen -> Increased Armor"
-- means 50% of the build's total Increased Mana Regen ALSO applies as Increased
-- Armour (PoB's "X% of increased Y also applies to Z" pattern). Datamine value
-- (50%) is ground truth.
--
-- Two coupled sites lock together:
--   (1) parser (ModParser.lua parseArrowConversion): the "->" branch handled
--       ONLY damage-type conversions and returned nil for stat-INC conversions,
--       so parseMod dropped the whole line as `extra` residue (0 mods). Now it
--       emits an IncreasedStatConversion LIST mod { src, dst, fraction } when
--       BOTH sides carry "increased" and both stat names resolve to single-stat
--       modName strings via modNameList.
--   (2) calc (CalcDefence.lua armour site): when summing Armour INC, fold in
--       `fraction% * modDB:Sum("INC", nil, src)` for every IncreasedStatConversion
--       whose dst == "Armour". The converted INC is scaled inside the same
--       (1 + INC/100) * MORE term as native Armour INC. No feedback loop (src is
--       never Armour) and no modDB mutation (source INC is read at calc time).
--   (3) ModCache (Data/ModCache.lua): the prebaked entry for the canonical node
--       text was a silent-failure stub {{}, fullstring}; modLib.parseMod serves
--       the cache before re-parsing, so the stub must be replaced with the
--       parsed conversion mod or the live parser fix never reaches builds.
--
-- See REGRESSION_GUARDS.md "apocrypha-incregen-to-armour".

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("ApocryphaIncRegenToArmour", function()
    before_each(function()
        newBuild()
    end)

    it("live-parse 'N% increased mana regen -> increased armour' emits the conversion mod", function()
        -- Lowercase / British-spelling form is NOT a ModCache key, so it
        -- exercises the live ModParser arrow-conversion branch.
        local mods, extra = modLib.parseMod("50% increased mana regen -> increased armour")
        assert.is_nil(extra)
        assert.is_not_nil(mods)
        assert.are.equals(1, #mods)
        assert.are.equals("IncreasedStatConversion", mods[1].name)
        assert.are.equals("LIST", mods[1].type)
        assert.are.equals("ManaRegen", mods[1].value.src)
        assert.are.equals("Armour", mods[1].value.dst)
        assert.are.equals(50, mods[1].value.fraction)
    end)

    it("canonical node text 'Increased Armor' (American spelling) also resolves", function()
        local mods = modLib.parseMod("50% Increased Mana Regen -> Increased Armor")
        assert.is_not_nil(mods)
        assert.are.equals(1, #mods)
        assert.are.equals("IncreasedStatConversion", mods[1].name)
        assert.are.equals("ManaRegen", mods[1].value.src)
        assert.are.equals("Armour", mods[1].value.dst)
        assert.are.equals(50, mods[1].value.fraction)
    end)

    it("does NOT over-match: a damage-type '->' still converts as damage, not a stat conversion", function()
        local mods = modLib.parseMod("Fire -> Cold")
        assert.is_not_nil(mods)
        assert.are.equals(1, #mods)
        assert.are.equals("FireDamageConvertToCold", mods[1].name)
    end)

    it("does NOT match a one-sided form (missing 'increased' on the source)", function()
        -- "mana regen" without the increased qualifier is not the INC-aggregate
        -- form; the branch must decline (no conversion mod).
        local mods = modLib.parseMod("50% mana regen -> increased armour")
        local hasConv = false
        for _, m in ipairs(mods or {}) do
            if m.name == "IncreasedStatConversion" then hasConv = true end
        end
        assert.is_false(hasConv, "one-sided form must not emit a stat conversion")
    end)

    -- Behavioral calc guard: in a build env, Armour INC gains fraction% of the
    -- total ManaRegen INC. We isolate the conversion's effect by diffing two
    -- builds identical except for the conversion line. The delta depends only on
    -- the flat Armour base (1000) and the converted INC, independent of any
    -- default-build Armour INC, so it stays robust to unrelated baseline drift.
    local function armourWith(convLine)
        build.configTab.input.customMods =
            "+1000 to armour\n300% increased Mana Regen\n" .. (convLine or "")
        build.configTab:BuildModList()
        runCallback("OnFrame")
        return build.calcsTab.calcsOutput.Armour, build.calcsTab.calcsOutput.ManaRegenInc
    end

    it("Armour gains 50% of total ManaRegen INC once the conversion applies", function()
        local noConv, manaRegenIncA = armourWith(nil)
        local withConv, manaRegenIncB = armourWith("50% Increased Mana Regen -> Increased Armor")
        assert.are.equals(300, manaRegenIncA)
        assert.are.equals(300, manaRegenIncB)
        -- Converted Armour INC = 50% * 300 = 150 -> on the 1000 flat Armour base
        -- that is +1500 Armour (More multiplier = 1 for this minimal build).
        assert.are.equals(1500, withConv - noConv,
            "Armour must gain baseArmour(1000) * 50% * ManaRegenInc(300)/100 = 1500")
    end)

    it("conversion scales proportionally with the source INC (fraction is honoured)", function()
        -- Double the ManaRegen INC -> double the converted Armour contribution.
        build.configTab.input.customMods =
            "+1000 to armour\n600% increased Mana Regen\n50% Increased Mana Regen -> Increased Armor"
        build.configTab:BuildModList()
        runCallback("OnFrame")
        local withConv = build.calcsTab.calcsOutput.Armour
        build.configTab.input.customMods = "+1000 to armour\n600% increased Mana Regen\n"
        build.configTab:BuildModList()
        runCallback("OnFrame")
        local noConv = build.calcsTab.calcsOutput.Armour
        -- 50% * 600 = 300 INC -> +3000 Armour on the 1000 base.
        assert.are.equals(3000, withConv - noConv,
            "doubling ManaRegen INC must double the converted Armour contribution")
    end)

    it("ModParser parse site carries the named guard marker", function()
        local parserText = readSource("Modules/ModParser.lua")
        assert.is_truthy(string.find(parserText,
            "@leb-regression-guard:apocrypha-incregen-to-armour", 1, true),
            "parse site must carry the named guard marker")
        assert.is_truthy(string.find(parserText, "IncreasedStatConversion", 1, true),
            "parser must emit the IncreasedStatConversion mod name")
    end)

    it("CalcDefence calc site carries the named guard marker and reads the LIST", function()
        local calcText = readSource("Modules/CalcDefence.lua")
        assert.is_truthy(string.find(calcText,
            "@leb-regression-guard:apocrypha-incregen-to-armour", 1, true),
            "calc site must carry the named guard marker")
        assert.is_truthy(string.find(calcText,
            'modDB:List(nil, "IncreasedStatConversion")', 1, true),
            "calc must read the IncreasedStatConversion LIST")
    end)

    it("ModCache entry for the canonical node text is the parsed conversion, not a silent-failure stub", function()
        local cacheText = readSource("Data/ModCache.lua")
        assert.is_truthy(string.find(cacheText,
            'name="IncreasedStatConversion",type="LIST",value={dst="Armour",fraction=50,src="ManaRegen"}', 1, true),
            "ModCache must carry the parsed conversion mod for the Apocrypha node text")
        assert.is_nil(string.find(cacheText,
            'c["50% Increased Mana Regen -> Increased Armor"]={{},"50% Increased Mana Regen -> Increased Armor"}', 1, true),
            "the stale silent-failure stub must not remain")
    end)
end)
