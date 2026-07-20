-- @leb-regression-guard:stygian-coal-per-int-castfreq
-- Locks the ModParser rule that makes Stygian Coal (unique id 328) parse its
-- per-Intelligence cast-frequency affix into a skill-scoped INC Speed modifier.
--
-- Affix text (uniques.json id 328, verbatim):
--   "1% increased Stygian Beam frequency per Intelligence"
--
-- Stygian Beam is the player-cast spell Drain Life fires when Stygian Coal is
-- equipped ("+1 Drain Life casts Stygian Beams instead"); it is a real modeled
-- skill (Data/skills.json "Drain Life Stygian Beam" -> name "Stygian Beam",
-- castTime 0.6818182, playerAbilityID lb23il). "frequency" = casts/second = the
-- skill's cast rate, i.e. an INC Speed scoped to that one skill.
--
-- Bug: there is no "frequency" modName alias, so the generic parse chain left
-- "frequency" as residue and returned {} (empty modList) -> the affix silently
-- dropped. The stale empty ModCache row
--   c["1% increased Stygian Beam frequency per Intelligence"]={{},"  frequency  "}
-- short-circuited the live parse (cache hit returns the empty modList) and was
-- deleted so the fix parses live. The consumer already exists (no new primitive):
-- CalcOffence.lua ~L2174 Sum("INC", cfg, "Speed") -> output.Speed/output.CastRate,
-- with the SkillName tag matched against cfg.skillName in ModStore.lua:762.
--
-- Invariants locked:
--   1. The phrasing parses to exactly one INC Speed mod carrying BOTH a
--      PerStat=Int tag and a SkillName="Stygian Beam" tag, value 1, residue-free.
--   2. Per-stat shape parity with the tyrannosaur/ballista attack-speed handlers:
--      an INC "Speed" mod (same modName the cast-rate consumer sums).
--   3. The stale empty ModCache row is gone (stale-row-no-longer-drops invariant).
--
-- See REGRESSION_GUARDS.md "stygian-coal-per-int-castfreq".

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

local FULL = "1% increased Stygian Beam frequency per Intelligence"

describe("StygianCoalPerIntCastFreq", function()
    local parserText, cacheText
    setup(function()
        newBuild()
        parserText = readSource("Modules/ModParser.lua")
        cacheText  = readSource("Data/ModCache.lua")
    end)

    it("inline guard marker present in ModParser.lua", function()
        assert.is_truthy(string.find(parserText, "stygian-coal-per-int-castfreq", 1, true))
    end)

    it("affix parses to exactly one INC Speed mod (value 1)", function()
        local list = modLib.parseMod(FULL)
        assert.is_not_nil(list, "must parse: " .. FULL)
        assert.are.equals(1, #list, "exactly one mod")
        local m = list[1]
        assert.are.equals("Speed", m.name)
        assert.are.equals("INC", m.type)
        assert.are.equals(1, m.value)
    end)

    it("carries a PerStat=Int tag and a SkillName='Stygian Beam' tag", function()
        local m = modLib.parseMod(FULL)[1]
        assert.is_true(hasTag(m, function(t) return t.type == "PerStat" and t.stat == "Int" end),
            "must carry PerStat=Int tag (per Intelligence)")
        assert.is_true(hasTag(m, function(t) return t.type == "SkillName" and t.skillName == "Stygian Beam" end),
            "must carry SkillName='Stygian Beam' tag (scopes the cast-rate scaling to the one skill)")
    end)

    it("is residue-free (whole-line handler, extra=nil)", function()
        local _, extra = modLib.parseMod(FULL)
        local trimmed = (extra or ""):lower():gsub("%s+", "")
        assert.are.equals("", trimmed, "residue must be empty, got: " .. tostring(extra))
    end)

    it("stale empty ModCache row for the affix is gone (no longer short-circuits live parse)", function()
        assert.is_nil(string.find(cacheText, FULL, 1, true),
            "the stale empty ModCache row must be deleted so the affix parses live")
    end)
end)
