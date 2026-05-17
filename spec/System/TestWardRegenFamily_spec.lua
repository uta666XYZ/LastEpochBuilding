-- @leb-regression-guard: ward-per-second-and-retention-family
-- Locks the parser + ModCache + config/calc auto-populate sites for the
-- 13 ward-related silent-failure affixes:
--   WardPerSecond:        per 5% uncapped res, with a catalyst, per 10 mana,
--                         forged weapon (MinionModifier), per stack
--                         (Firebrand), ward regen alias, arcane shield,
--                         holy symbol.
--   WardRetention:        per 1% increased area, per 100% uncapped Cold
--                         resistance, on transform, from increased armor.
--   WardDecayThreshold:   per 2% Necro Res (Imperishable inherent).
--
-- Before this guard the parser left the conditional text in slot[2] residue
-- and emitted bare WardPerSecond/WardRetention BASE mods, so the bonus
-- leaked onto the unconditional stat. Three sites lock together:
-- a. ModParser.lua specialModList: 13 patterns + 2 modTag suffix entries
--    ("on transform" / "when you transform") emit tagged inner mods or
--    MinionModifier wrappers.
-- b. ConfigOptions.lua: multiplierFirebrandStack (new) and
--    multiplierActiveSymbols (now sets Condition:HaveActiveSymbol when
--    val >= 1, mirroring HaveArcaneShield).
-- c. CalcSetup.lua: auto-populate Multiplier:AreaInc / ArmourInc /
--    UncappedResistTotal from the appropriate Sum().
-- d. ModCache.lua: all 13 entries carry the wrapper with empty residue.

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("WardRegenFamily", function()
    local parserText, cacheText, configText, calcText

    setup(function()
        parserText = readSource("Modules/ModParser.lua")
        cacheText  = readSource("Data/ModCache.lua")
        configText = readSource("Modules/ConfigOptions.lua")
        calcText   = readSource("Modules/CalcSetup.lua")
    end)

    it("ModParser registers 'on transform' / 'when you transform' modTag suffixes", function()
        assert.is_truthy(string.find(parserText,
            '%["on transform"%]%s*=%s*{%s*tag%s*=%s*{%s*type%s*=%s*"Condition",%s*var%s*=%s*"Transformed"%s*}%s*}',
            1, false),
            "ModParser must register 'on transform' tag suffix")
        assert.is_truthy(string.find(parserText,
            '%["when you transform"%]%s*=%s*{%s*tag%s*=%s*{%s*type%s*=%s*"Condition",%s*var%s*=%s*"Transformed"%s*}%s*}',
            1, false),
            "ModParser must register 'when you transform' tag suffix")
    end)

    it("ModParser registers all 13 ward-family specialModList patterns", function()
        local patterns = {
            "ward decay threshold per 2%%%% necro res",
            "ward per second per 5%%%% uncapped resistances",
            "ward retention per 1%%%% increased area",
            "ward retention per 100%%%% uncapped cold resistance",
            "ward per second with a catalyst",
            "ward retention on transform",
            "ward per second per 10 mana",
            "ward retention from increased armor",
            "forged weapon ward per second",
            "ward per second per stack",
            "ward regen per second",
            "arcane shield ward per second",
            "holy symbol ward per second",
        }
        for _, p in ipairs(patterns) do
            assert.is_truthy(string.find(parserText, p),
                "ModParser must register pattern matching: " .. p)
        end
    end)

    it("ConfigOptions adds multiplierFirebrandStack count", function()
        assert.is_truthy(string.find(configText,
            'var = "multiplierFirebrandStack"', 1, false),
            "ConfigOptions must declare multiplierFirebrandStack")
        assert.is_truthy(string.find(configText,
            'modList:NewMod%("Multiplier:FirebrandStack", "BASE", val,'),
            "multiplierFirebrandStack must set Multiplier:FirebrandStack from val")
    end)

    it("ConfigOptions multiplierActiveSymbols sets Condition:HaveActiveSymbol when >=1", function()
        assert.is_truthy(string.find(configText,
            'modList:NewMod%("Condition:HaveActiveSymbol", "FLAG", val >= 1,'),
            "multiplierActiveSymbols must set Condition:HaveActiveSymbol when val >= 1")
    end)

    it("CalcSetup auto-populates AreaInc/ArmourInc/UncappedResistTotal", function()
        assert.is_truthy(string.find(calcText,
            'NewMod%("Multiplier:AreaInc", "BASE", areaInc,'),
            "CalcSetup must auto-populate Multiplier:AreaInc")
        assert.is_truthy(string.find(calcText,
            'NewMod%("Multiplier:ArmourInc", "BASE", armourInc,'),
            "CalcSetup must auto-populate Multiplier:ArmourInc")
        assert.is_truthy(string.find(calcText,
            'NewMod%("Multiplier:UncappedResistTotal", "BASE", resTotal,'),
            "CalcSetup must auto-populate Multiplier:UncappedResistTotal")
    end)

    it("ModCache: Ward Decay Threshold carries PerStat:NecroticResist div=2 + empty residue", function()
        local needle = 'c%["%+1 Ward Decay Threshold Per 2%% Necro Res"%]={{%[1%]={%[1%]={div=2,stat="NecroticResist",type="PerStat"},flags=0,keywordFlags=0,name="WardDecayThreshold",type="BASE",value=1}},""}'
        assert.is_truthy(string.find(cacheText, needle, 1, false),
            "Ward Decay Threshold per 2%% Necro Res entry must carry PerStat:NecroticResist div=2")
    end)

    it("ModCache: WardPerSecond per 5%% uncapped resistances carries Multiplier:UncappedResistTotal div=5", function()
        local needle = 'c%["%+1 Ward Per Second Per 5%% Uncapped Resistances"%]={{%[1%]={%[1%]={div=5,type="Multiplier",var="UncappedResistTotal"},flags=0,keywordFlags=0,name="WardPerSecond",type="BASE",value=1}},""}'
        assert.is_truthy(string.find(cacheText, needle, 1, false))
    end)

    it("ModCache: WardRetention per 1%% Increased Area carries Multiplier:AreaInc", function()
        local needle = 'c%["%+1%% Ward Retention per 1%% Increased Area"%]={{%[1%]={%[1%]={type="Multiplier",var="AreaInc"},flags=0,keywordFlags=0,name="WardRetention",type="BASE",value=1}},""}'
        assert.is_truthy(string.find(cacheText, needle, 1, false))
    end)

    it("ModCache: WardRetention per 100%% uncapped Cold Resistance carries PerStat:ColdResist div=100", function()
        local needle = 'c%["%+100%% Ward Retention per 100%% uncapped Cold Resistance"%]={{%[1%]={%[1%]={div=100,stat="ColdResist",type="PerStat"},flags=0,keywordFlags=0,name="WardRetention",type="BASE",value=100}},""}'
        assert.is_truthy(string.find(cacheText, needle, 1, false))
    end)

    it("ModCache: WardPerSecond With A Catalyst carries Condition:UsingCatalyst", function()
        local needle = 'c%["%+15 Ward Per Second With A Catalyst"%]={{%[1%]={%[1%]={type="Condition",var="UsingCatalyst"},flags=0,keywordFlags=0,name="WardPerSecond",type="BASE",value=15}},""}'
        assert.is_truthy(string.find(cacheText, needle, 1, false))
    end)

    it("ModCache: WardRetention on Transform carries Condition:Transformed", function()
        local needle = 'c%["%+185%% Ward Retention on Transform"%]={{%[1%]={%[1%]={type="Condition",var="Transformed"},flags=0,keywordFlags=0,name="WardRetention",type="BASE",value=185}},""}'
        assert.is_truthy(string.find(cacheText, needle, 1, false))
    end)

    it("ModCache: WardPerSecond per 10 Mana carries PerStat:Mana div=10", function()
        local needle = 'c%["%+2 Ward Per Second per 10 Mana"%]={{%[1%]={%[1%]={div=10,stat="Mana",type="PerStat"},flags=0,keywordFlags=0,name="WardPerSecond",type="BASE",value=2}},""}'
        assert.is_truthy(string.find(cacheText, needle, 1, false))
    end)

    it("ModCache: WardRetention From Increased Armor carries Multiplier:ArmourInc div=100", function()
        local needle = 'c%["10%% Ward Retention From Increased Armor"%]={{%[1%]={%[1%]={div=100,type="Multiplier",var="ArmourInc"},flags=0,keywordFlags=0,name="WardRetention",type="BASE",value=10}},""}'
        assert.is_truthy(string.find(cacheText, needle, 1, false))
    end)

    it("ModCache: Forged Weapon Ward Per Second carries MinionModifier type=ForgedWeapon", function()
        local needle = 'c%["15 Forged Weapon Ward Per Second"%]={{%[1%]={flags=0,keywordFlags=0,name="MinionModifier",type="LIST",value={mod={flags=0,keywordFlags=0,name="WardPerSecond",type="BASE",value=15},type="ForgedWeapon"}}},""}'
        assert.is_truthy(string.find(cacheText, needle, 1, false))
    end)

    it("ModCache: Ward Per Second Per Stack carries Multiplier:FirebrandStack", function()
        local needle = 'c%["3 Ward Per Second Per Stack"%]={{%[1%]={%[1%]={type="Multiplier",var="FirebrandStack"},flags=0,keywordFlags=0,name="WardPerSecond",type="BASE",value=3}},""}'
        assert.is_truthy(string.find(cacheText, needle, 1, false))
    end)

    it("ModCache: Ward Regen Per Second is plain WardPerSecond BASE with empty residue", function()
        local needle = 'c%["3 Ward Regen Per Second"%]={{%[1%]={flags=0,keywordFlags=0,name="WardPerSecond",type="BASE",value=3}},""}'
        assert.is_truthy(string.find(cacheText, needle, 1, false))
    end)

    it("ModCache: Arcane Shield Ward Per Second carries Condition:HaveArcaneShield", function()
        local needle = 'c%["4 Arcane Shield Ward Per Second"%]={{%[1%]={%[1%]={type="Condition",var="HaveArcaneShield"},flags=0,keywordFlags=0,name="WardPerSecond",type="BASE",value=4}},""}'
        assert.is_truthy(string.find(cacheText, needle, 1, false))
    end)

    it("ModCache: Holy Symbol Ward Per Second carries Condition:HaveActiveSymbol", function()
        local needle = 'c%["5 Holy Symbol Ward Per Second"%]={{%[1%]={%[1%]={type="Condition",var="HaveActiveSymbol"},flags=0,keywordFlags=0,name="WardPerSecond",type="BASE",value=5}},""}'
        assert.is_truthy(string.find(cacheText, needle, 1, false))
    end)

    it("ModCache: no ward-family entry carries non-empty residue", function()
        local keys = {
            "%+1 Ward Decay Threshold Per 2%% Necro Res",
            "%+1 Ward Per Second Per 5%% Uncapped Resistances",
            "%+1%% Ward Retention per 1%% Increased Area",
            "%+100%% Ward Retention per 100%% uncapped Cold Resistance",
            "%+15 Ward Per Second With A Catalyst",
            "%+185%% Ward Retention on Transform",
            "%+2 Ward Per Second per 10 Mana",
            "10%% Ward Retention From Increased Armor",
            "15 Forged Weapon Ward Per Second",
            "3 Ward Per Second Per Stack",
            "3 Ward Regen Per Second",
            "4 Arcane Shield Ward Per Second",
            "5 Holy Symbol Ward Per Second",
        }
        for _, k in ipairs(keys) do
            local stale = 'c%["' .. k .. '"%]={{[^\n]-}},"[^"][^\n]*"}'
            assert.is_nil(string.find(cacheText, stale),
                "ward-family entry must have empty residue: " .. k)
        end
    end)

    -- ====================================================================
    -- W2: "Ward per Second per Gon Rune" — 16 silent-failure entries
    -- The parser DOES register `["per gon rune"]` -> Multiplier:GonRune
    -- (ModParser.lua L666) and ConfigOptions wires multiplierGonRune
    -- (ConfigOptions.lua L240), but the 16 cached entries below were baked
    -- before that wiring and retained "  per Gon Rune " residue with no
    -- inner tag — so the WardPerSecond BASE applied unconditionally.
    -- ====================================================================

    it("W2: 16 'Ward per Second per Gon Rune' entries carry Multiplier:GonRune with empty residue", function()
        for _, n in ipairs({ 14, 15, 19, 21, 25, 29, 31, 37, 46, 49, 56, 58, 73, 87, 114, 171 }) do
            local needle = 'c%["%+' .. n .. ' Ward per Second per Gon Rune"%]={{%[1%]={%[1%]={type="Multiplier",var="GonRune"},flags=0,keywordFlags=0,name="WardPerSecond",type="BASE",value=' .. n .. '}},""}'
            assert.is_truthy(string.find(cacheText, needle),
                "+" .. n .. " Ward per Second per Gon Rune must carry Multiplier:GonRune tag")
            local stale = 'c%["%+' .. n .. ' Ward per Second per Gon Rune"%]={{[^\n]-}},"[^"][^\n]*"}'
            assert.is_nil(string.find(cacheText, stale),
                "+" .. n .. " Ward per Second per Gon Rune must have empty residue")
        end
    end)

    -- ====================================================================
    -- W3: "Ward per Second for you or your allies while standing on your
    -- Glyph of Dominion" — 10 Runemaster Glyph entries had the proper
    -- StandingOnGlyphOfDominion Condition tag but retained descriptive
    -- "for you or your allies" residue. Parser now strips it via a new
    -- noise-eater modTag entry (ModParser.lua ~L545); cache entries
    -- regenerated with empty residue.
    -- ====================================================================

    it("ModParser registers 'for you or your allies' noise-eater modTag (empty tag)", function()
        local parserText = readSource("Modules/ModParser.lua")
        local needle = '%["for you or your allies"%]%s*=%s*{%s*}'
        assert.is_truthy(string.find(parserText, needle),
            "ModParser must register no-op modTag for 'for you or your allies'")
    end)

    it("W3: 10 Glyph of Dominion ward-regen entries have empty residue with StandingOnGlyphOfDominion tag", function()
        for _, n in ipairs({ 17, 25, 33, 36, 52, 65, 73, 118, 151, 306 }) do
            local needle = 'c%["%+' .. n .. ' Ward per Second for you or your allies while standing on your Glyph of Dominion"%]={{%[1%]={%[1%]={type="Condition",var="StandingOnGlyphOfDominion"},flags=0,keywordFlags=0,name="WardPerSecond",type="BASE",value=' .. n .. '}},""}'
            assert.is_truthy(string.find(cacheText, needle),
                "+" .. n .. " Ward per Second Glyph entry must carry StandingOnGlyphOfDominion tag with empty residue")
            local stale = 'c%["%+' .. n .. ' Ward per Second for you or your allies while standing on your Glyph of Dominion"%]={{[^\n]-}},"[^"][^\n]*"}'
            assert.is_nil(string.find(cacheText, stale),
                "+" .. n .. " Ward per Second Glyph entry must have empty residue")
        end
    end)

    -- ====================================================================
    -- W4: "+97 Ward per Second during Profane Veil" (Lich tree). Before
    -- this guard the parser had no `["during profane veil"]` modTag, so
    -- the scan() longest-match fell through to the auto-built skillNameList
    -- which ate "profane veil" as a SkillName scope. That mis-tagged the
    -- mod as Profane Veil-skill-scoped (wrong: Profane Veil deals no
    -- damage). Three sites lock together:
    --   a. ModParser.lua: new modTagList ["during profane veil"] ->
    --      Condition:DuringProfaneVeil (evaluated before SkillName eater
    --      via longest-match preference).
    --   b. ConfigOptions.lua: new conditionDuringProfaneVeil check toggle
    --      mirroring conditionHaveEterrasBlessing.
    --   c. ModCache.lua: the entry carries Condition:DuringProfaneVeil
    --      with empty residue.
    -- ====================================================================

    it("ModParser registers 'during profane veil' suffix -> Condition:DuringProfaneVeil", function()
        local parserText = readSource("Modules/ModParser.lua")
        local needle = '%["during profane veil"%]%s*=%s*{%s*tag%s*=%s*{%s*type%s*=%s*"Condition",%s*var%s*=%s*"DuringProfaneVeil"'
        assert.is_truthy(string.find(parserText, needle),
            "ModParser must register 'during profane veil' modTag -> Condition:DuringProfaneVeil")
    end)

    it("ConfigOptions wires conditionDuringProfaneVeil check", function()
        local cfgText = readSource("Modules/ConfigOptions.lua")
        assert.is_truthy(string.find(cfgText, 'conditionDuringProfaneVeil', 1, true),
            "ConfigOptions must register conditionDuringProfaneVeil")
        assert.is_truthy(string.find(cfgText, 'Condition:DuringProfaneVeil', 1, true),
            "ConfigOptions must emit Condition:DuringProfaneVeil FLAG")
    end)

    it("W4: '+97 Ward per Second during Profane Veil' carries Condition:DuringProfaneVeil with empty residue", function()
        local needle = 'c%["%+97 Ward per Second during Profane Veil"%]={{%[1%]={%[1%]={type="Condition",var="DuringProfaneVeil"},flags=0,keywordFlags=0,name="WardPerSecond",type="BASE",value=97}},""}'
        assert.is_truthy(string.find(cacheText, needle),
            "+97 Ward per Second during Profane Veil must carry Condition:DuringProfaneVeil with empty residue")
        local stale = 'c%["%+97 Ward per Second during Profane Veil"%]={{[^\n]-}},"[^"][^\n]*"}'
        assert.is_nil(string.find(cacheText, stale),
            "+97 Ward per Second during Profane Veil must have empty residue")
    end)

    -- ====================================================================
    -- W5: "140 Ward per Second for each Curse affecting you" — Acolyte
    -- self-curse stacking. New Multiplier:CurseOnSelf var introduced.
    -- ====================================================================

    it("ModParser registers 'for each curse affecting you' -> Multiplier:CurseOnSelf", function()
        local parserText = readSource("Modules/ModParser.lua")
        local needle = '%["for each curse affecting you"%]%s*=%s*{%s*tag%s*=%s*{%s*type%s*=%s*"Multiplier",%s*var%s*=%s*"CurseOnSelf"'
        assert.is_truthy(string.find(parserText, needle),
            "ModParser must register 'for each curse affecting you' -> Multiplier:CurseOnSelf")
    end)

    it("ConfigOptions wires multiplierCurseOnSelf count input", function()
        local cfgText = readSource("Modules/ConfigOptions.lua")
        assert.is_truthy(string.find(cfgText, 'multiplierCurseOnSelf', 1, true),
            "ConfigOptions must register multiplierCurseOnSelf")
        assert.is_truthy(string.find(cfgText, 'Multiplier:CurseOnSelf', 1, true),
            "ConfigOptions must emit Multiplier:CurseOnSelf BASE")
    end)

    it("W5: '140 Ward per Second for each Curse affecting you' carries Multiplier:CurseOnSelf with empty residue", function()
        local needle = 'c%["140 Ward per Second for each Curse affecting you"%]={{%[1%]={%[1%]={type="Multiplier",var="CurseOnSelf"},flags=0,keywordFlags=0,name="WardPerSecond",type="BASE",value=140}},""}'
        assert.is_truthy(string.find(cacheText, needle),
            "140 Ward per Second for each Curse affecting you must carry Multiplier:CurseOnSelf with empty residue")
    end)

    -- ====================================================================
    -- W6: "3 Ward per Second Duration (Seconds)" is a `notScalingStats`
    -- descriptive metadata line on a Sentinel Healing Hands tree node —
    -- it states that the Ward-per-Second buff granted by the node lasts
    -- 3 seconds, NOT that the player gets +3 Ward/sec unconditionally.
    -- The parser was over-eagerly extracting WardPerSecond=3 from the
    -- "3 Ward per Second" prefix.
    --
    -- Until the parser learns to recognize "Duration (Seconds)" as a
    -- unit/metadata suffix on a buff-grant stat (or notScalingStats grows
    -- separate parsing rules), the cache entry is neutralized to {{}, ""}
    -- so it contributes nothing. The visible tree-node tooltip still
    -- shows the original text via the notScalingStats render path.
    -- ====================================================================

    it("W6: '3 Ward per Second Duration (Seconds)' is neutralized to {{}, \"\"} (no spurious WardPerSecond)", function()
        local needle = 'c%["3 Ward per Second Duration %(Seconds%)"%]={{}, ""}'
        assert.is_truthy(string.find(cacheText, needle),
            "W6 entry must be neutralized to empty modlist + empty residue")
        local stale = 'c%["3 Ward per Second Duration %(Seconds%)"%]={{%[1%]={flags=0,keywordFlags=0,name="WardPerSecond"'
        assert.is_nil(string.find(cacheText, stale),
            "W6 entry must not emit WardPerSecond — this is descriptive notScalingStats metadata")
    end)
end)
