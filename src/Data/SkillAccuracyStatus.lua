-- Skill accuracy honesty status (display-only UI badge source).
--
-- @leb-regression-guard:ui-accuracy-honesty-badge
--
-- GENERATED FILE -- DO NOT HAND-EDIT.
-- Regenerate with:  python scripts/gen_skill_accuracy_status.py
-- Generated from maintainer-supplied verification status data.
-- Source version: LEB-0.13.2   (last_updated: 2026-07-16)
--
-- Maps a runtime socketGroup.grantedEffect.name to a two-axis honesty tag:
--   "approximate" (amber) = board RE/feature-gated (g) or gap-open (w)
--                            -- model intentionally incomplete / known gap.
--   "unverified"  (gray)  = board rig-unmeasurable (x) or offline (n)
--                            -- number may be right but is unconfirmed.
-- Skills that are ±5%-verified (v), or verified-in-some-build (verified-wins,
-- e.g. Hammer Throw), are ABSENT here -> no badge. This table is the ALLOW-LIST
-- of skills that MUST show a badge; absence = verified/untracked = no claim.
--
-- DPS-NEUTRAL: this is static reference data (like colorCodes). It is read only
-- by GUI draw code; it never enters modList / calcsTab.mainOutput, so corpus
-- snapshots are byte-identical. See REGRESSION_GUARDS.md ui-accuracy-honesty-badge.
return {
	["Flay"] = "approximate",	-- Flay Mana Lich (g)
	["Harvest"] = "approximate",	-- Harvest Flay Lich (g)
	["Heartseeker"] = "unverified",	-- Heartseeker Mksm (x)
	["Hydrahedron"] = "approximate",	-- Hydrahedron RM (g)
	["Profane Orb"] = "approximate",	-- Profane Veil Warlock (w)
	["Profane Veil"] = "approximate",	-- Profane Veil Warlock (w)
	["Shadow Rend"] = "approximate",	-- Shadow Rend BD (g)
	["Shatter Totem"] = "approximate",	-- Shatter Totem Druid (g)
	["Summon Raptor"] = "unverified",	-- Raptor BM (x)
	["Summon Sabertooth"] = "approximate",	-- Sabertooth BM (g)
}
