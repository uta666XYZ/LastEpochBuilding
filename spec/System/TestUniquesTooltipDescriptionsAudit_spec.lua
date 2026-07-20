-- @leb-regression-guard: uniques-tooltipdescriptions-per-char-level-floor
-- Regression FLOOR for the "dropped per-character-level tooltipDescription"
-- bug class (Frozen Ire #32, fixed <see git log>; Hammer of Lorent #41, this sweep).
--
-- Root cause of the class: in datamined game source a
-- unique's per-character-level scalars live ONLY in its `tooltipDescriptions`
-- block (bracket markup "[N,c]" / "[N,c,N]") and NEVER in the structured `mods`
-- roll table. Any transcription into LEB that walks the roll table alone
-- silently loses them. `spec/tools/audit_uniques_tooltipdescriptions.py`
-- (local, gitignored) re-derives the gap list from the datamining export; it
-- found that across all 471 uniques EXACTLY two carry bracket "[..,c,..]"
-- per-character-level lines: Frozen Ire (#32) and Hammer of Lorent (#41). Every
-- other "per <X>" tooltip line is per-stat / per-stack and was already modelled
-- (verified: Mourningfrost, Humming Bee, Vaions Chariot, Frostbite Shackles,
-- Urzils Pride, Sierpins Fractal Tree all present in LEB).
--
-- This spec pins the LEB side of that conclusion so a future datamined game source
-- regen / merge cannot silently re-drop the lines, and so adding per-char-level
-- scaling to a NEW unique forces a conscious update of the canonical set below
-- (the test fails until CANONICAL is updated, which is the intended gate).
--
-- NOT in scope (different scaling axis): "per Level of <Skill>" mods such as
-- Falcon Fists (#333) "+(12-16) Cinder Strike Melee Damage per Level of
-- Falconry While Unarmed" scale off a SKILL level, not the character level, and
-- use a different Multiplier var. They are explicitly excluded by the detector
-- (it rejects "per level of ...").
--
-- See REGRESSION_GUARDS.md "uniques-tooltipdescriptions-per-char-level-floor".
local dkjson = require("dkjson")

describe("UniquesTooltipDescriptionsAudit (per-char-level floor)", function()
    local function readFile(path)
        local f = assert(io.open(path, "r"), "missing: " .. path)
        local s = f:read("*a")
        f:close()
        return s
    end

    local uniques = dkjson.decode(readFile("Data/Uniques/uniques_1_4.json"))

    -- A mod is "per CHARACTER level" if it has a trailing "per [N] level" and is
    -- NOT a "per level of <skill>" (skill-level axis).
    local function isPerCharLevel(mod)
        local lower = mod:lower()
        if lower:find("per %d* ?level of ") or lower:find("per level of ") then
            return false
        end
        return lower:find("per %d* ?levels?%f[%A]") ~= nil
            or lower:find("per %d* ?levels?$") ~= nil
    end

    -- Canonical, audit-confirmed population of per-character-level uniques.
    -- id -> { name, expectedPerLevelModCount }
    local CANONICAL = {
        ["32"] = { name = "Frozen Ire",       count = 3 },
        ["41"] = { name = "Hammer of Lorent", count = 2 },
    }

    -- Collect actual per-char-level population from the LEB file.
    local actual = {}     -- id -> count
    for id, e in pairs(uniques) do
        if type(e) == "table" and type(e.mods) == "table" then
            local n = 0
            for _, m in ipairs(e.mods) do
                if isPerCharLevel(m) then n = n + 1 end
            end
            if n > 0 then actual[id] = n end
        end
    end

    it("the per-character-level population is EXACTLY the canonical set", function()
        -- every actual id must be canonical
        for id, n in pairs(actual) do
            assert.is_not_nil(CANONICAL[id],
                string.format("unexpected per-character-level mods on unique #%s (%s, %d lines) — "
                    .. "if this is a real new per-char-level unique, add it to CANONICAL "
                    .. "in this spec and write its own Test*TooltipDescriptionsMods_spec.lua",
                    id, (uniques[id] and uniques[id].name) or "?", n))
        end
        -- every canonical id must be present
        for id, want in pairs(CANONICAL) do
            assert.is_not_nil(actual[id],
                string.format("unique #%s (%s) lost its per-character-level mods — "
                    .. "datamined tooltipDescriptions were re-dropped", id, want.name))
        end
    end)

    it("each canonical unique carries the expected per-char-level mod count", function()
        for id, want in pairs(CANONICAL) do
            assert.are.equal(want.count, actual[id],
                string.format("unique #%s (%s): expected %d per-character-level mods, found %d",
                    id, want.name, want.count, actual[id] or 0))
            assert.are.equal(want.name, uniques[id].name,
                string.format("unique #%s name drift: expected %q", id, want.name))
        end
    end)

    it("excludes per-skill-level mods (Falcon Fists #333 is NOT per-char-level)", function()
        -- guards the detector against re-classifying "per Level of <skill>"
        assert.is_false(isPerCharLevel(
            "{rounding:Integer}+(12-16) Cinder Strike Melee Damage per Level of Falconry While Unarmed"))
        assert.is_true(isPerCharLevel("+1 Melee Physical Damage per level"))
        assert.is_true(isPerCharLevel("{rounding:Integer}+1 Spell Cold Damage per 5 level"))
    end)

    it("carries the @leb-regression-guard anchor at the spec head", function()
        local specSrc = readFile("../spec/System/TestUniquesTooltipDescriptionsAudit_spec.lua")
        assert.is_truthy(
            specSrc:find("@leb%-regression%-guard:%s*uniques%-tooltipdescriptions%-per%-char%-level%-floor"),
            "guard anchor must remain inline at the top of this spec")
    end)
end)
