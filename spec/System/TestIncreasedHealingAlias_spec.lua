-- @leb-regression-guard:increased-healing-effectiveness-alias
-- Skill-tree nodes whose display stat is the bare "(N)% Increased Healing" (NO
-- "Effectiveness" word) were SILENT FAILURES: ModCache baked {{},"  "} (empty modList).
-- The generic "increased X" path strips "increased" and looks up the remainder "healing"
-- in ModParser's modName map, which only has "healing effectiveness" -> "HealingEffectiveness"
-- (src/Modules/ModParser.lua L409), so the shortened node text resolved to no modName and
-- dropped. These are REAL nodes and each node's OWN description proves the semantics are
-- identical to Healing Effectiveness (src/TreeData/1_4/tree_0.json + tree_2.json, verbatim):
--   Blossoming Garden  "10% Increased Healing"   -> "Increases healing effectiveness for you and your minions."
--   Blessed Springs    "7% Increased Healing"    -> "Increases cold damage and healing effectiveness ..."
--   Improved Blessing  "+20% Increased Healing"  -> "Eterra's Blessing has increased healing effectiveness."
--   Violent Squall     "+200% Increased Healing" -> "Maelstrom ... has significantly increased healing effectiveness ..."
--   Redemption         "+10% Increased Healing"  (tree_2, Paladin)
--   Virtue of Patience "24% Increased Healing"   (tree_2, Paladin)
-- Fix: one whole-line specialModList handler in src/Modules/ModParser.lua emits a clean
-- (residue-free) INC HealingEffectiveness; the 6 stale ModCache rows were DELETED so they
-- re-parse live. Consumed at CalcDefence.lua L1845
--   output.HealingEffectiveness = modDB:Sum("INC", nil, "HealingEffectiveness").
-- See REGRESSION_GUARDS.md "increased-healing-effectiveness-alias".

describe("IncreasedHealingAlias #parser #healing", function()
    local function readSource(relPath)
        local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
        assert.is_not_nil(f, "must be able to open " .. relPath)
        local text = f:read("*a"); f:close()
        return text
    end

    -- 1. Ground truth: the bare node stat strings exist in the tree data --------------
    it("TreeData/1_4/tree_0.json carries the verbatim bare 'Increased Healing' node stats", function()
        local txt = readSource("TreeData/1_4/tree_0.json")
        assert.is_truthy(txt:find("10% Increased Healing", 1, true))
        assert.is_truthy(txt:find("7% Increased Healing", 1, true))
        assert.is_truthy(txt:find("+20% Increased Healing", 1, true))
        assert.is_truthy(txt:find("+200% Increased Healing", 1, true))
    end)
    it("TreeData/1_4/tree_2.json carries the verbatim Paladin bare 'Increased Healing' node stats", function()
        local txt = readSource("TreeData/1_4/tree_2.json")
        assert.is_truthy(txt:find("+10% Increased Healing", 1, true))
        assert.is_truthy(txt:find("24% Increased Healing", 1, true))
    end)

    -- 2. Parse contract: residue-free INC on HealingEffectiveness ---------------------
    local parseCases = {
        { "10% Increased Healing",   10 },
        { "7% Increased Healing",    7 },
        { "+20% Increased Healing",  20 },
        { "+200% Increased Healing", 200 },
        { "+10% Increased Healing",  10 },
        { "24% Increased Healing",   24 },
    }
    for _, c in ipairs(parseCases) do
        it("'"..c[1].."' -> INC HealingEffectiveness "..c[2].." (no residue)", function()
            local list, extra = modLib.parseMod(c[1])
            assert.is_not_nil(list, "must parse")
            assert.is_true(not extra or extra == "", "no residue, got: " .. tostring(extra))
            assert.are.equal(1, #list)
            local m = list[1]
            assert.are.equal("HealingEffectiveness", m.name)
            assert.are.equal("INC", m.type)
            assert.are.equal(c[2], m.value)
            assert.are.equal(0, #m, "no scope tags (plain global healing-effectiveness scalar)")
        end)
    end

    -- 3. modDB delivery: Sum() the way CalcDefence does ------------------------------
    it("parsed mod lands under the stat CalcDefence Sums (INC HealingEffectiveness)", function()
        for _, c in ipairs(parseCases) do
            local list = modLib.parseMod(c[1])
            local db = new("ModDB")
            for _, m in ipairs(list) do db:AddMod(m) end
            assert.are.equal(c[2], db:Sum("INC", nil, "HealingEffectiveness"),
                "modDB:Sum INC HealingEffectiveness must equal "..c[2])
        end
    end)

    -- 4. Same stat as the already-working "Increased Healing Effectiveness" affix ------
    it("bare 'Increased Healing' lands on the SAME stat as 'Increased Healing Effectiveness'", function()
        local bare = modLib.parseMod("37% Increased Healing")
        local full = modLib.parseMod("37% Increased Healing Effectiveness")
        assert.are.equal(full[1].name, bare[1].name)
        assert.are.equal(full[1].type, bare[1].type)
        assert.are.equal(full[1].value, bare[1].value)
    end)

    -- 5. Scoping: must NOT swallow the "Effectiveness" or minion variants ------------
    it("does not intercept 'Increased Healing Effectiveness' (still HealingEffectiveness, 1 mod)", function()
        local list, extra = modLib.parseMod("15% Increased Healing Effectiveness")
        assert.is_not_nil(list)
        assert.is_true(not extra or extra == "", "no residue, got: "..tostring(extra))
        assert.are.equal("HealingEffectiveness", list[1].name)
        assert.are.equal(15, list[1].value)
    end)
    it("does not intercept the minion variant 'Increased Minion Healing'", function()
        -- The whole-line ^...$ handler ends in "healing$" preceded directly by the
        -- number, so "increased minion healing" (extra word) cannot match it; the
        -- minion path is left untouched (no collision with minion code).
        local bareList = modLib.parseMod("10% Increased Minion Healing")
        local hasBareHE = false
        if bareList then
            for _, m in ipairs(bareList) do
                if m.name == "HealingEffectiveness" and #m == 0 then hasBareHE = true end
            end
        end
        assert.is_false(hasBareHE, "minion healing must not map to the plain-global HealingEffectiveness")
    end)

    -- 6. Guard the residue-drop trap ------------------------------------------------
    it("emits nil (clean) extra so PassiveTree:ProcessStats does not drop the mod", function()
        local _, extra = modLib.parseMod("200% Increased Healing")
        assert.is_true(extra == nil or extra == "", "extra must be falsy/empty, got: "..tostring(extra))
    end)
end)
