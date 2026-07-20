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
--      `cloneWithIdolBoosts` only matches the string form, so a tier-
--      specific lookup silently routes to the "Standard" default and skips
--      the weaver-enchant boost entirely.
--
-- Triangulation case study: <private build> lv99 Necromancer
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

    -- REPLACES (2026-07-16) "normalises numeric SpecialAffixType enum to its string
    -- form". That test pinned a `satEnumToStr` coercion table whose only reason to
    -- exist was a bug: Data.lua string-tagged the ModIdol _0 entries while ModItem
    -- carried integers, so the two halves of the same affix family disagreed in type
    -- and `== 6` never fired on an idol. Data.lua now tags integers, so there is no
    -- coercion to pin -- the invariant worth locking is the ABSENCE of the string form.
    -- See @leb-regression-guard:idol-special-affix-type-is-integer and
    -- spec/System/TestIdolSpecialAffixTypeInteger_spec.lua (which proves the
    -- section->integer mapping is lossless against ModItem).
    it("CalcSetup compares specialAffixType as the raw LE enum integer, not a string tag", function()
        assert.is_not_nil(setupSrc, "must read CalcSetup.lua")
        assert.is_falsy(string.find(setupSrc, "satEnumToStr", 1, true),
            "the numeric->string coercion table must be gone; Data.lua tags integers now")
        for _, tag in ipairs({ "Standard", "IdolEnchantment", "IdolWeaver", "Corrupted" }) do
            assert.is_falsy(string.find(setupSrc, 'sat%s*==%s*"' .. tag .. '"'),
                "string-tag comparison `sat == \"" .. tag .. "\"` silently fails against "
                .. "the integers ModItem carries -- that was the original bug")
        end
        assert.is_truthy(string.find(setupSrc, "return entry.specialAffixType or 0", 1, true),
            "specialAffixType must return the raw enum integer (defaulting to Standard=0)")
    end)

    it("CalcSetup prefers the _0 entry for SpecialAffixType lookup (avoids tier-numeric leak)", function()
        assert.is_not_nil(setupSrc, "must read CalcSetup.lua")
        -- The _0 entry is the canonical idol-pool entry (the only tier ModIdol
        -- actually stores); tier-specific keys resolve through flat's __index to
        -- ModItem (guard idol-affix-tier-fallback). Both carry the same integer now,
        -- so this is no longer load-bearing for correctness -- but the idol pool
        -- remains the authority for idol-specific corrections, so lock the
        -- preference order: base("_0") first, tier fallback second.
        assert.is_truthy(string.find(setupSrc,
            'local entry = %(base and idolFlat%[base %.%. "_0"%]%) or idolFlat%[modId%]',
            1, false),
            "specialAffixType must resolve via the _0 base entry first, tier-specific entry only as fallback")
    end)
end)
