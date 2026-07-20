-- @leb-regression-guard:holy-aura-damage-mutator-buff
-- See REGRESSION_GUARDS.md > "holy-aura-damage-mutator-buff".
-- Validation provenance is retained in maintainer notes.

local function readSrc(rel)
    local f = io.open(rel, "r") or io.open("src/" .. rel, "r")
    assert.is_not_nil(f, rel .. " must be readable")
    local s = f:read("*a"); f:close()
    return s
end

describe("HolyAuraDamageMutator", function()
    local calcs
    before_each(function()
        newBuild()
        calcs = require("Modules/Calcs")
    end)

    -- ---- the shared pure function (REAL production arithmetic) ----

    it("game source: +30% increased damage base, scaled by HolyAuraEffect -> +36% at +20% (captured i=0.36)", function()
        local mods = calcs.holyAuraDamageAuraMods(20, true)
        assert.are.equals(1, #mods, "only the type-agnostic default is intrinsic (elemental fire/light is the ah443-7 tree node)")
        assert.are.equals("Damage", mods[1].name)
        assert.are.equals("INC", mods[1].modType)
        assert.are.equals(36, mods[1].value, "30 base x 1.20 HolyAuraEffect = captured 0.36")
        assert.are.equals("Holy Aura", mods[1].source)
    end)

    it("contributes ONLY the all-damage default -- never typed Fire/Lightning/Cold (would double-count ah443-7)", function()
        for _, eff in ipairs({ 0, 20, 50, 100 }) do
            for _, m in ipairs(calcs.holyAuraDamageAuraMods(eff, true)) do
                assert.are.equals("Damage", m.name,
                    "no FireDamage/LightningDamage/ColdDamage -- the elemental aura is the already-modelled ah443-7 tree node")
            end
        end
    end)

    it("inactive (Holy Aura off the bar / toggle off) -> no contribution", function()
        assert.are.equals(0, #calcs.holyAuraDamageAuraMods(20, false))
        assert.are.equals(0, #calcs.holyAuraDamageAuraMods(0, nil))
    end)

    it("scales linearly with HolyAuraEffect off the +30% base", function()
        assert.are.equals(30, calcs.holyAuraDamageAuraMods(0, true)[1].value, "no effect -> base 30")
        assert.are.equals(36, calcs.holyAuraDamageAuraMods(20, true)[1].value, "30 x 1.20")
        assert.are.equals(45, calcs.holyAuraDamageAuraMods(50, true)[1].value, "30 x 1.50")
    end)

    -- ---- end-to-end through ModDB: the all-damage default reaches EVERY type ----

    it("the +36% all-damage default raises increased-damage for fire, cold, lightning AND physical equally", function()
        local db = new("ModDB")
        db.actor = { output = {}, modDB = db }
        for _, m in ipairs(calcs.holyAuraDamageAuraMods(20, true)) do
            db:NewMod(m.name, m.modType, m.value, m.source)
        end
        -- CalcOffence.calcDamage sums INC on {"Damage", "<type>Damage"} for a hit of <type>;
        -- the type-agnostic "Damage" reaches all of them.
        assert.are.equals(36, db:Sum("INC", nil, "Damage", "FireDamage"), "fire hit")
        assert.are.equals(36, db:Sum("INC", nil, "Damage", "LightningDamage"), "lightning hit")
        assert.are.equals(36, db:Sum("INC", nil, "Damage", "ColdDamage"), "cold hit")
        assert.are.equals(36, db:Sum("INC", nil, "Damage"), "physical / void hit (no own type stat)")
    end)

    -- ---- config source pin ----

    it("ConfigOptions declares the conditionHolyAuraDamageAura check (default OFF) -> Condition:HolyAuraDamageAura", function()
        local src = readSrc("Modules/ConfigOptions.lua")
        assert.is_truthy(src:find('var = "conditionHolyAuraDamageAura"', 1, true),
            "ConfigOptions must declare the conditionHolyAuraDamageAura toggle")
        assert.is_truthy(src:find("Condition:HolyAuraDamageAura", 1, true),
            "the toggle's apply must set Condition:HolyAuraDamageAura")
        -- The removed elemental form must NOT reappear (it would double-count ah443-7 Firestorm)
        assert.is_nil(src:find("HolyAuraDamageMutatorElemental", 1, true),
            "no elemental flag -- the fire/light aura is the ah443-7 tree node, modelled via the buff-tree path")
    end)

    -- ---- CalcSetup pin: gating + the shared pure function, ALL-damage only ----

    it("CalcSetup gates the buff on Holy Aura active + the config flag and uses the shared pure function", function()
        local src = readSrc("Modules/CalcSetup.lua")
        assert.is_truthy(src:find("@leb-regression-guard:holy-aura-damage-mutator-buff", 1, true),
            "CalcSetup must carry the guard")
        assert.is_truthy(src:find("calcs.holyAuraDamageAuraMods(haEffectInc, true)", 1, true),
            "injection must call the shared pure function (so the spec tests the real arithmetic)")
        assert.is_truthy(src:find("holyAuraPrefix and holyAuraPrefix.enabled", 1, true),
            "must gate on Holy Aura being on the bar + enabled")
        assert.is_truthy(src:find('Flag(nil, "Condition:HolyAuraDamageAura")', 1, true),
            "must gate on the config Condition flag")
        assert.is_truthy(src:find('Sum("INC", nil, "HolyAuraEffect")', 1, true),
            "must scale by HolyAuraEffect")
    end)

    it("the pure function pins base 30 * effectScale and emits NO typed damage stat", function()
        local src = readSrc("Modules/CalcSetup.lua")
        local body = src:match("function calcs%.holyAuraDamageAuraMods.-\nend")
        assert.is_not_nil(body, "calcs.holyAuraDamageAuraMods definition not found")
        assert.is_truthy(body:find("30 * effectScale", 1, true), "base 30 must be scaled by HolyAuraEffect")
        assert.is_nil(body:find("FireDamage", 1, true), "must not inject FireDamage (ah443-7 already does)")
        assert.is_nil(body:find("LightningDamage", 1, true), "must not inject LightningDamage (ah443-7 already does)")
        assert.is_nil(body:find("ColdDamage", 1, true), "must not inject ColdDamage")
    end)
end)
