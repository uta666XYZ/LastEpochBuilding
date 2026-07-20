-- @leb-regression-guard: symbols-of-hope-innate-flat-per-symbol
-- @leb-regression-guard: symbols-empowering-inc-per-symbol
-- See REGRESSION_GUARDS.md for the index entries.
-- Validation provenance is retained in maintainer notes.

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("SigilsInnateFlatEmpoweringInc", function()

    describe("Empowering Symbols rewrite (si4lgl-32)", function()
        it("LE_TREE_NODE_STAT_REWRITE registers a si4lgl-32 entry", function()
            local src = readSource("Data/Global.lua")
            assert.is_truthy(string.find(src, '%["si4lgl%-32"%]'),
                "Global.lua must register LE_TREE_NODE_STAT_REWRITE['si4lgl-32']")
        end)

        it("rewrites the per-point line to the 'increased' form", function()
            local entry = LE_TREE_NODE_STAT_REWRITE and LE_TREE_NODE_STAT_REWRITE["si4lgl-32"]
            assert.is_not_nil(entry, "LE_TREE_NODE_STAT_REWRITE['si4lgl-32'] must exist at runtime")
            local raw = "+5% Damage Granted Per Active Symbol"
            local rewritten = raw
            for _, rule in ipairs(entry) do
                rewritten = rewritten:gsub(rule.pat, rule.repl)
            end
            assert.are_equal("5% increased damage per active symbol", rewritten)
        end)

        it("the rewritten stat parses residue-free to Damage INC x Multiplier:ActiveSymbol", function()
            local mods, extra = modLib.parseMod("5% increased damage per active symbol")
            assert.is_not_nil(mods, "rewritten stat must parse")
            assert.is_true(extra == nil or extra:match("^%s*$") ~= nil,
                "rewritten stat must leave NO parse residue (residue -> ProcessStats drop)")
            local m = mods[1]
            assert.are_equal("Damage", m.name)
            assert.are_equal("INC", m.type,
                "the value belongs in the INCREASED pool")
            assert.are_equal(5, m.value)
            local hasSymbolTag = false
            for _, t in ipairs(m) do
                if t.type == "Multiplier" and t.var == "ActiveSymbol" then hasSymbolTag = true end
            end
            assert.is_true(hasSymbolTag, "must scale per active symbol")
        end)

        it("the raw (un-rewritten) stat parses with residue — documents the drop", function()
            local mods, extra = modLib.parseMod("+5% Damage Granted Per Active Symbol")
            assert.is_not_nil(mods)
            assert.is_truthy(extra and extra:match("%S"),
                "sanity: the raw form leaves residue ('Granted'), which ProcessStats drops whole")
        end)
    end)

    describe("innate per-symbol flat (CalcSetup sigils block)", function()
        it("CalcSetup emits the innate FireDamage rows next to the sigils LifeRegen block", function()
            local src = readSource("Modules/CalcSetup.lua")
            assert.is_truthy(string.find(src, "symbols%-of%-hope%-innate%-flat%-per%-symbol"),
                "CalcSetup must carry the innate-flat guard block")
            assert.is_truthy(string.find(src, 'NewMod%("FireDamage", "BASE", 3, "Symbols of Hope", 0, kw'),
                "innate rows must be FireDamage BASE 3 with keyword scoping")
        end)

        it("keyword scoping applies the innate exactly once per attack and once per spell", function()
            local db = new("ModDB")
            db:NewMod("Multiplier:ActiveSymbol", "BASE", 4, "Test")
            for _, kw in ipairs({ KeywordFlag.Melee, KeywordFlag.Spell }) do
                db:NewMod("FireDamage", "BASE", 3, "Symbols of Hope", 0, kw,
                    { type = "Multiplier", var = "ActiveSymbol" })
            end
            -- attack cfg: LEB attacks carry ALL of Melee|Throwing|Bow (SkillType.Attack
            -- collapse; probe: Multistrike kw=8392193). Must match the Melee row exactly
            -- once => 3 x 4 symbols = 12, NOT 36.
            local attackCfg = { flags = 0, keywordFlags = bit.bor(KeywordFlag.Melee, KeywordFlag.Throwing, KeywordFlag.Bow, KeywordFlag.Hit) }
            assert.are_equal(12, db:Sum("BASE", attackCfg, "FireDamage"),
                "attack skills must gain +3/symbol exactly once (12 at 4 symbols)")
            -- spell cfg (probe: Smite/DO kw=8388864 = Hit|Spell)
            local spellCfg = { flags = 0, keywordFlags = bit.bor(KeywordFlag.Spell, KeywordFlag.Hit) }
            assert.are_equal(12, db:Sum("BASE", spellCfg, "FireDamage"),
                "spell skills must gain +3/symbol (12 at 4 symbols)")
        end)

        it("four per-type keyword rows WOULD triple-apply on attacks — documents the scoping choice", function()
            local db = new("ModDB")
            db:NewMod("Multiplier:ActiveSymbol", "BASE", 4, "Test")
            for _, kw in ipairs({ KeywordFlag.Melee, KeywordFlag.Spell, KeywordFlag.Throwing, KeywordFlag.Bow }) do
                db:NewMod("FireDamage", "BASE", 3, "Symbols of Hope", 0, kw,
                    { type = "Multiplier", var = "ActiveSymbol" })
            end
            local attackCfg = { flags = 0, keywordFlags = bit.bor(KeywordFlag.Melee, KeywordFlag.Throwing, KeywordFlag.Bow, KeywordFlag.Hit) }
            assert.are_equal(36, db:Sum("BASE", attackCfg, "FireDamage"),
                "sanity: per-type rows over-apply under the attack-keyword collapse (why we use 2 rows)")
        end)
    end)
end)
