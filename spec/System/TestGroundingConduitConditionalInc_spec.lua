-- @leb-regression-guard: grounding-conduit-conditional-inc
-- "Grounding Conduit" (st38ml-8, Summon Storm Totem tree, Shaman) grants the
-- PLAYER lightning damage. Node description: "You deal increased lightning damage
-- if a Storm Totem has hit a shocked enemy recently." The LE->LEB extraction left
-- the bare stat "+15% Lightning Damage", which ModParser parses as an UNCONDITIONAL
-- LightningDamage MORE (the bare-"+N% <Type> Damage" default). The node must be
-- (a) INC, not MORE, and (b) gated on having an active totem.
-- LE_TREE_NODE_STAT_REWRITE["st38ml-8"] (Data/Global.lua) rewrites the bare stat to
-- "+N% increased Lightning Damage while totem active": "increased" -> INC, and the
-- " while totem active" suffix routes through the existing ModParser condition entry
-- -> Condition:HaveTotem. Dropping the rewrite reverts to the unconditional MORE.

describe("GroundingConduitConditionalInc", function()
    it("bare '+N% Lightning Damage' parses to an UNCONDITIONAL MORE by default (why the rewrite is needed)", function()
        local mods = modLib.parseMod("+15% Lightning Damage")
        assert.is_not_nil(mods)
        assert.are.equals("LightningDamage", mods[1].name)
        assert.are.equals("MORE", mods[1].type)
        assert.is_nil(mods[1][1], "bare stat must carry no condition tag")
    end)

    it("'+N% increased Lightning Damage while totem active' parses to INC gated on HaveTotem (the rewrite target)", function()
        local mods = modLib.parseMod("+15% increased Lightning Damage while totem active")
        assert.is_not_nil(mods)
        assert.are.equals("LightningDamage", mods[1].name)
        assert.are.equals("INC", mods[1].type)
        local tag = mods[1][1]
        assert.is_not_nil(tag, "must carry a condition tag")
        assert.are.equals("Condition", tag.type)
        assert.are.equals("HaveTotem", tag.var)
    end)

    it("st38ml-8 carries a rewrite that makes its bare stat INC + totem-conditional", function()
        local rewrites = LE_TREE_NODE_STAT_REWRITE["st38ml-8"]
        assert.is_not_nil(rewrites, "st38ml-8 must have the grounding-conduit rewrite")
        local s = "+15% Lightning Damage"
        for _, rw in ipairs(rewrites) do
            s = (s:gsub(rw.pat, rw.repl))
        end
        assert.are.equals("+15% increased Lightning Damage while totem active", s)
        local mods = modLib.parseMod(s)
        assert.are.equals("LightningDamage", mods[1].name)
        assert.are.equals("INC", mods[1].type, "Grounding Conduit must be INC, not MORE")
        assert.are.equals("HaveTotem", mods[1][1].var, "Grounding Conduit must be gated on an active totem")
    end)
end)
