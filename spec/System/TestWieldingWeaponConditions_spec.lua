-- @leb-regression-guard: wielding-weapon-conditions
-- Locks two related "wielding a <weapon>" silent-failure parses:
--
-- 1. Mace condition recognition.
--    Sentinel/Forge Guard affixes such as "+N Melee Physical Damage if
--    wielding a Mace" (affixId 364 in
--    LE_datamining/extracted/items/single_affixes_v3.json) gate the bonus
--    on the player wielding a Mace. Before this guard:
--      - Mace was NOT in Data/Global.lua `DamageSourceWeapons`, so neither
--        `modFlagList["mace"]` nor `modTagList["with a mace"] /
--        ["while wielding a mace"]` existed.
--      - CalcSetup.lua had no `flag == "Mace"` branch, so the UsingMace
--        condition was never set even when a Mace was equipped.
--    Result: 14 cached Mace affix tiers parsed as bare PhysicalDamage BASE
--    with residue "   if wielding a Mace " — flat damage independent of
--    weapon type. Also broke SkillStatMap UsingMace gates
--    (Nightblade Elusive crit) which never activated.
--
-- 2. "while wielding a 2 Handed <weapon>" gate.
--    Affixes like "+N Spell Damage while wielding a 2 Handed Axe" parsed
--    with Condition:UsingAxe only — the "2 Handed" qualifier dropped to
--    residue, so the bonus applied to one-handed Axes too. Adds a
--    modTagList tagList combining Using<weapon> + UsingTwoHandedWeapon.
--
-- Four sites lock together:
-- a. `Data/Global.lua` DamageSourceWeapons includes "Mace".
-- b. `Modules/CalcSetup.lua` adds `flag == "Mace"` (and `"Spear"`)
--    branches publishing the corresponding UsingX conditions.
-- c. `Modules/ModParser.lua` `["while wielding a 2 handed <weapon>"]`
--    tagList entry (both weapon condition + UsingTwoHandedWeapon).
-- d. `Data/ModCache.lua` Mace + 2H Axe entries carry the corrected tags
--    and have empty residue strings.

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("WieldingWeaponConditions", function()
    local parserText, cacheText, setupText, globalText

    setup(function()
        parserText = readSource("Modules/ModParser.lua")
        cacheText  = readSource("Data/ModCache.lua")
        setupText  = readSource("Modules/CalcSetup.lua")
        globalText = readSource("Data/Global.lua")
    end)

    it("Global.lua DamageSourceWeapons includes Mace", function()
        assert.is_truthy(string.find(globalText,
            'DamageSourceWeapons%s*=%s*{[^}]-"Mace"', 1, false),
            "DamageSourceWeapons must list Mace so parser tag/flag loops cover it")
    end)

    it("CalcSetup.lua publishes UsingMace when wielding a Mace-flagged weapon", function()
        assert.is_truthy(string.find(setupText,
            'flag == "Mace" then env.modDB.conditions%["UsingMace"%] = true', 1, false),
            "CalcSetup must set UsingMace for Mace-flag weapons")
    end)

    it("CalcSetup.lua publishes UsingSpear when wielding a Spear-flagged weapon", function()
        assert.is_truthy(string.find(setupText,
            'flag == "Spear" then env.modDB.conditions%["UsingSpear"%] = true', 1, false),
            "CalcSetup must set UsingSpear for Spear-flag weapons")
    end)

    it("ModParser modTagList generates 'while wielding a 2 handed <weapon>' tagList entries", function()
        assert.is_truthy(string.find(parserText,
            'modTagList%["while wielding a 2 handed " %.%. weapon:lower%(%)%]', 1, false),
            "ModParser must build the 2-Handed weapon tagList entries")
        assert.is_truthy(string.find(parserText,
            'var = "UsingTwoHandedWeapon"', 1, false),
            "2-Handed entry must reference UsingTwoHandedWeapon condition")
    end)

    it("ModCache '+10 Melee Physical Damage if wielding a Mace' carries Condition:UsingMace", function()
        local needle = 'c%["%+10 Melee Physical Damage if wielding a Mace"%]={{%[1%]={%[1%]={type="Condition",var="UsingMace"},flags=0,keywordFlags=512,name="PhysicalDamage",type="BASE",value=10}},""}'
        assert.is_truthy(string.find(cacheText, needle, 1, false),
            "Mace affix entry must carry Condition:UsingMace tag with empty residue")
    end)

    it("ModCache '+1 Spell Damage while wielding a 2 Handed Axe' carries both UsingAxe AND UsingTwoHandedWeapon", function()
        local needle = 'c%["%+1 Spell Damage while wielding a 2 Handed Axe"%]={{%[1%]={%[1%]={type="Condition",var="UsingAxe"},%[2%]={type="Condition",var="UsingTwoHandedWeapon"},flags=0,keywordFlags=256,name="Damage",type="BASE",value=1}},""}'
        assert.is_truthy(string.find(cacheText, needle, 1, false),
            "2-Handed Axe affix entry must carry both UsingAxe and UsingTwoHandedWeapon tags")
    end)

    it("ModCache must NOT carry the stale '   if wielding a Mace ' residue", function()
        assert.is_nil(string.find(cacheText, '"   if wielding a Mace "', 1, true),
            "ModCache must not contain any '   if wielding a Mace ' residue strings")
    end)

    it("ModCache must NOT carry the stale '   while wielding a 2 Handed  ' residue", function()
        assert.is_nil(string.find(cacheText, '"   while wielding a 2 Handed  "', 1, true),
            "ModCache must not contain any '   while wielding a 2 Handed  ' residue strings")
    end)
end)
