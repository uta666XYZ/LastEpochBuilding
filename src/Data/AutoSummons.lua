-- Auto-summon registry (auto-summon-framework Phase A).
--
-- Last Epoch has minions that are auto-summoned by GEAR / AFFIXES / PASSIVES
-- rather than by a slotted summon skill, e.g. the Apiarist set's "Bees" from
-- "+N Bees Per 10 Seconds". The affix grants a per-player COUNT stat; the
-- minion itself is the SAME prefab the corresponding summon skill produces.
--
-- Each entry maps such a player-side COUNT stat (parsed by ModParser onto the
-- PLAYER modDB) to the existing summon skill in data.skills that produces the
-- minion. CalcSetup's grantedAutoSummons loop (see file header / guard
-- `auto-summon-registry`) auto-detects the stat (env.modDB:Sum("BASE", ...)
-- > 0) and injects `summonSkill` as a granted skill with
-- includeInFullDPS=true (so it appears under Full DPS, not as the main-skill
-- panel) and carries `autoSummonCountStat` onto the socket group. calcFullDPS
-- (guard `auto-summon-pack-dps`) then resolves that count against the PLAYER
-- modDB and reports pack DPS = single-minion DPS x active count.
--
-- Schema (array; adding a row needs NO code change):
--   { countStat = "<PlayerModDBStatName>", summonSkill = "<data.skills key>" }
--
-- Every summonSkill here MUST exist in data.skills, and its minionList must
-- resolve to a real src/Data/minions.json entry (asserted by
-- spec/System/TestAutoSummonFramework_spec.lua). No fabricated entries.
--
-- Game ground truth for the Phase A bee entries (no fabrication):
--   * Apiarist set / Bee affixes grant "+N Bees Per 10 Seconds" (and the
--     "Elemental Bees" variant). LEB recognized the affix text but parsed it
--     to an EMPTY mod (src/Data/ModCache.lua rows c["+1 Bees Per 10
--     Seconds"]={{}," Bees Per 10 Seconds "}), so no minion was modeled.
--   * The summoned bee is data.skills.SummonBee (Druid, "Summon Bee") whose
--     minion is the src/Data/minions.json "Bee" prefab (skillList
--     {"BasicEnemyMelee"} = 18 base physical melee). Both the BeesPerTenSeconds
--     and the "Elemental Bees" affix produce the SAME Bee prefab, so both map
--     to SummonBee; the elemental variant's damage typing is carried by the
--     build's minion/conversion mods, not by a separate prefab.
--
-- Phase B (datamine v1; in-game DPS verification pending for these uniques):
-- gear-granted auto-summons whose summon skill + minion prefab linkage is now
-- verified in data. Each minion's PRIMARY attack skill is encoded in skills.json
-- (datamine: melee_base damage + addedDamageScaling->damageEffectiveness +
-- useDelay->castTime; only the basic attack, secondaries/buffs deferred), and
-- its summon skill's minionList dangling link was fixed to the real minions.json
-- key (see spec/System/TestMinionListResolves_spec.lua):
--   * Tyrannosaur -- Tyrant's Skull (unique 424) "+100% Summons Tyrannosaur
--     Minion" -> TyrannosaursSummoned (always 1) -> "Summon Giant T_Rex Minion"
--     -> PrimalTyrannosaur (Bite 125 phys).
--   * Tolmat -- Tolmat's Incorrect History of Eterra (unique 369) "+N Tolmat's
--     Historic Minions" -> TolmatHistoricMinions (count = N) -> "Summon Tolmat
--     Minion" -> TolmatMinionDivine (Melee 16 phys).
--   * Anurok -- Chorus of the Anurok (unique 430) "1 Summon Anuroks up to your
--     Companion Limit" -> GATE AnuroksSummoned (=1 only when Chorus equipped),
--     PACK count = MaxCompanions (packCountStat; the in-game Anuroks fill the
--     companion limit -- the Deluyi capture showed LEB count=1 was ~7.5x low).
--     -> "Summon AncientOasis01 Primordial Minion" -> PrimalAnurok, primary
--     Tongue Slap (04, 30 phys) = the DOMINANT in-game attack (Deluyi capture:
--     Tongue Slap 5171 hits vs "01 Melee"/Tongue Stab 11). MaxCompanions is an
--     upper bound (slight over when the build also runs other companions); the
--     residual ~1.7x vs in-game is the GENERAL per-minion-scaling gap, not
--     auto-summon-specific.
--   * Queen Bee -- Apiarist's Set 3-piece bonus "Summon the Queen Bee" (a SET
--     BONUS string, not an item affix: CalcSetup.applySetBonuses runs each bonus
--     tier through modLib.parseMod when the piece count is met) -> QueenBeeSummoned
--     (always 1, persistent) -> SummonQueenBee (NEW summon skill) -> QueenBee
--     minion (Scratch 60 phys, eff 3, datamine + in-game Fehm cross-check).
--     Quadruple Scratch + on-death Bee Explosion deferred (v1 single primary).
--
-- Phase C (Storm Sprite / Tempest Maw) -- IMPLEMENTED 2026-06-17 (StormSpritesSummoned
-- row below). Tempest Maw's intrinsic "When you summon a totem you also summon 4 Storm
-- Sprites ... (up to 2 times per 6 seconds)" is an ability tooltip, not a rollable mod, so
-- it was absent from LEB's Tempest Maw data; added as a non-rollable mod -> ModParser
-- "storm sprites" pattern -> StormSpritesSummoned BASE 4 (the game-source per-proc count;
-- in-game WARRIOR95 ~4 concurrent = 5231 Storm Dash hits/241.9s / ~5/s per sprite).
-- stormSpriteDash (base Lightning 20, eff 1.0, the minion's missing attack) added to
-- skills.json from the live 1.4.7 bundles (_extract_storm_sprite.py). The "2/6s" proc
-- rate + totem-summon gating are flattened to the steady-state count (planner). v1: count
-- ungated (Tempest Maw is a totem-synergy unique); the secondary smallLightningExplosion
-- (Lightning 9, eff 0.5) is deferred (v1 single primary, like Bee/T-Rex).
-- Phase D follow-up (NOT here -- wrong mechanism for the count registry):
--   * Per-area Tolmat resummon: the steady-state count already works via the row
--     above; the "on area enter" timing is DPS-irrelevant for a planner.
return {
	{ countStat = "BeesPerTenSeconds",          summonSkill = "SummonBee" },
	{ countStat = "ElementalBeesPerTenSeconds",  summonSkill = "SummonBee" },
	{ countStat = "TyrannosaursSummoned",        summonSkill = "Summon Giant T_Rex Minion" },
	{ countStat = "TolmatHistoricMinions",       summonSkill = "Summon Tolmat Minion" },
	{ countStat = "AnuroksSummoned",             packCountStat = "MaxCompanions", summonSkill = "Summon AncientOasis01 Primordial Minion" },
	{ countStat = "QueenBeeSummoned",            summonSkill = "SummonQueenBee" },
	{ countStat = "StormSpritesSummoned",        summonSkill = "SummonStormSprite" },
}
