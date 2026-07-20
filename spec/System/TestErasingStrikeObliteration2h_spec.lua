-- @leb-regression-guard:erasing-strike-obliteration-2h-double
-- Erasing Strike Obliteration (es6ai-16, maxPoints 5). Raw per-point stats:
--   "+10% Damage"  and  " Doubled with a 2h Weapon"
-- The node is "+X% MORE Damage, DOUBLED while wielding a 2h weapon". Bare "+X% Damage"
-- parses to Damage MORE; the " Doubled with a 2h Weapon" clause is its own stat line and
-- was residue-DROPPED, so LEB applied the un-doubled +50% MORE (x1.50 at 5 pts) to every
-- build -- undercounting 2h builds, which should get +100% MORE (x2.00).
--
-- FIX = split into two MUTUALLY EXCLUSIVE weapon-gated MORE mods (a single "+50% doubled"
-- cannot be modelled as a second additive mod: two MOREs multiply 1.5*1.5=2.25, not add):
--   1h -> "+10% Damage with 1h weapon" (x5 = +50% MORE = x1.50, unchanged)
--   2h -> "+20% Damage with 2h weapon" (x5 = +100% MORE = x2.00, doubled)
-- Verified on TitoGaoS4 (2h World Splitter): only the 2h mod applies (no double-count),
-- non-crit void per-hit 74,115.637 -> 98,573.80 = x1.330, More(Damage) 2.20 -> 2.926.
-- Per-point values are hardcoded (the doubling has to double the value); if LE re-tunes
-- the "+10%", the pattern stops matching and this spec surfaces it. See REGRESSION_GUARDS.md.

local RAW_BASE   = "+10% Damage"
local RAW_DOUBLE = " Doubled with a 2h Weapon"

local function applyRewrite(nodeId, stat)
    local rw = LE_TREE_NODE_STAT_REWRITE[nodeId]
    if rw then
        for _, r in ipairs(rw) do
            stat = (stat:gsub(r.pat, r.repl))
        end
    end
    return stat
end

local function liveParse(line)
    if modLib.parseModCache then modLib.parseModCache[line] = nil end
    return modLib.parseMod(line)
end

local function findCond(mod)
    for _, t in ipairs(mod) do
        if t.type == "Condition" then return (t.neg and "!" or "") .. t.var end
    end
    return nil
end

describe("ErasingStrikeObliteration2h", function()
    it("rewrite entry registered", function()
        assert.is_not_nil(LE_TREE_NODE_STAT_REWRITE["es6ai-16"], "Obliteration rewrite registered")
    end)

    it("base line -> NEG-2h-gated MORE at BASE value (+10%/pt; covers 1h AND weaponless)", function()
        local rewritten = applyRewrite("es6ai-16", RAW_BASE)
        assert.are.equals("+10% Damage while not wielding a two handed weapon", rewritten)
        local mods, extra = liveParse(rewritten)
        assert.is_falsy(extra, "must be residue-free")
        assert.is_not_nil(mods and mods[1])
        assert.are.equals("Damage", mods[1].name)
        assert.are.equals("MORE", mods[1].type, "Obliteration '+X% Damage' is MORE")
        assert.are.equals(10, mods[1].value, "un-doubled per-point value")
        assert.are.equals("!UsingTwoHandedWeapon", findCond(mods[1]), "negated 2h -> applies to 1h + weaponless")
    end)

    it("doubling clause -> 2h-gated MORE at DOUBLE value (+20%/pt)", function()
        local rewritten = applyRewrite("es6ai-16", RAW_DOUBLE)
        assert.are.equals("+20% Damage with 2h weapon", rewritten)
        local mods, extra = liveParse(rewritten)
        assert.is_falsy(extra, "must be residue-free")
        assert.is_not_nil(mods and mods[1])
        assert.are.equals("Damage", mods[1].name)
        assert.are.equals("MORE", mods[1].type)
        assert.are.equals(20, mods[1].value, "doubled per-point value (10 -> 20)")
        assert.are.equals("UsingTwoHandedWeapon", findCond(mods[1]))
    end)

    it("the two mods are mutually exclusive (2h XOR not-2h -> exactly one applies, no double-count, no gap)", function()
        local base = liveParse(applyRewrite("es6ai-16", RAW_BASE))[1]
        local dbl  = liveParse(applyRewrite("es6ai-16", RAW_DOUBLE))[1]
        assert.are.equals("!UsingTwoHandedWeapon", findCond(base))
        assert.are.equals("UsingTwoHandedWeapon", findCond(dbl))
    end)

    it("regression witness: the RAW doubling clause parses to nothing (why the rewrite exists)", function()
        local mods = liveParse(RAW_DOUBLE)
        assert.are.equals(0, #mods, "' Doubled with a 2h Weapon' has no standalone parse -> was silently dropped")
    end)
end)
