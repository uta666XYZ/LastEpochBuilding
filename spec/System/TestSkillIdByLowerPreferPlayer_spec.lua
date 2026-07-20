-- @leb-regression-guard:skillidbylower-prefer-player
-- Locks the deterministic, player-preferring construction of skillIdByLower /
-- skillNameByLower in ModParser.lua.
--
-- Before: the lookup was built with a bare `for skillId, skill in pairs(data.skills)`
-- loop. data.skills holds duplicate skill NAMES (a player skill plus minion / enemy /
-- ailment homonyms), so each name collapsed to ONE id whose identity depended on
-- pairs() iteration order — NON-DETERMINISTIC across processes. Every trigger bridge
-- that resolves a skill by name (skillIdByLower[lower]) — the on-hit / on-melee-hit /
-- on-spell-cast bridges, the cooldown globalCapped bridge, and the qualified on-crit
-- rate-cap bridge — could therefore inject the MINION's skill into Full DPS instead of
-- the player's (e.g. the real affix "Lightning Blast on Crit with Frost Claw" bridging
-- to minion StormCrowLightningBlast). Wrong triggered skill => wrong in-game DPS.
--
-- Fix: iterate keys in sorted order and, on a name collision, prefer the id whose
-- skill owns a player skill tree (data.skills[id].treeId, set only for player-usable
-- skills — every minion/enemy/ailment homonym has treeId == nil). Higher rank wins;
-- equal rank => sorted-first id wins (stable across processes). This spec asserts the
-- observable parser output resolves each known collision to the PLAYER id.
-- See REGRESSION_GUARDS.md "skillidbylower-prefer-player".

describe("skillIdByLower prefers the player skill deterministically", function()
    -- The discriminator the fix relies on: in every duplicate-name group the player
    -- skill is exactly the id carrying a non-nil treeId, and the minion/enemy/ailment
    -- homonym has treeId == nil. Lock that data invariant so the heuristic can't rot.
    it("treeId distinguishes the player id from its homonyms (data invariant)", function()
        assert.is_truthy(data.skills.LightningBlast.treeId, "player LightningBlast has a treeId")
        assert.is_nil(data.skills.StormCrowLightningBlast.treeId, "minion StormCrowLightningBlast has none")
        assert.is_truthy(data.skills.Surge.treeId, "player Surge has a treeId")
        assert.is_nil(data.skills["RogueFalcon Diving Attack"].treeId, "minion homonym has none")
        assert.is_truthy(data.skills.BoneCurse.treeId, "player BoneCurse has a treeId")
        assert.is_nil(data.skills.Ailment_BoneCurse.treeId, "ailment homonym has none")
        assert.is_truthy(data.skills.SpiritPlague.treeId, "player SpiritPlague has a treeId")
        assert.is_nil(data.skills.Ailment_SpiritPlague.treeId, "ailment homonym has none")
    end)

    -- The headline bug: the real in-data affix must bridge to the PLAYER id, not the
    -- minion StormCrowLightningBlast. Assert the exact mod name (no order-independent
    -- workaround).
    it("the real affix bridges to ChanceToTriggerCapped_LightningBlast (player id), NOT StormCrowLightningBlast", function()
        local mods, extra = modLib.parseMod("42% chance to cast Lightning Blast on crit with Frost Claw (up to 3 casts per second)")
        assert.is_nil(extra)
        assert.is_falsy(mods.notSupported)
        local byName = {}
        for _, m in ipairs(mods) do byName[m.name] = m.value end
        assert.are.equals(42, byName["ChanceToTriggerCapped_LightningBlast"])
        assert.are.equals(3, byName["TriggerRateCapPerSecond_LightningBlast"])
        assert.is_nil(byName["ChanceToTriggerCapped_StormCrowLightningBlast"],
            "must NOT resolve to the minion homonym")
    end)

    -- Other duplicate-name groups, exercised through the bare on-hit bridge
    -- (ChanceToTriggerOnHit_<id>). Each must resolve to the player id.
    it("'Lightning Blast on hit' -> player LightningBlast (not StormCrowLightningBlast)", function()
        local mods = modLib.parseMod("10% Chance to cast Lightning Blast on hit")
        assert.are.equals("ChanceToTriggerOnHit_LightningBlast", mods[1].name)
    end)

    it("'Surge on hit' -> player Surge (not 'RogueFalcon Diving Attack')", function()
        local mods = modLib.parseMod("10% Chance to cast Surge on hit")
        assert.are.equals("ChanceToTriggerOnHit_Surge", mods[1].name)
    end)

    it("'Bone Curse on hit' -> player BoneCurse (not Ailment_BoneCurse)", function()
        local mods = modLib.parseMod("10% Chance to cast Bone Curse on hit")
        assert.are.equals("ChanceToTriggerOnHit_BoneCurse", mods[1].name)
    end)

    it("'Spirit Plague on hit' -> player SpiritPlague (not Ailment_SpiritPlague)", function()
        local mods = modLib.parseMod("10% Chance to cast Spirit Plague on hit")
        assert.are.equals("ChanceToTriggerOnHit_SpiritPlague", mods[1].name)
    end)

    -- Stability: re-parsing yields the identical id every time (the resolution is a
    -- pure function of the sorted keys + treeId, with no pairs()-order dependence).
    it("repeated parsing resolves the same player id every time", function()
        local first
        for _ = 1, 50 do
            local mods = modLib.parseMod("10% Chance to cast Lightning Blast on hit")
            local name = mods[1].name
            first = first or name
            assert.are.equals(first, name)
            assert.are.equals("ChanceToTriggerOnHit_LightningBlast", name)
        end
    end)
end)
