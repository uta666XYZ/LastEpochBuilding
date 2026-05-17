-- @leb-regression-guard: affix-effect-modifier-formula
-- Locks the contract that LEB applies the affix display multiplier as
-- (1 + base.affixEffectModifier) / (1 + mod.standardAffixEffectModifier),
-- mirroring AffixList.Affix.standardAffixEffectModifier in the LE
-- IL2CPP dump (dump_v142, line 164779):
--
--     "if this is 0.5, then an item with affix effect modifier of 0.5
--      will have the stated values, and an item with affix effect
--      modifier 0 will have 66.7% of the stated values."
--
--   (1 + 0.5) / (1 + 0.5) = 1.000  <- stated values
--   (1 + 0)   / (1 + 0.5) = 0.667  <- 66.7%
--
-- Subtraction (the historical formula) only coincides for
-- standardAffixEffectModifier == 0, which is the common case for
-- non-sealed affixes. It diverges for:
--   - sealed-corrupted (specialAffixType=6, e.g. affix 1070_0
--     "+1% All Resistances", standardAEM=-0.83) on non-Small idol
--     bases. Heretical Large Shadow Idol (AEM=-0.33):
--       subtraction: (1-0.33) - (-0.83) = 1.500
--       division:    (1-0.33) / (1-0.83) = 3.941
--     LE displays +3% per resist for affix 1070_0 on the
--     QkY53Rj6 Falconer build, matching division x 0.008 = 3.15%.
--   - Class-Specific Idol enchants (specialAffixType=4,
--     standardAEM=-0.33) on neutral bases (AEM=0):
--       subtraction: 1.33 (off vs Maxroll)
--       division:    1/0.67 = 1.493 ~ 1.5x  <- matches Maxroll
--     The historical "+0.17 fudge" branch in Item.lua existed
--     purely to compensate for the subtraction error on Solar Idol
--     (affix 892), and is removed alongside this fix.
--
-- Establishing build: QkY53Rj6 lv73 Falconer (Item 3, uniform -2 per
-- resist drift; Heretical Large Shadow Idol corrupted-sealed
-- 1070_0).

describe("AffixEffectModifierFormula", function()
    local function readFile(path)
        local f = assert(io.open(path, "r"), "missing: " .. path)
        local s = f:read("*a")
        f:close()
        return s
    end

    describe("Item.lua / ItemsTabCraft.lua use division (not subtraction)", function()
        local sources = {
            "../src/Classes/Item.lua",
            "../src/Classes/ItemsTabCraft.lua",
        }

        for _, path in ipairs(sources) do
            it(path .. " uses '/ (1 + standardAffixEffectModifier)' form", function()
                local src = readFile(path)
                -- At least one division-form occurrence (Item.lua has 3, Craft has 1)
                local pat = "modScalar%s*=%s*modScalar%s*/%s*%(1%s*%+%s*mod%.standardAffixEffectModifier%)"
                assert.is_truthy(src:find(pat),
                    "expected division form in " .. path)
                -- The buggy subtraction form must not survive
                local badPat = "modScalar%s*=%s*modScalar%s*%-%s*mod%.standardAffixEffectModifier"
                assert.is_falsy(src:find(badPat),
                    "subtraction form must not appear in " .. path)
            end)
        end
    end)

    describe("Item.lua: +0.17 Solar-Idol-parity fudge is removed", function()
        it("no `modScalar = modScalar + 0.17` branch", function()
            local src = readFile("../src/Classes/Item.lua")
            -- The fudge added 0.17 to compensate for the subtraction
            -- formula. With division it is no longer needed.
            local badPat = "modScalar%s*=%s*modScalar%s*%+%s*0%.17"
            assert.is_falsy(src:find(badPat),
                "+0.17 fudge for specialAffixType=4 must be removed")
        end)
    end)

    describe("Guard markers are present", function()
        it("Item.lua carries the @leb-regression-guard marker", function()
            local src = readFile("../src/Classes/Item.lua")
            assert.is_truthy(
                src:find("@leb%-regression%-guard:%s*affix%-effect%-modifier%-formula"),
                "guard marker missing in src/Classes/Item.lua")
        end)
        it("ItemsTabCraft.lua carries the @leb-regression-guard marker", function()
            local src = readFile("../src/Classes/ItemsTabCraft.lua")
            assert.is_truthy(
                src:find("@leb%-regression%-guard:%s*affix%-effect%-modifier%-formula"),
                "guard marker missing in src/Classes/ItemsTabCraft.lua")
        end)
    end)
end)
