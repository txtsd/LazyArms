# LazyArms

A one-button 2H Arms Warrior rotation addon for [TurtleWoW](https://turtlecraft.gg/).

Bind `/lazyarms` to a key and spam it. LazyArms handles ability prioritization, stance dancing, rage management, swing timing, and reactive procs - all correctly.

## Requirements

- [pfUI](https://github.com/me0wg4ming/pfUI) (with libdebuff)
- [Nampower](https://gitea.com/avitasia/nampower)
- [SuperWoW](https://github.com/balakethelock/SuperWoW)
- [UnitXP_SP3](https://codeberg.org/konaka/UnitXP_SP3)

## Installation

Copy the `LazyArms` folder into your `Interface/AddOns/` directory.

## Usage

Create macros and place them on your action bar:

```
/lazyarms      -- single-target rotation
/lazyarmsaoe   -- AoE rotation
```

Spam the button. That's it.

## Rotations

### Single-target (`/lazyarms`)

Each press evaluates the following priority list top to bottom and executes the first eligible action:

1. **Auto Attack** - ensures auto attack is running before anything else
2. **Charge / Intercept** - closes the gap when 8-25 yards from target; Intercept is blocked on non-aggroed mobs inside instances to avoid pulling extras
3. **Berserker Stance** - switches stance if not already in it
4. **Battle Shout** - maintains the buff
5. **Execute** - fires immediately when the target is below 20% HP
6. **Sunder Armor** - maintains 5 stacks; refreshes when under 5 seconds remain; skips armor-less targets entirely
7. **Overpower / Revenge** - used when available but only below 26 rage, and only when Whirlwind is not already castable (Tactical Mastery awareness - see below)
8. **Mortal Strike** - highest-priority spender; will not fire if Whirlwind is already queued
9. **Whirlwind** - second-priority spender; will not fire if Mortal Strike is already queued
10. **Slam** - filler cast, gated on swing timer to never delay your next auto attack (see below)
11. **Heroic Strike** - queued when your next swing is projected to rage-cap you (see below)

### AoE (`/lazyarmsaoe`)

1. **Auto Attack** - same pre-rotation as single-target
2. **Charge / Intercept** - same gap closer logic
3. **Sweeping Strikes** - activated on cooldown before stance check, so it fires even from Battle Stance
4. **Berserker Stance** - switches if needed
5. **Battle Shout** - maintains the buff
6. **Cleave** - kept queued as a permanent on-swing replacement; no GCD conflict
7. **Whirlwind** - top GCD priority when in range
8. **Sunder Armor** - one application per target for tab-sundering; skips targets already sundered or armor-less
9. **Mortal Strike** - GCD filler between Whirlwinds
10. **Execute** - lowest priority finisher

## How the hard parts actually work

### Slam and the swing timer

Slam has a 2 second cast time (modified by any cast speed debuffs on you). If you start casting Slam too early in a swing cycle, the cast will push back your next auto attack, which is a significant DPS loss on a 2H warrior.

The safe window to begin Slam is: `swing_speed - slam_cast_time` seconds after an auto attack lands. LazyArms tracks the exact timestamp of every auto attack hit via Nampower's `AUTO_ATTACK_SELF` event, reads your current swing speed and cast speed modifier directly from unit fields each press, and only allows Slam to fire inside that window. Outside the window - even if Slam is off cooldown and you have the rage - it will not cast.

### Heroic Strike and rage capping

Heroic Strike is an on-swing attack, not a GCD ability. Queuing it at the wrong time wastes rage you could spend on actual spells. LazyArms uses a formula to estimate how much rage your next auto attack will generate:

```
rage_gain = ((avg_damage / 230.6) * 7.5 / 1.075) + (base_weapon_speed * 3.5 / 2.25)
```

Your weapon's base speed (before haste) is read from the item DBC via `GetItemStatsField`, your current damage values come from unit fields, and your current rage and rage cap are read the same way. Heroic Strike is only queued when `current_rage + projected_rage_gain >= max_rage`. If you are not going to cap, it does not queue.

### Tactical Mastery and Overpower/Revenge

Overpower and Revenge require switching to Battle Stance, which normally drains all but 10 rage. With 5/5 Tactical Mastery you retain 25 rage on stance switch instead. LazyArms will only use Overpower or Revenge when your rage is at 25 or below - meaning the stance switch costs you nothing you weren't going to keep anyway. Additionally, if you happen to have exactly 25 rage and Whirlwind is off cooldown, LazyArms skips the proc and casts Whirlwind instead.

### Spell queue collision prevention

Nampower allows spells to be queued before the GCD expires. LazyArms listens to `SPELL_QUEUE_EVENT` to track what is currently queued. Mortal Strike will not overwrite a queued Whirlwind, and Whirlwind will not overwrite a queued Mortal Strike. Slam will not cast if either is queued, since those instants should land first.

### Everything is read from your actual character

Spell IDs and rage costs are not hardcoded. On login and whenever your spellbook changes, LazyArms looks up the highest rank of every ability you know from the DBC and reads the actual rage costs from the spell records. Swing speed, cast speed modifier, weapon base speed, damage values, rage, and max rage are all read from unit fields at runtime. If you get a cast speed debuff, the Slam window recalculates automatically.

### Combat detection without polling

Rather than checking `UnitAffectingCombat` on every keypress, LazyArms registers for Nampower's `UNIT_FLAGS_GUID` event and caches the player's in-combat flag whenever it changes. `in_combat()` is a simple boolean read.
