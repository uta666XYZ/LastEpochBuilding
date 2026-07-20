-- @leb-regression-guard: with-2h-suffix-family
-- Locks the parser + ModCache for the colloquial "With 2h" suffix family
-- used by passive-tree nodes. 7 silent-failure entries (Sentinel Champion
-- of the Forge / Master of Arms, Warpath Battlemaster's Blade, Tempest
-- Strike Heorot's Arsenal, Rogue Expert Duelist) were emitting bare mods
-- with the "With 2h" / "With 2h Weapon" / "With 2h Sword" text dropped
-- into ModCache slot[2] residue.
--
-- Two sites lock together:
-- a. ModParser.lua modTagList: new "with 2h", "with 2h weapon", and
--    "with 2h <weapon>" suffix entries (the per-weapon variant combines
--    Using<Weapon> + UsingTwoHandedWeapon, mirroring the existing
--    "while wielding a 2 handed <weapon>" precedent).
-- b. ModCache.lua: 7 entries carry the UsingTwoHandedWeapon condition
--    (plus subtype condition where applicable) with empty residue.

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("With2hSuffixFamily", function()
    local parserText, cacheText

    setup(function()
        parserText = readSource("Modules/ModParser.lua")
        cacheText  = readSource("Data/ModCache.lua")
    end)

    it("ModParser registers 'with 2h' and 'with 2h weapon' generic suffixes", function()
        assert.is_truthy(string.find(parserText,
            'modTagList%["with 2h"%]%s*=%s*{%s*tag%s*=%s*{%s*type%s*=%s*"Condition",%s*var%s*=%s*"UsingTwoHandedWeapon"'),
            "ModParser must register generic 'with 2h' suffix")
        assert.is_truthy(string.find(parserText,
            'modTagList%["with 2h weapon"%]%s*=%s*{%s*tag%s*=%s*{%s*type%s*=%s*"Condition",%s*var%s*=%s*"UsingTwoHandedWeapon"'),
            "ModParser must register 'with 2h weapon' suffix")
    end)

    it("ModParser registers per-weapon 'with 2h <weapon>' inside the DamageSourceWeapons loop", function()
        assert.is_truthy(string.find(parserText,
            'modTagList%["with 2h " %.%. weapon:lower%(%)%] = { tagList = { { type = "Condition", var = "Using" %.%. weapon }, { type = "Condition", var = "UsingTwoHandedWeapon" } } }',
            1, false),
            "ModParser must register per-weapon 'with 2h <weapon>' tagList")
    end)

    it("ModCache: '+1% Critical Multiplier Per 2 Strength With 2h' carries PerStat:Str div=2 + UsingTwoHandedWeapon", function()
        local needle = 'c%["%+1%% Critical Multiplier Per 2 Strength With 2h"%]={{%[1%]={%[1%]={div=2,stat="Str",type="PerStat"},%[2%]={type="Condition",var="UsingTwoHandedWeapon"},flags=0,keywordFlags=0,name="CritMultiplier",type="BASE",value=1}},""}'
        assert.is_truthy(string.find(cacheText, needle, 1, false))
    end)

    it("ModCache: '+2 Strength With 2h Weapon' carries UsingTwoHandedWeapon", function()
        local needle = 'c%["%+2 Strength With 2h Weapon"%]={{%[1%]={%[1%]={type="Condition",var="UsingTwoHandedWeapon"},flags=0,keywordFlags=0,name="Str",type="BASE",value=2}},""}'
        assert.is_truthy(string.find(cacheText, needle, 1, false))
    end)

    it("ModCache: '+20% Area With 2h' carries UsingTwoHandedWeapon", function()
        local needle = 'c%["%+20%% Area With 2h"%]={{%[1%]={%[1%]={type="Condition",var="UsingTwoHandedWeapon"},flags=0,keywordFlags=0,name="AreaOfEffect",type="BASE",value=20}},""}'
        assert.is_truthy(string.find(cacheText, needle, 1, false))
    end)

    it("ModCache: '+8 Spell Damage With 2h Weapon' carries UsingTwoHandedWeapon (Spell keywordFlags=256)", function()
        local needle = 'c%["%+8 Spell Damage With 2h Weapon"%]={{%[1%]={%[1%]={type="Condition",var="UsingTwoHandedWeapon"},flags=0,keywordFlags=256,name="Damage",type="BASE",value=8}},""}'
        assert.is_truthy(string.find(cacheText, needle, 1, false))
    end)

    it("ModCache: '10% Increased Critical Chance With 2h' carries UsingTwoHandedWeapon", function()
        local needle = 'c%["10%% Increased Critical Chance With 2h"%]={{%[1%]={%[1%]={type="Condition",var="UsingTwoHandedWeapon"},flags=0,keywordFlags=0,name="CritChance",type="INC",value=10}},""}'
        assert.is_truthy(string.find(cacheText, needle, 1, false))
    end)

    it("ModCache: '10% Increased Melee Attack Speed With 2h Sword' carries UsingSword + UsingTwoHandedWeapon", function()
        local needle = 'c%["10%% Increased Melee Attack Speed With 2h Sword"%]={{%[1%]={%[1%]={type="Condition",var="UsingSword"},%[2%]={type="Condition",var="UsingTwoHandedWeapon"},flags=3584,keywordFlags=512,name="Speed",type="INC",value=10}},""}'
        assert.is_truthy(string.find(cacheText, needle, 1, false))
    end)

    it("ModCache: '7% Increased Melee Damage With 2h Weapon' carries UsingTwoHandedWeapon (Melee keywordFlags=512)", function()
        local needle = 'c%["7%% Increased Melee Damage With 2h Weapon"%]={{%[1%]={%[1%]={type="Condition",var="UsingTwoHandedWeapon"},flags=0,keywordFlags=512,name="Damage",type="INC",value=7}},""}'
        assert.is_truthy(string.find(cacheText, needle, 1, false))
    end)

    it("ModCache: no With-2h entry retains the stale residue form", function()
        local keys = {
            { '%+1%% Critical Multiplier Per 2 Strength With 2h', '   With 2h ' },
            { '%+2 Strength With 2h Weapon', '  With 2h Weapon ' },
            { '%+20%% Area With 2h', '  With 2h ' },
            { '%+8 Spell Damage With 2h Weapon', '   With 2h Weapon ' },
            { '10%% Increased Critical Chance With 2h', '  With 2h ' },
            { '10%% Increased Melee Attack Speed With 2h Sword', '   With 2h  ' },
            { '7%% Increased Melee Damage With 2h Weapon', '   With 2h Weapon ' },
        }
        for _, kv in ipairs(keys) do
            local needle = 'c%["' .. kv[1] .. '"%].-"' .. string.gsub(kv[2], "%%", "%%%%") .. '"}'
            assert.is_nil(string.find(cacheText, needle),
                "With-2h entry must not carry stale residue: " .. kv[1])
        end
    end)
end)
