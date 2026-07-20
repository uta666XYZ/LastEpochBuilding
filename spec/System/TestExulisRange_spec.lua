-- @leb-regression-guard: exulis-all-attributes-range
-- Locks the Exulis amulet (id 469) "+(10-20) to All Attributes" range.
--
-- Evidence for (10-20):
--   1. Game data extract: uniques_v3.json id=469 mod[1] has
--      value=10.0, maxValue=20.0 (property=46 = All Attributes).
--   2. LETools tooltip displays "+(10 to 20) to All Attributes".
--   3. applyRange trace with (10-20) and the span+1 rule reproduces
--      the in-game display: byte=156 -> 10 + 156/255 * (20-10+1)
--      = 10 + 156/255 * 11 = 16.73 -> floor = 16. Matches the user's
--      observed +16 in LEB once the data was corrected.
--
-- The earlier (10-18) value was a regression introduced from a
-- misobservation (a +18 roll that was actually 16 attribute + 2 from
-- the separate quest reward). Do NOT reintroduce (10-18).
--
-- See REGRESSION_GUARDS.md "exulis-all-attributes-range".

describe("ExulisAllAttributesRange", function()
    local files = {
        "Data/Uniques/uniques_1_4.json",
        "Data/Uniques/uniques.json",
    }

    for _, path in ipairs(files) do
        it(path .. " has Exulis '+(10-20) to All Attributes'", function()
            local f = io.open(path, "r")
            assert.is_not_nil(f, "must be able to open " .. path)
            local text = f:read("*a")
            f:close()
            -- Find the Exulis entry and assert the All Attributes mod string.
            local exulisStart = string.find(text, '"name": "Exulis"', 1, true)
            assert.is_not_nil(exulisStart, "Exulis entry must exist in " .. path)
            -- Look in a window after the name for the mod line.
            local window = string.sub(text, exulisStart, exulisStart + 1500)
            assert.is_truthy(string.find(window, "+(10-20) to All Attributes", 1, true),
                path .. " Exulis must carry '+(10-20) to All Attributes'")
            assert.is_falsy(string.find(window, "+(10-18) to All Attributes", 1, true),
                path .. " Exulis must NOT carry the regressed '+(10-18) to All Attributes' upper bound")
        end)

        -- @leb-regression-guard: exulis-shared-rollid
        -- mod[0] (Skills) and mod[1] (All Attributes) share rollID=0 in the
        -- game data (uniques_v3.json id=469), so they MUST share the ur byte
        -- when imported. See REGRESSION_GUARDS.md "exulis-shared-rollid".
        it(path .. " has Exulis rollIds[0]==rollIds[1]==0 (shared rollID)", function()
            local f = io.open(path, "r")
            assert.is_not_nil(f, "must be able to open " .. path)
            local text = f:read("*a")
            f:close()
            local exulisStart = string.find(text, '"name": "Exulis"', 1, true)
            assert.is_not_nil(exulisStart, "Exulis entry must exist in " .. path)
            local window = string.sub(text, exulisStart, exulisStart + 1500)
            -- Match the rollIds array. Whitespace is flexible; the first two
            -- entries must both be 0 to keep Skills and All Attributes reading
            -- the same ur byte.
            local r1, r2 = string.match(window, '"rollIds"%s*:%s*%[%s*(%d+)%s*,%s*(%d+)')
            assert.are.equal("0", r1,
                path .. " Exulis rollIds[0] must be 0 (Skills)")
            assert.are.equal("0", r2,
                path .. " Exulis rollIds[1] must be 0 (All Attributes shares rollID with Skills)")
        end)
    end
end)
