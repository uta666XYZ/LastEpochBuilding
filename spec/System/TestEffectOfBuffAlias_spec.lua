-- @leb-regression-guard:effect-of-buff-on-you-bare-alias
-- ALIAS family: bare "+N% Effect of <Buff> on You" (NO "increased" word) is the SAME
-- stat as the "increased" form. The datamine affix text is
--   "(3-5)% increased Effect of Haste on You" / "(3-5)% increased Effect of Frenzy on You"
-- (src/Data/ModItem_1_4.json L75499+, L75643+), and the "increased" rendering already
-- parses to <Buff>Effect INC (ModCache proves "14% increased Effect of Haste on You"
-- -> HasteEffect INC 14). LE also renders these rolls WITHOUT the "increased" word and
-- WITH a "+" prefix ("+14% Effect of Haste on You"); those rows were SILENT FAILURES --
-- ModCache baked {{}," Effect of  on You "} (the buff name stripped by the skill-name
-- post-scan) with an EMPTY modList. Same modName, same INC semantics, same consumer:
--   CalcPerform.lua:1216 / :1234
--     skillModList:Sum("INC", skillCfg, buff.name:gsub(" ", "").."Effect")
-- scales the active Haste/Frenzy buff's modList by (1 + inc/100). The engine buff names
-- are "Haste" and "Frenzy" (ModParser knownBuffsOnYou, L3364), so the stats are
-- "HasteEffect" / "FrenzyEffect" -- derived from the engine's own gsub, not invented.
-- Fix: one whole-line specialModList handler per known buff in ModParser.lua emits a
-- clean (residue-free) INC on the matching stat; the 24 stale bare-form ModCache rows
-- were DELETED so they re-parse live. See REGRESSION_GUARDS.md
-- "effect-of-buff-on-you-bare-alias".

describe("EffectOfBuffAlias #parser #buff", function()
    local function readSource(relPath)
        local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
        assert.is_not_nil(f, "must be able to open " .. relPath)
        local text = f:read("*a"); f:close()
        return text
    end

    -- 1. Ground truth strings present in the datamine ---------------------------------
    it("ModItem_1_4.json carries the verbatim affix strings", function()
        local txt = readSource("Data/ModItem_1_4.json")
        assert.is_truthy(txt:find("increased Effect of Haste on You", 1, true))
        assert.is_truthy(txt:find("increased Effect of Frenzy on You", 1, true))
    end)

    -- 2. The engine's buff-name -> stat-name transform matches our emitted stat names --
    it("buff.name:gsub(' ','')..'Effect' equals the emitted stat names", function()
        assert.are.equal("HasteEffect",  ("Haste"):gsub(" ", "") .. "Effect")
        assert.are.equal("FrenzyEffect", ("Frenzy"):gsub(" ", "") .. "Effect")
    end)

    -- 3. Parse contract: residue-free INC on the per-buff stat (BARE form) ------------
    local parseCases = {
        { "+10% Effect of Haste on You",  "HasteEffect",  10 },
        { "+14% Effect of Haste on You",  "HasteEffect",  14 },
        { "+45% Effect of Haste on You",  "HasteEffect",  45 },
        { "+2% Effect of Frenzy on You",  "FrenzyEffect", 2 },
        { "+11% Effect of Frenzy on You", "FrenzyEffect", 11 },
        { "+9% Effect of Frenzy on You",  "FrenzyEffect", 9 },
        -- no leading '+' also accepted
        { "20% Effect of Haste on You",   "HasteEffect",  20 },
        { "5% Effect of Frenzy on You",   "FrenzyEffect", 5 },
    }
    for _, c in ipairs(parseCases) do
        it("'"..c[1].."' -> INC "..c[2].." "..c[3].." (no residue)", function()
            local list, extra = modLib.parseMod(c[1])
            assert.is_not_nil(list, "must parse")
            assert.is_true(not extra or extra == "", "no residue, got: " .. tostring(extra))
            assert.are.equal(1, #list)
            local m = list[1]
            assert.are.equal(c[2], m.name)
            assert.are.equal("INC", m.type)
            assert.are.equal(c[3], m.value)
            assert.are.equal(0, #m, "no scope tags (plain global buff-effect scalar)")
        end)
    end

    -- 4. modDB delivery: Sum() the way CalcPerform does ------------------------------
    it("parsed mod lands under the stat CalcPerform Sums (INC, per-buff)", function()
        for _, c in ipairs(parseCases) do
            local list = modLib.parseMod(c[1])
            local db = new("ModDB")
            for _, m in ipairs(list) do db:AddMod(m) end
            assert.are.equal(c[3], db:Sum("INC", nil, c[2]),
                "modDB:Sum INC "..c[2].." must equal "..c[3])
        end
    end)

    -- 5. Bare form and the pre-existing "increased" form resolve to the SAME stat -----
    it("bare and 'increased' forms both land as the same INC modName", function()
        local bare = modLib.parseMod("+14% Effect of Haste on You")
        local incr = modLib.parseMod("14% increased Effect of Haste on You")
        assert.are.equal(bare[1].name, incr[1].name)
        assert.are.equal(bare[1].type, incr[1].type)
        assert.are.equal(bare[1].value, incr[1].value)
    end)

    -- 6. Guard the residue-drop trap: a non-empty extra would make PassiveTree drop it -
    it("emits nil (clean) extra so PassiveTree:ProcessStats does not drop the mod", function()
        local _, extra = modLib.parseMod("18% Effect of Haste on You")
        assert.is_true(extra == nil or extra == "", "extra must be falsy/empty, got: "..tostring(extra))
    end)

    -- 7. Non-collision: the "increased" handler is NOT shadowed / mis-scoped ----------
    it("does not swallow other 'effect of' text or collide with the increased form", function()
        -- The bare pattern requires "%% effect of <buff> on you$" so it cannot match the
        -- "%% increased effect of ..." string (which still routes to the increased handler).
        local list = modLib.parseMod("14% increased Effect of Frenzy on You")
        assert.are.equal("FrenzyEffect", list[1].name)
        assert.are.equal(14, list[1].value)
    end)

    -- 8. SIGNED value: a REDUCED roll ("-N%") must parse to a NEGATIVE INC -------------
    -- @leb-regression-guard:effect-of-buff-signed-value
    -- Found live in a captured build: "-7% Effect of Frenzy on You". The old "%+?"
    -- anchor matched only "+", so the "-" form was a SILENT FAILURE; and had the sign
    -- sat outside the capture, a reduction would have flipped to a +7 increase. The sign
    -- is now inside the number group, so tonumber keeps it negative.
    local signedCases = {
        { "-7% Effect of Frenzy on You",           "FrenzyEffect", -7 },
        { "-12% Effect of Frenzy on You",          "FrenzyEffect", -12 },
        { "-5% increased Effect of Haste on You",  "HasteEffect",  -5 },
    }
    for _, c in ipairs(signedCases) do
        it("signed '"..c[1].."' -> INC "..c[3].." (no residue)", function()
            local list, extra = modLib.parseMod(c[1])
            assert.is_not_nil(list, "must parse")
            assert.is_true(not extra or extra == "", "no residue, got: " .. tostring(extra))
            assert.are.equal(1, #list)
            assert.are.equal(c[2], list[1].name)
            assert.are.equal("INC", list[1].type)
            assert.are.equal(c[3], list[1].value)
        end)
    end
end)
