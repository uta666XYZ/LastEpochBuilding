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
-- Establishing commit: 73d6a712c
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
function itemLib.applyRange(line, range, valueScalar, rounding)
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
    if line:find("%%") and precision >= 100 then
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

    -- @leb-regression-guard: per-set-fractional-precision
    -- "per Complete Set" affixes are multiplied by CompleteSetCount in LE
    -- AFTER per-source quantization to HALF-INTEGER (0.5) steps, not after
    -- floor-to-integer. LEB historically rounded the per-item roll to int
    -- first (e.g. byte=41 +(2-5) Integer → floor(2.482)=2) then multiplied
    -- by the set multiplier (×3 → 6), losing the +1 that LE produces.
    -- Empirical match across two builds: precision=2 (half-step) + span+0.5:
    --   BxvJP3g1 byte=41,  ×3: numVal→2.5 → 7.5 → floor=7  (LE=7  ✓)
    --   Qqwv73q2 byte=203, ×6: numVal→4.5 → 27.0           (LE=27 ✓)
    -- ModStore:EvalMod applies m_floor after the Multiplier:CompleteSetCount
    -- tag (roundAfterMultiply) so the half-step value flows through intact.
    if line:find("per [Cc]omplete [Ss]et") and rounding == "Integer" then
        precision = 2
    end

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
                -- a previous attempt (f925695c5) special-cased these to ceil
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
                -- 25), affecting only `oN2zNnZM lv86 Bladedancer.xml`. The
                -- strict value 25 matches LE's in-game tooltip (vshDm direct port
                -- = IL2CPP `BaseStats.GetValueAfterRounding`).
                if line:find("%% Physical Resistance") then
                    -- precision/100 was already applied because of '%'; vshDm
                    -- always uses Hundredth precision for ADDED-Hundredth lines,
                    -- bypassing the bespoke (max-min) span / endpoint capping.
                    local v = itemLib.applyRangeStrict(minN, maxN, rollByte, valueScalar, 0, 0)
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
                -- Idol size scaling (valueScalar < 1.0, e.g. Humble=0.38, Stout=0.67)
                -- rounds endpoints FIRST to LE's display integers, then interpolates
                -- within the scaled span. Without this branch:
                --   AL07Kea4 Humble Weaver byte=221, scalar=0.38, "+(3-7) Vitality"
                --     interp-first: (3 + 221/255 × 5) × 0.38 = 2.79 → floor=2  (LE=3 ✗)
                --     scale-first : round(3×0.38)=1, round(7×0.38)=3
                --                   1 + 221/255 × (3-1+1) = 3.60 → floor=3   (LE=3 ✓)
                --   AL07Kea4 Humble Weaver byte=98:
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
                return (numVal < 0 and "" or plus) .. tostring(numVal)
            end)
               :gsub("%-(%d+%.?%d*%%) (%a+)", antonymFunc)
    -- Single-value scaling: affixes like "+5% Critical Strike Multiplier" have no
    -- (x-x) range, but still need valueScalar applied when the affix scales with
    -- the base (e.g. Class-Specific Idol enchants). Only applied when scalar != 1.
    if valueScalar ~= 1.0 and numbers == 0 then
        line = line:gsub("^(%+?)(%-?%d+%.?%d*)", function(plus, num)
            local v = roundHalfDownOnHalf(tonumber(num) * valueScalar)
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
-- Direct numeric port of LE planner JS `vshDm` ( = IL2CPP
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
-- Game behavior (verified against LE 1.4.6 IL2CPP dump RVA 0x230B940 +
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
    local e = roll / 255.0
    local c, d, v
    if modType ~= 0 then
        -- INCREASED / MORE / QUOTIENT: forced Hundredth + 0.001 epsilon.
        c = m_floor(100 * minN + 0.5) / 100
        d = m_floor(100 * maxN + 0.5) / 100
        v = m_floor(100 * ((d + 0.01 - c) * e + c + 0.001)) / 100
    elseif rounding == 1 then       -- Integer
        c = m_floor(minN + 0.5)
        d = m_floor(maxN + 0.5)
        v = m_floor((d + 1 - c) * e + c)
    elseif rounding == 2 then       -- Tenth
        c = m_floor(10 * minN + 0.5) / 10
        d = m_floor(10 * maxN + 0.5) / 10
        v = m_floor(10 * ((d + 0.1 - c) * e + c)) / 10
    elseif rounding == 3 then       -- Thousandth
        c = m_floor(1000 * minN + 0.5) / 1000
        d = m_floor(1000 * maxN + 0.5) / 1000
        v = m_floor(1000 * ((d + 0.001 - c) * e + c)) / 1000
    else                            -- Hundredth (rounding == 0)
        c = m_floor(100 * minN + 0.5) / 100
        d = m_floor(100 * maxN + 0.5) / 100
        v = m_floor(100 * ((d + 0.01 - c) * e + c + 0.001)) / 100
    end
    if v > d then v = d end
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

function itemLib.formatModLine(modLine, dbMode, altarBoost)
    local displayScalar = modLine.displayValueScalar or modLine.valueScalar
    local line = (not dbMode and modLine.range and itemLib.applyRange(modLine.line, modLine.range, displayScalar, modLine.rounding)) or modLine.line
    if line:match("^%+?0%%? ") or (line:match(" %+?0%%? ") and not line:match("0 to [1-9]")) or line:match(" 0%-0 ") or line:match(" 0 to 0 ") then
        -- Hack to hide 0-value modifiers
        return
    end
    local colorCode
    if modLine.extra then
        colorCode = colorCodes.UNSUPPORTED
        if launch.devModeAlt then
            line = line .. "   ^1'" .. modLine.extra .. "'"
        end
    else
        colorCode = (modLine.crafted and colorCodes.CRAFTED) or (modLine.custom and colorCodes.CUSTOM) or colorCodes.MAGIC
    end
    if modLine.notSupported and not modLine.extra then
        line = line .. "  " .. colorCodes.NORMAL .. "(NOT SUPPORTED IN LEB YET)"
    end
    if altarBoost and altarBoost > 0 and not dbMode and modLine.range then
        local boostedScalar = (modLine.valueScalar or 1) * (1 + altarBoost)
        local boostedLine = itemLib.applyRange(modLine.line, modLine.range, boostedScalar, modLine.rounding)
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