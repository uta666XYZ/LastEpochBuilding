-- @leb-regression-guard:erasing-strike-merciful-damaged
-- Erasing Strike Merciful (es6ai-9, maxPoints 4). Raw per-point stats:
--   "+15% Cooldown Recovery Speed"  and  "+5% Melee Damage vs Damaged Enemies"
-- The CDR line parses fine; the second line's "vs Damaged Enemies" condition clause
-- leaves parseMod `extra` residue, so PassiveTree:ProcessStats drops the WHOLE mod (the
-- melee bonus silently contributes NOTHING). Same residue-drop class as the es6ai-26/15
-- siblings -- but the in-game node tooltip (screenshot 2/4 pts, +10%) reads "deals MORE
-- melee damage to enemies that are already damaged (multiplicative with other
-- modifiers)", so this node is a MORE (multiplicative) mod, NOT increased.
--
-- FIX = LE_TREE_NODE_STAT_REWRITE (Data/Global.lua) re-expresses the melee line to
-- "N% more melee damage against damaged enemies", which parses (ModParser:32
-- `^([%+%-]?[%d%.]+)%% more`) to Damage MORE + melee keywordFlag + the enemy
-- ActorCondition {FullLife, neg=true} registered by the "against damaged enemies" phrase
-- (ModParser). "damaged" = NOT full life. conditionEnemyFullLife defaults OFF => enemy is
-- not full life by default => neg-FullLife is TRUE => the MORE applies by DEFAULT (LEB
-- realistic-sustained-DPS convention). NOT corpus-neutral: Merciful has no weapon gate,
-- so every allocating build gains the bonus and was snapshot-regen'd.
-- See REGRESSION_GUARDS.md + memory project_erasing_strike_perhit_under.

local RAW_MERCIFUL = "+5% Melee Damage vs Damaged Enemies"   -- es6ai-9 (per-point; x2 -> 10%)

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

local function findActorCond(mod)
    for _, t in ipairs(mod) do
        if t.type == "ActorCondition" then return t end
    end
    return nil
end

describe("ErasingStrikeMerciful", function()
    it("rewrite entry is registered", function()
        assert.is_not_nil(LE_TREE_NODE_STAT_REWRITE["es6ai-9"], "Merciful rewrite registered")
    end)

    it("rewrites to a residue-free MORE melee mod gated on the enemy being damaged (not full life)", function()
        local rewritten = applyRewrite("es6ai-9", RAW_MERCIFUL)
        assert.are.equals("5% more melee damage against damaged enemies", rewritten)
        local mods, extra = liveParse(rewritten)
        assert.is_falsy(extra, "rewritten line must parse with NO extra residue")
        assert.is_not_nil(mods and mods[1])
        assert.are.equals(1, #mods, "exactly one mod")
        local m = mods[1]
        assert.are.equals("Damage", m.name)
        assert.are.equals("MORE", m.type, "the node tooltip says 'more ... (multiplicative)' -> MORE, not INCREASED")
        assert.are.equals(5, m.value, "per-point value; rank scaling multiplies by node alloc (2 pts -> +10%)")
        assert.are.equals(512, m.keywordFlags, "Melee keyword")
        local ac = findActorCond(m)
        assert.is_not_nil(ac, "must carry an enemy ActorCondition")
        assert.are.equals("enemy", ac.actor)
        assert.are.equals("FullLife", ac.var)
        assert.is_true(ac.neg, "damaged = NOT full life -> negated FullLife")
    end)

    it("regression witness: the RAW node string leaves parse residue (why the rewrite exists)", function()
        local _, extra = liveParse(RAW_MERCIFUL)
        assert.is_truthy(extra and extra ~= "", "raw Merciful line must leave residue -> ProcessStats would drop it")
    end)
end)
