-- @leb-regression-guard:current-mana-damage-scaling
-- Locks the "X% Damage per N current mana" pipeline. These mods (game text "more
-- damage (multiplicative) per N current mana", altText "Multiplicative with other
-- modifiers") were SILENTLY DROPPED corpus-wide: ModParser had no "per N current
-- mana" entry, so the phrase fell to `extra` residue and PassiveTree.lua's
-- modifier-applied gate (`if mod.list and (not mod.extra or mod.extra == "")`)
-- discarded the whole mod — not even the flat % survived. Root cause confirmed by
-- modest-raman (2026-05-29): it is the DOMINANT (x3.13) gap in YsMaidenPrimalist's
-- Storm Bolt undermodel via Excited Bolts (+3% Damage Per 10 Current Mana, 711
-- mana => +213% MORE). Three live ModCache entries were hit:
--   ModCache 6069  "+3% Damage Per 10 Current Mana"               (Excited Bolts / Gathering Storm)
--   ModCache 1875  "+1% Damage Per 40 Current Mana"               (Flame Rush)
--   ModCache 13555 "3% more Stygian Beam Damage per 10 Current Mana" (Drain Life unique)
--
-- Fix: a "per (%d+) current mana" modTagList entry emitting PerStat{CurrentMana},
-- mirroring the existing "per N max mana". DESIGN ASSUMPTION: a static planner has
-- no live current mana (it fluctuates per cast), so current mana is modelled as
-- FULL mana (current == max). CalcPerform.doActorLifeMana sets
-- output.CurrentMana = output.Mana. This matches the in-game dominant case (mana
-- parked at the cap: 74% of YsMaiden's Storm Bolt hits land at full 711 mana).
-- Per-node caps (e.g. Excited Bolts +300%) are node metadata absent from the mod
-- string and are intentionally NOT modelled here; they would bind only above
-- ~1000 mana, beyond the 711-mana target.
--
-- See ModParser.lua / CalcPerform.lua "per (%d+) current mana" anchors and
-- REGRESSION_GUARDS.md > "current-mana-damage-scaling".

local function findTag(mod, stat)
    for _, tag in ipairs(mod) do
        if tag.type == "PerStat" and tag.stat == stat then return tag end
    end
end

describe("CurrentManaDamageScaling", function()
    before_each(function()
        newBuild()
    end)

    it("live-parses 'per N current mana' into a PerStat:CurrentMana MORE (nil extra)", function()
        -- A novel value is NOT a ModCache key, so this exercises the live
        -- ModParser modTagList branch rather than a baked cache entry.
        local mods, extra = modLib.parseMod("+5% Damage Per 20 Current Mana")
        assert.is_nil(extra, "a fully-parsed 'per N current mana' must leave no residue")
        assert.is_not_nil(mods)
        assert.are.equals(1, #mods)
        assert.are.equals("Damage", mods[1].name)
        assert.are.equals("MORE", mods[1].type)
        assert.are.equals(5, mods[1].value)
        local tag = findTag(mods[1], "CurrentMana")
        assert.is_not_nil(tag, "must carry a PerStat{CurrentMana} tag")
        assert.are.equals(20, tonumber(tag.div))
    end)

    it("ModCache Excited Bolts '+3% Damage Per 10 Current Mana' parses clean + tagged", function()
        local mods, extra = modLib.parseMod("+3% Damage Per 10 Current Mana")
        assert.is_nil(extra)
        assert.are.equals("Damage", mods[1].name)
        assert.are.equals("MORE", mods[1].type)
        assert.are.equals(3, mods[1].value)
        local tag = findTag(mods[1], "CurrentMana")
        assert.is_not_nil(tag, "Excited Bolts entry must scale by CurrentMana")
        assert.are.equals(10, tonumber(tag.div))
    end)

    it("ModCache Flame Rush '+1% Damage Per 40 Current Mana' parses clean + tagged", function()
        local mods, extra = modLib.parseMod("+1% Damage Per 40 Current Mana")
        assert.is_nil(extra)
        assert.are.equals("Damage", mods[1].name)
        assert.are.equals("MORE", mods[1].type)
        assert.are.equals(1, mods[1].value)
        local tag = findTag(mods[1], "CurrentMana")
        assert.is_not_nil(tag)
        assert.are.equals(40, tonumber(tag.div))
    end)

    it("ModCache Stygian Beam unique keeps SkillName AND adds PerStat:CurrentMana", function()
        local mods, extra = modLib.parseMod("3% more Stygian Beam Damage per 10 Current Mana")
        assert.is_nil(extra)
        assert.are.equals("Damage", mods[1].name)
        assert.are.equals("MORE", mods[1].type)
        assert.are.equals(3, mods[1].value)
        local perStat, skillTag
        for _, tag in ipairs(mods[1]) do
            if tag.type == "PerStat" and tag.stat == "CurrentMana" then perStat = tag end
            if tag.type == "SkillName" then skillTag = tag end
        end
        assert.is_not_nil(skillTag, "must retain the Stygian Beam skill gate")
        assert.are.equals("Stygian Beam", skillTag.skillName)
        assert.is_not_nil(perStat, "must add the per-10-current-mana scaling")
        assert.are.equals(10, tonumber(perStat.div))
    end)

    it("tree node '+3% Damage Per 10 Current Mana' reaches node.modList (no silent drop)", function()
        -- The original failure: PassiveTree dropped the mod because of non-empty
        -- `extra`. Assert the Damage MORE mod now lands in node.modList with its
        -- PerStat tag intact (regardless of the scaled value, which is 0 here
        -- because the bare node has no CurrentMana output).
        local node = { id = "test-current-mana-guard",
            stats = { "+3% Damage Per 10 Current Mana" }, alloc = 1 }
        build.spec.tree:ProcessStats(node)
        local found
        for _, m in ipairs(node.modList) do
            if m.name == "Damage" and m.type == "MORE" and findTag(m, "CurrentMana") then
                found = m
            end
        end
        assert.is_not_nil(found,
            "Excited-Bolts-style mod must survive into node.modList (was silently dropped)")
        assert.are.equals(3, found.value)
    end)

    it("PerStat:CurrentMana MORE scales by full mana (711 -> +213% -> x3.13)", function()
        -- EvalMod scales continuously: value = 3 * (711 / 10) = 213.3 (the PerStat
        -- block is explicitly NOT floored). ModDB:MoreInternal then computes the
        -- more multiplier "to the nearest percent" (ModDB.lua round(modResult, 2)):
        --   round(1 + 213.3/100, 2) = round(3.133, 2) = 3.13
        -- This reproduces modest-raman's x3.13 for the 711-mana Storm Bolt exactly.
        local db = new("ModDB")
        db.actor = { output = { CurrentMana = 711 }, modDB = db }
        db:NewMod("Damage", "MORE", 3, "Excited Bolts",
            { type = "PerStat", stat = "CurrentMana", div = 10 })
        assert.are.equals(3.13, round(db:More(nil, "Damage"), 2),
            "711 current mana must produce +213% MORE Damage (x3.13, nearest percent)")
    end)

    it("contributes nothing when current mana is 0 (proves wiring, no phantom bonus)", function()
        local db = new("ModDB")
        db.actor = { output = { CurrentMana = 0 }, modDB = db }
        db:NewMod("Damage", "MORE", 3, "Excited Bolts",
            { type = "PerStat", stat = "CurrentMana", div = 10 })
        assert.are.equals(1, db:More(nil, "Damage"),
            "0 current mana => 0 stacks => x1 (the bonus is mana-gated, not flat)")
    end)

    it("CalcPerform sets output.CurrentMana == output.Mana (full-mana assumption)", function()
        newBuild()
        build.calcsTab:BuildOutput()
        local output = build.calcsTab.mainOutput
        assert.is_not_nil(output.Mana, "output.Mana must be computed")
        assert.are.equals(output.Mana, output.CurrentMana,
            "static planner models current mana as full (max) mana")
    end)
end)
