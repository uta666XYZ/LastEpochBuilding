-- @leb-regression-guard:auto-summon-registry
-- @leb-regression-guard:auto-summon-pack-dps
-- Locks Phase A of the general "item/affix/passive-granted, non-skill-bound
-- auto-summon minion" framework: a per-player COUNT stat (data.autoSummons,
-- e.g. Apiarist "Bees" from "+N Bees Per 10 Seconds") auto-injects the
-- existing summon skill as an includeInFullDPS granted skill, and calcFullDPS
-- reports pack DPS = single-minion DPS x active count.
--
-- Game ground truth (no fabrication):
--   * "+N Bees Per 10 Seconds" / "+N% Bees Per 10 Seconds" (+ "Elemental"
--     variant) are real LE affixes (Apiarist set / bee affixes). LEB
--     recognized the text but baked it to an EMPTY mod
--     (Data/ModCache.lua c["+1 Bees Per 10 Seconds"]={{}," Bees Per 10
--     Seconds "}), so no minion was modeled.
--   * The summoned bee is data.skills.SummonBee ("Summon Bee", Druid); its
--     minion is the src/Data/minions.json "Bee" prefab (skillList
--     {"BasicEnemyMelee"} = 18 base physical melee, attack/hit). The
--     SummonBee.minionList previously pointed at the non-existent
--     "SummonedBee" key (dangling link); this feature fixes it to ["Bee"].
--
-- Three sites lock together:
--   a. Data/AutoSummons.lua (data.autoSummons): countStat -> summonSkill map.
--   b. Modules/CalcSetup.lua grantedAutoSummons loop: detects the count stat
--      on the PLAYER modDB and injects summonSkill (includeInFullDPS,
--      noSupports, autoSummonCountStat carried onto the socket group).
--   c. Modules/Calcs.lua calcFullDPS minion block: count = floor(player-modDB
--      value of autoSummonCountStat), min 1; pack DPS = single x count. All
--      other minions keep count = 1.
-- Plus the ModParser rules + rebaked ModCache rows that make the count stat
-- real instead of an empty parse.

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("AutoSummon registry data (no fabrication)", function()
    it("data.autoSummons is loaded and every summonSkill exists in data.skills", function()
        assert.is_table(data.autoSummons, "data.autoSummons must be loaded")
        assert.is_true(#data.autoSummons >= 1, "registry must have at least one entry")
        for _, entry in ipairs(data.autoSummons) do
            assert.is_string(entry.countStat, "entry must carry a countStat")
            assert.is_table(data.skills[entry.summonSkill],
                "summonSkill " .. tostring(entry.summonSkill) .. " must exist in data.skills")
        end
    end)

    it("the bee entries map the count stats to SummonBee", function()
        local byStat = {}
        for _, e in ipairs(data.autoSummons) do byStat[e.countStat] = e.summonSkill end
        assert.are.equals("SummonBee", byStat["BeesPerTenSeconds"])
        assert.are.equals("SummonBee", byStat["ElementalBeesPerTenSeconds"])
    end)

    it("SummonBee.minionList points at the existing minions.json 'Bee' prefab", function()
        local s = data.skills.SummonBee
        assert.is_table(s)
        assert.are.equals("Summon Bee", s.name)
        assert.is_table(s.minionList)
        assert.are.equals("Bee", s.minionList[1])
        -- and the linkage actually resolves
        assert.is_table(data.minions["Bee"], "minions.json must have a 'Bee' entry")
        assert.are.equals("BasicEnemyMelee", data.minions["Bee"].skillList[1],
            "Bee minion must use BasicEnemyMelee (18 phys melee)")
        assert.is_nil(data.minions["SummonedBee"],
            "stale 'SummonedBee' key must not exist (the dangling link is fixed)")
    end)
end)

describe("AutoSummon ModParser (count stats not empty)", function()
    -- Uncached numbers force a LIVE parse (bypassing the ModCache rows) so the
    -- ModParser rules themselves are exercised, not just the rebaked cache.
    it("'+11 Bees Per 10 Seconds' parses to BeesPerTenSeconds BASE (not empty)", function()
        local mods, extra = modLib.parseMod("+11 Bees Per 10 Seconds")
        assert.is_nil(extra, "must parse cleanly (was an empty parse with residue)")
        assert.are.equals(1, #mods)
        assert.are.equals("BeesPerTenSeconds", mods[1].name)
        assert.are.equals("BASE", mods[1].type)
        assert.are.equals(11, mods[1].value)
    end)

    it("'+77% Bees Per 10 Seconds' parses to BeesPerTenSeconds INC", function()
        local mods, extra = modLib.parseMod("+77% Bees Per 10 Seconds")
        assert.is_nil(extra)
        assert.are.equals("BeesPerTenSeconds", mods[1].name)
        assert.are.equals("INC", mods[1].type)
        assert.are.equals(77, mods[1].value)
    end)

    it("'+13 Elemental Bees Per 10 Seconds' parses to ElementalBeesPerTenSeconds BASE", function()
        local mods, extra = modLib.parseMod("+13 Elemental Bees Per 10 Seconds")
        assert.is_nil(extra)
        assert.are.equals("ElementalBeesPerTenSeconds", mods[1].name)
        assert.are.equals("BASE", mods[1].type)
        assert.are.equals(13, mods[1].value)
    end)

    it("'+99% Elemental Bees Per 10 Seconds' parses to ElementalBeesPerTenSeconds INC", function()
        local mods, extra = modLib.parseMod("+99% Elemental Bees Per 10 Seconds")
        assert.is_nil(extra)
        assert.are.equals("ElementalBeesPerTenSeconds", mods[1].name)
        assert.are.equals("INC", mods[1].type)
        assert.are.equals(99, mods[1].value)
    end)

    it("conditional '+6 Bees per 10 seconds while in Spriggan Form' carries the condition", function()
        local mods, extra = modLib.parseMod("+6 Bees per 10 seconds while in Spriggan Form")
        assert.is_nil(extra)
        assert.are.equals("BeesPerTenSeconds", mods[1].name)
        assert.are.equals("BASE", mods[1].type)
        assert.are.equals(6, mods[1].value)
        local hasCond = false
        for _, tag in ipairs(mods[1]) do
            if tag.type == "Condition" and tag.var == "InSprigganForm" then hasCond = true end
        end
        assert.is_true(hasCond, "must carry Condition=InSprigganForm")
    end)

    it("'+22 Melee Damage for your Summoned Bees' scopes a melee damage add to the Bee", function()
        local mods, extra = modLib.parseMod("+22 Melee Damage for your Summoned Bees")
        assert.is_nil(extra, "must parse cleanly (was player-scoped with residue)")
        assert.are.equals("MinionModifier", mods[1].name)
        assert.are.equals("LIST", mods[1].type)
        local v = mods[1].value
        assert.is_table(v.minionTypes)
        assert.are.equals("Bee", v.minionTypes[1])
        assert.are.equals("Damage", v.mod.name)
        assert.are.equals("BASE", v.mod.type)
        assert.are.equals(22, v.mod.value)
        assert.are.equals(KeywordFlag.Melee, v.mod.keywordFlags, "must carry the Melee keyword flag")
    end)
end)

describe("AutoSummon ModCache (rebaked rows, not empty)", function()
    local cacheText
    setup(function() cacheText = readSource("Data/ModCache.lua") end)

    it("a baked bee-count row now holds a real BeesPerTenSeconds mod", function()
        assert.is_truthy(string.find(cacheText,
            'c["+1 Bees Per 10 Seconds"]={{[1]={flags=0,keywordFlags=0,name="BeesPerTenSeconds",type="BASE",value=1}},nil}',
            1, true),
            "the +1 bee row must be rebaked to a real BeesPerTenSeconds BASE mod")
    end)

    it("the +80%% bee row is rebaked as INC", function()
        assert.is_truthy(string.find(cacheText,
            'c["+80% Bees Per 10 Seconds"]={{[1]={flags=0,keywordFlags=0,name="BeesPerTenSeconds",type="INC",value=80}},nil}',
            1, true))
    end)

    it("the elemental rows are rebaked to ElementalBeesPerTenSeconds", function()
        assert.is_truthy(string.find(cacheText,
            'c["+5 Elemental Bees Per 10 Seconds"]={{[1]={flags=0,keywordFlags=0,name="ElementalBeesPerTenSeconds",type="BASE",value=5}},nil}',
            1, true))
        assert.is_truthy(string.find(cacheText,
            'c["+80% Elemental Bees Per 10 Seconds"]={{[1]={flags=0,keywordFlags=0,name="ElementalBeesPerTenSeconds",type="INC",value=80}},nil}',
            1, true))
    end)

    it("no stale empty bee-count rows remain", function()
        assert.is_nil(string.find(cacheText,
            'c["+1 Bees Per 10 Seconds"]={{}," Bees Per 10 Seconds "}', 1, true),
            "the empty-parse +1 bee row must be gone")
        assert.is_nil(string.find(cacheText,
            ' Bees Per 10 Seconds "}', 1, true),
            "no bee-count row may retain the ' Bees Per 10 Seconds ' empty-parse residue")
    end)

    it("the melee-bee row is rebaked to a Bee-scoped MinionModifier", function()
        assert.is_truthy(string.find(cacheText,
            'c["+18 Melee Damage for your Summoned Bees"]={{[1]={flags=0,keywordFlags=0,name="MinionModifier",type="LIST",value={minionTypes={[1]="Bee"},mod={flags=0,keywordFlags=512,name="Damage",source="",type="BASE",value=18}}}},nil}',
            1, true),
            "the +18 melee bee row must be a Bee-scoped MinionModifier (no player leak / residue)")
    end)
end)

describe("AutoSummon source invariants", function()
    it("CalcSetup injects auto-summons as includeInFullDPS granted skills", function()
        local cs = readSource("Modules/CalcSetup.lua")
        assert.is_truthy(string.find(cs, "data.autoSummons", 1, true),
            "CalcSetup must consume data.autoSummons")
        assert.is_truthy(string.find(cs, "grantedAutoSummons", 1, true),
            "CalcSetup must build the grantedAutoSummons table")
        assert.is_truthy(string.find(cs, "autoSummonCountStat", 1, true),
            "the count stat must be carried onto the granted skill / group")
        assert.is_truthy(string.find(cs, "@leb%-regression%-guard:auto%-summon%-registry"),
            "CalcSetup must carry the auto-summon-registry guard marker")
    end)

    it("Calcs.calcFullDPS scales the minion count by the auto-summon count stat", function()
        local cc = readSource("Modules/Calcs.lua")
        assert.is_truthy(string.find(cc, "@leb%-regression%-guard:auto%-summon%-pack%-dps"),
            "Calcs must carry the auto-summon-pack-dps guard marker")
        assert.is_truthy(string.find(cc, "autoSummonCountStat", 1, true),
            "calcFullDPS must read the autoSummonCountStat off the socket group")
        assert.is_truthy(string.find(cc, "calcLib.val(usedEnv.modDB", 1, true),
            "the count must resolve against the PLAYER modDB (usedEnv.modDB), not the minion modDB")
    end)
end)

describe("AutoSummon end-to-end (empty build + Bee count stat)", function()
    it("BeesPerTenSeconds > 0 injects SummonBee into Full DPS as a pack", function()
        newBuild()
        build.configTab.input.customMods = "+5 Bees Per 10 Seconds\n"
        build.configTab:BuildModList()
        build.buildFlag = true
        runCallback("OnFrame")

        -- The granted SummonBee group must exist, be includeInFullDPS, NOT be a
        -- main socketed group, and carry the count stat.
        local beeSkill
        for _, s in ipairs(build.calcsTab.mainEnv.player.activeSkillList) do
            local sg = s.socketGroup
            if sg and sg.source == "AutoSummon:BeesPerTenSeconds" then beeSkill = s end
        end
        assert.is_not_nil(beeSkill, "SummonBee must be injected as an auto-summon granted skill")
        assert.is_true(beeSkill.socketGroup.includeInFullDPS, "auto-summon must be in Full DPS")
        assert.is_truthy(beeSkill.socketGroup.noSupports, "auto-summon group takes no supports")
        assert.are.equals("BeesPerTenSeconds", beeSkill.socketGroup.autoSummonCountStat)
        assert.are.equals("Summon Bee (auto-summoned)", beeSkill.socketGroup.label)

        -- Full DPS must contain a bee entry with count = 5 (the pack), and that
        -- pack DPS = single-minion DPS x 5.
        local out = build.calcsTab.mainOutput
        local beeEntry
        for _, e in ipairs(out.SkillDPS or {}) do
            if e.name == "Summon Bee" then beeEntry = e end
        end
        assert.is_not_nil(beeEntry, "Full DPS must list a 'Summon Bee' entry")
        assert.are.equals(5, beeEntry.count, "the bee pack count must equal BeesPerTenSeconds (5)")
        assert.is_true(beeEntry.dps > 0, "single bee DPS must be positive")
    end)

    it("the pack count tracks the count stat (10 bees = 10x single)", function()
        newBuild()
        build.configTab.input.customMods = "+5 Bees Per 10 Seconds\n"
        build.configTab:BuildModList()
        build.buildFlag = true
        runCallback("OnFrame")
        local function beeCountAndDps()
            for _, e in ipairs(build.calcsTab.mainOutput.SkillDPS or {}) do
                if e.name == "Summon Bee" then return e.count, e.dps end
            end
        end
        local c5, d5 = beeCountAndDps()
        assert.are.equals(5, c5)

        build.configTab.input.customMods = "+10 Bees Per 10 Seconds\n"
        build.configTab:BuildModList()
        build.buildFlag = true
        runCallback("OnFrame")
        local c10, d10 = beeCountAndDps()
        assert.are.equals(10, c10, "10-bee build must report a pack of 10")
        -- single-minion DPS is unchanged by the count; the multiplier is the count.
        assert.is_true(math.abs(d10 - d5) < 1e-6,
            "single-bee DPS must be count-independent (got d5=" .. tostring(d5) .. " d10=" .. tostring(d10) .. ")")
    end)

    it("Anurok pack count fills the FULL Companion Limit (2 base + bonus), not bonus-only", function()
        -- @leb-regression-guard:auto-summon-packcount-base-companions
        -- Chorus of the Anurok summons "up to your Companion Limit". The pack count is
        -- resolved via packCountStat=MaxCompanions, whose base 2 is added in CalcDefence
        -- (output.MaxCompanions), NOT as a modDB BASE mod -- so reading the raw modDB
        -- would undercount by 2 (count 5 instead of 7 here, ~FullDPS undercount).
        newBuild()
        build.configTab.input.customMods = "+5 Maximum Companions\n1 Summon Anuroks up to your Companion Limit\n"
        build.configTab:BuildModList()
        build.buildFlag = true
        runCallback("OnFrame")
        local out = build.calcsTab.mainOutput
        assert.are.equals(7, out.MaxCompanions, "MaxCompanions must be 2 base + 5 bonus = 7")
        local anurokEntry
        for _, e in ipairs(out.SkillDPS or {}) do
            if (e.skillPart and tostring(e.skillPart):find("Anurok", 1, true))
                or (e.name and tostring(e.name):find("Anurok", 1, true)) then anurokEntry = e end
        end
        assert.is_not_nil(anurokEntry, "Full DPS must list an Anurok entry")
        assert.are.equals(7, anurokEntry.count,
            "Anurok pack count must equal the FULL Companion Limit (2 base + 5 = 7), not the bonus-only 5")
    end)

    it("source contract: packCountStat resolves from the COMPUTED player output (base companions)", function()
        local f = io.open("Modules/Calcs.lua", "r") or io.open("src/Modules/Calcs.lua", "r")
        assert.is_not_nil(f, "must read Modules/Calcs.lua")
        local cc = f:read("*a"); f:close()
        assert.is_truthy(cc:find("usedEnv.player.output[sg.autoSummonPackCountStat]", 1, true),
            "packCountStat must read the computed player output (includes base companions), not raw modDB")
    end)

    it("a build with NO bee stat injects no SummonBee and leaves other minions at count 1", function()
        newBuild()
        build.configTab.input.customMods = ""
        build.configTab:BuildModList()
        build.buildFlag = true
        runCallback("OnFrame")
        for _, s in ipairs(build.calcsTab.mainEnv.player.activeSkillList) do
            local sg = s.socketGroup
            assert.is_falsy(sg and sg.autoSummonCountStat,
                "no auto-summon stat -> no group may carry autoSummonCountStat")
            if sg then
                assert.is_falsy(sg.source and tostring(sg.source):find("AutoSummon:", 1, true),
                    "no AutoSummon source group may be created without a count stat")
            end
        end
    end)
end)

-- @leb-regression-guard:auto-summon-registry
-- @leb-regression-guard:auto-summon-pack-dps
-- Phase B (datamine v1): three gear-granted auto-summons reuse the Phase A
-- framework. Each summon skill's dangling minionList was fixed to the real
-- minions.json key and the minion's PRIMARY attack skill encoded in skills.json.
describe("AutoSummon Phase B registry (T-Rex / Tolmat / Anurok)", function()
    local byStat
    setup(function()
        byStat = {}
        for _, e in ipairs(data.autoSummons) do byStat[e.countStat] = e.summonSkill end
    end)

    it("the three Phase B count stats map to their summon skills", function()
        assert.are.equals("Summon Giant T_Rex Minion", byStat["TyrannosaursSummoned"])
        assert.are.equals("Summon Tolmat Minion", byStat["TolmatHistoricMinions"])
        assert.are.equals("Summon AncientOasis01 Primordial Minion", byStat["AnuroksSummoned"])
    end)

    it("each Phase B summon skill's minionList resolves and its primary attack is encoded", function()
        local cases = {
            { skill = "Summon Giant T_Rex Minion",               minion = "PrimalTyrannosaur",  attack = "Giant T_Rex 01 Bite",            base = 125 },
            { skill = "Summon Tolmat Minion",                    minion = "TolmatMinionDivine", attack = "RahyehFactionSwarmer 01 Melee",  base = 16 },
            { skill = "Summon AncientOasis01 Primordial Minion", minion = "PrimalAnurok",       attack = "AncientOasis01 04 TongueSlap",   base = 30 },
        }
        for _, c in ipairs(cases) do
            assert.are.equals(c.minion, data.skills[c.skill].minionList[1], c.skill .. " minionList must resolve")
            assert.is_table(data.minions[c.minion], c.minion .. " must exist in minions.json")
            local atk = data.skills[c.attack]
            assert.is_table(atk, c.attack .. " primary attack must be encoded")
            assert.are.equals(c.base, atk.stats.melee_base_physical_damage,
                c.attack .. " base physical damage must match datamine")
            assert.is_truthy(atk.fromMinion, c.attack .. " must be a minion skill")
            -- the encoded attack must be index 1 of the minion's resolvable kit
            -- (secondaries/buffs are not encoded, so they are skipped)
            assert.are.equals(c.attack, data.minions[c.minion].skillList[
                (function()
                    for i, sid in ipairs(data.minions[c.minion].skillList) do
                        if data.skills[sid] then return i end
                    end
                end)()],
                c.attack .. " must be the first RESOLVABLE skill in the minion's skillList")
        end
    end)
end)

describe("AutoSummon Phase B ModParser (count stats not empty)", function()
    -- Uncached values force a LIVE parse (bypassing the rebaked ModCache rows).
    it("'+50% Summons Tyrannosaur Minion' -> TyrannosaursSummoned BASE 1 (count is fixed, not the %)", function()
        local mods, extra = modLib.parseMod("+50% Summons Tyrannosaur Minion")
        assert.is_nil(extra, "must parse cleanly (was an empty parse with residue)")
        assert.are.equals(1, #mods)
        assert.are.equals("TyrannosaursSummoned", mods[1].name)
        assert.are.equals("BASE", mods[1].type)
        assert.are.equals(1, mods[1].value, "the '%%' is a magnitude, not a count -> always 1")
    end)

    it("'+3 Tolmat's Historic Minions' -> TolmatHistoricMinions BASE 3 (count = N)", function()
        local mods, extra = modLib.parseMod("+3 Tolmat's Historic Minions")
        assert.is_nil(extra)
        assert.are.equals("TolmatHistoricMinions", mods[1].name)
        assert.are.equals("BASE", mods[1].type)
        assert.are.equals(3, mods[1].value)
    end)

    it("'2 Summon Anuroks up to your Companion Limit' -> AnuroksSummoned BASE 1 (conservative v1)", function()
        local mods, extra = modLib.parseMod("2 Summon Anuroks up to your Companion Limit")
        assert.is_nil(extra)
        assert.are.equals("AnuroksSummoned", mods[1].name)
        assert.are.equals("BASE", mods[1].type)
        assert.are.equals(1, mods[1].value, "v1 parses a presence flag (1), not the pack size")
    end)
end)

describe("AutoSummon Phase B ModCache (rebaked rows, not empty)", function()
    local cacheText
    setup(function() cacheText = readSource("Data/ModCache.lua") end)

    it("the Tyrannosaur / Tolmat / Anurok rows hold real BASE count mods", function()
        assert.is_truthy(string.find(cacheText,
            'c["+100% Summons Tyrannosaur Minion"]={{[1]={flags=0,keywordFlags=0,name="TyrannosaursSummoned",type="BASE",value=1}},nil}', 1, true),
            "Tyrannosaur row must be rebaked")
        assert.is_truthy(string.find(cacheText,
            'c["+1 Tolmat\'s Historic Minions"]={{[1]={flags=0,keywordFlags=0,name="TolmatHistoricMinions",type="BASE",value=1}},nil}', 1, true),
            "Tolmat row must be rebaked")
        assert.is_truthy(string.find(cacheText,
            'c["1 Summon Anuroks up to your Companion Limit"]={{[1]={flags=0,keywordFlags=0,name="AnuroksSummoned",type="BASE",value=1}},nil}', 1, true),
            "Anurok row must be rebaked")
    end)

    it("no stale empty-parse residue remains for the Phase B rows", function()
        assert.is_nil(string.find(cacheText, ' Summons Tyrannosaur  "}', 1, true))
        assert.is_nil(string.find(cacheText, 'lmat\'s Historic s "}', 1, true))
    end)
end)

describe("AutoSummon Phase B end-to-end", function()
    local function findEntry(name)
        for _, e in ipairs(build.calcsTab.mainOutput.SkillDPS or {}) do
            if e.name == name then return e end
        end
    end

    it("'+100% Summons Tyrannosaur Minion' injects a 1-T-Rex pack into Full DPS", function()
        newBuild()
        build.configTab.input.customMods = "+100% Summons Tyrannosaur Minion\n"
        build.configTab:BuildModList()
        build.buildFlag = true
        runCallback("OnFrame")

        local injected
        for _, s in ipairs(build.calcsTab.mainEnv.player.activeSkillList) do
            local sg = s.socketGroup
            if sg and sg.source == "AutoSummon:TyrannosaursSummoned" then injected = s end
        end
        assert.is_not_nil(injected, "Summon Giant T_Rex Minion must be injected")
        assert.is_true(injected.socketGroup.includeInFullDPS, "must be in Full DPS")
        assert.are.equals("TyrannosaursSummoned", injected.socketGroup.autoSummonCountStat)

        local e = findEntry("Summon Primal Tyrannosaur")
        assert.is_not_nil(e, "Full DPS must list the T-Rex")
        assert.are.equals(1, e.count, "T-Rex is always a pack of 1")
        assert.is_true(e.dps > 0, "T-Rex must produce non-zero DPS (Bite 125 phys encoded)")
    end)

    it("'+3 Tolmat's Historic Minions' injects a 3-Tolmat pack (count = N)", function()
        newBuild()
        build.configTab.input.customMods = "+3 Tolmat's Historic Minions\n"
        build.configTab:BuildModList()
        build.buildFlag = true
        runCallback("OnFrame")

        local e = findEntry("Summon Historic Minion")
        assert.is_not_nil(e, "Full DPS must list the Tolmat minion")
        assert.are.equals(3, e.count, "Tolmat pack count must equal the stat (3)")
        assert.is_true(e.dps > 0, "Tolmat must produce non-zero DPS (Melee 16 phys encoded)")
    end)

    it("Anurok count = MaxCompanions (packCountStat), gated by AnuroksSummoned, not the gate's 1", function()
        -- GATE AnuroksSummoned=1 (only Chorus sets it) but the PACK fills the
        -- companion limit -> count must resolve MaxCompanions, not the gate's 1.
        newBuild()
        build.configTab.input.customMods = "1 Summon Anuroks up to your Companion Limit\n+5 Maximum Companions\n"
        build.configTab:BuildModList()
        build.buildFlag = true
        runCallback("OnFrame")
        local injected
        for _, s in ipairs(build.calcsTab.mainEnv.player.activeSkillList) do
            local sg = s.socketGroup
            if sg and sg.source == "AutoSummon:AnuroksSummoned" then injected = s end
        end
        assert.is_not_nil(injected, "Summon Anurok must be injected (gate AnuroksSummoned > 0)")
        assert.are.equals("MaxCompanions", injected.socketGroup.autoSummonPackCountStat,
            "Anurok group must carry packCountStat = MaxCompanions")
        local e = findEntry("Summon Anurok")
        assert.is_not_nil(e, "Full DPS must list the Anurok")
        assert.is_true(e.count >= 5,
            "Anurok pack count must track MaxCompanions (>=5 with +5), NOT the gate value 1 (got " .. tostring(e.count) .. ")")
        assert.is_true(e.dps > 0, "Anurok must produce non-zero DPS (Tongue Slap 30 phys encoded)")
    end)
end)

-- @leb-regression-guard:auto-summon-registry
-- @leb-regression-guard:auto-summon-pack-dps
-- Queen Bee: granted by the Apiarist's Set 3-piece bonus "Summon the Queen Bee"
-- (a SET BONUS string, parsed via modLib.parseMod in CalcSetup.applySetBonuses,
-- NOT an item affix). A NEW summon skill SummonQueenBee was added (none existed);
-- its QueenBee minion's primary attack (Scratch 60 phys, eff 3) is encoded.
describe("AutoSummon Queen Bee (Apiarist set bonus)", function()
    it("registry maps QueenBeeSummoned -> SummonQueenBee and the skill resolves", function()
        local byStat = {}
        for _, e in ipairs(data.autoSummons) do byStat[e.countStat] = e.summonSkill end
        assert.are.equals("SummonQueenBee", byStat["QueenBeeSummoned"])
        local sk = data.skills.SummonQueenBee
        assert.is_table(sk, "SummonQueenBee must exist in data.skills")
        assert.are.equals("Summon Queen Bee", sk.name)
        assert.are.equals("QueenBee", sk.minionList[1])
        assert.is_table(data.minions.QueenBee, "minions.json must have QueenBee")
    end)

    it("the Queen's primary attack (Scratch 60 phys) is the first resolvable skill", function()
        local atk = data.skills["Queen Bee 01 Scratch"]
        assert.is_table(atk, "Scratch must be encoded")
        assert.are.equals(60, atk.stats.melee_base_physical_damage)
        assert.are.equals(3, atk.stats.damageEffectiveness)
        assert.is_truthy(atk.fromMinion)
        local first
        for _, sid in ipairs(data.minions.QueenBee.skillList) do
            if data.skills[sid] then first = sid; break end
        end
        assert.are.equals("Queen Bee 01 Scratch", first,
            "Scratch must be index-1 of the resolvable kit (Explosion/Quadruple deferred)")
    end)

    it("'Summon the Queen Bee' (set-bonus string) parses to QueenBeeSummoned BASE 1", function()
        local mods, extra = modLib.parseMod("Summon the Queen Bee")
        assert.is_nil(extra, "must parse cleanly")
        assert.are.equals(1, #mods)
        assert.are.equals("QueenBeeSummoned", mods[1].name)
        assert.are.equals("BASE", mods[1].type)
        assert.are.equals(1, mods[1].value)
    end)

    it("'Summon the Queen Bee' injects a 1-Queen pack into Full DPS", function()
        newBuild()
        build.configTab.input.customMods = "Summon the Queen Bee\n"
        build.configTab:BuildModList()
        build.buildFlag = true
        runCallback("OnFrame")
        local injected
        for _, s in ipairs(build.calcsTab.mainEnv.player.activeSkillList) do
            local sg = s.socketGroup
            if sg and sg.source == "AutoSummon:QueenBeeSummoned" then injected = s end
        end
        assert.is_not_nil(injected, "SummonQueenBee must be injected")
        assert.is_true(injected.socketGroup.includeInFullDPS, "must be in Full DPS")
        local e
        for _, x in ipairs(build.calcsTab.mainOutput.SkillDPS or {}) do
            if x.name == "Summon Queen Bee" then e = x end
        end
        assert.is_not_nil(e, "Full DPS must list the Queen Bee")
        assert.are.equals(1, e.count, "Queen Bee is always a pack of 1")
        assert.is_true(e.dps > 0, "Queen Bee must produce non-zero DPS (Scratch 60 phys encoded)")
    end)
end)
