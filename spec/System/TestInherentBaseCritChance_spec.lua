-- @leb-regression-guard: inherent-base-crit-chance
-- Locks the contract that LE gives every hit an inherent 5% base critical strike
-- chance, applied per-skill in CalcActiveSkill as the fallback for skills whose
-- skills.json entry OMITS the critChance field.
--
-- WHY THIS MATTERS:
-- LEB already carried the inherent 5% for 137 abilities via skills.json `critChance:5`,
-- which CalcActiveSkill copies into `activeSkill.skillData.CritChance`; CalcOffence then
-- reads that as `baseCrit` (source = skillData) in
--   `output.CritChance = (baseCrit + base) * (1 + inc/100) * more`.
-- BUT ~206 other abilities (e.g. Shatter Strike, Wandering Spirits) OMIT critChance in
-- skills.json, leaving skillData.CritChance = nil -> baseCrit = 0, silently dropping the
-- inherent 5%. The fix defaults the nil case to data.misc.BaseCritChance.
--
-- NOT a global modDB BASE seed: an earlier attempt seeded
-- `modDB:NewMod("CritChance","BASE",data.misc.BaseCritChance,"Base")` in CalcSetup, which
-- DOUBLE-COUNTED the 137 skills that already declare critChance=5 (5 + 5 = 10%), breaking
-- TestSkills. The correct surgical fix lives in CalcActiveSkill and touches ONLY the
-- nil (missing-field) case.
--
-- GROUND TRUTH (in-game ShutFackUp lv85 Spellblade, Damage tab):
--   generic Critical Strike Chance = 35%, Melee Critical Strike Chance = 59%.
-- Shatter Strike is melee, so its true crit is 59%, not 35%.
--   melee  Shatter Strike: (5 inherent + 5 sword-melee + 2 Phantom) * (1+3.95) = 12*4.95 = 59.4 -> 59
--   generic/spell        : (5 inherent + 2 Phantom)               * (1+3.95) =  7*4.95 = 34.65 -> 35
--
-- ROOT CAUSE: datamined game source `Stats.baseCritChance = 0.05` (global constant)
-- combined with skills.json omitting critChance on ~206 abilities.
--
-- THE FIX (CalcActiveSkill.lua, in buildActiveSkillModList):
--   activeSkill.skillData.CritChance = stats.critChance or data.misc.BaseCritChance
-- `or` (not nil-coalesce-on-0) keeps an explicit critChance=0 at 0, and never re-adds 5
-- to the 137 skills that already declare it.
--
-- See REGRESSION_GUARDS.md "inherent-base-crit-chance".

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("InherentBaseCritChance", function()

    describe("Data.lua exposes the LE inherent base crit constant", function()
        it("data.misc.BaseCritChance is 5 (LE Stats.baseCritChance 0.05 -> percent)", function()
            assert.is_not_nil(data, "global data table must be loaded by the headless wrapper")
            assert.is_not_nil(data.misc, "data.misc must exist")
            assert.are.equal(5, data.misc.BaseCritChance,
                "data.misc.BaseCritChance must be 5 (5% inherent base crit)")
        end)
    end)

    describe("CalcActiveSkill defaults the inherent base crit per-skill", function()
        local source
        setup(function()
            source = readSource("Modules/CalcActiveSkill.lua")
        end)

        it("keeps the @leb-regression-guard marker so future edits trip review", function()
            assert.is_truthy(string.find(source, "inherent%-base%-crit%-chance"),
                "CalcActiveSkill.lua must keep the @leb-regression-guard:inherent-base-crit-chance comment")
        end)

        it("defaults skillData.CritChance to data.misc.BaseCritChance when critChance is omitted", function()
            local pat = 'skillData%.CritChance%s*=%s*stats%.critChance%s+or%s+data%.misc%.BaseCritChance'
            assert.is_truthy(string.find(source, pat),
                "CalcActiveSkill must set skillData.CritChance = stats.critChance or data.misc.BaseCritChance")
        end)

        it("does NOT use nil-coalesce that would clobber an explicit critChance=0", function()
            -- `or` preserves Lua truthiness of 0; a `~= nil and ... or` ternary would wrongly
            -- coerce 0 -> 5. Guard against re-introducing such a ternary on this assignment.
            assert.is_falsy(string.find(source, 'skillData%.CritChance%s*=.-~=%s*nil.-data%.misc%.BaseCritChance'),
                "must not coerce an explicit critChance=0 up to the inherent default")
        end)
    end)

    describe("CalcSetup must NOT re-seed a global BASE CritChance (double-count guard)", function()
        local source
        setup(function()
            source = readSource("Modules/CalcSetup.lua")
        end)

        it("does not add modDB:NewMod(\"CritChance\",\"BASE\",data.misc.BaseCritChance,...)", function()
            local pat = 'NewMod%("CritChance",%s*"BASE",%s*data%.misc%.BaseCritChance'
            assert.is_falsy(string.find(source, pat),
                "CalcSetup must NOT globally seed BASE CritChance -- that double-counts the 137 "
                .. "skills already declaring critChance=5 (regression: TestSkills Lunge/Rive)")
        end)
    end)

    describe("CalcOffence consumes skillData.CritChance as baseCrit (the default's sink)", function()
        local source
        setup(function()
            source = readSource("Modules/CalcOffence.lua")
        end)

        it("reads baseCrit from source.CritChance", function()
            assert.is_truthy(string.find(source, "critOverride or source%.CritChance or 0", 1, false),
                "CalcOffence must keep `baseCrit = critOverride or source.CritChance or 0`")
        end)

        it("adds baseCrit to the BASE sum before applying increases", function()
            assert.is_truthy(string.find(source, "%(baseCrit %+ base%) %* %(1 %+ inc / 100%)", 1, false),
                "crit formula must keep (baseCrit + base) * (1 + inc/100)")
        end)
    end)
end)
