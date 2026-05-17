-- @leb-regression-guard: shadow-skills-minion-scope
-- @leb-regression-guard: shadow-damage-minion-scope
-- Locks the F3+F9 rewire: "for skills used by Shadows" and
-- "Shadow Damage" no longer use the no-op Scope:minion /
-- Condition:ShadowDamageScope placeholders. Both phrases now route
-- through MinionModifier LIST with minionTypes={"ShadowClone"} so the
-- CalcPerform dispatch gate (minion-modifier-multi-type-gate) can
-- narrow the apply to env.minion.type=="ShadowClone".

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("ShadowMinionScope", function()
    local parserText, cacheText

    setup(function()
        parserText = readSource("Modules/ModParser.lua")
        cacheText  = readSource("Data/ModCache.lua")
    end)

    it("ModParser: 'for skills used by shadows' maps to addToMinion + ShadowClone", function()
        local needle = '%["for skills used by shadows"%]%s*=%s*{%s*addToMinion%s*=%s*true,%s*addToMinionTypes%s*=%s*{%s*"ShadowClone"%s*}%s*}'
        assert.is_truthy(string.find(parserText, needle),
            "modTagList['for skills used by shadows'] must use addToMinion+addToMinionTypes={'ShadowClone'}")
    end)

    it("ModParser: 'shadow damage' maps to Damage with addToMinion + ShadowClone", function()
        local needle = '%["shadow damage"%]%s*=%s*{%s*"Damage",%s*addToMinion%s*=%s*true,%s*addToMinionTypes%s*=%s*{%s*"ShadowClone"%s*}%s*}'
        assert.is_truthy(string.find(parserText, needle),
            "modNameList['shadow damage'] must use addToMinion+addToMinionTypes={'ShadowClone'}")
    end)

    it("ModParser: no Scope:minion gate for the Shadows phrase remains", function()
        -- Defensive: catches accidental revert that re-introduces a
        -- Scope:minion placeholder for the Shadows phrase.
        local re = '%["for skills used by shadows"%]%s*=%s*{%s*tag%s*=%s*{%s*type%s*=%s*"Scope"'
        assert.is_nil(string.find(parserText, re),
            "Shadows-phrase Scope:minion placeholder must not be reintroduced")
    end)

    it("ModParser: no ShadowDamageScope Condition placeholder remains in code", function()
        -- The string may still appear inside the historical guard comment
        -- on line 384 explaining the rewire; we only want to catch a
        -- functional reintroduction (var="ShadowDamageScope").
        assert.is_nil(string.find(parserText, 'var%s*=%s*"ShadowDamageScope"'),
            "var=\"ShadowDamageScope\" must not be reintroduced as a Condition tag")
    end)

    it("ModCache: zero stale Scope:minion entries for 'for skills used by Shadows'", function()
        -- The 38 affected entries were regenerated via
        -- scripts/regen_shadow_modcache.py. Any reappearance of the
        -- old shape means a parser regression OR a partial regen.
        local count = 0
        for _ in string.gmatch(cacheText, '"[^"]*for skills used by Shadows[^"]*"%]={{%[1%]={%[1%]={scope="minion"') do
            count = count + 1
        end
        assert.are.equal(0, count,
            "no Shadows-phrase ModCache entry may keep the stale scope='minion' placeholder")
    end)

    it("ModCache: zero ShadowDamageScope references anywhere", function()
        assert.is_nil(string.find(cacheText, 'ShadowDamageScope'),
            "ModCache must not contain the deprecated ShadowDamageScope Condition")
    end)

    it("ModCache: rewired entries use MinionModifier LIST with ShadowClone target", function()
        -- Sample at least one well-known entry from each family to
        -- confirm the new shape really landed (not just the absence of
        -- the old shape).
        local damageEntry = '"%+1 Increased Damage for skills used by Shadows"%]={{%[1%]={flags=0,keywordFlags=0,name="MinionModifier",type="LIST",value={minionTypes={%[1%]="ShadowClone"},mod={flags=0,keywordFlags=0,name="Damage",type="INC",value=1}}}}'
        assert.is_truthy(string.find(cacheText, damageEntry),
            "Damage-INC Shadows entry must have new MinionModifier LIST shape")

        local critEntry = '"%+1%% Critical Strike Chance for skills used by Shadows"%]={{%[1%]={flags=0,keywordFlags=0,name="MinionModifier",type="LIST",value={minionTypes={%[1%]="ShadowClone"},mod={flags=0,keywordFlags=0,name="CritChance",type="BASE",value=1}}}}'
        assert.is_truthy(string.find(cacheText, critEntry),
            "CritChance-BASE Shadows entry must have new MinionModifier LIST shape")

        local shadowDmg = '"15%% Increased Shadow Damage"%]={{%[1%]={flags=0,keywordFlags=0,name="MinionModifier",type="LIST",value={minionTypes={%[1%]="ShadowClone"},mod={flags=0,keywordFlags=0,name="Damage",type="INC",value=15}}}}'
        assert.is_truthy(string.find(cacheText, shadowDmg),
            "'15%% Increased Shadow Damage' must have new MinionModifier LIST shape")
    end)
end)
