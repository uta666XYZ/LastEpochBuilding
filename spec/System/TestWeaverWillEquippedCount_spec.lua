-- @leb-regression-guard: weaver-will-equipped-autocount
-- Locks the full chain that makes Communion of the Erased's
-- "+1 Potion Slot per equipped Weaver('s Will) Item" reach PotionSlots:
--
--   (1) ModParser singular alias: the in-game / saved-build text uses the
--       SINGULAR "Potion Slot" name ("+1 Potion Slot per equipped Weaver
--       Item"). modNameList previously only carried the plural "potion
--       slots", so the modName scan failed and the whole mod dropped
--       (parse left residue " Potion Slot "). The singular alias must parse
--       it to PotionSlots BASE with a {Multiplier:EquippedWeaverItem} tag and
--       leave no residue. scan() is earliest+longest so plural text still
--       binds the longer "potion slots".
--   (2) ModParser game-accurate tag: "per equipped Weaver's Will Item"
--       (datamining localization Unique_Tooltip_1_327) must map to
--       Multiplier:EquippedWeaverItem alongside the legacy "per equipped
--       weaver item" phrasing.
--   (3) Data.weaversWillUniques: a name-keyed set built from every unique
--       with legendaryType == 1 (exactly the Weaver's Will uniques in game
--       data). CalcSetup.lua counts equipped items whose title is in this
--       set to supply Multiplier:EquippedWeaverItem automatically, so 2/3/4+
--       equipped Weaver's Will items all scale without hardcoding.
--
-- Establishing observation: ImPalmBeachPete lv36 Bladedancer (belt + boots =
-- 2 Weaver's Will items) PotionSlots
--   pre-fix  3 (implicit +3 only; per-item mod dropped at parse + a stale
--            ModCache row c["+1 Potion Slot per equipped Weaver Item"]={{},...}
--            short-circuited the live parser)
--   post-fix 5 (implicit 3 + 1 BASE x Multiplier:EquippedWeaverItem(2))
--
-- See REGRESSION_GUARDS.md > weaver-will-equipped-autocount.

describe("TestWeaverWillEquippedCount", function()
    before_each(function()
        newBuild()
    end)

    -- Uncached numbers (+7) so this exercises the live ModParser path rather
    -- than any precomputed Data/ModCache row.
    it("parses singular 'Potion Slot per equipped Weaver Item' to PotionSlots + Multiplier", function()
        local mods, extra = modLib.parseMod("+7 Potion Slot per equipped Weaver Item")
        assert.is_table(mods)
        assert.is_table(mods[1])
        assert.are.equals("PotionSlots", mods[1].name)
        assert.are.equals("BASE", mods[1].type)
        assert.are.equals(7, mods[1].value)
        assert.are.equals("Multiplier", mods[1][1].type)
        assert.are.equals("EquippedWeaverItem", mods[1][1].var)
        assert.is_nil(extra, "singular form must leave no residue (got '" .. tostring(extra) .. "')")
    end)

    -- Game-accurate phrasing (datamining localization Unique_Tooltip_1_327) is
    -- "per equipped Weaver's Will Item"; uniques 327/8145/8191 and the future-
    -- import data text use the PLURAL "Potion Slots" name with this tag.
    it("parses game-accurate \"Weaver's Will Item\" phrasing to the same multiplier", function()
        local mods, extra = modLib.parseMod("+7 Potion Slots per equipped Weaver's Will Item")
        assert.is_table(mods[1])
        assert.are.equals("PotionSlots", mods[1].name)
        assert.are.equals("Multiplier", mods[1][1].type)
        assert.are.equals("EquippedWeaverItem", mods[1][1].var)
        assert.is_nil(extra)
    end)

    it("plural text still binds the longer 'potion slots' name", function()
        local mods, extra = modLib.parseMod("+7 Potion Slots per equipped Weaver Item")
        assert.are.equals("PotionSlots", mods[1].name)
        assert.are.equals("EquippedWeaverItem", mods[1][1].var)
        assert.is_nil(extra)
    end)

    it("PotionSlots scales with Multiplier:EquippedWeaverItem", function()
        build.configTab.input.customMods = "+1 Potion Slot per equipped Weaver Item"
        build.configTab:BuildModList()
        runCallback("OnFrame")
        -- Zero contribution before any Weaver's Will item is equipped
        assert.are.equals(0, build.configTab.modList:Sum("BASE", nil, "PotionSlots"))
        -- 2 equipped Weaver's Will items (ImPalmBeachPete: belt + boots): 1 * 2
        build.configTab.modList.multipliers["EquippedWeaverItem"] = 2
        assert.are.equals(2, build.configTab.modList:Sum("BASE", nil, "PotionSlots"))
        -- Auto-count must handle 3 and 4 items too (user requirement)
        build.configTab.modList.multipliers["EquippedWeaverItem"] = 4
        assert.are.equals(4, build.configTab.modList:Sum("BASE", nil, "PotionSlots"))
        build.configTab.modList.multipliers["EquippedWeaverItem"] = nil
    end)

    it("data.weaversWillUniques is a name-keyed set of legendaryType==1 uniques", function()
        local set = build.data.weaversWillUniques
        assert.is_table(set, "data.weaversWillUniques must be built in Data.lua")
        -- Communion of the Erased (uniqueID 327) carries legendaryType 1
        assert.is_true(set["Communion of the Erased"] == true,
            "Communion of the Erased must be flagged as a Weaver's Will unique")
        -- Every entry must correspond to a legendaryType==1 unique in data
        local byName = {}
        for _, u in pairs(build.data.uniques or {}) do
            if type(u) == "table" and u.name then byName[u.name] = u end
        end
        for name in pairs(set) do
            local u = byName[name]
            assert.is_truthy(u, "weaversWillUniques name '" .. name .. "' must exist in data.uniques")
            assert.are.equals(1, u.legendaryType,
                "weaversWillUniques name '" .. name .. "' must have legendaryType == 1")
        end
    end)
end)
