-- @leb-regression-guard:icicle-cold-to-lightning-conversion-toggle
-- Locks the default-OFF config toggle that converts Icicle's BASE damage from
-- Cold to Lightning at 100% (faithful to IcicleMutator, game-source rate).
--
-- Ground truth (datamined game source):
--   DamageStatsHolder.convertBaseDamage(holder, from=2 COLD, to=3 LIGHTNING,
--                                       proportion=DAT_183d71c08, 0)
-- then the hit is re-tagged Lightning (field 0xd1 := 3 = LIGHTNING). DamageType
-- enum 2=COLD / 3=LIGHTNING is confirmed in src/Data game_enums.json. The
-- proportion DAT_183d71c08 is the GENERIC 1.0f shared across the binary (the
-- universal "+1" base in Ability.c; same const in the (field + DAT_183d71c08) * x
-- increase->multiplier lines at datamined game source and asserted = 1.0 in
-- ChaosBoltsDamage.fixspec) -- so the rate is 100%, NOT an Icicle magnitude.
--
-- WHY default OFF: the in-mutator conversion is gated on a bool spec field
-- (param_1+0x118). Icicle (skills.json HeorotUniqueBowIcicle, granted by "Reign of
-- Winter" #159) has NO skill tree, so no game-data node/affix can write that bool
-- -- the conversion is normally inert. Default OFF keeps Icicle pure Cold (matches
-- current dev skills.json spell_base_cold_damage:100) and the corpus byte-identical.
--
-- When ON, the config apply() (run ONLY for a checked box) emits the Condition flag
-- AND an Icicle-scoped + Condition-gated ColdDamageConvertToLightning BASE 100 that
-- CalcOffence's existing conversionTable consumer (globalConv, mult = 1 - converted)
-- applies -- the SAME channel as the Stormhide empowered Swipe / Acid Flask base
-- conversions. Mirrors conditionHolyAuraDamageAura (config-gated intrinsic).
--
-- See REGRESSION_GUARDS.md > "icicle-cold-to-lightning-conversion-toggle".

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

describe("IcicleColdToLightning", function()
    before_each(function()
        newBuild()
    end)

    ---------------------------------------------------------------------------
    -- Config: the conditionIcicleConvertedToLightning toggle exists, default OFF,
    -- Combat-scoped, and emits BOTH the Condition flag and the conversion mod.
    ---------------------------------------------------------------------------
    it("defines conditionIcicleConvertedToLightning bound to Condition:IcicleConvertedToLightning, Combat-scoped", function()
        local src = readSource("Modules/ConfigOptions.lua")
        assert.is_truthy(src:find('var = "conditionIcicleConvertedToLightning"', 1, true),
            "ConfigOptions must define conditionIcicleConvertedToLightning")
        assert.is_truthy(src:find('"Condition:IcicleConvertedToLightning"', 1, true),
            "the toggle must emit Condition:IcicleConvertedToLightning FLAG")
        assert.is_truthy(src:find('Condition:IcicleConvertedToLightning".-Combat', 1, false),
            "the Condition flag must be Combat-scoped")
        assert.is_truthy(src:find('"ColdDamageConvertToLightning", "BASE", 100', 1, true),
            "the toggle must emit a 100% Cold->Lightning base conversion (game-source rate)")
    end)

    it("conditionIcicleConvertedToLightning is default OFF (no default-state attribute)", function()
        -- A plain check with no `default`/`defaultState`/`defaultIndex` is unchecked
        -- by default => corpus byte-identical (matches conditionStoppedMoving /
        -- conditionEmpoweredSwipe). Match the config KEYS, not "default" in the prose.
        local src = readSource("Modules/ConfigOptions.lua")
        local line = src:match('([^\n]-var = "conditionIcicleConvertedToLightning"[^\n]*)')
        assert.is_not_nil(line, "must find the conditionIcicleConvertedToLightning config line")
        assert.is_nil(line:find("default = ", 1, true),
            "the toggle must NOT set `default =` (stays OFF -> baseline preserved)")
        assert.is_nil(line:find("defaultState", 1, true),
            "the toggle must NOT set `defaultState`")
        assert.is_nil(line:find("defaultIndex", 1, true),
            "the toggle must NOT set `defaultIndex`")
    end)

    it("carries the inline regression-guard markers (config + conversion site)", function()
        local src = readSource("Modules/ConfigOptions.lua")
        assert.is_truthy(src:find("@leb-regression-guard:icicle-cold-to-lightning-conversion-toggle (config + conversion site)", 1, true),
            "inline guard ID (config site) must remain in ConfigOptions.lua")
        assert.is_truthy(src:find("@leb-regression-guard:icicle-cold-to-lightning-conversion-toggle (conversion site)", 1, true),
            "inline guard ID (conversion site, at the ColdDamageConvertToLightning emit) must remain")
    end)

    it("tooltip is user-facing only (leaks no internal code symbol)", function()
        -- The config-tooltip-no-internal-info contract forbids dev symbols like
        -- "Mutator" in user-facing tooltips; keep the Icicle tooltip plain.
        local src = readSource("Modules/ConfigOptions.lua")
        local line = src:match('([^\n]-var = "conditionIcicleConvertedToLightning"[^\n]*)')
        assert.is_not_nil(line, "must find the conditionIcicleConvertedToLightning config line")
        local tip = line:match('tooltip = "([^"]*)"')
        assert.is_not_nil(tip, "the toggle must carry a tooltip")
        assert.is_nil(tip:find("Mutator", 1, true),
            "the tooltip must not leak the internal 'Mutator' code symbol")
    end)

    it("suggestBuff pairs with a buffDetectPatterns row so the highlight is not dead", function()
        -- suggestBuff = "HeorotUniqueBowIcicle" requires a matching name row in
        -- ConfigTab.lua's buffDetectPatterns (Reign of Winter's "...cast Icicle..."
        -- affix fires it via the Pass-3 item scan). Mirrors the HolyAura pairing.
        local cfgTab = readSource("Classes/ConfigTab.lua")
        local block = cfgTab:match("local buffDetectPatterns%s*=%s*(%b{})")
        assert.is_not_nil(block, "ConfigTab.lua must define buffDetectPatterns")
        assert.is_truthy(block:find('name = "HeorotUniqueBowIcicle"', 1, true),
            "buffDetectPatterns must contain a row named for the Icicle suggestBuff value")
    end)

    ---------------------------------------------------------------------------
    -- modDB tag resolution: the conversion mod is Icicle-scoped AND gated on the
    -- toggle Condition -- OFF filters it out, ON returns 100, no leak to other skills.
    ---------------------------------------------------------------------------
    it("conversion mod gates correctly: OFF -> 0, ON -> 100, Icicle-scoped (no leak)", function()
        local db = new("ModDB")
        db.actor = { modDB = db }
        db:NewMod("ColdDamageConvertToLightning", "BASE", 100, "Config",
            { type = "SkillName", skillName = "Icicle" },
            { type = "Condition", var = "IcicleConvertedToLightning" })
        local off = { skillName = "Icicle" } -- Condition NOT set -> gated out
        assert.are.equals(0, db:Sum("BASE", off, "ColdDamageConvertToLightning"),
            "OFF: the conversion is gated out (Icicle stays pure Cold)")
        local on = { skillName = "Icicle", skillCond = { IcicleConvertedToLightning = true } }
        assert.are.equals(100, db:Sum("BASE", on, "ColdDamageConvertToLightning"),
            "ON: Icicle's Cold base converts 100% to Lightning")
        local other = { skillName = "Meteor", skillCond = { IcicleConvertedToLightning = true } }
        assert.are.equals(0, db:Sum("BASE", other, "ColdDamageConvertToLightning"),
            "the conversion must not leak to a non-Icicle skill even with the condition on")
    end)

    ---------------------------------------------------------------------------
    -- End-to-end: select the real Icicle skill and flip the toggle via the live
    -- config pipeline (apply() -> conversionTable). (i) OFF == pure Cold; (ii) ON
    -- moves the base Cold to Lightning (Cold -> 0, Lightning == former Cold).
    ---------------------------------------------------------------------------
    local function icicleOut(on)
        newBuild()
        build.skillsTab:SelSkill(1, "HeorotUniqueBowIcicle")
        build.configTab.input["conditionIcicleConvertedToLightning"] = on or nil
        build.configTab:BuildModList()
        build.buildFlag = true
        runCallback("OnFrame")
        return build.calcsTab.mainOutput
    end
    local function hit(out, t) return out[t .. "HitAverage"] or 0 end

    it("(i) default OFF: Icicle hit is Cold, Lightning portion is 0", function()
        local out = icicleOut(false)
        assert.is_true(hit(out, "Cold") > 0, "Icicle's intrinsic Cold base hit must be present")
        assert.are.equals(0, hit(out, "Lightning"),
            "with the toggle OFF there is no conversion -> zero Lightning (corpus-neutral baseline)")
    end)

    it("(ii) toggle ON: base Cold becomes 0, base Lightning = former Cold (hit re-tagged Lightning)", function()
        local off = icicleOut(false)
        local formerCold = hit(off, "Cold")
        assert.is_true(formerCold > 0, "sanity: Icicle has a non-zero Cold base to convert")
        local out = icicleOut(true)
        assert.are.equals(0, hit(out, "Cold"),
            "100% Cold->Lightning conversion -> Cold hit becomes 0")
        assert.is_true(hit(out, "Lightning") > 0,
            "the converted base lands on Lightning (hit re-tagged Lightning)")
        assert.is_true(math.abs(hit(out, "Lightning") - formerCold) <= 0.5,
            "base Lightning must equal the former Cold value (100% conversion, no type-specific scaling on a bare build)")
    end)
end)
