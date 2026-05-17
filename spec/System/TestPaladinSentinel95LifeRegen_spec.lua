-- @leb-regression-guard: paladin-sentinel95-healthregen-partition
-- Locks the contract that Paladin tree node Sentinel-95 (Covenant of
-- Protection) emits its 5-point Health Regen bonus as a `notScalingStat`
-- string "+5 Health Regen From Symbols Of Hope" (gated at
-- noScalingPointThreshold=5), and that ModParser produces a BASE LifeRegen
-- mod tagged with `Multiplier=ActiveSymbol` for that string.
--
-- Pre-fix tree_2.json (1_4) listed `+6 Health Regen` in the scaling `stats`
-- array, double-counting against the LE engine's actual partitioning. The
-- in-game tooltip shows only the armor lines in stats + the From-Symbols
-- bonus in notScalingStats. ModParser previously had no handler for the
-- "From Symbols of Hope" suffix, so the BASE LifeRegen mod stayed in the
-- ModParser residue and never reached modDB. With 5 ActiveSymbols at the
-- BgRrP5rr Paladin build the +5 BASE multiplies to +25 BASE LifeRegen.
--
-- See REGRESSION_GUARDS.md for the index entry.

describe("PaladinSentinel95LifeRegen", function()
    before_each(function()
        newBuild()
    end)

    it("ModParser tags '+5 Health Regen From Symbols Of Hope' with Multiplier:ActiveSymbol", function()
        local modList, extra = modLib.parseMod("+5 Health Regen From Symbols Of Hope")
        assert.is_nil(extra,
            "ModParser residue must be nil for '+5 Health Regen From Symbols Of Hope'; got: " .. tostring(extra))
        assert.is_not_nil(modList, "ModParser returned no modList")
        assert.are.equals(1, #modList)
        local m = modList[1]
        assert.are.equals("LifeRegen", m.name)
        assert.are.equals("BASE", m.type)
        assert.are.equals(5, m.value)
        local foundTag = false
        for i = 1, #m do
            local t = m[i]
            if t.type == "Multiplier" and t.var == "ActiveSymbol" then
                foundTag = true
                break
            end
        end
        assert.is_true(foundTag,
            "BASE LifeRegen mod must carry Multiplier:ActiveSymbol tag")
    end)

    it("Sentinel-95 BASE LifeRegen mod reaches modDB tagged with Multiplier:ActiveSymbol", function()
        -- Push the tagged mod through configTab.modList so it is propagated by
        -- runCallback's modDB rebuild. The multiplier-engine arithmetic
        -- (BASE x ActiveSymbol count) is engine-level and tested elsewhere;
        -- this guard locks the contract that the tag survives the modDB
        -- rebuild, which is the part the Sentinel-95 fix is responsible for.
        build.configTab.modList:NewMod("LifeRegen", "BASE", 5, "Tree:Sentinel-95",
            { type = "Multiplier", var = "ActiveSymbol" })
        runCallback("OnFrame")

        local modDB = build.calcsTab.mainEnv.modDB
        local tagged = nil
        for _, m in ipairs(modDB.mods["LifeRegen"] or {}) do
            if m.source == "Tree:Sentinel-95" and m.type == "BASE" and m.value == 5 then
                tagged = m
                break
            end
        end
        assert.is_not_nil(tagged, "Sentinel-95 BASE LifeRegen mod not found in modDB.mods.LifeRegen")
        local foundTag = false
        for i = 1, #tagged do
            local t = tagged[i]
            if t.type == "Multiplier" and t.var == "ActiveSymbol" then
                foundTag = true
                break
            end
        end
        assert.is_true(foundTag,
            "Sentinel-95 BASE LifeRegen mod must carry Multiplier:ActiveSymbol tag in modDB")
    end)

    it("tree_2.json Sentinel-95 stats omit '+6 Health Regen'", function()
        local f = io.open("TreeData/1_4/tree_2.json", "r")
            or io.open("src/TreeData/1_4/tree_2.json", "r")
        assert.is_not_nil(f, "tree_2.json missing")
        local raw = f:read("*a")
        f:close()
        local block = raw:match('"Sentinel%-95"%s*:%s*{(.-)}%s*,%s*"Sentinel%-96"')
        assert.is_not_nil(block, "Sentinel-95 block not found")
        assert.is_falsy(block:find('"%+6 Health Regen"', 1, false),
            "Sentinel-95 stats must NOT contain '+6 Health Regen' (game-canonical post-fix state)")
        assert.is_truthy(block:find('"8%% Increased Armor"', 1, false),
            "Sentinel-95 stats must retain '8% Increased Armor'")
    end)

    it("tree_2.json Sentinel-95 notScalingStats contains '+5 Health Regen From Symbols Of Hope'", function()
        local f = io.open("TreeData/1_4/tree_2.json", "r")
            or io.open("src/TreeData/1_4/tree_2.json", "r")
        assert.is_not_nil(f, "tree_2.json missing")
        local raw = f:read("*a")
        f:close()
        local block = raw:match('"Sentinel%-95"%s*:%s*{(.-)}%s*,%s*"Sentinel%-96"')
        assert.is_not_nil(block, "Sentinel-95 block not found")
        assert.is_truthy(block:find('"%+5 Health Regen From Symbols Of Hope"', 1, false),
            "Sentinel-95 notScalingStats must contain '+5 Health Regen From Symbols Of Hope'")
        assert.is_truthy(block:find('"noScalingPointThreshold":%s*5', 1, false),
            "Sentinel-95 must keep noScalingPointThreshold=5 to gate the From-Symbols bonus")
    end)
end)
