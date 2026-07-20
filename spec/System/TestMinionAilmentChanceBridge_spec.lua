-- @leb-regression-guard:minion-ailment-chance-bridge
-- See REGRESSION_GUARDS.md > "minion-ailment-chance-bridge".
-- Validation provenance is retained in maintainer notes.

local function readSrc(rel)
    local f = io.open(rel, "r") or io.open("src/" .. rel, "r")
    assert.is_not_nil(f, rel .. " must be readable")
    local s = f:read("*a"); f:close()
    return s
end

describe("MinionAilmentChanceBridge", function()
    before_each(function()
        newBuild()
    end)

    -- ---- the name family + flag semantics the bridge relies on ----

    it("ModParser routes '+N% Bleed Chance' to ChanceToTriggerOnHit_Ailment_Bleed (Hit-flagged, LIVE parse)", function()
        -- bypass the ModCache entry so a stale cache can't shadow the live rule
        -- (the E.Nova-Bug2 / elemental-arrows bug class)
        local line = "+25% Bleed Chance"
        local saved = modLib.parseModCache[line]
        modLib.parseModCache[line] = nil
        local modList = modLib.parseMod(line)
        modLib.parseModCache[line] = saved
        assert.is_not_nil(modList, "the tree-node line must parse")
        local found
        for _, m in ipairs(modList) do
            if m.name == "ChanceToTriggerOnHit_Ailment_Bleed" then found = m end
        end
        assert.is_not_nil(found, "must emit the trigger-family stat (bridge source name)")
        assert.are.equals("BASE", found.type)
        assert.are.equals(25, found.value)
        assert.are.equals(ModFlag.Hit, found.flags, "inner mod is Hit-flagged (ModCache convention 8388608)")
    end)

    it("a Hit-flagged trigger chance in a minion-side ModDB is summable with a hit cfg (dispatch contract)", function()
        local db = new("ModDB")
        db.actor = { output = {}, modDB = db }
        -- what CalcPerform's MinionModifier dispatch lands on minion.modDB
        -- (probe-verified on VoidMaster_blank: BASE 35, flags=ModFlag.Hit)
        db:NewMod("ChanceToTriggerOnHit_Ailment_Bleed", "BASE", 35, "Tree:Sentinel-37", ModFlag.Hit)
        db:NewMod("ChanceToTriggerOnHit_Ailment_Bleed", "BASE", 50, "Tree:ma6hdr-22", ModFlag.Hit)
        local hitCfg = { flags = ModFlag.Melee + ModFlag.Hit } -- disjoint bits (512 | 8388608)
        assert.are.equals(85, db:Sum("BASE", hitCfg, "ChanceToTriggerOnHit_Ailment_Bleed"),
            "tree + skill-tree ranks stack additively (in-game 0.863 = 85 within binomial)")
        assert.are.equals(0, db:Sum("BASE", hitCfg, "BleedChance"),
            "the native name stays empty -- exactly why the bridge is needed")
    end)

    -- ---- source pins: the bridge site in CalcOffence ----

    it("CalcOffence carries the bridge for BOTH actors (no minion-only gate)", function()
        local src = readSrc("Modules/CalcOffence.lua")
        assert.is_truthy(src:find("@leb-regression-guard:minion-ailment-chance-bridge", 1, true),
            "CalcOffence must carry the guard")
        assert.is_falsy(src:find("if actor == env.minion then", 1, true),
            "bridge must NOT gate on the minion actor -- the player drops tree chance too")
        assert.is_truthy(src:find('"ChanceToTriggerOnHit_Ailment_" .. ailmentName', 1, true),
            "bridge must sum the trigger-family stat name")
        -- the fold must target the native chance the damagingAilment loop reads,
        -- capped at 100 like the native block
        assert.is_truthy(src:find('output[ailmentName .. "Chance"] = m_min((output[ailmentName .. "Chance"] or 0) + triggerChance, 100)', 1, true),
            "bridge must fold into output.<Key>Chance with the native 100 cap")
        -- and the uncapped overstacking re-sum must mirror the same trigger-family addition
        assert.is_truthy(src:find('+ modDB:Sum("BASE", skillCfg, "ChanceToTriggerOnHit_Ailment_" .. ailmentName)', 1, true),
            "the >100% overstacking application rate must also include the trigger-family chance")
    end)

    it("bridge scope = data.damagingAilment keys (the only consumers of output.<Key>Chance in the loop)", function()
        local src = readSrc("Modules/CalcOffence.lua")
        local block = src:match("@leb%-regression%-guard:minion%-ailment%-chance%-bridge.-\n\t%-%- @leb%-regression%-guard:chance%-chance%-conversion")
        assert.is_not_nil(block, "bridge block must sit before the chance-conversion engine")
        assert.is_truthy(block:find("for ailmentName in pairs(data.damagingAilment) do", 1, true),
            "must iterate damaging ailments only -- non-damaging ailments keep their routes")
    end)

    it("the ailment data the bridge feeds is stable (Bleed 53phys/3s, Ignite 40fire/2.5s)", function()
        -- the damagingAilment loop turns chance into DPS with these bases; pin the two
        -- capture-verified ailments so a data edit can't silently shift the bridge's output
        assert.are.equals(53, data.damagingAilment.Bleed.baseDamage)
        assert.are.equals(3, data.damagingAilment.Bleed.duration)
        assert.are.equals("Physical", data.damagingAilment.Bleed.associatedType)
        assert.are.equals(40, data.damagingAilment.Ignite.baseDamage)
        assert.are.equals(2.5, data.damagingAilment.Ignite.duration)
        assert.are.equals("Fire", data.damagingAilment.Ignite.associatedType)
    end)
end)
