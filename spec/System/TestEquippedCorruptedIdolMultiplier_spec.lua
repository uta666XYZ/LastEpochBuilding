-- @leb-regression-guard: equipped-corrupted-idol-multiplier
-- Locks the contract that CalcSetup emits Multiplier:EquippedCorruptedIdol
-- alongside the existing CorruptedIdolItemsEquipped stat, with the same
-- count source. Idol Altar corrupted/sealed prefixes such as Spire Altar T7
-- "+10 Mana per Equipped Corrupted Idol" (src/Data/ModItem.json line 65367,
-- ModCache.lua line 2036) are parsed with tag {type="Multiplier",
-- var="EquippedCorruptedIdol"}; without an emission of that multiplier the
-- affix resolves to 0 and contributes nothing.
--
-- Establishing build: B7GrkJrK lv100 Lich/Reaper. LE Mana 1607.21 vs
-- LEB 1373 (Δ=-234). Adding the multiplier closes ~75% of the gap to
-- LEB 1548. The remaining residual is unrelated (Reliquary Nest unique
-- "+(40-60)% Non-Unique Idol Stat Multiplier" still unparsed).
--
-- See REGRESSION_GUARDS.md "equipped-corrupted-idol-multiplier".

describe("EquippedCorruptedIdolMultiplier", function()

    describe("CalcSetup emits Multiplier:EquippedCorruptedIdol", function()
        local source
        setup(function()
            local f = io.open("Modules/CalcSetup.lua", "r")
            assert.is_not_nil(f, "must be able to open Modules/CalcSetup.lua")
            source = f:read("*a")
            f:close()
        end)

        it("regression-guard comment block is present", function()
            assert.is_truthy(string.find(source, "equipped-corrupted-idol-multiplier", 1, true),
                "CalcSetup.lua must keep the @leb-regression-guard comment so future edits trip review")
        end)

        it("emits Multiplier:EquippedCorruptedIdol with BASE type and the idol count", function()
            local pat = 'NewMod%(%s*"Multiplier:EquippedCorruptedIdol"%s*,%s*"BASE"%s*,%s*idol%s*,'
            assert.is_truthy(string.find(source, pat),
                "CalcSetup.lua must emit Multiplier:EquippedCorruptedIdol = idol so that "
                .. '"+N <stat> per Equipped Corrupted Idol" affixes evaluate to a non-zero contribution')
        end)

        it("emission sits inside the same `if idol > 0 then` block as CorruptedIdolItemsEquipped", function()
            -- Find the existing CorruptedIdolItemsEquipped emission and ensure the
            -- new Multiplier emission is in the same block (within ~600 chars).
            local i, j = string.find(source, 'NewMod%(%s*"CorruptedIdolItemsEquipped"%s*,%s*"BASE"%s*,%s*idol%s*,')
            assert.is_not_nil(i, "CorruptedIdolItemsEquipped emission must exist as the anchor")
            local window = string.sub(source, j, j + 600)
            assert.is_truthy(string.find(window, 'Multiplier:EquippedCorruptedIdol', 1, true),
                "Multiplier:EquippedCorruptedIdol must be emitted in the same `if idol > 0` block, "
                .. "so the count source matches CorruptedIdolItemsEquipped")
        end)
    end)

    describe("ModCache parses '+N Mana per Equipped Corrupted Idol' to the matching tag", function()
        local cache
        setup(function()
            cache = modLib.parseModCache
            assert.is_not_nil(cache, "modLib.parseModCache must be populated by HeadlessWrapper")
        end)

        it("'+10 Mana per Equipped Corrupted Idol' parses to Multiplier:EquippedCorruptedIdol", function()
            local entry = cache["+10 Mana per Equipped Corrupted Idol"]
            assert.is_not_nil(entry, "ModCache must contain the +10 Mana per Equipped Corrupted Idol entry")
            local mods, extra = entry[1], entry[2]
            assert.is_nil(extra, "entry must have no unparsed leftover")
            assert.is_not_nil(mods, "entry must carry a parsed mods list")
            local m = mods[1]
            assert.are.equals("Mana", m.name)
            assert.are.equals("BASE", m.type)
            assert.are.equals(10, m.value)
            assert.are.equals("Multiplier", m[1].type)
            assert.are.equals("EquippedCorruptedIdol", m[1].var)
        end)
    end)
end)
