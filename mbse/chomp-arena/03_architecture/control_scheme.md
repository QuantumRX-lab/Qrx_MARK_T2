# Control Scheme

**Hold to turn. Always driving forward. No buttons.**

That is the entire control scheme, and the absence of buttons is the design,
not a gap in it.

## The scheme

| | |
|---|---|
| **Forward** | Automatic. The vehicle is always moving at its current top speed. There is no accelerator and no brake |
| **Steer** | Touch and hold anywhere on the left of the screen to turn left, the right to turn right. Release to go straight |
| **Turn rate** | Proportional to how far from centre you hold — near the dead zone edge is a gentle curve, near the screen edge is full lock |
| **180° flip** | Double-tap the opposite side within 0.35 s. Costs `ReverseFlipSeconds`; Agility II makes it much faster |
| **Bank** | Automatic on entering your garage. No button, no prompt |
| **Buy** | Big tap targets, at your garage and during intermission. The only menu in the game |

Keyboard equivalent, for building in Studio: hold `A`/`D` or the arrow keys to
steer, double-tap the opposite key to flip. No forward key — the same rule
applies.

## Why this one

**No stick to lose.** A virtual thumbstick has an origin that drifts, gets
dropped mid-corner, and needs a visual to find. Hold-to-turn has no origin: any
touch on the correct side works, so a seven-year-old cannot lose it and a
panicking adult cannot fumble it.

**Turning is the whole skill, so turning gets the whole input.** Agility is
what converts a flank hit into a head-on. Giving steering the entire screen —
rather than a 120-pixel puck — is what makes that defensive move actually
performable under a thumb.

**Always-forward is Pac-Man.** The original has no stop, and stopping is not an
interesting choice: it makes you a stationary target with no upside. Removing it
also removes an entire class of "she doesn't know why she isn't moving".

**Zero action buttons means zero occlusion problems.** Banking, eating, Full
Jaw and gate passage are all consequences of driving somewhere. The only thing
the screen has to hold is the HUD, which can then sit clear of both thumbs.

## Proportional turning, with a dead zone

```
   screen x:  0.0        0.29    0.40  0.50  0.60    0.71        1.0
              |‹— full ——|‹ ramp ›|‹— dead ——›|‹ ramp ›|—— full —›|
                  left                straight              right
```

- Middle **20%** is a dead zone — a resting thumb does not steer.
- From the dead zone edge to **42%** out, turn rate ramps linearly from zero to
  full. Adults get fine control, and a child who just jams the screen edge gets
  full lock without needing precision.
- **Both sides held at once cancels to straight.** Predictable, and it is what
  a panicking player does.

## Thumb-safe zones

The bottom-left and bottom-right corners — 30% of screen width by 30% of
height — are where thumbs live. The HUD must place nothing there
(`CHOMP-SYS-032`). Bar, carry and gate readiness go top-left and top-centre;
standings top-right; nothing along the bottom edge.

## Considered and rejected

**A brake.** Adds skill expression for an adult, but it makes the child's
default state "stopped and confused", and a braking player in a corridor is a
free flank hit for anyone behind. Pac-Man's constant motion is load-bearing.

**Swipe-to-turn (one flick per junction).** Cleaner in theory, and it is how
some mobile Pac-Man ports work. Rejected because it decouples input from
timing: this game's combat is about *when* you bring your mouth to bear, and a
gesture that resolves at the next junction takes that away.

**A virtual thumbstick.** See above — the drifting origin is the killer.

Logged as `D-CHOMP-015`.
