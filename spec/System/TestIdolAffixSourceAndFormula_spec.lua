-- @leb-regression-guard: idol-affix-source-and-formula
-- Locks two paired behaviors:
--   1. Data.lua registers idol base types in itemMods so Item.lua's affix
--      lookup resolves to ModIdol (not ModItem.Item fallback) for idol items.
--   2. Item.lua skips standardAffixEffectModifier subtraction for sealed-
--      corrupted (specialAffixType==6) affixes on idol bases.
--
-- Game-data evidence (2026-05-12): in-game trade screenshots of affix 1070_0
-- "All Resistances for you and your Minions" (ModIdol raw "+5%", sAEM=-0.83):
--   Adorned (aem=-0.05): displayed +4%   → 5 × 0.95 = 4.75 floor
--   Huge    (aem= 0   ): displayed +5%   → 5 × 1.00 = 5
--   Grand/Large (aem=-0.33): displayed +3% → 5 × 0.67 = 3.35 floor
--   Large Arcane Omen Idol (aem=-0.33, Omen bypass → modScalar=1): displayed +5%
--     The Omen bypass sets modScalar=1, then would re-divide by (1+sAEM=0.17)
--     to 5.882× — but for sealed/corrupted-kind affixes that re-division must
--     be skipped too, otherwise 5 × 5.882 = +29% (29 instead of 5; +24 drift
--     observed on QDxZPWM9 lv99 Sorcerer item 14 before fix).
-- sAEM is NOT applied. Throne of Ambition (Adorned Silver Idol) confirmed +4%.
--
-- See REGRESSION_GUARDS.md "idol-affix-source-and-formula".

describe("IdolAffixSourceAndFormula", function()

    local dataSrc, itemSrc
    setup(function()
        local f = io.open("Modules/Data.lua", "r")
        assert.is_not_nil(f, "must open Modules/Data.lua")
        dataSrc = f:read("*a"); f:close()
        f = io.open("Classes/Item.lua", "r")
        assert.is_not_nil(f, "must open Classes/Item.lua")
        itemSrc = f:read("*a"); f:close()
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

    it("Item.lua gates sAEM subtraction on isIdolBase + corrupted/sealed kind", function()
        -- Detection uses affix.kind ("corrupted" / "sealed") because
        -- ModIdol entries do not carry specialAffixType=6.
        assert.is_truthy(string.find(itemSrc, "skipSaem", 1, true),
            "Item.lua must define a skipSaem flag for the idol sealed/corrupted case")
        assert.is_truthy(string.find(itemSrc,
            'isIdolBase and (affix.kind == "corrupted" or affix.kind == "sealed")', 1, true),
            "Item.lua skipSaem must check affix.kind for corrupted/sealed")
        assert.is_truthy(string.find(itemSrc, "not skipSaem", 1, true),
            "Item.lua sAEM subtraction must be gated on `not skipSaem`")
    end)

    it("Item.lua Omen Idol bypass also gates re-division by (1+sAEM) on `not skipSaem`", function()
        -- Without this gate, sealed/corrupted-kind affixes on Omen Idol bases
        -- (e.g. 1070_0 sAEM=-0.83 on Large Arcane Omen Idol) inflate from
        -- raw +5% to +29% because the bypass forces modScalar=1 and then the
        -- unconditional re-division by 0.17 multiplies by ~5.882×.
        -- The Omen bypass branch lives a few lines below the isIdolBase guard
        -- and must use the same `skipSaem` flag in scope (do not redeclare).
        local omenStart = string.find(itemSrc, "isOmenIdol then", 1, true)
        assert.is_truthy(omenStart, "Item.lua must contain the Omen Idol bypass block")
        local omenSnippet = itemSrc:sub(omenStart, omenStart + 800)
        assert.is_truthy(string.find(omenSnippet, "not skipSaem", 1, true),
            "Item.lua Omen Idol bypass must gate its sAEM re-division on `not skipSaem`")
    end)

    describe("XML-driven: QDxZPWM9 Large Arcane Omen Idol corrupted 1070_0 → +5%", function()
        -- Representative build (Lane T root case from
        -- Development/LEB vs LETools stat 比較.md). Item index 14 in the XML
        -- is a Large Arcane Omen Idol carrying corrupted affix 1070_0
        -- (raw +5%). Expected displayed text after fix: "+5% All Resistances"
        -- and "+5% Minion All Resistances" (NOT "+29% ..." which the pre-fix
        -- double-bypass produced). LETools matches +5%.
        it("item 14 affixes render +5% not +29%", function()
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

            -- Collect every modLine string the item exposes, regardless of
            -- which structure (modLines / explicitModLines / rangeLineList)
            -- the parser populated for this base type.
            local lines = {}
            local function collect(list)
                if type(list) ~= "table" then return end
                for _, ml in ipairs(list) do
                    if type(ml) == "table" and type(ml.line) == "string" then
                        table.insert(lines, ml.line)
                    elseif type(ml) == "string" then
                        table.insert(lines, ml)
                    end
                end
            end
            collect(item.modLines)
            collect(item.explicitModLines)
            collect(item.rangeLineList)

            local joined = table.concat(lines, "\n")
            assert.is_truthy(string.find(joined, "+5% All Resistances", 1, true),
                "expected '+5% All Resistances' on item 14; got:\n" .. joined)
            assert.is_truthy(string.find(joined, "+5% Minion All Resistances", 1, true),
                "expected '+5% Minion All Resistances' on item 14; got:\n" .. joined)
            assert.is_falsy(string.find(joined, "+29%", 1, true),
                "+29% indicates the pre-fix Omen Idol bypass double-applied sAEM; got:\n" .. joined)
        end)
    end)
end)
