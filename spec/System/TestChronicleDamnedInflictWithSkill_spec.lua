-- @leb-regression-guard:chronicle-damned-inflict-with-skill-per-spirit
-- Locks the ModParser rule that makes Chronicle of the Damned (unique id 247)
-- parse its "inflict" phrasing. Damned was the ONLY damaging ailment that had
-- "to apply damned" / "damned chance" but NOT the "to inflict damned" form that
-- every other ailment (bleed/ignite/poison/shock/chill/frostbite/...) registers.
--
-- Affix text (crafted, range 11-16):
--   "(11-16)% Chance to inflict Damned on Hit with Hungering Souls per Active
--    Wandering Spirit"
--
-- Bug: with no "to inflict damned" modNameList key the generic parse chain found
-- no modName and returned {} (empty modList) -> the whole affix silently dropped.
-- The consumer side is already fully modeled (DamnedChance @ CalcOffence L2532,
-- DamnedBaseDamage=35 Necrotic DoT, Multiplier:ActiveWanderingSpirit config), so
-- the ONLY gap was the parser entry point. The stale empty ModCache row
--   c["14% ... per Active Wandering Spirit"]={{}," to inflict   with Hungering Souls  "}
-- short-circuited the live parse (cache hit returns the empty modList) and was
-- deleted so the fix parses live.
--
-- Invariants locked:
--   1. The "inflict" phrasing parses to exactly one DamnedChance BASE mod carrying
--      BOTH a SkillName="Hungering Souls" tag and a Multiplier:ActiveWanderingSpirit
--      tag (ifMult scaler), with connector-only ("with") residue.
--   2. PARITY: the "inflict" form parses to the same mod name as the sanctioned
--      "apply" form (structural equality with the already-working mechanism).
--   3. The parse feeds the consumer: a plain "chance to inflict damned" yields the
--      same nonzero output.DamnedChance as "chance to apply damned" (end-to-end).
--   4. The stale empty ModCache row is gone (stale-row-no-longer-drops invariant).
--
-- See REGRESSION_GUARDS.md "chronicle-damned-inflict-with-skill-per-spirit".

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a"); f:close()
    return text
end

local function hasTag(mod, pred)
    for _, tag in ipairs(mod) do if pred(tag) then return true end end
    return false
end

local FULL = "13% Chance to inflict Damned on Hit with Hungering Souls per Active Wandering Spirit"

describe("ChronicleDamnedInflictWithSkill", function()
    local parserText, cacheText
    setup(function()
        newBuild()
        parserText = readSource("Modules/ModParser.lua")
        cacheText  = readSource("Data/ModCache.lua")
    end)

    it("inline guard marker present in ModParser.lua", function()
        assert.is_truthy(string.find(parserText, "chronicle-damned-inflict-with-skill-per-spirit", 1, true))
    end)

    it("registers the 'to inflict damned' modNameList key -> DamnedChance", function()
        assert.is_truthy(string.find(parserText, '%["to inflict damned"%]%s*=%s*"DamnedChance"'),
            "ModParser must map 'to inflict damned' to DamnedChance")
    end)

    it("full C9 phrasing parses to one DamnedChance BASE mod with SkillName + Multiplier tags", function()
        local list, extra = modLib.parseMod(FULL)
        assert.is_not_nil(list, "must parse: " .. FULL)
        assert.are.equals(1, #list, "exactly one mod")
        local m = list[1]
        assert.are.equals("DamnedChance", m.name)
        assert.are.equals("BASE", m.type)
        assert.are.equals(13, m.value)
        assert.is_true(hasTag(m, function(t) return t.type == "SkillName" and t.skillName == "Hungering Souls" end),
            "must carry SkillName=Hungering Souls tag")
        assert.is_true(hasTag(m, function(t) return t.type == "Multiplier" and t.var == "ActiveWanderingSpirit" end),
            "must carry Multiplier:ActiveWanderingSpirit tag (per-spirit scaler)")
        -- connector-only residue ("with") is accepted by Item.lua isConnectorOnlyExtra
        local trimmed = (extra or ""):lower():gsub("%s+", "")
        assert.are.equals("with", trimmed, "residue must be connector-only 'with', got: " .. tostring(extra))
    end)

    it("PARITY: 'inflict damned' parses to the same mod name as the sanctioned 'apply damned'", function()
        local inflictL = modLib.parseMod("13% Chance to inflict Damned on Hit")
        local applyL   = modLib.parseMod("13% Chance to apply Damned on Hit")
        assert.are.equals(1, #inflictL); assert.are.equals(1, #applyL)
        assert.are.equals(applyL[1].name, inflictL[1].name)   -- both DamnedChance
        assert.are.equals(applyL[1].type, inflictL[1].type)   -- both BASE
        assert.are.equals(applyL[1].value, inflictL[1].value)
    end)

    it("end-to-end: parse feeds the consumer identically to 'apply damned'", function()
        local function damnedChanceOf(mods)
            newBuild()
            build.skillsTab:SelSkill(1, "Hungering Souls")
            build.configTab.input.customMods = mods
            build.configTab:BuildModList(); runCallback("OnFrame")
            build.calcsTab:BuildOutput()
            return build.calcsTab.mainOutput.DamnedChance
        end
        local inflict = damnedChanceOf("11% chance to inflict damned")
        local apply   = damnedChanceOf("11% chance to apply damned")
        assert.are.equals(apply, inflict, "inflict must yield the same DamnedChance as apply")
        assert.is_true((inflict or 0) > 0, "inflict damned must produce nonzero DamnedChance (was silently dropped before the fix)")
    end)

    it("stale empty ModCache row for the affix is gone (no longer short-circuits live parse)", function()
        assert.is_nil(string.find(cacheText, "inflict Damned on Hit with Hungering Souls per Active Wandering Spirit", 1, true),
            "the stale empty ModCache row must be deleted so the affix parses live")
    end)
end)
