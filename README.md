# LazyArms

A one-button 2H Arms Warrior rotation addon for [TurtleWoW](https://turtlecraft.gg/).

Create a macro with `/lazyarms` or `/lazyarmsaoe`, put it on your action bar, and spam it. The addon handles ability prioritization, stance dancing, rage management, and swing timing for you.

## Requirements

- [pfUI](https://github.com/me0wg4ming/pfUI) (with libdebuff)
- [Nampower](https://gitea.com/avitasia/nampower)
- [SuperWoW](https://github.com/balakethelock/SuperWoW)
- [UnitXP_SP3](https://codeberg.org/konaka/UnitXP_SP3)

## Features

### Single-target (`/lazyarms`)

Priority-based rotation:

1. **Auto Attack** - ensures auto attack is active
2. **Charge / Intercept** - gap closers when 8-25 yards from target (Intercept blocked on non-aggroed mobs in instances)
3. **Berserker Stance** - switches if not already in it
4. **Battle Shout** - maintains the buff
5. **Execute** - target below 20% HP
6. **Sunder Armor** - maintains 5 stacks, refreshes below 5s remaining, skips 0-armor targets
7. **Overpower / Revenge** - reactive abilities when available and rage is low
8. **Mortal Strike** - top priority spender
9. **Whirlwind** - second priority spender
10. **Slam** - filler, gated on auto-attack timing to avoid delaying swings
11. **Heroic Strike** - rage dump above 80 rage to prevent capping

### AoE (`/lazyarmsaoe`)

Optimized for multi-target:

1. Pre-rotation (auto attack, charge, stance, shout)
2. **Sweeping Strikes** - activated on cooldown
3. **Cleave** - kept queued as on-swing rage dump
4. **Whirlwind** - top GCD priority
5. **Sunder Armor** - single application per target for tab-sundering
6. **Mortal Strike** - GCD filler
7. **Execute** - low priority finisher

### Smart behaviors

- **Swing-aware Slam** - only casts Slam after an auto-attack lands, preventing swing timer resets
- **Spell queue tracking** - avoids overwriting queued instants (MS won't overwrite a queued WW and vice versa)
- **Combat state caching** - uses `UNIT_FLAGS_GUID` events for efficient combat detection
- **Cross-stance gap closing** - uses distance checks instead of `IsSpellInRange` to work regardless of current stance
- **Rage normalization** - reads raw rage from unit fields and converts to the displayed value
- **State persistence** - rotation state survives `/reload` via global scope

## Installation

Copy the `LazyArms` folder into your `Interface/AddOns/` directory.

## Usage

Create macros with the following commands and place them on your action bar:

```
/lazyarms      - single-target rotation
/lazyarmsaoe   - AoE rotation
```

Spam the macro button during combat.
