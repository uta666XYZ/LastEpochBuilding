-- @leb-regression-guard: martyrdom-minion-armour
-- Locks the contract that the Necromancer Dread Shade specialization node
-- `ds4d3-3` ("Martyrdom") grants Armour to MINIONS, not the player.
-- Trigger: Qdz2yXN3 (lv99 Necromancer, Vit=99) showed +2970 player Armour
-- (BASE PerStat:Vit) flowing from `ds4d3-3` because the raw stat string was
-- `"30 Armour Per Vitality"` and the cached mod targeted the player modDB.
-- The in-game tooltip + LETools planner confirm the bonus is applied to
-- the minion target of Dread Shade (default-on toggle buff skill).
-- See REGRESSION_GUARDS.md "martyrdom-minion-armour".

describe("MartyrdomMinionArmour", function()
    it("'30 Minion Armour Per Vitality' parses as MinionModifier wrapping Armour BASE PerStat:Vit", function()
        local mods = modLib.parseMod("30 Minion Armour Per Vitality")
        assert.is_not_nil(mods, "parser must recognize the Minion-prefixed stat")
        assert.are.equals("MinionModifier", mods[1].name)
        assert.are.equals("LIST", mods[1].type)
        local inner = mods[1].value and mods[1].value.mod
        assert.is_not_nil(inner, "MinionModifier LIST must carry a wrapped mod")
        assert.are.equals("Armour", inner.name)
        assert.are.equals("BASE", inner.type)
        assert.are.equals(30, inner.value)
        local hasPerStatVit = false
        for _, tag in ipairs(inner) do
            if tag.type == "PerStat" and tag.stat == "Vit" then hasPerStatVit = true end
        end
        assert.is_true(hasPerStatVit, "wrapped mod must carry PerStat:Vit tag")
    end)

    it("'25 Minion Armour Per Vitality' (1.2 value) also parses to MinionModifier", function()
        local mods = modLib.parseMod("25 Minion Armour Per Vitality")
        assert.is_not_nil(mods)
        assert.are.equals("MinionModifier", mods[1].name)
        assert.are.equals("LIST", mods[1].type)
        local inner = mods[1].value and mods[1].value.mod
        assert.is_not_nil(inner)
        assert.are.equals("Armour", inner.name)
        assert.are.equals(25, inner.value)
    end)

    it("ModCache.lua keeps the @leb-regression-guard:martyrdom-minion-armour comment block", function()
        local f = io.open("Data/ModCache.lua", "r")
        assert.is_not_nil(f, "must be able to open Data/ModCache.lua")
        local source = f:read("*a")
        f:close()
        assert.is_truthy(string.find(source, "@leb-regression-guard: martyrdom-minion-armour", 1, true),
            "ModCache.lua must keep the @leb-regression-guard comment so future edits trip review")
    end)

    it("ds4d3-3 stat strings in tree_3.json carry the 'Minion' prefix", function()
        local versions = { ["1_2"] = 25, ["1_3"] = 30, ["1_4"] = 30 }
        for ver, val in pairs(versions) do
            local path = "TreeData/" .. ver .. "/tree_3.json"
            local f = io.open(path, "r")
            assert.is_not_nil(f, "must be able to open " .. path)
            local text = f:read("*a")
            f:close()
            local needle = string.format("%d Minion Armour Per Vitality", val)
            assert.is_truthy(string.find(text, needle, 1, true),
                "tree_3.json " .. ver .. " must contain '" .. needle .. "'")
            -- And must NOT contain the bare (player-armour) form
            local bare = string.format("\"%d Armour Per Vitality\"", val)
            assert.is_falsy(string.find(text, bare, 1, true),
                "tree_3.json " .. ver .. " must NOT contain bare '" .. bare .. "'")
        end
    end)
end)
