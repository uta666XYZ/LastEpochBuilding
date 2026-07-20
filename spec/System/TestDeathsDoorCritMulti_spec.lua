-- @leb-regression-guard:deaths-door-lowlife-critmult
-- See REGRESSION_GUARDS.md "deaths-door-lowlife-critmult".
-- Validation provenance is retained in maintainer notes.

describe("DeathsDoorCritMulti parser", function()
    it("'+10% Crit Multi While At Low Health' parses to CritMultiplier BASE 10 with Condition:LowLife and no residue", function()
        local mods, extra = modLib.parseMod("+10% Crit Multi While At Low Health")
        assert.is_nil(extra)
        assert.is_not_nil(mods)
        assert.are.equals(1, #mods)
        local m = mods[1]
        assert.are.equals("CritMultiplier", m.name)
        assert.are.equals("BASE", m.type)
        assert.are.equals(10, m.value)
        local foundLowLife = false
        for _, tag in ipairs(m) do
            if type(tag) == "table" and tag.type == "Condition" and tag.var == "LowLife" then
                foundLowLife = true
                break
            end
        end
        assert.is_true(foundLowLife, "the LowLife condition tag must gate the mod")
    end)

    it("'+5% Crit Multiplier' (Sentinel-86 Holy Precision) parses to CritMultiplier BASE 5 with no residue", function()
        local mods, extra = modLib.parseMod("+5% Crit Multiplier")
        assert.is_nil(extra)
        assert.is_not_nil(mods)
        assert.are.equals(1, #mods)
        assert.are.equals("CritMultiplier", mods[1].name)
        assert.are.equals("BASE", mods[1].type)
        assert.are.equals(5, mods[1].value)
    end)

    it("the canonical '+5% Critical Strike Multiplier' spelling still parses identically", function()
        local mods, extra = modLib.parseMod("+5% Critical Strike Multiplier")
        assert.is_nil(extra)
        assert.are.equals("CritMultiplier", mods[1].name)
        assert.are.equals("BASE", mods[1].type)
        assert.are.equals(5, mods[1].value)
    end)

    it("un-baked siblings with unmodeled suffixes now carry the stat but keep their residue (tree extra-gate)", function()
        -- These node texts gained the CritMultiplier stat from the alias but
        -- their suffix machinery (Tethered / per Stack / Max More) is still
        -- unmodeled: the residue stays non-empty, so PassiveTree's extra gate
        -- keeps dropping them -- same net behavior as the old empty rows,
        -- but the parse is now honest about which half is missing.
        for _, line in ipairs({
            "+18% Crit Multiplier while Tethered",
            "+2% Crit Multiplier per Stack Consumed",
            "3% Crit Multiplier per Stack",
            "20% Max More Crit Multi",
        }) do
            local mods, extra = modLib.parseMod(line)
            assert.is_not_nil(mods, line)
            assert.are.equals(1, #mods, line)
            assert.are.equals("CritMultiplier", mods[1].name, line)
            assert.is_truthy(extra, line .. " must keep its residue until the suffix is modeled")
        end
    end)
end)

describe("DeathsDoorCritMulti ModCache", function()
    it("no stale EMPTY-parse rows short-circuit the new aliases", function()
        -- Match the empty-parse FORM (`={{}`), not bare key absence: a healthy
        -- wholesale re-bake (REGENERATE_MOD_CACHE) re-adds these keys with the
        -- CORRECT parse, which must not trip this guard.
        local f = assert(io.open("Data/ModCache.lua", "r"))
        local body = f:read("*a"); f:close()
        for _, key in ipairs({
            "+10% Crit Multi While At Low Health",
            "+5% Crit Multiplier",
            "+18% Crit Multiplier while Tethered",
            "+2% Crit Multiplier per Stack Consumed",
            "3% Crit Multiplier per Stack",
            "20% Max More Crit Multi",
        }) do
            assert.is_nil(body:find('c["' .. key .. '"]={{}', 1, true),
                "stale empty '" .. key .. "' row would re-mask the stat aliases")
        end
    end)
end)

describe("DeathsDoorCritMulti config gate", function()
    it("conditionLowLife exists as a default-OFF checkbox gated on the LowLife condition", function()
        local found
        for _, opt in ipairs(LoadModule("Modules/ConfigOptions")) do
            if opt.var == "conditionLowLife" then found = opt end
        end
        assert.is_not_nil(found, "conditionLowLife config option must exist")
        assert.are.equals("check", found.type)
        assert.are.equals("LowLife", found.ifCond)
        assert.is_falsy(found.defaultState, "the LowLife condition must default OFF")
    end)
end)

describe("DeathsDoorCritMulti end-to-end", function()
    before_each(function()
        newBuild()
        -- CalcOffence only computes CritMultiplier for a hit skill
        -- (`not skillFlags.hit` short-circuits it to 0 on an empty build).
        build.skillsTab:SelSkill(1, "Runemaster 05c3 Runebolt Cold")
    end)

    local function critMultiplier()
        build.configTab:BuildModList()
        runCallback("OnFrame")
        return build.calcsTab.mainOutput.CritMultiplier
    end

    it("one node point: +10% rises CritMultiplier by 0.10 only with conditionLowLife ON", function()
        local base = critMultiplier()
        build.configTab.input.customMods = "+10% Crit Multi While At Low Health"
        local off = critMultiplier()
        assert.are.equals(base, off, "default config (LowLife OFF) must not move CritMultiplier")
        build.configTab.input.conditionLowLife = true
        local on = critMultiplier()
        assert.is_true(math.abs((on - off) - 0.10) < 1e-9,
            "conditionLowLife ON must add exactly +0.10 CritMultiplier")
    end)

    it("in-game olVLdj8q scenario: 8/8 Death's Door (+80) yields output.CritMultiplier +0.80 when low-life", function()
        local lines = {}
        for _ = 1, 8 do lines[#lines + 1] = "+10% Crit Multi While At Low Health" end
        build.configTab.input.customMods = table.concat(lines, "\n")
        local off = critMultiplier()
        build.configTab.input.conditionLowLife = true
        local on = critMultiplier()
        assert.is_true(math.abs((on - off) - 0.80) < 1e-9,
            "8 points x +10% must add exactly +0.80 CritMultiplier under low-life")
    end)
end)
