-- @leb-regression-guard: ballista-attack-speed-minion-scope
-- @leb-regression-guard: minion-modifier-multi-type-gate
-- Locks the parser handler that routes the "(X)% Increased Ballista Attack Speed"
-- affix family (datamine affix 536 "Rogue's" Max Ballistae+AS, affix 640 Level of
-- Ballista+AS; property 58 / summonBallista tag 379) to the RogueBallista minion's
-- BallistaBolt firing rate.
--
-- BUG (2026-07-08, Rem-MK3): the default parse stripped the "ballista" skill-name
-- token and produced a PLAIN player-side `INC Speed flags=Attack tag=SkillName:
-- "Ballista"`. That tag names the player SUMMON skill ("Ballista"), not the minion's
-- firing skill ("Ballista Bolt"), and the mod is never wrapped as a MinionModifier,
-- so it never reaches env.minion.modDB. Probe: a rolled INC 29 sat on the player and
-- was absent from the minion's Speed list -> ballista firing rate under-modeled
-- (minion Speed 1.4537 -> 1.8078 once routed).
--
-- FIX mirrors the Tyrannosaur precedent (TestTyrantSkullPerAttribute): emit a
-- MinionModifier LIST scoped to RogueBallista, whose inner mod is a plain INC Speed
-- with flags=0 and NO SkillName tag (the minion Speed query in CalcOffence.lua is
-- scoped to "Ballista Bolt"; an unscoped INC Speed matches). Dispatch in
-- CalcPerform.lua (guard minion-modifier-multi-type-gate) lands it on the minion.
--
-- Source-text lock (no build fixture): guards that (a) the handler stays registered,
-- (b) it routes to RogueBallista only, (c) the inner Speed mod carries no SkillName
-- tag (which would re-scope it to the player summon skill and re-break it).

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("BallistaAttackSpeedMinionScope", function()
    local parserText

    setup(function()
        parserText = readSource("Modules/ModParser.lua")
    end)

    it("ModParser registers the 'increased ballista attack speed' handler", function()
        assert.is_truthy(
            string.find(parserText, "increased ballista attack speed", 1, true),
            "ModParser must register a handler for 'increased ballista attack speed'")
    end)

    it("the handler routes to the RogueBallista minion", function()
        assert.is_truthy(
            string.find(parserText, 'minionTypes = { "RogueBallista" }', 1, true),
            "the ballista attack-speed handler must scope to minionTypes RogueBallista")
    end)

    it("the handler is a functional MinionModifier producing an INC Speed on the minion", function()
        -- Locate the handler block and assert its body emits a MinionModifier LIST with
        -- an inner Speed INC. Match from the pattern key to the RogueBallista scope.
        local block = string.match(parserText,
            "increased ballista attack speed%$\"%]%s*=%s*function.-minionTypes = { \"RogueBallista\" }")
        assert.is_not_nil(block, "must find the ballista attack-speed handler body")
        assert.is_truthy(string.find(block, 'mod("MinionModifier", "LIST"', 1, true),
            "handler must wrap the speed bonus as a MinionModifier LIST")
        assert.is_truthy(string.find(block, 'mod("Speed", "INC"', 1, true),
            "inner mod must be an INC Speed")
        -- The inner Speed mod must NOT carry a SkillName tag (that would re-scope it to
        -- the player summon skill "Ballista" and stop it reaching the minion again).
        assert.is_nil(string.find(block, "SkillName", 1, true),
            "inner Speed mod must not carry a SkillName tag")
    end)
end)
