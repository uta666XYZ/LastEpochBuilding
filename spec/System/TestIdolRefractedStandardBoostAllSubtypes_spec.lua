-- @leb-regression-guard: idol-refracted-standard-boost-all-subtypes
-- @leb-regression-guard: idol-altar-boost-subtype-rounding
-- See REGRESSION_GUARDS.md and Obsidian "Idol Altar boost rounding 仕様".
-- Validation provenance is retained in maintainer notes.

describe("IdolRefractedStandardBoostAllSubtypes", function()

    local source
    setup(function()
        local f = io.open("Modules/CalcSetup.lua", "r")
        assert.is_not_nil(f, "must be able to open Modules/CalcSetup.lua")
        source = f:read("*a")
        f:close()
    end)

    it("regression-guard comments are present", function()
        assert.is_truthy(string.find(source, "idol-refracted-standard-boost-all-subtypes", 1, true),
            "CalcSetup.lua must keep the @leb-regression-guard comment so future edits trip review")
        assert.is_truthy(string.find(source, "idol-altar-boost-subtype-rounding", 1, true),
            "CalcSetup.lua must keep the rounding @leb-regression-guard comment")
    end)

    -- NOTE (2026-07-16): these gates were rewritten from string tags to the raw LE
    -- enum integers -- Standard=0, IdolEnchantment=4, IdolWeaver=5, Corrupted=6. The
    -- string form was itself the bug: Data.lua string-tagged the ModIdol _0 entries
    -- while ModItem carried integers, so `mod.specialAffixType == 6` was always false
    -- on a tier-0 idol affix, and the same affix family changed TYPE between tier 0 and
    -- tier 1+. See @leb-regression-guard:idol-special-affix-type-is-integer and
    -- spec/System/TestIdolSpecialAffixTypeInteger_spec.lua. The INTENT pinned here is
    -- unchanged: which subtypes each altar property reaches.
    it("stdBoost (property 1/2/3) applies to Standard(0) + IdolWeaver(5) only", function()
        -- The boost gate must key off Standard OR IdolWeaver, NOT a blanket
        -- `sat ~= 6` (which would wrongly include IdolEnchantment).
        assert.is_truthy(
            string.find(source, 'local%s+stdBoost%s*=%s*%(sat%s*==%s*0%s+or%s+sat%s*==%s*5%)'),
            "stdBoost must be gated on `sat == 0 or sat == 5` so property 1/2/3 skips "
            .. "IdolEnchantment (driven by property 4 only) and Corrupted")
        assert.is_falsy(string.find(source, 'local%s+stdBoost%s*=%s*%(sat%s*~=%s*6%)'),
            "a blanket `sat ~= 6` gate would leak the boost onto IdolEnchantment")
        assert.is_falsy(string.find(source, 'sat%s*==%s*"Standard"'),
            "the string-tag form must not return -- it silently fails every integer test")
    end)

    it("weaverBoost (property 4) applies only to IdolEnchantment(4) / IdolWeaver(5)", function()
        assert.is_truthy(
            string.find(source, 'local%s+weaverBoost%s*=%s*%(sat%s*==%s*4%s+or%s+sat%s*==%s*5%)'),
            "weaverBoost must be gated on the IdolEnchantment/IdolWeaver subtypes")
        assert.is_falsy(string.find(source, 'sat%s*==%s*"IdolEnchantment"'),
            "the string-tag form must not return")
    end)

    it("all altar boosts use round-half-up (no postRoundFloor override)", function()
        -- The misdiagnosed property-4-only floor branch must be gone: CalcSetup
        -- must NOT set affix.postRoundFloor for altar boosts.
        assert.is_falsy(string.find(source, "weaverBoost%s*>%s*0%s+and%s+stdBoost%s*==%s*0"),
            "the property-4-only floor branch (`weaverBoost > 0 and stdBoost == 0`) must be removed; "
            .. "all altar boosts round-half-up")
    end)

    it("combined boost is stdBoost + weaverBoost applied as a postRoundScalar", function()
        -- The altar component is stdBoost + weaverBoost; since the
        -- different-shape-idol-stat-effect guard (Wings of Discord) the total
        -- boost additionally composes the wings boost ADDITIVELY:
        -- boost = (stdBoost + weaverBoost) + wingsBoost.
        assert.is_truthy(string.find(source, "altarPart%s*=%s*stdBoost%s*%+%s*weaverBoost"),
            "the altar component must be the sum of stdBoost and weaverBoost")
        assert.is_truthy(string.find(source, "local%s+boost%s*=%s*altarPart%s*%+%s*%(wingsBoost%s+or%s+0%)"),
            "the total boost must compose the altar component and the wings boost additively")
        assert.is_truthy(string.find(source, "postRoundScalar%s*=%s*%(affix%.postRoundScalar%s+or%s+1%)%s*%*%s*%(1%s*%+%s*boost%)"),
            "boost must be folded into postRoundScalar (two-phase: round rolled value first, then scale)")
    end)
end)
