-- @leb-regression-guard:stormhide-empowered-swipe
-- Locks the parser + Config contract for Stormhide Paws' (uniques_1_4.json #202)
-- INTERMITTENT empowered-Swipe effect.
--
-- Ground truth (in-game tooltip == datamine tooltipDescriptions, single combined
-- stat string, 2026-06-01):
--   "Every 3 seconds your next Swipe has 100% of its base damage converted to
--    Lightning and deals +(30-45) Melee Lightning Damage"
--
-- The effect only fires on the empowered (every-3s) Swipe cast, NOT on every
-- Swipe, so it MUST be gated behind the conditionEmpoweredSwipe config
-- (Condition:EmpoweredSwipe, default OFF). With the gate OFF the average Swipe is
-- unchanged (baseline parity); with it ON the conversion + bonus Lightning apply.
--
-- LEB transcribes the single in-game stat as two synthetic strings, both ending
-- in the "(Empowered Swipe)" marker that routes to the dedicated gated handlers:
--   1. "100% of Swipe Base Damage converted to Lightning (Empowered Swipe)"
--        -> SkillName=Swipe + Condition:EmpoweredSwipe scoped
--           <srcType>DamageConvertToLightning BASE % for every non-Lightning type
--           (same CalcOffence conversionTable consumer, mult = 1 - converted).
--   2. "+(30-45) Melee Lightning Damage with Swipe (Empowered Swipe)"
--        -> LightningDamage BASE with KeywordFlag.Melee + SkillName=Swipe
--           + Condition:EmpoweredSwipe.
--
-- Critical invariants:
--   * The generic always-on skillBaseDamageConversionHandler (Acid Flask /
--     Shuriken) is UNTOUCHED -- only the "(empowered swipe)"-suffixed form gets
--     the Condition gate. A normal conversion must NOT carry the Condition tag.
--   * Both halves are Swipe-scoped (SkillName) so they never leak to other skills.
--   * Both halves are fully parsed (nil extra) -- the prior
--     "+X Melee Lightning Damage with Swipe" form left dirty residue + no gate.
--
-- Probe (synthetic minimal Swipe build, spec/tools/probe_stormhide_dps.lua):
--   Stormhide OFF -> FullDPS 4.2768, Phys->Light 0, addedLight 0 (== no-Stormhide)
--   Stormhide ON  -> FullDPS 85.536, Phys->Light 100, addedLight 38
--   No-Stormhide OFF == No-Stormhide ON (config flag with nothing to gate is a no-op)
--
-- See REGRESSION_GUARDS.md > "stormhide-empowered-swipe".

local function findTag(m, ttype)
    for _, tag in ipairs(m) do
        if tag.type == ttype then return tag end
    end
end

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("StormhideEmpoweredSwipe", function()
    before_each(function()
        newBuild()
    end)

    ---------------------------------------------------------------------------
    -- Parse-level: gated conversion
    ---------------------------------------------------------------------------
    it("conversion parses to Swipe-scoped + EmpoweredSwipe-gated base->Lightning (nil extra)", function()
        local mods, extra = modLib.parseMod("100% of Swipe Base Damage converted to Lightning (Empowered Swipe)")
        assert.is_nil(extra, "a fully-parsed Stormhide conversion must leave no residue")
        assert.is_not_nil(mods)
        -- One conversion per non-Lightning damage type (6 of the 7 DamageTypes).
        assert.are.equals(6, #mods)
        local physToLight
        for _, m in ipairs(mods) do
            if m.name == "PhysicalDamageConvertToLightning" then physToLight = m end
            assert.are_not.equals("LightningDamageConvertToLightning", m.name, "destination type must be skipped")
            assert.are.equals("BASE", m.type)
            assert.are.equals(100, m.value)
            local sk = findTag(m, "SkillName")
            assert.is_not_nil(sk, "conversion must be Swipe-scoped")
            assert.are.equals("Swipe", sk.skillName)
            local cond = findTag(m, "Condition")
            assert.is_not_nil(cond, "conversion must be gated on the empowered-Swipe condition")
            assert.are.equals("EmpoweredSwipe", cond.var)
        end
        assert.is_not_nil(physToLight, "must emit PhysicalDamageConvertToLightning")
    end)

    ---------------------------------------------------------------------------
    -- Parse-level: gated added Lightning damage
    ---------------------------------------------------------------------------
    it("added damage parses to Swipe-scoped + EmpoweredSwipe-gated Melee LightningDamage (nil extra)", function()
        local mods, extra = modLib.parseMod("+38 Melee Lightning Damage with Swipe (Empowered Swipe)")
        assert.is_nil(extra, "the added-damage form must leave no residue (the bare 'with Swipe' form did not)")
        assert.is_not_nil(mods)
        assert.are.equals(1, #mods)
        local m = mods[1]
        assert.are.equals("LightningDamage", m.name)
        assert.are.equals("BASE", m.type)
        assert.are.equals(38, m.value)
        assert.are.equals(512, m.keywordFlags, "must carry KeywordFlag.Melee (512)")
        local sk = findTag(m, "SkillName")
        assert.is_not_nil(sk, "added damage must be Swipe-scoped")
        assert.are.equals("Swipe", sk.skillName)
        local cond = findTag(m, "Condition")
        assert.is_not_nil(cond, "added damage must be gated on the empowered-Swipe condition")
        assert.are.equals("EmpoweredSwipe", cond.var)
    end)

    ---------------------------------------------------------------------------
    -- Regression: the generic always-on conversion must NOT gain a Condition gate
    ---------------------------------------------------------------------------
    it("generic skill conversion (Acid Flask) stays UNGATED (no Condition tag)", function()
        local mods = modLib.parseMod("100% of Acid Flask Base Damage converted to Cold")
        assert.are.equals(6, #mods)
        for _, m in ipairs(mods) do
            assert.is_nil(findTag(m, "Condition"),
                "always-on conversions (Acid Flask/Shuriken) must NOT be gated by the Stormhide condition")
            local sk = findTag(m, "SkillName")
            assert.is_not_nil(sk)
            assert.are.equals("Acid Flask", sk.skillName)
        end
    end)

    ---------------------------------------------------------------------------
    -- ModCache: the two stale rows are gone so the new strings live-parse
    ---------------------------------------------------------------------------
    it("no stale Stormhide ModCache rows short-circuit the parser", function()
        local body = readSource("Data/ModCache.lua")
        assert.is_nil(body:find("Base Damage converted to Lightning for Swipe", 1, true),
            "the stale notSupported conversion row must be removed")
        assert.is_nil(body:find("Melee Lightning Damage with Swipe (3 second cooldown)", 1, true),
            "the stale (dirty-residue) added-damage row must be removed")
    end)

    ---------------------------------------------------------------------------
    -- modDB tag resolution: OFF filters the conversion out, ON returns it
    ---------------------------------------------------------------------------
    it("Condition gates the conversion: OFF -> filtered (no-op), ON -> active", function()
        local db = new("ModDB")
        db.actor = { modDB = db }
        db:AddList(modLib.parseMod("100% of Swipe Base Damage converted to Lightning (Empowered Swipe)"))
        db:AddList(modLib.parseMod("+38 Melee Lightning Damage with Swipe (Empowered Swipe)"))
        -- KeywordFlag.Melee = 512 (Global.lua); the added-damage mod carries it,
        -- so the query cfg must include it for the flag filter to match.
        local melee = KeywordFlag.Melee
        local swipeOff = { skillName = "Swipe", keywordFlags = melee } -- EmpoweredSwipe NOT set -> gated out
        assert.are.equals(0, db:Sum("BASE", swipeOff, "PhysicalDamageConvertToLightning"),
            "OFF: conversion must be fully gated (no-op)")
        assert.are.equals(0, db:Sum("BASE", swipeOff, "LightningDamage"),
            "OFF: added Lightning must be fully gated (no-op)")
        local swipeOn = { skillName = "Swipe", keywordFlags = melee, skillCond = { EmpoweredSwipe = true } }
        assert.are.equals(100, db:Sum("BASE", swipeOn, "PhysicalDamageConvertToLightning"),
            "ON: Swipe's physical base converts to Lightning")
        assert.are.equals(38, db:Sum("BASE", swipeOn, "LightningDamage"),
            "ON: the +38 Melee Lightning Damage applies")
    end)

    it("conversion is Swipe-scoped: another skill never sees it even with the condition on", function()
        local db = new("ModDB")
        db.actor = { modDB = db }
        db:AddList(modLib.parseMod("100% of Swipe Base Damage converted to Lightning (Empowered Swipe)"))
        local otherOn = { skillName = "Meteor", skillCond = { EmpoweredSwipe = true } }
        assert.are.equals(0, db:Sum("BASE", otherOn, "PhysicalDamageConvertToLightning"),
            "the conversion must not leak to a non-Swipe skill")
    end)

    ---------------------------------------------------------------------------
    -- Config: the conditionEmpoweredSwipe toggle exists, default OFF, Combat-scoped
    ---------------------------------------------------------------------------
    it("defines conditionEmpoweredSwipe bound to Condition:EmpoweredSwipe, Combat-scoped", function()
        local configText = readSource("Modules/ConfigOptions.lua")
        assert.is_truthy(configText:find('var = "conditionEmpoweredSwipe"', 1, true),
            "ConfigOptions must define conditionEmpoweredSwipe")
        assert.is_truthy(configText:find('"Condition:EmpoweredSwipe"', 1, true),
            "conditionEmpoweredSwipe must emit Condition:EmpoweredSwipe FLAG")
        assert.is_truthy(configText:find('Condition:EmpoweredSwipe".-Combat', 1, false),
            "conditionEmpoweredSwipe must be Combat-scoped")
    end)

    it("conditionEmpoweredSwipe is default OFF (no default attribute key set)", function()
        -- The toggle is a plain check with no `default`/`defaultState`/`defaultIndex`
        -- attribute => unchecked by default, matching the conditionStoppedMoving
        -- precedent (intermittent effect). (Match the config keys specifically, not
        -- the word "default" in the human-readable tooltip prose.)
        local configText = readSource("Modules/ConfigOptions.lua")
        local line = configText:match('([^\n]-var = "conditionEmpoweredSwipe"[^\n]*)')
        assert.is_not_nil(line, "must find the conditionEmpoweredSwipe config line")
        assert.is_nil(line:find("default = ", 1, true),
            "conditionEmpoweredSwipe must NOT set `default =` (stays OFF -> baseline preserved)")
        assert.is_nil(line:find("defaultState", 1, true),
            "conditionEmpoweredSwipe must NOT set `defaultState`")
        assert.is_nil(line:find("defaultIndex", 1, true),
            "conditionEmpoweredSwipe must NOT set `defaultIndex`")
    end)

    it("carries the inline regression-guard markers (parse + config sites)", function()
        local parserText = readSource("Modules/ModParser.lua")
        local configText = readSource("Modules/ConfigOptions.lua")
        assert.is_truthy(parserText:find("@leb-regression-guard:stormhide-empowered-swipe (parse site)", 1, true),
            "inline guard ID (parse site) must remain in ModParser.lua")
        assert.is_truthy(configText:find("@leb-regression-guard:stormhide-empowered-swipe (config site)", 1, true),
            "inline guard ID (config site) must remain in ConfigOptions.lua")
    end)
end)
