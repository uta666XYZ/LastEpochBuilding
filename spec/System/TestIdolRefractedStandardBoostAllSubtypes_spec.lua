-- @leb-regression-guard: idol-refracted-standard-boost-all-subtypes
-- @leb-regression-guard: idol-altar-boost-subtype-rounding
-- Locks the contract that LE Idol Altar property 1/2/3 ("Effect of Prefixes
-- and Suffixes / Prefixes / Suffixes for Idols in Refracted Slots") boost the
-- rolled value of EVERY non-Corrupted affix in a refracted slot, regardless of
-- SpecialAffixType — including IdolWeaver / IdolEnchantment affixes, NOT just
-- Standard. The earlier "Standard only" gate (a misread of dump.cs
-- `IsAffectedByAffectOfStandardPrefixesOrSuffixes`) silently dropped the boost
-- for builds whose refracted idols carry Weaver Idol affixes.
--
-- Establishing build: ZombieWarehouse lv72 Necromancer (Twisted Altar,
-- property 3 = +10% Effect of Suffixes for Idols in Refracted Slots). Its 4
-- refracted idols all carry IdolWeaver suffixes; in-game DOES boost them:
--   Chitin       PhysRes 23 -> 23x1.10 = 25.3 -> 25  (in-game total 77 = +2)
--   Many Threads Cold 5+10 -> 6+11 = 17                (in-game total 54 = +2)
--   Many Threads Light 5+10 -> 17                      (in-game total 47 = +2)
--   Repose       Mana 5 -> 5x1.10 = 5.5 -> 6           (in-game total 203 = +1)
-- All match ROUND-HALF-UP, not floor.
--
-- Rounding direction is PROPERTY-determined, not subtype-determined:
--   property 1/2/3 (stdBoost)   -> round-half-up
--   property 4   (weaverBoost)  -> floor  (verified BxvJP3g1 Many Threads
--                                          raw 6 -> 8 != 9 at property-4 +46%)
-- Floor therefore applies only when the boost is PURELY the property-4 path
-- (`weaverBoost > 0 and stdBoost == 0`).
--
-- See REGRESSION_GUARDS.md and Obsidian "Idol Altar boost rounding 仕様".

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

    it("stdBoost applies to every non-Corrupted subtype (not Standard-only)", function()
        -- The boost gate must key off `sat ~= \"Corrupted\"`, NOT `sat == \"Standard\"`.
        assert.is_truthy(string.find(source, 'local%s+stdBoost%s*=%s*%(sat%s*~=%s*"Corrupted"%)'),
            "stdBoost must be gated on `sat ~= \"Corrupted\"` so property 1/2/3 boost "
            .. "IdolWeaver / IdolEnchantment refracted affixes too")
        assert.is_falsy(string.find(source, 'sat%s*==%s*"Standard"%s+then%s+curBoost'),
            "the old Standard-only gate (`sat == \"Standard\" then curBoost`) must NOT return")
    end)

    it("weaverBoost (property 4) applies only to IdolEnchantment / IdolWeaver", function()
        assert.is_truthy(
            string.find(source, 'local%s+weaverBoost%s*=%s*%(sat%s*==%s*"IdolEnchantment"%s+or%s+sat%s*==%s*"IdolWeaver"%)'),
            "weaverBoost must be gated on the IdolEnchantment/IdolWeaver subtypes")
    end)

    it("floors ONLY when the boost is purely the property-4 weaver path", function()
        -- postRoundFloor must require weaverBoost > 0 AND stdBoost == 0, so that
        -- any property-1/2/3 contribution forces round-half-up.
        assert.is_truthy(string.find(source, "weaverBoost%s*>%s*0%s+and%s+stdBoost%s*==%s*0"),
            "postRoundFloor must be set only when `weaverBoost > 0 and stdBoost == 0`; "
            .. "any stdBoost (property 1/2/3) participation must keep round-half-up")
        -- And the floor flag is the thing guarded by that condition.
        local i = string.find(source, "weaverBoost%s*>%s*0%s+and%s+stdBoost%s*==%s*0")
        assert.is_not_nil(i)
        local window = string.sub(source, i, i + 120)
        assert.is_truthy(string.find(window, "postRoundFloor%s*=%s*true"),
            "the property-4-only branch must set affix.postRoundFloor = true")
    end)

    it("combined boost is stdBoost + weaverBoost applied as a postRoundScalar", function()
        assert.is_truthy(string.find(source, "local%s+boost%s*=%s*stdBoost%s*%+%s*weaverBoost"),
            "boost must be the sum of stdBoost and weaverBoost")
        assert.is_truthy(string.find(source, "postRoundScalar%s*=%s*%(affix%.postRoundScalar%s+or%s+1%)%s*%*%s*%(1%s*%+%s*boost%)"),
            "boost must be folded into postRoundScalar (two-phase: round rolled value first, then scale)")
    end)
end)
