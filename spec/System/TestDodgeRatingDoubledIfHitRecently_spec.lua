-- @leb-regression-guard: dodge-rating-doubled-if-hit-recently
-- Locks the ModParser trailing-clause tag for
-- "<N> Dodge Rating, Doubled if Hit Recently" (Rogue passive "Once",
-- node Rogue-52). The whole-clause modTagList entry maps
-- ", doubled if hit recently" to Condition:BeenHitRecently with mult = 2.
--
-- Before this guard the modTagList scan consumed only the inner
-- "hit recently" fragment and left residue " , Doubled if  Recently ".
-- A non-empty `extra` residue makes the mod invalid, so the Evasion BASE
-- mod was dropped at tree application -- losing 10 x allocated points of
-- Dodge Rating (60 at 6/6 on ImPalmBeachPete).
--
-- scan() is earliest+longest-match, so the comma-anchored phrase wins
-- over the inner "hit recently" tag. BeenHitRecently defaults OFF, so the
-- base (un-doubled) value applies, matching the in-game character-sheet
-- display. Same Condition+mult contract as ", doubled for shadow attack".
--
-- Establishing observation: ImPalmBeachPete lv36 Bladedancer (Once 6/6 =
-- 60 base Dodge Rating) Dodge Rating
--   pre-fix  111 (node mod dropped; a stale ModCache row
--            c["10 Dodge Rating, Doubled if Hit Recently"]={{...flags=8388608...},
--            " , Doubled if  Recently "} short-circuited the live parser)
--   post-fix 184 ((92 base + 60) * 1.05 INC * 1.15 MORE), Dodge Chance
--            10.65% -> ~14.7% (in-game display 15%)
--
-- See REGRESSION_GUARDS.md > dodge-rating-doubled-if-hit-recently.

local parseMod = LoadModule("Modules/ModParser")

local function parseFresh(line)
    -- ModCache.lua may pin a pre-fix broken entry; clear before assert.
    local _, cache = LoadModule("Modules/ModParser")
    cache[line] = nil
    return parseMod(line)
end

local function findCondition(mods, var, neg)
    if type(mods) ~= "table" then return nil end
    for _, m in ipairs(mods) do
        for _, tag in ipairs(m) do
            if tag.type == "Condition" and tag.var == var and (not not tag.neg) == (not not neg) then
                return m, tag
            end
        end
    end
    return nil
end

describe("DodgeRatingDoubledIfHitRecently", function()
    -- Uncached number (+11) so this exercises the live ModParser path
    -- rather than the precomputed Data/ModCache row.
    it("'11 Dodge Rating, Doubled if Hit Recently' parses to Evasion BASE + Condition:BeenHitRecently{mult=2}, no residue", function()
        local mods, extra = parseFresh("11 Dodge Rating, Doubled if Hit Recently")
        assert.is_truthy(mods)
        assert.is_table(mods[1])
        assert.are.equal("Evasion", mods[1].name)
        assert.are.equal("BASE", mods[1].type)
        assert.are.equal(11, mods[1].value)
        local _, tag = findCondition(mods, "BeenHitRecently", false)
        assert.is_truthy(tag, "must carry Condition:BeenHitRecently (not dropped/NotSupported)")
        assert.are.equal(2, tag.mult, "trailing 'doubled' clause must set mult = 2")
        assert.is_nil(extra, "whole clause must leave no residue (got '" .. tostring(extra) .. "')")
    end)

    -- Cached canonical text (value 10) must resolve to the same shape; this
    -- pins the corrected ModCache.lua row.
    it("cached '10 Dodge Rating, Doubled if Hit Recently' resolves to the same shape", function()
        local mods, extra = parseMod("10 Dodge Rating, Doubled if Hit Recently")
        assert.is_truthy(mods)
        assert.are.equal("Evasion", mods[1].name)
        assert.are.equal(10, mods[1].value)
        local _, tag = findCondition(mods, "BeenHitRecently", false)
        assert.is_truthy(tag, "ModCache row must carry Condition:BeenHitRecently")
        assert.are.equal(2, tag.mult)
        assert.is_nil(extra)
    end)

    it("Evasion base applies un-doubled when BeenHitRecently is off, doubles when on", function()
        newBuild()
        build.configTab.input.customMods = "10 Dodge Rating, Doubled if Hit Recently"
        build.configTab:BuildModList()
        runCallback("OnFrame")
        local modList = build.configTab.modList
        -- Default (BeenHitRecently off): base value, un-doubled.
        modList.conditions["BeenHitRecently"] = nil
        assert.are.equal(10, modList:Sum("BASE", nil, "Evasion"))
        -- Condition met: doubled (mult = 2).
        modList.conditions["BeenHitRecently"] = true
        assert.are.equal(20, modList:Sum("BASE", nil, "Evasion"))
        modList.conditions["BeenHitRecently"] = nil
    end)
end)
