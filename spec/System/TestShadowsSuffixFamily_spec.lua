-- @leb-regression-guard: shadow-suffix-family
-- Locks parser + ModCache for the Bladedancer Shadow suffix family. This
-- spec is incrementally extended across sub-commits C6a..C6f. Each sub
-- locks one pattern cluster from the 14-pattern Shadows inventory:
--   * C6a: P2 (per Shadow scaling), P4 (Maximum Shadows stat), P6 (At
--          Least N Shadows threshold)        — 7 entries
--   * C6b: P1 (for skills used by Shadows), P7 (for Shadow Attack)
--   * C6c: P3 (Gained on Shadow Creation), P5 (Subsequent Shadows
--          Consumed), P8 (Dusk Shroud on Shadow consume)
--   * C6d: P9 (with Shadow Daggers residue), P13 (Shadow keyword scope)
--   * C6e: P10/P11/P12 (notSupported tagging)
--   * C6f: P14 (Lethal Mirage Shadow Dagger composite)

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("ShadowSuffixFamily", function()
    local parserText, cacheText

    setup(function()
        parserText = readSource("Modules/ModParser.lua")
        cacheText  = readSource("Data/ModCache.lua")
    end)

    ----------------------------------------------------------------------
    -- C6a: P2 + P4 + P6
    ----------------------------------------------------------------------

    it("C6a: ModParser registers bare 'per shadow' Multiplier suffix", function()
        local needle = '%["per shadow"%]%s*=%s*{%s*tag%s*=%s*{%s*type%s*=%s*"Multiplier",%s*var%s*=%s*"ActiveShadow"%s*}%s*}'
        assert.is_truthy(string.find(parserText, needle),
            "ModParser must register ['per shadow'] = Multiplier:ActiveShadow")
    end)

    it("C6a: ModParser registers 'with at least 3 shadows' MultiplierThreshold suffix", function()
        local needle = '%["with at least 3 shadows"%]%s*=%s*{%s*tag%s*=%s*{%s*type%s*=%s*"MultiplierThreshold",%s*var%s*=%s*"ActiveShadow",%s*threshold%s*=%s*3%s*}%s*}'
        assert.is_truthy(string.find(parserText, needle),
            "ModParser must register ['with at least 3 shadows'] = MultiplierThreshold")
    end)

    it("C6a: ModParser modNameList maps 'maximum shadows' and 'max shadows' to MaxShadows", function()
        assert.is_truthy(string.find(parserText, '%["maximum shadows"%]%s*=%s*"MaxShadows"'),
            "must map 'maximum shadows' -> 'MaxShadows'")
        assert.is_truthy(string.find(parserText, '%["max shadows"%]%s*=%s*"MaxShadows"'),
            "must map 'max shadows' -> 'MaxShadows'")
    end)

    it("C6a: ModCache: 'per Shadow' scaling entries carry Multiplier:ActiveShadow with empty residue", function()
        local entries = {
            { key = '%+10%% Damage Per Shadow', name = "Damage", typ = "MORE", value = 10 },
            { key = '%+15%% Area Per Shadow', name = "AreaOfEffect", typ = "BASE", value = 15 },
            { key = '%+3%% Damage Per Shadow', name = "Damage", typ = "MORE", value = 3 },
        }
        for _, e in ipairs(entries) do
            local needle = 'c%["' .. e.key .. '"%]={{%[1%]={%[1%]={type="Multiplier",var="ActiveShadow"},flags=0,keywordFlags=0,name="' .. e.name .. '",type="' .. e.typ .. '",value=' .. e.value .. '}},""}'
            assert.is_truthy(string.find(cacheText, needle),
                "missing Multiplier:ActiveShadow tag with empty residue: " .. e.key)
        end
    end)

    it("C6a: ModCache: Maximum Shadows entries parse to MaxShadows BASE with empty residue", function()
        local entries = {
            { key = '%+1 Maximum Shadows', value = 1 },
            { key = '%+1 max Shadows', value = 1 },
            { key = '%+2 Maximum Shadows', value = 2 },
        }
        for _, e in ipairs(entries) do
            local needle = 'c%["' .. e.key .. '"%]={{%[1%]={flags=0,keywordFlags=0,name="MaxShadows",type="BASE",value=' .. e.value .. '}},""}'
            assert.is_truthy(string.find(cacheText, needle),
                "must parse to MaxShadows BASE: " .. e.key)
        end
    end)

    it("C6a: ModCache: '+20% Damage With At Least 3 Shadows' carries MultiplierThreshold tag", function()
        local needle = 'c%["%+20%% Damage With At Least 3 Shadows"%]={{%[1%]={%[1%]={threshold=3,type="MultiplierThreshold",var="ActiveShadow"},flags=0,keywordFlags=0,name="Damage",type="MORE",value=20}},""}'
        assert.is_truthy(string.find(cacheText, needle),
            "must carry MultiplierThreshold:ActiveShadow threshold=3")
    end)

    ----------------------------------------------------------------------
    -- C6b: P1 (for skills used by Shadows) + P7 (for Shadow Attack)
    ----------------------------------------------------------------------

    it("C6b: ModParser registers 'for skills used by shadows' as ShadowClone MinionType (F3+F9 supersession)", function()
        -- The original Scope:minion placeholder was superseded by F3+F9
        -- (shadow-minion-scope guard) into MinionModifier LIST via
        -- addToMinion=true + addToMinionTypes={"ShadowClone"}.
        local needle = '%["for skills used by shadows"%]%s*=%s*{%s*addToMinion%s*=%s*true,%s*addToMinionTypes%s*=%s*{%s*"ShadowClone"%s*}%s*}'
        assert.is_truthy(string.find(parserText, needle),
            "ModParser must register ['for skills used by shadows'] = MinionType:ShadowClone")
    end)

    it("C6b: ModParser registers 'for shadow attack' Condition: ShadowAttack", function()
        local needle = '%["for shadow attack"%]%s*=%s*{%s*tag%s*=%s*{%s*type%s*=%s*"Condition",%s*var%s*=%s*"ShadowAttack"%s*}%s*}'
        assert.is_truthy(string.find(parserText, needle),
            "ModParser must register ['for shadow attack'] = Condition:ShadowAttack")
    end)

    it("C6b: ModCache: '+15% Increased Damage for skills used by Shadows' carries MinionModifier:ShadowClone (F3+F9)", function()
        local needle = 'c%["%+15%% Increased Damage for skills used by Shadows"%]={{%[1%]={flags=0,keywordFlags=0,name="MinionModifier",type="LIST",value={minionTypes={%[1%]="ShadowClone"},mod={flags=0,keywordFlags=0,name="Damage",type="INC",value=15}}}},""}'
        assert.is_truthy(string.find(cacheText, needle))
    end)

    it("C6b: ModCache: '+10% Critical Strike Chance for skills used by Shadows' carries MinionModifier:ShadowClone (F3+F9)", function()
        local needle = 'c%["%+10%% Critical Strike Chance for skills used by Shadows"%]={{%[1%]={flags=0,keywordFlags=0,name="MinionModifier",type="LIST",value={minionTypes={%[1%]="ShadowClone"},mod={flags=0,keywordFlags=0,name="CritChance",type="BASE",value=10}}}},""}'
        assert.is_truthy(string.find(cacheText, needle))
    end)

    it("C6b: ModCache: all 35 percent 'for skills used by Shadows' entries carry MinionModifier:ShadowClone with empty residue (F3+F9)", function()
        -- Sweep: no full-% entry should retain residue containing 'for skills used by Shadows'
        local count = 0
        for _ in cacheText:gmatch('c%["[+]?[%d.]+%% [^"]-for skills used by Shadows"%]={{%[1%]={flags=0,keywordFlags=0,name="MinionModifier",type="LIST",value={minionTypes={%[1%]="ShadowClone"}') do
            count = count + 1
        end
        assert.is_true(count >= 35,
            "expected at least 35 percent-form P1 entries with MinionModifier:ShadowClone, got " .. count)
    end)

    -- C6b's 3 '+N Increased Damage' no-% entries originally carried BASE + " Increased " residue.
    -- C6-followup F2 promotes them to INC; the corresponding assertion lives in the followup
    -- section below. This placeholder is retained as documentation of the original C6b scope.
    it("C6b: 3 '+N Increased Damage' entries are tracked under C6-followup F2 (originally deferred)", function()
        assert.is_truthy(true)
    end)

    it("C6b: ModCache: '+12% Melee Area for Shadow Attack' carries Condition:ShadowAttack with empty residue", function()
        local needle = 'c%["%+12%% Melee Area for Shadow Attack"%]={{%[1%]={%[1%]={type="Condition",var="ShadowAttack"},flags=0,keywordFlags=512,name="AreaOfEffect",type="BASE",value=12}},""}'
        assert.is_truthy(string.find(cacheText, needle))
    end)

    it("C6b: ModCache: '+50% Shadow Daggers Chance for Shadow Attack' carries Condition:ShadowAttack", function()
        local needle = 'c%["%+50%% Shadow Daggers Chance for Shadow Attack"%]={{%[1%]={%[1%]={type="Condition",var="ShadowAttack"},flags=8388608,keywordFlags=0,name="ChanceToTriggerOnHit_Ailment_ShadowDaggers",type="BASE",value=50}},""}'
        assert.is_truthy(string.find(cacheText, needle))
    end)

    it("C6b: ModCache: 'Doubled for Shadow Attack' entries gated with Condition:ShadowAttack + mult=2 (F4 supersession)", function()
        -- F4 (condition-tag-mult + doubled-for-shadow-attack guards) rewrote
        -- the Doubled clause from a residue+separate-mod shape into a single
        -- Condition tag carrying mult=2.

        -- +25% Bleed Chance, Doubled for Shadow Attack
        local needle = 'c%["%+25%% Bleed Chance, Doubled for Shadow Attack"%]={{%[1%]={%[1%]={mult=2,type="Condition",var="ShadowAttack"},flags=8388608,keywordFlags=0,name="ChanceToTriggerOnHit_Ailment_Bleed",type="BASE",value=25}},""}'
        assert.is_truthy(string.find(cacheText, needle),
            "Bleed Chance Doubled entry must carry Condition:ShadowAttack with mult=2")
        -- +34# Armor Shred Chance for Shadow Attack, Doubled with Bow
        needle = 'c%["%+34# Armor Shred Chance for Shadow Attack, Doubled with Bow"%]={{%[1%]={%[1%]={type="Condition",var="ShadowAttack"},%[2%]={mult=2,type="Condition",var="UsingBow"}'
        assert.is_truthy(string.find(cacheText, needle),
            "Armor Shred Doubled-with-Bow entry must carry ShadowAttack + UsingBow(mult=2)")
    end)

    ----------------------------------------------------------------------
    -- C6c: P3 (Gained on Shadow Creation) + P5 (Subsequent Shadows Consumed)
    --      + P8 (Dusk Shroud on consume) + C6a-deferred Mana/Ward Gain
    ----------------------------------------------------------------------

    it("C6c: ModParser registers OnShadowCreate / OnShadowConsume trigger gates", function()
        local needles = {
            '%["gained on shadow creation"%]%s*=%s*{%s*tag%s*=%s*{%s*type%s*=%s*"Condition",%s*var%s*=%s*"OnShadowCreate"',
            '%["gain on shadow creation"%]%s*=%s*{%s*tag%s*=%s*{%s*type%s*=%s*"Condition",%s*var%s*=%s*"OnShadowCreate"',
            '%["gain per shadow"%]%s*=%s*{%s*tag%s*=%s*{%s*type%s*=%s*"Condition",%s*var%s*=%s*"OnShadowCreate"',
            '%["from subsequent shadows consumed"%]%s*=%s*{%s*tag%s*=%s*{%s*type%s*=%s*"Condition",%s*var%s*=%s*"OnShadowConsume"',
            '%["when you consume a shadow"%]%s*=%s*{%s*tag%s*=%s*{%s*type%s*=%s*"Condition",%s*var%s*=%s*"OnShadowConsume"',
        }
        for _, n in ipairs(needles) do
            assert.is_truthy(string.find(parserText, n), "missing parser registration: " .. n)
        end
    end)

    it("C6c: ModCache: '+110 Health Gained on Shadow Creation' carries OnShadowCreate condition", function()
        local needle = 'c%["%+110 Health Gained on Shadow Creation"%]={{%[1%]={%[1%]={type="Condition",var="OnShadowCreate"},flags=0,keywordFlags=0,name="Life",type="BASE",value=110}},""}'
        assert.is_truthy(string.find(cacheText, needle))
    end)

    it("C6c: ModCache: '113 Ward Gained on Shadow Creation' carries OnShadowCreate condition", function()
        local needle = 'c%["113 Ward Gained on Shadow Creation"%]={{%[1%]={%[1%]={type="Condition",var="OnShadowCreate"},flags=0,keywordFlags=0,name="Ward",type="BASE",value=113}},""}'
        assert.is_truthy(string.find(cacheText, needle))
    end)

    it("C6c: ModCache: all 27 'Gain(ed) on Shadow Creation' entries carry OnShadowCreate gate", function()
        local count = 0
        for _ in cacheText:gmatch('Gain[a-z]* on Shadow Creation"%]={{%[1%]={%[1%]={type="Condition",var="OnShadowCreate"}') do
            count = count + 1
        end
        assert.is_true(count >= 27, "expected at least 27 P3 entries with OnShadowCreate, got " .. count)
    end)

    it("C6c: ModCache: '+3 Mana Gain Per Shadow' and '25 Ward Gain Per Shadow' carry OnShadowCreate (C6a-deferred)", function()
        local n1 = 'c%["%+3 Mana Gain Per Shadow"%]={{%[1%]={%[1%]={type="Condition",var="OnShadowCreate"},flags=0,keywordFlags=0,name="Mana",type="BASE",value=3}},""}'
        assert.is_truthy(string.find(cacheText, n1))
        local n2 = 'c%["25 Ward Gain Per Shadow"%]={{%[1%]={%[1%]={type="Condition",var="OnShadowCreate"},flags=0,keywordFlags=0,name="Ward",type="BASE",value=25}},""}'
        assert.is_truthy(string.find(cacheText, n2))
    end)

    it("C6c: ModCache: 'from Subsequent Shadows Consumed' entries carry OnShadowConsume", function()
        local n1 = 'c%["%+20%% Damage from Subsequent Shadows Consumed"%]={{%[1%]={%[1%]={type="Condition",var="OnShadowConsume"},flags=0,keywordFlags=0,name="Damage",type="MORE",value=20}},""}'
        assert.is_truthy(string.find(cacheText, n1))
        local n2 = 'c%["%+10%% Melee Area from Subsequent Shadows Consumed"%]={{%[1%]={%[1%]={type="Condition",var="OnShadowConsume"},flags=0,keywordFlags=512,name="AreaOfEffect",type="BASE",value=10}},""}'
        assert.is_truthy(string.find(cacheText, n2))
    end)

    it("C6c: ModCache: 7 'Chance to gain a stack of Dusk Shroud when you consume a Shadow' entries gated with OnShadowConsume", function()
        local count = 0
        for _ in cacheText:gmatch('Chance to gain a stack of Dusk Shroud when you consume a Shadow"%]={{%[1%]={%[1%]={type="Condition",var="OnShadowConsume"}') do
            count = count + 1
        end
        assert.is_true(count >= 7, "expected at least 7 P8 entries with OnShadowConsume, got " .. count)
    end)

    it("C6a: ModCache: no C6a entry retains stale residue", function()
        local keys = {
            '%+10%% Damage Per Shadow',
            '%+15%% Area Per Shadow',
            '%+3%% Damage Per Shadow',
            '%+1 Maximum Shadows',
            '%+1 max Shadows',
            '%+2 Maximum Shadows',
            '%+20%% Damage With At Least 3 Shadows',
        }
        for _, k in ipairs(keys) do
            local stale = 'c%["' .. k .. '"%]={{[^\n]-}},"[^"][^\n]*"}'
            assert.is_nil(string.find(cacheText, stale),
                "C6a entry must have empty residue: " .. k)
        end
    end)

    ----------------------------------------------------------------------
    -- C6d: P9 (with Shadow Daggers residue) + P13 (Shadow Damage gate)
    ----------------------------------------------------------------------

    it("C6d: ModParser registers 'with shadow daggers' SkillName suffix", function()
        local needle = '%["with shadow daggers"%]%s*=%s*{%s*tag%s*=%s*{%s*type%s*=%s*"SkillName",%s*skillName%s*=%s*"Shadow Daggers"%s*}%s*}'
        assert.is_truthy(string.find(parserText, needle),
            "ModParser must register ['with shadow daggers'] = SkillName:Shadow Daggers")
    end)

    it("C6d: ModParser modNameList maps 'shadow damage' to Damage scoped to ShadowClone minions", function()
        -- Superseded by shadow-damage-minion-scope: was Condition:ShadowDamageScope,
        -- now addToMinion=true + addToMinionTypes={"ShadowClone"} so the damage
        -- bonus is routed onto the Shadow minion modDB (MinionModifier LIST).
        local needle = '%["shadow damage"%]%s*=%s*{%s*"Damage",%s*addToMinion%s*=%s*true,%s*addToMinionTypes%s*=%s*{%s*"ShadowClone"%s*}%s*}'
        assert.is_truthy(string.find(parserText, needle),
            "ModParser must register ['shadow damage'] = Damage with addToMinion=true, addToMinionTypes={'ShadowClone'}")
    end)

    it("C6d: ModCache 'Physical Penetration with Shadow Daggers' entries carry SkillName tag with empty residue", function()
        for _, n in ipairs({ 13, 15, 20, 25, 26, 30, 39, 69, 89, 180 }) do
            local needle = 'c%["%+' .. n .. '%% Physical Penetration with Shadow Daggers"%]={{%[1%]={%[1%]={skillName="Shadow Daggers",type="SkillName"},flags=0,keywordFlags=0,name="PhysicalPenetration",type="BASE",value=' .. n .. '}},""}'
            assert.is_truthy(string.find(cacheText, needle),
                "+" .. n .. "% Physical Penetration with Shadow Daggers must carry SkillName tag and empty residue")
        end
    end)

    it("C6d: ModCache 'N% Increased Shadow Damage' entries carry MinionModifier LIST scoped to ShadowClone", function()
        -- Superseded by shadow-damage-minion-scope: was an unconditional Damage INC
        -- gated by Condition:ShadowDamageScope. The damage now lives on the Shadow
        -- minion modDB via a MinionModifier LIST wrapper, mirroring how every other
        -- "X for skills used by Shadows" line is plumbed.
        for _, n in ipairs({ 15, 20 }) do
            local needle = 'c%["' .. n .. '%% Increased Shadow Damage"%]={{%[1%]={flags=0,keywordFlags=0,name="MinionModifier",type="LIST",value={minionTypes={%[1%]="ShadowClone"},mod={flags=0,keywordFlags=0,name="Damage",type="INC",value=' .. n .. '}}}},""}'
            assert.is_truthy(string.find(cacheText, needle),
                n .. "% Increased Shadow Damage must carry MinionModifier LIST scoped to ShadowClone")
        end
    end)

    it("C6e: ModCache 'Physical Penetration with Shadow Daggers ' trailing-space variants carry SkillName tag with empty residue", function()
        for _, n in ipairs({ 23, 30, 37, 45, 59, 103, 134, 270 }) do
            local needle = 'c%["%+' .. n .. '%% Physical Penetration with Shadow Daggers "%]={{%[1%]={%[1%]={skillName="Shadow Daggers",type="SkillName"},flags=0,keywordFlags=0,name="PhysicalPenetration",type="BASE",value=' .. n .. '}},""}'
            assert.is_truthy(string.find(cacheText, needle),
                "+" .. n .. "% Physical Penetration with Shadow Daggers (trailing space) must carry SkillName tag and empty residue")
        end
    end)

    ----------------------------------------------------------------------
    -- C6f: P14 Lethal Mirage suffix family
    ----------------------------------------------------------------------

    it("C6f: ModParser registers 'with lethal mirage' SkillName suffix", function()
        local needle = '%["with lethal mirage"%]%s*=%s*{%s*tag%s*=%s*{%s*type%s*=%s*"SkillName",%s*skillName%s*=%s*"Lethal Mirage"%s*}%s*}'
        assert.is_truthy(string.find(parserText, needle),
            "ModParser must register ['with lethal mirage'] = SkillName:Lethal Mirage")
    end)

    it("C6f: ModParser registers 'of mirage attacks with lethal mirage' composite suffix", function()
        local needle = '%["of mirage attacks with lethal mirage"%]%s*=%s*{%s*tag%s*=%s*{%s*type%s*=%s*"SkillName",%s*skillName%s*=%s*"Lethal Mirage"%s*}%s*}'
        assert.is_truthy(string.find(parserText, needle))
    end)

    it("C6f: ModParser modNameList registers 'chance to apply a shadow dagger on hit'", function()
        local needle = '%["chance to apply a shadow dagger on hit"%]%s*=%s*"ChanceToApplyShadowDaggerOnHit"'
        assert.is_truthy(string.find(parserText, needle))
    end)

    it("C6f: ModCache 'Mana Efficiency with Lethal Mirage' entries carry SkillName tag with empty residue", function()
        for _, n in ipairs({ 12, 16, 20, 24, 28, 42, 54, 108 }) do
            local needle = 'c%["%+' .. n .. '%% Mana Efficiency with Lethal Mirage"%]={{%[1%]={%[1%]={skillName="Lethal Mirage",type="SkillName"},flags=0,keywordFlags=0,name="ManaEfficiency",type="INC",value=' .. n .. '}},""}'
            assert.is_truthy(string.find(cacheText, needle),
                "+" .. n .. "% Mana Efficiency with Lethal Mirage must carry SkillName tag and empty residue")
        end
    end)

    it("C6f: ModCache '+71 Lightning Damage with Lethal Mirage' carries SkillName tag with empty residue", function()
        local needle = 'c%["%+71 Lightning Damage with Lethal Mirage"%]={{%[1%]={%[1%]={skillName="Lethal Mirage",type="SkillName"},flags=0,keywordFlags=0,name="LightningDamage",type="BASE",value=71}},""}'
        assert.is_truthy(string.find(cacheText, needle))
    end)

    it("C6f: ModCache '16% Increased Cooldown Recovery Speed with Lethal Mirage' carries SkillName tag with empty residue", function()
        local needle = 'c%["16%% Increased Cooldown Recovery Speed with Lethal Mirage"%]={{%[1%]={%[1%]={skillName="Lethal Mirage",type="SkillName"},flags=0,keywordFlags=0,name="CooldownRecovery",type="INC",value=16}},""}'
        assert.is_truthy(string.find(cacheText, needle))
    end)

    it("C6f: ModCache 'Increased Area of mirage attacks with Lethal Mirage' entries carry SkillName tag with empty residue", function()
        for _, n in ipairs({ 25, 60 }) do
            local needle = 'c%["' .. n .. '%% Increased Area of mirage attacks with Lethal Mirage"%]={{%[1%]={%[1%]={skillName="Lethal Mirage",type="SkillName"},flags=0,keywordFlags=0,name="AreaOfEffect",type="INC",value=' .. n .. '}},""}'
            assert.is_truthy(string.find(cacheText, needle))
        end
    end)

    it("C6f: P14 ModCache '50% Chance to apply a Shadow Dagger on Hit with Lethal Mirage' carries ChanceToApplyShadowDaggerOnHit + SkillName tag", function()
        local needle = 'c%["50%% Chance to apply a Shadow Dagger on Hit with Lethal Mirage"%]={{%[1%]={%[1%]={skillName="Lethal Mirage",type="SkillName"},flags=0,keywordFlags=0,name="ChanceToApplyShadowDaggerOnHit",type="BASE",value=50}},""}'
        assert.is_truthy(string.find(cacheText, needle))
    end)

    it("C6f: descriptive/composite Lethal Mirage entries no longer rely on SkillLevel fallback", function()
        -- '+1 Lethal Mirage is a quick attack with no invulnerability' was purged
        -- from Black Blade of Chaos uniques (game source mod has hideInTooltip=true
        -- and no descriptors.json entry for property=58/specialTag=8/tags=468).
        -- '+N Mirages created by Lethal Mirage' is now parser-anchored
        -- (mirages-created-by-lethal-mirage guard) and emits MirageCount BASE.
        -- The Lethal Mirage cooldown affix is now parser-anchored by the
        -- cooldown-recovered-on-hit-consumer guard (Mod #6) and emits paired
        -- CooldownRecoveryOnHit / CooldownRecoveryOnHitMaxPerCast BASE mods
        -- tagged SkillName='Lethal Mirage'. The C6f-era "must be empty no-op"
        -- assertion has been superseded; the dedicated guard's spec
        -- (TestCooldownRecoveredOnHitConsumer_spec) covers the new shape.
        local needle = 'c%["15%% of Lethal Mirage\\\'s remaining cooldown recovered on Melee Hit %(up to 12 times%)"%]'
        local startPos = string.find(cacheText, needle)
        assert.is_truthy(startPos, "Lethal Mirage cooldown anchor must exist in ModCache")
        local _, lineEnd = string.find(cacheText, '\n', startPos, true)
        local line = string.sub(cacheText, startPos, lineEnd)
        assert.is_truthy(string.find(line, 'name="CooldownRecoveryOnHit"', 1, true),
            "entry must emit CooldownRecoveryOnHit per Mod #6")
        assert.is_truthy(string.find(line, 'skillName="Lethal Mirage"', 1, true),
            "entry must be SkillName-gated to Lethal Mirage")
    end)

    ----------------------------------------------------------------------
    -- C6 follow-ups: F8 + F7 + F2 + F12
    ----------------------------------------------------------------------

    it("C6-followup F8: ModParser registers 'from shadow falcons' SkillName suffix", function()
        local needle = '%["from shadow falcons"%]%s*=%s*{%s*tag%s*=%s*{%s*type%s*=%s*"SkillName",%s*skillName%s*=%s*"Shadow Falcon"%s*}%s*}'
        assert.is_truthy(string.find(parserText, needle))
    end)

    it("C6-followup F8: ModCache '+34# Dusk Shroud Chance From Shadow Falcons' carries SkillName tag with empty residue", function()
        local needle = 'c%["%+34# Dusk Shroud Chance From Shadow Falcons"%]={{%[1%]={%[1%]={skillName="Shadow Falcon",type="SkillName"},flags=8388608,keywordFlags=0,name="ChanceToTriggerOnHit_Ailment_DuskShroud",type="BASE",value=34}},""}'
        assert.is_truthy(string.find(cacheText, needle))
    end)

    it("C6-followup F7: ModParser modNameList registers 'chance to consume shadow'", function()
        local needle = '%["chance to consume shadow"%]%s*=%s*"ChanceToConsumeShadow"'
        assert.is_truthy(string.find(parserText, needle))
    end)

    it("C6-followup F7: ModCache '10% Chance To Consume Shadow' carries ChanceToConsumeShadow stat with empty residue", function()
        local needle = 'c%["10%% Chance To Consume Shadow"%]={{%[1%]={flags=0,keywordFlags=0,name="ChanceToConsumeShadow",type="BASE",value=10}},""}'
        assert.is_truthy(string.find(cacheText, needle))
    end)

    -- @leb-regression-guard:dusk-shroud-trigger-effect
    -- F7 deferred piece: Doppelganger's Facade "Consuming a Shadow grants a stack
    -- of Dusk Shroud" promoted from no-op to ChanceToTriggerOnHit_Ailment_DuskShroud
    -- BASE=100 + Condition:OnShadowConsume (the guaranteed-form counterpart of the
    -- C6c P8 chance-form affix family). Verbatim source: uniques.json L10257 /
    -- set_1_4.json L301. dump.cs L22771 RogueShadow.duskShroudChanceOnConsumption.
    it("C6-followup F7: ModParser specialModList wires 'consuming a shadow grants a stack of dusk shroud' to ChanceToTriggerOnHit_Ailment_DuskShroud BASE=100 + Condition:OnShadowConsume", function()
        local needle = '%["%^consuming a shadow grants a stack of dusk shroud%$"%]%s*=%s*function%(%)%s*return%s*{%s*mod%("ChanceToTriggerOnHit_Ailment_DuskShroud",%s*"BASE",%s*100,%s*"",%s*ModFlag%.Hit,%s*0,%s*{%s*type%s*=%s*"Condition",%s*var%s*=%s*"OnShadowConsume"%s*}%s*%)%s*}%s*end'
        assert.is_truthy(string.find(parserText, needle),
            "ModParser must wire 'Consuming a Shadow grants a stack of Dusk Shroud' to ChanceToTriggerOnHit_Ailment_DuskShroud BASE=100 with Condition:OnShadowConsume")
    end)

    it("C6-followup F7: ModCache 'Consuming a Shadow grants a stack of Dusk Shroud' carries ChanceToTriggerOnHit_Ailment_DuskShroud BASE=100 + Condition:OnShadowConsume with empty residue", function()
        local needle = 'c%["Consuming a Shadow grants a stack of Dusk Shroud"%]={{%[1%]={%[1%]={type="Condition",var="OnShadowConsume"},flags=8388608,keywordFlags=0,name="ChanceToTriggerOnHit_Ailment_DuskShroud",type="BASE",value=100}},""}'
        assert.is_truthy(string.find(cacheText, needle),
            "ModCache must lock the wired guaranteed-form Dusk Shroud trigger-effect")
    end)

    it("C6-followup F2: ModParser formList registers no-% Increased/Reduced INC promotion", function()
        assert.is_truthy(string.find(parserText, '%["%^%(%[%%%+%%%-%]%?%[%%d%%.%]%+%) increased"%]%s*=%s*"INC"'))
        assert.is_truthy(string.find(parserText, '%["%^%(%[%%%+%%%-%]%?%[%%d%%.%]%+%) reduced"%]%s*=%s*"RED"'))
    end)

    it("C6-followup F2: ModCache '+N Increased Damage for skills used by Shadows' entries carry MinionModifier LIST scoped to ShadowClone", function()
        -- Superseded by shadow-damage-minion-scope: was Scope:minion (legacy
        -- generic-scope tag). Now routed via MinionModifier LIST with
        -- minionTypes={"ShadowClone"}, consistent with the broader Shadows
        -- minion-scope unification.
        for _, n in ipairs({ 1, 2, 3 }) do
            local needle = 'c%["%+' .. n .. ' Increased Damage for skills used by Shadows"%]={{%[1%]={flags=0,keywordFlags=0,name="MinionModifier",type="LIST",value={minionTypes={%[1%]="ShadowClone"},mod={flags=0,keywordFlags=0,name="Damage",type="INC",value=' .. n .. '}}}},""}'
            assert.is_truthy(string.find(cacheText, needle),
                "+" .. n .. " Increased Damage for skills used by Shadows must carry MinionModifier LIST scoped to ShadowClone")
        end
    end)

    it("C6-followup F2: ModCache '+N Increased Stun Chance' entries carry StunChance INC with empty residue", function()
        for _, n in ipairs({ 2, 3 }) do
            local needle = 'c%["%+' .. n .. ' Increased Stun Chance"%]={{%[1%]={flags=0,keywordFlags=0,name="StunChance",type="INC",value=' .. n .. '}},""}'
            assert.is_truthy(string.find(cacheText, needle))
        end
    end)

    it("C6-followup F12: ModParser SkillLevel fallback gated by whitespace-only-residue check", function()
        local needle = 'skillTag%.tag%.type%s*==%s*"SkillName"%s*and%s*line:match%("%^%%s%*%$"%)'
        assert.is_truthy(string.find(parserText, needle),
            "SkillLevel fallback must require line:match('^%s*$') gate")
    end)

    it("C6d: no C6d entry retains stale residue", function()
        local keys = {
            '%+13%% Physical Penetration with Shadow Daggers',
            '%+15%% Physical Penetration with Shadow Daggers',
            '%+20%% Physical Penetration with Shadow Daggers',
            '%+25%% Physical Penetration with Shadow Daggers',
            '%+26%% Physical Penetration with Shadow Daggers',
            '%+30%% Physical Penetration with Shadow Daggers',
            '%+39%% Physical Penetration with Shadow Daggers',
            '%+69%% Physical Penetration with Shadow Daggers',
            '%+89%% Physical Penetration with Shadow Daggers',
            '%+180%% Physical Penetration with Shadow Daggers',
            '15%% Increased Shadow Damage',
            '20%% Increased Shadow Damage',
        }
        for _, k in ipairs(keys) do
            local stale = 'c%["' .. k .. '"%]={{[^\n]-}},"[^"][^\n]*"}'
            assert.is_nil(string.find(cacheText, stale),
                "C6d entry must have empty residue: " .. k)
        end
    end)
end)
