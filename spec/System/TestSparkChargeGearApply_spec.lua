-- @leb-regression-guard:spark-charge-gear-apply
-- The gear/idol affix "+N% Chance to apply a Spark Charge on [Melee/Lightning
-- Melee] Hit" (URA_YA_RANGE crafted suffix "+(10-12)% Chance to apply a Spark
-- Charge on Hit") must route to ChanceToTriggerOnHit_Ailment_SparkCharge BASE --
-- the SAME stat the Cloud Answer tree node "X% Spark Charge Chance On Hit"
-- already emits -- NOT LEB_NotSupported. "Spark Charge" is absent from
-- knownAilmentChances and the SparkChargeExplosion HIT skill carries
-- excludeFromTriggerNameList, so the generic ailment chain has no route for it;
-- ailmentApplyHandler / ailmentApplyHandler2 special-case it via sparkChargeApplyMod.
--
-- Flag mapping (mirrors modFlagList "on melee hit"):
--   on Hit                 -> flags=ModFlag.Hit (8388608),       keywordFlags=0
--   on Melee Hit           -> flags=ModFlag.Melee|Hit (8389120), keywordFlags=0
--   on Lightning Melee Hit -> flags=ModFlag.Melee|Hit (8389120), keywordFlags=Lightning(2)
--
-- This is the Spark Charge APPLICATION chance (it feeds the separately-granted
-- SparkChargeExplosion detonation rate), never a HIT trigger, so it can never
-- fabricate SparkChargeExplosion damage. ModCache rows for these affixes are
-- patched directly (REGENERATE_MOD_CACHE=1 is blocked by a pre-existing
-- malformed-pattern bug). See REGRESSION_GUARDS.md "spark-charge-gear-apply" and
-- "spark-charge-detonation", memory project_runemaster_subskills_structurally_unmodeled.

local ModFlag_Hit = 8388608
local ModFlag_MeleeHit = 8388608 + 512 -- Melee|Hit
local KeywordFlag_Lightning = 2

local function readFile(path)
    local f = io.open(path, "r") or io.open("src/" .. path, "r")
    if not f then return nil end
    local s = f:read("*a"); f:close()
    return s
end

local function single(mods)
    assert.are.equals(1, #mods)
    return mods[1]
end

describe("Spark Charge gear-apply affix parse (was LEB_NotSupported)", function()
    it("'+11% Chance to apply a Spark Charge on Hit' -> SC chance BASE 11 (Hit)", function()
        local mods, extra = modLib.parseMod("+11% Chance to apply a Spark Charge on Hit")
        assert.is_truthy(extra == nil or extra == "")
        local m = single(mods)
        assert.are.equals("ChanceToTriggerOnHit_Ailment_SparkCharge", m.name)
        assert.are.equals("BASE", m.type)
        assert.are.equals(11, m.value)
        assert.are.equals(ModFlag_Hit, m.flags)
        assert.are.equals(0, m.keywordFlags)
    end)
    it("cache-miss '+12% ... on Hit' is live-parsed too (not value-locked to cache)", function()
        local m = single(modLib.parseMod("+12% Chance to apply a Spark Charge on Hit"))
        assert.are.equals("ChanceToTriggerOnHit_Ailment_SparkCharge", m.name)
        assert.are.equals(12, m.value)
        assert.are.equals(ModFlag_Hit, m.flags)
    end)
    it("'+9% ... on Melee Hit' -> SC chance with Melee|Hit flags", function()
        local m = single(modLib.parseMod("+9% Chance to apply a Spark Charge on Melee Hit"))
        assert.are.equals("ChanceToTriggerOnHit_Ailment_SparkCharge", m.name)
        assert.are.equals(9, m.value)
        assert.are.equals(ModFlag_MeleeHit, m.flags)
        assert.are.equals(0, m.keywordFlags)
    end)
    it("'+3% ... on Lightning Melee Hit' -> SC chance with Melee|Hit + Lightning kw", function()
        local m = single(modLib.parseMod("+3% Chance to apply a Spark Charge on Lightning Melee Hit"))
        assert.are.equals("ChanceToTriggerOnHit_Ailment_SparkCharge", m.name)
        assert.are.equals(3, m.value)
        assert.are.equals(ModFlag_MeleeHit, m.flags)
        assert.are.equals(KeywordFlag_Lightning, m.keywordFlags)
    end)
end)

describe("Spark Charge gear-apply does not over- or under-reach", function()
    it("a known ailment ('apply bleed on hit') is NOT diverted to SparkCharge", function()
        local mods = modLib.parseMod("+25% Chance to apply Bleed on Hit")
        for _, m in ipairs(mods) do
            assert.is_not.equal("ChanceToTriggerOnHit_Ailment_SparkCharge", m.name)
            assert.is_not.equal("LEB_NotSupported", m.name)
        end
    end)
    it("a genuinely unknown ailment still falls through to LEB_NotSupported", function()
        local m = single(modLib.parseMod("+5% Chance to apply Gobbledygook on Hit"))
        assert.are.equals("LEB_NotSupported", m.name)
    end)
end)

describe("Spark Charge gear-apply ModCache rows are no longer NotSupported stubs", function()
    it("no 'apply a Spark Charge' row carries notSupported=true", function()
        local body = assert(readFile("Data/ModCache.lua"))
        -- The URA on-Hit row and the Melee / Lightning-Melee variants all route to SC chance.
        assert.is_truthy(body:find(
            'c["+11% Chance to apply a Spark Charge on Hit"]={{[1]={flags=8388608,keywordFlags=0,name="ChanceToTriggerOnHit_Ailment_SparkCharge"',
            1, true))
        -- Scan every "apply a Spark Charge" cache row: none may be a NotSupported stub.
        for line in body:gmatch("[^\r\n]+") do
            if line:find("apply a Spark Charge", 1, true) then
                assert.is_nil(line:find("notSupported=true", 1, true),
                    "stale NotSupported SC-apply row: " .. line)
            end
        end
    end)
end)
