-- @leb-regression-guard:enchant-weapon-buff
--     channel keeps the spell cfg per @leb-regression-guard:flamewave-caster-hit-context-inc).
-- See REGRESSION_GUARDS.md > "enchant-weapon-buff".
-- Validation provenance is retained in maintainer notes.

local function readSrc(rel)
    local f = io.open(rel, "r") or io.open("src/" .. rel, "r")
    assert.is_not_nil(f, rel .. " must be readable")
    local s = f:read("*a"); f:close()
    return s
end

describe("EnchantWeaponBuff", function()
    local calcs
    before_each(function()
        newBuild()
        calcs = require("Modules/Calcs")
    end)

    -- ---- the shared pure function (REAL production arithmetic) ----

    it("passive tier: 15% MORE Fire/Cold/Lightning, Melee-flagged (serialized MORE 0.15)", function()
        local mods = calcs.enchantWeaponBuffMods(false)
        assert.are.equals(3, #mods, "exactly the three elemental types (ModParser 'elemental damage' list)")
        local seen = {}
        for _, m in ipairs(mods) do
            seen[m.name] = true
            assert.are.equals("MORE", m.modType, m.name .. " must be MORE (AltText: multiplicative)")
            assert.are.equals(15, m.value, m.name .. " passive tier = 15 (EnchantWeaponPassiveMutator 0.15)")
            assert.are.equals(ModFlag.Melee, m.flags, m.name .. " must be Melee-flagged (stat tags [Elemental, Melee])")
            assert.are.equals("Enchant Weapon (Passive)", m.source)
        end
        assert.is_true(seen.FireDamage and seen.ColdDamage and seen.LightningDamage,
            "Fire/Cold/Lightning exactly")
    end)

    it("active tier: 50% MORE, REPLACES the passive (never both -- capture: Cold ratio ~1.5, not 1.725)", function()
        local mods = calcs.enchantWeaponBuffMods(true)
        assert.are.equals(3, #mods, "one tier only -- the Active replaces the Passive, it does not stack")
        for _, m in ipairs(mods) do
            assert.are.equals("MORE", m.modType)
            assert.are.equals(50, m.value, m.name .. " active tier = 50 (EnchantWeaponMutator 0.5)")
            assert.are.equals(ModFlag.Melee, m.flags)
            assert.are.equals("Enchant Weapon (Active)", m.source)
        end
    end)

    it("scope: NEVER Physical / Void / Necrotic / Poison / generic Damage (phys in-game/LEB parity 1.02)", function()
        for _, active in ipairs({ false, true }) do
            for _, m in ipairs(calcs.enchantWeaponBuffMods(active)) do
                assert.is_true(m.name == "FireDamage" or m.name == "ColdDamage" or m.name == "LightningDamage",
                    "elemental-only: got " .. m.name)
            end
        end
    end)

    -- ---- end-to-end through ModDB: Melee flag filters spells ----

    it("through ModDB: a melee-fire hit gets the MORE; a spell-fire hit does NOT", function()
        local db = new("ModDB")
        db.actor = { output = {}, modDB = db }
        for _, m in ipairs(calcs.enchantWeaponBuffMods(true)) do
            db:NewMod(m.name, m.modType, m.value, m.source, m.flags)
        end
        -- CalcOffence.calcDamage multiplies MORE on {"Damage", "<type>Damage"} with the
        -- skill cfg; Melee-flagged mods require ModFlag.Melee in cfg.flags.
        local meleeCfg = { flags = ModFlag.Melee }
        local spellCfg = { flags = ModFlag.Spell }
        assert.are.equals(1.5, db:More(meleeCfg, "Damage", "FireDamage"), "melee fire hit x1.5")
        assert.are.equals(1.5, db:More(meleeCfg, "Damage", "ColdDamage"), "melee cold hit x1.5")
        assert.are.equals(1.0, db:More(spellCfg, "Damage", "FireDamage"),
            "spell fire hit unaffected (Flame Wave keeps its spell MORE channel)")
        assert.are.equals(1.0, db:More(meleeCfg, "Damage"),
            "typeless (physical/void) melee hit unaffected -- elemental-only")
    end)

    -- ---- config source pin ----

    it("ConfigOptions declares conditionEnchantWeaponActive (default OFF) -> Condition:EnchantWeaponActive", function()
        local src = readSrc("Modules/ConfigOptions.lua")
        assert.is_truthy(src:find('var = "conditionEnchantWeaponActive"', 1, true),
            "ConfigOptions must declare the conditionEnchantWeaponActive toggle")
        assert.is_truthy(src:find("Condition:EnchantWeaponActive", 1, true),
            "the toggle's apply must set Condition:EnchantWeaponActive")
    end)

    it("ConfigTab carries the EnchantWeapon highlight row (suggestBuff contract)", function()
        local src = readSrc("Classes/ConfigTab.lua")
        assert.is_truthy(src:find('name = "EnchantWeapon"', 1, true),
            "buffDetectPatterns must carry an EnchantWeapon row (else the suggestBuff highlight is dead)")
    end)

    -- ---- CalcSetup pin: gating + the shared pure function ----

    it("CalcSetup gates on Enchant Weapon on-bar+enabled; passive auto, active via the config flag", function()
        local src = readSrc("Modules/CalcSetup.lua")
        assert.is_truthy(src:find("@leb-regression-guard:enchant-weapon-buff", 1, true),
            "CalcSetup must carry the guard")
        assert.is_truthy(src:find('buffSkillTreePrefixes["sb44eQ-"]', 1, true),
            "must gate on the Enchant Weapon (sb44eQ) socket group being on the bar")
        assert.is_truthy(src:find("ewPrefix and ewPrefix.enabled", 1, true),
            "must gate on the group being enabled")
        assert.is_truthy(src:find('Flag(nil, "Condition:EnchantWeaponActive")', 1, true),
            "the Active tier must read the config Condition flag")
        assert.is_truthy(src:find("calcs.enchantWeaponBuffMods(ewActive)", 1, true),
            "injection must call the shared pure function (so this spec tests the real arithmetic)")
    end)

    it("the pure function pins 50/15 and never emits both tiers or non-elemental stats", function()
        local src = readSrc("Modules/CalcSetup.lua")
        local body = src:match("function calcs%.enchantWeaponBuffMods.-\nend")
        assert.is_not_nil(body, "calcs.enchantWeaponBuffMods definition not found")
        assert.is_truthy(body:find("active and 50 or 15", 1, true),
            "one tier only: 50 (Active) XOR 15 (Passive) -- replacement semantics")
        assert.is_truthy(body:find("ModFlag.Melee", 1, true), "mods must be Melee-flagged")
        assert.is_nil(body:find("PhysicalDamage", 1, true), "must not inject PhysicalDamage (parity-proven)")
        assert.is_nil(body:find('"Damage"', 1, true), "must not inject generic Damage (elemental-only)")
    end)
end)
