-- @leb-regression-guard: boss-crit-damage-taken
-- Validation provenance is retained in maintainer notes.

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("BossCritDamageTaken", function()
    it("ConfigOptions publishes ReducedBonusDamageTakenFromCrits = 0.35 for boss categories", function()
        local text = readSource("Modules/ConfigOptions.lua")
        assert.is_truthy(string.find(text,
            'enemyModList:NewMod("ReducedBonusDamageTakenFromCrits", "BASE", 0.35, "BossConfig")', 1, true),
            "boss config must add ReducedBonusDamageTakenFromCrits BASE 0.35")
        assert.is_truthy(string.find(text, "@leb-regression-guard:boss-crit-damage-taken", 1, true),
            "ConfigOptions must carry the inline guard marker")
    end)

    it("CalcOffence computes the headline AverageHit BEFORE the boss-crit display block", function()
        local text = readSource("Modules/CalcOffence.lua")
        local idxAvg = string.find(text,
            "output%.AverageHit = totalHitAvg %* %(1 %- output%.CritChance / 100%) %+ totalCritAvg %* output%.CritChance / 100")
        assert.is_not_nil(idxAvg, "sheet-faithful headline AverageHit line must exist")
        local idxDisplay = string.find(text, "output.NonCritAverageHit = totalHitAvg", 1, true)
        assert.is_not_nil(idxDisplay, "NonCritAverageHit display output must exist")
        assert.is_true(idxAvg < idxDisplay,
            "the display block must come AFTER AverageHit so the headline stays sheet-faithful")
    end)

    it("CalcOffence scales only the crit BONUS by (1 - RBDTFC) and gates on effective mode", function()
        local text = readSource("Modules/CalcOffence.lua")
        assert.is_truthy(string.find(text,
            'local bossCritReduce = env.mode_effective and enemyDB:Sum("BASE", nil, "ReducedBonusDamageTakenFromCrits") or 0', 1, true),
            "boss reduction must read enemy ReducedBonusDamageTakenFromCrits only in effective mode")
        assert.is_truthy(string.find(text,
            "output.BossCritDamageTakenMult = 1 - bossCritReduce", 1, true),
            "BossCritDamageTakenMult must be 1 - RBDTFC")
        -- crit hit = non-crit floor + bonus x (1 - RBDTFC); NOT a flat scale of the whole crit hit
        assert.is_truthy(string.find(text,
            "output.CritAverageHit = totalHitAvg + ((totalCritAvg - totalHitAvg) + superCritChance * 3 * totalHitAvg) * output.BossCritDamageTakenMult", 1, true),
            "CritAverageHit must keep the non-crit floor and scale only the (crit - non-crit) bonus (super-crit +3 folded into the bonus)")
        assert.is_truthy(string.find(text, "output.CritAverageHitSheet = totalCritAvg", 1, true),
            "full sheet crit hit must be preserved as CritAverageHitSheet")
        assert.is_truthy(string.find(text, "@leb-regression-guard:boss-crit-damage-taken", 1, true),
            "CalcOffence must carry the inline guard marker")
    end)

    it("CalcSections renders the non-crit / crit / crit-weighted breakdown", function()
        local text = readSource("Modules/CalcSections.lua")
        for _, out in ipairs({ "BossCritDamageTakenMult", "NonCritAverageHit", "CritAverageHit", "CritWeightedHit" }) do
            assert.is_truthy(string.find(text, "output:" .. out, 1, true),
                "Crit section must display output:" .. out)
        end
    end)
end)
