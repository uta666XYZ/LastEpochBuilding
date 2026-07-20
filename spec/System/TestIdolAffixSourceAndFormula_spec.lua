-- @leb-regression-guard: idol-affix-source-and-formula
-- Locks three paired behaviors:
--   1. Data.lua registers idol base types in itemMods so Item.lua's affix
--      lookup resolves to ModIdol (not ModItem.Item fallback) for idol items.
--   2. Item.lua divides out standardAffixEffectModifier (sAEM) UNIFORMLY for
--      every idol affix on BOTH the main path and the Omen-Idol bypass. There is
--      no sealed/corrupted skip: the engine's (1+sAEM) division is unconditional
--      (datamined game source affix_value_formula.md S46, datamined game source-verified).
--   3. ModIdol bakes the RAW stated roll. The three Apiarist corruption affixes
--      1070_0 / 1071_0 / 1072_0 are raw-baked ("+0.8%" / "+0.8"), NOT the legacy
--      pre-divided "+5" -- so the uniform division reproduces the engine value.
--
-- Game-data evidence (2026-05-12 in-game trade screenshots) for affix 1070_0
-- "All Resistances for you and your Minions" (datamine raw roll 0.008 = +0.8%,
-- sAEM = -0.83):
--   Adorned (aem=-0.05): round(0.8 * 0.95 / 0.17) = +4%
--   Huge    (aem= 0   ): round(0.8 * 1.00 / 0.17) = +5%
--   Grand/Large (aem=-0.33): round(0.8 * 0.67 / 0.17) = +3%
--   Large Arcane Omen Idol (aem=-0.33, Omen bypass resets modScalar=1 then
--     divides by 1+sAEM=0.17): round(0.8 * 1 / 0.17) = +5%   (NOT +29%, the
--     pre-fix double-bypass artifact; <private build> lv99 Sorcerer item 14 anchor).
--
-- History: the earlier per-case skipSaem / skipSaemRawPath gates protected the
-- legacy pre-divided bake by SKIPPING this division for corrupted/sealed idol
-- affixes. With the raw bake those gates are removed -- uniform division is now
-- correct on every import path (LETools, offline-save) and every idol size.
-- See REGRESSION_GUARDS.md "idol-affix-source-and-formula" + "affix-value-saem-uniform".

describe("IdolAffixSourceAndFormula", function()

    local dataSrc, itemSrc, modIdolSrc
    setup(function()
        local f = io.open("Modules/Data.lua", "r")
        assert.is_not_nil(f, "must open Modules/Data.lua")
        dataSrc = f:read("*a"); f:close()
        f = io.open("Classes/Item.lua", "r")
        assert.is_not_nil(f, "must open Classes/Item.lua")
        itemSrc = f:read("*a"); f:close()
        f = io.open("Data/ModIdol_1_4.json", "r")
        assert.is_not_nil(f, "must open Data/ModIdol_1_4.json")
        modIdolSrc = f:read("*a"); f:close()
    end)

    it("Data.lua guard comment is present", function()
        assert.is_truthy(string.find(dataSrc,
            "idol-affix-source-and-formula", 1, true),
            "Data.lua must keep the @leb-regression-guard comment")
    end)

    it("Data.lua registers all idol base types in itemMods", function()
        for _, idolType in ipairs({
            "Small Idol", "Minor Idol", "Humble Idol", "Stout Idol",
            "Grand Idol", "Large Idol", "Adorned Idol", "Ornate Idol", "Huge Idol",
        }) do
            assert.is_truthy(string.find(dataSrc, '"' .. idolType .. '"', 1, true),
                "Data.lua must register idol type '" .. idolType .. "' in itemMods")
        end
    end)

    it("Item.lua guard comment is present", function()
        assert.is_truthy(string.find(itemSrc,
            "idol-affix-source-and-formula", 1, true),
            "Item.lua must keep the @leb-regression-guard comment")
    end)

    it("Item.lua divides out sAEM UNCONDITIONALLY (no skipSaem gate)", function()
        -- The engine applies (1+aem)/(1+sAEM) with no sealed/corrupted branch.
        -- The division below must NOT be gated on any `not skipSaem*` flag.
        assert.is_truthy(string.find(itemSrc,
            "modScalar = modScalar / (1 + mod.standardAffixEffectModifier)", 1, true),
            "Item.lua must divide modScalar by (1 + sAEM)")
        assert.is_falsy(string.find(itemSrc, "not skipSaem", 1, true),
            "the sAEM division must NOT be gated on `not skipSaem` (gate removed)")
        assert.is_falsy(string.find(itemSrc, "local skipSaem", 1, true),
            "the `local skipSaem` / `skipSaemRawPath` gate declarations must be gone "
            .. "(a historical mention in a comment is fine)")
        -- The unconditional form `if mod.standardAffixEffectModifier then` must
        -- guard the division (so non-idol affixes with sAEM==nil are unaffected).
        assert.is_truthy(string.find(itemSrc,
            "if mod.standardAffixEffectModifier then", 1, true),
            "division must be guarded only by `if mod.standardAffixEffectModifier then`")
    end)

    it("Item.lua Omen Idol bypass divides by (1+sAEM) without a skip gate", function()
        -- The Omen bypass resets modScalar=1, then divides UNIFORMLY -- same
        -- engine formula. Locking that its inner division is no longer gated on
        -- `not skipSaem` (the pre-fix double-skip that this block once carried).
        local omenStart = string.find(itemSrc, "isOmenIdol then", 1, true)
        assert.is_truthy(omenStart, "Item.lua must contain the Omen Idol bypass block")
        local omenSnippet = itemSrc:sub(omenStart, omenStart + 900)
        assert.is_truthy(string.find(omenSnippet,
            "modScalar = modScalar / (1 + mod.standardAffixEffectModifier)", 1, true),
            "Omen Idol bypass must divide modScalar by (1+sAEM)")
        assert.is_falsy(string.find(omenSnippet, "not skipSaem", 1, true),
            "Omen Idol bypass division must NOT be gated on `not skipSaem`")
    end)

    it("ModIdol re-bakes the pre-divided trio to RAW stated values", function()
        -- 1070_0 (All Resistances): datamine roll 0.008 -> "+0.8%", NOT "+5%".
        assert.is_truthy(string.find(modIdolSrc, "+0.8% All Resistances", 1, true),
            "ModIdol 1070_0 line 1 must be raw '+0.8% All Resistances'")
        assert.is_truthy(string.find(modIdolSrc, "+0.8% Minion All Resistances", 1, true),
            "ModIdol 1070_0 line 2 must be raw '+0.8% Minion All Resistances'")
        -- 1071_0 / 1072_0 (Bees): datamine roll 0.8 -> "+0.8".
        assert.is_truthy(string.find(modIdolSrc, "+0.8 Bees Per 10 Seconds", 1, true),
            "ModIdol 1071_0 must be raw '+0.8 Bees Per 10 Seconds'")
        assert.is_truthy(string.find(modIdolSrc, "+0.8 Elemental Bees Per 10 Seconds", 1, true),
            "ModIdol 1072_0 must be raw '+0.8 Elemental Bees Per 10 Seconds'")
        -- The legacy pre-divided "+5%" bake must be gone (re-introducing it +
        -- uniform division would balloon to +29% on Omen idols).
        assert.is_falsy(string.find(modIdolSrc, "+5% All Resistances", 1, true),
            "the legacy pre-divided '+5% All Resistances' bake must be removed")
        assert.is_falsy(string.find(modIdolSrc, "+5 Bees Per 10 Seconds", 1, true),
            "the legacy pre-divided '+5 Bees Per 10 Seconds' bake must be removed")
    end)

    describe("XML-driven: QDxZPWM9 Large Arcane Omen Idol corrupted 1070_0 → +5%", function()
        -- Representative build (Lane T root case). Item index 14 is a Large
        -- Arcane Omen Idol carrying corrupted affix 1070_0. After the fix the
        -- resolved idol modLine carries the RAW bake "+0.8% All Resistances"
        -- with a valueScalar that the Omen bypass set to 1/(1+sAEM) = ~5.882,
        -- so the DISPLAYED value is round(0.8 * 5.882) = +5% (NOT +29%, the
        -- pre-fix double-bypass artifact, which needed valueScalar ~= 36).
        it("item 14 renders the raw 0.8% bake with an Omen scalar that yields +5%", function()
            local path = "../spec/TestBuilds/1.4/QDxZPWM9 lv99 Sorcerer.xml"
            local f = io.open(path, "r")
            if not f then
                pending("QDxZPWM9 XML fixture missing in this worktree — covered by snapshot regen")
                return
            end
            local xml = f:read("*a")
            f:close()
            loadBuildFromXML(xml, "QDxZPWM9 lv99 Sorcerer")
            runCallback("OnFrame")

            local item = build.itemsTab.items[14]
            assert.is_not_nil(item, "QDxZPWM9 item index 14 must exist")
            assert.is_truthy(item.baseName and item.baseName:find("Omen Idol", 1, true),
                "item 14 must be an Omen Idol base, got: " .. tostring(item.baseName))

            -- Collect modLine tables (line + valueScalar) across whichever
            -- structure the parser populated for this base type.
            local modLines = {}
            local function collect(list)
                if type(list) ~= "table" then return end
                for _, ml in ipairs(list) do
                    if type(ml) == "table" and type(ml.line) == "string" then
                        table.insert(modLines, ml)
                    end
                end
            end
            collect(item.modLines)
            collect(item.explicitModLines)
            collect(item.rangeLineList)

            local joined = {}
            for _, ml in ipairs(modLines) do table.insert(joined, ml.line) end
            joined = table.concat(joined, "\n")

            -- Raw bake propagated (re-bake works), and the legacy +5%/+29% are gone.
            assert.is_truthy(string.find(joined, "+0.8% All Resistances", 1, true),
                "expected the raw '+0.8% All Resistances' bake on item 14; got:\n" .. joined)
            assert.is_falsy(string.find(joined, "+29%", 1, true),
                "+29% indicates the pre-fix Omen Idol bypass double-applied sAEM; got:\n" .. joined)

            -- The Omen bypass uniform division must turn 0.8% into +5%: find the
            -- All-Resistances modLine and check round(0.8 * valueScalar) == 5.
            local found = false
            for _, ml in ipairs(modLines) do
                if ml.line:find("+0.8% All Resistances", 1, true) then
                    found = true
                    local scalar = ml.valueScalar or 1
                    local displayed = math.floor(0.8 * scalar + 0.5)
                    assert.are.equal(5, displayed,
                        ("Omen 1070_0 must render +5%% (0.8 * valueScalar=%s = %s -> %d); "
                         .. "a ~5.882 scalar is the uniform 1/(1+sAEM) division")
                        :format(tostring(scalar), tostring(0.8 * scalar), displayed))
                    assert.is_true(scalar < 10,
                        "valueScalar must be the ~5.882 uniform division, not the +29% bypass (~36)")
                end
            end
            assert.is_true(found, "did not find the +0.8% All Resistances modLine on item 14")
        end)
    end)
end)
