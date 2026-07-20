-- @leb-regression-guard: bare-form-damage-affix-increased
-- Locks the DATA fix that restored the dropped "increased" keyword on five LE
-- item-affix families whose bare "+(X)% <Type> Damage" templates were being
-- parsed as a MULTIPLICATIVE damage MORE instead of additive INCREASED.
--
-- Evidence (datamined game source extracted/items/multi_affixes_v3.json, affixProperties
-- modifierType enum: 0=Flat/Added, 1=Increased, 2=More):
--   959 Keplahan's Cryolith Reforged  Cold  (prop 0, modifierType 1 = Increased)
--   960 Keplahan's Pyrolith Reforged  Fire  (prop 0, modifierType 1 = Increased)
--   961 Kuzon's Fury Reforged         Fire  (prop 0, modifierType 1 = Increased)
--   986 "Increased Melee Damage and Damage for Melee Attacks per 1 Mana Cost"
--       Melee (prop 0, modifierType 1 = Increased) -- the Rusted Cleaver
--       "Cleaver Solution" sealed affix; in-game tooltip reads
--       "137% increased Melee Damage".
--   1090 Rogue's / Level of Bladestorm Throwing (prop 0, modifierType 1=Increased)
-- Counter-case left UNCHANGED (genuine MORE, must stay bare):
--   979 "Chance to Poison on Hit and More Damage against Poisoned Enemies"
--       Global Conditional (prop 117, modifierType 2 = More).
--
-- The fix edits the templates in Data/ModItem_1_4.json (+ legacy Data/ModItem.json)
-- from "+(X)% <Type> Damage" to "(X)% increased <Type> Damage". It is NOT a parser
-- change: a broad bare-damage -> INC promotion would wrongly flip the many skill/
-- tree nodes that render a genuine bare-MORE (e.g. "+200% Vine Melee Damage",
-- "+10% Riposte Fire Damage").
-- See REGRESSION_GUARDS.md "bare-form-damage-affix-increased".

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("BareFormDamageAffixIncreased", function()

    -- ---- Layer A: parser semantics (why the data fix is needed + that it works)
    it("bare '+N% <Type> Damage' parses to MORE by default (the defect's mechanism)", function()
        for _, t in ipairs({"Melee", "Cold", "Fire", "Throwing"}) do
            local mods = modLib.parseMod("+75% " .. t .. " Damage")
            assert.is_not_nil(mods, t .. " bare form must parse")
            assert.are.equals("MORE", mods[1].type,
                "bare '+75% " .. t .. " Damage' is a MORE by default (BASE_MORE form)")
        end
    end)

    it("'(N)% increased <Type> Damage' parses to INC (the fix target)", function()
        local expectName = { Melee = "Damage", Cold = "ColdDamage", Fire = "FireDamage", Throwing = "Damage" }
        for _, t in ipairs({"Melee", "Cold", "Fire", "Throwing"}) do
            local mods = modLib.parseMod("75% increased " .. t .. " Damage")
            assert.is_not_nil(mods, t .. " increased form must parse")
            assert.are.equals("INC", mods[1].type,
                "'75% increased " .. t .. " Damage' must be INC, not MORE")
            assert.are.equals(expectName[t], mods[1].name, t .. " stat name")
        end
    end)

    it("a genuine '+N% more Damage' still parses to MORE (no over-correction)", function()
        local mods = modLib.parseMod("+20% more Damage")
        assert.is_not_nil(mods)
        assert.are.equals("MORE", mods[1].type, "explicit 'more' must stay MORE")
    end)

    -- ---- Layer B: the data itself (ModItem templates now carry "increased")
    local files = { "Data/ModItem_1_4.json", "Data/ModItem.json" }

    it("no defective bare '+(X)% <Type> Damage' template remains", function()
        for _, fn in ipairs(files) do
            local text = readSource(fn)
            for _, t in ipairs({"Melee", "Cold", "Fire", "Throwing"}) do
                -- Lua pattern: +(NN-NN)% <Type> Damage"  (the exact bare template)
                local bare = text:match('%+%(%d+%-%d+%)%% ' .. t .. ' Damage"')
                assert.is_nil(bare,
                    fn .. " must not contain a bare '+(X)% " .. t .. " Damage' template (got: "
                    .. tostring(bare) .. ")")
            end
        end
    end)

    it("the canonical 'increased' melee template is present (986 Cleaver Solution)", function()
        for _, fn in ipairs(files) do
            local text = readSource(fn)
            assert.is_truthy(text:find('(70-79)% increased Melee Damage', 1, true),
                fn .. " must carry '(70-79)% increased Melee Damage'")
        end
    end)

    it("the increased Cold/Fire/Throwing templates are present in ModItem_1_4", function()
        local text = readSource("Data/ModItem_1_4.json")
        assert.is_truthy(text:find('(10-17)% increased Cold Damage', 1, true), "959 Cold")
        assert.is_truthy(text:find('(10-17)% increased Fire Damage', 1, true), "960 Fire")
        assert.is_truthy(text:find('(5-13)% increased Fire Damage', 1, true), "961 Kuzon Fire")
        assert.is_truthy(text:find('(5-10)% increased Throwing Damage', 1, true), "1090 Throwing")
    end)

    it("genuine MORE affix 979 'Global Conditional Damage' is LEFT bare (modifierType 2=More)", function()
        local text = readSource("Data/ModItem_1_4.json")
        assert.is_truthy(text:find('+(5-6)% Global Conditional Damage', 1, true),
            "979 'More Damage against Poisoned' must NOT be converted to increased")
        assert.is_nil(text:find('increased Global Conditional Damage', 1, true),
            "Global Conditional Damage must never carry 'increased'")
    end)

    -- ---- Layer C: the inline marker stays at the parser anchor site
    it("ModParser carries the @leb-regression-guard marker at the BASE_MORE rule", function()
        local parserText = readSource("Modules/ModParser.lua")
        assert.is_truthy(parserText:find("@leb-regression-guard: bare-form-damage-affix-increased", 1, true),
            "BASE_MORE rule must carry the named guard marker")
    end)
end)
