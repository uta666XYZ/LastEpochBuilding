-- @leb-regression-guard: ballista-agile-engineering-attack-speed-inc
-- Locks the LE_TREE_NODE_STAT_REWRITE entry that fixes Ballista spec node
-- ba1574-18 "Agile Engineering" "+1% Attack Speed per 5 Dexterity".
--
-- BUG (2026-07-09, Rem-MK3 A/B capture): the raw stat lacks the word "increased",
-- so the parser maps "+X% Attack Speed" to a Speed BASE mod. The minion attack-rate
-- formula (CalcOffence.lua:~2143) reads only Sum("INC","Speed") + More("Speed") and
-- NEVER Sum("BASE","Speed"), so the node's per-Dexterity bonus was silently dropped.
-- In-game single-ballista rate 2.532/s (OFF) -> 2.882/s (ON) = +13.8% real effect.
--
-- FIX: rewrite ONLY the attack-speed stat line to the "increased" form so it parses
-- to Speed INC + PerStat{Dex,div=5}. The placement-speed line is untouched.
--
-- (1) source-text lock: the rewrite entry stays registered and targets the
--     attack-speed line (not placement).
-- (2) functional: applying the rewrite's pattern/repl to the raw stat yields a string
--     that parseMod turns into a Speed *INC* (not BASE) carrying PerStat{Dex}.

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("BallistaAgileEngineeringAS", function()
    it("LE_TREE_NODE_STAT_REWRITE registers a ba1574-18 entry", function()
        local src = readSource("Data/Global.lua")
        assert.is_truthy(string.find(src, '%["ba1574%-18"%]'),
            "Global.lua must register LE_TREE_NODE_STAT_REWRITE['ba1574-18']")
    end)

    it("the rewrite targets the Attack Speed line and produces the 'increased' form", function()
        local entry = LE_TREE_NODE_STAT_REWRITE and LE_TREE_NODE_STAT_REWRITE["ba1574-18"]
        assert.is_not_nil(entry, "LE_TREE_NODE_STAT_REWRITE['ba1574-18'] must exist at runtime")
        local raw = "+1% Attack Speed per 5 Dexterity"
        local rewritten = raw
        for _, rule in ipairs(entry) do
            rewritten = rewritten:gsub(rule.pat, rule.repl)
        end
        assert.are_equal("1% increased attack speed per 5 dexterity", rewritten,
            "the attack-speed line must rewrite to the 'increased ... per 5 dexterity' form")
        -- the placement line must NOT be altered by this entry
        local placement = "+1% Placement Speed per Dexterity"
        local placeOut = placement
        for _, rule in ipairs(entry) do placeOut = placeOut:gsub(rule.pat, rule.repl) end
        assert.are_equal(placement, placeOut, "the placement-speed line must be left untouched")
    end)

    it("the rewritten stat parses to a Speed INC (not BASE) with a PerStat Dex tag", function()
        local mods = modLib.parseMod("1% increased attack speed per 5 dexterity")
        assert.is_not_nil(mods, "rewritten stat must parse to at least one mod")
        assert.is_true(#mods >= 1, "rewritten stat must parse to a mod")
        local m = mods[1]
        assert.are_equal("Speed", m.name, "must be a Speed mod")
        assert.are_equal("INC", m.type, "must be INCREASED (not BASE) so the attack-rate formula reads it")
        local hasPerStatDex = false
        for _, t in ipairs(m) do
            if t.type == "PerStat" and t.stat == "Dex" then hasPerStatDex = true end
        end
        assert.is_true(hasPerStatDex, "must carry a PerStat{stat=Dex} tag (scales per Dexterity; Guile via twin-add)")
    end)

    it("the raw (un-rewritten) stat would parse to BASE — documents the bug", function()
        local mods = modLib.parseMod("+1% Attack Speed per 5 Dexterity")
        assert.is_not_nil(mods)
        assert.are_equal("Speed", mods[1].name)
        assert.are_equal("BASE", mods[1].type,
            "sanity: the un-rewritten form parses to BASE, which the attack-rate formula drops")
    end)
end)
