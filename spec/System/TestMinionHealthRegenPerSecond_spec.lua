-- @leb-regression-guard: minion-health-regen-per-second
-- Locks the ModParser pattern that consumes the full
--   "+N Minion Health Regen Per Second"
-- line emitted by Acolyte tree node "Blood Armor" (tree_3.json Acolyte-21,
-- 1_2/1_3/1_4 trees). The "Minion" prefix routes to MinionModifier and
-- "Health Regen" maps to LifeRegen via nameMap, but the trailing
-- "Per Second" survives as residue when no explicit pattern consumes the
-- full line. modLib.parseMod sets node.extra=true on residue and
-- PassiveTree.lua silently drops the entire mod from modDB — losing
-- 6×ranks of minion regen on every Necromancer/Lich/Warlock build that
-- takes Blood Armor.
--
-- Triangulation: BxvJP3g1 lv99 Necromancer (g1) — Acolyte-21#8 should grant
-- +48 Minion Health Regen, lifting output.MinionLifeRegen from 186 (Pebbles'
-- Collar Reforged alone) to 234, matching LETools' Minion-tab Health Regen.
-- Pre-fix LEB reported 186 (Δ-48).
--
-- See REGRESSION_GUARDS.md "minion-health-regen-per-second".

describe("MinionHealthRegenPerSecond", function()
    local function readFile(path)
        local f = io.open(path, "r")
        if not f then return nil end
        local s = f:read("*a"); f:close()
        return s
    end

    local parserSrc = readFile("Modules/ModParser.lua")
    local cacheSrc  = readFile("Data/ModCache.lua")

    it("ModParser has explicit specialModList patterns for minion health/life regen per second", function()
        assert.is_not_nil(parserSrc, "must read ModParser.lua")
        assert.is_truthy(string.find(parserSrc,
            'specialModList["^%+?(%d+) minion health regen per second$"]',
            1, true),
            "ModParser must accept '+N minion health regen per second' as a full-line specialModList entry")
        assert.is_truthy(string.find(parserSrc,
            'specialModList["^%+?(%d+) minion life regen per second$"]',
            1, true),
            "ModParser must accept '+N minion life regen per second' alias")
    end)

    it("ModCache entry for '+6 Minion Health Regen Per Second' has no residue (extra=nil)", function()
        assert.is_not_nil(cacheSrc, "must read ModCache.lua")
        -- The cache stores {modList, extra}. extra must be nil — anything
        -- else means parseMod sets node.extra=true and the mod is dropped.
        assert.is_truthy(string.find(cacheSrc,
            'c["+6 Minion Health Regen Per Second"]={{[1]={flags=0,keywordFlags=0,name="MinionModifier",type="LIST",value={mod={flags=0,keywordFlags=0,name="LifeRegen",type="BASE",value=6}}}},nil}',
            1, true),
            "ModCache entry for +6 Minion Health Regen Per Second must have extra=nil")
    end)
end)
