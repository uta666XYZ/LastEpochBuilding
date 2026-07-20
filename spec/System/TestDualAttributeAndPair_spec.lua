-- @leb-regression-guard: dual-attribute-and-pair
-- Locks the parser handling of the "+N <Attr1> and <Attr2>" dual-attribute
-- mod form (Jormun's Hunger "+(6-10) Strength and Dexterity" being the
-- canonical case) against silent-drop regressions on BOwJRDdE lv74 Shaman:
--
--   Before fix the line matched the generic numberedlistAttribute chain:
--   modNameList caught "Strength", value 9 was applied, but " and Dexterity"
--   was left as non-empty `extra` residue. Item-mod consumers
--   (PassiveTree.lua and friends) drop any mod with non-empty extra
--   (`if mod.list and not mod.extra`), so the BOTH Strength AND Dexterity
--   contributions were silently lost.
--
--   The new specialModList entry emits two BASE mods (one per attribute)
--   so consumers keep the full mod, validating both captures against
--   LongAttributes so unrelated lines (e.g. "+9 Foo and Bar") decline and
--   fall through to the generic parse chain.
--
-- Evidence (BOwJRDdE lv74 Shaman, Jormun's Hunger byte=127.5 → +9/+9):
--   - LETools: Str=42, Dex=17
--   - LEB (pre-fix): Str=33, Dex=8   (Δ=-9/-9, exactly the dropped mod)
--
-- Dispatch convention reminder: specialMod(tonumber(cap[1]), unpack(cap))
-- so a 3-capture handler receives (num, cap1str, cap2str, cap3str). The
-- attribute captures live at args 3 and 4, not 2 and 3.

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

describe("DualAttributeAndPair", function()
    local modParserText

    setup(function()
        modParserText = readSource("Modules/ModParser.lua")
    end)

    it("ModParser carries the @leb-regression-guard:dual-attribute-and-pair marker", function()
        assert.is_truthy(string.find(modParserText,
            "@leb-regression-guard:dual-attribute-and-pair", 1, true),
            "ModParser dual-attribute hook must carry the named guard marker")
    end)

    it("ModParser registers the '+N <Attr> and <Attr>' specialModList pattern", function()
        assert.is_truthy(string.find(modParserText,
            'specialModList%["%^%%%+%?%(%[%%d%%.%]%+%) %(%%a%+%) and %(%%a%+%)%$"%]', 1, false),
            "Parser must hook the dual-attribute pattern in specialModList")
    end)

    it("emits two BASE mods (Str + Dex) with no extra residue for '+9 Strength and Dexterity'", function()
        local mods, extra = parseFresh("+9 Strength and Dexterity")
        assert.is_truthy(mods)
        assert.are.equal(2, #mods)
        assert.is_nil(extra, "extra residue must be nil so item-mod consumers keep the mod")
        local byName = {}
        for _, m in ipairs(mods) do byName[m.name] = m end
        assert.is_truthy(byName.Str, "must emit a Str BASE mod")
        assert.is_truthy(byName.Dex, "must emit a Dex BASE mod")
        assert.are.equal("BASE", byName.Str.type)
        assert.are.equal("BASE", byName.Dex.type)
        assert.are.equal(9, byName.Str.value)
        assert.are.equal(9, byName.Dex.value)
    end)

    it("handles float values produced by applyRange precision=100 (e.g. '+8.0 Strength and Dexterity')", function()
        -- applyRange defaults to precision=100 for "+(N-M) <text>" without a
        -- 'to' keyword, so byte=127.5 on Jormun's "+(6-10) Strength and
        -- Dexterity" renders as "+8.0 ..." not "+8 ...". The parser must
        -- accept the decimal form too.
        local mods, extra = parseFresh("+8.0 Strength and Dexterity")
        assert.is_truthy(mods)
        assert.are.equal(2, #mods)
        assert.is_nil(extra)
        local byName = {}
        for _, m in ipairs(mods) do byName[m.name] = m end
        assert.are.equal(8, byName.Str.value)
        assert.are.equal(8, byName.Dex.value)
    end)

    it("handles all 10 ordered pairs of the 5 attributes (Vit/Str/Dex/Int/Att)", function()
        local pairs10 = {
            {"Vitality", "Strength", "Vit", "Str"},
            {"Vitality", "Dexterity", "Vit", "Dex"},
            {"Vitality", "Intelligence", "Vit", "Int"},
            {"Vitality", "Attunement", "Vit", "Att"},
            {"Strength", "Dexterity", "Str", "Dex"},
            {"Strength", "Intelligence", "Str", "Int"},
            {"Strength", "Attunement", "Str", "Att"},
            {"Dexterity", "Intelligence", "Dex", "Int"},
            {"Dexterity", "Attunement", "Dex", "Att"},
            {"Intelligence", "Attunement", "Int", "Att"},
        }
        for _, p in ipairs(pairs10) do
            local line = "+5 " .. p[1] .. " and " .. p[2]
            local mods = parseFresh(line)
            assert.is_truthy(mods, line .. " must parse")
            assert.are.equal(2, #mods, line .. " must emit 2 mods")
            local names = {}
            for _, m in ipairs(mods) do names[m.name] = true end
            assert.is_truthy(names[p[3]], line .. " must include " .. p[3])
            assert.is_truthy(names[p[4]], line .. " must include " .. p[4])
        end
    end)

    it("declines (falls through) for non-attribute pairs like '+9 Foo and Bar'", function()
        -- The handler must return nil for pairs where either word is not a
        -- LongAttribute so unrelated lines fall through to the generic
        -- modNameList chain instead of being miscategorised.
        local mods, extra = parseFresh("+9 Foo and Bar")
        -- Generic chain will fail to match — exact return shape isn't what
        -- we lock; what we lock is that our handler doesn't catch it.
        -- An accepted handler would produce {Str/Dex,...} which is what we
        -- guard against by asserting neither attribute appears.
        if type(mods) == "table" then
            for _, m in ipairs(mods) do
                assert.is_nil(m.name == "Str" or nil, "must not emit Str for non-attribute pair")
                assert.is_nil(m.name == "Dex" or nil, "must not emit Dex for non-attribute pair")
            end
        end
    end)

    it("ModCache no longer pins the stale single-Str '+8 Strength and Dexterity' entry", function()
        -- The pre-fix parse produced `{Str BASE 8}` + extra="  and Dexterity "
        -- which got pinned into ModCache.lua. If left in place the cache
        -- short-circuits the new specialModList handler, re-introducing
        -- the silent-drop bug.
        local modCacheText = readSource("Data/ModCache.lua")
        assert.is_nil(string.find(modCacheText,
            '"+8 Strength and Dexterity"', 1, true),
            "Stale ModCache entry must be purged so re-parse picks up the new dual-attribute handler")
    end)

    it("declines for same-attribute pairs (e.g. '+9 Strength and Strength')", function()
        -- Defensive: the handler requires m1 ~= m2 so a malformed dup line
        -- doesn't double-credit the same attribute.
        local mods = parseFresh("+9 Strength and Strength")
        -- Either nil or generic-chain match — but our handler must not
        -- have emitted two Str mods.
        if type(mods) == "table" and #mods == 2 then
            assert.is_false(mods[1].name == "Str" and mods[2].name == "Str",
                "must not emit duplicate Str mods for same-attribute pair")
        end
    end)
end)
