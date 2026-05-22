-- @leb-regression-guard: unbroken-charge-block-effectiveness-per-ms-letools-artifact
-- Locks the LEB-correct / LET-wrong split on Unbroken Charge's
-- "+(11-30) Block Effectiveness per 1% Increased Movement Speed"
-- mod. LEB matches the in-game tooltip text verbatim (range:215 →
-- coefficient 27 BE per 1% MS on AVa9YEkg, contributing 27×29 = 783
-- to BlockEffectiveness). LE's planner ("LETools") reports +401 for
-- the same line because LE's `unique_mods_postprocessed.json` /
-- `unique_overrides.json` ship the in-game tooltip text whose value
-- ranges are SWAPPED vs the property-regenerated truth in
-- `unique_mods_regen.json` — LET's recompute path reads the actual
-- property value range (13-25) but with the WRONG ModRange index
-- (`range:18`, the Haste roll), producing 13.85 × 29 ≈ 401.
--
-- See REGRESSION_GUARDS.md entry
-- `unbroken-charge-block-effectiveness-per-ms-letools-artifact` for
-- the full math and rationale. This spec pins the LEB-side unique
-- data shape so that any future LE data-mining refresh that
-- collapses the postprocessed/regen swap (and which would in turn
-- require LEB to update its parse + recompute the expected
-- snapshot) fires here and forces a re-evaluation.

local function readFile(relPath)
    local candidates = { relPath, "src/" .. relPath, "../src/" .. relPath }
    for _, p in ipairs(candidates) do
        local f = io.open(p, "r")
        if f then
            local text = f:read("*a")
            f:close()
            return text
        end
    end
    error("must be able to open " .. relPath)
end

describe("UnbrokenChargeBELetoolsArtifact", function()
    local text
    setup(function()
        text = readFile("Data/Uniques/uniques_1_4.json")
    end)

    it("Unbroken Charge entry exists in uniques_1_4.json", function()
        assert.is_truthy(string.find(text, '"name"%s*:%s*"Unbroken Charge"'),
            "uniques_1_4.json must still define Unbroken Charge")
    end)

    it("BE-per-MS mod text still reads '+(11-30)' (the LE postprocessed/overrides shape)", function()
        -- This is the in-game tooltip wording; LEB parses it verbatim and
        -- produces the LEB-correct, LET-wrong-by-+382 BlockEffectiveness.
        -- If the upstream LE data drops the swap and reflows this to
        -- '+(13-25)', this assertion fires and the guard must be revisited.
        assert.is_truthy(
            string.find(text,
                "%+%(11%-30%) Block Effectiveness per 1%% Increased Movement Speed",
                1, false),
            "uniques_1_4.json must keep '+(11-30) Block Effectiveness per 1% Increased Movement Speed'")
    end)

    it("Haste chance mod text still reads '(13-25)%' (paired half of the LE template swap)", function()
        assert.is_truthy(
            string.find(text,
                "%(13%-25%)%% chance to gain Haste for 5 seconds after you Block",
                1, false),
            "uniques_1_4.json must keep '(13-25)% chance to gain Haste...' alongside the +(11-30) BE line")
    end)
end)
