-- @leb-regression-guard:aspect-effect-buff-scalar
-- Beastmaster "(N)% Increased Aspect of the {Lynx,Shark,Viper} Effect" affixes.
-- Ground truth (verbatim, no fabrication) in src/Data/ModItem_1_4.json:
--   "(10-25)% Increased Aspect of the Lynx Effect"
--   "(6-20)% Increased Aspect of the Shark Effect"
--   "(10-25)% Increased Aspect of the Viper Effect"
--   "(5-12)% Increased Aspect of the Boar Effect"
-- These were SILENT FAILURES: ModCache baked {{}," Effect "} (empty modList) because
-- ModParser's skillNameList post-scan strips "Aspect of the Lynx/Shark/Viper" as a skill
-- name, leaving a bare "Effect" residue that reaches no modName. The buff-effect scalar
-- is a per-buff INCREASE stat that CalcPerform reads as
--   skillModList:Sum("INC", skillCfg, buff.name:gsub(" ", "").."Effect")
-- (src/Modules/CalcPerform.lua ~L733 / ~L751), identical to the working
-- "frenzy effect"->"FrenzyEffect" alias. The three Beastmaster buffs are named
-- "Aspect of the {Lynx,Shark,Viper,Boar}" (src/TreeData/1_4/tree_0.json), so the engine
-- stats are "AspectoftheLynxEffect" / "AspectoftheSharkEffect" / "AspectoftheViperEffect"
-- / "AspectoftheBoarEffect" -- names derived from the engine's own gsub, not invented.
-- Fix: three whole-line specialModList handlers in src/Modules/ModParser.lua emit a clean
-- (residue-free) INC on the matching stat; the 48 stale ModCache rows were DELETED so they
-- re-parse live. See REGRESSION_GUARDS.md "aspect-effect-buff-scalar".

describe("AspectEffect #parser #beastmaster", function()
    local function readSource(relPath)
        local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
        assert.is_not_nil(f, "must be able to open " .. relPath)
        local text = f:read("*a"); f:close()
        return text
    end

    -- 1. Ground truth strings present in the datamine ---------------------------------
    it("ModItem_1_4.json carries the verbatim affix strings", function()
        local txt = readSource("Data/ModItem_1_4.json")
        assert.is_truthy(txt:find("(10-25)% Increased Aspect of the Lynx Effect", 1, true))
        assert.is_truthy(txt:find("(6-20)% Increased Aspect of the Shark Effect", 1, true))
        assert.is_truthy(txt:find("(10-25)% Increased Aspect of the Viper Effect", 1, true))
        assert.is_truthy(txt:find("(5-12)% Increased Aspect of the Boar Effect", 1, true))
    end)

    -- 2. The engine's buff-name -> stat-name transform matches our emitted stat names --
    it("buff.name:gsub(' ','')..'Effect' equals the emitted stat names", function()
        assert.are.equal("AspectoftheLynxEffect",  ("Aspect of the Lynx"):gsub(" ", "") .. "Effect")
        assert.are.equal("AspectoftheSharkEffect", ("Aspect of the Shark"):gsub(" ", "") .. "Effect")
        assert.are.equal("AspectoftheViperEffect", ("Aspect of the Viper"):gsub(" ", "") .. "Effect")
        assert.are.equal("AspectoftheBoarEffect",  ("Aspect of the Boar"):gsub(" ", "") .. "Effect")
    end)

    -- 3. Parse contract: residue-free INC on the per-buff stat ------------------------
    local parseCases = {
        { "125% Increased Aspect of the Lynx Effect",  "AspectoftheLynxEffect",  125 },
        { "13% Increased Aspect of the Shark Effect",  "AspectoftheSharkEffect", 13 },
        { "126% Increased Aspect of the Viper Effect", "AspectoftheViperEffect", 126 },
        { "10% Increased Aspect of the Lynx Effect",   "AspectoftheLynxEffect",  10 },  -- roll floor
        { "25% Increased Aspect of the Viper Effect",  "AspectoftheViperEffect", 25 },  -- roll ceil
        { "9% Increased Aspect of the Boar Effect",    "AspectoftheBoarEffect",  9 },
        { "5% Increased Aspect of the Boar Effect",    "AspectoftheBoarEffect",  5 },   -- roll floor
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

    -- 5. Guard the residue-drop trap: a non-empty extra would make PassiveTree drop it -
    it("emits nil (clean) extra so PassiveTree:ProcessStats does not drop the mod", function()
        local _, extra = modLib.parseMod("18% Increased Aspect of the Lynx Effect")
        -- PassiveTree.lua ProcessStats: `if mod.list and not mod.extra` -> a truthy
        -- non-empty extra drops the mod. nil (or "") is required.
        assert.is_true(extra == nil or extra == "", "extra must be falsy/empty, got: "..tostring(extra))
    end)

    -- 6. BARE alias (no "increased" word) + signed value ----------------------------
    -- @leb-regression-guard:aspect-effect-bare-alias
    -- LE also renders these rolls without "increased" and with a signed prefix, e.g.
    -- "+80% Aspect Of The Shark Effect" (found live in a captured build's ModCache as a
    -- SILENT FAILURE {{},"  Effect "}). Same stat/semantics as the "increased" form.
    local bareCases = {
        { "+80% Aspect Of The Shark Effect", "AspectoftheSharkEffect",  80 },
        { "+10% Aspect Of The Shark Effect", "AspectoftheSharkEffect",  10 },  -- ex-stale ModCache row
        { "20% Aspect of the Lynx Effect",   "AspectoftheLynxEffect",   20 },  -- no sign
        { "-15% Aspect of the Boar Effect",  "AspectoftheBoarEffect",  -15 },  -- reduced roll: negative INC
    }
    for _, c in ipairs(bareCases) do
        it("bare '"..c[1].."' -> INC "..c[2].." "..c[3].." (no residue)", function()
            local list, extra = modLib.parseMod(c[1])
            assert.is_not_nil(list, "must parse")
            assert.is_true(not extra or extra == "", "no residue, got: " .. tostring(extra))
            assert.are.equal(1, #list)
            local m = list[1]
            assert.are.equal(c[2], m.name)
            assert.are.equal("INC", m.type)
            assert.are.equal(c[3], m.value)
        end)
    end

    -- 7. The bare pattern must NOT collide with the "increased" / "less" renderings ---
    it("bare pattern does not swallow the 'increased' or 'less' forms", function()
        -- "increased" form still routes through the increased handler (value 33, INC).
        local inc = modLib.parseMod("33% Increased Aspect of the Shark Effect")
        assert.are.equal("AspectoftheSharkEffect", inc[1].name)
        assert.are.equal(33, inc[1].value)
        -- "less" form has an intervening word before " aspect", so the bare pattern
        -- cannot match it (it is neutralized elsewhere, not turned into a bogus +INC).
        local lst = modLib.parseMod("-60% Less Aspect Of The Shark Effect")
        assert.is_true(lst == nil or #lst == 0,
            "the 'less' rendering must not be captured as a positive INC by the bare alias")
    end)
end)
