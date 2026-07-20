-- @leb-regression-guard: crit-for-totems-per-int-and-multi
-- @leb-regression-guard: minion-modifier-multi-type-gate
-- Locks the parser + ModCache for totem-family crit affixes:
--   "+N% Critical Strike Chance for Totems per Intelligence"  (per-Int, 8 values)
--   "+N% Critical Strike Multiplier for Totems"               (flat, 9 values)
--
-- Sources verified against game files (2026-05-13):
--   Property_Player_175 "Critical Strike Chance for Totems per Intelligence"
--   AltText "Scales with your Intelligence" => parent (player) Int scaling.
--   Inherent on unique Ferebor's Chisel (uniques.json "+1% ...").
--   ModItem prefix 786 "Ferebor's Chisel Reforged" carries the LEB-current text;
--   v3 dump shows the 2nd line was reworked to a Frenzy line post-1.4.5 but the
--   parser fix is still correct for the LEB text and for the unique mod.
--
-- Three sites lock together:
-- a. ModParser.lua: two specialModList patterns emit MinionModifier LIST with
--    minionTypes = 8 totem family keys (Frenzy/Thorn/Storm/Healing/Claw/Tempest/
--    Warcry/Upheaval Totem). per-Int inner mod carries PerStat:Int actor=parent.
-- b. CalcPerform.lua dispatch (shared with skeleton guard) walks MinionModifier
--    entries and applies them when value.minionTypes array contains
--    env.minion.type.
-- c. ModCache.lua: 17 entries (8 per-Int + 9 Multi) carry the MinionModifier
--    wrapper with empty residue.

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("CritForTotemsPerIntAndMulti", function()
    local parserText, cacheText

    setup(function()
        parserText = readSource("Modules/ModParser.lua")
        cacheText  = readSource("Data/ModCache.lua")
    end)

    it("ModParser registers the per-Int and Multi patterns", function()
        assert.is_truthy(string.find(parserText,
            '%["%^%%%+%?%(%[%%d%%.%]%+%)%%%% critical strike chance for totems per intelligence%$"%]', 1, false),
            "ModParser must register the per-Intelligence pattern")
        assert.is_truthy(string.find(parserText,
            '%["%^%%%+%?%(%[%%d%%.%]%+%)%%%% critical strike multiplier for totems%$"%]', 1, false),
            "ModParser must register the Crit Multi pattern")
    end)

    it("ModParser per-Int handler carries PerStat:Int with actor=parent", function()
        assert.is_truthy(string.find(parserText,
            'mod%("CritChance", "BASE", num, "", 0, 0, { type = "PerStat", stat = "Int", actor = "parent" }%)',
            1, false),
            "per-Int handler must scale on player Int via actor=parent")
    end)

    it("ModParser per-Int handler lists the full 8-key totem family", function()
        local needle = '"Frenzy Totem",%s+"Thorn Totem",%s+"StormTotem",%s+"HealingTotem",%s+"ClawTotem",%s+"TempestTotem",%s+"WarcryTotem",%s+"UpheavalTotem",'
        local _, count = string.gsub(parserText, needle, "")
        assert.is_true(count >= 2,
            "both totem handlers must list the full 8-key totem family")
    end)

    it("ModParser Crit Multi handler emits CritMultiplier BASE (no PerStat)", function()
        assert.is_truthy(string.find(parserText,
            'mod = mod%("CritMultiplier", "BASE", num%),',
            1, false),
            "Crit Multi handler must use a plain CritMultiplier BASE inner mod")
    end)

    it("ModCache '+0.1% ... per Intelligence' carries totem minionTypes + PerStat:Int parent", function()
        local needle = 'c%["%+0%.1%% Critical Strike Chance for Totems per Intelligence"%]={{%[1%]={flags=0,keywordFlags=0,name="MinionModifier",type="LIST",value={minionTypes={%[1%]="Frenzy Totem",%[2%]="Thorn Totem",%[3%]="StormTotem",%[4%]="HealingTotem",%[5%]="ClawTotem",%[6%]="TempestTotem",%[7%]="WarcryTotem",%[8%]="UpheavalTotem"},mod={%[1%]={actor="parent",stat="Int",type="PerStat"},flags=0,keywordFlags=0,name="CritChance",type="BASE",value=0%.1}}}},""}'
        assert.is_truthy(string.find(cacheText, needle, 1, false),
            "+0.1%% per-Int entry must carry totem family + PerStat:Int actor=parent with empty residue")
    end)

    it("ModCache '+7% Critical Strike Multiplier for Totems' carries totem minionTypes", function()
        local needle = 'c%["%+7%% Critical Strike Multiplier for Totems"%]={{%[1%]={flags=0,keywordFlags=0,name="MinionModifier",type="LIST",value={minionTypes={%[1%]="Frenzy Totem",%[2%]="Thorn Totem",%[3%]="StormTotem",%[4%]="HealingTotem",%[5%]="ClawTotem",%[6%]="TempestTotem",%[7%]="WarcryTotem",%[8%]="UpheavalTotem"},mod={flags=0,keywordFlags=0,name="CritMultiplier",type="BASE",value=7}}}},""}'
        assert.is_truthy(string.find(cacheText, needle, 1, false),
            "+7%% Crit Multi entry must carry totem family with empty residue")
    end)

    it("ModCache must NOT carry stale flat-Crit entries for any patched values", function()
        for _, num in ipairs({"0.1","0.2","0.3","0.4","0.5","0.8","1","1.5"}) do
            local stale = 'c["+' .. num .. '% Critical Strike Chance for Totems per Intelligence"]={{[1]={[1]={stat="Int",type="PerStat"},flags=0,keywordFlags=0,name="CritChance",type="BASE",value=' .. num .. '}},"  for Totems  "}'
            assert.is_nil(string.find(cacheText, stale, 1, true),
                "+" .. num .. "%% per-Int entry must not carry the stale form")
        end
        for _, num in ipairs({"7","9","11","13","17","25","27","33","63"}) do
            local stale = 'c["+' .. num .. '% Critical Strike Multiplier for Totems"]={{[1]={flags=0,keywordFlags=0,name="CritMultiplier",type="BASE",value=' .. num .. '}},"  for Totems "}'
            assert.is_nil(string.find(cacheText, stale, 1, true),
                "+" .. num .. "%% Crit Multi entry must not carry the stale form")
        end
    end)

    it("ModCache patches exactly 8 per-Int and 9 Multi entries", function()
        local pi = 0
        for _ in string.gmatch(cacheText,
            'c%["%+[%d%.]+%% Critical Strike Chance for Totems per Intelligence"%]') do
            pi = pi + 1
        end
        local mu = 0
        for _ in string.gmatch(cacheText,
            'c%["%+%d+%% Critical Strike Multiplier for Totems"%]') do
            mu = mu + 1
        end
        assert.equal(8, pi, "must have exactly 8 per-Int ModCache entries")
        assert.equal(9, mu, "must have exactly 9 Crit Multi ModCache entries")
    end)
end)
