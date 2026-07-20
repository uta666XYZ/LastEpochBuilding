-- @leb-regression-guard: no-cooldown-flag-zeroes-cooldown
-- Locks the fix for the systemic cadence gap: "X No Cooldown" spec nodes
-- (Erasing Strike / Shield Throw / Judgement / Focus / Forge Strike / Shield
-- Bash / ...) convert a skill's cooldown into a mana cost, removing the cooldown
-- so the skill is cast/attack-speed-limited. LEB parses these into a NoCooldown
-- FLAG (ModParser "no cooldown" / ModCache " No Cooldown"), but calcSkillCooldown
-- previously IGNORED the flag and kept the base cooldown -- e.g. Erasing Strike's
-- 5s cooldown made LEB model 0.28 casts/s vs the in-game biman11 ~3.6/s (a 12x
-- cadence under-count). Grounded 2026-07-02 via biman11 Erasing Strike: with the
-- fix Speed 0.28 -> 1.68/s and TotalDPS 99,343 -> 596,508 (in-game 754,144,
-- -21% vs -87% before); AverageHit unchanged (cadence-only, per-hit untouched).

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("NoCooldownFlagZeroesCooldown", function()
    local calcText, parserText, cacheText

    setup(function()
        calcText   = readSource("Modules/CalcOffence.lua")
        parserText = readSource("Modules/ModParser.lua")
        cacheText  = readSource("Data/ModCache.lua")
    end)

    it("CalcOffence: carries the regression-guard marker", function()
        assert.is_truthy(
            string.find(calcText, '@leb%-regression%-guard:no%-cooldown%-flag%-zeroes%-cooldown'),
            "CalcOffence must carry the no-cooldown-flag guard marker"
        )
    end)

    it("CalcOffence: calcSkillCooldown honours the NoCooldown flag (cooldown -> 0)", function()
        assert.is_truthy(
            string.find(calcText, 'skillModList:Flag%(skillCfg,%s*"NoCooldown"%)'),
            "calcSkillCooldown must check skillModList:Flag(skillCfg, \"NoCooldown\")"
        )
        assert.is_truthy(
            string.find(calcText, 'NoCooldown"%)%s*then%s*cooldown%s*=%s*0'),
            "the NoCooldown branch must set cooldown = 0"
        )
    end)

    it("ModParser: parses \"no cooldown\" into a NoCooldown flag", function()
        assert.is_truthy(
            string.find(parserText, '%["no cooldown"%]%s*=%s*{%s*flag%("NoCooldown"%)'),
            "ModParser must map \"no cooldown\" -> flag(\"NoCooldown\")"
        )
    end)

    it("ModCache: bakes the \" No Cooldown\" NoCooldown flag mod", function()
        assert.is_truthy(
            string.find(cacheText, 'name="NoCooldown",type="FLAG",value=true', 1, true),
            "ModCache must bake a NoCooldown FLAG mod for the \" No Cooldown\" node"
        )
    end)
end)
