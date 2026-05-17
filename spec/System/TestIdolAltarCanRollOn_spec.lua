-- @leb-regression-guard: idol-altar-canrollon-normalization
-- Locks the invariant that every entry in
-- src/Data/ModItem_IdolAltar_1_4.json carries `canRollOn = {41}`
-- (slot id 41 = "Idol Altar"; see src/Data/LEToolsImport/slot_mapping.lua
-- L45).
--
-- Game-file backing (LE 1.4 il2cpp re-extraction, 2026-05-15):
--   * LE_datamining/extracted/items/single_affixes_v3.json
--   * LE_datamining/extracted/items/multi_affixes_v3.json
-- Every Idol Altar affixId family used by LEB (1088, 1089, 1092-1109,
-- total 20) sets `canRollOn: [41]` in the dumped affix data. The LEB
-- JSON was inconsistent: 16/160 entries (only 1095_* "Maximum Omen Idols
-- Equipped" + 1108_* "Corrupted Idol Limit") were populated, the other
-- 144 lacked the field entirely.
--
-- Consumer: src/Classes/ItemsTabCraft.lua `canRollOnIdol` (~L1340) and
-- the parallel filter inside the craft-list builder (~L1117). Both
-- treat an absent/empty `canRollOn` as "no restriction" (passes
-- regardless of baseTypeID). With 144 entries missing canRollOn, the
-- Idol Altar craft pool was bleeding into non-altar bases on builds
-- whose baseTypeID happened to land outside the legitimate altar slot.
--
-- Normalising every entry to `canRollOn = {41}` aligns the data file
-- with the game-file ground truth and tightens the craft-tab filter to
-- altar bases only. The spec does not touch the consumer logic; it just
-- guards the data invariant.
--
-- See REGRESSION_GUARDS.md "idol-altar-canrollon-normalization".

describe("TestIdolAltarCanRollOn #idolAltarData", function()
    setup(function()
        newBuild()
    end)

    it("every Idol Altar mod entry carries canRollOn = {41}", function()
        assert.is_not_nil(data.itemMods, "data.itemMods must be loaded")
        local altarMods = data.itemMods["Idol Altar"]
        assert.is_not_nil(altarMods, "data.itemMods['Idol Altar'] must be loaded")

        local offenders_missing = {}
        local offenders_wrong   = {}
        local total = 0
        for modId, mod in pairs(altarMods) do
            if type(mod) == "table" and mod.statOrderKey then
                total = total + 1
                local cro = mod.canRollOn
                if type(cro) ~= "table" or #cro == 0 then
                    table.insert(offenders_missing,
                        string.format("modId=%s name=%q (canRollOn missing/empty)",
                            tostring(modId), tostring(mod.affixName or "?")))
                elseif #cro ~= 1 or cro[1] ~= 41 then
                    table.insert(offenders_wrong,
                        string.format("modId=%s name=%q canRollOn=%s",
                            tostring(modId), tostring(mod.affixName or "?"),
                            "{" .. table.concat(cro, ",") .. "}"))
                end
            end
        end

        assert.is_true(total >= 100,
            "expected at least 100 Idol Altar mod entries, got " .. tostring(total))
        assert.are.equal(0, #offenders_missing,
            "entries missing canRollOn:\n  " .. table.concat(offenders_missing, "\n  "))
        assert.are.equal(0, #offenders_wrong,
            "entries with wrong canRollOn (expected {41}):\n  " .. table.concat(offenders_wrong, "\n  "))
    end)
end)
