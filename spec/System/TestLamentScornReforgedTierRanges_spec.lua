-- @leb-regression-guard: lament-scorn-reforged-tier-ranges
-- "The Last Bear's Lament Reforged" (statOrderKey 802) and
-- "The Last Bear's Scorn Reforged" (statOrderKey 803) are tiered unique
-- mods (T0..T7) appearing on the Last Bear set helmets. LE 1.4.5 silently
-- bumped both families' Health Regen / Endurance Threshold / Endurance %
-- ranges. Prior to the bump LEB underestimated Endurance Threshold by
-- ~half on T6-T7 tiers (e.g. BxvJP3g1 lv99 Necromancer triangulation
-- showed ET -130 vs in-game until 802_6 was corrected).
--
-- This spec locks in the T7 (top-tier, largest absolute miss) max value
-- for each statOrderKey. If anyone reverts to pre-1.4.5 ranges the test
-- fails with the exact offending entry.
--
-- See REGRESSION_GUARDS.md "lament-scorn-reforged-tier-ranges" for the
-- full tier table and triangulation evidence.

describe("LamentScornReforgedTierRanges", function()
    local cjson_ok, cjson = pcall(require, "lua.dkjson")
    if not cjson_ok then cjson_ok, cjson = pcall(require, "dkjson") end

    local function loadModItem()
        local f = assert(io.open("../src/Data/ModItem_1_4.json", "r"))
        local data = f:read("*a")
        f:close()
        if cjson_ok and cjson.decode then
            return cjson.decode(data)
        end
        return data
    end

    local function readAffixLine(modItem, key, lineKey)
        if type(modItem) == "table" then
            local entry = modItem[key]
            assert.is_not_nil(entry, "missing affix entry: " .. key)
            local text = entry[lineKey]
            assert.is_not_nil(text, "missing line " .. lineKey .. " on " .. key)
            return text
        else
            local idx = modItem:find('"' .. key .. '"%s*:')
            assert.is_not_nil(idx, "missing affix entry: " .. key)
            local sub = modItem:sub(idx, idx + 1200)
            local text = sub:match('"' .. lineKey .. '"%s*:%s*"([^"]+)"')
            return text
        end
    end

    -- Last Bear's Lament Reforged: T0-T7 Health Regen + Endurance Threshold.
    -- "1" = Health Regen, "2" = Endurance Threshold.
    -- Ranges are LE 1.4.5 values (verified vs in-game Bazaar affix detail panel).
    local lamentCases = {
        { "802_0", "1", "+(3-4) Health Regen",         "T0 HP regen" },
        { "802_0", "2", "+(30-53) Endurance Threshold", "T0 ET" },
        { "802_3", "1", "+(9-10) Health Regen",        "T3 HP regen" },
        { "802_3", "2", "+(102-125) Endurance Threshold", "T3 ET" },
        { "802_6", "1", "+(24-30) Health Regen",       "T6 HP regen (was 16-20)" },
        { "802_6", "2", "+(240-300) Endurance Threshold", "T6 ET (was 120-150)" },
        { "802_7", "1", "+(48-60) Health Regen",       "T7 HP regen (was 32-40)" },
        { "802_7", "2", "+(480-600) Endurance Threshold", "T7 ET (was 240-300)" },
    }

    -- Last Bear's Scorn Reforged: T0-T7 Endurance% + Phys Leech.
    -- "1" = Endurance %.
    local scornCases = {
        { "803_0", "1", "+(10-12)% Endurance", "T0 Endurance% (was 6-7)" },
        { "803_3", "1", "+(19-21)% Endurance", "T3 Endurance% (was 12-13)" },
        { "803_6", "1", "+(43-50)% Endurance", "T6 Endurance% (was 25-30)" },
        { "803_7", "1", "+(80-100)% Endurance", "T7 Endurance% (was 48-60)" },
    }

    describe("Lament Reforged (802_*) ranges match LE 1.4.5", function()
        local modItem = loadModItem()
        for _, row in ipairs(lamentCases) do
            local key, lineKey, expectedSubstring, note = row[1], row[2], row[3], row[4]
            it(key .. " line " .. lineKey .. " has " .. note, function()
                local text = readAffixLine(modItem, key, lineKey)
                assert.is_truthy(text and text:find(expectedSubstring, 1, true),
                    string.format("Expected '%s' in %s.%s, got '%s'",
                        expectedSubstring, key, lineKey, tostring(text)))
            end)
        end
    end)

    describe("Scorn Reforged (803_*) ranges match LE 1.4.5", function()
        local modItem = loadModItem()
        for _, row in ipairs(scornCases) do
            local key, lineKey, expectedSubstring, note = row[1], row[2], row[3], row[4]
            it(key .. " line " .. lineKey .. " has " .. note, function()
                local text = readAffixLine(modItem, key, lineKey)
                assert.is_truthy(text and text:find(expectedSubstring, 1, true),
                    string.format("Expected '%s' in %s.%s, got '%s'",
                        expectedSubstring, key, lineKey, tostring(text)))
            end)
        end
    end)

    it("spec file carries the @leb-regression-guard marker", function()
        local f = assert(io.open("../spec/System/TestLamentScornReforgedTierRanges_spec.lua", "r"))
        local text = f:read("*a"); f:close()
        assert.is_truthy(text:find("@leb-regression-guard: lament-scorn-reforged-tier-ranges", 1, true),
            "guard marker missing from spec file")
    end)
end)
