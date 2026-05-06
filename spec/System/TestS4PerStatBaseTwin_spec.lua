-- @leb-regression-guard: s4-perstat-base-includes-converted-twin
-- Locks the contract that text-parsed "Per <BaseAttr>" mods (passive
-- nodes / item affixes) sum the converted twin (Brutality for Strength,
-- Guile for Dexterity, Madness for Intelligence, Apathy for Attunement,
-- Rampancy for Vitality) at evaluation time, while the seven intrinsic
-- character bonuses registered in calcs.initEnv (+4% Armour PerStat:Str,
-- +4 Evasion PerStat:Dex, +2 WardRetention PerStat:Int, +2 Mana
-- PerStat:Att, +6 Life PerStat:Vit, +1 PoisonResist PerStat:Vit, +1
-- NecroticResist PerStat:Vit) reference Raw<Attr> so they do NOT pick
-- up the converted twin (sibling guard s4-converted-attr-no-base-inherit
-- forbids Brutality from inheriting Strength's +4% Armour).
--
-- Establishing build: Qb6WlbxD lv100 Druid (Brutality=198 via Exulis
-- 100% Str→Brutality conversion). The Druid passive node Primalist-111
-- "Aspects of Might" grants "1% Increased Armor Per Strength In Human
-- Or Spriggan" — LE counts Brutality, giving +198% INC; LEB previously
-- read PerStat:Str only and gave +0% (Str=0 after conversion). Fix
-- closes the Armour gap from LEB 1320 / LE 3161 to LEB 3110 / LE 3161
-- (residual ≈ 1.6%).
--
-- See REGRESSION_GUARDS.md "s4-perstat-base-includes-converted-twin".

describe("S4PerStatBaseIncludesConvertedTwin", function()

    describe("ModStore EvalMod sums converted twin for PerStat:<BaseAttr>", function()
        local source
        setup(function()
            local f = io.open("Classes/ModStore.lua", "r")
            assert.is_not_nil(f, "must be able to open Classes/ModStore.lua")
            source = f:read("*a")
            f:close()
        end)

        it("declares the s4ConvertedTwin lookup table", function()
            assert.is_truthy(string.find(source, "s4ConvertedTwin", 1, true),
                "ModStore.lua must declare the s4ConvertedTwin table at module scope")
        end)

        local pairs_ = {
            { base = "Str", twin = "Brutality" },
            { base = "Dex", twin = "Guile" },
            { base = "Int", twin = "Madness" },
            { base = "Att", twin = "Apathy" },
            { base = "Vit", twin = "Rampancy" },
        }
        for _, p in ipairs(pairs_) do
            it(("s4ConvertedTwin maps %s → %s"):format(p.base, p.twin), function()
                local pat = p.base .. '%s*=%s*"' .. p.twin .. '"'
                assert.is_truthy(string.find(source, pat),
                    ("ModStore.lua s4ConvertedTwin must map %s to %s"):format(p.base, p.twin))
            end)
        end

        it("EvalMod PerStat block calls into s4ConvertedTwin[tag.stat]", function()
            assert.is_truthy(string.find(source, "s4ConvertedTwin%[tag%.stat%]"),
                "ModStore.EvalMod PerStat scalar branch must look up s4ConvertedTwin[tag.stat]")
        end)

        it("EvalMod PerStat statList branch also sums the twin", function()
            assert.is_truthy(string.find(source, "s4ConvertedTwin%[stat%]"),
                "ModStore.EvalMod PerStat statList branch must look up s4ConvertedTwin[stat]")
        end)

        it("regression-guard comment block is present", function()
            assert.is_truthy(string.find(source, "s4-perstat-base-includes-converted-twin", 1, true),
                "ModStore.lua must keep the @leb-regression-guard comment so future edits trip review")
        end)
    end)

    describe("CalcSetup intrinsic bonuses reference Raw<Attr>", function()
        local source
        setup(function()
            local f = io.open("Modules/CalcSetup.lua", "r")
            assert.is_not_nil(f, "must be able to open Modules/CalcSetup.lua")
            source = f:read("*a")
            f:close()
        end)

        local intrinsics = {
            { target = "Armour",         attr = "Strength",     raw = "RawStr" },
            { target = "Evasion",        attr = "Dexterity",    raw = "RawDex" },
            { target = "WardRetention",  attr = "Intelligence", raw = "RawInt" },
            { target = "Mana",           attr = "Attunement",   raw = "RawAtt" },
            { target = "Life",           attr = "Vitality",     raw = "RawVit" },
            { target = "PoisonResist",   attr = "Vitality",     raw = "RawVit" },
            { target = "NecroticResist", attr = "Vitality",     raw = "RawVit" },
        }
        for _, c in ipairs(intrinsics) do
            it(("%s intrinsic from %s uses PerStat:%s"):format(c.target, c.attr, c.raw), function()
                local pat = 'NewMod%(%s*"' .. c.target .. '".-"' .. c.attr .. '".-PerStat.-stat%s*=%s*"' .. c.raw .. '"'
                assert.is_truthy(string.find(source, pat),
                    ("CalcSetup.lua %s intrinsic must reference PerStat:%s (not the live %s/converted twin)"):format(
                        c.target, c.raw, c.attr))
            end)
        end
    end)

    describe("CalcPerform mirrors live attributes onto Raw<Attr> after conversion", function()
        local source
        setup(function()
            local f = io.open("Modules/CalcPerform.lua", "r")
            assert.is_not_nil(f, "must be able to open Modules/CalcPerform.lua")
            source = f:read("*a")
            f:close()
        end)

        for _, raw in ipairs({ "RawStr", "RawDex", "RawInt", "RawAtt", "RawVit" }) do
            it("publishes output." .. raw, function()
                local pat = "output%." .. raw .. "%s*=%s*output%."
                assert.is_truthy(string.find(source, pat),
                    "CalcPerform.lua must mirror output." .. raw .. " from the post-conversion live attribute")
            end)
        end
    end)

    describe("ModCache entries for Druid OR-form conditionals carry the Condition tag", function()
        local cache
        setup(function()
            -- ModCache.lua is loaded via LoadModule("Data/ModCache", modLib.parseModCache)
            -- which populates modLib.parseModCache with `local c = ...`.
            cache = modLib.parseModCache
            assert.is_not_nil(cache, "modLib.parseModCache must be populated by HeadlessWrapper")
        end)

        it("'1% Increased Armor Per Strength In Human Or Spriggan' parses with PerStat:Str + Form NAND", function()
            local entry = cache["1% Increased Armor Per Strength In Human Or Spriggan"]
            assert.is_not_nil(entry, "ModCache must contain the Aspects of Might Armour entry")
            local mods, extra = entry[1], entry[2]
            assert.is_nil(extra, "entry must have no unparsed leftover (otherwise PassiveTree drops the mod)")
            assert.is_not_nil(mods, "entry must carry a parsed mods list")
            local m = mods[1]
            assert.are.equals("Armour", m.name)
            assert.are.equals("INC", m.type)
            -- Expect tag[1]=PerStat:Str, tag[2]=Condition with form-NAND
            assert.are.equals("PerStat", m[1].type)
            assert.are.equals("Str", m[1].stat)
            assert.are.equals("Condition", m[2].type)
            assert.is_truthy(m[2].neg, "human-or-spriggan must be encoded as NAND on the other forms")
            assert.is_table(m[2].varList)
        end)

        it("'1% Increased Melee Damage Per Strength In Bear Or Swarmblade' parses with PerStat:Str + form OR", function()
            local entry = cache["1% Increased Melee Damage Per Strength In Bear Or Swarmblade"]
            assert.is_not_nil(entry, "ModCache must contain the Aspects of Might Melee Damage entry")
            local mods, extra = entry[1], entry[2]
            assert.is_nil(extra, "entry must have no unparsed leftover")
            local m = mods[1]
            assert.are.equals("Damage", m.name)
            assert.are.equals("INC", m.type)
            assert.are.equals("PerStat", m[1].type)
            assert.are.equals("Str", m[1].stat)
            assert.are.equals("Condition", m[2].type)
            assert.is_table(m[2].varList)
            -- This direction is OR (positive), not NAND
            assert.is_falsy(m[2].neg, "bear-or-swarmblade must NOT be negated")
        end)
    end)
end)
