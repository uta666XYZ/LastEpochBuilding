-- @leb-regression-guard: unique-hideintooltip-letools-artifact
-- Locks the data-hygiene rule for unique mods whose game source has
-- `hideInTooltip=true` AND no descriptors.json entry: the LEB string is
-- a LETools fallback-formatter artifact and must be either deleted
-- (pure descriptive flag) or stripped of its `+N ` prefix (covered by
-- game tooltipDescriptions). See REGRESSION_GUARDS.md entry
-- `unique-hideintooltip-letools-artifact` for full rationale.
--
-- Anchor cases:
--   - Black Blade of Chaos (uniqueID=339) Mod[0] purged entirely
--   - The Claw  (uniqueID=58) Mod[2] keeps the game-verbatim form
--   - The Fang  (uniqueID=60) Mod[3] keeps the game-verbatim form
--   - ModCache MUST NOT carry a +1-prefixed Wolves entry (the prior
--     entry incorrectly mapped to MaxCompanions BASE +1, contradicting
--     the in-game altText "Does not increase your maximum number of
--     companions.")

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

local UNIQUE_JSONS = {
    "Data/Uniques/uniques.json",
    "Data/Uniques/uniques_1_2.json",
    "Data/Uniques/uniques_1_3.json",
    "Data/Uniques/uniques_1_4.json",
}

describe("UniqueHideInTooltipLETools", function()

    -- Case 1: pure descriptive flag (no tooltipDescription) -> purged.
    describe("Black Blade of Chaos quick-attack flag (purged)", function()
        for _, path in ipairs(UNIQUE_JSONS) do
            it(path .. " must not contain the purged LETools string", function()
                local text = readFile(path)
                assert.is_nil(
                    string.find(text,
                        "%+1 Lethal Mirage is a quick attack with no invulnerability",
                        1, false),
                    path .. " must not carry the descriptive flag"
                )
            end)
        end

        it("ModCache must not retain the no-op entry", function()
            local text = readFile("Data/ModCache.lua")
            assert.is_nil(
                string.find(text,
                    '%+1 Lethal Mirage is a quick attack with no invulnerability',
                    1, false),
                "ModCache must not carry a stale no-op key for the purged string"
            )
        end)
    end)

    -- Case 2: game tooltipDescription covers it -> `+N ` prefix stripped.
    describe("Claw/Fang Wolves flag (prefix stripped)", function()
        for _, path in ipairs(UNIQUE_JSONS) do
            it(path .. " must carry the game-verbatim form", function()
                local text = readFile(path)
                assert.is_truthy(
                    string.find(text,
                        '"You can Summon Wolves up to your Maximum Number of Companions"',
                        1, true),
                    path .. " must contain the stripped game-verbatim string"
                )
            end)

            it(path .. " must NOT carry the LETools +1-prefixed form", function()
                local text = readFile(path)
                assert.is_nil(
                    string.find(text,
                        '"%+1 You can Summon Wolves up to your Maximum Number of Companions"'),
                    path .. " must not contain the LETools fallback prefix"
                )
            end)
        end

        it("ModCache must not carry the wrong-stat +1 Wolves entry", function()
            local text = readFile("Data/ModCache.lua")
            assert.is_nil(
                string.find(text,
                    '%+1 You can Summon Wolves up to your Maximum Number of Companions',
                    1, false),
                "ModCache must not carry an entry that maps the LETools +1 form " ..
                "to MaxCompanions BASE -- the in-game altText explicitly states " ..
                "'Does not increase your maximum number of companions.'"
            )
        end)
    end)

    it("REGRESSION_GUARDS.md indexes this guard", function()
        local text = readFile("../REGRESSION_GUARDS.md")
        assert.is_truthy(
            string.find(text, "unique%-hideintooltip%-letools%-artifact", 1, false),
            "REGRESSION_GUARDS.md must index the unique-hideintooltip-letools-artifact guard"
        )
    end)
end)
