-- @leb-regression-guard:shatter-totem-upheaval-child
-- See REGRESSION_GUARDS.md "shatter-totem-upheaval-child".
-- @leb-regression-guard:shatter-totem-count-fold
-- neutral (0 builds allocate uph41-29; nil fold -> x1). See REGRESSION_GUARDS.md
-- Validation provenance is retained in maintainer notes.

local function readFile(path)
    local f = io.open(path, "r") or io.open("src/" .. path, "r")
    if not f then return nil end
    local s = f:read("*a"); f:close()
    return s
end

describe("ShatterTotem Upheaval-child grant registry (node-gated, no fabrication)", function()
    it("Upheaval grants ShatterTotem gated on uph41-29 (Totems Shatter On Upheaval Hit)", function()
        local grants = data.subSkillGrants.Upheaval
        assert.is_table(grants, "Upheaval must be in the grant registry")
        -- entry 1 is the pre-existing SummonUpheavalTotem; ShatterTotem is added after it.
        local shatter
        for _, g in ipairs(grants) do
            if g.skillId == "ShatterTotem" then shatter = g end
        end
        assert.is_table(shatter, "Upheaval must grant ShatterTotem")
        assert.are.equals("uph41-29", shatter.requiresNode,
            "the Shatter Totem grant must be node-conditional on uph41-29")
        assert.is_nil(shatter.summon, "Shatter Totem is a direct spell, not a summon")
        assert.is_nil(shatter.noParentTreeBaseConversion,
            "Shatter Totem must INHERIT Upheaval's tree Cold conversion (it is Cold in-game)")
    end)

    it("ShatterTotem carries the datamined Physical Spell base + eff 4.0", function()
        local d = data.skills.ShatterTotem
        assert.is_table(d, "ShatterTotem must exist in data.skills")
        assert.are.equals("Shatter Totem", d.name)
        assert.are.equals(80, d.stats.spell_base_physical_damage)
        assert.are.equals(4, d.stats.damageEffectiveness)
        assert.are.equals(5, d.stats.critChance)
        assert.are.equals(100, d.stats["base_critical_strike_multiplier_+"])
        assert.is_true(d.baseFlags.spell, "Shatter Totem is a Spell")
        assert.is_true(d.baseFlags.hit, "Shatter Totem deals a Hit (isHit=1 in datamine)")
        assert.is_nil(d.stats.spell_base_cold_damage,
            "base must be Physical (converted to Cold by uph41-5), not native Cold")
    end)
end)

describe("shatter-totem-upheaval-child guard markers", function()
    it("SubSkillGrants carries the grant guard marker at the Upheaval entry", function()
        local text = assert(readFile("Data/SubSkillGrants.lua"))
        assert.is_truthy(text:find("@leb%-regression%-guard:shatter%-totem%-upheaval%-child"),
            "SubSkillGrants must carry the guard marker")
        assert.is_truthy(text:find('skillId = "ShatterTotem", requiresNode = "uph41%-29"'),
            "SubSkillGrants must register the node-gated ShatterTotem grant")
    end)
end)

-- The concurrent-Thorn-Totem count fold: Shatter Totem fires once per active Thorn Totem
-- on every Upheaval hit, so its FullDPS contribution is x N with N = the DERIVED totem count.
describe("shatter-totem-count-fold (derived totem-count multiplier)", function()
    -- Faithful mirror of the CalcSetup computation (guard shatter-totem-count-fold):
    --   N = base + Sum(alloc x perPoint of shatterFoldCountNodes)
    --         - Sum(alloc x perPoint of shatterFoldCountNegNodes), floored at 1.
    local function computeFold(grant, allocNodes)
        local fold = grant.shatterFoldCountBase
        if grant.shatterFoldCountNodes then
            for nodeId, perPoint in pairs(grant.shatterFoldCountNodes) do
                local node = allocNodes[nodeId]
                if node then fold = fold + (node.alloc or 1) * perPoint end
            end
        end
        if grant.shatterFoldCountNegNodes then
            for nodeId, perPoint in pairs(grant.shatterFoldCountNegNodes) do
                local node = allocNodes[nodeId]
                if node then fold = fold - (node.alloc or 1) * perPoint end
            end
        end
        return math.max(1, fold)
    end

    local function shatterGrant()
        for _, g in ipairs(data.subSkillGrants.Upheaval) do
            if g.skillId == "ShatterTotem" then return g end
        end
    end

    it("the ShatterTotem grant declares the datamined fold-count model", function()
        local g = shatterGrant()
        assert.are.equals(2, g.shatterFoldCountBase,
            "base Maximum Thorn Totems is 2 (in-game 6 with th39-2 at 4/4 -> 6-4)")
        assert.is_table(g.shatterFoldCountNodes)
        assert.are.equals(1, g.shatterFoldCountNodes["th39-2"],
            "th39-2 'Thorn Totem Tree More Totems' grants +1 Maximum Thorn Totems per point")
        assert.is_table(g.shatterFoldCountNegNodes)
        assert.are.equals(1, g.shatterFoldCountNegNodes["th39-3"],
            "th39-3 'Thorn Totem Ring' grants -1 Maximum Thorn Totems")
    end)

    it("fold = concurrent totem count = 6 for the grounding build (th39-2 at 4/4)", function()
        local g = shatterGrant()
        -- Validation provenance is retained in maintainer notes.
        assert.are.equals(6, computeFold(g, { ["th39-2"] = { alloc = 4 } }),
            "base 2 + th39-2 x4 = 6, matching the in-game 216/36 fold")
    end)

    it("th39-3 (Thorn Totem Ring) subtracts one totem from the fold", function()
        local g = shatterGrant()
        assert.are.equals(5, computeFold(g, { ["th39-2"] = { alloc = 4 }, ["th39-3"] = { alloc = 1 } }),
            "base 2 + 4 - 1 = 5")
    end)

    it("fold falls back to the base count when no count nodes are allocated", function()
        local g = shatterGrant()
        assert.are.equals(2, computeFold(g, {}),
            "with no th39 count nodes the fold is the base Maximum Thorn Totems (2)")
    end)

    it("fold is floored at 1 (never zero/negative, and unspecced -> x1)", function()
        -- A pathological -N build still folds at >= 1; and a skill WITHOUT the fold fields
        -- carries no shatterTotemFoldCount, so calcFullDPS multiplies by 1 (see below).
        local pathological = { shatterFoldCountBase = 2, shatterFoldCountNegNodes = { ["th39-3"] = 5 } }
        assert.are.equals(1, computeFold(pathological, { ["th39-3"] = { alloc = 5 } }),
            "2 - 5 = -3 must floor to 1")
    end)

    it("CalcSetup derives the fold from cross-tree th39 nodes and carries it onto the group", function()
        local src = assert(readFile("Modules/CalcSetup.lua"))
        assert.is_truthy(src:find("@leb%-regression%-guard:shatter%-totem%-count%-fold"),
            "CalcSetup must carry the count-fold guard marker")
        assert.is_truthy(src:find("grant.shatterFoldCountBase", 1, true),
            "CalcSetup must compute the fold from the grant's base")
        assert.is_truthy(src:find("subEntry.shatterTotemFoldCount = m_max(1, fold)", 1, true),
            "the derived fold must be floored at 1 and stored on the sub-skill entry")
        assert.is_truthy(src:find("group.shatterTotemFoldCount = grantedSkill.shatterTotemFoldCount", 1, true),
            "the fold must be carried onto the sub-skill's own socket group")
    end)

    it("calcFullDPS folds ONLY the Shatter Totem group's slot (nil -> x1 elsewhere)", function()
        local src = assert(readFile("Modules/Calcs.lua"))
        assert.is_truthy(src:find("@leb%-regression%-guard:shatter%-totem%-count%-fold"),
            "calcFullDPS must carry the count-fold guard marker")
        assert.is_truthy(src:find("activeSkill.socketGroup.shatterTotemFoldCount) or 1", 1, true),
            "the fold defaults to x1 for every skill without shatterTotemFoldCount (corpus-neutral)")
        assert.is_truthy(src:find("local packCount = activeSkillCount * shatterFold", 1, true),
            "the fold must ride the pack count so the FullDPS slot is x N")
    end)
end)
