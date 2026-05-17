-- @leb-regression-guard: per-bleed-stack-suffix-family
-- Locks parser + ModCache for the per-Bleed-stack suffix family used by
-- passive-tree stats. 22 silent-failure entries had "Bleed" eaten as a
-- SkillName tag (because the parser had no modTagList match for the
-- colloquial "per Bleed" / "per 10 Bleeds on the target" / "per stack of
-- bleed on you" / "per 10% Bleed chance" forms), letting the inner mod
-- apply unconditionally (or scoped only to the "Bleed" skill which is
-- wrong).
--
-- Two sites lock together:
-- a. ModParser.lua: new modTagList entries for the 7 colloquial suffix
--    forms; each maps to either Multiplier:BleedStack (with the right
--    actor / div / limit) or PerStat:BleedChance.
-- b. ModCache.lua: 22 entries carry the correct tag (or composite
--    SkillName + BleedStack) with empty residue.
--
-- Two entries (`1% Chance per Bleed for Haste on Enemy Death`,
-- `15% Maximum Damage Per Bleed`) are GATED only — they stop applying
-- unconditionally but still need follow-up infrastructure work (minion
-- buff trigger / cross-stat limit linking respectively). See
-- REGRESSION_GUARDS.md "Known follow-ups" for context.

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("PerBleedStackSuffixFamily", function()
    local parserText, cacheText

    setup(function()
        parserText = readSource("Modules/ModParser.lua")
        cacheText  = readSource("Data/ModCache.lua")
    end)

    it("ModParser registers all 7 per-Bleed colloquial suffix forms", function()
        local needles = {
            '%["per bleed"%]%s*=%s*{%s*tag%s*=%s*{%s*type%s*=%s*"Multiplier",%s*var%s*=%s*"BleedStack",%s*actor%s*=%s*"enemy"',
            '%["per 10 bleeds on the target, up to 200 bleeds"%]%s*=%s*{%s*tag%s*=%s*{%s*type%s*=%s*"Multiplier",%s*var%s*=%s*"BleedStack",%s*actor%s*=%s*"enemy",%s*div%s*=%s*10,%s*limit%s*=%s*20',
            '%["per 10 bleeds on enemy, up to 20%%"%]%s*=%s*{%s*tag%s*=%s*{%s*type%s*=%s*"Multiplier",%s*var%s*=%s*"BleedStack",%s*actor%s*=%s*"enemy",%s*div%s*=%s*10,%s*limit%s*=%s*20',
            '%["per stack of bleed on you"%]%s*=%s*{%s*tag%s*=%s*{%s*type%s*=%s*"Multiplier",%s*var%s*=%s*"BleedStack",%s*actor%s*=%s*"self"',
            '%["per stack of bleed on the enemy releasing it"%]%s*=%s*{%s*tag%s*=%s*{%s*type%s*=%s*"Multiplier",%s*var%s*=%s*"BleedStack",%s*actor%s*=%s*"enemy",%s*limit%s*=%s*20',
            '%["per stack of bleed on the target"%]%s*=%s*{%s*tag%s*=%s*{%s*type%s*=%s*"Multiplier",%s*var%s*=%s*"BleedStack",%s*actor%s*=%s*"enemy"',
            '%["per 10%% bleed chance"%]%s*=%s*{%s*tag%s*=%s*{%s*type%s*=%s*"PerStat",%s*stat%s*=%s*"BleedChance",%s*div%s*=%s*10',
        }
        for _, needle in ipairs(needles) do
            assert.is_truthy(string.find(parserText, needle),
                "ModParser must register suffix matching pattern: " .. needle)
        end
    end)

    -- Pattern A: bare "per Bleed" / "Per Bleed"
    it("ModCache: 10 bare 'per Bleed' entries carry Multiplier:BleedStack actor=enemy with empty residue", function()
        local keys = {
            '%+1%% Hit Damage Per Bleed',
            '%+1%% Melee Damager per Bleed',
            '%+2%% Melee Damage Per Bleed',
            '%+3%% Melee Damage Per Bleed',
            '1%% Melee Damage per Bleed',
            '5%% More Crit Chance per Bleed',
            '15%% Maximum Damage Per Bleed',
        }
        for _, k in ipairs(keys) do
            local needle = 'c%["' .. k .. '"%]={{%[1%]={%[1%]={actor="enemy",type="Multiplier",var="BleedStack"}'
            assert.is_truthy(string.find(cacheText, needle),
                "missing Multiplier:BleedStack tag: " .. k)
            local stale = 'c%["' .. k .. '"%]={{[^\n]-}},"[^"][^\n]*"}'
            assert.is_nil(string.find(cacheText, stale),
                "stale residue still present: " .. k)
        end
    end)

    -- Pattern A composite: SkillName + BleedStack (Locust Swarm / Recalled Blades)
    it("ModCache: composite 'X Skill Y Per Bleed' entries carry SkillName + BleedStack tags", function()
        local needle = 'c%["%+5%% Locust Swarm Area Per Bleed"%]={{%[1%]={%[1%]={skillName="Locust Swarm",type="SkillName"},%[2%]={actor="enemy",type="Multiplier",var="BleedStack"}'
        assert.is_truthy(string.find(cacheText, needle))
        needle = 'c%["5%% Locust Swarm Increased Damage Per Bleed"%]={{%[1%]={%[1%]={skillName="Locust Swarm",type="SkillName"},%[2%]={actor="enemy",type="Multiplier",var="BleedStack"}'
        assert.is_truthy(string.find(cacheText, needle))
        needle = 'c%["%+3%% Recalled Blades Hit Damage Per Bleed"%]={{%[1%]={%[1%]={skillName="Recalled Blades",type="SkillName"},%[2%]={actor="enemy",type="Multiplier",var="BleedStack"}'
        assert.is_truthy(string.find(cacheText, needle))
    end)

    -- Pattern B: per 10 Bleeds with div+limit
    it("ModCache: 6 Critical Strike Multiplier 'per 10 Bleeds' entries carry div=10 limit=20", function()
        for _, n in ipairs({ 1, 2, 3, 5, 7, 11 }) do
            local needle = 'c%["%+' .. n .. '%% Critical Strike Multiplier per 10 Bleeds on the target, up to 200 Bleeds"%]={{%[1%]={%[1%]={actor="enemy",div=10,limit=20,type="Multiplier",var="BleedStack"},flags=0,keywordFlags=0,name="CritMultiplier",type="BASE",value=' .. n .. '}},""}'
            assert.is_truthy(string.find(cacheText, needle),
                "+" .. n .. "% Critical Strike Multiplier entry must carry div=10 limit=20")
        end
    end)

    it("ModCache: Poison Damage 'per 10 Bleeds on Enemy, up to 20%' carries div=10 limit=20", function()
        local needle = 'c%["1%% More Poison Damage per 10 Bleeds on Enemy, up to 20%%"%]={{%[1%]={%[1%]={actor="enemy",div=10,limit=20,type="Multiplier",var="BleedStack"},flags=0,keywordFlags=0,name="PoisonDamage",type="MORE",value=1}},""}'
        assert.is_truthy(string.find(cacheText, needle))
    end)

    -- Pattern C: per stack of Bleed composites
    it("ModCache: 'with Shatter Strike per stack of bleed on you' carries SkillName + actor=self BleedStack", function()
        local needle = 'c%["%+2%% Cold Penetration with Shatter Strike per stack of bleed on you"%]={{%[1%]={%[1%]={skillName="Shatter Strike",type="SkillName"},%[2%]={actor="self",type="Multiplier",var="BleedStack"},flags=0,keywordFlags=0,name="ColdPenetration",type="BASE",value=2}},""}'
        assert.is_truthy(string.find(cacheText, needle))
    end)

    it("ModCache: 'Primordial Blood per stack of Bleed on the enemy releasing it' carries limit=20", function()
        local needle = 'c%["%+69%% Chance to inflict Bleed on Hit for Primordial Blood per stack of Bleed on the enemy releasing it %(up to 20%)"%]={{%[1%]={%[1%]={skillName="Primordial Blood",type="SkillName"},%[2%]={actor="enemy",limit=20,type="Multiplier",var="BleedStack"},flags=8388608,keywordFlags=0,name="BleedChance",type="BASE",value=69}},""}'
        assert.is_truthy(string.find(cacheText, needle))
    end)

    it("ModCache: 'Health gained on Kill per stack of Bleed on the Target' carries KilledRecently + BleedStack", function()
        local needle = 'c%["20 Health gained on Kill per stack of Bleed on the Target"%]={{%[1%]={%[1%]={type="Condition",var="KilledRecently"},%[2%]={actor="enemy",type="Multiplier",var="BleedStack"},flags=0,keywordFlags=0,name="Life",type="BASE",value=20}},""}'
        assert.is_truthy(string.find(cacheText, needle))
    end)

    -- Pattern D: per 10% Bleed chance
    it("ModCache: '+1% Damage per 10% Bleed chance' carries PerStat:BleedChance div=10", function()
        local needle = 'c%["%+1%% Damage per 10%% Bleed chance"%]={{%[1%]={%[1%]={div=10,stat="BleedChance",type="PerStat"},flags=0,keywordFlags=0,name="Damage",type="MORE",value=1}},""}'
        assert.is_truthy(string.find(cacheText, needle))
    end)

    -- Gated entry E: '1% Chance per Bleed for Haste on Enemy Death'
    it("ModCache: gated '1% Chance per Bleed for Haste on Enemy Death' carries BleedStack (full minion-trigger pending)", function()
        local needle = 'c%["1%% Chance per Bleed for Haste on Enemy Death"%]={{%[1%]={%[1%]={actor="enemy",type="Multiplier",var="BleedStack"},flags=0,keywordFlags=0,name="HasteOnEnemyDeathChance",type="BASE",value=1}},""}'
        assert.is_truthy(string.find(cacheText, needle))
    end)

    it("ModCache: no per-Bleed entry retains stale residue", function()
        local keys = {
            '%+1%% Critical Strike Multiplier per 10 Bleeds on the target, up to 200 Bleeds',
            '%+1%% Damage per 10%% Bleed chance',
            '%+1%% Hit Damage Per Bleed',
            '%+1%% Melee Damager per Bleed',
            '%+11%% Critical Strike Multiplier per 10 Bleeds on the target, up to 200 Bleeds',
            '%+2%% Cold Penetration with Shatter Strike per stack of bleed on you',
            '%+2%% Critical Strike Multiplier per 10 Bleeds on the target, up to 200 Bleeds',
            '%+2%% Melee Damage Per Bleed',
            '%+3%% Critical Strike Multiplier per 10 Bleeds on the target, up to 200 Bleeds',
            '%+3%% Melee Damage Per Bleed',
            '%+3%% Recalled Blades Hit Damage Per Bleed',
            '%+5%% Critical Strike Multiplier per 10 Bleeds on the target, up to 200 Bleeds',
            '%+5%% Locust Swarm Area Per Bleed',
            '%+69%% Chance to inflict Bleed on Hit for Primordial Blood per stack of Bleed on the enemy releasing it %(up to 20%)',
            '%+7%% Critical Strike Multiplier per 10 Bleeds on the target, up to 200 Bleeds',
            '1%% Chance per Bleed for Haste on Enemy Death',
            '1%% Melee Damage per Bleed',
            '1%% More Poison Damage per 10 Bleeds on Enemy, up to 20%%',
            '15%% Maximum Damage Per Bleed',
            '20 Health gained on Kill per stack of Bleed on the Target',
            '5%% Locust Swarm Increased Damage Per Bleed',
            '5%% More Crit Chance per Bleed',
        }
        for _, k in ipairs(keys) do
            local stale = 'c%["' .. k .. '"%]={{[^\n]-}},"[^"][^\n]*"}'
            assert.is_nil(string.find(cacheText, stale),
                "per-Bleed entry must have empty residue: " .. k)
        end
    end)
end)
