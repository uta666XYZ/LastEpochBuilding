-- Last Epoch Building
-- @leb-canary v1 / id:leb-2e7a08-itemtools-2026 / do-not-remove (see Development/リリース手順.md)
--
-- Module: Item Tools
-- Various functions for dealing with items.
--
local t_insert = table.insert
local t_remove = table.remove
local m_min = math.min
local m_max = math.max
local m_floor = math.floor
local m_ceil = math.ceil

-- @leb-regression-guard:applyrange-float32-boundary
-- LuaJIT ffi float32 round-trip. LE evaluates its value interpolation
-- (BaseStats.GetValueAfterRounding) in single precision; LEB must round each
-- intermediate product to float32 to reproduce the game's truncation at exact
-- integer boundaries (see itemLib.applyRangeStrict). A double-precision reduction
-- lands on N.0 where the game's float32 lands on (N-1).9999 → truncates to N-1.
local ffi = require("ffi")
local f32buf = ffi.new("float[1]")
local function toF32(x)
    f32buf[0] = x
    return f32buf[0]
end

-- @leb-regression-guard:banker-round-vshdm
-- C# Math.Round / Mathf.RoundToInt default = MidpointRounding.ToEven (banker's
-- rounding). LE's vshDm endpoint quantization (FUN_18038f970 in
-- AscendingValueAfterPropertyRounding datamined offset) uses banker's rounding,
-- not half-up. The boundary case that matters in practice is
-- scaler-applied .5 fractions: e.g. min=61 max=75 scalar=1.5 produces
-- min*scalar=91.5 max*scalar=112.5; banker rounds these to 92/112 (both even),
-- not 92/113 like half-up does. This shifts the byte=93 result from 100 to 99
-- on <private build> lv98 Paladin Body Armor void resist suffix (matches LE tooltip
-- breakdown +99% Void Resistance).
local function banker_round(x)
    local f = m_floor(x)
    local frac = x - f
    if frac < 0.5 then
        return f
    elseif frac > 0.5 then
        return f + 1
    else
        -- exactly at 0.5: round to even
        if f % 2 == 0 then return f else return f + 1 end
    end
end

itemLib = { }

-- @leb-regression-guard: rounding-mode-default-floor
-- The DEFAULT must stay `false` (= floor). Live LEB GUI (Launch.lua) never
-- flips this, so default false is what end-users see; floor matches the
-- in-game tooltip per-affix display. Flipping the default to true silently
-- shifts every live build's stat values by ±1/affix and re-introduces the
-- 2026-05-04 ShutFackUp Mercurial Shrine Boots regression (LEB 79% vs
-- in-game 78%).
-- Test: spec/System/TestItemTools_spec.lua "production (floor) matches
--       in-game tooltip on % reduced affix"
-- Establishing reference: see git log
--
-- Per-affix rounding mode for `% increased/reduced/more/less` lines.
-- false (default, production): floor — matches in-game tooltip per-affix display.
-- true  (test/snapshot mode):   round-half-up — matches LETools/Maxroll display,
-- which existing test fixtures and snapshots were generated against.
-- HeadlessWrapper.lua flips this to true so spec/ runs stay LETools-compatible.
itemLib.useLEToolsRounding = false

-- Influence info (unused in Last Epoch, kept as empty table for compatibility)
itemLib.influenceInfo = { }

-- ============================================================================
-- Shared icon cache (used by ItemListControl and ItemSlotControl).
-- Single NewImageHandle per Asset filename, shared across all controls.
-- Per-control caches were causing duplicate texture handles for the same file
-- and a non-deterministic C++ renderer crash when both controls rendered
-- simultaneously (see Bug Tracker: primordial-add crash, 2026-04-26).
-- ============================================================================
local sharedIconHandles = {}
itemLib._sharedIconHandles = sharedIconHandles

-- Item type -> 16x16 icon filename (in Assets/).
local TYPE_ICON = {
	["Amulet"]            = "Icon_Amulet.png",
	["Belt"]              = "Icon_Belt.png",
	["Body Armor"]        = "Icon_Armor.png",
	["Boots"]             = "Icon_Boots.png",
	["Bow"]               = "Icon_Bow.png",
	["Dagger"]            = "Icon_Dagger.png",
	["Gloves"]            = "Icon_Gloves.png",
	["Helmet"]            = "Icon_Helmet.png",
	["Off-Hand Catalyst"] = "Icon_Offhand.png",
	["One-Handed Axe"]    = "Icon_Axe.png",
	["Two-Handed Axe"]    = "Icon_Axe.png",
	["One-Handed Mace"]   = "Icon_Mace.png",
	["Two-Handed Mace"]   = "Icon_Mace.png",
	["One-Handed Sword"]  = "Icon_Sword.png",
	["Two-Handed Sword"]  = "Icon_Sword.png",
	["Two-Handed Spear"]  = "Icon_Polearm.png",
	["Two-Handed Staff"]  = "Icon_Staff.png",
	["Quiver"]            = "Icon_Quiver.png",
	["Relic"]             = "Icon_Relic.png",
	["Ring"]              = "Icon_Ring.png",
	["Sceptre"]           = "Icon_Sceptre.png",
	["Shield"]            = "Icon_Shield.png",
	["Wand"]              = "Icon_Wand.png",
	["Idol Altar"]        = "idol/Idol_Altar_Pyramidal_Altar.png",
	["Blessing"]          = "blessings/body_of_obsidian.png",
}

function itemLib.iconFileForItem(item)
	if not item or not item.type then return nil end
	local t = item.type
	local f = TYPE_ICON[t]
	if f then return f end
	if t:find("Idol") then return "Icon_Idol.png" end
	return nil
end

function itemLib.getIconHandle(filename)
	if not filename then return nil end
	if not sharedIconHandles[filename] then
		local h = NewImageHandle()
		h:Load("Assets/" .. filename)
		sharedIconHandles[filename] = h
	end
	return sharedIconHandles[filename]
end

-- Primordial detection: covers (a) currently-active craft editor state,
-- (b) explicitModLines flagged by CraftRebuildItem, and (c) any prefix/suffix
-- mod whose specialAffixType == 7 (covers imported items too).
function itemLib.itemHasPrimordial(item)
	if not item then return false end
	if item.primordial then return true end
	if item.craftState and item.craftState.affixState
		and item.craftState.affixState.primordial
		and item.craftState.affixState.primordial.modKey ~= nil then
		return true
	end
	if item.explicitModLines then
		for i, line in ipairs(item.explicitModLines) do
			if line.primordial then return true end
		end
	end
	if item.affixes then
		local lists = { item.prefixes, item.suffixes }
		for li = 1, 2 do
			local list = lists[li]
			if list then
				for si, slot in ipairs(list) do
					if slot.modId and slot.modId ~= "None" then
						local mod = item.affixes[slot.modId]
						if mod and mod.specialAffixType == 7 then return true end
					end
				end
			end
		end
	end
	return false
end

-- Returns a list (table) of icon handles for this item, in display order:
-- [type, primordial?, corrupted?]. Returns nil if no icons resolvable.
function itemLib.getItemIcons(item)
	if not item then return nil end
	local list = {}
	local fname = itemLib.iconFileForItem(item)
	local h = itemLib.getIconHandle(fname)
	if h and h:IsValid() then t_insert(list, h) end
	if itemLib.itemHasPrimordial(item) then
		local p = itemLib.getIconHandle("Icon_Primordial.png")
		if p and p:IsValid() then t_insert(list, p) end
	end
	if item.corrupted then
		local c = itemLib.getIconHandle("Icon_Corrupted.png")
		if c and c:IsValid() then t_insert(list, c) end
	end
	if #list == 0 then return nil end
	return list
end

local antonyms = {
    ["increased"] = "reduced",
    ["reduced"] = "increased",
    ["more"] = "less",
    ["less"] = "more",
}

local function antonymFunc(num, word)
    local antonym = antonyms[word]
    return antonym and (num .. " " .. antonym) or ("-" .. num .. " " .. word)
end

-- Apply range value (0 to 256) to a modifier that has a range: "(x-x)" or "(x-x) to (x-x)"
-- @leb-regression-guard: two-phase-floor-post-round-scalar
-- `postRoundScalar` (optional, default 1.0) models LE's
-- `ChangeAffixModifier(..., float affixEffectModifier, ..., float
-- postRoundingEffectModifier = 0)` (datamined game source). LE applies the
-- post-round scalar AFTER the rolled value has been quantized to its display
-- integer/fraction. The post-boost integer is then rendered with
-- **round-half-up**, NOT floor — verified by comparing LETools planner
-- tooltips against in-game UI on <private build> Spellblade lv99 idol-altar.
-- Folding refracted-slot altar boosts (Weaver Enchant ~22%) into
-- `valueScalar` instead of this dedicated arg lets the unrounded
-- interpolation fraction leak through the boost.
-- Verified on <private build> Heretical Large Arcane Idol affix 897_4
-- "+(2-9) Ward per Second" T5 byte=255 boost=1.22:
--   rolled = 9, 9 × 1.22 = 10.98
--   floor          → 10 (pre-fix LEB, mismatched LETools/in-game)
--   round-half-up  → 11 (post-fix LEB; matches LETools tooltip)
-- See REGRESSION_GUARDS.md "two-phase-floor-post-round-scalar" for the
-- 5 fix sites and the busted spec
-- (spec/System/TestPostRoundScalarRoundHalfUp_spec.lua).
-- `postRoundFloor` (optional, default false) overrides the post-round
-- scalar's default round-half-up to **floor**. It is NOT used by Idol Altar
-- refracted-slot boosts — those are all round-half-up (see CalcSetup
-- scaleAffixList `idol-altar-boost-subtype-rounding` guard for why the
-- earlier property-4→floor override was a misdiagnosis). The flag remains
-- for the `armour-percent-vshdm-strict` guard, whose strict "% Armour" lines
-- floor after the post-round scalar.
function itemLib.applyRange(line, range, valueScalar, rounding, postRoundScalar, postRoundFloor)
    -- High precision for increased modifier
    local precision = 100
    if rounding == "Integer" then
        precision = 1
    elseif rounding == "Tenth" then
        precision = 10
    elseif rounding == "Thousandth" then
        precision = 1000
    end
    -- If there is a percent, we need to divide the precision by 100
    -- @leb-regression-guard: per-mana-cost-melee-affix-fractional-precision
    -- The "... for Melee Attacks per 1 Mana Cost" affix family (combined affix
    -- 986: the Damage MORE sub-line, plus the Critical Strike Chance / Area
    -- siblings) rolls FRACTIONAL percentages (LE property_list_1_4.json
    -- property 0 "Damage" roundingForMore = Hundredth; the roll is e.g.
    -- 0.2%/0.3%). The generic "% => integer percent" collapse below (default
    -- rounding => precision 100, then /100 => 1) would round the scalar-scaled
    -- value to an INTEGER: 0.3 x weapon-slot scalar 1.829 = 0.549 => round => 1
    -- (~3-5x too high). The {rounding:Integer} that ships on the combined
    -- affix is legitimate for the integer "increased Melee Damage" part, but
    -- must NOT collapse this fractional per-mana sub-line. Keep Hundredth
    -- precision (0.01) so the fraction survives scaling (0.549 => 0.55).
    -- Scoped by the "per 1 Mana Cost" token, which no non-per-mana affix uses.
    -- Spec: spec/System/TestPerManaCostMeleeAffix_spec.lua.
    local isPerManaCostFractional = line:lower():find("per 1 mana cost") ~= nil
    if line:find("%%") and precision >= 100 and not isPerManaCostFractional then
        precision = precision / 100
    end
    -- "+(N-N) to <name>" style affixes (e.g. "+(2-4) to Cinder Strike",
    -- "+(1-3) to Strength Skills", "+(2-6) to All Attributes") always roll
    -- discrete integers in LE — the rolled byte 0..255 maps to {min,...,max}
    -- with no fractional positions. When the unique data omits the explicit
    -- {rounding:Integer} directive we used to interpolate at precision=100,
    -- producing fractional skill-level contributions like +2.46 that drift
    -- the cap (Kuzon's Fury "+(2-4) to Cinder Strike" → LEB 30 vs game 29).
    -- Auto-force integer precision when the line has "+(range) to <alpha>"
    -- with no explicit rounding directive or %.
    if not rounding and not line:find("%%") and line:find("^%+?%([%-%d%.]+%-[%-%d%.]+%) to %a") then
        precision = 1
    end

    -- @leb-regression-guard: per-set-integer-source-not-halfstep
    -- "per Complete Set" Integer affixes (e.g. Legends Entwined
    -- "{rounding:Integer}+(2-5) to All Attributes per Complete Set") use the
    -- NORMAL integer roll path (precision=1) — NO special half-step bump.
    --
    -- Grounded against the datamining (datamined game source):
    --   * EpochExtensions.GetValueAfterRounding (formulas_verified.md §38) has
    --     ONLY integer / tenth / hundredth / thousandth modes -- there is NO
    --     0.5-step rounding mode anywhere. An Integer affix's per-source value
    --     is an INTEGER.
    --   * CharacterMutator (CharacterMutator.c L9697 accumulate, L10497-10501
    --     apply) computes the applied stat as a raw float
    --       current = completeItemSetsEquipped * allAttributesPerCompleteSet
    --     with NO floor/round after the multiply; the All-Attributes total is
    --     floored only at final display. Integer per-source * integer count is
    --     already exact, so roundAfterMultiply (ModStore EvalMod) is a harmless
    --     no-op for this affix.
    --   * Game unique data (uniques_v3.json id 423): mod value=2 max=5
    --     property=98 tags=566 type=0(ADDED) -- a plain integer attribute roll.
    --
    -- The previous `precision=2` half-step bump was a fictional mechanic fit to
    -- LETools display, not in-game (<private build> is a `.letools.*` build). In-game
    -- capture refutes it: Aurora_blank Legends Entwined byte=205, CompleteSet=2
    -- shows All Attributes = 10 = 5*2; the normal integer path gives
    -- floor(2 + 4*205/255) = floor(5.216) = 5 -> 5*2 = 10 (correct), while the
    -- half-step model stored 4.5 -> floor(4.5*2) = 9 (the -1 bug). byte=203
    -- (<private build>, near-identical roll) -> 5 -> *6 = 30, NOT the LETools 27 the
    -- old fit chased.
    -- Spec: spec/System/TestPerCompleteSetIntegerRoll_spec.lua

    -- range is actually given as a roll (TODO:rename)
    local rollByte = range
    range = range / 255.0

    local numbers = 0
    if not valueScalar then
        valueScalar = 1.0
    end
    -- Only "% increased/reduced/more/less" affixes use round; flat %, scalars, and flat values use floor
    local useRound = valueScalar == 1.0
        and (line:find("%% increased") ~= nil or line:find("%% reduced") ~= nil
             or line:find("%% more") ~= nil or line:find("%% less") ~= nil)
    local function roundHalfDownOnHalf(v)
        -- Round half-up, except x.5 rounds down (floor). Matches LE's endpoint rounding.
        if v * precision % 1 == 0.5 then
            return m_floor(v * precision) / precision
        end
        return m_floor(v * precision + 0.5) / precision
    end
    -- @leb-regression-guard: applyrange-fixed-tier-noop
    -- Lines without a `(min-max)` pattern are FIXED-VALUE tiers and must
    -- pass through `applyRange` unchanged regardless of the `range`/`r`
    -- byte. LETools T1-T7 corrupted tiers of affix 1011
    -- (`+N All Attributes with at least 7 Corrupted non-Idol Items
    -- equipped`) are fixed 8/9/10/11/12/13/14; only the primordial-only
    -- T8 carries `(19-21)`. A misstated REGRESSION_GUARDS claim that
    -- `1011_6 @ range 221 → +11` triggered a bogus investigation
    -- 2026-05-08; do NOT add a "scale fixed values too" patch here.
    -- See REGRESSION_GUARDS.md "applyrange-fixed-tier-noop".
    line = line:gsub("(%+?)%((%-?%d+%.?%d*)%-(%-?%d+%.?%d*)%)",
            function(plus, min, max)
                numbers = numbers + 1
                local minN = tonumber(min)
                local maxN = tonumber(max)
                -- Flat values (useRound=false) use (max-min+1/precision) span so the
                -- top byte (255) reaches max; percentage-with-word affixes (useRound=true)
                -- use the plain (max-min) span, matching LETools/Maxroll displays.
                --
                -- Applies to SP=88 LevelOfSkills "+(N-N) to <Skill/Cat>" too —
                -- a previous attempt (<see git log>) special-cased these to ceil
                -- based on a single Omnis byte=17→+2 datapoint, but a direct
                -- in-game verification on Phantom Grip "+(1-2) to All Minion
                -- Skills" at range:90 showed +1 each (not +2). ceil is not
                -- monotonically consistent with byte=17→+2 + byte=90→+1, so
                -- the Omnis observation was likely misread. Reverting to the
                -- shared linear-interp + floor path: byte=90 → 1+floor(0.706)
                -- = 1, byte=255 → 1+floor(2)=3 capped to 2.
                local span = maxN - minN
                -- Targeted fix: "+(N-N)% Physical Resistance" affixes use plain (max-min)
                -- span to match LE/LETools display. Verified vs in-game tooltip on
                -- ShutFackUp Cursed Coin Amulet (range 76, scalar 1.17, +(50-60)%):
                --   plain span 10 → (50 + 76/255 × 10) × 1.17 = 61.99 → 61 ✓
                --   span+1/prec  → (50 + 76/255 × 11) × 1.17 = 62.336 → 62 ✗
                -- The +1/precision adjustment was added for flat-integer affixes
                -- (e.g. "+(2-4) Strength") so the top byte reaches max; it does not
                -- match LE's percentage interpolation. Scoped narrowly here so the
                -- broader percentage path can be audited per resistance type.
                -- @leb-regression-guard: phys-res-vshdm-strict
                -- "% Physical Resistance" rolls are migrated to the game-faithful
                -- vshDm path (`applyRangeStrict`). Verified across 117 spec/1.4
                -- builds (.tmp/survey_phys_res_impact.py): scalar=1.0 → 0/193
                -- divergence; scalar=1.17 (Cursed Coin) → 1/193 unique tuple
                -- (`+(13-40)% Physical Resistance` byte=79: existing 24 → strict
                -- 25), affecting only `<private build> lv86 Bladedancer.xml`. The
                -- strict value 25 matches LE's in-game tooltip (vshDm direct port
                -- = datamined game source `BaseStats.GetValueAfterRounding`).
                -- @leb-regression-guard:resist-vshdm-strict
                -- All seven elemental resistances PLUS the composite
                -- "% Elemental Resistance" affix (cold+fire+lightning)
                -- route through the game-faithful vshDm Hundredth path.
                -- LE property_list_v3.json:
                --   property 52 "Elemental Resistance" roundingForAdded=0 (Hundredth)
                -- Pre-fix the default applyRange branch was missing LE's
                -- `+0.001` (fraction) / `+0.1` (percent) epsilon, and
                -- LEB's `applyRangeStrict` Hundredth branch had a
                -- unit-mismatch bug (see vshdm-percentage-units guard).
                -- AL07RL31 (Cold=39→40, Phys=58→59) verified vs in-game
                -- tooltip after the combined patch.
                if line:find("%% Cold Resistance")
                   or line:find("%% Fire Resistance")
                   or line:find("%% Lightning Resistance")
                   or line:find("%% Necrotic Resistance")
                   or line:find("%% Poison Resistance")
                   or line:find("%% Void Resistance")
                   or line:find("%% Physical Resistance")
                   or line:find("%% Elemental Resistance") then
                    local v = itemLib.applyRangeStrict(minN, maxN, rollByte, valueScalar, 0, 0)
                    if postRoundScalar and postRoundScalar ~= 1.0 then
                        if postRoundFloor then
                            v = m_floor(v * postRoundScalar * precision) / precision
                        else
                            v = m_floor(v * postRoundScalar * precision + 0.5) / precision
                        end
                    end
                    return (v < 0 and "" or plus) .. tostring(v)
                end
                -- @leb-regression-guard:minion-movement-speed-vshdm-strict
                -- "% increased/reduced Minion Movement Speed" rolls route through the
                -- LE-faithful vshDm Hundredth path. Triangulated on <private build> lv99
                -- Necromancer Pebbles' Collar Reforged implicit
                -- `(6-16)% increased Minion Movement Speed` byte=186:
                --   legacy round-half-up: floor((6 + 186/255 × 10) + 0.5) = 13
                --   strict (vshDm):       floor((16 + 1 - 6) × 186/255 + 6) = 14
                -- LETools planner Minion-tab "Movement Speed" = 14% — matches strict.
                -- Scoped narrowly to the "Minion Movement Speed" SP=9 minion-scope
                -- variant. The player-scope "% increased Movement Speed" line is
                -- handled by its own strict branch immediately below (same root
                -- cause). See REGRESSION_GUARDS.md
                -- "minion-movement-speed-vshdm-strict".
                if line:find("%% increased Minion Movement Speed")
                   or line:find("%% reduced Minion Movement Speed") then
                    local v = itemLib.applyRangeStrict(minN, maxN, rollByte, valueScalar, 0, 0)
                    if postRoundScalar and postRoundScalar ~= 1.0 then
                        if postRoundFloor then
                            v = m_floor(v * postRoundScalar * precision) / precision
                        else
                            v = m_floor(v * postRoundScalar * precision + 0.5) / precision
                        end
                    end
                    return (v < 0 and "" or plus) .. tostring(v)
                end
                -- @leb-regression-guard:movement-speed-vshdm-strict
                -- See REGRESSION_GUARDS.md "movement-speed-vshdm-strict".
                -- Validation provenance is retained in maintainer notes.
                if line:find("%% increased Movement Speed")
                   or line:find("%% reduced Movement Speed") then
                    local v = itemLib.applyRangeStrict(minN, maxN, rollByte, valueScalar, 0, 0)
                    if postRoundScalar and postRoundScalar ~= 1.0 then
                        if postRoundFloor then
                            v = m_floor(v * postRoundScalar * precision) / precision
                        else
                            v = m_floor(v * postRoundScalar * precision + 0.5) / precision
                        end
                    end
                    return (v < 0 and "" or plus) .. tostring(v)
                end
                -- @leb-regression-guard: health-percent-vshdm-strict
                -- See REGRESSION_GUARDS.md "health-percent-vshdm-strict".
                -- Validation provenance is retained in maintainer notes.
                if valueScalar == 1.0
                   and (line:find("%% increased Health") or line:find("%% reduced Health"))
                   and not line:find("Minion Health") and not line:find("Health Regen") then
                    local v = itemLib.applyRangeStrict(minN, maxN, rollByte, valueScalar, 0, 0)
                    if postRoundScalar and postRoundScalar ~= 1.0 then
                        if postRoundFloor then
                            v = m_floor(v * postRoundScalar * precision) / precision
                        else
                            v = m_floor(v * postRoundScalar * precision + 0.5) / precision
                        end
                    end
                    return (v < 0 and "" or plus) .. tostring(v)
                end
                -- @leb-regression-guard: armour-percent-vshdm-strict
                -- @leb-regression-guard: armour-percent-refracted-fractional
                -- See REGRESSION_GUARDS.md "armour-percent-vshdm-strict" /
                -- Validation provenance is retained in maintainer notes.
                if valueScalar == 1.0
                   and (line:find("%% increased Armou?r") or line:find("%% reduced Armou?r"))
                   and not line:find("Minion Armou?r") and not line:find("Armou?r Shred") then
                    local v = itemLib.applyRangeStrict(minN, maxN, rollByte, valueScalar, 0, 0)
                    if postRoundScalar and postRoundScalar ~= 1.0 then
                        if postRoundFloor then
                            -- Property-4 weaver-enchant boost (rare on % Armour):
                            -- preserve the verified floor direction.
                            v = m_floor(v * postRoundScalar * precision) / precision
                        else
                            -- Standard prefix/suffix boost: keep the fractional
                            -- product (hundredth quantum), do not collapse to int.
                            v = m_floor(v * postRoundScalar * 100 + 0.5) / 100
                        end
                    end
                    return (v < 0 and "" or plus) .. tostring(v)
                end
                -- @leb-regression-guard:pen-affix-vshdm-strict
                -- See REGRESSION_GUARDS.md "pen-affix-vshdm-strict".
                -- Validation provenance is retained in maintainer notes.
                if line:find("%)%% [%a%s]-Penetration")
                   and not line:find("Converted to")
                   and not line:find("%% increased") and not line:find("%% reduced")
                   and not line:find("%% more") and not line:find("%% less") then
                    -- @leb-regression-guard: hive-mind-pen-tenth-rounding
                    -- Most "% ... Penetration" affixes display whole (Hundredth), but
                    -- Hive Mind (270) "+(4-6)% ... Penetration ... per Dexterity" is
                    -- TENTH precision in-game (4.4%, not 4%). Honor an explicit
                    -- {rounding:Tenth} tag (parsed by ParseRaw into `rounding`) instead
                    -- of hardcoding Hundredth; untagged pen affixes (rounding=nil) keep
                    -- Hundredth and are byte-identical. byte 56 -> 4.4 (in-game match).
                    -- Test: spec/System/TestItemTools_spec.lua "...Penetration...per Dexterity"
                    local penRounding = (rounding == "Tenth") and 2 or 0
                    local v = itemLib.applyRangeStrict(minN, maxN, rollByte, valueScalar, 0, penRounding)
                    if postRoundScalar and postRoundScalar ~= 1.0 then
                        if postRoundFloor then
                            v = m_floor(v * postRoundScalar * precision) / precision
                        else
                            v = m_floor(v * postRoundScalar * precision + 0.5) / precision
                        end
                    end
                    return (v < 0 and "" or plus) .. tostring(v)
                end
                -- @leb-regression-guard: flat-int-vshdm-strict
                -- Flat-integer "+(N-N) <Stat>" affixes (no %) at scalar<=1.0
                -- migrate to the game-faithful vshDm Integer path. Survey
                -- (.tmp/survey_strict_scalar1.py / survey_strict_phase4.py)
                -- across 117 spec/1.4 builds:
                --   scalar=1.0  -> 0/3241 unique-tuple divergence
                --   scalar=0.67 -> 0/3241 (Grand idol)
                --   scalar=0.38 -> 0/3241 (Humble/Stout idol)
                -- For integer endpoints both formulas reduce to
                --   floor((halfup(max*s) + 1 - halfup(min*s)) * roll/255 + halfup(min*s))
                -- so this is a byte-identical migration covering scalar=1.0
                -- AND the humble-idol-scalar-scale-first branch's flat-int
                -- portion. Scalar > 1.0 flat-int (Apiarist=1.5: survey shows
                -- 656 mismatches; existing apiarist-scalar-interpolate-first
                -- guard is empirically validated against in-game tooltip)
                -- remains on the existing branch below.
                if precision == 1 and not line:find("%%") and valueScalar <= 1.0 then
                    local v = itemLib.applyRangeStrict(minN, maxN, rollByte, valueScalar, 0, 1)
                    if postRoundScalar and postRoundScalar ~= 1.0 then
                        -- @leb-regression-guard: flat-health-refracted-fractional
                        -- See REGRESSION_GUARDS.md "flat-health-refracted-fractional".
                        -- Validation provenance is retained in maintainer notes.
                        local flatHealth = line:find("Health")
                            and not line:find("Minion Health") and not line:find("Health Regen")
                        if postRoundFloor then
                            v = m_floor(v * postRoundScalar)
                        elseif flatHealth then
                            v = m_floor(v * postRoundScalar * 100 + 0.5) / 100
                        else
                            v = m_floor(v * postRoundScalar + 0.5)
                        end
                    end
                    return (v < 0 and "" or plus) .. tostring(v)
                end
                -- @leb-regression-guard: flat-int-vshdm-strict
                -- Flat-integer "+(N-N) <Stat>" affixes (no %) at scalar<=1.0
                -- migrate to the game-faithful vshDm Integer path. Survey
                -- (.tmp/survey_strict_scalar1.py / survey_strict_phase4.py)
                -- across 117 spec/1.4 builds:
                --   scalar=1.0  -> 0/3241 unique-tuple divergence
                --   scalar=0.67 -> 0/3241 (Grand idol)
                --   scalar=0.38 -> 0/3241 (Humble/Stout idol)
                -- For integer endpoints both formulas reduce to
                --   floor((halfup(max*s) + 1 - halfup(min*s)) * roll/255 + halfup(min*s))
                -- so this is a byte-identical migration covering scalar=1.0
                -- AND the humble-idol-scalar-scale-first branch's flat-int
                -- portion. Scalar > 1.0 flat-int (Apiarist=1.5: survey shows
                -- 656 mismatches; existing apiarist-scalar-interpolate-first
                -- guard is empirically validated against in-game tooltip)
                -- remains on the existing branch below.
                if precision == 1 and not line:find("%%") and valueScalar <= 1.0 then
                    local v = itemLib.applyRangeStrict(minN, maxN, rollByte, valueScalar, 0, 1)
                    return (v < 0 and "" or plus) .. tostring(v)
                end
                if not useRound then
                    span = span + 1 / precision
                end
                -- @leb-regression-guard: humble-idol-scalar-scale-first
                -- Idol size scaling (valueScalar < 1.0). Per
                -- src/Data/Bases/bases_1_4.json affixEffectModifier:
                --   Humble  (1×1) -0.62 -> scalar 0.38
                --   Stout   (1×2) -0.62 -> scalar 0.38   (NOT 0.67)
                --   Grand   (1×4) -0.33 -> scalar 0.67
                --   Adorned (1×3) -0.05 -> scalar 0.95
                --   Ornate  (2×2)  0    -> scalar 1.00
                -- rounds endpoints FIRST to LE's display integers, then interpolates
                -- within the scaled span. Without this branch:
                --   <private build> Humble Weaver byte=221, scalar=0.38, "+(3-7) Vitality"
                --     interp-first: (3 + 221/255 × 5) × 0.38 = 2.79 → floor=2  (LE=3 ✗)
                --     scale-first : round(3×0.38)=1, round(7×0.38)=3
                --                   1 + 221/255 × (3-1+1) = 3.60 → floor=3   (LE=3 ✓)
                --   <private build> Humble Weaver byte=98:
                --     interp-first: 1.87 → 1 (LE=2 ✗); scale-first: 2.15 → 2 (LE=2 ✓)
                --
                -- @leb-regression-guard: apiarist-scalar-interpolate-first
                -- Conversely, valueScalar > 1.0 (Apiarist's Suit unique = 1.5) MUST
                -- interpolate first then scale, otherwise the integer grid shifts
                -- and the top byte underrepresents:
                --   Str "+(11-13)" × 1.5 byte=57:
                --     interp-first: (11 + 57/255 × 3) × 1.5 = 17.51 → floor=17 (LE=17 ✓)
                --     scale-first : round(16.5)=16, round(19.5)=19
                --                   16 + 57/255 × 4 = 16.89 → floor=16        (LE=17 ✗)
                -- Discriminator is `valueScalar < 1.0`. Phys Resistance is now
                -- handled separately above via applyRangeStrict.
                -- See REGRESSION_GUARDS.md "humble-idol-scalar-scale-first" and
                -- "apiarist-scalar-interpolate-first".
                local numVal
                if not useRound and valueScalar < 1.0 then
                    local minScaled = roundHalfDownOnHalf(minN * valueScalar)
                    local maxScaled_local = roundHalfDownOnHalf(maxN * valueScalar)
                    local localSpan = maxScaled_local - minScaled + 1 / precision
                    numVal = minScaled + range * localSpan
                else
                    -- Interpolate first, THEN apply valueScalar, to match LE/LETools.
                    numVal = (minN + range * span) * valueScalar
                end
                if useRound and itemLib.useLEToolsRounding then
                    numVal = m_floor(numVal * precision + 0.5) / precision
                else
                    numVal = m_floor(numVal * precision) / precision
                end
                local maxScaled = roundHalfDownOnHalf(maxN * valueScalar)
                if numVal > maxScaled then
                    numVal = maxScaled
                end
                if postRoundScalar and postRoundScalar ~= 1.0 then
                    if postRoundFloor then
                        numVal = m_floor(numVal * postRoundScalar * precision) / precision
                        local maxBoosted = m_floor(maxScaled * postRoundScalar * precision) / precision
                        if numVal > maxBoosted then numVal = maxBoosted end
                    else
                        numVal = m_floor(numVal * postRoundScalar * precision + 0.5) / precision
                        local maxBoosted = m_floor(maxScaled * postRoundScalar * precision + 0.5) / precision
                        if numVal > maxBoosted then numVal = maxBoosted end
                    end
                end
                return (numVal < 0 and "" or plus) .. tostring(numVal)
            end)
               :gsub("%-(%d+%.?%d*%%) (%a+)", antonymFunc)
    -- Single-value scaling: affixes like "+5% Critical Strike Multiplier" have no
    -- (x-x) range, but still need valueScalar applied when the affix scales with
    -- the base (e.g. Class-Specific Idol enchants). Only applied when scalar != 1.
    if valueScalar ~= 1.0 and numbers == 0 then
        line = line:gsub("^(%+?)(%-?%d+%.?%d*)", function(plus, num)
            local v = roundHalfDownOnHalf(tonumber(num) * valueScalar)
            if postRoundScalar and postRoundScalar ~= 1.0 then
                if postRoundFloor then
                    v = m_floor(v * postRoundScalar * precision) / precision
                else
                    v = m_floor(v * postRoundScalar * precision + 0.5) / precision
                end
            end
            return plus .. tostring(v)
        end, 1)
    elseif (valueScalar == 1.0) and postRoundScalar and postRoundScalar ~= 1.0 and numbers == 0 then
        line = line:gsub("^(%+?)(%-?%d+%.?%d*)", function(plus, num)
            local v
            if postRoundFloor then
                v = m_floor(tonumber(num) * postRoundScalar * precision) / precision
            else
                v = m_floor(tonumber(num) * postRoundScalar * precision + 0.5) / precision
            end
            return plus .. tostring(v)
        end, 1)
    end
    -- Single-value paren form `+(N)` (no min-max). LE renders some affixes as
    -- `+(4) Maximum Omen Idols Equipped` for fixed-value rolls. The range gsub
    -- above only matches `+(min-max)`, so single-value parens remain literal,
    -- breaking the downstream parseMod form detection (`+(4) Foo` vs `+4 Foo`).
    -- Strip the parens here so parseMod sees a clean `+4 Maximum Omen Idols`.
    line = line:gsub("(%+?)%((%-?%d+%.?%d*)%)", "%1%2")
    return line
end

function itemLib.hasRange(line)
    return line:find("%(%-?%d+%.?%d*%-%-?%d+%.?%d*%)");
end

-- @leb-regression-guard: vshdm-direct-port
-- Direct numeric port of LE planner JS `vshDm` ( = datamined game source
-- `BaseStats.GetValueAfterRounding` ). Reproduces the game's interpolation
-- bit-for-bit so LEB can be game-faithful per stat once the existing
-- empirical workarounds (`useRound`, `skipSpanBump`, scalar-order branches
-- in `applyRange`) are migrated stat-by-stat.
--
-- Inputs:
--   minN, maxN : roll endpoints (post-localization, pre-scalar)
--   roll       : 0..255 byte
--   scalar     : valueScalar (idol size / unique scalar). Default 1.0.
--   modType    : BaseStats.ModType  (0=ADDED 1=INCREASED 2=MORE 3=QUOTIENT)
--   rounding   : PropertyRounding   (0=Hundredth 1=Integer 2=Tenth 3=Thousandth)
--                from src/Data/Properties/property_list_1_4.json bySP[<SP>]
--                .roundingForAdded.
--
-- Output: numeric value (caller composes the line / suffix).
--
-- Game behavior (verified against LE 1.4.6 datamined game source dump datamined offset +
-- planner JS `function vshDm(a,b,c,d,e)` decoded 2026-05-09):
--   * Endpoints are rounded HALF-UP to the rounding precision FIRST.
--   * Span uses `(max + 1/precision - min)` so the top byte (255) reaches max.
--   * Hundredth-ADDED carries a `+0.001` epsilon to nudge boundary values.
--   * Non-ADDED branch is forced to Hundredth precision regardless of input
--     `rounding` argument (matches `if (0 != b)` clause in vshDm).
--   * Final clamp: `min(v, d)`.
--
-- This function is intentionally PURE: no string parsing, no global state,
-- no feature-flag check. Callers gate adoption per call site.
-- Reference: src/Data/Properties/property_list_1_4.json (extracted from
-- LE 1.4.6 resources.assets via TypeTreeGeneratorAPI).
function itemLib.applyRangeStrict(minN, maxN, roll, scalar, modType, rounding)
    scalar   = scalar   or 1.0
    modType  = modType  or 0
    rounding = rounding or 0
    if scalar ~= 1.0 then
        minN = minN * scalar
        maxN = maxN * scalar
    end
    if minN > maxN then
        return minN
    end
    -- @leb-regression-guard:vshdm-percentage-units
    -- @leb-regression-guard:banker-round-vshdm
    -- @leb-regression-guard:applyrange-float32-boundary
    -- LE's AscendingValueAfterPropertyRounding (datamined offset) is:
    --   c_int = banker_round(gm * min_scaled)          (FUN_18038f970, ToEven)
    --   d_int = banker_round(gm * max_scaled)
    --   c = c_int / scale_f32                          (Hundredth: 100, Tenth: 10)
    --   d = d_int / scale_f32 + epsilon_f32            (epsilon = 1/scale)
    --   raw = ((d - c) * (byte / 255_f32) + c) * scale_f32   -- ALL float32
    --   result = Math.Truncate(raw) / gm               (FUN_180322480, signed truncate)
    -- This is evaluated in SINGLE precision. The prior LEB code collapsed it to the
    -- exact-double reduction `floor((d_int - c_int + 1) * (byte/255) + c_int)`, which
    -- is algebraically equal but NOT bit-equal: at exact integer boundaries the double
    -- reduction lands on N.0 while the game's float32 evaluation lands on (N-1).9999…
    -- and truncates to N-1. Rounding each intermediate product to float32 (`toF32`,
    -- matching the game's operation order) IS this path's purpose — do NOT re-collapse
    -- it to the double form. The move is NOT one-directional: a double UNDER-read
    -- (exact rational = N.0, double lands N-0.0001 → N-1) is corrected UP by float32.
    -- Both are boundary-only (~0.14% of Hundredth triples, ~98% down / ~2% up).
    -- LEB callers store percentages, so Hundredth uses gm=1 (endpoints are whole
    -- percents) with scale=100; Tenth/Thousandth carry gm=scale so their sub-integer
    -- resolution survives; Integer is gm=scale=1.
    -- LEB's previous formulation used HALF-UP endpoint rounding and an extra
    -- "+0.1" bias which was a legacy hack that only worked away from .5
    -- scaler boundaries. The half-up vs banker divergence shows up when
    -- min*scalar or max*scalar lands exactly on .5 (e.g. 61*1.5=91.5,
    -- 75*1.5=112.5 → half-up gives 92/113, banker gives 92/112).
    -- Constants (verified from datamined game source .rdata 2026-05-10):
    --   DAT_183d81c50 = 255.0 (byte divisor)
    --   DAT_183d81f48 = 100.0 (Hundredth scale)
    --   DAT_183d81ddc = 0.01  (Hundredth epsilon)
    --   DAT_183d81e0c = 10.0, DAT_183d81de8 = 0.1   (Tenth)
    --   DAT_183d81e84 = 1000.0, DAT_183d81bdc = 0.001 (Thousandth)
    -- @leb-regression-guard: applyrange-no-epsilon-truncate
    -- No round-up epsilon: the game interpolates in float32 and TRUNCATES, so the
    -- legacy +0.1 was removed and MUST stay removed. Grounded by a live in-game
    -- capture (Fehm gloves Lightning byte=98 -> 11, not 12).
    -- Test: spec/System/TestItemTools_spec.lua
    --   "no epsilon: Fehm gloves Lightning (10-14)% byte=98 truncates 11.922 -> 11"
    -- Verified vs in-game tooltip (the game interpolates in float32 and TRUNCATES;
    -- there is NO round-up epsilon -- the old +0.1 was removed and stays removed):
    --   Fehm gloves Lightning (10-14)% byte=98 → 11 (LE=11, 11.922 truncates to 11)
    --   Omnis Void (1-45)% byte=238 → 42 (LE=42; double reduction gave 43.0 → 43, the
    --     float32 path lands 42.9999 → 42). This is the boundary flip this port fixes.
    --   <private build> Void (61-75)% byte=93 scalar=1.5 → 99 (LE=99, was 100)
    --   <private build> Cursed Coin Phys (13-40)% byte=79 scalar=1.17 → 25 (LE=25)
    local gm, scale
    if modType ~= 0 then
        gm, scale = 1, 100          -- INCREASED / MORE / QUOTIENT: forced Hundredth
    elseif rounding == 1 then
        gm, scale = 1, 1            -- Integer
    elseif rounding == 2 then
        gm, scale = 10, 10          -- Tenth
    elseif rounding == 3 then
        gm, scale = 1000, 1000      -- Thousandth
    else
        gm, scale = 1, 100          -- Hundredth (rounding == 0)
    end
    local c_int = banker_round(gm * minN)
    local d_int = banker_round(gm * maxN)
    -- float32 game-order evaluation (each toF32 rounds one intermediate product).
    local fscale = toF32(scale)
    local c   = toF32(c_int / fscale)
    local d   = toF32(toF32(d_int / fscale) + toF32(1.0 / fscale))
    local bf  = toF32(roll / toF32(255.0))
    local raw = toF32(toF32(toF32(toF32(d - c) * bf) + c) * fscale)
    -- signed truncate toward zero (C# Math.Truncate), then back to display units.
    local v
    if raw >= 0 then v = m_floor(raw) else v = -m_floor(-raw) end
    v = v / gm
    local dmax = d_int / gm
    if v > dmax then v = dmax end
    return v
end

-- Map ItemClass.type -> slotOverrides key (tunklab-style slug). Returns nil
-- for types without a distinct slot-variant table (e.g. Weapon, Idol).
local typeToSlotKey = {
    ["Helmet"]             = "helmet",
    ["Body Armor"]         = "body_armor",
    ["Belt"]               = "belt",
    ["Boots"]              = "boots",
    ["Gloves"]             = "gloves",
    ["Amulet"]             = "amulet",
    ["Ring"]               = "ring",
    ["Relic"]              = "relic",
    ["Shield"]             = "shield",
    ["Off-Hand Catalyst"]  = "catalyst",
}
function itemLib.slotKeyForType(itemType)
    return typeToSlotKey[itemType]
end

-- Pick the mod-line array that matches the item's slot. Falls back to the
-- default mod table when no override is defined.
function itemLib.modLinesForSlot(mod, slotKey)
    if slotKey and mod.slotOverrides and mod.slotOverrides[slotKey] then
        return mod.slotOverrides[slotKey]
    end
    return mod
end

-- @leb-regression-guard:item-tooltip-source-colour
-- Colours a mod line by its SOURCE, mirroring LE's own per-line priority
-- (TooltipContentBuilder.GetItemModifierIconForAffix, which the game applies as the
-- row's icon tint). The ORDER is load-bearing and is not a preference:
--
--   * The legendary test precedes the exalted test, so a Legendary item's affixes are
--     crimson even at T7. In-game evidence (2026-07-16): Suloron's Step, an LP-crafted
--     Legendary — "+16 Strength" (T7) and "32% Increased Cooldown Recovery Speed" (T7)
--     both render crimson, NOT exalted purple. Contrast The Last Bear's Fury Reforged,
--     a Set item, where the same T7 "+16 Strength" renders purple. That difference is
--     only explicable by item-rarity-before-tier, and it matches the game's own order.
--   * Legendary is gated on `affixType` (rolled affixes only) because on that same
--     Suloron's Step the unique's own mods ("+95% Melee Critical Strike Multiplier"
--     etc.) render WHITE, not crimson.
--
-- White (NORMAL) is the correct default, not a fallback: the game never wraps implicit,
-- unique-inherent, or normal-tier affix text in a colour at all (GetItemImplicitInfo /
-- GetUniqueModifierInfoFromMod / GetItemSingleAffixInfo all leave ModifierColor unset),
-- so those lines take the default text colour.
--
-- Exalted is `tier >= 5` on the 0-indexed tier, matching ItemAffix.get_IsExalted
-- (`affixTier + 1 > 5`, i.e. display T6/T7). T5 is the max craftable tier.
--
-- TWO INDEPENDENT AXES, do not conflate them (they are separate fields on LE's ItemAffix,
-- and GetSealedAffixType() takes no specialAffixType argument):
--   * `modLine.kind` ≡ LE `SealedAffixType` — HOW the affix was sealed.
--     None=0 (nil here) / Regular=1 ("sealed") / Primordial=2 / FromCorruption=3
--     ("corrupted"). Item.lua:115-117 states the same equivalence.
--   * `modLine.specialAffixType` ≡ LE `AffixList.SpecialAffixType` — which POOL it came
--     from. 0=Standard, 1=Experimental, 2=Personal, 3=Set(Reforged), 4=IdolEnchantment,
--     5=IdolWeaver, 6=Corrupted(corruption-exclusive).
-- `kind == "corrupted"` (sealed BY corruption, purple box #A872DE) and
-- `specialAffixType == 6` (drawn from the corruption-only pool, #E6ADFF) are DIFFERENT
-- facts with DIFFERENT colours. An affix can be either, both, or neither.
--
-- Not modelled here because the game decides them per-ITEM or on a separate path:
-- set bonuses (rendered by ItemsTab directly) and the corrupted item marker.
--
-- Depends on @leb-regression-guard:idol-special-affix-type-is-integer — every `sat ==`
-- test below is dead on idols while idol affixes are string-tagged.
-- Spec: spec/System/TestItemTooltipSourceColour_spec.lua
local function sourceColorCode(modLine, item)
	local sat = modLine.specialAffixType
	if modLine.custom then
		-- LEB-only concept (user-authored mod); no in-game analogue.
		return colorCodes.CUSTOM
	end
	-- --- sealed axis first, exactly as the game orders it ---
	if modLine.kind == "primordial" then
		return colorCodes.PRIMORDIAL        -- .Primordial (9)
	end
	if modLine.kind == "corrupted" then
		return colorCodes.SEALEDCORRUPTED   -- .Corrupted (10) — sealed FROM corruption
	end
	-- --- item rarity beats every remaining per-affix fact ---
	if item and item.rarity == "LEGENDARY" and modLine.affixType then
		return colorCodes.LEGENDARY         -- .Legendary (12)
	end
	-- --- affix pool ---
	if sat == 3 then
		return colorCodes.SET               -- .ReforgedSet (14)
	end
	if sat == 4 or sat == 5 then
		-- IdolEnchantment / IdolWeaver — both tint #35C8C8 in-game.
		-- MUST precede the exalted test: idol enchantments tier up to T7, so a
		-- `tier >= 5` test placed first would paint them EXALTED purple. In-game
		-- evidence (2026-07-16): a Weaver's Touch idol's "+13 Ward Decay Threshold" /
		-- "+18 Ward gained when you use Evade" ("Tier: 4 (enchantment only)") are CYAN.
		-- NOTE this reads `specialAffixType`, NOT `modLine.enchant` — the latter comes
		-- only from a `{enchant}` raw-text tag, which appears ZERO times in
		-- ModItem_*.json / ModIdol_*.json and so can never be set by an affix roll.
		return colorCodes.IDOL
	end
	if sat == 6 then
		return colorCodes.CORRUPTEDAFFIX    -- corruption-exclusive pool
	end
	if modLine.tier and modLine.tier >= 5 then
		return colorCodes.EXALTED           -- .Exalted (11) — T6/T7
	end
	if modLine.kind == "sealed" then
		return colorCodes.SEALED            -- .Sealed (8) — plain sealed
	end
	return colorCodes.NORMAL
end

-- @leb-regression-guard:unique-tooltip-entries-display-order
-- The game renders a unique's tooltip from its `tooltipEntries`, NOT from `mods[]` order:
-- entry <128 -> mods[entry], entry >=128 -> tooltipDescriptions[entry-128]. Mods flagged
-- hideInTooltip are never in tooltipEntries; they are folded into a description line, and
-- one description can cover SEVERAL mods (Hollow Finger folds player+minion resistances
-- into one line each). So LEB's mods[] order is NOT the display order and its row count is
-- NOT the game's line count (Exsanguinous: 6 rows -> 4 lines).
-- INVARIANT: `mods[]` is the MECHANICS carrier (ModParser input) and must never be
-- reordered or rewritten for display -- 464 of the 699 rows LEB marks NOT SUPPORTED still
-- emit real modDB mods. This layer is ADDITIVE: it only chooses which modLine to show and
-- in what order, so the computed modDB is untouched by construction.
-- Do NOT permute item.explicitModLines in place instead: ItemsTabCraft seeds
-- craftUniqueRanges[i] from explicitModLines[i] and reads it back when rebuilding, so an
-- in-place reorder desyncs the craft roll sliders.
-- Only items whose LEB-row <-> game-mod correspondence RESOLVED carry tooltipEntries;
-- absent = fall back to mods[] order. "Resolved" means matched structurally against the
-- game data (property/type/tags/value signature), NOT confirmed in-game: only Exsanguinous
-- (11) and Shattered Worlds (413) were read off screenshots. Do not let either the code or
-- the tooltip imply the other 428 are in-game-verified.
-- Test: spec/System/TestUniqueTooltipEntriesOrder_spec.lua
-- Establishing commit: <see git log>
function itemLib.buildUniqueTooltipPlan(modLines, uniqueData)
	if not uniqueData or not uniqueData.tooltipEntries or not uniqueData.mods then
		return nil
	end
	local uniqueLines = {}
	for _, modLine in ipairs(modLines) do
		if modLine.uniqueInherent then
			t_insert(uniqueLines, modLine)
		end
	end
	-- The k-th uniqueInherent line is mods[k] (every producer inserts them in mods[] order).
	-- If that no longer holds, the plan's indices would point at the wrong lines, so bail
	-- out to the unordered fallback rather than render a confident lie.
	if #uniqueLines ~= #uniqueData.mods then
		return nil
	end
	local plan = { shownByIndex = {} }
	for _, entry in ipairs(uniqueData.tooltipEntries) do
		if entry < 128 then
			local modLine = uniqueLines[entry + 1]
			if not modLine then return nil end
			t_insert(plan, { modLine = modLine })
			plan.shownByIndex[entry + 1] = true
		else
			local desc = uniqueData.tooltipDescriptions and uniqueData.tooltipDescriptions[entry - 128 + 1]
			if not desc then return nil end
			t_insert(plan, { text = desc })
		end
	end
	-- Item-level unsupported note. A description line can cover several folded mods, and
	-- the desc->mod attribution is NOT derivable (413 of 560 descriptions carry no rollID
	-- placeholder; 284 of 533 folded mods map to no description), so a per-desc marker
	-- would have to be guessed. Worse, a folded line can be PARTIALLY supported, which a
	-- per-line marker cannot express at all. We therefore count the folded lines LEB
	-- cannot use and let the caller state it once, for the item.
	plan.foldedExtra, plan.foldedNotSupported = 0, 0
	for i, modLine in ipairs(uniqueLines) do
		if not plan.shownByIndex[i] then
			if modLine.extra then
				plan.foldedExtra = plan.foldedExtra + 1
			elseif modLine.notSupported then
				plan.foldedNotSupported = plan.foldedNotSupported + 1
			end
		end
	end
	return plan
end

function itemLib.formatModLine(modLine, dbMode, altarBoost, item)
    local displayScalar = modLine.displayValueScalar or modLine.valueScalar
    local line = (not dbMode and modLine.range and itemLib.applyRange(modLine.line, modLine.range, displayScalar, modLine.rounding, modLine.postRoundScalar, modLine.postRoundFloor)) or modLine.line
    if line:match("^%+?0%%? ") or (line:match(" %+?0%%? ") and not line:match("0 to [1-9]")) or line:match(" 0%-0 ") or line:match(" 0 to 0 ") then
        -- Hack to hide 0-value modifiers
        return
    end
    local colorCode = sourceColorCode(modLine, item)
    -- @leb-regression-guard:item-tooltip-source-colour
    -- "LEB can't use this line" is signalled by a SUFFIX, not by painting the text red.
    -- The text colour now carries the line's SOURCE (see sourceColorCode), and red text
    -- would both destroy that signal and collide with LEGENDARY crimson (^xE80B58 vs the
    -- old UNSUPPORTED ^xF05050). Both states get the same suffix because they mean the
    -- same thing to someone reading a build: the line contributes nothing.
    --   * `extra`        -- parse residue: LEB does not understand the line.
    --   * `notSupported` -- nsList: recognised, deliberately not modelled yet.
    -- A line that is not a modifier at all (display-only tooltip text, e.g. "20 Maximum
    -- Stacks of Ambition") parses to zero mods with NO residue, so it lands in neither
    -- branch and is correctly left unmarked. See ModParser's displayOnlyModList.
    if modLine.extra and launch.devModeAlt then
        line = line .. "   ^1'" .. modLine.extra .. "'"
    end
    if modLine.extra or modLine.notSupported then
        -- @leb-regression-guard:unsupported-note-own-line
        -- Put the "(NOT SUPPORTED IN LEB YET)" note on its OWN line (\n), not appended with
        -- spaces. Tooltip:AddLine splits on \n before width-wrapping, so a long mod line (e.g.
        -- "16 Minions teleported around you after you use a Traversal Skill") no longer wraps
        -- THROUGH the note ("(NOT SUPPORTED" / "IN LEB YET)"); the note sits cleanly below.
        -- The note keeps its own UNSUPPORTED colour; the mod text keeps its source colour.
        line = line .. "\n" .. colorCodes.UNSUPPORTED .. "(NOT SUPPORTED IN LEB YET)"
    end
    if altarBoost and altarBoost > 0 and not dbMode and modLine.range then
        -- @leb-regression-guard: two-phase-floor-post-round-scalar
        -- Pass altar boost via postRoundScalar (two-phase floor) rather than
        -- folding into valueScalar, so the tooltip preview matches LE's
        -- post-rounding behaviour (e.g. base +9 × 1.22 → +10, not +11).
        local boostedPostRound = (modLine.postRoundScalar or 1) * (1 + altarBoost)
        local boostedLine = itemLib.applyRange(modLine.line, modLine.range, displayScalar, modLine.rounding, boostedPostRound)
        if boostedLine ~= line then
            line = line .. "  (-> " .. boostedLine .. " with Altar)"
        end
    end
    return colorCode .. line
end

itemLib.wiki = {
    key = "F1",
    openGem = function(gemData)
        local name
        if gemData.name then
            -- skill
            name = gemData.name
            if gemData.tags.support then
                name = name .. " Support"
            end
        else
            -- grantedEffect from item/passive
            name = gemData;
        end

        itemLib.wiki.open(name)
    end,
    openItem = function(item)
        local name = item.rarity == "UNIQUE" and item.title or item.baseName

        itemLib.wiki.open(name)
    end,
    open = function(name)
        OpenURL("https://www.lastepochtools.com/db/search?query=" .. name)
        itemLib.wiki.triggered = true
    end,
    matchesKey = function(key)
        return key == itemLib.wiki.key
    end,
    triggered = false
}
