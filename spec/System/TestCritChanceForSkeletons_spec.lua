-- @leb-regression-guard: crit-chance-for-skeletons-skeletal-mages
-- @leb-regression-guard: minion-modifier-multi-type-gate
-- Locks the parser + ModCache + dispatch for Acolyte minion-summoner crit
-- affixes "+N% Critical Strike Chance for Skeletons" / "for Skeletal Mages".
-- Before the guard the bare CritChance BASE mod leaked the +N% onto the
-- PLAYER main-skill crit instead of the minion family.
--
-- Three sites lock together:
-- a. `Modules/ModParser.lua` specialModList: maps each line to a
--    `MinionModifier` LIST carrying either `minionTypes` (Skeletons family)
--    or `type` (Skeletal Mages).
-- b. `Modules/CalcPerform.lua` dispatch (~L506 + ~L1182 mirror): walks
--    MinionModifier entries and applies them if `type` matches OR
--    `minionTypes` array contains env.minion.type.
-- c. `Data/ModCache.lua` 24 patched entries (12 Skeleton values × 2 lines)
--    carry the MinionModifier wrapper with empty residue.

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("CritChanceForSkeletonsSkeletalMages", function()
    local parserText, cacheText, performText

    setup(function()
        parserText  = readSource("Modules/ModParser.lua")
        cacheText   = readSource("Data/ModCache.lua")
        performText = readSource("Modules/CalcPerform.lua")
    end)

    it("ModParser specialModList registers the two patterns", function()
        assert.is_truthy(string.find(parserText,
            '%["%^%%%+%?%(%[%%d%%.%]%+%)%%%% critical strike chance for skeletons%$"%]', 1, false),
            "ModParser must register the 'for skeletons' pattern")
        assert.is_truthy(string.find(parserText,
            '%["%^%%%+%?%(%[%%d%%.%]%+%)%%%% critical strike chance for skeletal mages%$"%]', 1, false),
            "ModParser must register the 'for skeletal mages' pattern")
    end)

    it("ModParser Skeletons handler emits MinionModifier with the full minionTypes family", function()
        local handlerNeedle = 'minionTypes = {%s+"SummonedSkeleton",%s+"SummonedSkeletonArcher",%s+"SummonedSkeletonHarvester",%s+"SummonedSkeletonVanguard",%s+"SummonedSkeletonRogue",%s+},'
        assert.is_truthy(string.find(parserText, handlerNeedle),
            "Skeletons handler must list all 5 SummonedSkeleton family minion types")
    end)

    it("ModParser Skeletal Mages handler emits MinionModifier with single type SummonedSkeletonMage", function()
        assert.is_truthy(string.find(parserText,
            'type = "SummonedSkeletonMage"', 1, false),
            "Skeletal Mages handler must carry type=SummonedSkeletonMage")
    end)

    it("CalcPerform dispatch matches value.minionTypes array (primary site)", function()
        assert.is_truthy(string.find(performText,
            '@leb%-regression%-guard:minion%-modifier%-multi%-type%-gate'),
            "CalcPerform must carry the inline guard marker on primary dispatch site")
        assert.is_truthy(string.find(performText,
            'for _, mt in ipairs%(value%.minionTypes%) do'),
            "CalcPerform primary dispatch must iterate value.minionTypes array")
    end)

    it("CalcPerform mirror dispatch site (buff loop) also matches value.minionTypes", function()
        -- The buff-loop site near line 1180 is the second dispatch site.
        -- Both must support minionTypes to prevent skill-buff-routed mods from
        -- silently falling through.
        local _, count = string.gsub(performText,
            'for _, mt in ipairs%(value%.minionTypes%) do', '')
        assert.is_true(count >= 2,
            "CalcPerform must support minionTypes in BOTH dispatch sites (primary + buff mirror)")
    end)

    it("ModCache '+5% Critical Strike Chance for Skeletons' carries the Skeletons family minionTypes", function()
        local needle = 'c%["%+5%% Critical Strike Chance for Skeletons"%]={{%[1%]={flags=0,keywordFlags=0,name="MinionModifier",type="LIST",value={minionTypes={%[1%]="SummonedSkeleton",%[2%]="SummonedSkeletonArcher",%[3%]="SummonedSkeletonHarvester",%[4%]="SummonedSkeletonVanguard",%[5%]="SummonedSkeletonRogue"},mod={flags=0,keywordFlags=0,name="CritChance",type="BASE",value=5}}}},""}'
        assert.is_truthy(string.find(cacheText, needle, 1, false),
            "+5%% Skeletons entry must carry full minionTypes family with empty residue")
    end)

    it("ModCache '+5% Critical Strike Chance for Skeletal Mages' carries type=SummonedSkeletonMage", function()
        local needle = 'c%["%+5%% Critical Strike Chance for Skeletal Mages"%]={{%[1%]={flags=0,keywordFlags=0,name="MinionModifier",type="LIST",value={mod={flags=0,keywordFlags=0,name="CritChance",type="BASE",value=5},type="SummonedSkeletonMage"}}},""}'
        assert.is_truthy(string.find(cacheText, needle, 1, false),
            "+5%% Skeletal Mages entry must carry type=SummonedSkeletonMage with empty residue")
    end)

    it("ModCache must NOT carry stale flat-CritChance entries for any of the 12 Skeleton values", function()
        for _, num in ipairs({"1", "2", "3", "4", "5", "7", "8", "10", "12", "15", "17", "26"}) do
            for _, family in ipairs({"Skeletons", "Skeletal Mages"}) do
                local stale = 'c["+' .. num .. '% Critical Strike Chance for ' .. family
                    .. '"]={{[1]={flags=0,keywordFlags=0,name="CritChance",type="BASE",value='
                    .. num .. '}},"  for ' .. family .. ' "}'
                assert.is_nil(string.find(cacheText, stale, 1, true),
                    "+" .. num .. "%% " .. family ..
                    " entry must not carry the stale flat-CritChance form")
            end
        end
    end)

    it("ModCache patches all 12 values for both Skeletons and Skeletal Mages (24 total)", function()
        local skeletonsCount = 0
        for _ in string.gmatch(cacheText,
            'c%["%+%d+%% Critical Strike Chance for Skeletons"%]') do
            skeletonsCount = skeletonsCount + 1
        end
        local magesCount = 0
        for _ in string.gmatch(cacheText,
            'c%["%+%d+%% Critical Strike Chance for Skeletal Mages"%]') do
            magesCount = magesCount + 1
        end
        assert.equal(12, skeletonsCount,
            "must have exactly 12 Skeletons crit chance ModCache entries")
        assert.equal(12, magesCount,
            "must have exactly 12 Skeletal Mages crit chance ModCache entries")
    end)
end)
