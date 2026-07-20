# Skill Calculation Status (v0.14.0)

> **TL;DR** — LEB models essentially every main skill: across the full **639-build test
> corpus every build computes a real, non-zero Full DPS** — none are left "unsupported" at 0.
> What varies is how thoroughly each skill's number has been **verified** against an in-game
> reference. This page separates those two things: **is the skill modeled?** and **has that
> model been checked?**

LEB v0.14.0 carries a verification baseline built against **119 LE 1.4 canonical test builds**
shared by the community (huge thanks to all contributors — see [CHANGELOG](../CHANGELOG.md)
Special Thanks). For each of these the reference number is captured **in-game — by hitting Last
Epoch's training dummy and reading the actual damage dealt** — and LEB's Full DPS is compared
against that measured value within ±5%. Beyond those, LEB's stat calculations were also
cross-checked against **over 500 community-shared builds per mastery** to surface systematic
discrepancies. This baseline is carried forward and extended each release; per-skill calculation
accuracy is improved release by release.

---

## 🧭 Two meanings of "supported"

The word "supported" is ambiguous, so this page splits it into two independent axes:

- **Modeled (support)** — does LEB actually compute this skill?
  As of v0.14.0 the calculation coverage is **robust: 0 unmodeled main skills, and the
  full 639-build corpus computes cleanly**. So main skills are, as a rule, **`Full`**.
  A small number are **`Partial`** — modeled, but one specific mechanism is approximated
  or intentionally deferred (see *Cross-cutting modeling limits* below).
- **Verified** — has that model been cross-checked within ±5% of a reference?
  `✅ Verified` / `⚠️ Partial` / `❓ Unverified`.

> **Important:** `❓ Unverified` does **not** mean "unsupported". It means "modeled, but no
> test build has exercised it yet." A skill not listed below almost certainly still
> calculates correctly — it just hasn't been independently confirmed.

---

## 🧪 Methodology

Each skill is bucketed into one of three verification tiers:

| Tier | Criteria |
|------|----------|
| ✅ **Verified** | Used in **≥3 test builds**, character-level DPS within **±5%** of the **in-game reference** (measured on Last Epoch's training dummy), no flagged per-skill discrepancy |
| ⚠️ **Partial** | Used in **1–2 test builds**, OR ≥3 builds but with a **known per-skill discrepancy** |
| ❓ **Unverified** | **Not touched** by any current test build. Calculation may still be correct — just not validated |

Legend for the tables below — Modeled: `Full` / `Partial` · Verified: `✅` / `⚠️` / `❓`.

---

## 🗂️ Support status (Modeled × Verified)

### Sentinel — Verified 13 / Partial 8

| Skill | Modeled | Verified | Notes |
|-------|:---:|:---:|-------|
| Symbols of Hope, Healing Hands, Holy Aura, Abyssal Echoes, Anomaly, Devouring Orb, Smite, Warpath, Javelin, Shield Throw, Judgement, Vengeance, Volatile Reversal | Full | ✅ | |
| Multistrike, Forge Strike, Lunge, Shield Bash, Void Cleave, Ring of Shields, Rive | Full | ⚠️ | Seen in only 1–2 builds |
| Hammer Throw | Partial | ⚠️ | Physical per-hit matches. Bleed *orbit* stacking is geometry-dependent and intentionally not modeled (to avoid curve-fitting); >100% overstacking and the 3-projectile spiral are modeled |

### Mage — Verified 21 / Partial 4

| Skill | Modeled | Verified | Notes |
|-------|:---:|:---:|-------|
| Flame Ward, Enchant Weapon, Fire Aura, Flame Reave, Teleport, Frost Claw, Glacier, Surge, Frost Wall, Mana Strike, Firebrand, Static, Focus, Volcanic Orb, Elemental Nova, Meteor, Shatter Strike, Fireball, Ice Barrage | Full | ✅ | |
| Lightning Blast | Partial | ✅ | Direct hits verified. When specced into **Spark Charges**, the detonation rate is approximate (needs in-game grounding) |
| Runic Invocation | Partial | ✅ | Combo selection and the Hydrahedron / Grand Prism nova proc rate are approximate |
| Arcane Ascendance, Flame Rush, Black Hole | Full | ⚠️ | Seen in only 1–2 builds |
| Static Orb | Full | ⚠️ | An earlier over-reading was a display/row mismatch, now resolved |

### Rogue — Verified 15 / Partial 8

| Skill | Modeled | Verified | Notes |
|-------|:---:|:---:|-------|
| Smoke Bomb, Shadow Cascade, Umbral Blades, Shift, Bladestorm Throw, Shurikens, Explosive Trap, Synchronized Strike, Puncture, Falconry, Dancing Strikes, Multishot, Heartseeker, Decoy | Full | ✅ | |
| Shadow Rend | Partial | ✅ | Base per-hit is correct; the manifest sub-skill grant is intentionally deferred |
| Dark Quiver, Dive Bomb, Cinder Strike, Net, Acid Flask, Lethal Mirage, Aerial Assault | Full | ⚠️ | Seen in only 1–2 builds |
| Summon Ballista | Full | ⚠️ | Per-hit matches after the attack-speed fix; a secondary sub-skill rate is display-only |

### Primalist — Verified 9 / Partial 14

| Skill | Modeled | Verified | Notes |
|-------|:---:|:---:|-------|
| Warcry, Summon Wolf, Tempest Strike, Swipe, Summon Frenzy Totem, Summon Spriggan, Fury Leap, Summon Thorn Totem | Full | ✅ | |
| Upheaval | Full | ✅ | A totem-driven interaction has a state-dependent residual; the base skill is correct |
| Maelstrom | Partial | ⚠️ | The per-tick pulse-DoT structure has a per-stack baseline residual |
| Summon Scorpion, Eterra's Blessing, Summon Storm Crow, Entangling Roots, Spriggan Form, Gathering Storm, Earthquake Slam, Avalanche, Primal Lightning, Summon Bear, Werebear Form, Swarmblade Form, Summon Storm Totem | Full | ⚠️ | Seen in only 1–2 builds |

### Acolyte — Verified 18 / Partial 7

| Skill | Modeled | Verified | Notes |
|-------|:---:|:---:|-------|
| Summon Skeletal Mage, Dread Shade, Summon Volatile Zombie, Summon Skeleton, Summon Bone Golem, Marrow Shards, Bone Curse, Reaper Form, Transplant, Chaos Bolts, Chthonic Fissure, Flay, Infernal Shade, Rip Blood, Hungering Souls, Harvest, Summon Wraith | Full | ✅ | |
| Aura of Decay | Full | ✅ | Previously read 0 DPS; the ailment application was reworked and now passes ±5% |
| Soul Feast, Death Seal, Sacrifice, Spirit Plague, Wandering Spirits, Assemble Abomination | Full | ⚠️ | Seen in only 1–2 builds |
| Profane Veil | Partial | ⚠️ | A Profane-Orb interaction under-reads; the mechanism is wired but not yet in-game ±5% verified |

---

## 🧬 Minions, triggered & item-granted skills

The tables above list skills you slot and cast directly. Three other categories also flow into
Full DPS, so they belong on this page too:

### Minions (slotted summon skills)

Every minion gets Last Epoch's inherent per-level scaling, and multi-ability minions fold their
own skills into a single Full DPS number.

- **✅ Verified** (≥3 builds, ±5% in-game): Summon Wolf, Summon Frenzy Totem, Summon Spriggan,
  Summon Thorn Totem, Summon Skeletal Mage, Summon Volatile Zombie, Summon Skeleton,
  Summon Bone Golem, Summon Wraith, Falcon (Falconry).
- **⚠️ Partial** (1–2 builds, or a known residual): Summon Scorpion, Summon Storm Crow,
  Summon Bear, Summon Storm Totem, Summon Ballista, Assemble Abomination.
- **Known gap:** the **ailment** DPS a minion applies (Bleed / Ignite, etc.) is not yet modeled —
  a minion's *direct hits* are correct (see *Cross-cutting modeling limits* below).

### Item-granted minions (auto-summon framework)

Some minions are raised by a **unique / set**, not by a slotted summon skill (e.g. the Apiarist
set's Bees). LEB detects the gear-granted count and folds pack DPS (single-minion DPS × active
count) into Full DPS.

- **⚠️ Partial** (modeled + in-game cross-checked; v1 models the primary attack only, or a known
  residual): **Anurok** (Chorus of the Anurok), **Queen Bee** (Apiarist set 3-piece),
  **Storm Sprites** (Tempest Maw).
- **❓ Unverified** (modeled from datamined base + prefab, in-game DPS check still pending):
  **Tyrannosaur** (Tyrant's Skull), **Tolmat's Historic Minions** (Tolmat's Incorrect History of
  Eterra), **Bees / Elemental Bees** (Apiarist set / bee affixes).

### Node / kit-granted sub-skills

Several skills' *real* damage comes from a sub-skill their base kit or a specialization node grants
(e.g. Judgement's Consecrated Ground, Firebrand's Flame Wave). These are modeled as their own
sub-skill and validated **per-hit** in-game; the grant's *firing rate* inherits the parent's
(the same rate caveat as triggers).

- **✅ Verified** (in-game per-hit validated, parent well-covered): Consecrated Ground (Judgement),
  Iron Blade (Vengeance), Flame Wave (Firebrand), Dagger Dance daggers (Shadow Cascade),
  Divine Flare (Symbols of Hope), Shatter Totem + Upheaval Totem (Upheaval), Chthonic Fissure
  fire-line DoT + Soul Blast (Chthonic Fissure), Spark Discharge (Explosive Trap).
- **⚠️ Partial** (in-game grounded but a known residual / limited builds): Static Orb body-hit +
  Charged Ground (Static Orb), Avalanche Fissure (Avalanche), Spirit Thorns + Thorn Shield +
  Healing Totems (Spriggan Form), **Profane Orb (Profane Veil) — wired but under-reads, not yet
  ±5% in-game**.
- **❓ Deferred** (base datamined but intentionally not yet active pending validation): Shadow Rend
  manifest shadows.

### Triggered skills ("chance to cast / trigger")

LEB does **not** keep a separate whitelist of triggerable skills. Any skill named by a "chance to
cast / trigger `<skill>`" affix, idol, or tree node is fired through the trigger engine and
computes its per-hit with **the exact same model as when you cast it directly** — so a triggered
skill's per-hit accuracy is simply **its own tier in the per-mastery tables above**. Two things
are trigger-specific:

- **Rate** — the firing frequency is build-derived and **rate-capped**; for some proc families it
  is approximate (see *Cross-cutting modeling limits*). The most notable approximate rates are the
  **proc-nova** family — Runic Invocation's Hydrahedron / Grand Prism nova, and Lightning Blast →
  Spark Charge detonation.
- **Unique-triggered skills** — uniques that trigger a skill on hit / on cast (e.g. Spine of
  Malatros casting Flame Whip) run through the same engine; the triggered skill inherits its own
  tier, and any behaviour the unique fundamentally changes is called out in the per-mastery Notes
  where it has been tested.

---

## ⚙️ Cross-cutting modeling limits

These are **not** unsupported skills — they are modeled, but one mechanism is approximate
or deferred, and it can affect any build that leans heavily on it:

| Mechanism | Effect | Status |
|-----------|--------|--------|
| **Trigger / proc rates** (proc-nova, on-hit, on-cast) | The base hit is correct; the *firing frequency* of some procs is approximate | Needs in-game grounding |
| **Minion ailments** | Ailment DPS that a minion applies (Bleed / Ignite, etc.) is not yet modeled; a minion's direct hits are correct | Needs in-game grounding |
| **Pulse-DoT / channeled** (e.g. Maelstrom) | Per-tick, per-stack baseline has a residual | Larger feature work |
| **Spark Charge detonation rate** | Lightning Blast → Spark Charges detonation frequency | Needs in-game grounding |
| **Weapon base (melee / throwing inheritance)** | Mostly resolved (bow-minion inheritance, skill-intrinsic bases fixed individually) | Largely resolved |

If your build depends heavily on one of these, double-check the DPS against an in-game
tooltip.

---

## ⚠️ Known limitations (v0.14.0)

- **Buff / debuff rotation combos** — some skill rotations rely on temporary buffs or debuffs.
  Combinations that weren't captured during validation may not have their DPS reflected
  accurately.
- **Reflect and enemy-state-dependent damage** — damage that scales off the enemy's state,
  such as **Reflect** (Reflect Shaman) or health/execute-based effects (**Raptor**,
  Beastmaster), is not yet fully handled.
- **Importing from a Last Epoch Tools *character* URL** (e.g. `.../planner/XYZ`) can cause
  minor stat differences versus in-game. For the most accurate import, use a Last Epoch Tools
  **profile** URL (`.../profile/XYZ/character/XYZ`) or **import via Maxroll**.

---

## ❓ Unverified

Any skill **not listed above** is Unverified — modeled, but no current test build exercises
it (roughly **~17% / ~24 skills**). This includes several Bladedancer / Falconer / Marksman
utilities, a few Acolyte minion variants, and most secondary-mastery skills not used as a
main attack in any shared build.

**Want your skill verified?** Share your build:
1. Export from LEB → "Generate Build Code"
2. Post in [Issues](https://github.com/uta666XYZ/LastEpochBuilding/issues) or DM on Reddit
3. The more diverse the test build pool grows, the more skills can be promoted to ✅

---

## 📊 Coverage Stats (v0.14.0)

| Mastery | Verified | Partial | Notes |
|---------|---------:|--------:|-------|
| Sentinel | 13 | 8 | VK / Paladin well-covered |
| Mage | 21 | 4 | Sorcerer / Spellblade / Runemaster well-covered |
| Rogue | 15 | 8 | Bladedancer well-covered, Falconer partial |
| Primalist | 9 | 14 | Beastmaster / Shaman well-covered, Druid partial |
| Acolyte | 18 | 7 | Necromancer / Lich / Warlock well-covered |
| **Total** | **76** | **41** | 117 distinct skill IDs exercised |

Verification rate (Verified ÷ touched): Mage 84% · Acolyte 72% · Rogue 65% · Sentinel 62% ·
Primalist 39%. Roughly two-thirds of every skill that has been touched now lands within ±5%.

---

*Last updated: v0.14.0. Status is re-evaluated each release as the test build pool grows
and per-skill verification improves. The bottom line has held steady: across the 639-build
corpus no main skill computes 0 DPS — the open work is verifying models against in-game
references and closing the cross-cutting limits above.*
