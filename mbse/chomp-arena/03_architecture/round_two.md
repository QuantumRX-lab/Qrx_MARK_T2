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

Concretely: **perches**. Raised blocks reached with the two moves the player
already has — the **charge jump** and the **jet pack** — from which a stationary
player fires **homing missiles** down into the maze.

No climbing and no platforming. Reusing the existing mobility is the point: the
same button that saves you from a corner is the one that puts you above the
maze, so there is nothing new to teach and nothing new to fail at. §7 explains
why this is the most valuable idea in the sketch.

Everything else — ring corridors, pellets, garages, sanctuaries, waves — carries
over unchanged. The new maze earns its place through the perches and the new
weapons, not through novelty for its own sake.

## 5. Weapons as answers to fears

The test for whether a weapon earns a belt slot: **what fear does it answer?**
If two weapons answer the same fear, one is a skin.

| Weapon | The fear | The cost | Status |
|---|---|---|---|
| Cannon | "that one, in front of me" | needs a lock, needs facing | built |
| Bomb | "they are following me" | placed behind, two taps | built |
| Shield | "I am about to lose the carry" | one hit only | built |
| Jet pack | "I am cornered" | one use, no aiming | built |
| **Flamethrower** | **"they are ALL around me"** | very short range — they must get close | Round Two |
| **Homing missile** | **"that one, far away"** — and the perch weapon | slow, one target, long lock | Round Two |

Flamethrower and homing missile are a good pair precisely because they are
opposites: panic-close versus patient-far. Between them they cover the two
situations the current belt handles worst — being surrounded, and being unable
to reach the ghost that is hurting you.

### Notes that constrain implementation

- **Flamethrower** is a *cone*, not a projectile, and should be the only weapon
  that hits several ghosts at once. Held, drains fast, and lights the corridor
  while it burns — it is also the best light source in a dark game.
- **Homing missile** must be visibly slow. If it is fast it is just a cannon
  with more steps. Its pleasure is watching it turn.
- The missile is also **the reason perches exist**. It is the weapon that works
  from a standstill at range, so it earns its slot twice: once on the ground
  against a ghost you cannot line up, once from above as the sniping tool. A
  perch without a weapon built for it is just a place to hide.
- Both obey `CHOMP-SYS-066`: with friendly fire off they may not damage another
  player **by any route**, and a cone weapon is exactly where that rule gets
  forgotten.

## 6. Sniper perches, and the constraint that shapes them

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
- **Perches are reached by charge jump or jet pack**, and are small — a place to
  stand, not a platform to traverse. No jumping between them, and no new
  traversal mechanic: if a player cannot already get up there with the moves
  they have, the perch is in the wrong place.
- **A perch is a room, not a route.** The guardian chamber already proves a
  separate contained space works; a perch should be as contained.
- **Nothing required is ever up there.** No pellets, no pads, no bank. A player
  who never goes up must not be behind one who does.

If `CHOMP-TC-040` fails on Level 1, perches do not get built. That is the
dependency, and it is not negotiable.

## 7. Everyone gets a job

The strongest thing in the sketch, and the reason perches are worth the risk.

The game currently has one verb — drive and chomp — so in co-op everyone does
the same thing, and the least coordinated player simply dies more. A perch is a
**stationary, ranged, safe-ish role**, which is exactly the job for whoever is
worst at driving: the youngest, or the friend who keeps hitting walls.

A guardian fight with three jobs is dramatically better co-op than three people
doing one job:

| Role | Does | Suits |
|---|---|---|
| **Bait** | holds the guardian's attention, stays alive | the confident driver |
| **Sweeper** | clears the ghosts it summons | the middle player |
| **Gunner** | perched, puts homing missiles into the weak point when it opens | the one who keeps crashing |

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

1. **`CHOMP-TC-040` passes on the iPad** on flat Level 1. Perches depend on it,
   and so does any further vertical design.
2. **The current guardian is played** by the actual audience, at least twice.
   Everything in §3 is a guess until someone watches a child fight it.
3. **The §8 decision is made**, because it changes how Level 2 is tuned.
4. Then: boss phases (§3), then weapons (§5), then the maze, then perches (§6).

Perches last, deliberately. They are the most exciting item on the list and the
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
