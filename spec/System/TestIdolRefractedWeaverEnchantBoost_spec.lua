-- @leb-regression-guard: idol-refracted-weaver-enchant-boost
-- Locks the two halves of the +N% "Effect of Weaver Enchantment Affixes for
-- Idols in Refracted Slots" boost (LE Idol Altar property 4,
-- `EffectOfIdolEnchantsInRefractedSlots`). Both bugs below produced a silent
-- zero-boost outcome that looked correct in isolation:
--
--   1. ModParser.lua pattern coverage.
--      The in-game tooltip text for the Weaver Enchantment variant of the
--      Idol Altar refracted-slot affixes omits the word "increased" and is
--      prefixed with "+", e.g. "+(46-52)% Effect of Weaver Enchantment
--      Affixes for Idols in Refracted Slots". The Standard prefix / suffix
--      variants instead read "(15-17)% increased Effect of …" (no "+",
--      with "increased"). A single `^N%% increased effect of …` pattern
--      matches the Standard variants but silently drops the Weaver variant,
--      leaving `IdolRefractedWeaverEffect` un-summed in modDB.
--   2. CalcSetup.lua `specialAffixType` enum normalisation.
--      `ModIdol_<ver>.json` `_0` entries get the SpecialAffixType STRING
--      tag injected by `Data.lua` (general→Standard, enchanted→
--      IdolEnchantment, weaver→IdolWeaver, corrupted→Corrupted). Tier-
--      specific entries (e.g. `897_4`) may instead carry the raw NUMERIC
--      LE enum value (4 for IdolEnchantment). The clone-time routing in
--      `cloneWithAltarBoost` only matches the string form, so a tier-
--      specific lookup silently routes to the "Standard" default and skips
--      the weaver-enchant boost entirely.
--
-- Triangulation case study: BxvJP3g1 lv99 Necromancer
--   Altar of Arctus property 4 = +46%, Heretical Large Immortal Idol with
--   affix 897_4 "+10 Ward per Second" — LE/LETools display
--   floor(10 × 1.46 + 0.5) = 15. Pre-fix LEB showed 10, producing
--   Ward Regen Δ-5 (60 vs 65) and Ward Decay Threshold Δ-14 (72 vs 86).
--   Both stats are driven by the same affix family and reconcile with the
--   same +46% boost once both halves of the fix are in place.
--
-- See REGRESSION_GUARDS.md "idol-refracted-weaver-enchant-boost".

describe("IdolRefractedWeaverEnchantBoost", function()
    local function readFile(path)
        local f = io.open(path, "r")
        if not f then return nil end
        local s = f:read("*a"); f:close()
        return s
    end

    local parserSrc = readFile("Modules/ModParser.lua")
    local setupSrc  = readFile("Modules/CalcSetup.lua")

    it("ModParser accepts both 'increased effect' and '+N% effect' weaver variants", function()
        assert.is_not_nil(parserSrc, "must read ModParser.lua")
        -- Both patterns must exist. The "+" prefix anchor is what lets the
        -- in-game "+(46-52)%" text match. Plain-text substring search.
        assert.is_truthy(string.find(parserSrc,
            '["^%+?(%d+)%% increased effect of weaver enchantment affixes for idols in refracted slots$"]',
            1, true),
            "ModParser must accept the 'increased effect' weaver variant with optional '+' prefix")
        assert.is_truthy(string.find(parserSrc,
            '["^%+?(%d+)%% effect of weaver enchantment affixes for idols in refracted slots$"]',
            1, true),
            "ModParser must accept the bare 'effect of weaver enchantment affixes' variant (no 'increased')")
    end)

    it("CalcSetup specialAffixType normalises numeric SpecialAffixType enum to its string form", function()
        assert.is_not_nil(setupSrc, "must read CalcSetup.lua")
        -- The numeric→string lookup table must exist and cover the four
        -- enum values used at runtime (Standard=0, IdolEnchantment=4,
        -- IdolWeaver=5, Corrupted=6). The string-tag routing branch in
        -- scaleAffixList only matches "IdolEnchantment" / "IdolWeaver"
        -- exactly, so a tier-specific entry carrying numeric 4 must be
        -- coerced or the boost silently drops.
        assert.is_truthy(string.find(setupSrc,
            '%[0%]%s*=%s*"Standard"', 1, false),
            "specialAffixType enum table must map 0 → Standard")
        assert.is_truthy(string.find(setupSrc,
            '%[4%]%s*=%s*"IdolEnchantment"', 1, false),
            "specialAffixType enum table must map 4 → IdolEnchantment")
        assert.is_truthy(string.find(setupSrc,
            '%[5%]%s*=%s*"IdolWeaver"', 1, false),
            "specialAffixType enum table must map 5 → IdolWeaver")
        assert.is_truthy(string.find(setupSrc,
            '%[6%]%s*=%s*"Corrupted"', 1, false),
            "specialAffixType enum table must map 6 → Corrupted")
        assert.is_truthy(string.find(setupSrc,
            'if type%(sat%) == "number" then return satEnumToStr%[sat%]', 1, false),
            "specialAffixType must coerce numeric LE enum values via satEnumToStr before returning")
    end)

    it("CalcSetup prefers the _0 entry for SpecialAffixType lookup (avoids tier-numeric leak)", function()
        assert.is_not_nil(setupSrc, "must read CalcSetup.lua")
        -- The _0 entry is the only one guaranteed to carry the string
        -- specialAffixType tag from Data.lua. Looking up the tier-specific
        -- key first risks finding a numeric-tagged entry. Lock the
        -- preference order: base("_0") first, tier fallback second.
        assert.is_truthy(string.find(setupSrc,
            'local entry = %(base and idolFlat%[base %.%. "_0"%]%) or idolFlat%[modId%]',
            1, false),
            "specialAffixType must resolve via the _0 base entry first, tier-specific entry only as fallback")
    end)
end)
