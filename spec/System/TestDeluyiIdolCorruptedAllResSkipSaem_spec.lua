-- @leb-regression-guard: deluyi-idol-corrupted-allres-skipsaem-by-specialtype
-- See REGRESSION_GUARDS.md "idol-affix-source-and-formula" + "affix-value-saem-uniform".
-- Validation provenance is retained in maintainer notes.

describe("DeluyiIdolCorruptedAllResSkipSaem", function()

    local itemSrc, modIdolSrc
    setup(function()
        local f = assert(io.open("Classes/Item.lua", "r"), "must open Classes/Item.lua")
        itemSrc = f:read("*a"); f:close()
        f = assert(io.open("Data/ModIdol_1_4.json", "r"), "must open Data/ModIdol_1_4.json")
        modIdolSrc = f:read("*a"); f:close()
    end)

    it("the removed skipSaem / skipSaemRawPath gates stay removed", function()
        -- A historical mention in a comment is fine; the GATE CODE must be gone.
        assert.is_falsy(string.find(itemSrc, "local skipSaem", 1, true),
            "the `local skipSaem` / `skipSaemRawPath` gate declarations must stay removed")
        assert.is_falsy(string.find(itemSrc, "not skipSaem", 1, true),
            "no division may be gated on `not skipSaem` (uniform division)")
        assert.is_falsy(string.find(itemSrc, "not skipSaemRawPath", 1, true),
            "no division may be gated on `not skipSaemRawPath` (uniform division)")
    end)

    it("ModIdol re-bakes the trio raw so the uniform division is correct", function()
        assert.is_truthy(string.find(modIdolSrc, "+0.8% All Resistances", 1, true),
            "1070_0 must be raw-baked '+0.8%' (the legacy pre-divided '+5%' would balloon)")
        assert.is_falsy(string.find(modIdolSrc, "+5% All Resistances", 1, true),
            "the legacy pre-divided '+5%' bake must be gone")
    end)

    -- Behavioral (main path): offline-save Stout Weaver Idol (non-Omen) carrying
    -- corrupted affix 1070_0 WITHOUT a {kind:...} tag (exactly what offline-save
    -- import produces). Uniform division -> +2% per player resistance.
    it("Stout Weaver Idol corrupted 1070_0 (no kind tag) renders +2%, not +11%", function()
        newBuild()
        build.itemsTab:CreateDisplayItemFromRaw([[Rarity: RARE
		Stout Weaver Idol
		Stout Weaver Idol
		Unique ID: Idol 4
		Crafted: true
		Prefix: {range:117}1070_0
		Prefix: None
		Prefix: None
		Suffix: None
		Suffix: None
		Suffix: None
		LevelReq: 0
		Implicits: 0]])
        local item = build.itemsTab.displayItem
        assert.is_not_nil(item, "displayItem should exist")
        assert.are.equals("Stout Idol", item.base and item.base.type,
            "fixture must resolve to the Stout Idol base type")

        local resistNames = {
            FireResist = true, ColdResist = true, LightningResist = true,
            PhysicalResist = true, NecroticResist = true, PoisonResist = true,
            VoidResist = true,
        }
        local playerByResist, minionAny = {}, false
        for _, mod in ipairs(item.modList) do
            if mod.type == "BASE" and resistNames[mod.name] then
                playerByResist[mod.name] = (playerByResist[mod.name] or 0) + mod.value
            elseif mod.name == "MinionModifier" and type(mod.value) == "table"
                   and mod.value.mod and resistNames[mod.value.mod.name] then
                minionAny = true
            end
        end

        for name in pairs(resistNames) do
            assert.are.equals(2, playerByResist[name],
                name .. " must be +2 (round(0.8 x (1-0.62)/(1-0.83))), not +11 (the pre-divided-double bug)")
        end
        assert.is_true(minionAny, "the minion all-res line must still be produced")
    end)

    -- Behavioral (Omen path, SuXes-class): offline-save corrupted affix on an
    -- Omen idol WITHOUT a {kind:...} tag must still DIVIDE by (1+sAEM). The Omen
    -- bypass resets modScalar=1 then /(1+sAEM) = 1/0.17, so 1070_0 -> +5%.
    it("Large Arcane Omen Idol corrupted 1070_0 (no kind tag) renders +5% (Omen path divides)", function()
        newBuild()
        build.itemsTab:CreateDisplayItemFromRaw([[Rarity: RARE
		Large Arcane Omen Idol
		Large Arcane Omen Idol
		Unique ID: Idol 5
		Crafted: true
		Prefix: {range:117}1070_0
		Prefix: None
		Prefix: None
		Suffix: None
		Suffix: None
		Suffix: None
		LevelReq: 0
		Implicits: 0]])
        local item = build.itemsTab.displayItem
        assert.is_not_nil(item, "displayItem should exist")
        assert.is_truthy(item.baseName and item.baseName:find("Omen Idol", 1, true),
            "fixture must resolve to an Omen Idol base, got: " .. tostring(item.baseName))

        local resistNames = {
            FireResist = true, ColdResist = true, LightningResist = true,
            PhysicalResist = true, NecroticResist = true, PoisonResist = true,
            VoidResist = true,
        }
        local playerByResist = {}
        for _, mod in ipairs(item.modList) do
            if mod.type == "BASE" and resistNames[mod.name] then
                playerByResist[mod.name] = (playerByResist[mod.name] or 0) + mod.value
            end
        end
        for name in pairs(resistNames) do
            assert.are.equals(5, playerByResist[name],
                name .. " must be +5 (round(0.8 x 1/0.17)); the Omen bypass must divide by (1+sAEM)")
        end
    end)
end)
