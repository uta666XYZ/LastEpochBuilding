-- @leb-regression-guard:exulis-haste-effect-per-rampancy
-- Exulis (Oracle Amulet, unique) carries "5% Increased effect of Haste per 10 Rampancy"
-- (src/Data/Uniques/uniques_1_4.json L9476, uniques.json L10662). The pre-existing
-- buff-effect handlers ("on you" / "per strength" / "while dual wielding") only anchor
-- their own tails; the " per N rampancy" tail fell through -- "Haste" was stripped by the
-- skill-name post-scan, leaving a bare " effect of " residue, so ModCache baked
-- {{}," effect of   "} (EMPTY modList, SILENT FAILURE) at :14683.
-- Same stat, same INC semantics, same consumer as the working "on you" form:
--   CalcPerform.lua  skillModList:Sum("INC", skillCfg, buff.name:gsub(" ","").."Effect")
-- scales the active Haste buff's modList by (1 + inc/100). The PerStat:Rampancy tag with
-- a captured divisor (Rampancy is the Vit-converted Season-4 attribute; ModStore.lua:413
-- resolves PerStat, :450 applies base/div) is the standard tag, carried inline on the mod
-- with source=nil (NOT "") so a strict `not extra` consumer keeps the flag. BOTH the
-- coefficient (5) and the divisor (10) are CAPTURED from the string, never hardcoded.
-- NON-DPS: Haste is movement-only in-game (datamine ailment id 33 "Increases movement
-- speed", single buff property 9 = MovementSpeed, increasedValue 0.30, dealsDamage=false)
-- and LEB models it as MovementSpeed INC 30 (ConfigOptions.lua:511) -- HasteEffect scales
-- movement speed only. Fix: one whole-line specialModList handler in ModParser.lua
-- (residue-free); the stale ModCache row was DELETED so it re-parses live.
-- See REGRESSION_GUARDS.md.

describe("ExulisHasteEffectRampancy #parser #buff", function()
    local function readSource(relPath)
        local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
        assert.is_not_nil(f, "must be able to open " .. relPath)
        local text = f:read("*a"); f:close()
        return text
    end

    -- 1. Ground truth: the verbatim affix string lives on the Exulis unique ------------
    it("uniques_1_4.json carries the verbatim Exulis affix string", function()
        local txt = readSource("Data/Uniques/uniques_1_4.json")
        assert.is_truthy(txt:find("Increased effect of Haste per 10 Rampancy", 1, true))
    end)

    -- 2. The stale ModCache row is GONE (else the empty cache shadows live parse) ------
    it("the silent-failure ModCache row was deleted", function()
        local txt = readSource("Data/ModCache.lua")
        assert.is_falsy(txt:find("Increased effect of Haste per 10 Rampancy", 1, true),
            "stale per-Rampancy cache row must be deleted so it re-parses live")
    end)

    -- 3. Parse contract: -> HasteEffect INC + PerStat{Rampancy, div=N}, no residue -----
    -- Both the coefficient and the divisor are captured from the string.
    local cases = {
        { "5% Increased effect of Haste per 10 Rampancy", 5, 10 },
        { "3% increased effect of Haste per 5 Rampancy",  3, 5 },
    }
    for _, c in ipairs(cases) do
        it("'"..c[1].."' -> INC HasteEffect "..c[2].." + PerStat Rampancy div "..c[3].." (no residue)", function()
            local list, extra = modLib.parseMod(c[1])
            assert.is_not_nil(list, "must parse")
            assert.is_true(not extra or extra == "", "no residue, got: " .. tostring(extra))
            assert.are.equal(1, #list)
            local m = list[1]
            assert.are.equal("HasteEffect", m.name)
            assert.are.equal("INC", m.type)
            assert.are.equal(c[2], m.value)
            assert.is_nil(m.source, "source must be nil (not '') so the flag survives")
            assert.are.equal(1, #m, "exactly one tag")
            assert.are.equal("PerStat", m[1].type)
            assert.are.equal("Rampancy", m[1].stat)
            assert.are.equal(c[3], m[1].div)
        end)
    end

    -- 4. modDB delivery: per-Rampancy INC scales HasteEffect by Rampancy/div ----------
    it("per-Rampancy INC scales HasteEffect (5 per 10 Rampancy)", function()
        local list = modLib.parseMod("5% Increased effect of Haste per 10 Rampancy")
        local db = new("ModDB")
        for _, m in ipairs(list) do db:AddMod(m) end
        -- GetStat reads actor.output[stat]; Rampancy has no converted twin (only the
        -- forward Vit->Rampancy map exists), so nothing else contributes.
        db.actor.output = { Rampancy = 100 }
        assert.are.equal(50, db:Sum("INC", nil, "HasteEffect"), "5 * (100 / 10) = 50")
        db.actor.output = { Rampancy = 0 }
        assert.are.equal(0, db:Sum("INC", nil, "HasteEffect"), "no Rampancy -> no effect")
    end)

    -- 5. Engine buff-name -> stat transform matches the emitted stat ------------------
    it("buff.name:gsub(' ','')..'Effect' equals HasteEffect", function()
        assert.are.equal("HasteEffect", ("Haste"):gsub(" ", "") .. "Effect")
    end)

    -- 6. Non-collision: the new handler does not shadow the "on you" form -------------
    it("does not collide with the 'on you' increased form", function()
        local list = modLib.parseMod("14% increased Effect of Haste on You")
        assert.are.equal("HasteEffect", list[1].name)
        assert.are.equal(14, list[1].value)
        assert.are.equal(0, #list[1], "on-you form carries no scope tags")
    end)
end)
