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
	"Cold",
	"Lightning",
	"Physical",
	"Necrotic",
	"Poison",
	"Void"
}

Attributes = {"Str","Dex","Int","Att","Vit"}
LongAttributes = {"Strength","Dexterity","Intelligence","Attunement","Vitality"}
AttributesColored = {
    colorCodes.STRENGTH.."Strength",
    colorCodes.DEXTERITY.."Dexterity",
    colorCodes.INTELLIGENCE.."Intelligence",
    colorCodes.ATTUNEMENT.."Attunement",
    colorCodes.VITALITY.."Vitality"
}

DamageTypesColored = {
	colorCodes.FIRE.."Fire",
	colorCodes.COLD .. "Cold",
	colorCodes.LIGHTNING .. "Lightning",
	colorCodes.PHYSICAL.."Physical",
	colorCodes.NECROTIC.."Necrotic",
	colorCodes.POISON.."Poison",
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
DamageSourceWeapons = { "Wand", "Bow", "Axe", "Sceptre", "Staff", "Dagger", "Sword" }

-- Active skill types — bits 1..16384 mirror Last Epoch's internal AT enum
-- (Game.dll Ability.Tags). Higher bits are LEB-specific tags that LE doesn't
-- expose but ModParser/Calc* depend on (Buff/Curse/Ailment/etc.). Do NOT
-- reuse bits 1..16384 for LEB-only flags — `skills.json` skillTypeTags are
-- imported verbatim from datamining and rely on LE's bit layout.
SkillType = {
	-- LE-aligned bits (must not change)
	Physical = 1,
	Lightning = 2,
	Cold = 4,
	Fire = 8,
	Void = 16,
	Necrotic = 32,
	Poison = 64,
	Bow = 128,
	Spell = 256,
	Melee = 512,
	Throwing = 1024,
	Dot = 2048,
	Minion = 4096,
	Movement = 8192,
	Channelling = 16384,
	-- bit 15 (32768) and bit 16 (65536) — LE AT enum likely uses these but
	-- their identity isn't dumped yet (datamining Phase 8 stopped at bit 14).
	-- bit 17 (131072) is in use by LE: Focus carries it and Focus is a buff
	-- skill, so we provisionally name it Buff. To be confirmed when datamining
	-- dumps the full Tag enum.
	Buff = 131072,
	-- LEB-specific bits — placed at bit 18+ to leave LE bits 15..17 free.
	-- Renumber freely if LE turns out to use bit 18+.
	Totem = 262144,
	PetResisted = 524288,
	Potion = 1048576,
	Transform = 2097152,
	LowLife = 4194304,
	HighLife = 8388608,
	FullLife = 16777216,
	Hit = 33554432,
	Curse = 67108864,
	Ailment = 134217728,
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

