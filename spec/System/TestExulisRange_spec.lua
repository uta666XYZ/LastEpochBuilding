-- @leb-regression-guard: exulis-all-attributes-range
-- Locks the Exulis amulet (id 469) "+(10-18) to All Attributes" range.
-- Verified against in-game LE 1.4 inspect panel + LETools planner: a
-- mid-roll Exulis (rollId=245/255) shows +18, which matches 10 + 8*245/255
-- = 17.69 → 18. The earlier (10-20) range over-rounded to 20 for the same
-- roll. The +2 quest reward is a SEPARATE +2 to All Attributes, NOT part
-- of the amulet's own roll range — conflating them is what produced the
-- wrong upper bound originally.
-- See REGRESSION_GUARDS.md "exulis-all-attributes-range".

describe("ExulisAllAttributesRange", function()
    local files = {
        "Data/Uniques/uniques_1_4.json",
        "Data/Uniques/uniques.json",
    }

    for _, path in ipairs(files) do
        it(path .. " has Exulis '+(10-18) to All Attributes'", function()
            local f = io.open(path, "r")
            assert.is_not_nil(f, "must be able to open " .. path)
            local text = f:read("*a")
            f:close()
            -- Find the Exulis entry and assert the All Attributes mod string.
            local exulisStart = string.find(text, '"name": "Exulis"', 1, true)
            assert.is_not_nil(exulisStart, "Exulis entry must exist in " .. path)
            -- Look in a window after the name for the mod line.
            local window = string.sub(text, exulisStart, exulisStart + 1500)
            assert.is_truthy(string.find(window, "+(10-18) to All Attributes", 1, true),
                path .. " Exulis must carry '+(10-18) to All Attributes'")
            assert.is_falsy(string.find(window, "+(10-20) to All Attributes", 1, true),
                path .. " Exulis must NOT carry the regressed '+(10-20) to All Attributes' upper bound")
        end)
    end
end)
