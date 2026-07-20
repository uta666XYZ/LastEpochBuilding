-- @leb-regression-guard:druid-form-base-aura
-- Locks the Werebear/Spriggan form "base aura" stat injection in ConfigOptions.
-- Toggling conditionInWerebearForm / conditionInSprigganForm must apply the form's
-- inherent buff stats (datamined BuffParent.stats, datamined game source
-- extracted/form_auras_decoded.json), not merely the Condition FLAGs:
--   Werebear: +50% increased Melee Damage, +15% increased Health, -100% MORE ManaRegen.
--   Spriggan: +50% increased Spell Damage, +300 BASE Armour, -100% MORE ManaRegen.
-- ManaDrain (+5, in both forms' aura) is intentionally NOT modelled: LEB has no
-- ManaDrain/mana-degen stat to map it onto (separate follow-up). Values are verbatim
-- from the datamine (no fabrication). When the form is OFF the stats must NOT apply.
-- See REGRESSION_GUARDS.md "druid-form-base-aura".

local function buildConfig(setInput)
    newBuild()
    setInput(build.configTab.input)
    build.configTab:BuildModList()
    runCallback("OnFrame")
    return build.configTab.modList
end

describe("DruidFormBaseAura", function()
    it("default (no form) applies none of the form base-aura stats", function()
        local modList = buildConfig(function() end)
        assert.are.equal(0, modList:Sum("INC", nil, "Life"))
        assert.are.equal(0, modList:Sum("BASE", nil, "Armour"))
        assert.are.equal(0, modList:Sum("INC", { flags = ModFlag.Melee }, "Damage"))
        assert.are.equal(0, modList:Sum("INC", { flags = ModFlag.Spell }, "Damage"))
        assert.are.equal(1, modList:More(nil, "ManaRegen"))
    end)

    it("Werebear Form applies +50% Melee Damage, +15% Health, -100% ManaRegen", function()
        local modList = buildConfig(function(input) input.conditionInWerebearForm = true end)
        assert.are.equal(15, modList:Sum("INC", nil, "Life"))
        assert.are.equal(50, modList:Sum("INC", { flags = ModFlag.Melee }, "Damage"))
        assert.are.equal(0, modList:More(nil, "ManaRegen")) -- MORE -100 => x0
        -- Werebear gives no flat Armour and no Spell-tagged damage
        assert.are.equal(0, modList:Sum("BASE", nil, "Armour"))
        assert.are.equal(0, modList:Sum("INC", { flags = ModFlag.Spell, keywordFlags = 0 }, "Damage"))
    end)

    it("Spriggan Form applies +50% Spell Damage, +300 Armour, -100% ManaRegen", function()
        local modList = buildConfig(function(input) input.conditionInSprigganForm = true end)
        assert.are.equal(300, modList:Sum("BASE", nil, "Armour"))
        assert.are.equal(50, modList:Sum("INC", { flags = ModFlag.Spell }, "Damage"))
        assert.are.equal(0, modList:More(nil, "ManaRegen"))
        -- Spriggan gives no Health % and no Melee-tagged damage
        assert.are.equal(0, modList:Sum("INC", nil, "Life"))
        assert.are.equal(0, modList:Sum("INC", { flags = ModFlag.Melee, keywordFlags = 0 }, "Damage"))
    end)

    it("ManaDrain is NOT modelled (no stat exists to carry the datamined +5)", function()
        local modList = buildConfig(function(input) input.conditionInWerebearForm = true end)
        assert.are.equal(0, modList:Sum("BASE", nil, "ManaDrain"))
    end)
end)
