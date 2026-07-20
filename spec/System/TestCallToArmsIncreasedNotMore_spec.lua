-- @leb-regression-guard: call-to-arms-increased-not-more
-- "Call To Arms" (ah443-10, Holy Aura tree, Paladin) grants the player and allies
-- INCREASED physical damage (node description: "Holy Aura grants you and your
-- allies increased physical damage."). The LE->LEB extraction dropped the
-- "increased" keyword, leaving the bare stat "+10% Physical Damage", which
-- ModParser parses as a MULTIPLICATIVE PhysicalDamage MORE (the correct default
-- for the ~45 nodes whose description actually says "more"/"multiplicative").
-- LE_TREE_NODE_STAT_REWRITE["ah443-10"] (Data/Global.lua) re-inserts "increased"
-- so it parses to PhysicalDamage INC. Node-scoped so the genuinely-MORE nodes are
-- untouched. Dropping the rewrite reverts to the MORE over-count.

describe("CallToArmsIncreasedNotMore", function()
    it("bare '+N% Physical Damage' parses to MORE by default (why the rewrite is needed)", function()
        local mods = modLib.parseMod("+10% Physical Damage")
        assert.is_not_nil(mods)
        assert.are.equals("PhysicalDamage", mods[1].name)
        assert.are.equals("MORE", mods[1].type)
    end)

    it("'+N% increased Physical Damage' parses to INC (the rewrite target)", function()
        local mods = modLib.parseMod("+10% increased Physical Damage")
        assert.is_not_nil(mods)
        assert.are.equals("PhysicalDamage", mods[1].name)
        assert.are.equals("INC", mods[1].type)
    end)

    it("ah443-10 carries a rewrite that turns its bare stat into 'increased'", function()
        local rewrites = LE_TREE_NODE_STAT_REWRITE["ah443-10"]
        assert.is_not_nil(rewrites, "ah443-10 must have the increased-not-more rewrite")
        local s = "+10% Physical Damage"
        for _, rw in ipairs(rewrites) do
            s = (s:gsub(rw.pat, rw.repl))
        end
        assert.are.equals("+10% increased Physical Damage", s)
        local mods = modLib.parseMod(s)
        assert.are.equals("PhysicalDamage", mods[1].name)
        assert.are.equals("INC", mods[1].type, "Call To Arms must be INC, not MORE")
    end)
end)
