-- @leb-regression-guard: dual-wield-pair-suffix-family
-- Locks parser + ModCache for the dual-wield pair / "with 2 <weapons>"
-- suffix family used by Rogue-65 "Weapons of Choice". 7 silent-failure
-- entries had only one weapon condition (or both but missing
-- DualWielding) with the connector text dropped into slot[2] residue:
--   * +10% Critical Multiplier with a Mace and Dagger
--   * +20% Bleed Chance with an Axe and a Sword
--   * +20% Poison Chance with 2 Daggers
--   * +5% Glancing Blow Chance with 2 Swords
--   * 2% Physical Damage Leeched as Health with an Axe and Dagger
--   * 20% Increased Crit Chance with a Sword and Dagger
--   * 20% Increased Stun Duration with a Mace and Sword
--
-- Two sites lock together:
-- a. ModParser.lua: nested DamageSourceWeapons loop emits
--    modTagList["with a/an <w1> and (a/an) <w2>"] (all 8*7*3 = 168
--    ordered pairs) and modTagList["with 2 <w>s"] (8 same-weapon forms).
--    Each tagList carries Using<W1> + Using<W2> + DualWielding (or
--    Using<W> + DualWielding for the same-weapon form).
-- b. ModCache.lua: 7 entries carry the full 3-condition (or 2-condition)
--    tagList with empty residue.

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("DualWieldPairSuffixFamily", function()
    local parserText, cacheText

    setup(function()
        parserText = readSource("Modules/ModParser.lua")
        cacheText  = readSource("Data/ModCache.lua")
    end)

    it("ModParser registers nested 'with a/an <w1> and (a/an) <w2>' pair loop", function()
        assert.is_truthy(string.find(parserText,
            'modTagList%["with " %.%. a1 %.%. " " %.%. w1:lower%(%) %.%. " and " %.%. w2:lower%(%)%]',
            1, false),
            "ModParser must register pair suffix without article")
        assert.is_truthy(string.find(parserText,
            'modTagList%["with " %.%. a1 %.%. " " %.%. w1:lower%(%) %.%. " and a " %.%. w2:lower%(%)%]',
            1, false),
            "ModParser must register pair suffix with 'a' article on w2")
    end)

    it("ModParser registers 'with 2 <weapons>' same-weapon form inside the loop", function()
        assert.is_truthy(string.find(parserText,
            'modTagList%["with 2 " %.%. w1:lower%(%) %.%. "s"%]',
            1, false),
            "ModParser must register 'with 2 <weapons>' same-weapon suffix")
    end)

    it("Pair tagList carries 3 conditions: Using<W1>, Using<W2>, DualWielding", function()
        local needle = 'tagList = {%s*{%s*type = "Condition", var = "Using" %.%. w1 },%s*{%s*type = "Condition", var = "Using" %.%. w2 },%s*{%s*type = "Condition", var = "DualWielding" },%s*}'
        assert.is_truthy(string.find(parserText, needle),
            "Pair tagList must carry Using<W1> + Using<W2> + DualWielding")
    end)

    it("ModCache: '+10% Critical Multiplier with a Mace and Dagger' carries Mace + Dagger + DualWielding", function()
        local needle = 'c%["%+10%% Critical Multiplier with a Mace and Dagger"%]={{%[1%]={%[1%]={type="Condition",var="UsingMace"},%[2%]={type="Condition",var="UsingDagger"},%[3%]={type="Condition",var="DualWielding"},flags=0,keywordFlags=0,name="CritMultiplier",type="BASE",value=10}},""}'
        assert.is_truthy(string.find(cacheText, needle, 1, false))
    end)

    it("ModCache: '+20% Bleed Chance with an Axe and a Sword' carries Axe + Sword + DualWielding", function()
        local needle = 'c%["%+20%% Bleed Chance with an Axe and a Sword"%]={{%[1%]={%[1%]={type="Condition",var="UsingAxe"},%[2%]={type="Condition",var="UsingSword"},%[3%]={type="Condition",var="DualWielding"},flags=8388608,keywordFlags=0,name="ChanceToTriggerOnHit_Ailment_Bleed",type="BASE",value=20}},""}'
        assert.is_truthy(string.find(cacheText, needle, 1, false))
    end)

    it("ModCache: '+20% Poison Chance with 2 Daggers' carries Dagger + DualWielding", function()
        local needle = 'c%["%+20%% Poison Chance with 2 Daggers"%]={{%[1%]={%[1%]={type="Condition",var="UsingDagger"},%[2%]={type="Condition",var="DualWielding"},flags=8388608,keywordFlags=0,name="ChanceToTriggerOnHit_Ailment_Poison",type="BASE",value=20}},""}'
        assert.is_truthy(string.find(cacheText, needle, 1, false))
    end)

    it("ModCache: '+5% Glancing Blow Chance with 2 Swords' carries Sword + DualWielding", function()
        local needle = 'c%["%+5%% Glancing Blow Chance with 2 Swords"%]={{%[1%]={%[1%]={type="Condition",var="UsingSword"},%[2%]={type="Condition",var="DualWielding"},flags=0,keywordFlags=0,name="GlancingBlowChance",type="BASE",value=5}},""}'
        assert.is_truthy(string.find(cacheText, needle, 1, false))
    end)

    it("ModCache: '2% Physical Damage Leeched as Health with an Axe and Dagger' carries Axe + Dagger + DualWielding", function()
        local needle = 'c%["2%% Physical Damage Leeched as Health with an Axe and Dagger"%]={{%[1%]={%[1%]={type="Condition",var="UsingAxe"},%[2%]={type="Condition",var="UsingDagger"},%[3%]={type="Condition",var="DualWielding"},flags=0,keywordFlags=0,name="PhysicalDamageLifeLeech",type="BASE",value=2}},""}'
        assert.is_truthy(string.find(cacheText, needle, 1, false))
    end)

    it("ModCache: '20% Increased Crit Chance with a Sword and Dagger' carries Sword + Dagger + DualWielding", function()
        local needle = 'c%["20%% Increased Crit Chance with a Sword and Dagger"%]={{%[1%]={%[1%]={type="Condition",var="UsingSword"},%[2%]={type="Condition",var="UsingDagger"},%[3%]={type="Condition",var="DualWielding"},flags=0,keywordFlags=0,name="CritChance",type="INC",value=20}},""}'
        assert.is_truthy(string.find(cacheText, needle, 1, false))
    end)

    it("ModCache: '20% Increased Stun Duration with a Mace and Sword' carries Mace + Sword + DualWielding", function()
        local needle = 'c%["20%% Increased Stun Duration with a Mace and Sword"%]={{%[1%]={%[1%]={type="Condition",var="UsingMace"},%[2%]={type="Condition",var="UsingSword"},%[3%]={type="Condition",var="DualWielding"},flags=0,keywordFlags=0,name="EnemyStunDuration",type="INC",value=20}},""}'
        assert.is_truthy(string.find(cacheText, needle, 1, false))
    end)

    it("ModCache: no dual-wield pair entry retains stale residue", function()
        local keys = {
            "%+10%% Critical Multiplier with a Mace and Dagger",
            "%+20%% Bleed Chance with an Axe and a Sword",
            "%+20%% Poison Chance with 2 Daggers",
            "%+5%% Glancing Blow Chance with 2 Swords",
            "2%% Physical Damage Leeched as Health with an Axe and Dagger",
            "20%% Increased Crit Chance with a Sword and Dagger",
            "20%% Increased Stun Duration with a Mace and Sword",
        }
        for _, k in ipairs(keys) do
            local stale = 'c%["' .. k .. '"%]={{[^\n]-}},"[^"][^\n]*"}'
            assert.is_nil(string.find(cacheText, stale),
                "dual-wield pair entry must have empty residue: " .. k)
        end
    end)
end)
