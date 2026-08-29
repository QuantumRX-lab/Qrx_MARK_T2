# Control Scheme

**Current as of `D-CHOMP-074`.**

> ### Status: built, awaiting device verification
>
> The cycle button, the `X` / `C` / `E` keys and the landscape request are
> implemented in release `0.4.0-alpha`. The essential HUD is parented before
> the optional orientation request, which is protected by `pcall`, so a platform
> property failure cannot make the HUD disappear.
>
> Desktop Studio and target-iPad checks are still required before this control
> layout is accepted.

**One thumb drives. One finger fires. Two buttons do what a gesture cannot.**

This document was wrong for two days, and it is worth saying why, because the
failure is instructive: it described the grid driving of `D-CHOMP-033` after
`D-CHOMP-042` had replaced it, and it declared "the absence of buttons is the
design, not a gap in it" after the game had already grown three. An architecture
spec that lags the build is worse than no spec, because it is believed.

## The scheme

| | |
|---|---|
| **Steer** | Proportional. Push the stick, the vehicle turns at a rate set by how far you push. No snapping, no cardinal directions — a ring corridor has no north (`D-CHOMP-042`) |
| **Throttle** | The same stick. Forward drives, back reverses and swings the nose round. Release and the vehicle coasts to a stop over `Braking` |
| **Fire** | HELD, not tapped. The cannon is a machine gun and the SERVER paces it at `fireRatePerSecond`; the client only says "still holding" (`D-CHOMP-056`) |
| **Jump** | The charge button. Costs `Charge.JumpCost`, carries you up and forward, and is the only escape the player controls. Bottom right |
| **Swap** | Cycle forward through occupied belt slots, wrapping. Purely positional; it never chooses for the player. An item can also be chosen by tapping its slot |
| **Bank** | Automatic on any garage pad. No button, no prompt (`D-CHOMP-048`) |
| **Buy** | Dwell beside a plinth. No menu, no confirmation dialog (`D-CHOMP-055`) |

## Touch — the reference platform

The stick **floats**: it anchors wherever the thumb lands, so there is nothing to
find and nothing to lose if the thumb drifts (`D-CHOMP-027`, whose floating
anchor survived every later revision).

**A second finger anywhere holds fire.** This was the single biggest gap between
the designed game and the played one: a second touch used to be discarded
entirely, so the machine gun was keyboard-only on the one device this game is
for, and shooting meant letting go of the wheel. A quick tap of the *stick*
finger also fires, for one-handed play.

### Where the buttons are, and why

```
 +---------------------------------------------+
 |                                             |
 |   steering: the whole left half,            |
 |   the stick anchors where you touch         |
 |                              carried/banked |
 |                                      health |
 |                                    belt x5  |
 |                            ( SWAP )( JUMP ) |
 +---------------------------------------------+
```

Both action buttons are **bottom right**, and neither is on the left. The reason
is the floating stick: every button on the left shrinks the area you can start
steering in, and worse, it means letting go of the wheel to press the one
control that exists to save you. **The escape move must never cost you the
steering.**

Bottom-right is also where **Roblox's own touch jump button** lives, so a child
who plays other Roblox games already reaches there. Convention beats our
preference when the audience has muscle memory.

They are **sized by urgency**:

- **Jump, 128px, in the corner.** A panic button, pressed without looking, while
  something is chasing you. The largest control on screen, and the one a thumb
  finds by feel.
- **Cycle, 96px, beside it.** A planning action done between fights. Smaller,
  because getting it wrong costs a wrong weapon rather than a wall.

## Keyboard, for building in Studio

Movement, fire, jump and swap keyboard routes are built.

| Key | Action |
|---|---|
| `W` `A` `S` `D` / arrows | steer and throttle; opposed keys cancel to neutral |
| `Space` | fire, held |
| `C` or `E` | jump |
| `X` | cycle the belt |

`E` is an alias for jump because it is the key a Roblox player tries first — the
platform's universal interact key. `Space` is fire rather than jump because the
default control script is disabled (`D-CHOMP-023`), so the conventional jump key
was free and the trigger needed a held key more.

## Orientation

**Landscape only.** `PlayerGui.ScreenOrientation` is locked at startup.

This is a driving game in a wide arena, and the right-hand column does not fit a
portrait iPad once the action buttons are on it. `CHOMP-SYS-032` originally
required both orientations; it was **amended** to require landscape rather than
left to be silently violated.

If a device reports portrait anyway, the **cycle** button hides. An item can
still be chosen by tapping its slot; Jump remains visible.

## Why there are buttons at all

The original scheme had none and was right to be proud of it. But it was the
scheme for a game whose only verbs were **drive** and **eat**.

The game acquired three more — **spend an item**, **choose an item**, **jump** —
and no gesture carries those. Every gestural alternative turns into a memory
test: a double-tap meaning one thing while driving and another while stopped is
exactly the kind of hidden rule a seven-year-old cannot learn by playing.

So the rule is not "no buttons". The rule is:

> **A button must be a verb the player already knows they have.**

Jump, swap. Nothing modal, nothing that changes meaning by context, nothing that
needs teaching. Banking and buying stay buttonless because *driving somewhere*
already expresses them.

## What is not decided

- Whether reversing should mirror the steering axis. It currently does not, so
  holding back-and-left swings the nose the same way as forward-and-left. That
  reads as turn-around rather than as reversing a car, and **nobody has felt it
  on a device**.
- Whether the belt should also answer number keys `1`–`5`, matching Roblox's
  Backpack convention. Cheap to add; unclear whether a child would use it.
- Every handling number — speed, turn rate, braking, reverse fraction — is a
  first guess. Tuning is deferred rather than done blind.
