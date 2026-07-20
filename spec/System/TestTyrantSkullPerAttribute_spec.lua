-- @leb-regression-guard: tyrant-skull-per-attribute-minion-scope
-- @leb-regression-guard: minion-modifier-multi-type-gate
-- Locks the parser handlers + config gate for Tyrant's Skull (unique 424) per-
-- attribute Tyrannosaur scaling. The unique's tooltip (in-game-confirmed,
-- 2026-06-19) grants the summoned PrimalTyrannosaur:
--   "+2 Tyrannosaur Melee Damage per Strength"
--   "1% more Tyrannosaur Health and Damage per 1% Uncapped Endurance"
--   "+1% Tyrannosaur Physical Penetration per Intelligence"
--   "+1% Tyrannosaur Critical Strike Multiplier per Attunement"
--   "1% increased Tyrannosaur Attack and Cast Speed per Dexterity"
--
-- COEFFICIENTS are in-game-confirmed (tooltip; pen 0.27 == Int x1%, crit mult
-- 2.79 == base + Att x1%; Endurance-MORE slope matches a belt toggle). But the
-- applied MAGNITUDE overshoots (engine added-damage-scaling/baseline not pinned),
-- so the block is GATED behind config `conditionTyrantSkullPerAttribute`
-- (DEFAULT OFF) via an ActorCondition tag on Condition:TyrantSkullPerAttribute.
-- Default OFF keeps every snapshot byte-identical to the no-block baseline.
--
-- This is a source-text lock (no build fixture): it guards that (a) the 5
-- handlers stay registered and PrimalTyrannosaur-scoped, (b) the per-attribute
-- PerStat tags read the player (actor=parent), (c) EVERY inner mod carries the
-- ActorCondition gate so the block cannot leak into snapshots while OFF, and
-- (d) the config option exists and only sets the flag when checked (default OFF).

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("TyrantSkullPerAttribute", function()
    local parserText, configText

    setup(function()
        parserText = readSource("Modules/ModParser.lua")
        configText = readSource("Modules/ConfigOptions.lua")
    end)

    it("ModParser registers all 5 per-attribute Tyrannosaur patterns", function()
        for _, frag in ipairs({
            "tyrannosaur melee damage per strength",
            "more tyrannosaur health and damage per 1%% uncapped endurance",
            "tyrannosaur physical penetration per intelligence",
            "tyrannosaur critical strike multiplier per attunement",
            "increased tyrannosaur attack and cast speed per dexterity",
        }) do
            assert.is_truthy(string.find(parserText, frag, 1, true),
                "ModParser must register: " .. frag)
        end
    end)

    it("each handler routes to the PrimalTyrannosaur minion only", function()
        local _, count = string.gsub(parserText, 'minionTypes = { "PrimalTyrannosaur" }', "")
        assert.is_true(count >= 6,
            "expected >=6 PrimalTyrannosaur-scoped MinionModifier inner mods (5 lines, Endurance line emits 2)")
    end)

    it("per-attribute PerStat tags read the player (actor=parent)", function()
        for _, stat in ipairs({ "Str", "EnduranceTotal", "Int", "Att", "Dex" }) do
            assert.is_truthy(string.find(parserText,
                '{ type = "PerStat", stat = "' .. stat .. '", actor = "parent" }', 1, true),
                "PerStat tag for " .. stat .. " must use actor=parent")
        end
    end)

    it("EVERY inner mod carries the ActorCondition gate (default-OFF safety)", function()
        local gate = '{ type = "ActorCondition", actor = "parent", var = "TyrantSkullPerAttribute" }'
        local _, gates = string.gsub(parserText, gate:gsub("[%-%.%+%[%]%(%)%$%^%%%?%*]", "%%%1"), "")
        assert.is_true(gates >= 6,
            "all 6 Tyrannosaur inner mods must carry the ActorCondition gate so the block stays inert while OFF")
    end)

    it("Endurance MORE scales on uncapped Endurance (EnduranceTotal), both Life and Damage", function()
        assert.is_truthy(string.find(parserText,
            'mod%("Life", "MORE", tonumber%(num%), "", 0, 0, { type = "PerStat", stat = "EnduranceTotal"', 1, false),
            "Endurance line must emit a Life MORE per EnduranceTotal")
        assert.is_truthy(string.find(parserText,
            'mod%("Damage", "MORE", tonumber%(num%), "", 0, 0, { type = "PerStat", stat = "EnduranceTotal"', 1, false),
            "Endurance line must emit a Damage MORE per EnduranceTotal")
    end)

    it("config option exists and is gated (only sets the flag when checked)", function()
        assert.is_truthy(string.find(configText,
            'var = "conditionTyrantSkullPerAttribute", type = "check"', 1, true),
            "ConfigOptions must define the conditionTyrantSkullPerAttribute check")
        assert.is_truthy(string.find(configText,
            'modList:NewMod%("Condition:TyrantSkullPerAttribute", "FLAG", true, "Config"', 1, false),
            "config apply must set Condition:TyrantSkullPerAttribute only when checked (default OFF)")
    end)
end)
