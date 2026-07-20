-- @leb-regression-guard:erasing-strike-conditional-melee
-- See REGRESSION_GUARDS.md + memory project_erasing_strike_perhit_under.
-- Validation provenance is retained in maintainer notes.

local RAW_FINAL_HOUR = "+100% Melee Damage vs 12 stacks of Time Rot"   -- es6ai-26 (alloc 1)
local RAW_CHAMBER    = "+25% Melee Damage to Slowed"                    -- es6ai-15 (per-point; x2 -> 50%)

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

describe("ErasingStrikeConditionalMelee", function()
    it("rewrite entries are registered for both large nodes", function()
        assert.is_not_nil(LE_TREE_NODE_STAT_REWRITE["es6ai-26"], "Final Hour rewrite registered")
        assert.is_not_nil(LE_TREE_NODE_STAT_REWRITE["es6ai-15"], "Chamber of Fate rewrite registered")
    end)

    it("Final Hour: rewrites to a residue-free MORE melee mod gated on enemy Time Rot", function()
        local rewritten = applyRewrite("es6ai-26", RAW_FINAL_HOUR)
        assert.are.equals("100% more melee damage against time rotting enemies", rewritten)
        local mods, extra = liveParse(rewritten)
        assert.is_falsy(extra, "rewritten line must parse with NO extra residue")
        assert.is_not_nil(mods and mods[1])
        local m = mods[1]
        assert.are.equals("Damage", m.name)
        assert.are.equals("MORE", m.type, "the in-game tooltip says MORE (multiplicative with other modifiers)")
        assert.are.equals(100, m.value)
        assert.are.equals(512, m.keywordFlags, "Melee keyword")
        local ac = findActorCond(m)
        assert.is_not_nil(ac, "must carry an enemy ActorCondition")
        assert.are.equals("enemy", ac.actor)
        assert.are.equals("TimeRotted", ac.var)
    end)

    it("Chamber of Fate: rewrites to a residue-free MORE melee mod gated on enemy Slowed", function()
        local rewritten = applyRewrite("es6ai-15", RAW_CHAMBER)
        assert.are.equals("25% more melee damage to slowed enemies", rewritten)
        local mods, extra = liveParse(rewritten)
        assert.is_falsy(extra, "rewritten line must parse with NO extra residue")
        assert.is_not_nil(mods and mods[1])
        local m = mods[1]
        assert.are.equals("Damage", m.name)
        assert.are.equals("MORE", m.type, "the in-game tooltip says MORE (multiplicative with other modifiers)")
        assert.are.equals(25, m.value, "per-point value; rank scaling multiplies by node alloc")
        assert.are.equals(512, m.keywordFlags)
        local ac = findActorCond(m)
        assert.is_not_nil(ac, "must carry an enemy ActorCondition")
        assert.are.equals("enemy", ac.actor)
        assert.are.equals("Slowed", ac.var)
    end)

    it("regression witness: the RAW node strings leave parse residue (why the rewrite exists)", function()
        local _, e1 = liveParse(RAW_FINAL_HOUR)
        assert.is_truthy(e1 and e1 ~= "", "raw Final Hour line must leave residue -> ProcessStats would drop it")
        local _, e2 = liveParse(RAW_CHAMBER)
        assert.is_truthy(e2 and e2 ~= "", "raw Chamber line must leave residue -> ProcessStats would drop it")
    end)
end)
