-- @leb-regression-guard: slot-override-post-saem
-- Locks Item.lua's usingSlotOverride branch: when a slotOverride is selected,
-- modScalar must be 1 unconditionally (no standardAffixEffectModifier
-- subtraction). The override ranges are already LE-displayed values with both
-- the base affixEffectModifier and the per-affix sealed sAEM baked in;
-- subtracting sAEM here double-applies the penalty.
--
-- Game-data evidence (2026-05-12): BZ37dR2l Sorcerer Unstable Core (body
-- armor) corrupted sealed prefix 1014_4, sAEM=0.17, range:69, body_armor
-- override "+(46-50) Mana". LE in-game / LETools display +47. Pre-fix LEB
-- showed 47 × 0.83 = 39.
--
-- See REGRESSION_GUARDS.md "slot-override-post-saem".

describe("SlotOverridePostSaem", function()

    local source
    setup(function()
        local f = io.open("Classes/Item.lua", "r")
        assert.is_not_nil(f, "must be able to open Classes/Item.lua")
        source = f:read("*a")
        f:close()
        -- Item.lua is checked-in with CRLF line endings on Windows; normalize
        -- so the block-matching pattern below doesn't depend on platform.
        source = source:gsub("\r\n", "\n")
    end)

    it("guard comment block is present", function()
        assert.is_truthy(string.find(source, "slot-override-post-saem", 1, true),
            "Item.lua must keep the @leb-regression-guard comment so future edits trip review")
    end)

    it("usingSlotOverride branch does not subtract standardAffixEffectModifier", function()
        -- Locate the usingSlotOverride if-block and assert it sets modScalar=1
        -- without re-subtracting standardAffixEffectModifier inside the branch.
        local block = string.match(source,
            "if usingSlotOverride then(.-)\n%s*end\n")
        assert.is_not_nil(block,
            "must find a single-line `if usingSlotOverride then ... end` block")
        assert.is_truthy(string.find(block, "modScalar = 1", 1, true),
            "branch must set modScalar = 1")
        -- The branch may MENTION standardAffixEffectModifier in comments
        -- (explaining what NOT to do), but must not contain the actual
        -- subtraction assignment.
        assert.is_falsy(string.find(block,
            "modScalar = modScalar %- mod%.standardAffixEffectModifier"),
            "branch must NOT subtract mod.standardAffixEffectModifier — that double-applies the sealed sAEM penalty when the override already bakes it in")
    end)
end)
