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

	BRUTALITY = "^xFF4040",
	MADNESS = "^xFF60FF",
	GUILE = "^x60FF60",
	APATHY = "^x6060FF",
	RAMPANCY = "^xFF8040",
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

-- @leb-regression-guard:minion-buff-skill-to-condition (registry site)
-- Map of LE-skill canonical name -> ModDB Condition name that gates
-- minion-side contributions from buff-skills whose effect applies *per
-- target minion* (e.g. Dread Shade's per-shade auraStats). This is
-- distinct from LE_WHILE_ACTIVE_BUFF_BY_TREE_ID (which gates the player
-- buff's own tree-node contributions): this registry is consulted by
-- CalcPerform.lua MinionModifier dispatch so per-minion mods carrying a
-- SkillId tag for one of these skills also pick up an ActorCondition
-- tag that resolves against player.modDB. Mirrors LE's in-game model
-- where Dread Shade is a per-target Buff Component (dump.cs
-- DreadShadeMutator.DelayedCastOnMinion()), not a skill-scope flag.
LE_MINION_BUFF_SKILL_TO_CONDITION = {
	DreadShade = "MinionsHaveDreadShade",
}

