# Last Epoch Game Mechanics Reference

Source: https://support.lastepoch.com/hc/en-us (Last Epoch Compendium)
Extracted: 2026-03-31

---

## Damage System

### Hit vs Damage Over Time
- Damage is dealt as a **hit** or **damage over time (DoT)**
- DoT sources: ailments (ignite, bleed, poison), area DoTs (Fire Aura, Tornado, Consecrated Ground)
- Hits can be dodged, blocked, or turned into glancing blow
- DoT cannot be mitigated by most defenses except resistances
- DoT cannot critically strike and does not trigger on-hit effects

### Base Damage
- All skills have base damage (modifiable only by skill tree)
- Melee skills typically have 2 base damage (most damage comes from weapons)
- Spells/throwing attacks can have much more base damage
- Stats like "+5 melee fire damage" are multiplied by added damage effectiveness, then added to base damage
- Added damage without a type (e.g. "+5 Melee Damage") inherits the skill's base damage type

### Damage Conversion
- Base damage type of skills can be converted (e.g. Physical -> Fire)
- Conversions found in skill trees, items, sometimes passive trees
- Conversion affects base damage and untyped added damage
- Does NOT affect typed added damage (e.g. "+5 Melee Fire Damage")
- Does NOT affect ailments unless stated otherwise

### Damage Effectiveness
- All skills have an added damage effectiveness multiplier
- Applied to all damage from stats like "+5 melee fire damage"
- High cost/cooldown skills typically have >100% effectiveness
- Rapid-hit skills typically have <100% effectiveness
- Does NOT affect base damage

### Increased, Added, and More
- **Added**: All added sources totaled first
- **Increased/Reduced**: All increased sources totaled together (additive with each other)
- **More/Less**: Each more/less source is a separate multiplier (multiplicative with each other)
- Formula: `(sum of added) * (1 + sum of increased%) * (1 + more1%) * (1 + more2%) * ...`
- Example: (5+2+3) * (1+0.05+0.3+0.1) * (1.05) * (1.3) * (1.1) = 21.77

---

## Defensive Mechanics

### Resistances
- Reduce damage taken of that type
- Cap at **75%**
- Can go negative (each 1% negative = 1% increased damage taken)
- Over-cap protects against resistance shred effects
- One of the few ways to mitigate DoT
- Enemies gain **1% penetration per area level** (max 75%)

### Armor
- Mitigates damage from **all hits** (no effect vs DoT)
- Formula: `mitigation = armor / (armor + 70 * areaLevel)`
- Max mitigation: **85%**
- **70% effective** against non-physical damage

### Penetration
- Subtracts from resistances after the 75% cap
- Can reduce resistances to negative values
- Example: 30% lightning pen vs 20% resist = -10% resist
- All enemies gain 1% penetration per area level (max 75%)
- Overcapping resistances above 75% does NOT help against enemy penetration

### Ward
- Shield above health, rapidly decays over time
- No maximum value
- Ward Decay Threshold: ward does not decay below this value
- Decays faster as you gain more
- Ward Retention slows decay
- Intelligence grants Ward Retention (2% per point)

### Dodge
- Chance to completely avoid a hit
- Formula: `dodge_chance = dodge_rating / (dodge_rating + X)` (area-level dependent)
- Rule of thumb: dodge rating = 10 * area level gives ~50% dodge chance
- Cap: **85%**
- No effect vs DoT
- Dodging does NOT count as being hit

### Block
- Chance to reduce damage from hits
- Block Chance determines if you block
- Block Effectiveness determines damage reduction (area-level dependent)
- Max block effectiveness mitigation: **85%**
- Can block all hits including spells
- Blocking DOES count as being hit
- No effect vs DoT

### Endurance
- Take less damage while below Endurance Threshold
- Default: **20% Endurance**, threshold = **20% of max health**
- Cap: **60%** less damage taken (multiplicative with other modifiers)
- Endurance Threshold has no cap
- Applies to damage crossing the threshold proportionally
- Applies to both hits AND DoT
- Does NOT protect ward

### Glancing Blow
- Chance to reduce hit damage by **35%**
- Cap: >100% has no additional effect
- No effect vs DoT
- Taking a glancing blow DOES count as being hit

### Parry
- Chance to negate **all** damage from a hit
- Cap: **75%**
- Parrying DOES count as being hit (ailments can still apply)
- No effect vs DoT

### Evade
- Movement ability (not a defense stat)
- Bound to Space, 2 charges
- Base cooldown: **4 seconds**
- Gains **0.5% Increased Cooldown Recovery Speed per character level**
- At level 100: ~2.7 second cooldown (no other sources)
- NOT immune to damage during evade

### Damage Taken From Mana Before Health
- Primarily for Mages/Sorcerers
- Portion of damage dealt to mana instead of health
- **1 mana shields 5 health** (effectively 80% damage reduction on mana portion)
- Does NOT work at 0 or negative mana
- Does NOT protect ward
- Cap: >100% has no additional effect

### Boss Ward
- Certain bosses have ward notches on health bar
- When health reaches a notch, boss gains ward based on max health and is stunned briefly
- Boss ward decay speeds up over time (unlike player ward)

---

## Offensive Mechanics

### Critical Strikes
- Base crit chance: **5%**
- Default crit multiplier: **200%**
- DoT cannot crit
- **Added crit chance**: +1% crit chance with base 5% = 6% final
- **Increased crit chance**: 1% increased with base 5% = 5.05% final
- Critical Strike Avoidance: chance to turn crits into normal hits (rolled after attacker's crit)
- Less bonus damage from crits: max 100% (reduces crit to normal hit damage)
- All enemy crits have 200% multiplier

### Stun
- Duration: **0.4 seconds**
- Chance based on damage dealt vs target max health
- Player melee damage: **3x multiplier** for stun calculation
- Other player damage: **2x multiplier**
- At 0% increased stun chance / 0 avoidance: must deal >5% of target max HP
- Every 100 stun avoidance raises threshold by 1%
- Bosses: max health treated as **50% higher** for stun calc
- Players have inherent stun avoidance: **250 + 5 per level**
- Shock increases chance to be stunned

### Freeze
- Duration: **1.2 seconds**
- Requires freeze rate on skill
- Formula: `freeze_chance = (freeze_rate * freeze_rate_multiplier) / (max_health + current_ward)`
- Frostbite increases chance to be frozen
- Bosses: max health treated as **50% higher** for freeze calc

### Health Leech
- Recover % of damage dealt as health
- Uses **final damage dealt** (after target's defenses)
- Excess damage beyond target's remaining HP is NOT counted
- Health returned evenly over **3 seconds**
- Each instance independent (expires at different times)
- No limit to simultaneous leech

---

## Character Stats

### Attributes
| Attribute | Bonus per point |
|-----------|----------------|
| Strength | 4% Increased Armor |
| Dexterity | 4 Dodge Rating |
| Intelligence | 2% Ward Retention |
| Attunement | 2 Mana |
| Vitality | 6 Health, 1% Poison and Necrotic Resistance |

### Level-up Stats (per level)
| Stat | Per Level | Total at 100 |
|------|-----------|-------------|
| Health | +10 | +990 |
| Mana | +0.5 | +50 |
| Stun Avoidance | +5 | +495 |
| Health Regeneration | +0.125 | +12 |
| Health on Potion | +5 | +495 |

### Other Level Benefits
- Passive Skill Point: levels 3-100 (total 98)
- Skill Specialization slots at levels 4, 8, 20, 35, 50
- Minimum Skill Levels increase at levels 8, 12, 17, 24, 32, 40, 50, 60, 70
- Minion scaling from level 26+: **0.6% more damage** and **0.8% damage reduction** per level
  - At level 100: 45% more minion damage, 60% minion damage reduction

### Base Mana Regeneration
- Default: **8 mana per second**
- Can be increased through skills, items, passives (NOT by leveling)

### Health
- Can go to 0 = death
- Health regen: base + 0.125 per level

### Mana
- Skills can be used at 0 mana if cost > 0 (goes negative)
- Cannot use skills costing mana while at negative mana
- Some skills benefit from negative mana

### Potions
- Drop from kills/boss hits
- Instant burst healing
- Max capacity increased by belt upgrades
- Auto-consumed if picked up at max potions but not full health

---

## Minions

### General
- Auto-attack enemies, return to player if too far
- Attack command: A key (default)
- Two modes: Protect (stay near player) and Assassinate (prioritize nearby targets/bosses)
- Character modifiers do NOT apply unless "minion" is specified
- Level scaling (from level 26): +0.6% more damage, +0.8% damage reduction per level

### Companions
- Special minion type (primarily Primalist)
- Default limit: 2 companions active
- All minion stats apply + companion-specific effects
- Summon skill becomes companion ability after summoning
- Downed state at 0 HP (revive by standing near; dies if too long)

### Totems
- Minion type (Primalist)
- Cannot move, fixed duration + health
- All minion stats apply + totem-specific effects
