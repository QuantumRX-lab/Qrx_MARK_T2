# Round Two — bosses, the second maze, and what unlocks it

**Status: SPECIFICATION. None of this is built.**

Written 2026-08-27 from an ideation session with the owner. It describes the
shape of the game *after* Level 1, and it deliberately starts from what already
exists rather than from the sketch, because a guardian landed while we were
talking.

Nothing here is a requirement yet. Requirements come after the open questions in
§8 are answered, and after `CHOMP-TC-040` has actually run.

---

## 1. What already exists

`GuardianService` is built and running. It is worth reading before this document,
because Round Two is mostly a re-framing of it rather than new machinery.

| | |
|---|---|
| **Where** | A chamber *beneath* the Level 1 centre, reached by a hatch and a shaft (`ChamberY = -260`) |
| **Gate** | `RequiredPower = 500`. Under that, you deal a quarter damage — you are let in but you cannot win |
| **Health** | `120`, plus `40` per victory. It gets harder every time you beat it |
| **Reward** | `15,000` dollars |
| **Space** | Cover at two radii, item pickups that respawn every 8s |
| **Shape** | **Infinite.** An endlessly escalating rematch |

The important thing that is already proven: **a separate vertical space, entered
through a hatch, works.** The camera problem that killed the two-deck map
(`D-CHOMP-046`) does not apply to a self-contained room you drop into. That
changes what is safe to build in §6.

## 2. What Round Two changes

Today the guardian is a **treadmill**: beat it, get paid, beat a harder one. It
has no destination.

Round Two makes the *first* victory mean something permanent, without taking the
treadmill away:

> **The first guardian victory unlocks Level 2. Every victory after that is the
> ladder it already is.**

That costs almost nothing to build — one persisted flag — and it converts the
best thing in the game into a door.

### The session shape it produces

```
  waves 1-5  ~8 min   collect, bank, upgrade, survive
  guardian   ~2 min   the fight you prepared for
  VICTORY            a win, a natural place to stop
  ...later           Level 2 is open, permanently
```

That last line matters more than the content. The game currently has **no
ending** — waves escalate until you die. A win is what lets a seven-year-old
stop playing feeling good, which is the difference between a game a parent
allows and one a parent regrets.

## 3. The boss pattern, generalised

Every level ends in a guardian. To be beatable by a child, each one obeys four
rules — none of which the current guardian fully does yet:

1. **One visible weak point.** Not a health bar you erode: a *thing you hit*.
   She must be able to tell a friend "hit the eye".
2. **Telegraphs of at least 1.5 seconds**, with sound, before anything that
   hurts. Bosses are frightening because you see it coming, not because it is
   fast.
3. **Phases change the verb, not the numbers.** Chase it → clear the ghosts it
   summons → pile in while it is open. "The same fight but faster" teaches
   nothing.
4. **It can never one-shot you.** There is always a scare, then a chance to run.

The existing `ContactDamage = 28` against 100 health satisfies rule 4 with room
to spare. Rules 1–3 are the work.

## 4. Level 2 — what makes it different

Not "the same maze, harder". The maze must ask a different question.

| Level 1 asks | Level 2 asks |
|---|---|
| Can you route and bank under pressure? | Can you route and bank when the floor is not all one place? |

Concretely: **floating blocks**. Raised blocks reached with the two moves the player
already has — the **charge jump** and the **jet pack** — from which a stationary
player fires **homing missiles** down into the maze.

No climbing and no platforming. Reusing the existing mobility is the point: the
same button that saves you from a corner is the one that puts you above the
maze, so there is nothing new to teach and nothing new to fail at. §7 explains
why this is the most valuable idea in the sketch.

Everything else — ring corridors, pellets, garages, sanctuaries, waves — carries
over unchanged. The new maze earns its place through the floating blocks and the new
weapons, not through novelty for its own sake.

## 5. The two new weapons

Numbers are starting points to tune, not decisions. Both are specified against
what the cannon already does, because "different from the cannon" is the only
thing that makes a belt slot worth spending.

### Homing missile — the weapon floating blocks exist for

| | |
|---|---|
| charges | 1 |
| speed | ~70 studs/s (cannon: 360 — slow enough to watch it turn) |
| turn rate | ~90°/s toward the locked target |
| range | ~320 studs (cannon: 170 — the extra reach is the point of height) |
| lock | reuse the cannon's, unchanged: 0.45s, red-to-green reticle |
| damage | one normal ghost, like everything else |
| walls | stops at them, same swept raycast as the cannon |

It is the only weapon that reaches past the cannon. That is what makes standing
still on a block worth doing, and it is why the missile and the blocks have to
ship together or not at all.

### Flamethrower — the close answer

| | |
|---|---|
| trigger | HELD, like the cannon |
| shape | cone ~45°, ~40 studs, from the kart nose |
| targets | **every** ghost in the cone — the only weapon that does |
| fuel | a bar, ~2.5s of continuous fire. Not discrete charges: a cone spent in "shots" reads wrong |
| light | a PointLight on the cone while firing. Brightest thing in a dark game |
| damage | one tick kills a normal ghost. Do not stack ticks per frame |

### Both

Must respect `CHOMP-SYS-066`: friendly fire off means **no damage to another
player by any route**. The cone is exactly where that gets missed — gate the
HIT, not the targeting.

## 6. Floating blocks, and the constraint that shapes them

This is the part of the sketch most likely to break the game, and it is worth
being explicit about why.

`D-CHOMP-046` deleted the two-deck map for two reasons: **a drop is a way to
fall out of the map**, and the camera could not follow between levels without a
jump cut. `CHOMP-TC-040`, the camera acceptance test, **has still never run on
even one flat level.**

Floating blocks are decks with more edges. So they are only safe under rules:

- **Falling is harmless.** You drop, you land, you drive on. No damage, no lost
  carry. The moment falling is punished, an unproven camera becomes a fairness
  problem.
- **Floating blocks are reached by charge jump or jet pack**, and are small — a place to
  stand, not a platform to traverse. No jumping between them, and no new
  traversal mechanic: if a player cannot already get up there with the moves
  they have, the block is in the wrong place.
- **A block is a room, not a route.** The guardian chamber already proves a
  separate contained space works; a block should be as contained.
- **Nothing required is ever up there.** No pellets, no pads, no bank. A player
  who never goes up must not be behind one who does.

If `CHOMP-TC-040` fails on Level 1, floating blocks do not get built. That is the
dependency, and it is not negotiable.

## 7. Everyone gets a job

The strongest thing in the sketch, and the reason floating blocks are worth the risk.

The game currently has one verb — drive and chomp — so in co-op everyone does
the same thing, and the least coordinated player simply dies more. A block is a
**stationary, ranged, safe-ish role**, which is exactly the job for whoever is
worst at driving: the youngest, or the friend who keeps hitting walls.

A guardian fight with three jobs is dramatically better co-op than three people
doing one job:

| Role | Does | Suits |
|---|---|---|
| **Bait** | holds the guardian's attention, stays alive | the confident driver |
| **Sweeper** | clears the ghosts it summons | the middle player |
| **Gunner** | on a block, puts homing missiles into the weak point when it opens | the one who keeps crashing |

The design goal is that a seven-year-old who is *bad at driving* still has
something she is unambiguously good at.

## 8. The decision the owner has to make

**If Level 2 gives flamethrowers permanently, what happens to Level 1?**

The old design doc says permanent rewards stay cosmetic *"so experienced players
never enter a match with a power advantage."* That rule is **already broken** —
`ProfileService` persists dollars, chassis and upgrades (`D-CHOMP-069`).

Two coherent answers:

- **A — power persists, Level 1 becomes easy.** Going back to the first maze
  overpowered is one of the great childhood video-game pleasures. It is a
  victory lap, not a balance failure. Level 2 is then tuned for a player who
  *arrives* armed.
- **B — weapons are level-scoped.** Flamethrowers exist only in Level 2. Level 1
  stays exactly as tuned, and a friend joining at any level meets the same game
  everyone else does.

**Recommendation: A**, unless friends joining at mixed progression is a common
case — in which case B, and it must be decided *before* the second maze is
designed rather than after.

## 9. What must be true before any of this starts

In order. Nothing below the first unchecked line should begin.

1. **`CHOMP-TC-040` passes on the iPad** on flat Level 1. Floating blocks depend on it,
   and so does any further vertical design.
2. **The current guardian is played** by the actual audience, at least twice.
   Everything in §3 is a guess until someone watches a child fight it.
3. **The §8 decision is made**, because it changes how Level 2 is tuned.
4. Then: boss phases (§3), then weapons (§5), then the maze, then floating blocks (§6).

Floating blocks last, deliberately. They are the most exciting item on the list and the
one most likely to reintroduce the problem that deleted the last map.

## 10. Open questions

- Does the first-victory unlock persist **per player** or per server? Per player
  is obvious for progression and awkward for co-op — does a friend who has never
  beaten the guardian get into your Level 2?
- Does Level 2 have its own guardian, and does *that* unlock Level 3? An
  unbounded ladder of mazes is a lot of content for one child.
- Do ghosts differ in Level 2? `V1Behaviours` names `Chaser` and `GreedyOne` in
  config and **nothing reads it** — every ghost in the game today runs one
  identical behaviour. Ghost variety may be a better Round Two than a second
  maze, and it is cheaper.
- Does the flamethrower need a fuel gauge separate from charges? A cone weapon
  spent in discrete "charges" reads oddly.
