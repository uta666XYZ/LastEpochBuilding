-- @leb-regression-guard:near-enemy-proximity-suffix-eat
-- Locks the parser handling of the "against enemies within (N) metres"
-- proximity suffix against silent-drop regressions on Bastion of Honour
-- Old Kite Shield (uniqueID 198):
--
--   The shield's intrinsic
--     "+1% Block Chance per Strength against enemies within 4 metres"
--   parses modName="BlockChance" + per-Stat tag from "per Strength", but
--   "against enemies within 4 metres" was left as non-empty `extra` residue.
--   PassiveTree.lua and friends drop any mod with non-empty extra
--   (`if mod.list and not mod.extra`), so on a Str=125 build the entire
--   125% BlockChance contribution silently vanished.
--
--   LETools always counts this bonus (it does not gate on proximity), so the
--   fix is a modTagList noise-eater that consumes the suffix without
--   attaching a Condition tag. Pattern uses (%d+) so future "within N metres"
--   rerolls share the same handler.
--
-- Evidence (Δ = LEB - LETools, pre-fix):
--   - Qqwvdex2 lv98 Beastmaster (Str=125): LET BC=139, LEB BC=14, Δ=-125 (89.9%)
--   - om6xa9dY lv100 Void Knight: LET BC=126, LEB BC=55, Δ=-71 (56.3%)

local parseMod, parserCache

local function parseFresh(line)
    if not parseMod then
        parseMod, parserCache = LoadModule("Modules/ModParser")
    end
    parserCache[line] = nil
    return parseMod(line)
end

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("NearEnemyProximitySuffixEat", function()
    local modParserText

    setup(function()
        modParserText = readSource("Modules/ModParser.lua")
    end)

    it("ModParser carries the @leb-regression-guard:near-enemy-proximity-suffix-eat marker", function()
        assert.is_truthy(string.find(modParserText,
            "@leb-regression-guard:near-enemy-proximity-suffix-eat", 1, true),
            "ModParser proximity-suffix hook must carry the named guard marker")
    end)

    it("ModParser registers the 'against enemies within (N) metres' modTagList entry", function()
        assert.is_truthy(string.find(modParserText,
            '%["against enemies within %(%%d%+%) metres"%]', 1, false),
            "Parser must hook the proximity-suffix pattern in modTagList")
    end)

    it("emits BlockChance BASE with PerStat:Str and NO extra residue for the Bastion line", function()
        local mods, extra = parseFresh("+1% Block Chance per Strength against enemies within 4 metres")
        assert.is_truthy(mods)
        assert.are.equal(1, #mods)
        assert.is_nil(extra, "extra residue must be nil so item-mod consumers keep the mod")
        local m = mods[1]
        assert.are.equal("BlockChance", m.name)
        assert.are.equal("BASE", m.type)
        assert.are.equal(1, m.value)
        local foundPerStr = false
        for _, tag in ipairs(m) do
            if tag.type == "PerStat" and tag.stat == "Str" then foundPerStr = true end
        end
        assert.is_true(foundPerStr, "must carry PerStat:Str tag so BC scales with Strength")
    end)

    it("does NOT attach Condition:NearEnemy (LETools-parity, always-on)", function()
        -- We chose noise-eat over Condition-tag so the bonus matches LETools
        -- display regardless of conditionNearEnemy config. Locking this
        -- decision so a well-meaning refactor doesn't silently re-gate it.
        local mods = parseFresh("+1% Block Chance per Strength against enemies within 4 metres")
        for _, m in ipairs(mods) do
            for _, tag in ipairs(m) do
                assert.is_false(tag.type == "Condition" and tag.var == "NearEnemy",
                    "must not gate this mod behind Condition:NearEnemy")
            end
        end
    end)

    it("handles any (%d+) reroll, not just '4 metres'", function()
        for _, n in ipairs({1, 3, 6, 8, 12}) do
            local line = "+1% Block Chance per Strength against enemies within " .. n .. " metres"
            local mods, extra = parseFresh(line)
            assert.is_truthy(mods, line .. " must parse")
            assert.is_nil(extra, line .. " must leave nil extra")
            assert.are.equal(1, #mods, line .. " must emit 1 mod")
        end
    end)

    it("ModCache no longer pins the stale BlockChance entry with residue", function()
        -- The pre-fix parse pinned the stale entry into ModCache.lua. If left
        -- in place the cache short-circuits the new modTagList handler,
        -- re-introducing the silent-drop bug.
        local modCacheText = readSource("Data/ModCache.lua")
        assert.is_nil(string.find(modCacheText,
            '"+1% Block Chance per Strength against enemies within 4 metres"', 1, true),
            "Stale ModCache entry must be purged so re-parse picks up the new noise-eater")
    end)
end)
