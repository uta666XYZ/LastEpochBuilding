-- @leb-regression-guard:trigger-chance-to-cast-every-n-seconds
-- Locks the source-INDEPENDENT timer trigger: "X% chance to cast <skill> every N
-- seconds". There is no source skill - it fires on a fixed N-second clock - so the
-- expected steady-state rate is chance/100 attempts per N seconds = num/(100*N)
-- casts per second. The parser bakes that exact (text-derived) value into a
-- functional TriggerRatePerSecond_<skillId> BASE mod; CalcSetup injects a
-- timer-triggered group (triggeredByTimer, includeInFullDPS, no triggeredOnHit);
-- CalcTriggers' gated timerTriggerConfig feeds the fixed rate so
-- output.EffectiveSourceRate = rate (not the cap). See REGRESSION_GUARDS.md.

describe("TriggerEveryNSeconds bridge (parser)", function()
    it("'100% chance to cast Maelstrom every 3 seconds' bakes rate = 1/3 per second", function()
        assert.are.equals("Maelstrom", data.skills.Maelstrom.name)
        local mods, extra = modLib.parseMod("100% chance to cast Maelstrom every 3 seconds")
        assert.is_nil(extra)
        assert.is_not_nil(mods)
        assert.are.equals(1, #mods)
        local m = mods[1]
        assert.are.equals("TriggerRatePerSecond_Maelstrom", m.name)
        assert.are.equals("BASE", m.type)
        assert.is_true(math.abs(m.value - (100/100/3)) < 1e-9, "rate must be chance/100/N = 1/3")
        assert.is_falsy(mods.notSupported)
    end)

    it("the chance scales the rate: 12% every 3s = 0.04/s", function()
        local mods = modLib.parseMod("12% chance to cast Maelstrom every 3 seconds")
        assert.are.equals("TriggerRatePerSecond_Maelstrom", mods[1].name)
        assert.is_true(math.abs(mods[1].value - 0.04) < 1e-9, "12/100/3 = 0.04")
    end)
end)

describe("TriggerEveryNSeconds ModCache", function()
    it("no stale 'cast Maelstrom every 3 seconds' row short-circuits the parser", function()
        local f = assert(io.open("Data/ModCache.lua", "r"))
        local body = f:read("*a"); f:close()
        assert.is_nil(body:find("cast Maelstrom every 3 seconds", 1, true),
            "stale (previously empty-parse) ModCache rows would re-mask the bridge")
    end)
end)

describe("TriggerEveryNSeconds source invariants", function()
    it("ModParser emits the functional TriggerRatePerSecond_ mod", function()
        local f = assert(io.open("Modules/ModParser.lua", "r"))
        local text = f:read("*a"); f:close()
        assert.is_truthy(text:find('TriggerRatePerSecond_" .. triggerSkillId', 1, true),
            "ModParser must emit TriggerRatePerSecond_<skillId>")
        assert.is_truthy(text:find("@leb%-regression%-guard:trigger%-chance%-to%-cast%-every%-n%-seconds"),
            "inline regression-guard marker must be present in ModParser")
    end)

    it("CalcSetup injects a timer-triggered group and CalcTriggers gates a timer config", function()
        local f = assert(io.open("Modules/CalcSetup.lua", "r"))
        local cs = f:read("*a"); f:close()
        assert.is_truthy(cs:find("TriggerRatePerSecond_", 1, true), "CalcSetup must sum TriggerRatePerSecond_")
        assert.is_truthy(cs:find("triggeredByTimer", 1, true), "CalcSetup must mark triggeredByTimer")
        local g = assert(io.open("Modules/CalcTriggers.lua", "r"))
        local ct = g:read("*a"); g:close()
        assert.is_truthy(ct:find("triggeredByTimer", 1, true), "CalcTriggers must gate on triggeredByTimer")
        assert.is_truthy(ct:find("timerTriggerConfig", 1, true), "CalcTriggers must define the timer config")
    end)
end)

describe("TriggerEveryNSeconds end-to-end (build)", function()
    it("injects Maelstrom into Full DPS at the timer rate with the rest of the build unchanged", function()
        local xmlPath = "../spec/TestBuilds/1.4/BZ37GXdY lv94 Beastmaster.xml"
        local fh = io.open(xmlPath, "r")
        if not fh then pending("BZ37GXdY build XML not present (spec/TestBuilds is gitignored)"); return end
        local xml = fh:read("*a"); fh:close()
        loadBuildFromXML(xml)
        build.buildFlag = true
        build:OnFrame({})
        local env = build.calcsTab.mainEnv
        local mael
        for _, s in ipairs(env.player.activeSkillList) do
            local ge = s.activeEffect and s.activeEffect.grantedEffect
            if ge and ge.name == "Maelstrom" and s.socketGroup and s.socketGroup.triggeredByTimer then mael = s end
        end
        assert.is_not_nil(mael, "Maelstrom must be injected as a timer trigger")
        assert.is_true(mael.socketGroup.includeInFullDPS, "timer-triggered Maelstrom must be in Full DPS")
        -- this build's roll is 12% every 3s -> 0.04 casts/sec
        assert.is_true(math.abs(mael.socketGroup.triggerRatePerSecond - 0.04) < 1e-9,
            "timer rate must be the build-derived 0.04/s")
        -- Maelstrom contributes a small, finite, positive amount; the rest of the
        -- build's Full DPS (the bear) is unchanged. Instead of a blind FullDPS window,
        -- pin the bear-only part = FullDPS minus the Maelstrom SkillDPS entry, so the
        -- two halves of the contract are asserted independently.
        -- Bear-only baseline re-derived 2026-06-12 (2nd re-base, minion propagation
        -- merge): the minion-skill-tree-mods-to-minion / minion-crit-multiplier-base-2
        -- guards legitimately moved the bear again, 6091.4977 -> 7975.6072 (x1.3093):
        --   * PrimalBear ActorStats baseline (minions.json modList, game prefab):
        --     Damage MORE x1.75, attack speed MORE x0.78 -> DPS x1.365
        --     (probe: bear MORE chain 2.70 = 1.544 lv94 x 1.75 ActorStats)
        --   * minion base crit multi 2.0 (PoB +30 removed): CM 2.46 -> 2.16 with
        --     this build's +16 affix sum; at CC 18.8 the crit effect drops
        --     1.2745 -> 1.2181 (x0.956). 1.365 x 0.956 = 1.305 ~= measured 1.3093
        --     (residual = bleed/ailment sub-entries riding the same chain).
        --   * This build's be36ar allocations are roar/defense nodes only
        --     (7,9,14,18,21,26,27,28) -- no bear damage-MORE nodes, no companion
        --     MORE passives, so the transfer itself adds no further damage here.
        -- 1st re-base (minion-level-MORE merge <see git log>, LE's hidden
        -- 1 + 0.008x(lv-26) minion MORE): SkillDPS PrimalBear 3953.54 -> 6088.46,
        -- exactly x1.5400; FullDPS 3964.1104 = bear 3956.5840 + Maelstrom 7.5264 ->
        -- 6099.0241 = bear 6091.4977 + Maelstrom 7.5264. The Maelstrom entry is
        -- bit-identical across BOTH re-bases (7.5264), so the timer-trigger feature
        -- this spec guards is untouched.
        -- (The original 3956.58/3966 window had itself been re-based once for the
        -- `skill-dot-stacking` merge growing Maelstrom <1.4 -> ~7.53.)
        local out = build.calcsTab.mainOutput
        local maelDPS = 0
        for _, e in ipairs(out.SkillDPS or {}) do
            if e.name == "Maelstrom" then maelDPS = maelDPS + e.dps * (e.count or 1) end
        end
        assert.is_true(maelDPS > 0 and maelDPS < 100,
            "Maelstrom must add a small positive Full DPS entry, got " .. tostring(maelDPS))
        -- Sum the bear's OWN SkillDPS entries directly rather than (FullDPS - Maelstrom).
        -- This build equips Chorus of the Anurok, so the auto-summon framework
        -- (data.autoSummons, AnuroksSummoned -> packCount MaxCompanions) now adds
        -- Summon Anurok pack DPS to FullDPS — a separate, unrelated minion source
        -- (the build has zero player-global conversions, so the off-type conversion
        -- work does not touch it). "FullDPS - Maelstrom" therefore no longer isolates
        -- the bear. Guarding the bear's own SkillDPS entries keeps this spec focused on
        -- the Maelstrom timer-trigger feature and robust to other FullDPS-included
        -- minions (Anurok / bees / etc.). Bear total = 7975.6072 (7972.58 + 3.03).
        local bearDPS = 0
        for _, e in ipairs(out.SkillDPS or {}) do
            if e.name == "Summon Bear" then bearDPS = bearDPS + e.dps * (e.count or 1) end
        end
        assert.is_true(math.abs(bearDPS - 7975.6072) < 0.01,
            "bear Summon Bear Full DPS must stay at the re-derived 7975.6072 baseline, got "
            .. tostring(bearDPS) .. " (FullDPS " .. tostring(out.FullDPS) .. ", Maelstrom " .. tostring(maelDPS) .. ")")
    end)
end)
