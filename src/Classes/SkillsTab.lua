-- Last Epoch Building
--
-- Module: Skills Tab
-- Skills tab for the current build.
--
local pairs = pairs
local ipairs = ipairs
local t_insert = table.insert
local t_remove = table.remove
local m_min = math.min
local m_max = math.max
local m_floor = math.floor
local m_ceil = math.ceil

local sortGemTypeList = {
	{ label = "Full DPS", type = "FullDPS" },
	{ label = "Combined DPS", type = "CombinedDPS" },
	{ label = "Hit DPS", type = "TotalDPS" },
	{ label = "Average Hit", type = "AverageDamage" },
	{ label = "DoT DPS", type = "TotalDot" },
	{ label = "Bleed DPS", type = "BleedDPS" },
	{ label = "Ignite DPS", type = "IgniteDPS" },
	{ label = "Poison DPS", type = "TotalPoisonDPS" },
	{ label = "Effective Hit Pool", type = "TotalEHP" },
}

-- Scaling Tags display: maps skillTypes bits and attribute scalings into a
-- short label list (Fire, Cold, Melee, Spell, Intelligence, ...) shown in
-- skill slot and skill-spec tree root tooltips. Mirrors LE's ability tooltip.
-- Order: damage types (LE display order) -> combat class -> attributes.
-- AT enum bit -> display label, sourced from il2cpp_dump_v142/dump.cs:240086.
-- Bit values match Global.lua's SkillType enum (canonical AT enum layout).
local SCALING_TAG_DAMAGE = {
    { bit = 1,   name = "Physical"  },
    { bit = 8,   name = "Fire"      },
    { bit = 4,   name = "Cold"      },
    { bit = 2,   name = "Lightning" },
    { bit = 32,  name = "Necrotic"  },
    { bit = 64,  name = "Poison"    },
    { bit = 16,  name = "Void"      },
    { bit = 128, name = "Elemental" },
}
local SCALING_TAG_COMBAT = {
    { bit = 512,  name = "Melee"    },
    { bit = 256,  name = "Spell"    },
    { bit = 1024, name = "Throwing" },
    { bit = 2048, name = "Bow"      },
}
-- Meta tags after combat class. DoT/Minion/Channelling/Buff per canonical AT enum.
local SCALING_TAG_META = {
    { bit = 4096,   name = "DoT"         },
    { bit = 8192,   name = "Minion"      },
    { bit = 16384,  name = "Totem"       },
    { bit = 262144, name = "Channelling" },
    { bit = 524288, name = "Transform"   },
    { bit = 131072, name = "Buff"        },
}
-- Capitalize a lowercase damage type name ("cold" -> "Cold").
local function capitalizeDamageType(s)
    return s:sub(1, 1):upper() .. s:sub(2)
end
-- Build the Scaling Tags list. If `dynamicDamageTypes` is provided (the array
-- form returned by SkillsTabClass:GetDynamicDamageTypes / ByTreeId), the
-- damage-type portion is taken from that array so tree node conversions
-- (e.g. Flame Ward -> Cold, Surge -> Fire) are reflected. Otherwise damage
-- bits are read straight from grantedEffect.skillTypeTags (base only).
function getScalingTagsList(grantedEffect, dynamicDamageTypes, extraFlags, areaOverride)
    if not grantedEffect then return nil end
    local tags = {}
    -- Include fakeTags so categories LE adds at runtime (e.g. Judgement is
    -- Spell-tagged via fakeTags=256 despite being mechanically Melee) appear
    -- in the Scaling Tags row exactly like the in-game tooltip. extraFlags
    -- carries tree-node-injected bits (e.g. Totemic Heart adds Minion+Totem
    -- when Warcry is converted into a Warcry Totem). areaOverride lets a
    -- caller substitute the effective areaTagDisplay value (used when a
    -- "Create X Totem" node moves the cast's Area onto the minion side).
    local flags = bit.bor(grantedEffect.skillTypeTags or 0, grantedEffect.fakeTags or 0, extraFlags or 0)
    if dynamicDamageTypes and #dynamicDamageTypes > 0 then
        for _, dt in ipairs(dynamicDamageTypes) do
            if dt.isBase then t_insert(tags, { name = capitalizeDamageType(dt.type) }) end
        end
        -- Preserve the "Elemental" meta marker when the static skillTypeTags
        -- carry bit128 (tri-elemental skills); dynamicDamageTypes only knows
        -- individual damage types and would otherwise drop it.
        if bit.band(flags, 128) ~= 0 then
            t_insert(tags, { name = "Elemental" })
        end
    else
        for _, t in ipairs(SCALING_TAG_DAMAGE) do
            if bit.band(flags, t.bit) ~= 0 then t_insert(tags, { name = t.name }) end
        end
    end
    for _, t in ipairs(SCALING_TAG_COMBAT) do
        if bit.band(flags, t.bit) ~= 0 then t_insert(tags, { name = t.name, color = t.color }) end
    end
    for _, t in ipairs(SCALING_TAG_META) do
        if bit.band(flags, t.bit) ~= 0 then t_insert(tags, { name = t.name, color = t.color }) end
    end
    -- Area tag: Ability.areaTagDisplay {None=0, Tag=1, MinionTagOnly=2, TagAndMinionTag=3}.
    -- Scaling Tags row gets Area only when value is Tag(1) or TagAndMinionTag(3).
    -- MinionTagOnly(2) is surfaced separately on the Minion Tags row.
    local atd = areaOverride or grantedEffect.areaTagDisplay or 0
    if atd == 1 or atd == 3 then
        t_insert(tags, { name = "Area" })
    end
    -- Instant Cast comes from the LE ability field `instantCastForPlayer` (1/0),
    -- not from the skillTypeTags bitmap. Datamined into skills.json separately.
    if grantedEffect.instantCastForPlayer == 1 then
        t_insert(tags, { name = "Instant Cast" })
    end
    if grantedEffect.attributeScalings then
        for _, attr in ipairs(grantedEffect.attributeScalings) do
            t_insert(tags, { name = attr })
        end
    end
    return tags
end
function formatScalingTagsLine(tags)
    if not tags or #tags == 0 then return nil end
    local parts = {}
    for _, tag in ipairs(tags) do
        t_insert(parts, "^7" .. tag.name)
    end
    return "^7Scaling Tags: " .. table.concat(parts, ", ")
end
-- Minion Tags row: tags of the minion ability spawned by this skill.
-- Source: Ability.minionTagsDisplay (datamined into skills.json) — same bitmap
-- layout as skillTypeTags. Plus Area when areaTagDisplay is MinionTagOnly(2)
-- or TagAndMinionTag(3). Returns nil when the skill spawns no minion (i.e.
-- minionTagsDisplay == 0 and areaTagDisplay does not include MinionTag).
function getMinionTagsList(grantedEffect, extraMinionFlags, areaOverride)
    if not grantedEffect then return nil end
    local mtd = bit.bor(grantedEffect.minionTagsDisplay or 0, extraMinionFlags or 0)
    local atd = areaOverride or grantedEffect.areaTagDisplay or 0
    local hasMinionArea = (atd == 2 or atd == 3)
    if mtd == 0 and not hasMinionArea then return nil end
    local tags = {}
    for _, t in ipairs(SCALING_TAG_DAMAGE) do
        if bit.band(mtd, t.bit) ~= 0 then t_insert(tags, { name = t.name }) end
    end
    for _, t in ipairs(SCALING_TAG_COMBAT) do
        if bit.band(mtd, t.bit) ~= 0 then t_insert(tags, { name = t.name, color = t.color }) end
    end
    for _, t in ipairs(SCALING_TAG_META) do
        if bit.band(mtd, t.bit) ~= 0 then t_insert(tags, { name = t.name, color = t.color }) end
    end
    if hasMinionArea then
        t_insert(tags, { name = "Area" })
    end
    return tags
end
function formatMinionTagsLine(tags)
    if not tags or #tags == 0 then return nil end
    local parts = {}
    for _, tag in ipairs(tags) do
        t_insert(parts, "^7" .. tag.name)
    end
    return "^7Minion Tags: " .. table.concat(parts, ", ")
end

-- Layout constants for visual skill panel
local SLOT_SIZE = 76
local SLOT_GAP = 12
local SLOT_ROW_HEIGHT = 116  -- slot height + damage type icon row
local ICON_SIZE = 72         -- icon size in spec slots
local GRID_ICON_SIZE = 56   -- icon size in skill selection grid (fits within frame border)
local FRAME_SIZE = 84
local CELL_W = 100
local CELL_H = 120
local SECTION_HEADER_H = 30
local GRID_PAD = 16

-- Skill unlock data per mastery (same as TreeTab.lua)
local MASTERY_SKILL_UNLOCKS = {
	["Primalist"] = {
		[0] = {
			{ name = "Eterras Blessing", label = "Eterra's Blessing", treeId = "eb5656", level = 5 },
			{ name = "Warcry", label = "Warcry", treeId = "wc57", level = 10 },
			{ name = "SummonStormCrow", label = "Summon Storm Crows", treeId = "ssc50", level = 15 },
			{ name = "SerpentStrike", label = "Serpent Strike", treeId = "st31et", level = 20 },
		},
		[1] = {
			{ name = "SummonBear", label = "Summon Bear", treeId = "be36ar", level = 5 },
			{ name = "SummonScorpion", label = "Summon Scorpion", treeId = "sc36pi", level = 15 },
			{ name = "SummonFrenzyTotem", label = "Summon Frenzy Totem", treeId = "sf37", level = 25 },
			{ name = "SummonSabertooth", label = "Summon Sabertooth", treeId = "sa36oh", level = 35 },
			{ name = "SummonRaptor", label = "Summon Raptor", treeId = "srtor" },
		},
		[2] = {
			{ name = "Tornado", label = "Tornado", treeId = "to50", level = 5 },
			{ name = "EarthquakeSlam", label = "Earthquake", treeId = "eq5s", level = 15 },
			{ name = "Avalanche", label = "Avalanche", treeId = "av75ch", level = 25 },
			{ name = "SummonStormTotem", label = "Summon Storm Totem", treeId = "st38ml" },
		},
		[3] = {
			{ name = "SprigganForm", label = "Spriggan Form", treeId = "sf5rd", level = 5 },
			{ name = "SummonSpriggan", label = "Summon Spriggan", treeId = "sp38", level = 15 },
			{ name = "Swarmblade Form", label = "Swarmblade Form", treeId = "sbf4m", level = 25 },
			{ name = "EntanglingRoots", label = "Entangling Roots", treeId = "er6no", level = 35 },
			{ name = "WerebearForm", label = "Werebear Form", treeId = "wb8fo" },
		},
	},
	["Mage"] = {
		[0] = {
			{ name = "Glacier", label = "Glacier", treeId = "gl14", level = 5 },
			{ name = "Disintegrate", label = "Disintegrate", treeId = "dig5", level = 10 },
			{ name = "VolcanicOrb", label = "Volcanic Orb", treeId = "vo54", level = 15 },
			{ name = "Focus", label = "Focus", treeId = "vm53dx", level = 20 },
		},
		[1] = {
			{ name = "StaticOrb", label = "Static Orb", treeId = "so35a", level = 5 },
			{ name = "IceBarrage", label = "Ice Barrage", treeId = "ib5g3", level = 15 },
			{ name = "ArcaneAscendance", label = "Arcane Ascendance", treeId = "arcas", level = 30 },
			{ name = "BlackHole", label = "Black Hole", treeId = "bh2", level = 40 },
			{ name = "Meteor", label = "Meteor", treeId = "me27" },
		},
		[2] = {
			{ name = "FlameReave", label = "Flame Reave", treeId = "fr11mv", level = 5 },
			{ name = "EnchantWeapon", label = "Enchant Weapon", treeId = "sb44eQ", level = 15 },
			{ name = "Firebrand", label = "Firebrand", treeId = "f1b4d", level = 30 },
			{ name = "Surge", label = "Surge", treeId = "su5g3", level = 40 },
			{ name = "ShatterStrike", label = "Shatter Strike", treeId = "ss3tre" },
		},
		[3] = {
			{ name = "FlameRush", label = "Flame Rush", treeId = "fl71ds", level = 5 },
			{ name = "FrostWall", label = "Frost Wall", treeId = "fr4wl", level = 15 },
			{ name = "Runebolt", label = "Runebolt", treeId = "fb8fe", level = 30 },
			{ name = "GlyphOfDominion", label = "Glyph of Dominion", treeId = "gy2dm", level = 35 },
			{ name = "RunicInvocation", label = "Runic Invocation", treeId = "rn7iv" },
		},
	},
	["Sentinel"] = {
		[0] = {
			{ name = "Rebuke", label = "Rebuke", treeId = "re82ke", level = 5 },
			{ name = "ShieldRush", label = "Shield Rush", treeId = "sr31hu", level = 10 },
			{ name = "Multistrike", label = "Multistrike", treeId = "multis", level = 15 },
			{ name = "Smite", label = "Smite", treeId = "sm87r4", level = 20 },
		},
		[1] = {
			{ name = "VolatileReversal", label = "Volatile Reversal", treeId = "vr53sl", level = 5 },
			{ name = "AbyssalEchoes", label = "Abyssal Echoes", treeId = "ab0lh", level = 10 },
			{ name = "DevouringOrb", label = "Devouring Orb", treeId = "do5vr", level = 15 },
			{ name = "Anomaly", label = "Anomaly", treeId = "an0my", level = 30 },
			{ name = "ErasingStrike", label = "Erasing Strike", treeId = "es6ai" },
		},
		[2] = {
			{ name = "ShieldThrow", label = "Shield Throw", treeId = "st31io", level = 5 },
			{ name = "ManifestArmor", label = "Manifest Armor", treeId = "ma6hdr", level = 15 },
			{ name = "RingOfShields", label = "Ring of Shields", treeId = "rs31hi", level = 30 },
			{ name = "SmeltersWrath", label = "Smelter's Wrath", treeId = "st4th", level = 40 },
			{ name = "ForgeStrike", label = "Forge Strike", treeId = "fs3e3" },
		},
		[3] = {
			{ name = "HealingHands", label = "Healing Hands", treeId = "hh7pa3", level = 5 },
			{ name = "SymbolsOfHope", label = "Symbols of Hope", treeId = "si4lgl", level = 15 },
			{ name = "Judgement", label = "Judgement", treeId = "pa67ju", level = 30 },
			{ name = "HolyAura", label = "Holy Aura", treeId = "ah443" },
		},
	},
	["Acolyte"] = {
		[0] = {
			{ name = "HungeringSouls", label = "Hungering Souls", treeId = "hs18gu", level = 5 },
			{ name = "SummonBoneGolem", label = "Summon Bone Golem", treeId = "bg36nl", level = 10 },
			{ name = "SpiritPlague", label = "Spirit Plague", treeId = "sp5g2", level = 15 },
			{ name = "InfernalShade", label = "Infernal Shade", treeId = "is40", level = 20 },
		},
		[1] = {
			{ name = "SummonSkeletalMage", label = "Summon Skeletal Mage", treeId = "sm4g", level = 5 },
			{ name = "Sacrifice", label = "Sacrifice", treeId = "sf31rc", level = 10 },
			{ name = "DreadShade", label = "Dread Shade", treeId = "ds4d3", level = 30 },
			{ name = "AssembleAbomination", label = "Assemble Abomination", treeId = "aa710", level = 40 },
			{ name = "SummonWraith", label = "Summon Wraith", treeId = "sw42ih" },
		},
		[2] = {
			{ name = "DrainLife", label = "Drain Life", treeId = "dl73", level = 5 },
			{ name = "AuraOfDecay", label = "Aura of Decay", treeId = "ad0ry", level = 10 },
			{ name = "Flay", label = "Flay", treeId = "fl44", level = 30 },
			{ name = "DeathSeal", label = "Death Seal", treeId = "ds34l", level = 35 },
			{ name = "ReaperForm", label = "Reaper Form", treeId = "rf1azz" },
		},
		[3] = {
			{ name = "ChaosBolts", label = "Chaos Bolts", treeId = "ch4bo", level = 5 },
			{ name = "Ghostflame", label = "Ghostflame", treeId = "gh0fl", level = 15 },
			{ name = "SoulFeast", label = "Soul Feast", treeId = "fe8at", level = 30 },
			{ name = "ProfaneVeil", label = "Profane Veil", treeId = "pr5fm", level = 35 },
			{ name = "ChthonicFissure", label = "Chthonic Fissure", treeId = "ch0fs" },
		},
	},
	["Rogue"] = {
		[0] = {
			{ name = "SmokeBomb", label = "Smoke Bomb", treeId = "smbmb", level = 5 },
			{ name = "Bladestorm Throw", label = "Bladestorm Throw", treeId = "bl5st", level = 10 },
			{ name = "SummonBallista", label = "Ballista", treeId = "ba1574", level = 15 },
			{ name = "UmbralBlades", label = "Umbral Blades", treeId = "ub5d9", level = 20 },
		},
		[1] = {
			{ name = "ShadowCascade", label = "Shadow Cascade", treeId = "dagg3", level = 5 },
			{ name = "SynchronizedStrike", label = "Synchronized Strike", treeId = "sync5", level = 10 },
			{ name = "LethalMirage", label = "Lethal Mirage", treeId = "mira59", level = 30 },
			{ name = "DancingStrike", label = "Dancing Strikes", treeId = "dacn33" },
		},
		[2] = {
			{ name = "Multishot", label = "Multishot", treeId = "mush9", level = 5 },
			{ name = "DarkQuiver", label = "Dark Quiver", treeId = "dqv5", level = 15 },
			{ name = "Heartseeker", label = "Heartseeker", treeId = "htsk5", level = 30 },
			{ name = "HailOfArrows", label = "Hail of Arrows", treeId = "exvol8", level = 35 },
			{ name = "DetonatingArrow", label = "Detonating Arrow", treeId = "detar" },
		},
		[3] = {
			{ name = "ExplosiveTrap", label = "Explosive Trap", treeId = "ex4tp", level = 5 },
			{ name = "Net", label = "Net", treeId = "ne01t", level = 15 },
			{ name = "AerialAssault", label = "Aerial Assault", treeId = "aa989", level = 30 },
			{ name = "DiveBomb", label = "Dive Bomb", treeId = "db992", level = 35 },
			{ name = "Falconry", label = "Falconry", treeId = "falc0" },
		},
	},
}

-- Display order for base class skills (treeId order from LETools)
-- Skills not listed appear at the end in their original order
local BASE_SKILL_ORDER = {
	["Primalist"] = {
		"wo42", "ga2st", "fl13", "th39",   -- Summon Wolf, Gathering Storm, Fury Leap, Summon Thorn Totem
		"sw43", "ts85i", "mas54", "uph41", -- Swipe, Tempest Strike, Maelstrom, Upheaval
	},
	["Acolyte"] = {
		"rb31pl", "ss37kl", "bp2nk", "ws54hm",  -- Rip Blood, Summon Skeleton, Marrow Shards, Wandering Spirits
		"ha84", "bc53", "ts50pl", "svz81",       -- Harvest, Bone Curse, Transplant, Summon Volatile Zombie
	},
	["Mage"] = {
		"lb23il", "fi9", "sw31a", "en6",         -- Lightning Blast, Fireball, Snap Freeze, Elemental Nova
		"ms26", "fw3d", "te44", "frc87w", "st47ic", -- Mana Strike, Flame Ward, Teleport, Frost Claw, Static
	},
	["Rogue"] = {
		"flur3", "srk21", "sh4re", "aacfl",      -- Flurry, Shurikens, Shadow Rend, Acid Flask
		"pun22", "shiif", "cstri", "deeco",      -- Puncture, Shift, Cinder Strike, Decoy
	},
	["Sentinel"] = {
		"gs15de", "va53st", "ht16aw", "lu25ng",  -- Vengeance, Warpath, Hammer Throw, Lunge
		"sndr1", "sb4h", "javeli", "v01cv",      -- Rive, Shield Bash, Javelin, Void Cleave
	},
}

local SkillsTabClass = newClass("SkillsTab", "UndoHandler", "ControlHost", "Control", function(self, build)
	self.UndoHandler()
	self.ControlHost()
	self.Control()

	self.build = build

	self.socketGroupList = { }

	self.sortGemsByDPS = true
	self.sortGemsByDPSField = "CombinedDPS"
	self.showSupportGemTypes = "ALL"
	self.showAltQualityGems = false
	self.defaultGemLevel = "normalMaximum"
	self.defaultGemQuality = main.defaultGemQuality

	-- Create a single Skill Tree Viewer for all skill trees (combined view)
	self.skillTreeViewer = new("PassiveTreeView")
	self.skillTreeViewer.filterMode = "skill"
	self.skillTreeViewer.selectedSkillIndex = nil  -- nil = show all trees in one viewport
	self.selectedSkillTreeIndex = nil

	-- Search state
	self.skillOverviewSearchStr = ""
	self.skillOverviewSearchCache = { str = nil, results = {} }
	self.controls.skillTreeSearch = new("EditControl", nil, 0, 0, 200, 20, "", nil, "%c", 100, function(buf)
		self.skillTreeViewer.searchStr = buf
	end, nil, nil, true)
	self.controls.skillTreeSearch.placeholder = "Search Nodes..."
	self.controls.skillOverviewSearch = new("EditControl", nil, 0, 0, 200, 20, "", nil, "%c", 100, function(buf)
		self.skillOverviewSearchStr = buf
	end, nil, nil, true)
	self.controls.skillOverviewSearch.placeholder = "Search Nodes..."

	-- Phase 2: Visual skill panel state
	self.viewMode = "overview"       -- "overview" or "tree"
	self.selectedSlotIndex = 1       -- which spec slot is selected (1-5)
	self.viewingTreeSlot = nil       -- which slot's tree is shown (1-5)
	self.hoverSlotIndex = nil
	self.hoverSkillId = nil
	self.spriteHandles = {}

	-- Set selector
	self.controls.setSelect = new("DropDownControl", { "TOPLEFT", self, "TOPLEFT" }, 76, 8, 210, 20, nil, function(index, value)
		self:SetActiveSkillSet(self.skillSetOrderList[index])
		self:AddUndoState()
	end)
	self.controls.setSelect.enableDroppedWidth = true
	self.controls.setSelect.enabled = function()
		return #self.skillSetOrderList > 1
	end
	self.controls.setLabel = new("LabelControl", { "RIGHT", self.controls.setSelect, "LEFT" }, -2, 0, 0, 16, "^7Skill set:")
	self.controls.setManage = new("ButtonControl", { "LEFT", self.controls.setSelect, "RIGHT" }, 4, 0, 90, 20, "Manage...", function()
		self:OpenSkillSetManagePopup()
	end)

	-- Socket group list (fixed height for 5 skills)
	self.controls.skillsSection = new("SectionControl", { "TOPLEFT", self, "TOPLEFT" }, 20, 54, 720, 150, "Skills")
	self.controls.skillsSection.height = function()
		return 40 + 24 * 5  -- Fixed: 5 skills only
	end

	-- Socket group details
	if main.portraitMode then
		self.anchorGroupDetail = new("Control", { "TOPLEFT", self.controls.optionSection, "BOTTOMLEFT" }, 0, 20, 0, 0)
	else
		self.anchorGroupDetail = new("Control", { "TOPLEFT", self.controls.skillsSection, "TOPRIGHT" }, 20, 0, 0, 0)
	end
	self.anchorGroupDetail.shown = function()
		return self.displayGroup ~= nil
	end
	self.controls.groupLabel = new("EditControl", { "TOPLEFT", self.anchorGroupDetail, "TOPLEFT" }, 0, 0, 380, 20, nil, "Label", "%c", 50, function(buf)
		self.displayGroup.label = buf
		self:ProcessSocketGroup(self.displayGroup)
		self:AddUndoState()
		self.build.buildFlag = true
	end)
	self.controls.groupSlotLabel = new("LabelControl", { "TOPLEFT", self.anchorGroupDetail, "TOPLEFT" }, 0, 30, 0, 16, "^7Socketed in:")
	self.controls.groupSlot = new("DropDownControl", { "TOPLEFT", self.anchorGroupDetail, "TOPLEFT" }, 85, 28, 130, 20, groupSlotDropList, function(index, value)
		self.displayGroup.slot = value.slotName
		self:AddUndoState()
		self.build.buildFlag = true
	end)
	self.controls.groupSlot.tooltipFunc = function(tooltip, mode, index, value)
		tooltip:Clear()
		if mode == "OUT" or index == 1 then
			tooltip:AddLine(16, "Select the item in which this skill is socketed.")
			tooltip:AddLine(16, "This will allow the skill to benefit from modifiers on the item that affect socketed gems.")
		else
			local slot = self.build.itemsTab.slots[value.slotName]
			local ttItem = self.build.itemsTab.items[slot.selItemId]
			if ttItem then
				self.build.itemsTab:AddItemTooltip(tooltip, ttItem, slot)
			else
				tooltip:AddLine(16, "No item is equipped in this slot.")
			end
		end
	end
	self.controls.groupSlot.enabled = function()
		return self.displayGroup.source == nil
	end
	self.controls.sourceNote = new("LabelControl", { "TOPLEFT", self.controls.groupSlotLabel, "TOPLEFT" }, 0, 30, 0, 16)
	self.controls.sourceNote.shown = function()
		return self.displayGroup.source ~= nil
	end
	self.controls.sourceNote.label = function()
		local label
		if self.displayGroup.explodeSources then
			label = [[^7This is a special group created for the enemy explosion effect,
which comes from the following sources:]]
			for _, source in ipairs(self.displayGroup.explodeSources) do
				label = label .. "\n\t" .. colorCodes[source.rarity or "NORMAL"] .. (source.name or source.dn or "???")
			end
			label = label .. "^7\nYou cannot delete this group, but it will disappear if you lose the above sources."
		else
			local activeGem = self.displayGroup.gemList[1]
			local sourceName
			if self.displayGroup.sourceItem then
				sourceName = "'" .. colorCodes[self.displayGroup.sourceItem.rarity] .. self.displayGroup.sourceItem.name
			elseif self.displayGroup.sourceNode then
				sourceName = "'" .. colorCodes["NORMAL"] .. self.displayGroup.sourceNode.name
			else
				sourceName = "'" .. colorCodes["NORMAL"] .. "?"
			end
			sourceName = sourceName .. "^7'"
			label = [[^7This is a special group created for the ']] .. activeGem.color .. (activeGem.grantedEffect and activeGem.grantedEffect.name or activeGem.nameSpec) .. [[^7' skill,
which is being provided by ]] .. sourceName .. [[.
You cannot delete this group, but it will disappear if you ]] .. (self.displayGroup.sourceNode and [[un-allocate the node.]] or [[un-equip the item.]])
			if not self.displayGroup.noSupports then
				label = label .. "\n\n" .. [[You cannot add support gems to this group, but support gems in
any other group socketed into ]] .. sourceName .. [[
will automatically apply to the skill.]]
			end
		end
		return label
	end

	-- Scroll bar (horizontal - for existing content)
	self.controls.scrollBarH = new("ScrollBarControl", nil, 0, 0, 0, 18, 100, "HORIZONTAL", true)
	
	-- Vertical scroll bar for skill trees
	self.controls.scrollBarV = new("ScrollBarControl", nil, 0, 0, 18, 0, 100, "VERTICAL", true)

	-- Initialise skill sets
	self.skillSets = { }
	self.skillSetOrderList = { 1 }
	self:NewSkillSet(1)
	self:SetActiveSkillSet(1)
end)

function SkillsTabClass:InitSkillControl(i)
    if i <= 5 then
		-- "Skill #:" label
		self.controls['skillLabel-' .. i] = new("LabelControl", { "TOPLEFT", self.controls.skillsSection, "TOPLEFT" }, 20, 24 * i, 0, 16, "^7Skill " .. i .. ":")
		-- Skill name dropdown
		self.controls['skill-' .. i] = new("DropDownControl", { "LEFT", self.controls['skillLabel-' .. i], "RIGHT" }, 4, 0, 140, 20, nil, function(index, value)
			self:SelSkill(i, value.name)
			self.build.spec:BuildAllDependsAndPaths()
		end)
	else
		self.controls['skill-' .. i] = new("LabelControl", { "TOPLEFT", self.controls.skillsSection, "TOPLEFT" }, 20, 24 * i, 0, 16, "^7Skill " .. i .. ":")
		self.controls['skill-' .. i].shown = function()
				return self.socketGroupList[i] ~= nil
		end
		self.controls['skill-' .. i].label = function()
			return (colorCodes.SOURCE .. self.socketGroupList[i].displayLabel) or ""
		end
	end
	-- Level label (shown after skill dropdown, before Enabled)
	self.controls['skillLevel-'..i] = new("LabelControl", { "LEFT", self.controls['skill-' .. i], "RIGHT" }, 6, 0, 38, 16)
	self.controls['skillLevel-'..i].shown = function()
		return self.socketGroupList[i] ~= nil
	end
	self.controls['skillLevel-'..i].label = function()
		local baseLvl = self:GetUsedSkillPoints(i)
		local totalBonus = self:GetTotalSkillLevelBonus(i)
		if totalBonus > 0 then
			return "^7Lv " .. baseLvl .. "^x4DD9FF+" .. totalBonus
		end
		return "^7Lv " .. baseLvl
	end
	-- Points label (always shown with fixed width to keep Enabled checkbox anchored correctly)
	self.controls['skillPts-'..i] = new("LabelControl", { "LEFT", self.controls['skillLevel-'..i], "RIGHT" }, 4, 0, 80, 16)
	-- Note: always shown (even if empty) so groupEnabled anchor position is stable
	self.controls['skillPts-'..i].shown = function()
		return self.socketGroupList[i] ~= nil
	end
	self.controls['skillPts-'..i].label = function()
		local sg = self.socketGroupList[i]
		if not sg or not sg.grantedEffect or not sg.grantedEffect.treeId then
			return ""  -- Empty but width still reserved, keeping Enabled in place
		end
		local used = self:GetUsedSkillPoints(i)
		local maxPts = self:GetMaxSkillPoints(i)
		local rem = maxPts - used
		if rem > 0 then
			return "^x4DD9FF" .. rem .. " pts left"
		elseif rem == 0 then
			return "^70 pts left"
		else
			return "^xFF6666" .. math.abs(rem) .. " pts over"
		end
	end
	-- Enabled checkbox
	-- NOTE: CheckBoxControl draws its label to the LEFT of the box (RIGHT_X aligned at x-5).
	-- So we must add the label width to the x-offset to prevent overlap with skillPts.
	-- labelWidth = DrawStringWidth(size-4=16, "VAR", "Enabled:") + 5 ≈ 70px
	local enabledLabelW = 70
	self.controls['groupEnabled-'..i] = new("CheckBoxControl", { "LEFT", self.controls['skillPts-'..i], "RIGHT" }, enabledLabelW + 6, 0, 20, "Enabled:", function(state)
		self.socketGroupList[i].enabled = state
		self:AddUndoState()
		self.build.buildFlag = true
	end)
	self.controls['groupEnabled-'..i].shown = function()
			return self.socketGroupList[i] ~= nil
	end
	self.controls['includeInFullDPS-'..i] = new("CheckBoxControl", { "LEFT", self.controls['groupEnabled-'..i], "RIGHT" }, 145, 0, 20, "Include in Full DPS:", function(state)
		self.socketGroupList[i].includeInFullDPS = state
		self:AddUndoState()
		self.build.buildFlag = true
	end)
	self.controls['includeInFullDPS-'..i].shown = function()
			return self.socketGroupList[i] ~= nil
	end
	if i > 5 then
		self.controls['includeInFullDPS-'..i].enabled = false
	end
end

-- parse real gem name and quality by omitting the first word if alt qual is set
function SkillsTabClass:GetBaseNameAndQuality(gemTypeLine, quality)
	gemTypeLine = sanitiseText(gemTypeLine)
	-- if quality is default or nil check the gem type line if we have alt qual by comparing to the existing list
	if gemTypeLine and (quality == nil or quality == "" or quality == "Default") then
		local firstword, otherwords = gemTypeLine:match("(%w+)%s(.+)")
		if firstword and otherwords then
			for _, entry in ipairs(alternateGemQualityList) do
				if firstword == entry.label then
					-- return the gem name minus <altqual> without a leading space and the new resolved type
					if entry.type == nil or entry.type == "" then
						entry.type = "Default"
					end
					return otherwords, entry.type
				end
			end
		end
	end
	-- no alt qual found, return gemTypeLine as is and either existing quality or Default if none is set
	return gemTypeLine, quality or "Default"
end

function SkillsTabClass:LoadSkill(node, skillSetId)
	if node.elem ~= "Skill" then
		return
	end

	local socketGroup = { }
	socketGroup.enabled = node.attrib.active == "true" or node.attrib.enabled == "true"
	socketGroup.includeInFullDPS = node.attrib.includeInFullDPS and node.attrib.includeInFullDPS == "true"
	socketGroup.groupCount = tonumber(node.attrib.groupCount)
	socketGroup.label = node.attrib.label
	socketGroup.slot = node.attrib.slot
	socketGroup.source = node.attrib.source
	socketGroup.mainActiveSkill = tonumber(node.attrib.mainActiveSkill) or 1
	socketGroup.mainActiveSkillCalcs = tonumber(node.attrib.mainActiveSkillCalcs) or 1
	socketGroup.gemList = { }
	local skillId = node.attrib.skillId
	local grantedEffect = self.build.data.skills[skillId]
	socketGroup.skillId = skillId
	socketGroup.grantedEffect = grantedEffect
	self:ProcessSocketGroup(socketGroup)
	if node.attrib.index then
	    self.skillSets[skillSetId].socketGroupList[tonumber(node.attrib.index)] = socketGroup
	else
		t_insert(self.skillSets[skillSetId].socketGroupList, socketGroup)
	end
end

function SkillsTabClass:Load(xml, fileName)
	self.activeSkillSetId = 0
	self.skillSets = { }
	self.skillSetOrderList = { }
	for _, node in ipairs(xml) do
		if node.elem == "Skill" then
			-- Old format, initialize skill sets if needed
			if not self.skillSetOrderList[1] then
				self.skillSetOrderList[1] = 1
				self:NewSkillSet(1)
			end
			self:LoadSkill(node, 1)
		end

		if node.elem == "SkillSet" then
			local skillSet = self:NewSkillSet(tonumber(node.attrib.id))
			skillSet.title = node.attrib.title
			t_insert(self.skillSetOrderList, skillSet.id)
			for _, subNode in ipairs(node) do
				self:LoadSkill(subNode, skillSet.id)
			end
		end
	end
	self:SetActiveSkillSet(tonumber(xml.attrib.activeSkillSet) or 1)
	self:ResetUndo()
end

function SkillsTabClass:Save(xml)
	xml.attrib = {
		activeSkillSet = tostring(self.activeSkillSetId),
		defaultGemLevel = self.defaultGemLevel,
		defaultGemQuality = tostring(self.defaultGemQuality),
		sortGemsByDPS = tostring(self.sortGemsByDPS),
		showSupportGemTypes = self.showSupportGemTypes,
		sortGemsByDPSField = self.sortGemsByDPSField,
		showAltQualityGems = tostring(self.showAltQualityGems)
	}
	for _, skillSetId in ipairs(self.skillSetOrderList) do
		local skillSet = self.skillSets[skillSetId]
		local child = { elem = "SkillSet", attrib = { id = tostring(skillSetId), title = skillSet.title } }
		t_insert(xml, child)

		for index, socketGroup in pairsSortByKey(skillSet.socketGroupList) do
			local node = { elem = "Skill", attrib = {
				index = tostring(index),
				enabled = tostring(socketGroup.enabled),
				includeInFullDPS = tostring(socketGroup.includeInFullDPS),
				groupCount = socketGroup.groupCount ~= nil and tostring(socketGroup.groupCount),
				label = socketGroup.label,
				slot = socketGroup.slot,
				source = socketGroup.source,
				mainActiveSkill = tostring(socketGroup.mainActiveSkill),
				mainActiveSkillCalcs = tostring(socketGroup.mainActiveSkillCalcs),
				skillId = socketGroup.skillId,
			} }
			t_insert(child, node)
		end
	end
end

-- Lazy-load a sprite from Assets/tree/ directory
function SkillsTabClass:GetSpriteHandle(spriteName)
	local key = "sprite_" .. spriteName
	if not self.spriteHandles[key] then
		self.spriteHandles[key] = NewImageHandle()
		self.spriteHandles[key]:Load("Assets/tree/" .. spriteName .. ".png")
	end
	return self.spriteHandles[key]
end

-- Get skill icon handle using root node icon (same pattern as TreeTab)
-- treeId: the skill tree ID (e.g. "av75ch")
-- useSpec: if true, load pointy-top hex (-spec) version for spec slots
-- Returns image handle or nil
function SkillsTabClass:GetSkillIconFromTree(treeId, useSpec)
	if not treeId then return nil end
	local suffix = useSpec and "_spec" or ""
	local cacheKey = "skillicon_" .. treeId .. suffix
	if self.spriteHandles[cacheKey] ~= nil then
		return self.spriteHandles[cacheKey]
	end
	-- Look up root node to find icon name
	local spec = self.build.spec
	local rootNodeId = treeId .. "-0"
	local rootNode = spec.nodes[rootNodeId]
	local iconName = rootNode and rootNode.icon or nil
	if not iconName then
		self.spriteHandles[cacheKey] = false
		return nil
	end
	local baseName = iconName:gsub("%-root$", ""):gsub("%-hex$", "")
	local handle = NewImageHandle()
	local w, h
	if useSpec then
		-- Try pointy-top hex version for spec slots
		handle:Load("TreeData/sprites/" .. baseName .. "-spec.png")
		w, h = handle:ImageSize()
		if not w or w == 0 then
			-- Fallback to hex version (same pointy-top shape)
			handle:Load("TreeData/sprites/" .. baseName .. "-hex.png")
			w, h = handle:ImageSize()
		end
		if not w or w == 0 then
			-- Fallback to circle version
			handle:Load("TreeData/sprites/" .. baseName .. ".png")
		end
		-- Note: -root.png is flat-top hex (wrong shape for spec slots), not used here
	else
		-- Square version for skill grid, fallback to circle, then hex, then root
		handle:Load("TreeData/sprites/" .. baseName .. "-sq.png")
		w, h = handle:ImageSize()
		if not w or w == 0 then
			handle:Load("TreeData/sprites/" .. baseName .. ".png")
			w, h = handle:ImageSize()
		end
		if not w or w == 0 then
			handle:Load("TreeData/sprites/" .. baseName .. "-hex.png")
			w, h = handle:ImageSize()
		end
		if (not w or w == 0) and baseName ~= iconName then
			handle:Load("TreeData/sprites/" .. iconName .. ".png")
		end
	end
	self.spriteHandles[cacheKey] = handle
	return handle
end

-- Find which slot a skill is assigned to (nil if not assigned)
function SkillsTabClass:FindSkillSlot(skillId)
	for i = 1, 5 do
		local sg = self.socketGroupList[i]
		if sg and sg.skillId == skillId then
			return i
		end
	end
	return nil
end

-- Find first empty spec slot
function SkillsTabClass:FindEmptySlot()
	for i = 1, 5 do
		if not self.socketGroupList[i] then
			return i
		end
	end
	return nil
end

-- Count points spent in a specific mastery tree (same logic as TreeTab)
function SkillsTabClass:GetMasteryPointsSpent(masteryIndex)
	local spec = self.build.spec
	local className = spec.curClassName or ""
	local pts = 0
	for nodeId, node in pairs(spec.allocNodes) do
		if nodeId:match("^" .. className) and node.mastery == masteryIndex then
			if node.type ~= "ClassStart" and node.type ~= "AscendClassStart" then
				pts = pts + (node.alloc or 0)
			end
		end
	end
	return pts
end

-- Damage type display priority order
local DAMAGE_TYPE_ORDER = {
	physical = 1, fire = 2, cold = 3, lightning = 4, necrotic = 5,
	poison = 6, void = 7,
}

-- Damage type data per treeId (from LETools: base tags / minion tags / skill tree conversion tags)
-- base = native damage types, conv = types available via skill tree conversion (shown gray)
local TREE_ID_DAMAGE_TYPES = {
	-- Primalist base
	["sw43"]   = { base = { "physical" },              conv = { "lightning" } },            -- Swipe
	["wo42"]   = { base = { "physical" },              conv = { "cold", "lightning" } },    -- Summon Wolf
	["ga2st"]  = { base = { "lightning" },             conv = { "physical", "cold" } },     -- Gathering Storm
	["fl13"]   = { base = { "physical" },              conv = { "lightning" } },            -- Fury Leap
	["th39"]   = { base = { "physical" },              conv = { "cold" } },                -- Summon Thorn Totem
	["ts85i"]  = { base = { "physical", "lightning", "cold" }, conv = {} },                -- Tempest Strike
	["mas54"]  = { base = { "cold" },                  conv = { "physical" } },            -- Maelstrom
	["uph41"]  = { base = { "physical" },              conv = { "fire", "cold", "lightning" } }, -- Upheaval
	-- Primalist passive unlock
	["eb5656"] = { base = {},                          conv = {} },                        -- Eterra's Blessing
	["wc57"]   = { base = {},                          conv = { "physical", "cold" } },    -- Warcry
	["ssc50"]  = { base = { "lightning" },             conv = { "cold" } },                -- Summon Storm Crows
	["st31et"] = { base = { "physical", "poison" },    conv = { "cold" } },                -- Serpent Strike
	-- Beastmaster
	["be36ar"] = { base = { "physical" },              conv = { "lightning" } },            -- Summon Bear
	["sc36pi"] = { base = { "physical", "poison" },    conv = { "lightning", "cold" } },   -- Summon Scorpion
	["sf37"]   = { base = {},                          conv = {} },                        -- Summon Frenzy Totem
	["sa36oh"] = { base = { "physical" },              conv = { "cold" } },                -- Summon Sabertooth
	["srtor"]  = { base = { "physical" },              conv = { "fire" } },                -- Summon Raptor
	-- Shaman
	["to50"]   = { base = { "physical" },              conv = { "fire", "lightning" } },   -- Tornado
	["eq5s"]   = { base = { "physical" },              conv = { "fire", "lightning" } },   -- Earthquake
	["av75ch"] = { base = { "physical", "cold" },      conv = {} },                        -- Avalanche
	["st38ml"] = { base = { "lightning" },             conv = { "cold" } },                -- Summon Storm Totem
	-- Druid
	["sf5rd"]  = { base = { "physical" },              conv = { "cold" } },                -- Spriggan Form
	["sp38"]   = { base = { "physical" },              conv = { "cold" } },                -- Summon Spriggan
	["sbf4m"]  = { base = { "physical" },              conv = { "cold" } },                -- Swarmblade Form
	["er6no"]  = { base = { "physical" },              conv = { "cold", "poison" } },      -- Entangling Roots
	["wb8fo"]  = { base = { "physical" },              conv = { "lightning" } },           -- Werebear Form
	-- Mage base
	["lb23il"] = { base = { "lightning" },             conv = { "cold" } },                -- Lightning Blast
	["fi9"]    = { base = { "fire" },                  conv = { "lightning" } },            -- Fireball
	["ms26"]   = { base = { "lightning" },             conv = {} },                        -- Mana Strike
	["en6"]    = { base = { "fire", "cold", "lightning" }, conv = {} },                    -- Elemental Nova
	["sw31a"]  = { base = { "cold" },                  conv = { "lightning" } },            -- Snap Freeze
	["gl14"]   = { base = { "cold" },                  conv = {} },                        -- Glacier
	["dig5"]   = { base = { "lightning", "fire" },     conv = {} },                        -- Disintegrate
	["fw3d"]   = { base = { "fire" },                  conv = { "lightning", "cold" } },   -- Flame Ward
	["frc87w"] = { base = { "cold" },                  conv = { "lightning", "fire" } },   -- Frost Claw
	["st47ic"] = { base = { "lightning" },             conv = {} },                        -- Static
	["vo54"]   = { base = { "fire" },                  conv = { "cold" } },                -- Volcanic Orb
	["vm53dx"] = { base = {},                          conv = { "lightning" } },            -- Focus
	["te44"]   = { base = {},                          conv = {} },                        -- Teleport
	["me27"]   = { base = { "fire" },                  conv = {} },                        -- Meteor
	-- Sorcerer
	["so35a"]  = { base = { "lightning" },             conv = { "cold" } },                -- Static Orb
	["ib5g3"]  = { base = { "cold" },                  conv = {} },                        -- Ice Barrage
	["arcas"]  = { base = {},                          conv = { "lightning" } },            -- Arcane Ascendance
	["bh2"]    = { base = { "cold" },                  conv = { "fire" } },                -- Black Hole
	-- Spellblade
	["fr11mv"] = { base = { "fire" },                  conv = { "lightning" } },            -- Flame Reave
	["sb44eQ"] = { base = {},                          conv = {} },                        -- Enchant Weapon
	["ss3tre"] = { base = { "cold" },                  conv = { "lightning" } },            -- Shatter Strike
	["f1b4d"]  = { base = { "fire" },                  conv = { "lightning" } },            -- Firebrand
	["su5g3"]  = { base = { "lightning" },             conv = { "fire", "cold" } },        -- Surge
	-- Runemaster
	["fl71ds"] = { base = { "fire" },                  conv = { "cold", "lightning" } },   -- Flame Rush
	["fr4wl"]  = { base = { "cold" },                  conv = { "fire", "lightning" } },   -- Frost Wall
	["fb8fe"]  = { base = { "fire", "cold", "lightning" }, conv = {} },                    -- Runebolt
	["gy2dm"]  = { base = { "lightning" },             conv = { "fire" } },                -- Glyph of Dominion
	["rn7iv"]  = { base = { "fire", "cold", "lightning" }, conv = {} },                    -- Runic Invocation
	-- Sentinel base
	["sndr1"]  = { base = { "physical" },              conv = { "void" } },                -- Rive
	["va53st"] = { base = { "physical" },              conv = { "fire", "void" } },        -- Warpath
	["lu25ng"] = { base = { "physical" },              conv = { "fire", "void" } },        -- Lunge
	["ht16aw"] = { base = { "physical" },              conv = { "void" } },                -- Hammer Throw
	["gs15de"] = { base = { "physical" },              conv = { "fire", "void" } },        -- Vengeance
	["re82ke"] = { base = { "physical" },              conv = {} },                        -- Rebuke
	["sr31hu"] = { base = { "physical" },              conv = { "void" } },                -- Shield Rush
	["multis"] = { base = { "physical" },              conv = {} },                        -- Multistrike
	["sm87r4"] = { base = { "fire" },                  conv = { "lightning", "void" } },   -- Smite
	["sb4h"]   = { base = { "physical" },              conv = { "fire" } },                -- Shield Bash
	["javeli"] = { base = { "physical" },              conv = { "lightning" } },           -- Javelin
	["v01cv"]  = { base = { "void" },                  conv = { "physical", "fire" } },    -- Void Cleave
	-- Void Knight
	["vr53sl"] = { base = { "void" },                  conv = { "fire" } },                -- Volatile Reversal
	["ab0lh"]  = { base = { "void" },                  conv = { "fire" } },                -- Abyssal Echoes
	["do5vr"]  = { base = { "void" },                  conv = {} },                        -- Devouring Orb
	["es6ai"]  = { base = { "void" },                  conv = {} },                        -- Erasing Strike
	["an0my"]  = { base = { "void" },                  conv = {} },                        -- Anomaly
	-- Forge Guard
	["st31io"] = { base = { "physical" },              conv = { "fire" } },                -- Shield Throw
	["ma6hdr"] = { base = { "physical" },              conv = { "fire" } },                -- Manifest Armor
	["fs3e3"]  = { base = { "physical" },              conv = { "fire" } },                -- Forge Strike
	["rs31hi"] = { base = {},                          conv = { "fire" } },                -- Ring of Shields
	["st4th"]  = { base = { "physical", "fire" },      conv = {} },                        -- Smelter's Wrath
	-- Paladin
	["hh7pa3"] = { base = {},                          conv = {} },                        -- Healing Hands
	["si4lgl"] = { base = {},                          conv = {} },                        -- Sigils of Hope
	["pa67ju"] = { base = { "fire" },                  conv = {} },                        -- Judgement
	["ah443"]  = { base = {},                          conv = {} },                        -- Holy Aura
	-- Acolyte base
	["rb31pl"] = { base = { "physical" },              conv = { "necrotic" } },            -- Rip Blood
	["ss37kl"] = { base = { "physical" },              conv = { "cold", "fire" } },        -- Summon Skeleton
	["bp2nk"]  = { base = { "physical" },              conv = { "cold" } },                -- Marrow Shards
	["ws54hm"] = { base = { "necrotic" },              conv = { "poison" } },              -- Wandering Spirits
	["ha84"]   = { base = { "necrotic" },              conv = { "physical", "cold" } },    -- Harvest
	["bc53"]   = { base = { "physical" },              conv = { "necrotic" } },            -- Bone Curse
	["ts50pl"] = { base = { "physical" },              conv = { "necrotic" } },            -- Transplant
	["svz81"]  = { base = { "physical", "fire" },      conv = { "necrotic" } },            -- Summon Volatile Zombie
	["hs18gu"] = { base = { "necrotic" },              conv = { "fire" } },                -- Hungering Souls
	["bg36nl"] = { base = { "physical" },              conv = { "cold", "fire" } },        -- Summon Bone Golem
	["sp5g2"]  = { base = { "necrotic" },              conv = {} },                        -- Spirit Plague
	["is40"]   = { base = { "fire" },                  conv = { "physical" } },            -- Infernal Shade
	-- Necromancer
	["sm4g"]   = { base = { "necrotic" },              conv = { "cold", "fire" } },        -- Summon Skeletal Mage
	["sf31rc"] = { base = { "physical" },              conv = { "fire" } },                -- Sacrifice
	["sw42ih"] = { base = { "physical" },              conv = { "fire", "necrotic", "poison" } }, -- Summon Wraith
	["ds4d3"]  = { base = { "necrotic" },              conv = {} },                        -- Dread Shade
	["aa710"]  = { base = { "physical" },              conv = {} },                        -- Assemble Abomination
	-- Lich
	["dl73"]   = { base = { "necrotic" },              conv = { "poison" } },              -- Drain Life
	["ad0ry"]  = { base = { "poison" },                conv = { "physical", "cold" } },    -- Aura of Decay
	["fl44"]   = { base = { "physical" },              conv = { "cold", "necrotic" } },    -- Flay
	["ds34l"]  = { base = { "necrotic" },              conv = { "physical", "cold" } },    -- Death Seal
	["rf1azz"] = { base = {},                          conv = { "physical", "cold", "necrotic", "poison" } }, -- Reaper Form
	-- Warlock
	["ch4bo"]  = { base = { "fire", "necrotic" },      conv = { "physical", "cold" } },   -- Chaos Bolts
	["gh0fl"]  = { base = { "fire", "necrotic" },      conv = { "physical" } },            -- Ghostflame
	["fe8at"]  = { base = { "necrotic" },              conv = { "physical" } },            -- Soul Feast
	["pr5fm"]  = { base = { "necrotic" },              conv = { "physical", "fire" } },    -- Profane Veil
	["ch0fs"]  = { base = { "fire", "necrotic" },      conv = { "physical", "poison" } },  -- Chthonic Fissure
	-- Rogue base
	["flur3"]  = { base = { "physical" },              conv = {} },                        -- Flurry
	["srk21"]  = { base = { "physical" },              conv = { "lightning" } },           -- Shurikens
	["sh4re"]  = { base = { "physical" },              conv = { "lightning" } },           -- Shadow Rend
	["aacfl"]  = { base = { "physical", "poison" },    conv = { "fire" } },                -- Acid Flask
	["pun22"]  = { base = { "physical" },              conv = {} },                        -- Puncture
	["shiif"]  = { base = {},                          conv = {} },                        -- Shift
	["cstri"]  = { base = { "fire" },                  conv = {} },                        -- Cinder Strike
	["deeco"]  = { base = { "fire" },                  conv = { "cold" } },                -- Decoy
	["smbmb"]  = { base = {},                          conv = {} },                        -- Smoke Bomb
	["bl5st"]  = { base = { "physical" },              conv = { "cold", "poison" } },      -- Bladestorm Throw
	["ba1574"] = { base = { "physical" },              conv = {} },                        -- Ballista
	["ub5d9"]  = { base = { "physical" },              conv = { "cold", "fire", "poison" } }, -- Umbral Blades
	-- Bladedancer
	["dagg3"]  = { base = { "physical" },              conv = {} },                        -- Shadow Cascade
	["sync5"]  = { base = { "physical" },              conv = {} },                        -- Synchronized Strike
	["dacn33"] = { base = { "physical" },              conv = { "poison" } },              -- Dancing Strikes
	["mira59"] = { base = { "physical" },              conv = { "lightning" } },            -- Lethal Mirage
	-- Marksman
	["detar"]  = { base = { "lightning" },             conv = { "cold", "fire", "poison" } }, -- Detonating Arrow
	["mush9"]  = { base = { "physical" },              conv = {} },                        -- Multishot
	["dqv5"]   = { base = {},                          conv = {} },                        -- Dark Quiver
	["htsk5"]  = { base = { "physical" },              conv = { "cold", "fire" } },        -- Heartseeker
	["exvol8"] = { base = { "physical" },              conv = { "fire", "cold", "poison" } }, -- Hail of Arrows
	-- Falconer
	["ex4tp"]  = { base = { "fire" },                  conv = { "cold", "lightning" } },   -- Explosive Trap
	["ne01t"]  = { base = { "physical" },              conv = { "lightning", "poison" } },  -- Net
	["aa989"]  = { base = { "physical" },              conv = {} },                        -- Aerial Assault
	["db992"]  = { base = { "physical" },              conv = {} },                        -- Dive Bomb
	["falc0"]  = { base = { "physical" },              conv = { "cold", "lightning" } },   -- Falconry
}

-- Get damage types for a skill by treeId (primary) or skillId (fallback to skills.json stats)
-- Returns: array of { type = "fire", isBase = true/false } entries, sorted by DAMAGE_TYPE_ORDER
function SkillsTabClass:GetSkillDamageTypes(skillId, treeId)
	local result = {}
	-- Primary: use LETools-sourced treeId lookup with base/conv separation
	if treeId and TREE_ID_DAMAGE_TYPES[treeId] then
		local data = TREE_ID_DAMAGE_TYPES[treeId]
		for _, dt in ipairs(data.base or {}) do
			t_insert(result, { type = dt, isBase = true })
		end
		for _, dt in ipairs(data.conv or {}) do
			t_insert(result, { type = dt, isBase = false })
		end
		table.sort(result, function(a, b)
			return (DAMAGE_TYPE_ORDER[a.type] or 99) < (DAMAGE_TYPE_ORDER[b.type] or 99)
		end)
		return result
	end
	-- Fallback: extract from skills.json stats (all treated as base)
	local skillData = self.build.data.skills[skillId]
	if skillData and skillData.stats then
		local seen = {}
		for key, _ in pairs(skillData.stats) do
			local dt = key:match("_base_(%w+)_damage$")
			if dt and not seen[dt] then
				seen[dt] = true
				t_insert(result, { type = dt, isBase = true })
			end
		end
	end
	table.sort(result, function(a, b)
		return (DAMAGE_TYPE_ORDER[a.type] or 99) < (DAMAGE_TYPE_ORDER[b.type] or 99)
	end)
	return result
end

function SkillsTabClass:Draw(viewPort, inputEvents)
	self.x = viewPort.x
	self.y = viewPort.y
	self.width = viewPort.width
	self.height = viewPort.height

	-- Layout constants (needed before input processing)
	local slotBarY = viewPort.y + 10
	local contentY = slotBarY + SLOT_ROW_HEIGHT
	local bottomBarH = 28

	-- Hide all legacy controls (including scroll bars - new UI doesn't scroll)
	for key, ctrl in pairs(self.controls) do
		ctrl.shown = false
	end

	-- Show and position the active search control in the bottom bar
	local searchY = viewPort.y + viewPort.height - bottomBarH + 4
	if self.viewMode == "tree" then
		local ctrl = self.controls.skillTreeSearch
		ctrl.shown = true
		ctrl.x = viewPort.x + 4
		ctrl.y = searchY
		if not ctrl.hasFocus then
			ctrl:SetText(self.skillTreeViewer.searchStr)
		end
	else
		local ctrl = self.controls.skillOverviewSearch
		ctrl.shown = true
		ctrl.x = viewPort.x + 4
		ctrl.y = searchY
	end

	-- Handle ESC: tree -> overview; CTRL+F: focus search
	for id, event in ipairs(inputEvents) do
		if event.type == "KeyDown" then
			if event.key == "ESCAPE" and self.viewMode == "tree" then
				self.viewMode = "overview"
				inputEvents[id] = nil
			elseif event.key == "z" and IsKeyDown("CTRL") then
				self:Undo()
				self.build.buildFlag = true
			elseif event.key == "y" and IsKeyDown("CTRL") then
				self:Redo()
				self.build.buildFlag = true
			elseif event.key == "f" and IsKeyDown("CTRL") then
				if self.viewMode == "tree" then
					self:SelectControl(self.controls.skillTreeSearch)
				else
					self:SelectControl(self.controls.skillOverviewSearch)
				end
				inputEvents[id] = nil
			end
		end
	end

	self:ProcessControlsInput(inputEvents, viewPort)

	main:DrawBackground(viewPort)

	-- Detect class change and reset all skill slots
	local curClassId = self.build.spec.curClassId
	if self.lastClassId and self.lastClassId ~= curClassId then
		for i = 1, 5 do
			self:SelSkill(i, nil)
		end
		self.viewMode = "overview"
		self.viewingTreeSlot = nil
		self.selectedSlotIndex = nil
	end
	self.lastClassId = curClassId

	-- Ensure socket groups are initialised for all 5 slots
	local skillList = { { label = "None" } }
	for _, v in ipairs(self.build.spec.curClass.skills) do
		t_insert(skillList, v)
	end
	for i = 1, 5 do
		if not self.controls['skill-' .. i] then
			self:InitSkillControl(i)
		end
		local sg = self.socketGroupList[i]
		self.controls['skill-' .. i].list = skillList
		self.controls['skill-' .. i]:SelByValue(sg and sg.skillId, "name")
		if sg then
			self.controls['groupEnabled-' .. i].state = sg.enabled
			self.controls['includeInFullDPS-' .. i].state = sg.includeInFullDPS and sg.enabled
		end
	end

	-- Rebuild overview search cache when search string changes
	if self.skillOverviewSearchCache.str ~= self.skillOverviewSearchStr then
		self:BuildOverviewSearchResults(self.build, self.skillOverviewSearchStr)
	end

	-- Draw tree/overview first so slots always render on top
	if self.viewMode == "tree" and self.viewingTreeSlot then
		self:DrawSkillTree(viewPort, inputEvents, contentY)
	else
		self:DrawSkillOverview(viewPort, inputEvents, contentY)
	end

	-- Draw spec slots on top of everything (high draw layer)
	SetDrawLayer(nil, 150)
	self:DrawSpecSlots(viewPort, inputEvents, slotBarY)
	SetDrawLayer(nil, 0)

	-- Draw bottom search bar (main layer 1, same as TreeTab footer)
	SetDrawLayer(1)
	SetDrawColor(0.05, 0.05, 0.05)
	DrawImage(nil, viewPort.x, viewPort.y + viewPort.height - bottomBarH, viewPort.width, bottomBarH)
	SetDrawColor(0.85, 0.85, 0.85)
	DrawImage(nil, viewPort.x, viewPort.y + viewPort.height - bottomBarH - 4, viewPort.width, 4)
	self:DrawControls(viewPort)
end

-- Skills that legitimately allow multiple simultaneous conversions from the same damage type.
-- For all others, the last-allocated conversion per fromType wins.
local MULTI_CONV_TREES = {
	["ex4tp"] = true,  -- Explosive Trap (fire -> cold AND fire -> lightning)
}

-- Get damage types for a spec slot, accounting for allocated conversion nodes.
-- Returns array of {type, isBase} sorted by DAMAGE_TYPE_ORDER.
function SkillsTabClass:GetDynamicDamageTypes(slotIndex)
	local sg = self.socketGroupList[slotIndex]
	if not sg or not sg.grantedEffect or not sg.grantedEffect.treeId then return {} end
	return self:GetDynamicDamageTypesByTreeId(sg.grantedEffect.treeId)
end

-- Same as GetDynamicDamageTypes but keyed by treeId directly. Lets callers
-- (e.g. PassiveTreeView root-node tooltip) compute the conversion-aware
-- damage type list without needing a slot index.
-- Compute tree-node-injected SkillType bit additions for a given treeId.
-- Mirrors calcs.getTreeTagAdditions but uses self.build.spec.allocNodes so
-- tooltip rendering (Scaling Tags row) can include these bits without an env.
-- See CalcActiveSkill.lua for the canonical pattern detection logic.
function SkillsTabClass:GetTreeTagAdditionsByTreeId(treeId)
	if not (treeId and self.build and self.build.spec and self.build.spec.allocNodes) then return 0 end
	local prefix = treeId .. "-"
	local adds = 0
	for nodeId, node in pairs(self.build.spec.allocNodes) do
		if nodeId:sub(1, #prefix) == prefix and node.stats then
			for _, stat in ipairs(node.stats) do
				if stat:lower():match("^%s*creates?%s+.+%s+totem%s*$") then
					adds = bit.bor(adds, 8192, 16384) -- Minion | Totem
				end
			end
		end
	end
	return adds
end

-- Returns true if a "Create X Totem" specialisation node is allocated for this
-- treeId. Callers use this to remap areaTagDisplay (Area moves from the cast's
-- Scaling Tags row onto the spawned totem's Minion Tags row, since the cast
-- itself no longer has range — the totem does).
function SkillsTabClass:IsTotemConvertedByTreeId(treeId)
	if not (treeId and self.build and self.build.spec and self.build.spec.allocNodes) then return false end
	local prefix = treeId .. "-"
	for nodeId, node in pairs(self.build.spec.allocNodes) do
		if nodeId:sub(1, #prefix) == prefix and node.stats then
			for _, stat in ipairs(node.stats) do
				if stat:lower():match("^%s*creates?%s+.+%s+totem%s*$") then
					return true
				end
			end
		end
	end
	return false
end

function SkillsTabClass:GetDynamicDamageTypesByTreeId(treeId)
	if not treeId then return {} end

	-- Build base/conv sets from static table
	local baseSet, convSet = {}, {}
	local staticData = TREE_ID_DAMAGE_TYPES[treeId]
	if staticData then
		for _, t in ipairs(staticData.base or {}) do baseSet[t] = true end
		for _, t in ipairs(staticData.conv or {}) do convSet[t] = true end
	end

	-- Scan allocated nodes for conversion descriptions.
	-- convMap[fromType] = toType  (last-wins for regular skills)
	-- For MULTI_CONV_TREES, collect all pairs instead.
	local TYPE_NAMES = { "physical", "fire", "cold", "lightning", "void", "necrotic", "poison" }
	local TYPE_SET   = {}
	for _, t in ipairs(TYPE_NAMES) do TYPE_SET[t] = true end
	local isMultiConv = MULTI_CONV_TREES[treeId]
	local convMap   = {}   -- fromType -> toType  (single, last wins)
	local multiList = {}   -- {fromType, toType} pairs (multi-conv skills)
	-- addSet: types forced into baseSet *after* conversions resolve. Captures
	-- "split-effect" nodes like Black Hole's Binary System ("One deals fire
	-- damage and the other deals cold damage") that simultaneously surface
	-- multiple damage types as base, without converting away from the original.
	-- Per LE_datamining findings, per-node mutator state isn't serialized; we
	-- pattern-match the description as a fallback until a Ghidra-decomp
	-- node->mutator table is available.
	local addSet = {}

	for nodeId, node in pairs(self.build.spec.allocNodes) do
		if nodeId:match("^" .. treeId) and (node.maxPoints or 0) > 0 and node.description then
			for _, line in ipairs(node.description) do
				local lo = line:lower()
				for _, fromType in ipairs(TYPE_NAMES) do
					local toType = lo:match(fromType .. " damage is converted to%s+(%a+)")
					             or lo:match("base " .. fromType .. " damage is converted to%s+(%a+)")
					if toType and TYPE_SET[toType] then
						if isMultiConv then
							t_insert(multiList, { fromType, toType })
						else
							convMap[fromType] = toType  -- overwrite: last allocation wins
						end
					end
				end
				-- Split-effect detector: "one deals X damage and the other deals Y damage".
				-- Both X and Y are surfaced as base (added, not converted).
				do
					local oneType, otherType = lo:match("one deals (%a+) damage and the other deals (%a+) damage")
					if oneType and otherType and TYPE_SET[oneType] and TYPE_SET[otherType] then
						addSet[oneType] = true
						addSet[otherType] = true
					end
				end
				-- Whole-skill conversion phrasing used by some trees, e.g.
				-- Flame Ward fw3d-6: "Flame Ward is converted to Cold". This
				-- doesn't name the source damage type, so apply it to every
				-- type currently in baseSet (the skill's pre-conversion base).
				-- Filters:
				--  * skip lines that start with "if " — these are conditional
				--    references like fw3d-2 "If Flame Ward is converted to
				--    cold or lightning, then this damage increase is also
				--    converted." which describe downstream behaviour rather
				--    than performing a conversion.
				--  * skip lines that already matched the per-type pattern
				--    above (they contain " damage is converted to ").
				local wholeTo = lo:match("is converted to%s+(%a+)")
				if wholeTo and TYPE_SET[wholeTo]
				   and not lo:match("^%s*if%s")
				   and not lo:find(" damage is converted to ", 1, true) then
					for fromType in pairs(baseSet) do
						if fromType ~= wholeTo then
							if isMultiConv then
								t_insert(multiList, { fromType, wholeTo })
							else
								convMap[fromType] = wholeTo
							end
						end
					end
				end
			end
		end
	end

	-- Apply conversions
	local function applyConv(fromType, toType)
		if baseSet[fromType] then
			baseSet[fromType] = nil
			convSet[fromType] = true
		end
		if convSet[toType] then
			convSet[toType] = nil
			baseSet[toType] = true
		end
	end
	if isMultiConv then
		for _, pair in ipairs(multiList) do applyConv(pair[1], pair[2]) end
	else
		for fromType, toType in pairs(convMap) do applyConv(fromType, toType) end
	end
	-- Apply split-effect additions last: force each addSet entry into baseSet
	-- (re-promote from convSet if a prior conversion demoted it).
	for t in pairs(addSet) do
		if convSet[t] then convSet[t] = nil end
		baseSet[t] = true
	end

	-- Build sorted result
	local result = {}
	for t in pairs(baseSet) do t_insert(result, { type = t, isBase = true }) end
	for t in pairs(convSet) do t_insert(result, { type = t, isBase = false }) end
	table.sort(result, function(a, b)
		return (DAMAGE_TYPE_ORDER[a.type] or 99) < (DAMAGE_TYPE_ORDER[b.type] or 99)
	end)
	return result
end

-- Draw 5 hex specialization slots centered at top
function SkillsTabClass:DrawSpecSlots(viewPort, inputEvents, startY)
	local totalW = SLOT_SIZE * 5 + SLOT_GAP * 4
	local startX = viewPort.x + m_floor((viewPort.width - totalW) / 2)
	local cursorX, cursorY = GetCursorPos()

	self.hoverSlotIndex = nil

	for i = 1, 5 do
		local sx = startX + (i - 1) * (SLOT_SIZE + SLOT_GAP)
		local sy = startY
		local sg = self.socketGroupList[i]
		local isSelected = (i == self.selectedSlotIndex)
		local isHover = cursorX >= sx and cursorX < sx + SLOT_SIZE
			and cursorY >= sy and cursorY < sy + SLOT_SIZE

		if isHover then
			self.hoverSlotIndex = i
		end

		-- Background: empty slot sprite
		local emptyHandle = self:GetSpriteHandle("spec-slot-empty")
		if sg then
			SetDrawColor(1, 1, 1)
		else
			SetDrawColor(0.4, 0.4, 0.4)
		end
		DrawImage(emptyHandle, sx, sy, SLOT_SIZE, SLOT_SIZE)

		-- Skill icon if assigned (draw before border, use pointy-top hex)
		local slotIconHandle, slotTreeId
		if sg then
			slotTreeId = sg.grantedEffect and sg.grantedEffect.treeId or nil
			slotIconHandle = self:GetSkillIconFromTree(slotTreeId, true)
			if slotIconHandle then
				SetDrawColor(1, 1, 1)
				local iconOff = m_floor((SLOT_SIZE - ICON_SIZE) / 2)
				DrawImage(slotIconHandle, sx + iconOff, sy + iconOff, ICON_SIZE, ICON_SIZE)
			end
		end

		-- Border (drawn over icon, under level badge)
		local borderSprite = isSelected and "spec-slot-selected" or "spec-slot-border"
		local borderHandle = self:GetSpriteHandle(borderSprite)
		SetDrawColor(1, 1, 1)
		if isSelected then
			-- spec-slot-selected.png is 126x80 (wider hex border)
			-- Maintain aspect ratio (126:80 = 1.575:1), center over slot
			local selW = SLOT_SIZE + 16
			local selH = m_floor((SLOT_SIZE + 16) * 80 / 126)
			local selX = sx - m_floor((selW - SLOT_SIZE) / 2)
			local selY = sy + m_floor((SLOT_SIZE - selH) / 2) + 21
			DrawImage(borderHandle, selX, selY, selW, selH)
		else
			DrawImage(borderHandle, sx, sy, SLOT_SIZE, SLOT_SIZE)
		end

		-- Level badge (drawn on top of border, in front)
		if sg then
			local used = self:GetUsedSkillPoints(i)
			local maxPts = self:GetMaxSkillPoints(i)
			local rem = maxPts - used
			local lvlHandle = self:GetSpriteHandle("spec-slot-level")
			local lvlW = 50
			local lvlH = 34
			local lvlX = sx + m_floor((SLOT_SIZE - lvlW) / 2)
			local lvlY = sy + SLOT_SIZE - 30
			SetDrawColor(1, 1, 1)
			DrawImage(lvlHandle, lvlX, lvlY, lvlW, lvlH)
			-- Show effective skill level cap (Base 20 + all "+SkillLevel" bonuses),
			-- matching the in-game "Level of <Skill>" display rather than just the
			-- allocated tree points. The "remaining points" badge below still
			-- reflects unspent allocation, not unused cap.
			DrawString(lvlX + lvlW / 2, lvlY + 11, "CENTER_X", 12, "VAR", "^7" .. maxPts)

			-- Remaining points badge (blue square, top-right corner of slot)
			if rem > 0 then
				local badgeW = 18
				local badgeH = 18
				local badgeX = sx + SLOT_SIZE - badgeW + 0
				local badgeY = sy + 3
				SetDrawColor(0.05, 0.30, 0.80)
				DrawImage(nil, badgeX, badgeY, badgeW, badgeH)
				SetDrawColor(0.6, 0.80, 1.0)
				DrawImage(nil, badgeX,             badgeY,              badgeW, 1)
				DrawImage(nil, badgeX,             badgeY + badgeH - 1, badgeW, 1)
				DrawImage(nil, badgeX,             badgeY,              1, badgeH)
				DrawImage(nil, badgeX + badgeW - 1, badgeY,             1, badgeH)
				SetDrawColor(1, 1, 1)
				DrawString(badgeX + badgeW / 2, badgeY + 3, "CENTER_X", 11, "VAR", "^7" .. rem)
			end
		end

		-- Damage type icons below slot (horizontally centered)
		if sg then
			local dtTypes = self:GetDynamicDamageTypes(i)
			if #dtTypes > 0 then
				local dtSize = 14
				local dtGap = 2
				local totalDtW = #dtTypes * dtSize + (#dtTypes - 1) * dtGap
				local dtX = sx + m_floor((SLOT_SIZE - totalDtW) / 2)
				local dtY = sy + SLOT_SIZE + 4
				for _, dtInfo in ipairs(dtTypes) do
					local dtHandle = self:GetSpriteHandle("skill-damage-" .. dtInfo.type)
					if dtHandle then
						if dtInfo.isBase then
							SetDrawColor(1, 1, 1)
						else
							SetDrawColor(0.4, 0.4, 0.4)
						end
						DrawImage(dtHandle, dtX, dtY, dtSize, dtSize)
					end
					dtX = dtX + dtSize + dtGap
				end
			end
		end

		-- Buff skill enabled toggle (below damage type icons)
		if sg then
			local ge = sg.grantedEffect
			if ge and ge.skillTypes and ge.skillTypes[SkillType.Buff] then
				local TW, TH = 22, 12  -- slightly smaller than damage type icons
				local toggleY = sy + SLOT_SIZE + 4 + 14 + 2  -- below damage type icons
				local toggleX = sx + m_floor((SLOT_SIZE - TW) / 2)

				-- Draw iOS-style toggle sprite
				local isEnabled = sg.enabled ~= false
				local toggleSprite = self:GetSpriteHandle(isEnabled and "toggle_on" or "toggle_off")
				SetDrawColor(1, 1, 1)
				DrawImage(toggleSprite, toggleX, toggleY, TW, TH)

				-- Click detection
				local toggleHover = cursorX >= toggleX and cursorX < toggleX + TW
					and cursorY >= toggleY and cursorY < toggleY + TH
				if toggleHover then
					for id, event in ipairs(inputEvents) do
						if event.type == "KeyUp" and event.key == "LEFTBUTTON" then
							sg.enabled = not isEnabled
							self:AddUndoState()
							self.build.buildFlag = true
							inputEvents[id] = nil
						end
					end
				end
			end
		end

		-- Hover highlight
		if isHover then
			SetDrawColor(1, 1, 1, 0.15)
			DrawImage(nil, sx, sy, SLOT_SIZE, SLOT_SIZE)
		end

		-- Skill cap breakdown tooltip on hover (mirrors LETools layout):
		-- "Level of <Skill>: <cap>" header, "Base: 20" (LE base cap), then
		-- one line per +SkillLevel source. Total = 20 + sum(bonuses), rounded
		-- half-up to match GetMaxSkillPoints.
		if isHover and sg and sg.grantedEffect and sg.grantedEffect.treeId then
			local maxPts    = self:GetMaxSkillPoints(i)
			local skillName = sg.grantedEffect.name or "Skill"
			local breakdown = self.build.perSkillLevelBreakdown and self.build.perSkillLevelBreakdown[i]
			SetDrawLayer(nil, 200)
			local tooltip = new("Tooltip")
			tooltip:Clear()
			tooltip:AddLine(16, "^7Level of " .. skillName .. ": ^x60FF60" .. maxPts)
			tooltip:AddSeparator(8)
			tooltip:AddLine(14, "^7Base: ^x60A0FF20")
			if breakdown and #breakdown > 0 then
				for _, entry in ipairs(breakdown) do
					local v = entry.value
					local sign = v >= 0 and "+" or ""
					-- Show 1 decimal only if non-integer (Permanence may yield fractional)
					local valStr = (v == m_floor(v)) and tostring(m_floor(v)) or string.format("%.1f", v)
					tooltip:AddLine(14, "^7" .. (entry.source or "Unknown") .. ": ^x60A0FF" .. sign .. valStr)
				end
			end
			-- Scaling Tags row (damage types + combat class + attribute scalings).
			-- Use the conversion-aware damage type list so tree nodes that
			-- swap a skill's damage type (Surge -> Fire, Flame Ward -> Cold)
			-- are reflected in the tag display.
			local dynDt = self:GetDynamicDamageTypes(i)
			local extraFlags = sg.grantedEffect.treeId and self:GetTreeTagAdditionsByTreeId(sg.grantedEffect.treeId) or 0
			local areaOverride = sg.grantedEffect.treeId and self:IsTotemConvertedByTreeId(sg.grantedEffect.treeId) and 2 or nil
			local tagsLine = formatScalingTagsLine(getScalingTagsList(sg.grantedEffect, dynDt, extraFlags, areaOverride))
			local minionLine = formatMinionTagsLine(getMinionTagsList(sg.grantedEffect, nil, areaOverride))
			if tagsLine or minionLine then
				tooltip:AddSeparator(8)
				if tagsLine then tooltip:AddLine(14, tagsLine) end
				if minionLine then tooltip:AddLine(14, minionLine) end
			end
			tooltip:Draw(sx, sy, SLOT_SIZE, SLOT_SIZE, viewPort)
			SetDrawLayer(nil, 0)
		end

		-- Click handling
		if isHover then
			for id, event in ipairs(inputEvents) do
				if event.type == "KeyUp" then
					if event.key == "LEFTBUTTON" then
						if sg then
							-- Open tree view for filled slot
							self.viewMode = "tree"
							self.viewingTreeSlot = i
							self.selectedSlotIndex = i
							self.skillTreeViewer.selectedSkillIndex = i
							self.skillTreeViewer.skillBaseScale = nil
							self.skillTreeViewer.skillRefZoom = nil
						else
							-- Open skill selection overview for empty slot
							self.selectedSlotIndex = i
							self.viewMode = "overview"
							self.viewingTreeSlot = nil
						end
						inputEvents[id] = nil
					elseif event.key == "RIGHTBUTTON" then
						if sg then
							self:SelSkill(i, nil)
							self.build.spec:BuildAllDependsAndPaths()
							if self.viewMode == "tree" and self.viewingTreeSlot == i then
								self.viewMode = "overview"
								self.viewingTreeSlot = nil
							end
						end
						inputEvents[id] = nil
					end
				end
			end
		end
	end
end

-- Build a cache of treeId -> boolean for skills matching the search string.
-- Searches skill name, node names, and node description text.
function SkillsTabClass:BuildOverviewSearchResults(build, searchStr)
	local results = {}
	if not searchStr or searchStr == "" then
		self.skillOverviewSearchCache = { str = searchStr, results = results }
		return
	end

	local searchLower = searchStr:lower()
	local searchWords = {}
	for word in searchLower:gmatch("%S+") do
		t_insert(searchWords, word)
	end
	if #searchWords == 0 then
		self.skillOverviewSearchCache = { str = searchStr, results = results }
		return
	end

	local function matchesAll(text)
		if not text then return false end
		local ltext = text:lower()
		for _, word in ipairs(searchWords) do
			if not ltext:find(word, 1, true) then return false end
		end
		return true
	end

	for _, skill in ipairs(build.spec.curClass.skills) do
		local treeId = skill.treeId
		if treeId and not results[treeId] then
			-- Check skill name
			if matchesAll(skill.label) or matchesAll(skill.name) then
				results[treeId] = true
			else
				-- Check all nodes belonging to this skill tree
				for nodeId, node in pairs(build.spec.nodes) do
					if nodeId:match("^" .. treeId) then
						if matchesAll(node.dn) then
							results[treeId] = true
							break
						end
						if node.sd then
							for _, line in ipairs(node.sd) do
								if type(line) == "string" and matchesAll(line) then
									results[treeId] = true
									break
								end
							end
						end
						if results[treeId] then break end
					end
				end
			end
		end
	end

	self.skillOverviewSearchCache = { str = searchStr, results = results }
end

-- Draw skill selection grid (overview mode)
function SkillsTabClass:DrawSkillOverview(viewPort, inputEvents, startY)
	local spec = self.build.spec
	local className = spec.curClassName or ""
	local classData = MASTERY_SKILL_UNLOCKS[className]
	local cursorX, cursorY = GetCursorPos()

	self.hoverSkillId = nil

	-- Build a set of all treeIds that are in MASTERY_SKILL_UNLOCKS
	-- (passive unlock + mastery skills) so we can exclude them from base class
	local masteryTreeIdSet = {}
	if classData then
		for masteryIdx, skills in pairs(classData) do
			for _, entry in ipairs(skills) do
				masteryTreeIdSet[entry.treeId] = true
			end
		end
	end

	local leftSections = {}
	local rightSections = {}

	-- Left column top: Base class skills (character level unlock)
	-- = all skills in spec.curClass.skills that are NOT in MASTERY_SKILL_UNLOCKS
	local baseSkills = {}
	for _, skill in ipairs(spec.curClass.skills) do
		if not masteryTreeIdSet[skill.treeId] then
			t_insert(baseSkills, {
				name = skill.name,
				label = skill.label or skill.name,
				skillId = skill.name,
				treeId = skill.treeId,
				isUnlocked = true,
			})
		end
	end
	-- Sort base skills by LETools display order
	local orderTable = BASE_SKILL_ORDER[className]
	if orderTable and #baseSkills > 0 then
		local orderMap = {}
		for idx, treeId in ipairs(orderTable) do
			orderMap[treeId] = idx
		end
		table.sort(baseSkills, function(a, b)
			local oa = orderMap[a.treeId] or 9999
			local ob = orderMap[b.treeId] or 9999
			if oa ~= ob then return oa < ob end
			return (a.label or "") < (b.label or "")
		end)
	end
	if #baseSkills > 0 then
		t_insert(leftSections, { title = className:upper(), skills = baseSkills })
	end

	-- Build a treeId -> skill name lookup from curClass.skills (for correct skillId)
	local treeIdToSkillName = {}
	for _, skill in ipairs(spec.curClass.skills) do
		if skill.treeId then
			treeIdToSkillName[skill.treeId] = skill.name
		end
	end

	-- Left column bottom: Passive unlock skills (mastery index 0)
	-- Unlock based on points spent in base class passive tree
	local baseTreePts = self:GetMasteryPointsSpent(0)
	if classData and classData[0] then
		local passiveSkills = {}
		for _, entry in ipairs(classData[0]) do
			local requiredPts = entry.level or 0
			t_insert(passiveSkills, {
				name = entry.name,
				label = entry.label,
				skillId = treeIdToSkillName[entry.treeId] or entry.name,
				treeId = entry.treeId,
				level = entry.level,
				isUnlocked = baseTreePts >= requiredPts,
			})
		end
		if #passiveSkills > 0 then
			t_insert(leftSections, { title = "Passive Unlock", skills = passiveSkills })
		end
	end

	-- Right column: 3 masteries with actual names
	if classData then
		for m = 1, 3 do
			if classData[m] then
				local isMasterySelected = (spec.curAscendClassId == m)
				local masteryPts = isMasterySelected and self:GetMasteryPointsSpent(m) or 0
				local mSkills = {}
				for _, entry in ipairs(classData[m]) do
					local requiredPts = entry.level or 0
					t_insert(mSkills, {
						name = entry.name,
						label = entry.label,
						skillId = treeIdToSkillName[entry.treeId] or entry.name,
						treeId = entry.treeId,
						level = entry.level,
						locked = not isMasterySelected,
						isMastery = true,
						isUnlocked = isMasterySelected and (masteryPts >= requiredPts),
					})
				end
				if #mSkills > 0 then
					-- Get actual mastery name from class data
					local mName = "Mastery " .. m
					local ascendClass = spec.curClass.classes and spec.curClass.classes[m]
					if ascendClass and ascendClass.name then
						mName = ascendClass.name:upper()
					end
					t_insert(rightSections, { title = mName, skills = mSkills })
				end
			end
		end
	end

	-- Layout: two columns
	local colW = m_floor((viewPort.width - GRID_PAD * 3) / 2)
	local leftX = viewPort.x + GRID_PAD
	local rightX = viewPort.x + GRID_PAD + colW + GRID_PAD

	-- Draw left column (force 4 columns for base class layout)
	local ly = startY
	for _, section in ipairs(leftSections) do
		if #section.skills > 0 then
			ly = self:DrawSectionTitle(leftX, ly, colW, section.title)
			ly = self:DrawSkillGrid(leftX, ly, colW, section.skills, inputEvents, cursorX, cursorY, 4)
			ly = ly + 8
		end
	end

	-- Draw right column
	local ry = startY
	for _, section in ipairs(rightSections) do
		if #section.skills > 0 then
			ry = self:DrawSectionTitle(rightX, ry, colW, section.title)
			ry = self:DrawSkillGrid(rightX, ry, colW, section.skills, inputEvents, cursorX, cursorY)
			ry = ry + 8
		end
	end
end

-- Draw section title with divider
function SkillsTabClass:DrawSectionTitle(x, y, w, title)
	SetDrawColor(0.7, 0.6, 0.4)
	DrawString(x + 4, y + 4, "LEFT", 14, "VAR", "^xDDC080" .. title)
	-- Divider line
	SetDrawColor(0.3, 0.25, 0.15)
	DrawImage(nil, x, y + SECTION_HEADER_H - 2, w, 1)
	return y + SECTION_HEADER_H
end

-- Draw a grid of skill cells, return y after grid
function SkillsTabClass:DrawSkillGrid(x, y, w, skills, inputEvents, cursorX, cursorY, forceCols)
	local cols = forceCols or m_max(1, m_floor(w / CELL_W))
	local rows = m_ceil(#skills / cols)

	for idx, skill in ipairs(skills) do
		local col = (idx - 1) % cols
		local row = m_floor((idx - 1) / cols)
		local cx = x + col * CELL_W
		local cy = y + row * CELL_H

		local isHover = cursorX >= cx and cursorX < cx + CELL_W
			and cursorY >= cy and cursorY < cy + CELL_H
		local assignedSlot = self:FindSkillSlot(skill.skillId or skill.name)
		local isLocked = skill.locked

		-- Background on hover
		if isHover then
			self.hoverSkillId = skill.skillId or skill.name
			SetDrawColor(0.2, 0.2, 0.25, 0.5)
			DrawImage(nil, cx, cy, CELL_W, CELL_H)
		end

		-- Icon (use root node icon lookup, same as TreeTab)
		local treeId = skill.treeId
		local iconHandle = self:GetSkillIconFromTree(treeId)
		local iconX = cx + m_floor((CELL_W - GRID_ICON_SIZE) / 2)
		local iconY = cy + 4

		-- Frame: gold if unlocked, silver if locked/not-yet-unlocked
		local isUnlocked = skill.isUnlocked
		local frameName = isUnlocked and "skill-icon-frame" or "skill-icon-frame-locked"
		local frameHandle = self:GetSpriteHandle(frameName)
		local frameOff = m_floor((GRID_ICON_SIZE - FRAME_SIZE) / 2)

		-- Search highlight: determine match state
		local hasSearch = self.skillOverviewSearchStr ~= ""
		local isMatch = not hasSearch or self.skillOverviewSearchCache.results[skill.treeId] ~= nil

		if isLocked then
			SetDrawColor(0.35, 0.35, 0.35)
		elseif not isUnlocked then
			SetDrawColor(0.55, 0.55, 0.55)
		else
			SetDrawColor(1, 1, 1)
		end
		if iconHandle then
			DrawImage(iconHandle, iconX, iconY, GRID_ICON_SIZE, GRID_ICON_SIZE)
		end

		SetDrawColor(1, 1, 1)
		DrawImage(frameHandle, iconX + frameOff, iconY + frameOff, FRAME_SIZE, FRAME_SIZE)

		-- Search match: red square outline
		if hasSearch and isMatch then
			local ringSize = m_floor(GRID_ICON_SIZE * 1.5)
			local cx2 = iconX + m_floor(GRID_ICON_SIZE / 2)
			local cy2 = iconY + m_floor(GRID_ICON_SIZE / 2)
			local rx = cx2 - m_floor(ringSize / 2)
			local ry = cy2 - m_floor(ringSize / 2)
			local thick = 3
			SetDrawColor(1, 0, 0)
			DrawImage(nil, rx, ry, ringSize, thick)
			DrawImage(nil, rx, ry + ringSize - thick, ringSize, thick)
			DrawImage(nil, rx, ry, thick, ringSize)
			DrawImage(nil, rx + ringSize - thick, ry, thick, ringSize)
		end

		-- (slot assignment indicator removed)

		-- Level badge (centered on icon, hidden when unlocked)
		if skill.level and not isUnlocked then
			local lvBadgeW = 48
			local lvBadgeH = 40
			local lvBadgeX = iconX + GRID_ICON_SIZE / 2 - lvBadgeW / 2
			local lvBadgeY = iconY + GRID_ICON_SIZE / 2 - lvBadgeH / 2
			if isLocked then
				SetDrawColor(0.6, 0.6, 0.6)
			else
				SetDrawColor(1, 1, 1)
			end
			local badgeHandle = self:GetSpriteHandle("skill-req-mastery-level")
			DrawImage(badgeHandle, lvBadgeX, lvBadgeY, lvBadgeW, lvBadgeH)
			SetDrawColor(1, 1, 1)
			DrawString(lvBadgeX + lvBadgeW / 2, lvBadgeY + lvBadgeH / 2 - 5, "CENTER_X", 10, "VAR", "^7" .. tostring(skill.level))
		end

		-- Mastered badge (star skills without level requirement)
		if not skill.level and skill.isMastery and not isUnlocked then
			local lvBadgeW = 48
			local lvBadgeH = 40
			local lvBadgeX = iconX + GRID_ICON_SIZE / 2 - lvBadgeW / 2
			local lvBadgeY = iconY + GRID_ICON_SIZE / 2 - lvBadgeH / 2
			if isLocked then
				SetDrawColor(0.6, 0.6, 0.6)
			else
				SetDrawColor(1, 1, 1)
			end
			-- Use level badge frame with mastered star inside
			local badgeHandle = self:GetSpriteHandle("skill-req-mastery-level")
			DrawImage(badgeHandle, lvBadgeX, lvBadgeY, lvBadgeW, lvBadgeH)
			-- Draw star icon inside (smaller)
			local starHandle = self:GetSpriteHandle("skill-req-mastery-mastered")
			local starSize = 24
			SetDrawColor(1, 1, 1)
			DrawImage(starHandle, iconX + GRID_ICON_SIZE / 2 - starSize / 2, iconY + GRID_ICON_SIZE / 2 - starSize / 2, starSize, starSize)
		end

		-- Damage type icons (right side of icon, top-aligned)
		-- Base types bright, convertible types gray (TODO: dynamic conversion tracking)
		local damageTypes = self:GetSkillDamageTypes(skill.skillId or skill.name, skill.treeId)
		if #damageTypes > 0 then
			local dtSize = 16
			local dtX = iconX + GRID_ICON_SIZE + 2
			local dtY = iconY
			for _, dtInfo in ipairs(damageTypes) do
				local dtHandle = self:GetSpriteHandle("skill-damage-" .. dtInfo.type)
				if dtHandle then
					if dtInfo.isBase then
						SetDrawColor(1, 1, 1)
					else
						SetDrawColor(0.4, 0.4, 0.4)
					end
					DrawImage(dtHandle, dtX, dtY, dtSize, dtSize)
					dtY = dtY + dtSize + 1
				end
			end
		end

		-- Skill name (below icon, word-wrap if too wide)
		local nameY = iconY + ICON_SIZE + 4
		local displayName = skill.label or skill.name or ""
		local nameColor = isLocked and "^8" or (isUnlocked and "^7" or "^x999999")
		local maxNameW = CELL_W - 4
		local nameW = DrawStringWidth(10, "VAR", displayName)
		local nameLines = 1
		if nameW > maxNameW then
			local words = {}
			for word in displayName:gmatch("%S+") do t_insert(words, word) end
			local line1, line2 = "", ""
			for wi, word in ipairs(words) do
				local test = line1 == "" and word or (line1 .. " " .. word)
				if DrawStringWidth(10, "VAR", test) <= maxNameW or line1 == "" then
					line1 = test
				else
					line2 = table.concat(words, " ", wi)
					break
				end
			end
			DrawString(cx + CELL_W / 2, nameY, "CENTER_X", 10, "VAR", nameColor .. line1)
			if line2 ~= "" then
				DrawString(cx + CELL_W / 2, nameY + 12, "CENTER_X", 10, "VAR", nameColor .. line2)
				nameLines = 2
			end
		else
			DrawString(cx + CELL_W / 2, nameY, "CENTER_X", 10, "VAR", nameColor .. displayName)
		end

		-- Curse tag (Bone Curse, Spirit Plague, Chthonic Fissure)
		local CURSE_SKILL_IDS = { ["bc53"] = true, ["sp5g2"] = true, ["ch0fs"] = true }
		if CURSE_SKILL_IDS[skill.treeId] then
			local curseColor = isLocked and "^8" or (isUnlocked and "^xBB66FF" or "^x775599")
			DrawString(cx + CELL_W / 2, nameY + nameLines * 12, "CENTER_X", 9, "VAR", curseColor .. "CURSE")
		end

		-- Dim non-matching skills when search is active
		if hasSearch and not isMatch then
			SetDrawColor(0, 0, 0, 0.6)
			DrawImage(nil, cx, cy, CELL_W, CELL_H)
		end

		-- Click: assign skill to selected slot
		if isHover and not isLocked then
			for id, event in ipairs(inputEvents) do
				if event.type == "KeyUp" and event.key == "LEFTBUTTON" then
					local targetSlot = assignedSlot or self.selectedSlotIndex
					if not targetSlot then goto continueSkillClick end
					if not self.socketGroupList[targetSlot] or assignedSlot then
						if not assignedSlot then
							self:SelSkill(targetSlot, skill.skillId or skill.name)
							self.build.spec:BuildAllDependsAndPaths()
						end
						self.viewMode = "tree"
						self.viewingTreeSlot = assignedSlot or targetSlot
						self.selectedSlotIndex = self.viewingTreeSlot
						self.skillTreeViewer.selectedSkillIndex = self.viewingTreeSlot
						self.skillTreeViewer.skillBaseScale = nil
						self.skillTreeViewer.skillRefZoom = nil
					else
						local empty = self:FindEmptySlot()
						if empty then
							self:SelSkill(empty, skill.skillId or skill.name)
							self.build.spec:BuildAllDependsAndPaths()
							self.selectedSlotIndex = empty
							self.viewMode = "tree"
							self.viewingTreeSlot = empty
							self.skillTreeViewer.selectedSkillIndex = empty
							self.skillTreeViewer.skillBaseScale = nil
							self.skillTreeViewer.skillRefZoom = nil
						end
					end
					inputEvents[id] = nil
					::continueSkillClick::
				end
			end
		end
	end

	return y + rows * CELL_H
end

-- Draw skill tree view with back button and info bar
function SkillsTabClass:DrawSkillTree(viewPort, inputEvents, startY)
	local slot = self.viewingTreeSlot
	local sg = self.socketGroupList[slot]

	-- Back button area (top-left corner of viewport, above slots)
	local backW = 60
	local backH = 24
	local backX = viewPort.x + 6
	local backY = viewPort.y + 6
	local cursorX, cursorY = GetCursorPos()
	local overBack = cursorX >= backX and cursorX < backX + backW
		and cursorY >= backY and cursorY < backY + backH

	-- Back button
	if overBack then
		SetDrawColor(0.3, 0.3, 0.35)
	else
		SetDrawColor(0.15, 0.15, 0.2)
	end
	DrawImage(nil, backX, backY, backW, backH)
	SetDrawColor(0.5, 0.5, 0.55)
	DrawImage(nil, backX, backY, backW, 1)
	DrawImage(nil, backX, backY + backH, backW, 1)
	DrawImage(nil, backX, backY, 1, backH)
	DrawImage(nil, backX + backW, backY, 1, backH)
	DrawString(backX + backW / 2, backY + 4, "CENTER_X", 14, "VAR", "^7< Back")

	for id, event in ipairs(inputEvents) do
		if event.type == "KeyUp" and event.key == "LEFTBUTTON" and overBack then
			self.viewMode = "overview"
			self.viewingTreeSlot = nil
			inputEvents[id] = nil
		end
	end

	-- Steps mode button (below Back button, cycles none→all→min→none)
	do
		local STEPS_MODES   = { "none", "all", "min" }
		local STEPS_LABELS  = { "Steps", "Steps: All", "Steps: Min" }
		local STEPS_TOOLTIP = "Show allocating order numbers on allocated nodes.\nAll: every step the node was allocated (e.g. 3,7,12)\nMin: only the first allocation step (e.g. 3)"
		local cur    = self.skillTreeViewer.stepsMode or "none"
		local curIdx = 1
		for i, m in ipairs(STEPS_MODES) do if m == cur then curIdx = i end end

		-- Width wide enough for "Steps: Min" at font 13
		local stepsBtnW = 82
		local stepX = backX
		local stepY = backY + backH + 4
		local overSteps = cursorX >= stepX and cursorX < stepX + stepsBtnW
		              and cursorY >= stepY and cursorY < stepY + backH
		if overSteps then
			SetDrawColor(0.3, 0.3, 0.35)
		else
			SetDrawColor(0.15, 0.15, 0.2)
		end
		DrawImage(nil, stepX, stepY, stepsBtnW, backH)
		SetDrawColor(0.5, 0.5, 0.55)
		DrawImage(nil, stepX,            stepY,          stepsBtnW, 1)
		DrawImage(nil, stepX,            stepY + backH,  stepsBtnW, 1)
		DrawImage(nil, stepX,            stepY,          1,        backH)
		DrawImage(nil, stepX + stepsBtnW, stepY,          1,        backH)
		local stepsColor = curIdx == 1 and "^8" or "^2"
		DrawString(stepX + m_floor(stepsBtnW / 2), stepY + 4, "CENTER_X", 13, "VAR", stepsColor .. STEPS_LABELS[curIdx])

		-- Tooltip on hover (drawn at high layer to appear in front)
		if overSteps then
			SetDrawLayer(nil, 200)
			local tooltip = new("Tooltip")
			tooltip:Clear()
			for line in STEPS_TOOLTIP:gmatch("[^\n]+") do
				tooltip:AddLine(14, line)
			end
			tooltip:Draw(stepX, stepY, stepsBtnW, backH, viewPort)
			SetDrawLayer(nil, 0)
		end

		for id, event in ipairs(inputEvents) do
			if event.type == "KeyUp" and event.key == "LEFTBUTTON" and overSteps then
				self.skillTreeViewer.stepsMode = STEPS_MODES[(curIdx % #STEPS_MODES) + 1]
				inputEvents[id] = nil
			end
		end
	end

	-- Icon Preview toggle (dev mode only)
	if launch.devMode then
		local ipW = 110
		local ipX = backX + backW + 6
		local ipY = backY
		local overIP = cursorX >= ipX and cursorX < ipX + ipW
			and cursorY >= ipY and cursorY < ipY + backH
		if overIP then
			SetDrawColor(0.3, 0.3, 0.35)
		else
			SetDrawColor(0.15, 0.15, 0.2)
		end
		DrawImage(nil, ipX, ipY, ipW, backH)
		SetDrawColor(0.5, 0.5, 0.55)
		DrawImage(nil, ipX, ipY, ipW, 1)
		DrawImage(nil, ipX, ipY + backH, ipW, 1)
		DrawImage(nil, ipX, ipY, 1, backH)
		DrawImage(nil, ipX + ipW, ipY, 1, backH)
		local ipLabel = self.skillTreeViewer.showIconPreview and "^2Icon Preview: ON" or "^8Icon Preview: OFF"
		DrawString(ipX + ipW / 2, ipY + 4, "CENTER_X", 14, "VAR", ipLabel)
		for id, event in ipairs(inputEvents) do
			if event.type == "KeyUp" and event.key == "LEFTBUTTON" and overIP then
				self.skillTreeViewer.showIconPreview = not self.skillTreeViewer.showIconPreview
				inputEvents[id] = nil
			end
		end
	end

	-- Skill name + unspent points bar (between spec slots and tree)
	-- Draw at layer 145 so it stays above the skill background art (layer 15) and tree nodes (25)
	local infoBarH = 42
	local infoY = startY + 4
	if sg then
		local used = self:GetUsedSkillPoints(slot)
		local maxPts = self:GetMaxSkillPoints(slot)
		local rem = maxPts - used
		local skillName = (sg.grantedEffect and sg.grantedEffect.name) or "???"
		SetDrawLayer(nil, 145)
		-- Thin dark background strip so text is always legible
		SetDrawColor(0, 0, 0, 0.5)
		DrawImage(nil, viewPort.x, infoY - 2, viewPort.width, infoBarH - 4)
		-- Skill name (gold, centered)
		SetDrawColor(1, 1, 1)
		DrawString(viewPort.x + viewPort.width / 2, infoY, "CENTER_X", 14, "VAR", "^xDDC080" .. skillName:upper())
		-- Unspent points (blue if > 0, gray if 0)
		if rem > 0 then
			DrawString(viewPort.x + viewPort.width / 2, infoY + 16, "CENTER_X", 14, "VAR", "^x4DD9FF" .. rem .. " UNSPENT POINTS")
		else
			DrawString(viewPort.x + viewPort.width / 2, infoY + 16, "CENTER_X", 14, "VAR", "^x666666" .. used .. " / " .. maxPts .. " POINTS USED")
		end
		SetDrawLayer(nil, 0)
	end

	-- Tree viewport (fills remaining space, leave room for history bar + bottom search bar)
	local HISTORY_BAR_H = self.skillTreeViewer.historyExpanded and 72 or 48
	local treeY = startY + infoBarH
	local treeH = m_max(200, viewPort.y + viewPort.height - treeY - 4 - 32 - HISTORY_BAR_H)
	local treeVP = {
		x = viewPort.x + 2,
		y = treeY,
		width = viewPort.width - 4,
		height = treeH,
	}

	-- Background
	SetDrawColor(0.04, 0.04, 0.05)
	DrawImage(nil, treeVP.x, treeVP.y, treeVP.width, treeVP.height)

	self.skillTreeViewer.selectedSkillIndex = slot
	self.skillTreeViewer:Draw(self.build, treeVP, inputEvents)

	-- Leveling order history bar (sits between tree and search bar)
	local histBarVP = {
		x      = viewPort.x + 2,
		y      = treeY + treeH,
		width  = viewPort.width - 4,
		height = HISTORY_BAR_H,
	}
	self.skillTreeViewer:DrawHistoryBar(self.build, histBarVP, inputEvents)
end

function SkillsTabClass:getGemAltQualityList(gemData)
	local altQualList = { }

	for indx, entry in ipairs(alternateGemQualityList) do
		if gemData and (gemData.grantedEffect.qualityStats and gemData.grantedEffect.qualityStats[entry.type] or (gemData.secondaryGrantedEffect and gemData.secondaryGrantedEffect.qualityStats and gemData.secondaryGrantedEffect.qualityStats[entry.type])) then
			t_insert(altQualList, entry)
		end
	end
	return #altQualList > 0 and altQualList or {{ label = "Default", type = "Default" }}
end

-- Find the skill gem matching the given specification
function SkillsTabClass:FindSkillGem(nameSpec)
	-- Search for gem name using increasingly broad search patterns
	local patternList = {
		"^ "..nameSpec:gsub("%a", function(a) return "["..a:upper()..a:lower().."]" end).."$", -- Exact match (case-insensitive)
		"^"..nameSpec:gsub("%a", " %0%%l+").."$", -- Simple abbreviation ("CtF" -> "Cold to Fire")
		"^ "..nameSpec:gsub(" ",""):gsub("%l", "%%l*%0").."%l+$", -- Abbreviated words ("CldFr" -> "Cold to Fire")
		"^"..nameSpec:gsub(" ",""):gsub("%a", ".*%0"), -- Global abbreviation ("CtoF" -> "Cold to Fire")
		"^"..nameSpec:gsub(" ",""):gsub("%a", function(a) return ".*".."["..a:upper()..a:lower().."]" end), -- Case insensitive global abbreviation ("ctof" -> "Cold to Fire")
	}
	for i, pattern in ipairs(patternList) do
		local foundGemData
		for gemId, gemData in pairs(self.build.data.gems) do
			if (" "..gemData.name):match(pattern) then
				if foundGemData then
					return "Ambiguous gem name '" .. nameSpec .. "': matches '" .. foundGemData.name .. "', '" .. gemData.name .. "'"
				end
				foundGemData = gemData
			end
		end
		if foundGemData then
			return nil, foundGemData
		end
	end
	return "Unrecognised gem name '" .. nameSpec .. "'"
end

function SkillsTabClass:ProcessGemLevel(gemData)
	local grantedEffect = gemData.grantedEffect
	local naturalMaxLevel = gemData.naturalMaxLevel
	if self.defaultGemLevel == "awakenedMaximum" then
		return naturalMaxLevel + 1
	elseif self.defaultGemLevel == "corruptedMaximum" then
		if grantedEffect.plusVersionOf then
			return naturalMaxLevel
		else
			return naturalMaxLevel + 1
		end
	elseif self.defaultGemLevel == "normalMaximum" then
		return naturalMaxLevel
	else -- self.defaultGemLevel == "characterLevel"
		local maxGemLevel = naturalMaxLevel
		if not grantedEffect.levels[maxGemLevel] then
			maxGemLevel = #grantedEffect.levels
		end
		local characterLevel = self.build and self.build.characterLevel or 1
		for gemLevel = maxGemLevel, 1, -1 do
			if grantedEffect.levels[gemLevel].levelRequirement <= characterLevel then
				return gemLevel
			end
		end
		return 1
	end
end

-- Processes the given socket group, filling in information that will be used for display or calculations
function SkillsTabClass:ProcessSocketGroup(socketGroup)
	-- Loop through the skill gem list
	local data = self.build.data
	local gemInstance = socketGroup
	gemInstance.color = "^8"
	gemInstance.nameSpec = gemInstance.nameSpec or ""
	local prevDefaultLevel = gemInstance.gemData and gemInstance.gemData.naturalMaxLevel or (gemInstance.new and 20)
	gemInstance.gemData, gemInstance.grantedEffect = nil
	if gemInstance.gemId then
		-- Specified by gem ID
		-- Used for skills granted by skill gems
		gemInstance.errMsg = nil
		gemInstance.gemData = data.gems[gemInstance.gemId]
		if gemInstance.gemData then
			gemInstance.nameSpec = gemInstance.gemData.name
			gemInstance.skillId = gemInstance.gemData.grantedEffectId
		end
	elseif gemInstance.skillId then
		-- Specified by skill ID
		-- Used for skills granted by items
		gemInstance.errMsg = nil
		gemInstance.grantedEffect = data.skills[gemInstance.skillId]
	elseif gemInstance.nameSpec:match("%S") then
		-- Specified by gem/skill name, try to match it
		-- Used to migrate pre-1.4.20 builds
		gemInstance.errMsg, gemInstance.gemData = self:FindSkillGem(gemInstance.nameSpec)
		gemInstance.gemId = gemInstance.gemData and gemInstance.gemData.id
		gemInstance.skillId = gemInstance.gemData and gemInstance.gemData.grantedEffectId
		if gemInstance.gemData then
			gemInstance.nameSpec = gemInstance.gemData.name
		end
	else
		gemInstance.errMsg, gemInstance.gemData, gemInstance.skillId = nil
	end
	if gemInstance.gemData and gemInstance.gemData.grantedEffect.unsupported then
		gemInstance.errMsg = gemInstance.nameSpec .. " is not supported yet"
		gemInstance.gemData = nil
	end
	if gemInstance.gemData or gemInstance.grantedEffect then
		gemInstance.new = nil
		local grantedEffect = gemInstance.grantedEffect or gemInstance.gemData.grantedEffect
		if grantedEffect.color == 1 then
			gemInstance.color = colorCodes.STRENGTH
		elseif grantedEffect.color == 2 then
			gemInstance.color = colorCodes.DEXTERITY
		elseif grantedEffect.color == 3 then
			gemInstance.color = colorCodes.INTELLIGENCE
		else
			gemInstance.color = colorCodes.NORMAL
		end
		if prevDefaultLevel and gemInstance.gemData and gemInstance.gemData.naturalMaxLevel ~= prevDefaultLevel then
			gemInstance.level = gemInstance.gemData.naturalMaxLevel
			gemInstance.naturalMaxLevel = gemInstance.level
		end
		if gemInstance.gemData then
			gemInstance.reqLevel = grantedEffect.levels[gemInstance.level].levelRequirement
			gemInstance.reqStr = calcLib.getGemStatRequirement(gemInstance.reqLevel, grantedEffect.support, gemInstance.gemData.reqStr)
			gemInstance.reqDex = calcLib.getGemStatRequirement(gemInstance.reqLevel, grantedEffect.support, gemInstance.gemData.reqDex)
			gemInstance.reqInt = calcLib.getGemStatRequirement(gemInstance.reqLevel, grantedEffect.support, gemInstance.gemData.reqInt)
		end
	end
end

function SkillsTabClass:CreateUndoState()
	local state = { }
	state.activeSkillSetId = self.activeSkillSetId
	state.skillSets = { }
	for skillSetIndex, skillSet in pairs(self.skillSets) do
		local newSkillSet = copyTable(skillSet, true)
		newSkillSet.socketGroupList = { }
		for socketGroupIndex, socketGroup in pairs(skillSet.socketGroupList) do
			local newGroup = copyTable(socketGroup, true)
			newSkillSet.socketGroupList[socketGroupIndex] = newGroup
		end
		state.skillSets[skillSetIndex] = newSkillSet
	end
	state.skillSetOrderList = copyTable(self.skillSetOrderList)
	-- Save active socket group for both skillsTab and calcsTab to UndoState
	state.activeSocketGroup = self.build.mainSocketGroup
	state.activeSocketGroup2 = self.build.calcsTab.input.skill_number
	return state
end

function SkillsTabClass:RestoreUndoState(state)
	local displayId = isValueInArray(self.socketGroupList, self.displayGroup)
	wipeTable(self.skillSets)
	for k, v in pairs(state.skillSets) do
		self.skillSets[k] = v
	end
	wipeTable(self.skillSetOrderList)
	for k, v in ipairs(state.skillSetOrderList) do
		self.skillSetOrderList[k] = v
	end
	self:SetActiveSkillSet(state.activeSkillSetId)
	-- Load active socket group for both skillsTab and calcsTab from UndoState
	self.build.mainSocketGroup = state.activeSocketGroup
	self.build.calcsTab.input.skill_number = state.activeSocketGroup2
end

-- Opens the skill set manager
function SkillsTabClass:OpenSkillSetManagePopup()
	main:OpenPopup(370, 290, "Manage Skill Sets", {
		new("SkillSetListControl", nil, 0, 50, 350, 200, self),
		new("ButtonControl", nil, 0, 260, 90, 20, "Done", function()
			main:ClosePopup()
		end),
	})
end

-- Creates a new skill set
function SkillsTabClass:NewSkillSet(skillSetId)
	local skillSet = { id = skillSetId, socketGroupList = {} }
	if not skillSetId then
		skillSet.id = 1
		while self.skillSets[skillSet.id] do
			skillSet.id = skillSet.id + 1
		end
	end
	self.skillSets[skillSet.id] = skillSet
	return skillSet
end

-- Changes the active skill set
function SkillsTabClass:SetActiveSkillSet(skillSetId)
	-- Initialize skill sets if needed
	if not self.skillSetOrderList[1] then
		self.skillSetOrderList[1] = 1
		self:NewSkillSet(1)
	end

	if not skillSetId then
		skillSetId = self.activeSkillSetId
	end

	if not self.skillSets[skillSetId] then
		skillSetId = self.skillSetOrderList[1]
	end

	self.socketGroupList = self.skillSets[skillSetId].socketGroupList
	self.activeSkillSetId = skillSetId
	self.build.buildFlag = true
end

function SkillsTabClass:SelSkill(index, skillId)
	self.build.spec:ResetSkill(index)
	if skillId then
		self.socketGroupList[index] = {
			grantedEffect = self.build.data.skills[skillId] or {
				id = skillId,
				name = skillId,
				skillTypes = {},
				baseFlags = {},
				stats = {},
			},
			skillId = skillId,
			slot = "Skill " .. index,
			enabled = true
		}
	else
		self.socketGroupList[index] = nil
	end
	-- Reset the zoom cache so the tree re-fits when skills change
	self.skillTreeViewer.skillBaseScale = nil
	self.skillTreeViewer.skillRefZoom = nil
	self:AddUndoState()
	self.build.buildFlag = true
end

-- Get skill level for a given skill slot
-- In Last Epoch, skill level = total allocated points + global bonus + per-skill bonus
function SkillsTabClass:GetSkillLevel(index)
	local socketGroup = self.socketGroupList[index]
	if not socketGroup or not socketGroup.grantedEffect then
		return 0
	end
	return self:GetUsedSkillPoints(index) + self:GetTotalSkillLevelBonus(index)
end

-- Get the global +skill level bonus from equipment (e.g. "+1 Skills")
function SkillsTabClass:GetSkillLevelBonus()
	return self.build.skillLevelBonus or 0
end

-- Get the per-skill +level bonus from equipment (e.g. "+4 to Erasing Strike")
function SkillsTabClass:GetPerSkillLevelBonus(index)
	return (self.build.perSkillLevelBonus and self.build.perSkillLevelBonus[index]) or 0
end

-- Get total skill level bonus (global + per-skill)
function SkillsTabClass:GetTotalSkillLevelBonus(index)
	return self:GetSkillLevelBonus() + self:GetPerSkillLevelBonus(index)
end

-- Get the maximum skill points available for a skill tree
-- In Last Epoch, each skill has a base cap of 20 points.
-- Equipment "+X Skills" increases the effective max.
function SkillsTabClass:GetMaxSkillPoints(index)
	-- Range affixes (e.g. "+(3-4) to Intelligence Skills") roll at the midpoint
	-- (3.5) in LEB's display, which would yield a fractional cap. In-game caps
	-- are always integers; round half-up so e.g. 8.5 bonus → +9 cap (matches
	-- the upper end of the tier, which is what users expect when allocating).
	return 20 + m_floor(self:GetTotalSkillLevelBonus(index) + 0.5)
end

-- Get the number of skill points used in a skill tree
function SkillsTabClass:GetUsedSkillPoints(index)
	local socketGroup = self.socketGroupList[index]
	if not socketGroup or not socketGroup.grantedEffect or not socketGroup.grantedEffect.treeId then
		return 0
	end
	
	local treeId = socketGroup.grantedEffect.treeId
	local usedPoints = 0
	
	-- Count allocated nodes in this skill's tree, excluding the root node (maxPoints=0)
	for nodeId, node in pairs(self.build.spec.allocNodes) do
		if nodeId:match("^" .. treeId) and (node.maxPoints or 0) > 0 then
			usedPoints = usedPoints + (node.alloc or 0)
		end
	end
	
	return usedPoints
end