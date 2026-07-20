-- Last Epoch Building
--
-- Module: Global
-- Global constants
--

colorCodes = {
	NORMAL = "^xFFFFFF",
	MAGIC = "^x36A3E2",
	RARE = "^xE3D157",
	UNIQUE = "^xEB730A",
	EXALTED = "^xC184FF",
	LEGENDARY = "^xE80B58",
	SET = "^x71E87D",
	WWUNIQUE = "^xEB730A",
	WWLEGENDARY = "^xE80B58",
	IDOL = "^x36C8C8",
	CURRENCY = "^xAA9E82",
	CRAFTED = "^xB8DAF1",
	CUSTOM = "^x5CF0BB",
	-- Per-mod-line source colours, taken from the game's own tooltip assets so LEB's
	-- item tooltip reads like the in-game one. Values are the `_modifierIconSprites`
	-- tints in MasterItemTooltipAssetList (ItemTooltipModifierIconSprite indices),
	-- except CORRUPTEDAFFIX which is EpochColor[18] — what the affix-colour lookup
	-- returns for specialAffixType==6. See @leb-regression-guard:item-tooltip-source-colour.
	SEALED = "^x7C8992",          -- ItemTooltipModifierIconSprite.Sealed (8)
	SEALEDCORRUPTED = "^xA872DE", -- .Corrupted (10) — sealed-from-corruption
	PRIMORDIAL = "^xF0A534",      -- .Primordial (9)
	CORRUPTEDAFFIX = "^xE6ADFF",  -- corruption-exclusive affix pool
	SOURCE = "^x88FFFF",
	UNSUPPORTED = "^xF05050",
	WARNING = "^xFF9922",
	TIP = "^x80A080",
	PHYSICAL = "^xFCDFC0",
	FIRE = "^xEC4D29",
	COLD = "^x17BBEA",
	LIGHTNING = "^x286AFF",
	VOID = "^x7E1BC5",
	POISON = "^x1DA546",
	NECROTIC = "^x2DBF9C",
	POSITIVE = "^x33FF77",
	NEGATIVE = "^xDD0022",
	HIGHLIGHT ="^xFF0000",
	OFFENCE = "^xE07030",
	DEFENCE = "^x8080E0",
	MAINHAND = "^x50FF50",
	MAINHANDBG = "^x071907",
	OFFHAND = "^xB7B7FF",
	OFFHANDBG = "^x070719",

	VITALITY = "^xFFFD60",
	STRENGTH = "^xFF7B61",
	DEXTERITY = "^x9EFF76",
	INTELLIGENCE = "^x8EFFFF",
	ATTUNEMENT = "^xFD9CFF",

	-- Season-4 attributes are twins of a base attribute, so each uses a
	-- darker shade of its base's colour (Str/Dex/Int/Att/Vit) to read as the
	-- same family: Brutality~Strength, Guile~Dexterity, Madness~Intelligence,
	-- Apathy~Attunement, Rampancy~Vitality.
	BRUTALITY = "^xCC624D",
	MADNESS = "^x71CCCC",
	GUILE = "^x7ECC5E",
	APATHY = "^xCA7CCC",
	RAMPANCY = "^xCCCA4D",
}

colorCodes.LIFE = "^xE05030"
colorCodes.MANA = "^x7070FF"
colorCodes.ES = colorCodes.SOURCE
colorCodes.WARD = "^x90C8FF"
colorCodes.ENDURANCE = "^x71E87D"
colorCodes.ARMOUR = "^xFCDFC0"
colorCodes.EVASION = "^x9EFF76"
colorCodes.RAGE = colorCodes.WARNING
colorCodes.PHYS = colorCodes.NORMAL

defaultColorCodes = copyTable(colorCodes)
function updateColorCode(code, color)
 	if colorCodes[code] then
		colorCodes[code] = color:gsub("^0", "^")
		if code == "HIGHLIGHT" then
			rgbColor = hexToRGB(color)
		end
	end
end

function hexToRGB(hex)
	hex = hex:gsub("0x", "") -- Remove "0x" prefix
	hex = hex:gsub("#","") -- Remove '#' if present
	if #hex ~= 6 then
		return nil
	end
	local r = (tonumber(hex:sub(1, 2), 16)) / 255
	local g = (tonumber(hex:sub(3, 4), 16)) / 255
	local b = (tonumber(hex:sub(5, 6), 16)) / 255
	return {r, g, b}
end

-- @leb-regression-guard:damage-type-ingame-order
-- DamageTypes, DamageTypesColored and DamageTypeColors must stay aligned
-- index-for-index in the in-game resistance order: Fire, Lightning, Cold,
-- Physical, Poison, Necrotic, Void. Display/config sites zip DamageTypes[i]
-- with DamageTypeColors[i] (Build.lua max-hit/resist rows, Data.lua power
-- stats), so a reorder of one array without the others mis-colors and
-- mis-orders the Resists panel.
-- Test: spec/System/TestDamageTypeOrder_spec.lua "damage type arrays share in-game order"
DamageTypes = {
	"Fire",
	"Lightning",
	"Cold",
	"Physical",
	"Poison",
	"Necrotic",
	"Void"
}

Attributes = {"Vit","Str","Dex","Int","Att"}
-- @leb-regression-guard:minion-modifier-perstat-parent-actor
-- Set of primary-attribute stat names that, when referenced via a
-- PerStat tag on a MinionModifier mod, must resolve against the
-- player (minion.actor.parent) instead of the minion itself. LE
-- minions don't carry primary attributes of their own; tree-passive
-- text like "X% Y Per Vitality" reads the player's value. Includes
-- the Raw* variants used by intrinsic-bonus paths (see
-- s4-perstat-base-includes-converted-twin guard in ModStore.lua).
-- CalcPerform.lua's MinionModifier dispatch reads this table.
LE_MINION_PERSTAT_PARENT_ATTRS = {
    Vit = true, Str = true, Dex = true, Int = true, Att = true,
    RawVit = true, RawStr = true, RawDex = true, RawInt = true, RawAtt = true,
}
-- @leb-regression-guard:weapon-attack-minion-weapon-inheritance
-- Validation provenance is retained in maintainer notes.
LE_WEAPON_ATTACK_MINIONS = {
    RogueBallista = { weapon = "Bow" },
}
-- @leb-regression-guard:upheaval-totem-grant
-- Validation provenance is retained in maintainer notes.
LE_PLAYER_ADDED_FLAT_MINIONS = {
    UpheavalTotem = { skill = "Upheaval" },
}
-- @leb-regression-guard:minion-skill-redundant-attr-scaling
-- Validation provenance is retained in maintainer notes.
LE_MINION_SKILL_REDUNDANT_ATTR_SCALING = {
    ["Skeletal Mages Necrotic Projectile"] = { Int = true }, -- Dread Bolt; SummonMage already scales per Int
    ["Skeletal Mages Fire Projectile"] = { Int = true }, -- Fireball (sm4g-9 Pyromancer conversion); SummonMage already scales per Int
    -- @leb-regression-guard:falcon-diving-attack-redundant-attr-scaling
    ["RogueFalcon Diving Attack"] = { Dex = true, Int = true }, -- Aerial Assault; Falconry already scales per Dex, and the falcon has no Int scaling in-game
    -- @leb-regression-guard:spriggan-thornvolley-redundant-attr-scaling
    ["ThornVolley"] = { Att = true }, -- Thorn Volley; SummonSpriggan already scales per Attunement
    -- @leb-regression-guard:stormcrow-lightningblast-redundant-attr-scaling
    ["StormCrowLightningBlast"] = { Int = true }, -- Lightning Blast; PHANTOM (SummonStormCrow grants NO per-Int; the crow has no Int scaling in-game)
}
-- @leb-regression-guard:minion-default-skill-index
-- Validation provenance is retained in maintainer notes.
LE_MINION_DEFAULT_SKILL_INDEX = {
    SummonedAbomination = 2, -- index 1 = Devour (consume spell, 0 DPS); index 2 = Melee Attack (the real hit)
    -- @leb-regression-guard:falcon-default-skill-aerial-assault
    -- SummonedAbomination default. See REGRESSION_GUARDS.md "falcon-default-skill-aerial-assault".
    -- Validation provenance is retained in maintainer notes.
    RogueFalcon = 2,
}
LongAttributes = {"Vitality","Strength","Dexterity","Intelligence","Attunement"}
AttributesColored = {
    colorCodes.VITALITY.."Vitality",
    colorCodes.STRENGTH.."Strength",
    colorCodes.DEXTERITY.."Dexterity",
    colorCodes.INTELLIGENCE.."Intelligence",
    colorCodes.ATTUNEMENT.."Attunement"
}

DamageTypesColored = {
	colorCodes.FIRE.."Fire",
	colorCodes.LIGHTNING .. "Lightning",
	colorCodes.COLD .. "Cold",
	colorCodes.PHYSICAL.."Physical",
	colorCodes.POISON.."Poison",
	colorCodes.NECROTIC.."Necrotic",
	colorCodes.VOID.."Void"
}

DamageTypeColors = {
	colorCodes.FIRE,
	colorCodes.LIGHTNING,
	colorCodes.COLD,
	colorCodes.PHYSICAL,
	colorCodes.POISON,
	colorCodes.NECROTIC,
	colorCodes.VOID
}

DamageSourceTypes = { "Spell", "Melee", "Throwing", "Bow", "Dot"}
-- @leb-regression-guard:wielding-weapon-conditions
-- Mace must be in this list — Sentinel/Forge Guard affixes like "+N Melee
-- Physical Damage if wielding a Mace" (affixId 364 in single_affixes_v3)
-- and SkillStatMap Elusive crit gates (UsingMace neg) all depend on the
-- parser-side modTagList/modFlagList entries this loop generates plus the
-- corresponding `flag == "Mace"` branch in CalcSetup that publishes the
-- UsingMace condition.
DamageSourceWeapons = { "Wand", "Bow", "Axe", "Mace", "Sceptre", "Staff", "Dagger", "Sword" }

-- Active skill types
SkillType = {
	Physical = 1,
	Lightning = 2,
	Cold = 4,
	Fire = 8,
	Void = 16,
	Necrotic = 32,
	Poison = 64,
	Elemental = 128,
	Spell = 256,
	Melee = 512,
	Throwing = 1024,
	Bow = 2048,
	Dot = 4096,
	Minion = 8192,
	Totem = 16384,
	PetResisted = 32768,
	Potion = 65536,
	Buff = 131072,
	Channelling = 262144,
	Transform = 524288,
	LowLife = 1048576,
	HighLife = 2097152,
	FullLife = 4194304,
	Hit = 8388608,
	Curse = 16777216,
	Ailment = 33554432,
}

SkillType.Attack = SkillType.Melee + SkillType.Throwing + SkillType.Bow
SkillType.Cast = SkillType.Spell

-- TODO: Not supported yet
SkillType.Unsupported = SkillType.Ailment * 2
SkillType.Wand = SkillType.Unsupported
SkillType.Sword = SkillType.Unsupported
SkillType.Axe = SkillType.Unsupported
SkillType.Dagger = SkillType.Unsupported
SkillType.Mace = SkillType.Unsupported
-- @leb-regression-guard:sceptre-not-mace — LE sceptres are their own weapon
-- type (weaponTypeInfo flag "Sceptre"); same Unsupported bit keeps weapon-flag
-- matching byte-identical to the old flag="Mace" wiring.
SkillType.Sceptre = SkillType.Unsupported
SkillType.Staff = SkillType.Unsupported
SkillType.Unarmed = SkillType.Unsupported
SkillType.Weapon = SkillType.Unsupported
SkillType.Weapon1H = SkillType.Unsupported
SkillType.Weapon2H = SkillType.Unsupported
SkillType.WeaponRanged = SkillType.Unsupported
SkillType.WeaponMelee = SkillType.Unsupported
SkillType.WeaponMask = SkillType.Unsupported
SkillType.Ignite = SkillType.Unsupported
SkillType.Area = SkillType.Unsupported
SkillType.Projectile = SkillType.Unsupported

for _, damageType in ipairs(DamageTypes) do
	SkillType[damageType .. "Dot"] = SkillType.Unsupported
end

ModFlag = SkillType

KeywordFlag = copyTable(SkillType)

---The default behavior for KeywordFlags is to match *any* of the specified flags.
---Including the "MatchAll" flag when creating a mod will cause *all* flags to be matched rather than any.
KeywordFlag.MatchAll = SkillType.Unsupported * 2

-- Helper function to compare KeywordFlags
local band = bit.band
local MatchAllMask = bit.bnot(KeywordFlag.MatchAll)
---@param keywordFlags number The KeywordFlags to be compared to.
---@param modKeywordFlags number The KeywordFlags stored in the mod.
---@return boolean Whether the KeywordFlags in the mod are satisfied.
function MatchKeywordFlags(keywordFlags, modKeywordFlags)
	local matchAll = band(modKeywordFlags, KeywordFlag.MatchAll) ~= 0
	modKeywordFlags = band(modKeywordFlags, MatchAllMask)
	keywordFlags = band(keywordFlags, MatchAllMask)
	if matchAll then
		return band(keywordFlags, modKeywordFlags) == modKeywordFlags
	end
	return modKeywordFlags == 0 or band(keywordFlags, modKeywordFlags) ~= 0
end

GlobalCache = {
	cachedData = { MAIN = {}, CALCS = {}, CALCULATOR = {}, CACHE = {}, },
	deleteGroup = { },
	excludeFullDpsList = { },
	useFullDPS = false,
	numActiveSkillInFullDPS = 0
}

-- @leb-regression-guard:while-active-buff-tree-id-map (registry site)
-- Map of LE-skill treeId -> ModDB Condition name that gates "while active"
-- buff-tree contributions. A node under one of these treeIds only feeds
-- modDB while the matching Condition flag is set (mirrors LE's in-game
-- behaviour where Flame Ward / Form-style buffs grant their tree mods only
-- during the buff's active window). CalcSetup.lua reads this to scope tree
-- contributions; SkillsTab can read the same map to render toggles without
-- forking the source of truth. See CalcSetup.lua "buffSkillTreePrefixes".
LE_WHILE_ACTIVE_BUFF_BY_TREE_ID = {
	["fw3d"]   = "HaveFlameWard",        -- Flame Ward (Mage): 3s duration, FlameWardMutator
	["wb8fo"]  = "InWerebearForm",       -- Werebear Form (Druid)
	["sf5rd"]  = "InSprigganForm",       -- Spriggan Form (Druid)
	["sbf4m"]  = "InSwarmbladeForm",     -- Swarmblade Form (Druid)
	["rf1azz"] = "InReaperForm",         -- Reaper Form (Lich)
	["eb5656"] = "HaveEterrasBlessing",  -- Eterra's Blessing (Primalist): 4s duration cast buff
	["ds4d3"]  = "MinionsHaveDreadShade", -- Dread Shade (Necromancer): per-target minion buff (DreadShadeMutator)
}

-- @leb-regression-guard:tree-conversion-target-skill (registry site)
-- Map of LE-skill treeId -> the scope that a buff-tree's damage *conversion*
-- mods must be re-tagged with. Some buff trees advertise a conversion that,
-- in-game, applies ONLY to a specific skill (the granted DoT, or the form's
-- own attacks) rather than to every damaging skill the player has. Because
-- active buff-tree nodes are added with SkillId tags STRIPPED (so the buff's
-- defensive/utility mods apply globally — calcs.buildModListForNodeList with
-- stripSkillId), their conversion mods would otherwise leak to every skill of
-- the source type. CalcSetup.lua "applyBuffPrefix" re-tags ONLY the conversion
-- mods so the conversion lands on the intended skill's cfg alone (and, being
-- skill-scoped, converts that skill's intrinsic BASE only — typed added keeps
-- its type, per @leb-regression-guard:conversion-base-only-scope).
--
-- Value forms:
--   * <string>  -> a SkillName tag for that exact active-skill name. Used when
--     the conversion belongs to ONE granted/triggered skill. Example: Flame
--     Ward fw3d-6 "Frost Ward" (" Fire -> Cold") "globally converts {Fire Aura}
--     to cold" -> the granted Fire Aura DoT only
--     (datamined game source FireAuraMutator.coldConversionFromFlameWard).
--   * true      -> a SkillId tag carrying THIS buff group's own grantedEffect.id.
--     Used for FORM / transform trees whose conversion node scopes (per its game
--     description) to the form's attack(s) and their BASE damage. The SkillId tag
--     matches the form skill itself AND every sub-ability the form GRANTS (via
--     cfg.groupSource = "SkillId:<form id>", ModStore.lua), so it covers e.g.
--     Werebear's Maul/Rampage or Spriggan Form's Spirit Thorns/Thorn Shield
--     without enumerating them. This RESTORES exactly the SkillId scope that
--     ProcessStats originally set (skillId = the tree's own skill) and that the
--     buff-strip path removed -- defensive mods stay global, conversions do not.
--     Game descriptions (TreeData/1_4):
--       wb8fo-26 "Bringer of Storms": "Maul and Rampage's base physical damage
--         is converted to lightning."
--       sbf4m-10 (Swarmblade Form): "The base damage of Swarm Strike, Locust
--         Swarm, and Dive is converted to cold..."
--       sf5rd-34 (Spriggan Form): "Spirit Thorns, Summon Vines and Thorn
--         Shield's base physical damage is converted to cold."
--       ds34l-32 (Death Seal): "The Wave of Death's base damage is converted to
--         cold." (Death Seal carries the SkillType.Buff bit -> buff-bucketed.)
--       rf1azz-12 (Reaper Form): "<Reaper's> base necrotic damage -> physical."
-- DELIBERATELY ABSENT: si4lgl-30 (Symbols of Hope "Fire Damage -> Void"). That
-- is a genuine player-GLOBAL aura conversion (converts ALL damage of the type,
-- incl. typed added) -- validated in-game on VK Symbols-of-Hope builds
-- (@leb-regression-guard:global-conversion-converts-added-offtype). It MUST stay
-- untagged/global; do not add it here. The discriminator is the game text: a
-- "<specific skill>'s base damage is converted" node is scoped; a blanket aura
-- "<Type> Damage -> <Type>" is global.
-- See CalcSetup.lua "applyBuffPrefix" and REGRESSION_GUARDS.md
-- "tree-conversion-target-skill".
LE_TREE_CONVERSION_TARGET_SKILL = {
	["fw3d"]   = "Fire Aura",  -- Flame Ward "Frost Ward" globally converts the granted Fire Aura DoT to cold
	["wb8fo"]  = true,         -- Werebear Form: wb8fo-26 phys -> lightning, scoped to the form's attacks (Maul/Rampage)
	["sbf4m"]  = true,         -- Swarmblade Form: sbf4m-10 phys/poison -> cold, scoped to the form's attacks
	["sf5rd"]  = true,         -- Spriggan Form: sf5rd-34 phys -> cold, scoped to the form's attacks (Spirit Thorns/Thorn Shield/Summon Vines)
	["ds34l"]  = true,         -- Death Seal: ds34l-32 necrotic -> cold, scoped to Wave of Death
	["rf1azz"] = true,         -- Reaper Form: rf1azz-12 necrotic -> physical, scoped to the form's attacks
}

-- @leb-regression-guard:tree-node-grants-skill (registry site)
-- Map of skill-tree NODE id -> data.skills KEY for a continuous DoT/aura skill
-- GRANTED by allocating that node (an ExtraSkill grant, source "Tree:<nodeId>").
-- LEB already creates an active-skill group for such grants
-- (CalcSetup.prepareTrees -> node.grantedSkills -> env.grantedSkillsNodes ->
-- the env.grantedSkills group loop), but tree grants never set includeInFullDPS,
-- so calcFullDPS ignored their damage. This registry marks the grants whose DoT
-- contributes to sustained damage; CalcSetup sets group.includeInFullDPS=true
-- for them. Modeled at 100% uptime (continuous aura). No explicit buff gate is
-- needed: the grant is present in env.grantedSkills only while its parent
-- while-active buff is active (e.g. fw3d-12 only when Flame Ward is on).
--
-- fw3d-12 "Fire Aura" (Flame Ward tree): "Each second ... chance to cast a
-- {Fire Aura}" (TreeData/1_4/tree_1.json). The Fire Aura DoT carries
-- spell_base_fire_damage=14 / damageEffectiveness=0.7 (skills.json), is
-- converted to cold by fw3d-6 (LE_TREE_CONVERSION_TARGET_SKILL), and scaled by
-- SkillName="Fire Aura"-tagged idol/passive mods (~794 DoT/s in-game while
-- Flame Ward active, ~93.8% cold).
LE_TREE_NODE_GRANTS_SKILL = {
	["fw3d-12"] = "FireAura",  -- Flame Ward "Fire Aura" node grants the triggered Fire Aura DoT
}

-- @leb-regression-guard:tree-node-defensive-hit-damage (registry site)
-- Map of skill-tree NODE id -> list of { pat, repl } stat-string rewrites applied
-- (case-as-written, before rank scaling) in PassiveTree:ProcessStats.
--
-- Why this exists: a handful of LE tree nodes carry the stat string
-- "X% Less Hit Damage" whose IN-GAME meaning is DEFENSIVE — the player TAKES
-- less damage from hits — but the bare string is indistinguishable from the
-- ~90 OFFENSIVE "hit damage" nodes ("<skill> hits deal less/more damage").
-- ModParser parses the bare string as % less + ModFlag.Hit + "Damage" = an
-- OFFENSIVE -X% hit damage DEALT, which wrongly cuts the player's own DPS.
-- The disambiguator lives only in the node DESCRIPTION, so we re-express the
-- stat as "less hit damage taken" (-> ModParser LESS + ModFlag.Hit +
-- "DamageTaken" = a mitigation mod) for the specific nodes confirmed defensive.
--
-- fw3d-18 "Barrier" (Flame Ward tree, maxPoints 5, per-point "8% Less Hit
-- Damage"): description (TreeData/1_4/tree_1.json) = "You take less damage from
-- hits while Flame Ward is active (multiplicative with other modifiers)." Gated
-- behind the Flame Ward while-active buff (LE_WHILE_ACTIVE_BUFF_BY_TREE_ID
-- "fw3d"), so before this fix ticking "Flame Ward active" applied -40% (8%x5) to
-- the player's outgoing DPS. NOTE: keep this node-scoped — e.g. mush9-6 "Point
-- Blank" also has the words "less hit damage" but is OFFENSIVE ("Multishot
-- deals less hit damage as it travels"), so a blanket string rule is wrong.
-- The $-anchored pattern tolerates LE re-tuning the per-point value; the spec
-- (TestFlameWardBarrierDefensive_spec.lua) pins the live tree-data wiring so a
-- stat-string rename surfaces as a failure rather than a silent revert.
LE_TREE_NODE_STAT_REWRITE = {
	["fw3d-18"] = {
		{ pat = "[Ll]ess [Hh]it [Dd]amage$", repl = "less hit damage taken" },
	},
	-- @leb-regression-guard:ballista-agile-engineering-attack-speed-inc
	-- Validation provenance is retained in maintainer notes.
	["ba1574-18"] = {
		{ pat = "^%+([%d%.]+)%% Attack Speed per 5 Dexterity$", repl = "%1%% increased attack speed per 5 dexterity" },
	},
	-- @leb-regression-guard:raptor-execute-missing-health-more (rewrite site)
	-- Spec: spec/System/TestRaptorExecuteMissingHealth_spec.lua. See REGRESSION_GUARDS.md.
	-- Validation provenance is retained in maintainer notes.
	["srtor-20"] = {
		{ pat = "^%+([%d%.]+)%% Damage per 1%% Missing Health$", repl = "%1%% raptor damage per 1%% missing health" },
	},
	-- @leb-regression-guard:symbols-empowering-inc-per-symbol (rewrite site)
	-- Spec: spec/System/TestSymbolsOfHope_spec.lua. See REGRESSION_GUARDS.md.
	-- Validation provenance is retained in maintainer notes.
	["si4lgl-32"] = {
		{ pat = "^%+([%d%.]+)%% Damage Granted Per Active Symbol$", repl = "%1%% increased damage per active symbol" },
	},
	-- @leb-regression-guard:flame-reave-rhythm-consume (rewrite site)
	-- normal (4guanghuan capture 20260707_140512_03). See REGRESSION_GUARDS.md.
	-- Validation provenance is retained in maintainer notes.
	["fr11mv-3"] = {
		{ pat = "^%+130%% Damage when consuming 12 stacks$", repl = "+130%% Damage when consuming Rhythm of Fire" },
	},
	-- @leb-regression-guard:erasing-strike-conditional-melee (rewrite site)
	-- Spec: spec/System/TestErasingStrikeConditionalMelee_spec.lua. See REGRESSION_GUARDS.md.
	-- Validation provenance is retained in maintainer notes.
	["es6ai-26"] = {
		{ pat = "^%+(%d+)%% Melee Damage vs 12 stacks of Time Rot$", repl = "%1%% more melee damage against time rotting enemies" },
	},
	["es6ai-15"] = {
		{ pat = "^%+(%d+)%% Melee Damage to Slowed$", repl = "%1%% more melee damage to slowed enemies" },
	},
	-- @leb-regression-guard:erasing-strike-merciful-damaged (rewrite site)
	-- Erasing Strike Merciful (es6ai-9, maxPoints 4). Raw per-point stats:
	--   "+15% Cooldown Recovery Speed"  and  "+5% Melee Damage vs Damaged Enemies"
	-- The CDR line parses fine; the second line's "vs Damaged Enemies" condition clause
	-- leaves parse residue -> PassiveTree:ProcessStats drops the whole mod -> the melee
	-- bonus silently contributes NOTHING (same residue-drop class as the es6ai-26/15
	-- siblings above). Like those two, the in-game node tooltip (screenshot 2/4 pts,
	-- +10%) reads: "Erasing Strike has increased cooldown recovery speed and deals MORE
	-- melee damage to enemies that are already damaged (multiplicative with other
	-- modifiers)." => model as a MORE (multiplicative) mod, NOT increased. Re-express to
	-- "N% more melee damage against damaged enemies": ModParser:32 (`^([%+%-]?[%d%.]+)%%
	-- more`) parses it to Damage MORE + melee keywordFlag + the enemy ActorCondition
	-- {FullLife, neg=true} registered by the "against damaged enemies" phrase (ModParser,
	-- same guard). "damaged" = NOT full life. Applied on the raw per-point string BEFORE
	-- rank scaling; the captured leading value (5) is multiplied by node alloc afterward
	-- (2 pts -> +10% MORE, 4 pts -> +20% MORE). NOT corpus-neutral: conditionEnemyFullLife
	-- defaults OFF => enemy is not full life by default => neg-FullLife is TRUE => the MORE
	-- applies by default (intentional; LEB "most combat occurs below full life" realistic-
	-- sustained-DPS convention). Merciful has NO weapon gate (unlike Obliteration), so
	-- EVERY build that allocates es6ai-9 gains the bonus and was snapshot-regen'd.
	-- Spec: spec/System/TestErasingStrikeMerciful_spec.lua. See REGRESSION_GUARDS.md.
	["es6ai-9"] = {
		{ pat = "^%+(%d+)%% Melee Damage vs Damaged Enemies$", repl = "%1%% more melee damage against damaged enemies" },
	},
	-- NOTE: Erasing Strike Ruthless (es6ai-10, "+25% Melee Damage Vs Full Health Enemies")
	-- previously had a rewrite entry here to escape a residue-drop. That rewrite is now a
	-- semantic NO-OP and was RETIRED: <see git log> added the "vs full health enemies" word-order
	-- key to ModParser (@leb-regression-guard:enemy-full-health-alt-order), so the RAW line
	-- already parses residue-free to Damage MORE + Melee keywordFlag (512) + a NON-negated
	-- enemy ActorCondition{FullLife} -- byte-identical to what the rewrite produced. The
	-- invariant (raw line -> MORE, not INCREASED; Melee kept; non-neg enemy FullLife) now
	-- lives in spec/System/TestEnemyFullHealthAltOrder_spec.lua under that guard. Bare "+N%"
	-- maps to BASE_MORE (@leb-regression-guard:bare-form-damage-affix-increased, ModParser:56),
	-- so this is MORE by construction. CORPUS-NEUTRAL: no corpus build allocates es6ai-10, and
	-- conditionEnemyFullLife defaults OFF (non-neg FullLife FALSE) => inert regardless.
	-- @leb-regression-guard:erasing-strike-obliteration-2h-double (rewrite site)
	-- Erasing Strike Obliteration (es6ai-16, maxPoints 5). Raw per-point stats:
	--   "+10% Damage"  and  " Doubled with a 2h Weapon"
	-- The node is "+X% MORE Damage, DOUBLED while wielding a 2h weapon" (bare "+X%
	-- Damage" parses to Damage MORE; the "Doubled with a 2h Weapon" clause is its own
	-- stat line and was residue-DROPPED, so LEB applied the un-doubled +50% MORE (x1.50
	-- at 5 pts) to every build -- undercounting 2h builds, which should get +100% MORE
	-- (x2.00). Modelling the doubling as a SECOND +50% MORE would be WRONG: two MORE
	-- mods multiply (1.5*1.5=2.25), not add. Instead split into two MUTUALLY EXCLUSIVE
	-- weapon-gated MORE mods so exactly one applies:
	--   NOT 2h -> "+10% Damage while not wielding a two handed weapon" (x5 -> +50% MORE =
	--             x1.50, unchanged; covers 1h AND weaponless/unclassified builds)
	--   2h     -> "+20% Damage with 2h weapon"  (x5 -> +100% MORE = x2.00, doubled)
	-- The base is gated on NEG-2h (not "with 1h weapon") so a build where neither 1h nor 2h
	-- fires still keeps the base +50% -- gating the base on "1h" regressed YsBonkVK_S2 (a
	-- weaponless ES snapshot) to x0.91 by dropping Obliteration entirely. Condition is
	-- GEAR-deterministic (UsingTwoHandedWeapon, auto-detected) -- NOT a config, so this is
	-- NOT corpus-neutral: 2h Erasing Strike builds gain the doubling and were snapshot-
	-- regen'd (5: <private build> x1.33, VoidCleaver x1.33, BakEPgze x1.23, YsFckAFKKick x1.17,
	-- YsAberrothKiller x1.09); 1h/weaponless unchanged. The negated phrase is registered in
	-- ModParser (same guard). Per-point values are hardcoded (the doubling
	-- has to double the value, which a %-capture cannot do): if LE re-tunes Obliteration's
	-- "+10%", the pattern stops matching and the spec surfaces it (manifest-armor
	-- exact-value precedent). Rank scaling multiplies the leading value afterward; the
	-- "2h" hand token is protected by tree-rank-scale-skip-weapon-hand-token.
	-- Spec: spec/System/TestErasingStrikeObliteration2h_spec.lua. See REGRESSION_GUARDS.md.
	["es6ai-16"] = {
		{ pat = "^%+10%% Damage$", repl = "+10%% Damage while not wielding a two handed weapon" },
		{ pat = "^ Doubled with a 2h Weapon$", repl = "+20%% Damage with 2h weapon" },
	},
	-- @leb-regression-guard:manifest-armor-redistributed-steel-7pct (rewrite site)
	-- Spec: spec/System/TestManifestArmorGearChannel_spec.lua. See REGRESSION_GUARDS.md.
	-- Validation provenance is retained in maintainer notes.
	["ma6hdr-25"] = {
		{ pat = "^%+15%% Damage$", repl = "7%% more Damage" },
	},
	-- @leb-regression-guard:manifest-armor-weapon-stats-copy (Platemail phantom site)
	-- Platemail (ma6hdr-1, maxPoints 4) "+40% Stats From Armor" means "Manifested
	-- Armor gains increased effect of stats copied from your BODY ARMOR" (node desc;
	-- ManifestArmorMutator.GetArmourStats GetValueMultiplier chest branch). It is a
	-- SCALAR on the armor-slot stat-copy channel, NOT a stat itself. ModCache parses
	-- the bare string as `Armour BASE 40` -> a phantom +160 flat armor on the minion
	-- at rank 4. Blank the line (empty-line skip machinery) until the armor-slot
	-- stat-copy channel (phase 2) consumes the scalar. The weapon-slot copy landed
	-- first (see CalcPerform manifest-armor-weapon-stats-copy) because the weapon
	-- slot takes NO Platemail scaling (engine GetValueMultiplier weapon branch =
	-- 1 + increasedGearStats only, measured x1.0 exact: addedMH=113 = the raw
	-- Bone Scythe implicit on VoidMaster 20260705).
	["ma6hdr-1"] = {
		{ pat = "^%+40%% Stats From Armor$", repl = "" },
	},
	-- @leb-regression-guard:singular-purpose-low-block-double (rewrite site)
	-- Validation provenance is retained in maintainer notes.
	["Sentinel-61"] = {
		{ pat = "^2%% More Void Damage$", repl = "" },
	},
	-- @leb-regression-guard:call-to-arms-increased-not-more (rewrite site)
	-- "Call To Arms" (ah443-10, Holy Aura tree, Paladin) grants PLAYER+ally
	-- physical damage. The LE->LEB extraction dropped the "increased" keyword: the
	-- node stat is the bare "+10% Physical Damage", which ModParser parses as a
	-- MULTIPLICATIVE PhysicalDamage MORE (the standard LEB default for a bare
	-- "+N% <Type> Damage" string -- correctly so for the ~45 nodes whose
	-- description says "more"/"multiplicative"). But ah443-10's description is
	-- unambiguous: "Holy Aura grants you and your allies INCREASED physical
	-- damage." So it must be additive INC, not MORE. Rewrite the bare stat to
	-- "+N% increased Physical Damage" so it parses to PhysicalDamage INC.
	-- Node-scoped (NOT a global bare->INC change) so the 45 genuinely-MORE nodes
	-- are untouched. Value-tolerant ($-anchored on "Physical Damage"; the leading
	-- per-point % rank-scales as before). Affects ~5 corpus Paladin builds with
	-- Call To Arms (<private build>, <private build>, <private build>, YsSupportCentre, 1.3 throwing) --
	-- MORE x1.5 (5/5) -> INC +50% (diluted) REDUCES their physical damage (corrects
	-- an over-count). Sibling node ah443-11 "Strength From Afar" is already correct
	-- ("+12% Throwing Attack Damage" parses to Damage INC). See REGRESSION_GUARDS.md.
	["ah443-10"] = {
		{ pat = "([Pp]hysical [Dd]amage)$", repl = "increased %1" },
	},
	-- @leb-regression-guard:abomination-pertype-more (rewrite site)
	-- Sharpened Bones (aa710-2, Assemble Abomination tree). Its first stat line is a
	-- COMPOUND "+2% Melee Damage and Health per Skeleton Warrior" -- the generic parser
	-- only consumes "Melee Damage" and leaves "and Health per Skeleton Warrior" as
	-- residue, so PassiveTree (which drops any mod with non-empty `extra`) would discard
	-- the whole line. Rewrite it to a single Damage-only line so it parses cleanly and the
	-- "per skeleton warrior" modTagList tag (ModParser, same guard) attaches. The Health
	-- half (a defensive minion stat) is intentionally dropped -- only the damage MORE is
	-- modeled. $-anchored on the suffix; value-tolerant ("%d+" preserves the leading %).
	-- The Rogue attack-speed / Archer area lines in this node stay untouched (secondary;
	-- their "per skeleton rogue/archer" tags still let them parse, but only count configs
	-- exist for them). See REGRESSION_GUARDS.md "abomination-pertype-more".
	["aa710-2"] = {
		{ pat = "[Mm]elee [Dd]amage and [Hh]ealth per [Ss]keleton [Ww]arrior$", repl = "Melee Damage per Skeleton Warrior" },
	},
	-- @leb-regression-guard:chthonic-fissure-hit-pyrochasm-gated (rewrite site)
	-- Validation provenance is retained in maintainer notes.
	["ch0fs-21"] = {
		{ pat = "^%s*Fissure Fire Damage on Hit%s*$", repl = "Chthonic Fissure also casts Chthonic Fissure Hit" },
	},
	-- @leb-regression-guard:grounding-conduit-conditional-inc (rewrite site)
	-- "Grounding Conduit" (st38ml-8, Summon Storm Totem tree, Shaman) grants the
	-- PLAYER lightning damage. The LE->LEB extraction dropped both the "increased"
	-- keyword AND the condition: the node stat is the bare "+15% Lightning Damage",
	-- which ModParser parses as an UNCONDITIONAL MULTIPLICATIVE LightningDamage MORE
	-- (the standard bare-"+N% <Type> Damage" default). But the node description is
	-- unambiguous on both counts: "You deal INCREASED lightning damage IF a Storm
	-- Totem has hit a shocked enemy recently." So it is (a) additive INC, not MORE,
	-- and (b) conditional on having an active Storm Totem. Rewrite the bare stat to
	-- "+N% increased Lightning Damage while totem active": "increased" -> INC, and
	-- the " while totem active" suffix routes through the pre-existing
	-- ModParser ["while totem active"] -> Condition:HaveTotem tag (same machinery as
	-- the av75ch-12 "Grounding" node, guard grounding-totem-condition). HaveTotem is
	-- auto-set for totem MAINS (CalcPerform.lua) and otherwise OFF unless the build
	-- enables conditionHaveTotem -- the standard LEB safe-default-OFF treatment for
	-- every conditional damage bonus. The "hit a shocked enemy recently" sub-clause
	-- is approximated by plain HaveTotem (a Storm Totem build with Static Field shock
	-- satisfies it throughout sustained combat; gated OFF by default regardless).
	-- Node-scoped. Corpus: only ChevyVolt (lv96 Shaman, 1.4/bin) allocates st38ml-8
	-- (#3 = +45%); its main is GatheringStormMelee (melee, not a totem) so HaveTotem
	-- is OFF. CORPUS OUTPUT-NEUTRAL: an A/B (rewrite present vs reverted) on ChevyVolt
	-- gives byte-identical mainOutput (688 numeric fields, FullDPS 8133.0187 both
	-- ways) -- the node's lightning bonus never reached the full output even as the
	-- prior unconditional MORE, because a skill-tree node mod scopes to its own skill
	-- (Summon Storm Totem, includeInFullDPS=false). So this is a LATENT correctness
	-- fix (right type + right condition), not a corpus DPS change: it would manifest
	-- for a build where Storm Totem is the includeInFullDPS main (HaveTotem auto-ON),
	-- applying as conditional INC instead of unconditional MORE. (The node desc reads
	-- player-global "You deal..."; whether a skill-tree node should propagate globally
	-- to the player is a separate pre-existing scoping matter, out of scope here.)
	-- Node stats are parsed live (PassiveTree:ProcessNode) -> no ModCache/snapshot
	-- regen needed; the committed ChevyVolt snapshot still matches. See REGRESSION_GUARDS.md.
	["st38ml-8"] = {
		{ pat = "([Ll]ightning [Dd]amage)$", repl = "increased %1 while totem active" },
	},
	-- @leb-regression-guard:rhythm-stack-crit-multi (rewrite site)
	-- Dancing Strikes "Rhythm" stack family (Bladedancer). The per-stack
	-- semantics live ONLY in the node DESCRIPTION, not the stat string:
	--   dacn33-26 "Art of Blades" stat = "+10% Global Critical Multiplier"
	--     description: "Your critical strikes deal more damage per stack of
	--     {Rhythm}." -> +10%/point per stack (in-game CSV: exact 20-pt
	--     crit-mult steps at 2/2, plateau +200 at 10 stacks).
	--   dacn33-23 "Rhythm" notScalingStat = "3% Global More Damage"
	--     description: "...granting you global more damage per stack
	--     (multiplicative with other modifiers)." -> 3% MORE per stack.
	-- The rewrites append "per stack of Rhythm" so ModParser's modTagList
	-- attaches Multiplier:RhythmStacks (limit 10 = 2 x 5/5 in dacn33-23),
	-- driven by the "# of Rhythm Stacks" config. $-anchored, value-tolerant.
	-- Spec: spec/System/TestRhythmStackCritMulti_spec.lua
	["dacn33-26"] = {
		{ pat = "([Gg]lobal [Cc]ritical [Mm]ultiplier)$", repl = "%1 per stack of Rhythm" },
	},
	["dacn33-23"] = {
		{ pat = "([Gg]lobal [Mm]ore [Dd]amage)$", repl = "%1 per stack of Rhythm" },
	},
	-- @leb-regression-guard:berserk-stack-melee-damage (rewrite site)
	-- Warcry "Berserker" node (wc57-22, Primalist). Berserk is a buff gained on
	-- Warcry use (1.5s) that grants "additional melee damage" and gains stacks
	-- on melee hit up to a maximum (10 base + 1 per Brutality point, 15 at 5/5).
	-- Game source (TreeData/1_4/tree_0.json wc57-22) stats:
	--   [" Berserk On Use", "+4 Melee Damage Per Stack",
	--    "+1 Berserk Stacks On Hit While Berserk", "10 Maximum Stacks"]
	--   description "...granting you additional melee damage."
	-- The per-stack semantics live in the node ("Per Stack" = per Berserk stack)
	-- and the buff is GLOBAL on the player (all melee, not Warcry-scoped). The
	-- rewrite appends "per stack of Berserk" so ModParser attaches
	-- Multiplier:BerserkStacks (limit 15); LE_TREE_NODE_GLOBAL_SCOPE lifts the
	-- SkillId:Warcry tag (else the flat melee is scoped to Warcry, which deals no
	-- damage -> inert; this is the player Swipe -27% gap on DoNotReleaseThem
	-- lv69 Beastmaster, in-game phys 1507 vs LEB 994). Driven by the "# of
	-- Berserk Stacks" config (default 0 -> strict no-op). $-anchored,
	-- value-tolerant. Spec: spec/System/TestBerserkStackMeleeDamage_spec.lua
	["wc57-22"] = {
		{ pat = "([Mm]elee [Dd]amage) [Pp]er [Ss]tack$", repl = "%1 per stack of Berserk" },
	},
	-- @leb-regression-guard:firebrand-per-stack-tree-damage (rewrite site)
	-- Firebrand specialization tree (treeId f1b4d, Spellblade) CONTINUOUS per-stack damage nodes.
	-- Game source (TreeData/1_4/tree_1.json): f1b4d-2 Charring stats ["+4% Melee Damage Per Stack"]
	-- (maxPoints 3); f1b4d-18 Ardent Branding stats ["+3 Maximum Stacks","+3% Damage Per Stack",
	-- "-20% Attack Speed"] (maxPoints 1). Both descriptions: "Firebrand deals more ... per stack of
	-- Firebrand (multiplicative with other modifiers)." The rewrites append "per stack of Firebrand"
	-- so ModParser attaches Multiplier:FirebrandStack (CalcOffence sets it; default 4). NODE-ID-KEYED
	-- so f1b4d-7 Incineration "+12% Damage Per Stack" (IDENTICAL text, but a CONSUMED-stack proc:
	-- "Other Melee Consumes Stacks") is NOT touched. $-anchored + value-tolerant; the f1b4d-18 pat
	-- matches ONLY its "+3% Damage Per Stack" line (siblings "+3 Maximum Stacks" / "-20% Attack
	-- Speed" do not end in "Damage Per Stack"). Scope = default owning-skill SkillId (Firebrand is
	-- both the tree's skill and the hit), so NOT added to LE_TREE_NODE_GLOBAL_SCOPE.
	-- Spec: spec/System/TestFirebrandTreePerStackDamage_spec.lua
	["f1b4d-2"] = {
		{ pat = "([Mm]elee [Dd]amage) [Pp]er [Ss]tack$", repl = "%1 per stack of Firebrand" },
	},
	-- @leb-regression-guard:firebrand-tree-max-stacks (rewrite site)
	-- Firebrand "+X Maximum Stacks" tree nodes raise the live/default Firebrand stack count
	-- (base 4 in CalcOffence): f1b4d-9 Wildfire "+1 Maximum Stacks" (maxPoints 2), f1b4d-18 Ardent
	-- Branding "+3 Maximum Stacks" (maxPoints 1). Rewritten node-id-keyed to "+X Firebrand Maximum
	-- Stacks" -> ModParser modNameList maps it to BASE FirebrandMaxStacks; CalcOffence adds it to
	-- baseMaxStacks so per-stack added-fire AND per-stack damage scale by the real max, not just 4.
	-- $-anchored; the pat matches ONLY the "...Maximum Stacks" line (siblings end in "Stack"/"Speed").
	-- Spec: spec/System/TestFirebrandTreePerStackDamage_spec.lua
	["f1b4d-9"] = {
		{ pat = "([Mm]aximum [Ss]tacks)$", repl = "Firebrand %1" },
	},
	["f1b4d-18"] = {
		{ pat = "([Dd]amage) [Pp]er [Ss]tack$", repl = "%1 per stack of Firebrand" },
		{ pat = "([Mm]aximum [Ss]tacks)$", repl = "Firebrand %1" },
	},
	-- @leb-regression-guard:aerial-prowess-per-stack (rewrite site)
	-- Falconer "Aerial Prowess" node (aa989-19, Aerial Assault tree, tree_4.json).
	-- Game source (TreeData/1_4/tree_4.json aa989-19, maxPoints 3):
	--   stats           ["12 Max Aerial Prowess stacks"]
	--   notScalingStats ["6 Health Gain per stack", "+2% Damage Per stack"]
	--   description "...When you next use Aerial Assault, it consumes all stacks to
	--   restore health per stack and deal more damage (multiplicative with other
	--   modifiers) per stack."
	-- The per-stack MORE semantics live in the node ("Per stack" = per Aerial
	-- Prowess stack, backed by "12 Max Aerial Prowess stacks"); the bare "+2%
	-- Damage Per stack" string is UNIQUE to this node across all tree versions
	-- (grep: only tree_4.json 1_2/1_3/1_4, all aa989-19), so a node-keyed rewrite
	-- is exact. The rewrite appends "per stack of Aerial Prowess" so ModParser
	-- attaches Multiplier:AerialProwessStacks (limit 12 = the node's max stacks).
	-- The pattern is $-anchored and value-tolerant, and matches ONLY the Damage
	-- line (the sibling "6 Health Gain per stack" has no "Damage" before "per
	-- stack" and "12 Max Aerial Prowess stacks" ends in "stacks", so neither is
	-- touched). Scope is the DEFAULT owning-skill SkillId tag (Aerial Assault is
	-- both the tree's skill and the in-game consumer that absorbs the stacks), so
	-- aa989-19 is deliberately NOT added to LE_TREE_NODE_GLOBAL_SCOPE (unlike
	-- Berserk, whose buff is player-global). Datamine: datamining
	-- AerialAssaultMutator.GetMoreDamageFromAerialProwess (datamined offset) returns
	-- stackCount(0x138) x perStackFloat(0x15c = 2%), capped at maxStacks(0x150 =
	-- 12), consumed on cast. Driven by the "# of Aerial Prowess Stacks" config
	-- (default 0 -> strict no-op). Spec: spec/System/TestAerialProwessPerStack_spec.lua
	["aa989-19"] = {
		{ pat = "([Dd]amage) [Pp]er [Ss]tack$", repl = "%1 per stack of Aerial Prowess" },
	},
	-- @leb-regression-guard:chaos-bolts-exult-in-misery-enemy-ailment (rewrite site)
	-- Warlock "Exult in Misery" node (ch4bo-11, Chaos Bolts tree, tree_3.json).
	-- Game source (TreeData/{1_2,1_3,1_4}/tree_3.json ch4bo-11, maxPoints 3, 1_4
	-- lines 8600-8629):
	--   stats ["+4% Hit Damage to Damned", "+4% Hit Damage to Ignited",
	--          "+4% Hit Damage to Bleeding", "+4% Hit Damage to Frostbitten"]
	--   description "Chaos Bolts' hits deal more damage (multiplicative with other
	--   modifiers) to damned, ignited, bleeding and frostbitten."
	--   reminderText "Hitting enemies inflicted with multiple of these ailments,
	--   will cause the damage modifier to stack."
	-- The engine does NOT gate four independent ailment buffs: it builds ONE
	-- perAilment value (= the node's 4%/pt, ChaosBoltsDamageMutator field+0x154)
	-- and MULTIPLIES it by the live count of DISTINCT negative ailments on the
	-- target. Datamine (datamined game source ctor at
	-- datamined game source): factor = 1 + perAilment ×
	-- GetUniqueNegativeAilmentCount(target). So 3/3 with all four ailments =
	-- ×(1 + 0.12×4) = ×1.48 on Chaos Bolts hits; the reminderText ("...multiple of
	-- these ailments, will cause the damage modifier to stack") states this. The
	-- four display lines therefore COLLAPSE into a SINGLE count-scaled MORE: the
	-- Damned line is rewritten to carry "per Negative Ailment on Enemy"
	-- ($-anchored, value-tolerant -- the leading "+4%" is preserved and rank-scales
	-- to +12% at 3/3), and the other three lines are EMPTIED so exactly ONE MORE
	-- survives. (Four separate MOREs are WRONG: ModDB:MoreInternal compounds them
	-- multiplicatively, ≈×1.57 at count=4, not the engine's additive-within-mod
	-- value×count ×1.48.) PassiveTree.lua ProcessStats skips the emptied lines
	-- (same guard id) so they never reach parseMod (which would leave a space
	-- residue -> false node.extra) nor emit phantom mods. ModParser attaches
	-- Multiplier:EnemyNegativeAilmentCount (actor=enemy), driven by the
	-- "# Distinct Negative Ailments on Enemy" config (default 0 -> strict no-op).
	-- Keyed by node id so the rewrite is Chaos-Bolts-only; ch4bo-11 is NOT added to
	-- LE_TREE_NODE_GLOBAL_SCOPE (the MORE is scoped to Chaos Bolts by the default
	-- owning-skill SkillId tag, mirroring AerialAssault not Berserk). Spec:
	-- spec/System/TestChaosBoltsExultInMisery_spec.lua
	["ch4bo-11"] = {
		{ pat = "([Hh]it [Dd]amage) to Damned$", repl = "%1 per Negative Ailment on Enemy" },
		{ pat = "%+?[%d%.]+%% Hit Damage to Ignited$",     repl = "" },
		{ pat = "%+?[%d%.]+%% Hit Damage to Bleeding$",    repl = "" },
		{ pat = "%+?[%d%.]+%% Hit Damage to Frostbitten$", repl = "" },
	},
	-- @leb-regression-guard:profane-orb-hex-flurry-per-negative-ailment-more (rewrite site)
	-- Validation provenance is retained in maintainer notes.
	["pr5fm-29"] = {
		{ pat = "Profane Orb Damage per Curse$", repl = "Hit Damage per Negative Ailment on Enemy" },
	},
	-- @leb-regression-guard:dragonfang-stack-fire-damage (rewrite site)
	-- Marksman "Dragonfang" node (htsk5-15, Heartseeker tree, tree_4.json).
	-- Game source (TreeData/1_4/tree_4.json htsk5-15, maxPoints 4):
	--   stats           ["+1 Bow Fire Damage Per Stack",
	--                     "+1 Spell Fire Damage Per Stack",
	--                     "+1 Throwing Fire Damage Per Stack"]
	--   notScalingStats [" Dragonfang On Recurve"]
	--   description "Consecutive Recurves each grant a stack of Dragonfang for 10
	--   seconds. Higher stacks can only be achieved by a higher amount of
	--   consecutive Recurves, up to a maximum of 20."
	-- The per-stack flat-Fire semantics live in the node ("Per Stack" = per
	-- Dragonfang stack, capped at 20 by the description); the bare "Per Stack"
	-- phrasing collides with ~18 unrelated stacking stats (e.g. the unrelated "+5%
	-- Fire Damage Per Stack" MORE on a different tree_4.json node, L6862), so a
	-- node-keyed rewrite is required. The pattern is $-anchored and value-tolerant,
	-- and rewrites ONLY the trailing "Per Stack" -- the captured "Fire Damage" and
	-- the leading "Bow"/"Spell"/"Throwing" keyword survive, so the existing
	-- keywordFlags parse (Bow 2048 / Spell 256 / Throwing 1024 -> FireDamage BASE 1)
	-- is preserved and ModParser then attaches Multiplier:DragonfangStacks
	-- (limit 20 = the node's "up to a maximum of 20"). Scope is the DEFAULT
	-- owning-skill SkillId tag (Heartseeker): the flat Fire is granted to and
	-- consumed by Heartseeker, so htsk5-15 is deliberately NOT added to
	-- LE_TREE_NODE_GLOBAL_SCOPE (unlike Berserk, whose buff is player-global).
	-- Datamine: datamined game source
	-- Stats__AddedStat(0, <tag>, field+0x144) = +1 Fire per stack, capped at
	-- 0x14 = 20 (L603/608). Driven by the "# of Dragonfang Stacks" config
	-- (default 0 -> strict no-op). Spec: spec/System/TestDragonfangStackFireDamage_spec.lua
	["htsk5-15"] = {
		{ pat = "([Ff]ire [Dd]amage) [Pp]er [Ss]tack$", repl = "%1 per stack of Dragonfang" },
	},
	-- @leb-regression-guard:umbral-blades-edge-of-obscurity-per-shroud (rewrite site)
	-- Rogue "Edge of Obscurity" node (ub5d9-7, Umbral Blades tree, tree_4.json,
	-- maxPoints 3). Game source (TreeData/1_4/tree_4.json ub5d9-7):
	--   stats           ["+2% Damage per Dusk Shroud, up to 20"]
	--   notScalingStats [" Doubled Inside Smoke Bomb"]
	-- Umbral Blades gains MORE damage (multiplicative) per active Dusk Shroud, +2%
	-- per allocated point (so +6% at 3/3), capped at 20 Dusk Shrouds considered.
	-- The "+2% Damage per Dusk Shroud, up to 20" string is UNIQUE to this node (a
	-- sibling Shadow node sh4re-8 carries "+1% Damage per Dusk Shroud" with NO
	-- "up to 20", so it is a different cache key and is NOT touched -- and anyway
	-- this rewrite is node-keyed to ub5d9-7), so a node-keyed, $-anchored,
	-- value-tolerant rewrite is exact. The rewrite appends "per stack of dusk
	-- shroud" and DROPS the literal "20" -- that cap is folded into the modTagList
	-- key as `limit = 20` (the node text "up to 20" + the corpus "20 Max Dusk
	-- Shrouds Considered" backing). It runs in PassiveTree:ProcessStats at
	-- L393-397, BEFORE the rank-scaling block at L398-421, so the leading "+2%"
	-- correctly scales to "+6%" at 3/3 while the dropped "20" cannot be scaled.
	-- The trailing " per stack of dusk shroud" has no digit after "per", so the
	-- "per N divisor" guard never trips. Scope is the DEFAULT owning-skill SkillId
	-- tag (Umbral Blades is the tree's own skill and the in-game damage dealer),
	-- so ub5d9-7 is deliberately NOT added to LE_TREE_NODE_GLOBAL_SCOPE (unlike
	-- Berserk, whose buff is player-global). Datamine: datamining BaseUmbralBlades
	-- datamined game source MoreStat = (InsideSmokeBomb?2:1) x nodeFloat(0x108 = 2%) x
	-- getStacks(0x52), capped at DAT_183d71c44 = 20. The Smoke-Bomb x2 doubling
	-- (notScalingStats " Doubled Inside Smoke Bomb") is a documented follow-up
	-- (Mechanic 2), NOT modeled here. Driven by the existing "Dusk Shroud Stacks"
	-- config (multiplierDuskShroudStacks, default 0 -> strict no-op). Spec:
	-- spec/System/TestUmbralBladesEdgeOfObscurity_spec.lua
	["ub5d9-7"] = {
		{ pat = "([Dd]amage) per [Dd]usk [Ss]hroud, up to 20$", repl = "%1 per stack of dusk shroud" },
	},
	-- @leb-regression-guard:rive-temporal-warrior-void-conversion (rewrite site)
	-- Validation provenance is retained in maintainer notes.
	["sndr1-5"] = {
		{ pat = "^%s*Void Conversion$", repl = "Physical -> Void" },
	},
	-- @leb-regression-guard:htsk5-10-cold-conversion (rewrite site)
	-- Validation provenance is retained in maintainer notes.
	["htsk5-10"] = {
		{ pat = "^%s*Cold Conversion$", repl = "Physical -> Cold" },
	},
	-- @leb-regression-guard:htsk5-13-fire-conversion (rewrite site)
	-- Validation provenance is retained in maintainer notes.
	["htsk5-13"] = {
		{ pat = "^%s*Fire Conversion$", repl = "Physical -> Fire" },
	},
	-- @leb-regression-guard:flaming-sword-fire-conversion (rewrite site)
	-- "Flaming Sword" node (gs15de-8, Vengeance tree, tree_2.json). The deferred
	-- Vengeance sharer of the inert " Fire Conversion" string called out in the
	-- htsk5-13 block above: game source description "Vengeance' base physical damage
	-- is converted to fire" -> source type Physical (same as htsk5-13), but a DIFFERENT
	-- owning skill (Vengeance, not Heartseeker), so it MUST be node-keyed rather than a
	-- global ModCache edit (which would also mis-source the Void-typed vr53sl-18 sharer).
	-- Rewriting to the arrow form "Physical -> Fire" yields a single skill-agnostic
	-- PhysicalDamageConvertToFire BASE 100 mod; PassiveTree:ProcessStats then appends the
	-- node's DEFAULT owning-skill SkillId tag (treeId gs15de -> "Vengeance"), scoping the
	-- conversion to Vengeance (and, via groupSource, the Iron Blade / DarkBlade grant on
	-- gs15de-7). In-game (MyLittleStJames F9, Holy Aura + Symbols OFF, 2026-06-23):
	-- Vengeance + Iron Blade hits are 100% Fire, matching this 100% base conversion;
	-- pre-fix LEB left them part-Physical (Vengeance phys 356 + fire 114). Mirrors
	-- htsk5-13 exactly. $-anchored so the sibling lines are untouched.
	-- Spec: spec/System/TestFlamingSwordFireConversion_spec.lua
	["gs15de-8"] = {
		{ pat = "^%s*Fire Conversion$", repl = "Physical -> Fire" },
	},
	-- @leb-regression-guard:void-knight-mastery-melee-void-more (rewrite site)
	-- Spec: spec/System/TestVoidKnightMasteryMoreVoid_spec.lua. See REGRESSION_GUARDS.md.
	-- Validation provenance is retained in maintainer notes.
	["Void Knight"] = {
		{ pat = "^You gain 1%% more melee void damage.*per 3 Vitality%.$", repl = "1%% more melee void damage per 3 Vitality" },
	},
	-- @leb-regression-guard:paladin-mastery-full-health-more (rewrite site)
	-- Paladin ascendancy-START node ("Paladin" mastery bonus, tree_2.json,
	-- isAscendancyStart): "You deal 1.5% more damage (multiplicative with other
	-- modifiers) per 10% remaining health, up to 15% more damage at full health."
	-- Same class of bug as the Void Knight mastery: ModParser's start-anchored
	-- "^N% more" detector is defeated by the "You deal " prefix, so the line parsed to
	-- an EMPTY mod list (the bonus was dropped entirely -- worse than BASE). Surfaced by
	-- the cross-class preventive scan in TestVoidKnightMasteryMoreVoid_spec.
	-- MODEL: the bonus is health-scaled (1.5% per 10% REMAINING health), reaching its
	-- stated max "15% more damage at full health". LEB's health-state config defaults to
	-- FULL health (playerMissingHealthPercent = 0), which is the DPS-sheet baseline, so
	-- the correct value at the default state is a flat +15% more Damage -- the tooltip's
	-- own at-full-health figure, not a curve-fit. The downscale at low health (via
	-- Multiplier:MissingHealthPercent) is left unmodeled: it needs a RemainingHealthPercent
	-- multiplier LEB doesn't yet expose, and only diverges off the full-health default.
	-- If/when a build is validated below full health, promote this to a scaled MORE.
	-- Spec: spec/System/TestVoidKnightMasteryMoreVoid_spec.lua. See REGRESSION_GUARDS.md.
	["Paladin"] = {
		{ pat = "^You deal 1%.5%% more damage.*at full heath%.$", repl = "15%% more Damage" },
	},
}

-- @leb-regression-guard:rhythm-stack-crit-multi (global-scope registry site)
-- Set of skill-tree NODE ids whose parsed mods must NOT receive the
-- [SkillId] scoping tag in PassiveTree:ProcessStats because their effect is
-- GLOBAL in-game (player sheet), not scoped to the owning skill.
--
-- dacn33-26 "Art of Blades" / dacn33-23 "Rhythm" (Dancing Strikes tree):
-- both stats are GLOBAL per stack of Rhythm (verified in-game 2026-06-11,
-- <private build> capture decomposition: character-sheet added crit multi
-- 397 = 116 sheet + 80 Death's Door + 200 Rhythm = 10 stacks x 20). With the
-- SkillId tag the crit-mult mod contributed NOTHING to the player sheet
-- (Sum BASE CritMultiplier = 116 excluded it). dacn33-23's other lines
-- ("+2 Rhythm Maximum Stacks", "2 Rhythm Duration (seconds)") parse with
-- residue and are dropped regardless, so the node-level lift only affects
-- the intended per-stack mods.
LE_TREE_NODE_GLOBAL_SCOPE = {
	["dacn33-26"] = true,
	["dacn33-23"] = true,
	-- @leb-regression-guard:berserk-stack-melee-damage (global-scope registry site)
	-- wc57-22 "Berserker" (Warcry): the "+4 Melee Damage Per Stack" Berserk buff
	-- is GLOBAL on the player (every melee skill, e.g. Swipe), not scoped to
	-- Warcry. Without this lift the SkillId:Warcry tag confines the flat melee to
	-- Warcry (zero damage) so the player Swipe gets nothing (the -27% gap).
	["wc57-22"] = true,
}

-- @leb-regression-guard:tree-node-skill-rescope (registry site)
-- Validation provenance is retained in maintainer notes.
LE_TREE_NODE_SKILL_RESCOPE = {
	["ga2st-3"]  = { directOnly = true },
	["ga2st-13"] = { skillIdList = { "GatheringStormMelee", "PrimalLightning" } },
	["ga2st-14"] = { skillId = "PrimalLightning" },
	["lb23il-26"] = { skillId = "SparkChargeExplosion" },
	-- @leb-regression-guard:tree-node-skill-rescope (directOnly entry)
	-- Validation provenance is retained in maintainer notes.
	["ch4bo-2"] = { directOnly = true },
	-- ch4bo-13 "Call of Morditas" (same Chaos Bolts tree): "Chaos Bolts' base fire
	-- damage is converted to cold ... Swaps Chaos Bolts' Fire tag for a Cold tag" +
	-- "Ignite chance ... to frostbite chance for Chaos Bolts". Structurally
	-- IDENTICAL to ch4bo-2 (Chaos-Bolts-scoped conversion leaking onto group-mates
	-- via groupSource); grounded by the same in-game principle (ch4bo-2 A/B proved
	-- Chaos Bolts tree conversions are skill-scoped, never reaching group-mate
	-- skills like Harvest). Corpus-inert: 44 corpus builds allocate it but NONE put
	-- Chaos Bolts in their main socket group / FullDPS (all main = a different
	-- skill), so mainOutput is byte-identical pre/post (verified by 44-build probe).
	["ch4bo-13"] = { directOnly = true },
	-- @leb-regression-guard:profane-orb-hex-flurry-per-negative-ailment-more (rescope entry)
	-- Hex Flurry (pr5fm-29) grants its per-negative-ailment MORE to the Profane Orb,
	-- which is a GRANTED SUB-SKILL ("Warlock 05.2 Profane Orb", SubSkillGrants) of the
	-- owning tree skill "Warlock 05 Profane Veil". Left at the default owning-skill
	-- SkillId ("Warlock 05 Profane Veil"), the MORE reaches the granted orb through the
	-- cfg.groupSource channel (source="SkillId:Warlock 05 Profane Veil") -- BUT it
	-- lands on the orb TWICE (measured effective value 120% = 2x the 60% node value at
	-- 4/4 -> (1 + 1.20*N) instead of (1 + 0.60*N); confirmed by an N=0..4 A/B probe on
	-- the Dicey save), because the orb matches the parent-scoped tag via both ModStore
	-- match branches and the two identical-tag copies sum additive-within-mod. Rescoping
	-- the SkillId tag to the orb's OWN grantedEffect.id makes it match the orb exactly
	-- once via the direct skillGrantedEffect.id branch (REGIME A, INDEPENDENT of
	-- groupSource -- the same single-match posture the lb23il-26 "Mortal Capacitor"
	-- rescope relies on), which is also the semantically precise scope (the node text is
	-- "Profane Orb deals more damage ... per Curse"). Verified: with this rescope the
	-- orb per-hit scales as exactly (1 + 0.60*N) at 4/4, no double-count.
	["pr5fm-29"] = { skillId = "Warlock 05.2 Profane Orb" },
}

-- @leb-regression-guard:tree-node-spellify-skill (registry site)
-- Validation provenance is retained in maintainer notes.
LE_TREE_NODE_SKILL_SPELLIFY = {
	["fl44-29"] = "fl44",  -- Flay: Exquisite Blood
}

-- @leb-regression-guard:tree-node-meleeify-skill (registry site)
-- Validation provenance is retained in maintainer notes.
LE_TREE_NODE_SKILL_MELEEIFY = {
	["hh7pa3-8"] = "hh7pa3",  -- Healing Hands: Seraph Blade
}

-- @leb-regression-guard:tree-node-add-hit-skill (registry site)
-- Validation provenance is retained in maintainer notes.
LE_TREE_NODE_SKILL_ADD_HIT = {
	["hh7pa3-1"] = "hh7pa3",  -- Healing Hands: Searing Light
}

-- @leb-regression-guard:minion-buff-skill-to-condition (registry site)
-- Map of LE-skill canonical name -> ModDB Condition name that gates
-- minion-side contributions from buff-skills whose effect applies *per
-- target minion* (e.g. Dread Shade's per-shade auraStats). This is
-- distinct from LE_WHILE_ACTIVE_BUFF_BY_TREE_ID (which gates the player
-- buff's own tree-node contributions): this registry is consulted by
-- CalcPerform.lua MinionModifier dispatch so per-minion mods carrying a
-- SkillId tag for one of these skills also pick up an ActorCondition
-- tag that resolves against player.modDB. Mirrors LE's in-game model
-- where Dread Shade is a per-target Buff Component (datamined game source
-- DreadShadeMutator.DelayedCastOnMinion()), not a skill-scope flag.
LE_MINION_BUFF_SKILL_TO_CONDITION = {
	DreadShade = "MinionsHaveDreadShade",
}

-- @leb-regression-guard:minion-aura-player-application (registry site)
-- Validation provenance is retained in maintainer notes.
LE_MINION_AURA_PLAYER_NODES = {
	["sp38-13"] = "InSprigganHealingAura",  -- Aura of Kinship: +5 Spell Damage/pt to allies (the player)
}

-- @leb-regression-guard:vengeance-bolster-player-buff (registry site)
-- Validation provenance is retained in maintainer notes.
LE_TREE_NODE_PLAYER_CONDITIONAL_BUFF = {
	["gs15de-19"] = "HaveBolster",  -- Bolster (Vengeance): -13% DamageTaken MORE / +25% Armour INC per pt, while hit-with-Vengeance-recently
}

