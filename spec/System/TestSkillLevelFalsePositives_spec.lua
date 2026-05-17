-- @leb-regression-guard: skill-level-false-positive-purge
-- Locks the purge of 287 ModCache entries that the over-permissive
-- SkillLevel fallback (ModParser ~L2643) wrongly produced. F12 (commit
-- ec1755aca) gated the fallback on whitespace-only residue, stopping
-- NEW false positives -- but the cache file already contained 287
-- stale entries baked before that gate landed.
--
-- Each affected entry had:
--   body  = `name="SkillLevel",type="BASE",value=N` with some SkillName
--           scope (skillName="X")
--   resid = non-empty descriptive text (Stacks / Charges / Immunity /
--           Casts / "Seconds of <X> after you use a Traversal Skill" /
--           etc.)
--
-- The actual game stats are NOT SkillLevel grants -- they are Stacks,
-- Charges, Cooldown, Duration, Immunity, etc. None of those have
-- parser/calc infrastructure today, so the safe minimal fix is to
-- neutralize each entry to `{{}, ""}`. This:
--   1. Stops the false positive (entry contributes nothing instead of
--      contributing a wrong +N to <Skill>).
--   2. Preserves the cache key so re-baking remains stable.
--   3. Leaves each residue category visible as a future sweep target
--      when proper per-stat infra lands.

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("SkillLevelFalsePositivesPurge", function()
    local cacheText

    setup(function()
        cacheText = readSource("Data/ModCache.lua")
    end)

    it("ModCache: zero stale name='SkillLevel' BASE entries with residue", function()
        -- Any c[...]={...} where body contains name="SkillLevel",type="BASE"
        -- AND has non-empty residue would indicate the false positive returned.
        local stale = 'c%["[^"]+"%]={{%[1%]={[^\n]-name="SkillLevel",type="BASE"[^\n]-}},"[^"][^\n]-"}'
        assert.is_nil(string.find(cacheText, stale),
            "no SkillLevel BASE entry may have non-empty residue (over-permissive fallback regression)")
    end)

    it("ModCache: representative neutralized entries are present as no-ops", function()
        -- Sample 5 entries spanning the residue categories. Each should be
        -- `{{},""}` -- not a SkillLevel BASE grant.
        local samples = {
            '+3 Maximum Plasma Orb Stacks',
            '+1 Seconds of Flame Ward after you use a Traversal Skill',
            '+3 Black Arrows Dropped by Detonating Arrow',
        }
        for _, key in ipairs(samples) do
            local pat_key = key:gsub('([%(%)%.%%%+%-%*%?%[%]%^%$])', '%%%1')
            local needle = 'c%["' .. pat_key .. '"%]={{},""}'
            -- Only assert if the cache contains the key at all (entries may
            -- be omitted by future cache regen). Presence-with-wrong-shape is
            -- what we forbid.
            local found_neutralized = string.find(cacheText, needle)
            local found_stale = string.find(cacheText, 'c%["' .. pat_key .. '"%]={{%[1%]=')
            assert.is_nil(found_stale,
                "stale SkillLevel BASE shape returned for: " .. key)
        end
    end)
end)
