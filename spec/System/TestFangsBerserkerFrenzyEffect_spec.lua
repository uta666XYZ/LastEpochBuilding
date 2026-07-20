-- @leb-regression-guard:fangs-berserker-frenzy-effect
-- Fangs of the Berserker (unique 446, src/Data/Uniques/uniques_1_4.json) carries two
-- buff-effect scalars the parser was silently dropping:
--   "(12-20)% increased Effect of Frenzy while Dual Wielding"
--   "0.5% increased Effect of Frenzy per Strength"
-- Ground truth (datamine, datamined game source unique 446): mod idx 6 val 0.12 / max 0.20
-- (dual-wield), mod idx 7 val 0.005 / max 0.01 (per-Str is a 0.5%->1% ROLLABLE, so the
-- coefficient is CAPTURED from the string, never hardcoded).
-- The pre-existing "on you" handlers only anchor the " on you" suffix; the
-- "while dual wielding" / "per strength" tails fell through -- "Frenzy" is stripped by
-- the skill-name post-scan, leaving a bare " Effect of " residue, so ModCache baked
-- {{}," Effect of   "} (EMPTY modList, SILENT FAILURE) at :10026 / :11708.
-- Same stat, same INC semantics, same consumer as the working "on you" form:
--   CalcPerform.lua:1305 / :1323
--     skillModList:Sum("INC", skillCfg, buff.name:gsub(" ", "").."Effect")
-- scales the active Frenzy buff's modList by (1 + inc/100). The DualWielding Condition
-- tag (modTagList "while dual wielding", ModParser.lua:952) and PerStat:Str tag
-- (Attributes[2]="Str", Global.lua:97; precedent ModCache.lua:10280 "... per player
-- Attunement" -> FrenzyEffect INC + PerStat) are the standard tags, carried inline on
-- the mod with source=nil (NOT "") so a strict `not extra` consumer keeps the flag.
-- Fix: two whole-line specialModList handlers in ModParser.lua (residue-free); the two
-- stale ModCache rows were DELETED so they re-parse live. See REGRESSION_GUARDS.md.

describe("FangsBerserkerFrenzyEffect #parser #buff", function()
    local function readSource(relPath)
        local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
        assert.is_not_nil(f, "must be able to open " .. relPath)
        local text = f:read("*a"); f:close()
        return text
    end

    -- 1. Ground truth: the verbatim affix strings live on unique 446 -----------------
    it("uniques_1_4.json carries the verbatim Fangs affix strings", function()
        local txt = readSource("Data/Uniques/uniques_1_4.json")
        assert.is_truthy(txt:find("increased Effect of Frenzy while Dual Wielding", 1, true))
        assert.is_truthy(txt:find("increased Effect of Frenzy per Strength", 1, true))
    end)

    -- 2. The stale ModCache rows are GONE (else the empty cache shadows live parse) ---
    it("the two silent-failure ModCache rows were deleted", function()
        local txt = readSource("Data/ModCache.lua")
        assert.is_falsy(txt:find("increased Effect of Frenzy while Dual Wielding", 1, true),
            "stale dual-wield cache row must be deleted so it re-parses live")
        assert.is_falsy(txt:find("increased Effect of Frenzy per Strength", 1, true),
            "stale per-Strength cache row must be deleted so it re-parses live")
    end)

    -- 3. Parse contract: DUAL WIELDING -> FrenzyEffect INC + Condition:DualWielding ---
    local dwCases = {
        { "12% increased Effect of Frenzy while Dual Wielding", 12 },
        { "16% increased Effect of Frenzy while Dual Wielding", 16 },
        { "20% increased Effect of Frenzy while Dual Wielding", 20 },
    }
    for _, c in ipairs(dwCases) do
        it("'"..c[1].."' -> INC FrenzyEffect "..c[2].." + DualWielding (no residue)", function()
            local list, extra = modLib.parseMod(c[1])
            assert.is_not_nil(list, "must parse")
            assert.is_true(not extra or extra == "", "no residue, got: " .. tostring(extra))
            assert.are.equal(1, #list)
            local m = list[1]
            assert.are.equal("FrenzyEffect", m.name)
            assert.are.equal("INC", m.type)
            assert.are.equal(c[2], m.value)
            assert.is_nil(m.source, "source must be nil (not '') so the flag survives")
            assert.are.equal(1, #m, "exactly one tag")
            assert.are.equal("Condition", m[1].type)
            assert.are.equal("DualWielding", m[1].var)
        end)
    end

    -- 4. Parse contract: PER STRENGTH -> FrenzyEffect INC + PerStat:Str --------------
    -- Coefficient is captured, so both the current 0.5% roll and the legacy 1% render.
    local strCases = {
        { "0.5% increased Effect of Frenzy per Strength", 0.5 },
        { "1% increased Effect of Frenzy per Strength",   1 },
    }
    for _, c in ipairs(strCases) do
        it("'"..c[1].."' -> INC FrenzyEffect "..c[2].." + PerStat Str (no residue)", function()
            local list, extra = modLib.parseMod(c[1])
            assert.is_not_nil(list, "must parse")
            assert.is_true(not extra or extra == "", "no residue, got: " .. tostring(extra))
            assert.are.equal(1, #list)
            local m = list[1]
            assert.are.equal("FrenzyEffect", m.name)
            assert.are.equal("INC", m.type)
            assert.are.equal(c[2], m.value)
            assert.is_nil(m.source, "source must be nil (not '') so the flag survives")
            assert.are.equal(1, #m, "exactly one tag")
            assert.are.equal("PerStat", m[1].type)
            assert.are.equal("Str", m[1].stat)
        end)
    end

    -- 5. modDB delivery: the dual-wield roll lands under FrenzyEffect when the -------
    -- DualWielding condition holds, and drops to 0 when it does not.
    it("dual-wield INC lands under FrenzyEffect gated by DualWielding", function()
        local list = modLib.parseMod("16% increased Effect of Frenzy while Dual Wielding")
        local db = new("ModDB")
        for _, m in ipairs(list) do db:AddMod(m) end
        db.conditions["DualWielding"] = true
        assert.are.equal(16, db:Sum("INC", nil, "FrenzyEffect"), "full effect while dual wielding")
        db.conditions["DualWielding"] = false
        assert.are.equal(0, db:Sum("INC", nil, "FrenzyEffect"), "no effect when not dual wielding")
    end)

    -- 6. modDB delivery: per-Str INC scales with output.Str -------------------------
    it("per-Strength INC scales FrenzyEffect by Strength (0.5 per point)", function()
        local list = modLib.parseMod("0.5% increased Effect of Frenzy per Strength")
        local db = new("ModDB")
        for _, m in ipairs(list) do db:AddMod(m) end
        -- GetStat reads actor.output[stat] (or cfg.skillStats); no Brutality twin set.
        db.actor.output = { Str = 100 }
        assert.are.equal(50, db:Sum("INC", nil, "FrenzyEffect"), "0.5 * 100 Str = 50")
    end)

    -- 7. Engine buff-name -> stat transform matches the emitted stat ----------------
    it("buff.name:gsub(' ','')..'Effect' equals FrenzyEffect", function()
        assert.are.equal("FrenzyEffect", ("Frenzy"):gsub(" ", "") .. "Effect")
    end)

    -- 8. Non-collision: the new handlers do not shadow the "on you" form ------------
    it("does not collide with the 'on you' increased form", function()
        local list = modLib.parseMod("14% increased Effect of Frenzy on You")
        assert.are.equal("FrenzyEffect", list[1].name)
        assert.are.equal(14, list[1].value)
        assert.are.equal(0, #list[1], "on-you form carries no scope tags")
    end)
end)
