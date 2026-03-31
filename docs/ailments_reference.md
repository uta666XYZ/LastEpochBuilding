# Last Epoch Ailments Reference

Source: https://support.lastepoch.com/hc/en-us (Last Epoch Compendium)
Extracted: 2026-03-31

---

## Ailment Mechanics

- Applied by hits or area effects at fixed intervals
- Most are chance-based
- Chance >100% applies multiple stacks (if stackable)
  - Example: 235% ignite chance = 2 stacks + 35% chance for 3rd
- Each damaging ailment has fixed base damage
- Affected by damage modifiers from skill tree and attribute scaling of the applying skill
- Ailment damage is NOT melee/hit damage even if applied by melee/hit
- Max stacks: new stack replaces oldest

## Ailment Duration and Effectiveness

- "Increased ailment duration" lengthens duration
- Longer duration = more total damage, same DPS
  - Example: Bleed 120 dmg / 3s -> with 50% inc duration: 180 dmg / 4.5s
- "Increased ailment effectiveness" applies to all stat modifiers
  - Example: 50% inc armor shred effectiveness: 150 armor reduction instead of 100

---

## Core Negative Ailments (for build calculations)

| Ailment | Duration | Max Stacks | Base Damage | Type | Effects |
|---------|----------|------------|-------------|------|---------|
| **Bleed** | 3s | Unlimited | 53 Physical | DoT | Inc Effect = Phys Pen |
| **Ignite** | 2.5s | Unlimited | 40 Fire | DoT | Inc Effect = Fire Pen |
| **Poison** | 3s | Unlimited | 28 Poison | DoT | First 30 stacks: +5% neg Poison Res each. Inc Effect = Poison Pen. 60% less vs players/bosses |
| **Frostbite** | 3s | Unlimited | 50 Cold | DoT | First 15 stacks: +20% inc chance to be frozen. Inc Effect = Cold Pen |
| **Electrify** | 2.5s | Unlimited | 44 Lightning | DoT | Inc Effect = Lightning Pen |
| **Damned** | 2.5s | Unlimited | 35 Necrotic | DoT | 20% reduced Health Regen. Inc Effect = Necrotic Pen |
| **Time Rot** | 3s | 12 stacks | 60 Void | DoT | 5% inc stun duration received. Inc Effect = Void Pen |
| **Future Strike** | 3s | Unlimited | 60 Void | DoT | Deals all damage at end. Inc Effect = Void Pen |

## Debuff Ailments

| Ailment | Duration | Max Stacks | Effects | Notes |
|---------|----------|------------|---------|-------|
| **Chill** | 4s | 3 | 12% less Attack/Cast/Move Speed per stack | 50% less vs players/bosses |
| **Shock** | 4s | 10 | +20% inc stun chance, +5% neg Lightning Res per stack | 60% less vs players/bosses |
| **Slow** | 4s | 3 | 20% less Movement Speed per stack | 50% less vs players/bosses |
| **Blind** | 4s | 1 | 100% less Critical Strike Chance | |
| **Frailty** | 4s | 3 | 6% less Damage per stack | |
| **Marked for Death** | 8s | 1 | -25% to All Resistances | |
| **Stagger** | 10s | 1 | -100 Armor, 10% inc Damage Taken | |
| **Critical Vulnerability** | 4s | 10 | +2% chance to receive crit, -10% Crit Avoidance per stack | |

## Resistance Shreds

| Ailment | Duration | Max Stacks | Effect per Stack | Notes |
|---------|----------|------------|-----------------|-------|
| **Shred Armor** | 4s | Unlimited | +100 Negative Armor | |
| **Shred Physical Res** | 4s | 10 | +5% Negative Physical Res | 60% less vs players/bosses |
| **Shred Fire Res** | 4s | 10 | +5% Negative Fire Res | 60% less vs players/bosses |
| **Shred Cold Res** | 4s | 10 | +5% Negative Cold Res | 60% less vs players/bosses |
| **Shred Lightning Res** | 4s | 10 | +5% Negative Lightning Res | 60% less vs players/bosses |
| **Shred Necrotic Res** | 4s | 10 | +5% Negative Necrotic Res | 60% less vs players/bosses |
| **Shred Poison Res** | 4s | 10 | +5% Negative Poison Res | 60% less vs players/bosses |
| **Shred Void Res** | 4s | 10 | +5% Negative Void Res | 60% less vs players/bosses |

## Curses

| Ailment | Duration | Max Stacks | Base Damage | Effects |
|---------|----------|------------|-------------|---------|
| **Bone Curse** | 8s | 1 | 4 Physical DoT | Takes spell phys dmg when hit. Inc Effect = Phys Pen |
| **Spirit Plague** | 3s | 1 | 90 Necrotic DoT | Spreads on death (9m, 1 target). Inc Effect = Necrotic Pen |
| **Torment** | 3s | 1 | 120 Necrotic DoT | 18% less Move Speed. Inc Effect = Necrotic Pen |
| **Decrepify** | 10s | 1 | 200 Physical DoT | 15% more DoT Taken (multiplicative). Scales with caster missing HP. Inc Effect = Phys Pen |
| **Anguish** | 10s | 1 | 480 Necrotic DoT | 15% less DoT. Inc Effect = Necrotic Pen |
| **Penance** | 15s | 1 | 20 Fire DoT | Target takes Fire dmg when hitting (0.35s cooldown) |
| **Exposed Flesh** | 8s | 1 | - | -15% Cold Res, +30% inc chance to be frozen |
| **Acid Skin** | 5s | 1 | 80 Poison DoT | +20% chance to receive crit. Inc Effect = Poison Pen |

## Doom / Void Ailments

| Ailment | Duration | Max Stacks | Base Damage | Effects |
|---------|----------|------------|-------------|---------|
| **Doom** | 4s | 4 | 400 Void DoT | 4% inc Melee Damage Taken. Inc Effect = Void Pen |
| **Abyssal Decay** (single) | 5s | 1 | 1000 Void DoT | Applies all remaining on hit. Inc Effect = Void Pen |
| **Abyssal Decay** (stacking) | 3s | Unlimited | 30 Void DoT | Applies all remaining on hit. Inc Effect = Void Pen |

## Other Notable Ailments

| Ailment | Duration | Max Stacks | Effects |
|---------|----------|------------|---------|
| **Withering** | 3s | 10 | 10% inc Curse Damage Taken per stack. 60% less vs players/bosses |
| **Efficacious Toxin** | 4s | 1 | 12% inc DoT Taken |
| **Plague** | 4s | 1 | 150 Poison DoT. Spreads (6m, unlimited targets, 0.6s delay) |
| **Spreading Flames** | 4s | 1 | 200 Fire DoT. Spreads (5m, unlimited targets, 0.6s delay) |
| **Immobilize** | 1s | 1 | Immobilizes target |
| **Root** | 0.7s | 1 | 93% less Movement Speed |

---

## Key Positive Ailments (for build calculations)

| Ailment | Duration | Max Stacks | Effects |
|---------|----------|------------|---------|
| **Frenzy** | 1s | 1 | 20% inc Attack/Cast Speed |
| **Haste** | 4s | 1 | 30% inc Movement Speed |
| **Void Barrier** | 999999s | 6 | 5% less Damage Taken per stack |
| **Void Essence** | 8s | 3 | 3% more Void Damage, 3% more Melee Damage, 15% reduced stun duration |
| **Dusk Shroud** | 4s | Unlimited | 5% Glancing Blow chance, +50 Dodge Rating per stack |
| **Aspect of the Spider** | 8s | 1 | +100% Slow on Hit, 15% more Damage to Slowed |
| **Totem Armor** | 4s | 3 | 80% inc Armor, 15% more Damage per stack |
| **Storm Infusion** | 4s | 3 | +21 Lightning Spell/Melee/Bow/Throwing Damage per stack |
| **Molten Infusion** | 4s | Unlimited | +15 Fire Melee Damage, +30% Ignite Chance per stack |
| **Contempt** | 500s | 5 | +10% All Res, 10% more Armor per stack |
| **Damage Immunity** | 3s | Unlimited | 100% less Damage Taken |
