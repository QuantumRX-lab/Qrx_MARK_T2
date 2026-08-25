# Control Scheme

**One floating stick. Forward to drive, left and right to turn, back to turn around.**

That is the entire control scheme, and the absence of buttons is the design,
not a gap in it.

## The scheme

| | |
|---|---|
| **Forward** | Push the stick up. Release to centre and the vehicle coasts to a stop over `Braking` |
| **Steer** | Push the stick left or right. Turn rate is proportional to deflection, so a small push is a gentle curve and the rim is full lock |
| **Turn rate** | Proportional to how far from centre you hold — near the dead zone edge is a gentle curve, near the screen edge is full lock |
| **Reverse / turn around** | Pull the stick back. Reverse runs at `ReverseSpeedFraction` of top speed, and the vehicle swings to face where it is going, so backing out of a dead end reads as turning around |
| **180° flip** | Keyboard only for now: double-tap the opposite key within 0.35 s. Costs `ReverseFlipSeconds`; Agility II makes it much faster |
| **Bank** | Automatic on entering your garage. No button, no prompt |
| **Buy** | Big tap targets, at your garage and during intermission. The only menu in the game |

Keyboard equivalent, for building in Studio: `W`/`Up` to drive, `S`/`Down` to
reverse, `A`/`D` or `Left`/`Right` to steer, double-tap the opposite steering key
to flip. Opposed keys cancel to neutral on both axes.

## Why this one

**No stick to lose — still true, differently.** A *fixed* thumbstick has an
origin that drifts, gets dropped mid-corner, and needs a visual to find. A
floating stick re-anchors on every touch, so any touch anywhere is a valid grip:
a seven-year-old cannot miss it and a panicking adult cannot fumble it. Only one
finger drives; a second touch is ignored rather than averaged in, because
averaging two touches is how a panicking player ends up going straight.

**Turning is the whole skill, so turning gets the whole input.** Agility is
what converts a flank hit into a head-on. Giving steering the entire screen —
rather than a 120-pixel puck — is what makes that defensive move actually
performable under a thumb.

**A floating stick, after playing both alternatives.** The tree first specified
constant motion (`D-CHOMP-015`), then briefly gated movement on the steering hold
(`D-CHOMP-026`). Playing the second exposed the flaw immediately: if holding left
or right is the only way to move, the vehicle can only ever travel in an arc, and
driving straight down a corridor is impossible. That is fatal in a maze.

The answer is a stick, which `D-CHOMP-015` rejected — but the objection there was
specifically that a stick *with a fixed origin* drifts, gets dropped mid-corner,
and needs a visual to find. A floating stick has none of those properties: it
anchors wherever the finger lands, so it cannot be missed and cannot be lost
(`D-CHOMP-027`). Releasing coasts rather than stopping dead, so letting go
mid-corner is a decision, not a punishment.

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

**A separate brake, and a separate accelerator.** Both were rejected for the
same reason and both stay rejected: they are a second thing to hold on a tablet
with no buttons. Under `D-CHOMP-026` releasing the steering hold already brakes,
so the capability exists without the control. The original objection — that a
child's default state becomes "stopped and confused" — is answered by the fact
that the only thing she can do wrong is let go, and letting go is visibly what
stopped her.

**A fixed-origin thumbstick.** Still rejected, and for the original reason: a
puck drawn at a fixed spot has to be found by eye and is lost the moment the
thumb drifts off it. The stick in `D-CHOMP-027` is floating, which is a different
control that happens to share a name.

**Swipe-to-turn (one flick per junction).** Cleaner in theory, and it is how
some mobile Pac-Man ports work. Rejected because it decouples input from
timing: this game's combat is about *when* you bring your mouth to bear, and a
gesture that resolves at the next junction takes that away.

**A virtual thumbstick.** See above — the drifting origin is the killer.

Logged as `D-CHOMP-015`.
