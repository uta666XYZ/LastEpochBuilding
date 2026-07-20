-- @leb-regression-guard: skill-grants-ward-per-second
-- Locks the ModParser channelling-loop handler for the Rune Master node
--   tree_1.json L10164 "Runes of Disintegration":
--     stats: "+40 Disintegrate Grants Ward Gain Per Second"
--     description: "channelling it while standing on your Glyph"
--
-- Before this guard the line fell through to `name="Ward"` (max ward) +
-- SkillName:Disintegrate tag with residue "  Grants  Gain Per Second ".
-- Allocating the node granted +40 max Ward attached to Disintegrate
-- damage rather than +40 WPS while channelling. Silent failure invisible
-- in any numeric Ward output diff.
--
-- The handler is registered inside the same per-skill loop that emits
-- `Channelling<Skill>` conditions for "ward per second while channelling
-- <skill>", so it inherits the same gating mechanic. The Glyph-on
-- sub-condition from the in-game description is the player's intended
-- play pattern and is not modelled — consistent with how the existing
-- channelling-WPS handlers also do not model positional sub-conditions.

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("SkillGrantsWardPerSecond", function()
    local parserText, cacheText

    setup(function()
        parserText = readSource("Modules/ModParser.lua")
        cacheText  = readSource("Data/ModCache.lua")
    end)

    it("ModParser registers the '<skill> grants ward gain per second' pattern", function()
        assert.is_truthy(string.find(parserText,
            ' grants ward gain per second%$', 1, false),
            "ModParser must register a '<skill> grants ward gain per second' specialModList handler")
        assert.is_truthy(string.find(parserText,
            'mod%("WardPerSecond", "BASE", num, "", 0, 0, { type = "Condition", var = _condVar }%)', 1, false),
            "Handler must emit WardPerSecond BASE conditional on Channelling<Skill>")
    end)

    it("ModCache '+40 Disintegrate Grants Ward Gain Per Second' resolves to conditional WardPerSecond", function()
        local needle = 'c%["%+40 Disintegrate Grants Ward Gain Per Second"%]={{%[1%]={%[1%]={type="Condition",var="ChannellingDisintegrate"},flags=0,keywordFlags=0,name="WardPerSecond",type="BASE",value=40}},nil}'
        assert.is_truthy(string.find(cacheText, needle, 1, false),
            "ModCache entry must produce WardPerSecond BASE=40 gated on ChannellingDisintegrate")
    end)

    it("ModCache must NOT carry the stale 'name=\"Ward\" + SkillName:Disintegrate' parse", function()
        assert.is_nil(string.find(cacheText,
            'c%["%+40 Disintegrate Grants Ward Gain Per Second"%]={{%[1%]={%[1%]={skillName="Disintegrate"', 1, false),
            "ModCache must not contain the stale max-Ward + SkillName parse for the Disintegrate Glyph node")
    end)
end)
