-- @leb-regression-guard: eterras-path-player-ms
-- Locks the Eterra's Path (id 21) "20% increased Movement Speed" PLAYER mod.
--
-- Evidence:
--   1. Datamining (extracted/items/uniques_v3.json id=21):
--      mods[0]: value=0.2, property=9 (MovementSpeed), tags=0      <- player
--      mods[1]: value=0.2, property=9 (MovementSpeed), tags=8192   <- minion
--      tooltipDescriptions[0]: "You and your minions have 20% increased
--        movement speed" (single tooltip line that displays BOTH mods).
--   2. LETools planner Movement Speed breakdown for Qb6WgDEp lv95
--      Beastmaster (Eterra's Path equipped):
--        Boots (Implicit) 12% + Boots (Prefix) 24% + Boots (Unique mod) 20%
--        + Predator Tree 5% = 61% (matches in-game tooltip).
--   3. Before fix, uniques_1_4.json id=21 listed only the minion variant,
--      causing a -20% player Movement Speed gap on every Eterra's Path
--      build (Qb6WgDEp Δ=-25, plus the -5 Predator BASE issue).
--
-- The "You and your minions have ..." tooltip pattern in LE corresponds to
-- TWO separate mods in the underlying data (one tags=0, one tags=8192=Minion).
-- LEB unique JSON must list BOTH explicitly. Do NOT drop either one.
--
-- See REGRESSION_GUARDS.md "eterras-path-player-ms".

describe("EterrasPathPlayerMS", function()
    it("uniques_1_4.json Eterra's Path has BOTH player and minion 20% MS mods", function()
        local f = io.open("Data/Uniques/uniques_1_4.json", "r")
        assert.is_not_nil(f, "must be able to open uniques_1_4.json")
        local text = f:read("*a")
        f:close()
        local entryStart = string.find(text, '"name": "Eterra\'s Path"', 1, true)
        assert.is_not_nil(entryStart, "Eterra's Path entry must exist")
        -- Window the entry (next ~1500 chars covers mods + rollIds)
        local window = string.sub(text, entryStart, entryStart + 1500)
        assert.is_truthy(
            string.find(window, '"20% increased Movement Speed"', 1, true),
            "Eterra's Path must carry the PLAYER '20% increased Movement Speed' mod")
        assert.is_truthy(
            string.find(window, '"20% increased Minion Movement Speed"', 1, true),
            "Eterra's Path must carry the MINION '20% increased Minion Movement Speed' mod")
    end)
end)
