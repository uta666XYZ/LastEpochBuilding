describe("TestModParse", function()
    before_each(function()
        newBuild()
    end)

    teardown(function()
        -- newBuild() takes care of resetting everything in setup()
    end)

    it("health", function()
        build.configTab.input.customMods = "+92 Health\n\z
        20% increased Health"
        build.configTab:BuildModList()
        build.buildFlag = true
        runCallback("OnFrame")
        assert.are.equals(242, build.calcsTab.calcsOutput.Life)

        build.configTab.input.customMods = "+892 Health\n\z
        20.5% increased Health"
        build.configTab:BuildModList()
        build.buildFlag = true
        runCallback("OnFrame")
        assert.are.equals(1207, build.calcsTab.calcsOutput.Life)
    end)

    it("health regen", function()
        build.configTab.input.customMods = "100% Increased Health Regen"
        build.configTab:BuildModList()
        build.buildFlag = true
        runCallback("OnFrame")
        assert.are.equals(12, math.floor(build.calcsTab.calcsOutput.LifeRegen))

        build.configTab.input.customMods = "200% Increased Health Regen\n\z50% Reduced Health Regeneration"
        build.configTab:BuildModList()
        build.buildFlag = true
        runCallback("OnFrame")
        assert.are.equals(15, math.floor(build.calcsTab.calcsOutput.LifeRegen))
    end)

    it("cooldown recovery", function()
        build.configTab.input.customMods = "-17% Cooldown Recovery Speed"
        build.configTab:BuildModList()
        runCallback("OnFrame")
        assert.are.equals(0, build.configTab.modList:Sum("BASE", nil, "CooldownRecovery"))
        assert.are.equals(-17, build.configTab.modList:Sum("INC", nil, "CooldownRecovery"))
    end)

    it("duration", function()
        build.configTab.input.customMods = "+81% Duration"
        build.configTab:BuildModList()
        runCallback("OnFrame")
        assert.are.equals(0, build.configTab.modList:Sum("BASE", nil, "Duration"))
        assert.are.equals(81, build.configTab.modList:Sum("INC", nil, "Duration"))
    end)

    it("fire resistance", function()
        build.configTab.input.customMods = "81% Fire resistance"
        build.configTab:BuildModList()
        runCallback("OnFrame")
        assert.are.equals(81, build.configTab.modList:Sum("BASE", nil, "FireResist"))
        assert.are.equals(0, build.configTab.modList:Sum("INC", nil, "FireResist"))
        assert.are.equals(0, build.configTab.modList:Sum("MORE", nil, "FireResist"))
    end)

    it("fire and necrotic resistance", function()
        build.configTab.input.customMods = "+81% fire and necrotic resistance"
        build.configTab:BuildModList()
        runCallback("OnFrame")
        assert.are.equals(81, build.configTab.modList:Sum("BASE", nil, "FireResist"))
        assert.are.equals(81, build.configTab.modList:Sum("BASE", nil, "NecroticResist"))
    end)

    -- @leb-regression-guard:crits-abbreviation
    -- Locks the parser routing for the Sentinel-tree "Crits" abbreviation.
    -- If the specific "from crits$" patterns get reordered after the
    -- "from (.+)$" catch-all in src/Modules/ModParser.lua, scan() picks the
    -- catch-all first (longest-pattern tie-breaking), the value falls through
    -- to LEB_NotSupported, and Sentinel-114 Heaven's Bulwark stops crediting
    -- ReduceCritExtraDamage. This reproduces the original B4Xq8aG6 -30 diff.
    it("crits abbreviation reduces crit damage", function()
        build.configTab.input.customMods = "30% Reduced Bonus Damage Taken From Crits\n\z
        2% Reduced Bonus Damage Taken From Crits\n\z
        5% Less Bonus Damage Taken From Crits"
        build.configTab:BuildModList()
        runCallback("OnFrame")
        assert.are.equals(37, build.configTab.modList:Sum("BASE", nil, "ReduceCritExtraDamage"))
    end)

    -- @leb-regression-guard:with-a-shield-condition
    -- Sentinel-90 "Sanctuary Guardian" lists "+15% All Resistances With A Shield"
    -- in its notScalingStats. Without the "with a shield" condition mapping in
    -- ModParser.modTagList, the trailing condition survives as residual extra
    -- and PassiveTree.lua line 421-423 sets node.extra=true, causing the entire
    -- mod to be discarded — silently dropping ~15 from every resist on B4Xq8aG6.
    it("with a shield condition tag", function()
        build.configTab.input.customMods = "+15% All Resistances With A Shield"
        build.configTab:BuildModList()
        runCallback("OnFrame")
        -- All seven resists must each receive +15 BASE tagged with UsingShield.
        -- ModStoreClass:EvalMod uses cfg.skillCond[var] for Condition tag matching
        -- (see ModStore.lua line 563/574), so probe the cfg with skillCond set.
        local resists = { "FireResist", "ColdResist", "LightningResist",
            "PhysicalResist", "NecroticResist", "PoisonResist", "VoidResist" }
        for _, key in ipairs(resists) do
            assert.are.equals(15, build.configTab.modList:Sum("BASE", { skillCond = { UsingShield = true } }, key))
            assert.are.equals(0,  build.configTab.modList:Sum("BASE", { skillCond = { UsingShield = false } }, key))
        end
    end)

    -- @leb-regression-guard:while-with-a-shield-condition
    -- Sentinel-90 "Sanctuary Guardian" notScalingStats also uses the long form
    -- "+50 Armor While With A Shield". Without the "while with a shield" entry
    -- the trailing condition leaves residual extra (non-nil), which causes
    -- ConfigOptions.customMods (and PassiveTree.lua node ingestion) to drop the
    -- entire mod silently. We assert at the parseMod boundary so the test
    -- exercises the parser path even when ModList:Sum cfg semantics differ.
    it("while with a shield condition tag", function()
        local mods, extra = modLib.parseMod("+50 Armor While With A Shield")
        assert.is_nil(extra, "parseMod must consume 'while with a shield' (residual='" .. tostring(extra) .. "')")
        assert.is_not_nil(mods)
        assert.are.equals(1, #mods)
        assert.are.equals("Armour", mods[1].name)
        assert.are.equals("BASE", mods[1].type)
        assert.are.equals(50, mods[1].value)
        local tag = mods[1][1]
        assert.is_not_nil(tag, "expected a Condition tag on the mod")
        assert.are.equals("Condition", tag.type)
        assert.are.equals("UsingShield", tag.var)
    end)

    -- @leb-regression-guard:per-1pct-increased-movement-speed
    -- Unbroken Charge unique grants "+(11-30) Block Effectiveness per 1%
    -- Increased Movement Speed". Without the "per 1% increased movement speed"
    -- matcher the trailing suffix leaves residual extra and the entire mod is
    -- silently dropped. The Multiplier:MovementSpeedInc auto-injection in
    -- CalcSetup is verified separately at the build level.
    it("per 1% increased movement speed multiplier", function()
        local mods, extra = modLib.parseMod("+21 Block Effectiveness per 1% Increased Movement Speed")
        assert.is_nil(extra, "parseMod must consume 'per 1% increased movement speed' (residual='" .. tostring(extra) .. "')")
        assert.is_not_nil(mods)
        assert.are.equals(1, #mods)
        assert.are.equals("BlockEffectiveness", mods[1].name)
        assert.are.equals("BASE", mods[1].type)
        assert.are.equals(21, mods[1].value)
        local tag = mods[1][1]
        assert.is_not_nil(tag, "expected a Multiplier tag on the mod")
        assert.are.equals("Multiplier", tag.type)
        assert.are.equals("MovementSpeedInc", tag.var)
    end)

    -- @leb-regression-guard:traitors-tongue-offhand-crit-flat
    -- Traitor's Tongue (dual-wield dagger) is the only unique in the game that
    -- uses cross-slot self-referential mod text "with X equipped in the
    -- offhand/mainhand" (verified 2026-05-12 against
    -- LE_datamining/extracted/unique_mods_generated.json). Without the
    -- "with (.-) equipped in the offhand|mainhand" matchers the trailing
    -- condition survives as residual extra and Item.lua's processModLine
    -- silently drops the entire mod from modDB.
    it("equipped in the offhand condition tag", function()
        local mods, extra = modLib.parseMod("+12% Critical Strike Chance with Traitor's Tongue equipped in the offhand")
        assert.is_nil(extra, "parseMod must consume 'with X equipped in the offhand' (residual='" .. tostring(extra) .. "')")
        assert.is_not_nil(mods)
        assert.are.equals(1, #mods)
        assert.are.equals("CritChance", mods[1].name)
        assert.are.equals("BASE", mods[1].type)
        assert.are.equals(12, mods[1].value)
        local tag = mods[1][1]
        assert.is_not_nil(tag, "expected a Condition tag on the mod")
        assert.are.equals("Condition", tag.type)
        assert.are.equals("OffhandHas:traitor's tongue", tag.var)
    end)

    it("equipped in the mainhand condition tag", function()
        local mods, extra = modLib.parseMod("+12% Parry Chance with Traitor's Tongue equipped in the mainhand")
        assert.is_nil(extra, "parseMod must consume 'with X equipped in the mainhand' (residual='" .. tostring(extra) .. "')")
        assert.is_not_nil(mods)
        assert.are.equals(1, #mods)
        assert.are.equals("ParryChance", mods[1].name)
        assert.are.equals("BASE", mods[1].type)
        assert.are.equals(12, mods[1].value)
        local tag = mods[1][1]
        assert.is_not_nil(tag, "expected a Condition tag on the mod")
        assert.are.equals("Condition", tag.type)
        assert.are.equals("MainHandHas:traitor's tongue", tag.var)
    end)

    it("attributes", function()
        build.configTab.input.customMods = "+2 to All Attributes"
        build.configTab:BuildModList()
        build.buildFlag = true
        runCallback("OnFrame")

        assert.are.equals(4, build.calcsTab.calcsOutput.Str)
        assert.are.equals(2, build.calcsTab.calcsOutput.Dex)
        assert.are.equals(2, build.calcsTab.calcsOutput.Int)
        assert.are.equals(3, build.calcsTab.calcsOutput.Att)
        assert.are.equals(2, build.calcsTab.calcsOutput.Vit)
    end)

    it("damage types", function()
        build.configTab.input.customMods = "+10 damage\n+20 melee physical damage\n+25 spell fire damage"
        build.configTab:BuildModList()
        runCallback("OnFrame")

        assert.are.equals(10, build.configTab.modList:Sum("BASE", { keywordFlags = KeywordFlag.Physical }, "Damage"))
        assert.are.equals(10, build.configTab.modList:Sum("BASE", { keywordFlags = KeywordFlag.Physical }, "Damage"))
        assert.are.equals(20, build.configTab.modList:Sum("BASE", { keywordFlags = ModFlag.Melee }, "PhysicalDamage"))
        assert.are.equals(0, build.configTab.modList:Sum("BASE", nil, "PhysicalDamage"))
        assert.are.equals(0, build.configTab.modList:Sum("BASE", { keywordFlags = KeywordFlag.Fire }, "FireDamage"))
        assert.are.equals(25, build.configTab.modList:Sum("BASE", { keywordFlags = bit.bor(KeywordFlag.Fire, KeywordFlag.Spell) }, "FireDamage"))
    end)
    
    it("void spell damage", function()
        build.configTab.input.customMods = "+13 void spell damage"
        build.configTab:BuildModList()
        runCallback("OnFrame")

        assert.are.equals(13, build.configTab.modList:Sum("BASE", { keywordFlags = ModFlag.Spell }, "VoidDamage"))
        assert.are.equals(0, build.configTab.modList:Sum("BASE", nil, "VoidDamage"))
    end)

    it("increased damage", function()
        build.configTab.input.customMods = "50% increased melee void damage"
        build.configTab:BuildModList()
        runCallback("OnFrame")

        assert.are.equals(50, build.configTab.modList:Sum("INC", { keywordFlags = bit.bor(KeywordFlag.Void, KeywordFlag.Melee) }, "VoidDamage"))
    end)

    it("passive node more damage", function()
        build.configTab.input.customMods = "+10.5% Damage"
        build.configTab:BuildModList()
        runCallback("OnFrame")

        assert.are.equals(10.5, build.configTab.modList:Sum("MORE", nil, "Damage"))
    end)

    it("passive node more fire damage", function()
        build.configTab.input.customMods = "+10.5% Melee Fire Damage"
        build.configTab:BuildModList()
        runCallback("OnFrame")

        assert.are.equals(10.5, build.configTab.modList:Sum("MORE", {keywordFlags = ModFlag.Melee}, "FireDamage"))
        assert.are.equals(0, build.configTab.modList:Sum("MORE", nil, "FireDamage"))
    end)

    it("effect doubled", function()
        build.configTab.input.customMods = "+40% Increased fire damage. This effect is doubled if you have 300 or more maximum mana."
        build.configTab:BuildModList()
        runCallback("OnFrame")
        build.skillsTab:SelSkill(1, "Fireball")
        runCallback("OnFrame")

        -- @leb-regression-guard: int-truncate-life-mana
        -- Default Acolyte lv1: baseMana 50 + manaPerLevel 0.50506*1 + 2*Att(1) = 52.5
        -- → m_floor = 52 (LE in-game truncates int, see commit 153d4e455).
        -- Was 53 under upstream's round(); LEB switched to floor for in-game parity.
        -- If this assertion flips back to 53, output.Mana truncation regressed.
        assert.are.equals(52, build.calcsTab.calcsOutput.Mana)
        assert.are.equals(40, build.calcsTab.mainEnv.player.mainSkill.skillModList:Sum("INC", nil, "FireDamage"))

        build.configTab.input.customMods = "+900 maximum mana\n\z+40% Increased fire damage. This effect is doubled if you have 300 or more maximum mana."
        build.configTab:BuildModList()
        build.buildFlag = true
        runCallback("OnFrame")

        assert.are.equals(952, build.calcsTab.calcsOutput.Mana)
        assert.are.equals(80, build.calcsTab.mainEnv.player.mainSkill.skillModList:Sum("INC", nil, "FireDamage"))
    end)

    it("elemental cast speed", function()
        build.configTab.input.customMods = "+10% increased elemental cast speed"
        build.configTab:BuildModList()
        runCallback("OnFrame")

        assert.are.equals(10, build.configTab.modList:Sum("INC", {keywordFlags = KeywordFlag.Fire, flags = ModFlag.Cast}, "Speed"))
    end)

    it("melee and throwing attack speed", function()
        build.configTab.input.customMods = "+10% increased Melee And Throwing Attack Speed"
        build.configTab:BuildModList()
        runCallback("OnFrame")

        assert.are.equals(0, build.configTab.modList:Sum("INC", {flags = ModFlag.Attack}, "Speed"))
        assert.are.equals(10, build.configTab.modList:Sum("INC", {keywordFlags = ModFlag.Melee, flags = ModFlag.Attack}, "Speed"))
        assert.are.equals(10, build.configTab.modList:Sum("INC", {keywordFlags = ModFlag.Throwing, flags = ModFlag.Attack}, "Speed"))
    end)

    it("shred chance", function()
        build.configTab.input.customMods = "+10% Void Shred Chance"
        build.configTab:BuildModList()
        runCallback("OnFrame")

        assert.are.equals(10, build.configTab.modList:Sum("BASE", {flags = ModFlag.Hit}, "ChanceToTriggerOnHit_Ailment_VoidResistanceShred"))
    end)

    it("melee chance", function()
        build.configTab.input.customMods = "+10% Chance to Ignite on Melee Hit"
        build.configTab:BuildModList()
        runCallback("OnFrame")

        assert.are.equals(0, build.configTab.modList:Sum("BASE", {flags = bit.bor(ModFlag.Hit)}, "ChanceToTriggerOnHit_Ailment_Ignite"))
        assert.are.equals(10, build.configTab.modList:Sum("BASE", {flags = bit.bor(ModFlag.Hit, ModFlag.Melee)}, "ChanceToTriggerOnHit_Ailment_Ignite"))
    end)
    
    it("bleed chance", function()
        build.configTab.input.customMods = "+17% Bleed Chance"
        build.configTab:BuildModList()
        runCallback("OnFrame")

        assert.are.equals(17, build.configTab.modList:Sum("BASE", {flags = ModFlag.Hit}, "ChanceToTriggerOnHit_Ailment_Bleed"))
    end)

    -- "Depending on Area Level" scaling
    -- Formula: effective = min(rolled * min(areaLevel, 75) / 75, cap)
    -- where cap = rolled for single-value form, or explicit Z for "to Z%" form.
    local function approxEq(actual, expected, tol)
        tol = tol or 0.01
        assert.is_true(math.abs(actual - expected) < tol,
            "expected ~" .. tostring(expected) .. " got " .. tostring(actual))
    end

    describe("depending on area level", function()
        it("less damage single-value at area level 75 reaches rolled value", function()
            build.configTab.input.enemyLevel = 75
            build.configTab.input.customMods = "50% less Damage depending on Area Level for You and your Minions"
            build.configTab:BuildModList()
            runCallback("OnFrame")
            approxEq(build.configTab.modList:Sum("MORE", nil, "Damage"), -50)
        end)

        it("less damage single-value at partial area level scales linearly", function()
            build.configTab.input.enemyLevel = 37
            build.configTab.input.customMods = "50% less Damage depending on Area Level for You and your Minions"
            build.configTab:BuildModList()
            runCallback("OnFrame")
            -- effective = 50/75 * 37 ≈ 24.6667
            approxEq(build.configTab.modList:Sum("MORE", nil, "Damage"), -50 * 37 / 75)
        end)

        it("less damage area level clamps at 75", function()
            build.configTab.input.enemyLevel = 100
            build.configTab.input.customMods = "50% less Damage depending on Area Level for You and your Minions"
            build.configTab:BuildModList()
            runCallback("OnFrame")
            -- Mult clamped at 75, so effective = 50 even at area level 100.
            approxEq(build.configTab.modList:Sum("MORE", nil, "Damage"), -50)
        end)

        it("more damage taken single-value at area level 75", function()
            build.configTab.input.enemyLevel = 75
            build.configTab.input.customMods = "100% more Damage Taken depending on Area Level for You and your Minions"
            build.configTab:BuildModList()
            runCallback("OnFrame")
            approxEq(build.configTab.modList:Sum("MORE", nil, "DamageTaken"), 100)
        end)

        it("'X to Y' ranged form caps at Y at high area level (Tier 8)", function()
            build.configTab.input.enemyLevel = 75
            build.configTab.input.customMods = "120% to 75% less Damage depending on Area Level for You and your Minions"
            build.configTab:BuildModList()
            runCallback("OnFrame")
            -- rolled=120, cap=75, areaLevel=75 -> min(120/75 * 75, 75) = min(120, 75) = 75
            approxEq(build.configTab.modList:Sum("MORE", nil, "Damage"), -75)
        end)

        it("'X to Y' ranged form caps at Y at mid area level (Tier 8)", function()
            build.configTab.input.enemyLevel = 50
            build.configTab.input.customMods = "120% to 75% less Damage depending on Area Level for You and your Minions"
            build.configTab:BuildModList()
            runCallback("OnFrame")
            -- rolled=120, cap=75, areaLevel=50 -> min(120/75 * 50, 75) = min(80, 75) = 75
            approxEq(build.configTab.modList:Sum("MORE", nil, "Damage"), -75)
        end)

        it("'X to Y' ranged form below cap at low area level", function()
            build.configTab.input.enemyLevel = 30
            build.configTab.input.customMods = "120% to 75% less Damage depending on Area Level for You and your Minions"
            build.configTab:BuildModList()
            runCallback("OnFrame")
            -- rolled=120, cap=75, areaLevel=30 -> min(120/75 * 30, 75) = min(48, 75) = 48
            approxEq(build.configTab.modList:Sum("MORE", nil, "Damage"), -48)
        end)
    end)

    describe("while channelling <skill>", function()
        it("endurance while channelling Warpath applies only with condition", function()
            build.configTab.input.customMods = "10% Endurance while channelling Warpath"
            build.configTab:BuildModList()
            runCallback("OnFrame")
            -- Without ChannellingWarpath condition, mod is gated off.
            assert.are.equals(0, build.configTab.modList:Sum("BASE", nil, "Endurance"))
            -- With the skill-specific condition set via cfg.skillCond, mod applies.
            local cfg = { skillCond = { ChannellingWarpath = true } }
            assert.are.equals(10, build.configTab.modList:Sum("BASE", cfg, "Endurance"))
        end)

        it("endurance while channelling Warpath is NOT triggered by wrong skill", function()
            build.configTab.input.customMods = "10% Endurance while channelling Warpath"
            build.configTab:BuildModList()
            runCallback("OnFrame")
            -- ChannellingGhostflame condition should not activate the Warpath-tagged mod.
            local cfg = { skillCond = { ChannellingGhostflame = true } }
            assert.are.equals(0, build.configTab.modList:Sum("BASE", cfg, "Endurance"))
        end)

        it("ward per second while channeling Ghostflame (American spelling)", function()
            build.configTab.input.customMods = "+50 Ward per Second while channeling Ghostflame"
            build.configTab:BuildModList()
            runCallback("OnFrame")
            local cfg = { skillCond = { ChannellingGhostflame = true } }
            assert.are.equals(50, build.configTab.modList:Sum("BASE", cfg, "WardPerSecond"))
        end)

        it("ward per second while channelling Ghostflame (British spelling)", function()
            build.configTab.input.customMods = "+50 Ward per Second while channelling Ghostflame"
            build.configTab:BuildModList()
            runCallback("OnFrame")
            local cfg = { skillCond = { ChannellingGhostflame = true } }
            assert.are.equals(50, build.configTab.modList:Sum("BASE", cfg, "WardPerSecond"))
        end)
    end)

    describe("buff-conditional stat scaling (while you have X)", function()
        it("increased damage while you have Lightning Aegis — gated by HaveLightningAegis", function()
            build.configTab.input.customMods = "19% Increased Damage while you have Lightning Aegis"
            build.configTab:BuildModList()
            runCallback("OnFrame")
            assert.are.equals(0, build.configTab.modList:Sum("INC", nil, "Damage"))
            local cfg = { skillCond = { HaveLightningAegis = true } }
            assert.are.equals(19, build.configTab.modList:Sum("INC", cfg, "Damage"))
        end)

        it("increased damage while you have Frenzy — gated by Frenzy condition", function()
            build.configTab.input.customMods = "30% Increased Damage while you have Frenzy"
            build.configTab:BuildModList()
            runCallback("OnFrame")
            assert.are.equals(0, build.configTab.modList:Sum("INC", nil, "Damage"))
            local cfg = { skillCond = { Frenzy = true } }
            assert.are.equals(30, build.configTab.modList:Sum("INC", cfg, "Damage"))
        end)

        it("increased damage while you have Haste — gated by Haste condition", function()
            build.configTab.input.customMods = "25% Increased Damage while you have Haste"
            build.configTab:BuildModList()
            runCallback("OnFrame")
            assert.are.equals(0, build.configTab.modList:Sum("INC", nil, "Damage"))
            local cfg = { skillCond = { Haste = true } }
            assert.are.equals(25, build.configTab.modList:Sum("INC", cfg, "Damage"))
        end)
    end)

    describe("per active/equipped multipliers", function()
        it("increased damage per active Rune scales with Multiplier:ActiveRune", function()
            build.configTab.input.customMods = "10% Increased Damage per active Rune"
            build.configTab:BuildModList()
            runCallback("OnFrame")
            -- Zero without multiplier set
            assert.are.equals(0, build.configTab.modList:Sum("INC", nil, "Damage"))
            -- With 3 active runes: 10 * 3 = 30
            build.configTab.modList.multipliers["ActiveRune"] = 3
            assert.are.equals(30, build.configTab.modList:Sum("INC", nil, "Damage"))
            build.configTab.modList.multipliers["ActiveRune"] = nil
        end)

        it("increased damage per active Dread Shade scales with Multiplier:ActiveDreadShade", function()
            build.configTab.input.customMods = "15% Increased Damage per active Dread Shade"
            build.configTab:BuildModList()
            runCallback("OnFrame")
            build.configTab.modList.multipliers["ActiveDreadShade"] = 2
            assert.are.equals(30, build.configTab.modList:Sum("INC", nil, "Damage"))
            build.configTab.modList.multipliers["ActiveDreadShade"] = nil
        end)

        it("increased damage per active Wandering Spirit scales with multiplier", function()
            build.configTab.input.customMods = "8% Increased Damage per active Wandering Spirit"
            build.configTab:BuildModList()
            runCallback("OnFrame")
            build.configTab.modList.multipliers["ActiveWanderingSpirit"] = 4
            assert.are.equals(32, build.configTab.modList:Sum("INC", nil, "Damage"))
            build.configTab.modList.multipliers["ActiveWanderingSpirit"] = nil
        end)

        it("increased damage per equipped Omen Idol scales with multiplier", function()
            build.configTab.input.customMods = "5% Increased Damage per equipped Omen Idol"
            build.configTab:BuildModList()
            runCallback("OnFrame")
            build.configTab.modList.multipliers["EquippedOmenIdol"] = 4
            assert.are.equals(20, build.configTab.modList:Sum("INC", nil, "Damage"))
            build.configTab.modList.multipliers["EquippedOmenIdol"] = nil
        end)

        it("increased damage per equipped Weaver Item scales with multiplier", function()
            build.configTab.input.customMods = "7% Increased Damage per equipped Weaver Item"
            build.configTab:BuildModList()
            runCallback("OnFrame")
            build.configTab.modList.multipliers["EquippedWeaverItem"] = 3
            assert.are.equals(21, build.configTab.modList:Sum("INC", nil, "Damage"))
            build.configTab.modList.multipliers["EquippedWeaverItem"] = nil
        end)
    end)

    describe("per arrow/projectile scaling", function()
        it("increased damage per arrow with Multishot — skill-gated + multiplier", function()
            build.configTab.input.customMods = "11% Increased Damage per arrow with Multishot"
            build.configTab:BuildModList()
            runCallback("OnFrame")
            -- No multiplier, no skill cfg: zero
            assert.are.equals(0, build.configTab.modList:Sum("INC", nil, "Damage"))
            -- Multiplier set but skill mismatch: still zero (SkillName gate)
            build.configTab.modList.multipliers["ArrowsWithMultishot"] = 5
            assert.are.equals(0, build.configTab.modList:Sum("INC", { skillName = "Volley" }, "Damage"))
            -- Multishot context: 11 * 5 = 55
            assert.are.equals(55, build.configTab.modList:Sum("INC", { skillName = "Multishot" }, "Damage"))
            build.configTab.modList.multipliers["ArrowsWithMultishot"] = nil
        end)

        it("increased area per Projectile scales with ProjectileCountConfig multiplier", function()
            build.configTab.input.customMods = "35% Increased Area per Projectile"
            build.configTab:BuildModList()
            runCallback("OnFrame")
            assert.are.equals(0, build.configTab.modList:Sum("INC", nil, "AreaOfEffect"))
            build.configTab.modList.multipliers["ProjectileCountConfig"] = 3
            assert.are.equals(105, build.configTab.modList:Sum("INC", nil, "AreaOfEffect"))
            build.configTab.modList.multipliers["ProjectileCountConfig"] = nil
        end)

        it("mana cost per Additional Totem Summoned scales with AdditionalTotem multiplier", function()
            build.configTab.input.customMods = "+15 Mana Cost per Additional Totem Summoned"
            build.configTab:BuildModList()
            runCallback("OnFrame")
            build.configTab.modList.multipliers["AdditionalTotem"] = 2
            assert.are.equals(30, build.configTab.modList:Sum("BASE", nil, "ManaCost"))
            build.configTab.modList.multipliers["AdditionalTotem"] = nil
        end)
    end)

    describe("ailment/charge application on hit", function()
        it("Chance to apply Frailty on Hit feeds FrailtyChance with Hit flag", function()
            build.configTab.input.customMods = "+12% Chance to apply Frailty on Hit"
            build.configTab:BuildModList()
            runCallback("OnFrame")
            -- Hit-flagged context sums the chance
            assert.are.equals(12, build.configTab.modList:Sum("BASE", { flags = ModFlag.Hit }, "FrailtyChance"))
        end)

        it("Chance to inflict Plague on Hit feeds PlagueChance with Hit flag", function()
            build.configTab.input.customMods = "+8% Chance to inflict Plague on Hit"
            build.configTab:BuildModList()
            runCallback("OnFrame")
            assert.are.equals(8, build.configTab.modList:Sum("BASE", { flags = ModFlag.Hit }, "PlagueChance"))
        end)

        it("Chance to apply Poison on Hit feeds PoisonChance with Hit flag", function()
            build.configTab.input.customMods = "+25% Chance to apply Poison on Hit"
            build.configTab:BuildModList()
            runCallback("OnFrame")
            assert.are.equals(25, build.configTab.modList:Sum("BASE", { flags = ModFlag.Hit }, "PoisonChance"))
        end)
    end)

    describe("damage-taken reductions with source", function()
        it("reduced Bonus Damage Taken from Critical Strikes feeds ReduceCritExtraDamage", function()
            build.configTab.input.customMods = "3% reduced Bonus Damage Taken from Critical Strikes"
            build.configTab:BuildModList()
            runCallback("OnFrame")
            assert.are.equals(3, build.configTab.modList:Sum("BASE", nil, "ReduceCritExtraDamage"))
        end)

        it("less Physical Damage Taken reduces PhysicalDamageTaken", function()
            build.configTab.input.customMods = "5% less Physical Damage Taken"
            build.configTab:BuildModList()
            runCallback("OnFrame")
            -- "less" applies as MORE with negative sign
            assert.are.equals(-5, build.configTab.modList:Sum("MORE", nil, "PhysicalDamageTaken"))
        end)

        it("less Damage Taken from Chilled Enemies gates via ActorCondition", function()
            build.configTab.input.customMods = "8% less Damage Taken from Chilled Enemies"
            build.configTab:BuildModList()
            runCallback("OnFrame")
            -- Without enemy-chilled condition: no reduction
            assert.are.equals(0, build.configTab.modList:Sum("MORE", nil, "DamageTaken"))
            -- Mod exists in modList (recognised + not nsAny-swallowed)
            local found = false
            for _, m in ipairs(build.configTab.modList) do
                if m.name == "DamageTaken" and m.value == -8 then
                    found = true
                    break
                end
            end
            assert.is_true(found)
        end)
    end)

    describe("resource conversion (Mana to Ward)", function()
        it("X% of Mana Spent Gained as Ward emits ManaSpentGainedAsWard", function()
            build.configTab.input.customMods = "40% of Mana Spent Gained as Ward"
            build.configTab:BuildModList()
            runCallback("OnFrame")
            assert.are.equals(40, build.configTab.modList:Sum("BASE", nil, "ManaSpentGainedAsWard"))
        end)

        it("unknown spent-gained combo still recognised (nsAny fallback, no ManaSpentGainedAsWard)", function()
            build.configTab.input.customMods = "10% of Rage Spent Gained as Frenzy"
            build.configTab:BuildModList()
            runCallback("OnFrame")
            -- Not the known Mana->Ward path
            assert.are.equals(0, build.configTab.modList:Sum("BASE", nil, "ManaSpentGainedAsWard"))
            -- But the mod is recognised (not an error)
            local found = false
            for _, m in ipairs(build.configTab.modList) do
                if m.name == "LEB_NotSupported" then
                    found = true
                    break
                end
            end
            assert.is_true(found)
        end)
    end)

    describe("+N to <skill> skill level", function()
        it("+N to <skill> emits SkillLevel tagged with SkillName", function()
            build.configTab.input.customMods = "+3 to Flame Ward"
            build.configTab:BuildModList()
            runCallback("OnFrame")
            -- Untagged sum (global) is 0: mod is gated by SkillName tag
            assert.are.equals(0, build.configTab.modList:Sum("BASE", nil, "SkillLevel"))
            -- With matching skill cfg: value applies
            local cfg = { skillName = "Flame Ward" }
            assert.are.equals(3, build.configTab.modList:Sum("BASE", cfg, "SkillLevel"))
            -- With non-matching skill cfg: no bonus
            local cfg2 = { skillName = "Fireball" }
            assert.are.equals(0, build.configTab.modList:Sum("BASE", cfg2, "SkillLevel"))
        end)

        it("+N to non-skill name (e.g. Strength) falls through to generic stat mod", function()
            build.configTab.input.customMods = "+5 to Strength"
            build.configTab:BuildModList()
            runCallback("OnFrame")
            -- Should NOT emit SkillLevel
            assert.are.equals(0, build.configTab.modList:Sum("BASE", nil, "SkillLevel"))
            -- Should apply as Str (generic parse chain)
            assert.are.equals(5, build.configTab.modList:Sum("BASE", nil, "Str"))
        end)
    end)

    -- Regression guard: in-game stat parity invariants from determined-hawking-2a827c.
    -- These tests exist to catch a class of regressions where ModCache.lua and the
    -- ModParser drift apart and re-introduce the ShutFackUp Health=1423 (vs in-game
    -- 1572) bug. If any of these fail, regenerate ModCache.lua via the headless
    -- regen flow before investigating ModParser changes.
    describe("in-game stat parity (regression guard)", function()
        it("'+N% Health' is INC, not BASE (ModCache regression marker)", function()
            build.configTab.input.customMods = "+10% Health"
            build.configTab:BuildModList()
            runCallback("OnFrame")
            assert.are.equals(10, build.configTab.modList:Sum("INC", nil, "Life"))
            assert.are.equals(0, build.configTab.modList:Sum("BASE", nil, "Life"))
        end)

        it("'+N Additional Health Per M Vitality' carries PerStat tag", function()
            build.configTab.input.customMods = "+1 Additional Health Per 2 Vitality"
            build.configTab:BuildModList()
            runCallback("OnFrame")
            local found
            for _, m in ipairs(build.configTab.modList) do
                if m.name == "Life" and m.type == "BASE" and m.value == 1 then
                    found = m
                    break
                end
            end
            assert.is_not_nil(found, "Life BASE mod (value 1) not found")
            assert.is_not_nil(found[1], "PerStat tag missing on Life mod")
            assert.are.equals("PerStat", found[1].type)
            assert.are.equals(2, found[1].div)
            assert.are.equals("Vit", found[1].stat)
        end)

        it("PerStat scales Life by Vitality (continuous, not floored at mod level)", function()
            -- Without scaling mod: baseline Life from +50 Vit alone
            build.configTab.input.customMods = "+50 Vitality"
            build.configTab:BuildModList()
            build.buildFlag = true
            runCallback("OnFrame")
            local baseline = build.calcsTab.calcsOutput.Life

            build.configTab.input.customMods = "+50 Vitality\n+1 Additional Health Per 2 Vitality"
            build.configTab:BuildModList()
            build.buildFlag = true
            runCallback("OnFrame")
            -- 50 Vit / 2 = 25 extra Life
            assert.are.equals(baseline + 25, build.calcsTab.calcsOutput.Life)
        end)

        it("'Crit Multi While At Low Health' does NOT match a Life mod", function()
            -- Guards against ModCache entries that erroneously parse low-health
            -- conditional crit-multi as a flat Life BASE/INC.
            build.configTab.input.customMods = "+10% Crit Multi While At Low Health"
            build.configTab:BuildModList()
            runCallback("OnFrame")
            assert.are.equals(0, build.configTab.modList:Sum("BASE", nil, "Life"))
            assert.are.equals(0, build.configTab.modList:Sum("INC", nil, "Life"))
        end)

        -- @leb-regression-guard: idol-altar-not-idol-slot
        -- Two-part guard:
        --  (1) CalcSetup must NOT classify the "Idol Altar" equipment slot as
        --      an idol slot (the corrupted altar feeds
        --      CorruptedNonIdolItemsEquipped, not CorruptedIdolItemsEquipped).
        --  (2) CalcPerform must publish CorruptedItemsEquipped /
        --      CorruptedNonIdolItemsEquipped / CorruptedIdolItemsEquipped onto
        --      `output` BEFORE the Attributes loop, so StatThreshold tags
        --      (resolved via ModStore:GetStat reading actor.output[stat])
        --      observe the correct count and the
        --      "+N to All Attributes with at least N Corrupted non-Idol Items
        --      equipped" affix (Shroud of Obscurity) trips.
        -- Establishing build: Qqwv73q2 lv62 Warlock — LEB Vit 35 → 49 after fix
        -- (still differs from LETools 44 by remaining CompleteSetCount bug B).
        it("Corrupted Idol Altar counts as non-Idol for CorruptedNonIdolItemsEquipped", function()
            -- Character must clear LevelReq filter (CalcSetup nulls items
            -- whose requirements.level > characterLevel).
            build.characterLevel = 99

            -- Equip a corrupted Idol Altar; nothing else corrupted.
            build.itemsTab:CreateDisplayItemFromRaw([[Rarity: RARE
            Test Corrupted Altar
            Archaic Altar
            Unique ID: 123
            LevelReq: 50
            Implicits: 0
            Corrupted]])
            -- AddDisplayItem with noAutoEquip then manually equip into the
            -- Idol Altar slot (auto-equip relies on slot:IsShown() which
            -- returns false in headless tests).
            build.itemsTab:AddDisplayItem(true)
            local altarItemId
            for id, it in pairs(build.itemsTab.items) do
                if it.baseName == "Archaic Altar" then altarItemId = id; break end
            end
            assert.is_not_nil(altarItemId, "altar item should be in items list")
            assert.is_not_nil(build.itemsTab.slots["Idol Altar"], "Idol Altar slot should exist")
            build.itemsTab.slots["Idol Altar"]:SetSelItemId(altarItemId)
            build.itemsTab:PopulateSlots()

            -- Inject the Shroud-style threshold mod via customMods so we don't
            -- depend on a specific unique's affix roll.
            build.configTab.input.customMods =
                "+14 to All Attributes with at least 1 Corrupted non-Idol Items equipped"
            build.configTab:BuildModList()
            build.buildFlag = true
            runCallback("OnFrame")

            -- (1) Counter classification: altar in non-idol bucket.
            assert.are.equals(1, build.calcsTab.mainOutput.CorruptedNonIdolItemsEquipped)
            assert.are.equals(0, build.calcsTab.mainOutput.CorruptedIdolItemsEquipped)
            assert.are.equals(1, build.calcsTab.mainOutput.CorruptedItemsEquipped)

            -- (2) StatThreshold trips — base Vit (no class) 0 + threshold +14 = 14.
            assert.are.equals(14, build.calcsTab.mainOutput.Vit)

            -- (3) Negative case: with no corrupted items the threshold must NOT
            -- trip. Remove the altar and rebuild — Vit drops back to base.
            build.itemsTab.slots["Idol Altar"]:SetSelItemId(0)
            build.itemsTab:PopulateSlots()
            build.buildFlag = true
            runCallback("OnFrame")
            assert.are.equals(0, build.calcsTab.mainOutput.CorruptedNonIdolItemsEquipped or 0)
            assert.are.equals(0, build.calcsTab.mainOutput.Vit)
        end)

        -- @leb-regression-guard: corrupted-count-pre-levelreq
        -- Equipped semantics: a level-gated item still occupies its slot in
        -- game (stats inactive) and counts toward "with at least N Corrupted
        -- ... Items equipped" thresholds. CalcSetup must capture every
        -- level-gated item into env._levelGatedAllItems and include it in
        -- the corrupted-counter loop.
        -- Establishing build: Qqwv73q2 lv62 Warlock — Silver Grail relic
        -- (LevelReq=68 > charLevel=62) brings nonIdol from 6 to 7 → trips
        -- Shroud of Obscurity's +11 All Attributes (affix 1011_6).
        it("Level-gated corrupted item still counts toward CorruptedNonIdolItemsEquipped", function()
            -- Character below the relic's LevelReq (68), so LevelReq filter
            -- nulls it from `items[]`. Without the fix, corrupted counter
            -- iterates the post-filter table and misses the relic.
            build.characterLevel = 62

            -- Equip a corrupted relic with LevelReq=68 (will be level-gated).
            build.itemsTab:CreateDisplayItemFromRaw([[Rarity: RARE
            Test Corrupted Relic
            Silver Grail
            Unique ID: 1
            LevelReq: 68
            Implicits: 0
            Corrupted]])
            build.itemsTab:AddDisplayItem(true)
            local relicItemId
            for id, it in pairs(build.itemsTab.items) do
                if it.baseName == "Silver Grail" then relicItemId = id; break end
            end
            assert.is_not_nil(relicItemId, "relic item should be in items list")
            assert.is_not_nil(build.itemsTab.slots["Relic"], "Relic slot should exist")
            build.itemsTab.slots["Relic"]:SetSelItemId(relicItemId)
            build.itemsTab:PopulateSlots()

            -- Threshold of 1 — only the level-gated relic is corrupted.
            -- If the fix is regressed, count=0 → threshold not met → Vit=0.
            -- With fix, count=1 → threshold met → Vit gets +14.
            build.configTab.input.customMods =
                "+14 to All Attributes with at least 1 Corrupted non-Idol Items equipped"
            build.configTab:BuildModList()
            build.buildFlag = true
            runCallback("OnFrame")

            assert.are.equals(1, build.calcsTab.mainOutput.CorruptedNonIdolItemsEquipped)
            assert.are.equals(14, build.calcsTab.mainOutput.Vit)
        end)

        it("maxHealth uses floor (truncation), matching in-game (1258 * 1.25 = 1572)", function()
            -- ShutFackUp lv85 Spellblade scenario reduced to customMods:
            -- 110 (default base) + 1148 = 1258 base, * 1.25 INC = 1572.5
            -- floor -> 1572 (in-game). round -> 1573 (LETools). LEB must match in-game.
            build.configTab.input.customMods = "+1148 Health\n25% increased Health"
            build.configTab:BuildModList()
            build.buildFlag = true
            runCallback("OnFrame")
            assert.are.equals(1572, build.calcsTab.calcsOutput.Life)
        end)
    end)

    -- @leb-regression-guard: regen-pct-shorthand-inc
    -- Locks in ModParser BASE_MORE classification for ManaRegen/LifeRegen.
    -- LE in-game text shorthand "+N% Mana Regen" / "+N% Health Regen" (without
    -- "increased") must be parsed as INC, matching the existing Life/Mana/Ward
    -- exception. The game's authoritative localized_master.json affix 1015
    -- affixProperties[1] (Mana Regen) is modifierType=1 (INC) with extraRolls
    -- stored as 0.08-0.09 (= 8-9% multiplier). Without this, Keplahan's Cryolith
    -- Reforged ring sealed affix +(8-9)% Mana Regen is treated as flat +8 BASE,
    -- causing ~+15.5/s drift (Qqwv73q2: LE 16.72 vs LEB 32.20 prior to fix).
    -- Establishing commit: <unset; bump after first commit on this branch>.
    it("LE shorthand '+N% Mana Regen' parses as INC", function()
        build.configTab.input.customMods = "+8% Mana Regen"
        build.configTab:BuildModList()
        runCallback("OnFrame")
        assert.are.equals(0, build.configTab.modList:Sum("BASE", nil, "ManaRegen"),
            "Bare '+8% Mana Regen' must NOT add flat BASE Mana Regen")
        assert.are.equals(8, build.configTab.modList:Sum("INC", nil, "ManaRegen"),
            "Bare '+8% Mana Regen' must contribute +8% INC Mana Regen")
    end)

    it("LE shorthand '+N% Health Regen' parses as INC", function()
        build.configTab.input.customMods = "+12% Health Regen"
        build.configTab:BuildModList()
        runCallback("OnFrame")
        assert.are.equals(0, build.configTab.modList:Sum("BASE", nil, "LifeRegen"),
            "Bare '+12% Health Regen' must NOT add flat BASE Life Regen")
        assert.are.equals(12, build.configTab.modList:Sum("INC", nil, "LifeRegen"),
            "Bare '+12% Health Regen' must contribute +12% INC Life Regen")
    end)

    -- @leb-regression-guard: butchers-crown-no-mana-regen
    -- The Butcher's Crown (uniqueID=449) zeros mana regen. In-game tooltip is
    -- "You do not Regenerate Mana"; LEB unique JSON variant is
    -- "100% Disabled Mana Regen". Both must produce a NoManaRegen FLAG, not a
    -- BASE ManaRegen mod. CalcDefence.lua:602 reads NoManaRegen and forces
    -- output.ManaRegen = 0. Without this guard the BASE_MORE form ("100%")
    -- collapses the LEB JSON variant into +100 BASE ManaRegen (boost), the
    -- opposite of intent (~+87.4 mana/s drift on QDxZPWM9 lv99 Sorcerer).
    -- Establishing commit: <unset; bump after first commit on this branch>.
    it("'You do not Regenerate Mana' sets NoManaRegen flag", function()
        build.configTab.input.customMods = "You do not Regenerate Mana"
        build.configTab:BuildModList()
        runCallback("OnFrame")
        assert.is_true(build.configTab.modList:Flag(nil, "NoManaRegen"),
            "'You do not Regenerate Mana' must set NoManaRegen flag")
        assert.are.equals(0, build.configTab.modList:Sum("BASE", nil, "ManaRegen"),
            "Must NOT add flat BASE ManaRegen")
    end)

    it("'100% Disabled Mana Regen' (LEB JSON variant) sets NoManaRegen flag", function()
        build.configTab.input.customMods = "100% Disabled Mana Regen"
        build.configTab:BuildModList()
        runCallback("OnFrame")
        assert.is_true(build.configTab.modList:Flag(nil, "NoManaRegen"),
            "'100% Disabled Mana Regen' must set NoManaRegen flag")
        assert.are.equals(0, build.configTab.modList:Sum("BASE", nil, "ManaRegen"),
            "Must NOT add +100 BASE ManaRegen (the bug being guarded)")
    end)
end)
