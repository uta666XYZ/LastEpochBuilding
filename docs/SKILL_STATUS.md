# Skill Calculation Status (v0.13.0)

> **TL;DR** — Calculation accuracy varies per skill. This page lists which skills have been
> exercised against community-shared reference builds, and which haven't yet. If a skill
> isn't listed, assume **Unverified** — it likely works, but the DPS number may need a sanity check.

LEB v0.13.0 was validated against ~45 LE 1.4 test builds shared by the community
(huge thanks to all contributors — see [CHANGELOG](../CHANGELOG.md) Special Thanks).
Per-skill calculation accuracy is being improved release by release.

---

## 🧪 Methodology

Each skill is bucketed into one of three tiers:

| Tier | Criteria |
|------|----------|
| ✅ **Verified** | Used in **≥3 test builds**, character-level DPS within **±5%** of the reference, no flagged per-skill discrepancy |
| ⚠️ **Partial** | Used in **1–2 test builds**, OR ≥3 builds but with a **known per-skill discrepancy** |
| ❓ **Unverified** | **Not touched** by any current test build. Calculation may still be correct — just not validated |

---

## ⚠️ Known Issues (v0.13.0)

These skills have **flagged discrepancies** vs the reference and are tracked for v0.13.x hotfixes:

| Skill | Mastery | Issue |
|-------|---------|-------|
| Gathering Storm | Shaman / Druid | CritMultiplier ~20% lower than reference (single build, Moorhuhn Druid) |
| Rive | Void Knight | Test snapshot ratio drifted ~26% — under investigation |

If you build around these, double-check the DPS against an in-game tooltip.

---

## ✅ Verified (≥3 builds, no flagged issues)

### Sentinel
- Healing Hands, Symbols of Hope, Anomaly, Devouring Orb, Erasing Strike,
  Warpath, Volatile Reversal, Void Cleave, Abyssal Echoes, Vengeance,
  Shield Rush, Holy Aura, Hammer Throw, Smite *(touched — review pending)*

### Mage
- Lightning Blast, Enchant Weapon, Static, Focus, Mana Strike, Flame Ward,
  Teleport, Shatter Strike, Frost Wall, Frost Claw, Fire Aura, Meteor,
  Arcane Ascendance, Firebrand, Surge

### Rogue
- Smoke Bomb, Umbral Blades, Shadow Cascade, Shurikens, Shift, Explosive Trap,
  Falconry, Puncture, Heartseeker, Shadow Rend, Dive Bomb, Dark Quiver

### Primalist
- Summon Wolf, Spriggan Form, Summon Spriggan, Warcry, Summon Frenzy Totem,
  Eterra's Blessing, Maelstrom, Storm Bolt, Fury Leap, Swipe, Tornado,
  Synchronized Strike, Summon Sabertooth, Summon Thorn Totem, Summon Storm Crows,
  Summon Scorpion, Summon Raptor

### Acolyte
- Reaper Form, Aura of Decay, Chaos Bolts, Summon Volatile Zombie, Summon Skeleton,
  Rip Blood, Marrow Shards, Harvest, Dread Shade, Spirit Plague, Bone Curse,
  Death Seal, Wandering Spirits, Infernal Shade, Chthonic Fissure

---

## ⚠️ Partial (1–2 builds — light validation)

Skills below are seen in only 1 or 2 test builds. Calculations are likely correct
but accuracy hasn't been cross-checked widely. **Use with caution; report bugs.**

- **Sentinel:** Manifest Armor, Judgement, Javelin, Multistrike, Forge Strike, Smite, Rebuke, Ring of Shields, Shield Bash, Shield Throw
- **Mage:** Fireball, Glacier, Static Orb, Disintegrate, Flame Reave, Flame Rush, Runebolt
- **Rogue:** Acid Flask, Net, Aerial Assault, Bladestorm Throw, Detonating Arrow, Hail of Arrows, Cinder Strike, Dancing Strikes, Flurry
- **Primalist:** Werebear Form, Swarmblade Form, Summon Bear, Summon Storm Totem, Tempest Strike, Upheaval, Serpent Strike
- **Acolyte:** Profane Veil, Summon Bone Golem, Drain Life, Soul Feast, Ghostflame, Sacrifice, Assemble Abomination, Flay

---

## ❓ Unverified

Any skill **not listed above** is Unverified — currently no test build exercises it.
This includes (non-exhaustive): many Ranger-tree skills (Bladedancer/Falconer/Marksman utilities),
several Acolyte minion variants, and most secondary-mastery skills not used as a main
attack in shared builds.

**Want your skill verified?** Share your build:
1. Export from LEB → "Generate Build Code"
2. Post in [Issues](https://github.com/uta666XYZ/LastEpochBuilding/issues) or DM on Reddit
3. The more diverse the test build pool grows, the more skills can be promoted to ✅

---

## 📊 Coverage Stats (v0.13.0)

| Mastery | Verified | Partial | Notes |
|---------|---------:|--------:|-------|
| Sentinel | ~14 | ~10 | VK / Paladin well-covered |
| Mage | ~15 | ~7 | Sorcerer / Spellblade well-covered |
| Rogue | ~12 | ~9 | Bladedancer well-covered, Falconer partial |
| Primalist | ~17 | ~7 | Beastmaster / Shaman well-covered |
| Acolyte | ~15 | ~8 | Necromancer / Lich well-covered, Warlock partial |

---

*Last updated: v0.13.0 release. Status will be re-evaluated each release as the test
build pool grows and per-skill verification improves.*
