-- Last Epoch Planner
-- Boss Data
-- Source: lastepoch.tunklab.com (game version 1.3)
--
-- health    : HP at the reference difficulty (see category notes)
-- ward      : Ward amount (derived from wardPct where applicable)
-- wardPct   : Ward as % of max HP (0 = flat ward or no ward)
-- damageMod : More Damage % (0 Corruption baseline)
-- category  : used for bossStats averaging in Data.lua
--
-- Category reference difficulties:
--   "Empowered Monolith Boss" : Empowered Monolith, level 100, 0 Corruption
--   "Dungeon Boss"            : Tier 4, base stats (no dungeon modifiers)
--   "Pinnacle Boss"           : fixed (Aberroth, Vision of the Observer)
--   "Uber Boss"               : fixed (Herald of Oblivion)
--
local bosses = ...

-- Pinnacle Boss
bosses["Aberroth"] = {
	category  = "Pinnacle Boss",
	health    = 5657439,
	ward      = 4243079,
	wardPct   = 0,
	damageMod = 14,
}
bosses["Vision of the Observer"] = {
	category  = "Pinnacle Boss",
	health    = 4892857,
	ward      = 3669643,
	wardPct   = 0,
	damageMod = 0,
}

-- Uber Boss
bosses["Herald of Oblivion"] = {
	category  = "Uber Boss",
	health    = 50100612,
	ward      = 37575459,
	wardPct   = 0,
	damageMod = 654,
}

-- Dungeon Boss (Tier 4, no dungeon modifiers; The Mountain Beneath excluded)
bosses["Chronomancer Julra"] = {
	category  = "Dungeon Boss",
	health    = 144059,
	wardPct   = 75,
	ward      = 108044,
	damageMod = 197,
}
bosses["Fire Lich Cremorus"] = {
	category  = "Dungeon Boss",
	health    = 108489,
	wardPct   = 75,
	ward      = 81367,
	damageMod = 59,
}
bosses["Stone Titan's Heart"] = {
	category  = "Dungeon Boss",
	health    = 199549,
	wardPct   = 75,
	ward      = 149662,
	damageMod = 739,
}

-- Empowered Monolith Boss (level 100, 0 Corruption; all have wardPct=75)
bosses["Abomination"] = {
	category  = "Empowered Monolith Boss",
	health    = 144059,
	wardPct   = 75,
	ward      = 108044,
	damageMod = 21,
}
bosses["Emperor of Corpses"] = {
	category  = "Empowered Monolith Boss",
	health    = 330803,
	wardPct   = 75,
	ward      = 248102,
	damageMod = 239,
}
bosses["Frost Lich Formosus"] = {
	category  = "Empowered Monolith Boss",
	health    = 489268,
	wardPct   = 75,
	ward      = 366951,
	damageMod = 45,
}
bosses["God Hunter Argentus"] = {
	category  = "Empowered Monolith Boss",
	health    = 250770,
	wardPct   = 75,
	ward      = 188078,
	damageMod = 15,
}
bosses["Harbinger of Ash"] = {
	category  = "Empowered Monolith Boss",
	health    = 464191,
	wardPct   = 75,
	ward      = 348143,
	damageMod = 30,
}
bosses["Harbinger of Chaos"] = {
	category  = "Empowered Monolith Boss",
	health    = 410836,
	wardPct   = 75,
	ward      = 308127,
	damageMod = 30,
}
bosses["Harbinger of Defilement"] = {
	category  = "Empowered Monolith Boss",
	health    = 464191,
	wardPct   = 75,
	ward      = 348143,
	damageMod = 30,
}
bosses["Harbinger of Destruction"] = {
	category  = "Empowered Monolith Boss",
	health    = 464191,
	wardPct   = 75,
	ward      = 348143,
	damageMod = 30,
}
bosses["Harbinger of Fear"] = {
	category  = "Empowered Monolith Boss",
	health    = 410836,
	wardPct   = 75,
	ward      = 308127,
	damageMod = 30,
}
bosses["Harbinger of Hatred"] = {
	category  = "Empowered Monolith Boss",
	health    = 464191,
	wardPct   = 75,
	ward      = 348143,
	damageMod = 30,
}
bosses["Harbinger of Pride"] = {
	category  = "Empowered Monolith Boss",
	health    = 410836,
	wardPct   = 75,
	ward      = 308127,
	damageMod = 30,
}
bosses["Harbinger of Treason"] = {
	category  = "Empowered Monolith Boss",
	health    = 410836,
	wardPct   = 75,
	ward      = 308127,
	damageMod = 30,
}
bosses["Harbinger of Tyranny"] = {
	category  = "Empowered Monolith Boss",
	health    = 464191,
	wardPct   = 75,
	ward      = 348143,
	damageMod = 30,
}
bosses["Harbinger of War"] = {
	category  = "Empowered Monolith Boss",
	health    = 410836,
	wardPct   = 75,
	ward      = 308127,
	damageMod = 30,
}
bosses["Harton's Husk"] = {
	category  = "Empowered Monolith Boss",
	health    = 295233,
	wardPct   = 75,
	ward      = 221425,
	damageMod = 48,
}
bosses["Heorot"] = {
	category  = "Empowered Monolith Boss",
	health    = 268555,
	wardPct   = 75,
	ward      = 201416,
	damageMod = 21,
}
bosses["Lagon, God of Storms"] = {
	category  = "Empowered Monolith Boss",
	health    = 357480,
	wardPct   = 75,
	ward      = 268110,
	damageMod = 245,
}
bosses["Rahyeh, The Black Sun"] = {
	category  = "Empowered Monolith Boss",
	health    = 268555,
	wardPct   = 75,
	ward      = 201416,
	damageMod = 209,
}
bosses["The Husk of Elder Gaspar"] = {
	category  = "Empowered Monolith Boss",
	health    = 268555,
	wardPct   = 75,
	ward      = 201416,
	damageMod = 27,
}
bosses["Volcanic Shaman"] = {
	category  = "Empowered Monolith Boss",
	health    = 246501,
	wardPct   = 75,
	ward      = 184876,
	damageMod = 21,
}
