-- @leb-regression-guard:pierce-chance-to-crit-multiplier
-- Locks the Pierce Chance ledger + the Shurikens "Ricochet" (srk21-19)
-- conversion "Pierce chance is converted to additional critical strike
-- multiplier". Sheet-verified on StarSeaVnV (2026-06-10): in-game carried
-- critMult 757 = sheet Throwing 582 + Massacre 75 + pierce 100 (Ethereal
-- Blades srk21-27 x4 = +25%/pt) EXACT. The conversion is an EXACT-pair
-- branch in parseArrowConversion on purpose: a generic "X -> Y" stat rule
-- is how the #3-B "Additional <skill> Chance" misparse class happens.
-- See REGRESSION_GUARDS.md "pierce-chance-to-crit-multiplier".

describe("PierceChanceToCritMultiplier parser", function()
    it("'+25% Pierce Chance' parses to PierceChance BASE 25 with no residue", function()
        local mods, extra = modLib.parseMod("+25% Pierce Chance")
        assert.is_nil(extra)
        assert.is_not_nil(mods)
        assert.are.equals(1, #mods)
        assert.are.equals("PierceChance", mods[1].name)
        assert.are.equals("BASE", mods[1].type)
        assert.are.equals(25, mods[1].value)
        assert.is_falsy(mods.notSupported)
    end)

    it("'+50% Pierce Chance' scales the value", function()
        local mods, extra = modLib.parseMod("+50% Pierce Chance")
        assert.is_nil(extra)
        assert.are.equals(50, mods[1].value)
    end)

    it("' Pierce Chance -> Critical Multiplier' (Ricochet notScalingStat) parses to the conversion flag", function()
        local mods, extra = modLib.parseMod(" Pierce Chance -> Critical Multiplier")
        assert.is_nil(extra)
        assert.is_not_nil(mods)
        assert.are.equals(1, #mods)
        assert.are.equals("PierceChanceConvertsToCritMultiplier", mods[1].name)
        assert.are.equals("FLAG", mods[1].type)
    end)

    it("the conversion is an exact pair, not a generic stat->stat rule", function()
        -- a non-increased flat pair that is NOT pierce->critmulti must not
        -- produce a conversion (falls through to residue, like before)
        local mods, extra = modLib.parseMod(" Dodge Rating -> Critical Multiplier")
        local gotFlag = false
        for _, m in ipairs(mods or {}) do
            if (m.name or ""):find("ConvertsToCritMultiplier") then gotFlag = true end
        end
        assert.is_false(gotFlag, "only 'pierce chance -> critical multiplier' may emit the flag")
    end)
end)

describe("PierceChanceToCritMultiplier ModCache", function()
    it("no stale EMPTY-parse rows short-circuit the new parser", function()
        -- Match the empty-parse FORM (`={{}`), not bare key absence: a healthy
        -- wholesale re-bake (REGENERATE_MOD_CACHE) re-adds these keys with the
        -- CORRECT parse, which must not trip this guard.
        local f = assert(io.open("Data/ModCache.lua", "r"))
        local body = f:read("*a"); f:close()
        assert.is_nil(body:find('c["+25% Pierce Chance"]={{}', 1, true),
            "stale empty '+25%% Pierce Chance' row would re-mask the PierceChance ledger")
        assert.is_nil(body:find('c["+50% Pierce Chance"]={{}', 1, true),
            "stale empty '+50%% Pierce Chance' row would re-mask the PierceChance ledger")
        assert.is_nil(body:find('c[" Pierce Chance -> Critical Multiplier"]={{}', 1, true),
            "stale empty conversion row would re-mask the Ricochet conversion")
        assert.is_nil(body:find('Pierce Chance with Fireball"]={{}', 1, true),
            "stale empty skill-scoped pierce rows would re-mask the ledger for future conversions")
    end)
end)

describe("PierceChanceToCritMultiplier consumption (CalcOffence)", function()
    it("CalcOffence adds the PierceChance sum into the crit-multi extra behind the flag", function()
        local f = assert(io.open("Modules/CalcOffence.lua", "r"))
        local text = f:read("*a"); f:close()
        assert.is_truthy(text:find("@leb%-regression%-guard:pierce%-chance%-to%-crit%-multiplier"),
            "inline guard marker must be present in CalcOffence")
        assert.is_truthy(text:find('skillModList:Flag(cfg, "PierceChanceConvertsToCritMultiplier")', 1, true),
            "consumption must be gated on the conversion flag")
        assert.is_truthy(text:find('playerExtra = playerExtra + skillModList:Sum("BASE", cfg, "PierceChance")', 1, true),
            "the PierceChance sum must join the additive crit-multi pool")
    end)
end)

describe("PierceChanceToCritMultiplier end-to-end (StarSeaVnV)", function()
    it("Shurikens crit multiplier reaches the in-game sheet value 7.57", function()
        local fh = io.open("../spec/TestBuilds/StarSeaVnV_LEB.xml", "r")
        if not fh then pending("StarSeaVnV_LEB.xml not present (spec/TestBuilds is gitignored)"); return end
        local xml = fh:read("*a"); fh:close()
        loadBuildFromXML(xml)
        local grp
        for i, g in ipairs(build.skillsTab.socketGroupList) do
            if not g.triggeredOnHit and not g.triggeredByTimer then
                for _, sk in ipairs(g.displaySkillList or {}) do
                    local nm = sk.activeEffect and sk.activeEffect.grantedEffect and sk.activeEffect.grantedEffect.name
                    if nm == "Shurikens" then grp = grp or i end
                end
            end
        end
        assert.is_not_nil(grp)
        build.mainSocketGroup = grp
        build.calcsTab.input.skill_number = grp
        build.buildFlag = false
        build.calcsTab:BuildOutput()
        local out = build.calcsTab.calcsEnv.player.output
        local ms = build.calcsTab.calcsEnv.player.mainSkill
        assert.are.equals(100, ms.skillModList:Sum("BASE", ms.skillCfg, "PierceChance"),
            "Ethereal Blades x4 must sum to 100% pierce chance")
        -- 757% = 200 base + 448 gear/tree + 9 Wings-doubled idol multi + 100 pierce
        assert.is_true(math.abs(out.CritMultiplier - 7.57) < 1e-9,
            "in-game carried critMult 757 (sheet 582 + Massacre 75 + pierce 100)")
    end)
end)
