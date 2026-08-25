# The Authoring Kit — how children build content without writing code

**The owner builds the mechanics once. The children build mazes, vehicles and
ghosts on top of them, in Studio, with no scripting.**

This document defines the contract between the two. It is the most important
architectural decision in the project, because it decides how much of the
game the kids can actually own — and because everything they build has to keep
working when the engine changes underneath it.

---

## 1. The principle: content is geometry plus labels

Kid-built content contains **no scripts, ever**. It is parts, models, and two
kinds of label:

- a **tag** (CollectionService) that says *what a thing is* — this is a wall,
  this is a pellet, this is a gate
- **attributes** that say *what its numbers are* — this gate's Threat is 250

At run time the engine asks CollectionService for everything with a given tag,
reads the attributes off each one, and wires up the game. Nothing in the
Workspace has to know the engine exists.

Three things fall out of that, all of them worth having:

1. **A child cannot break the game.** The worst they can do is build a bad
   maze, and the validator (§5) catches most of that before anyone plays it.
2. **No free-model scripts ever enter the place** — content is not allowed to
   contain scripts, so the rule is structural rather than a thing to remember.
3. **The engine can be rewritten without touching their work.** Their maze is
   data. It survives.

Tagging is two clicks in Studio's Tag Editor. Setting an attribute is typing a
number into a box in the Properties panel. Both are within reach at seven.

---

## 2. The tag vocabulary

This table is the entire interface. If it isn't here, the engine ignores it —
so decoration, colour, and anything else they want to build is automatically
safe and automatically free.

| Tag | Goes on | Attributes | Meaning |
|---|---|---|---|
| `Chomp_Wall` | a part | — | Solid. Blocks driving and ghost pathing |
| `Chomp_Pellet` | a small part | `Value` (number) | A pellet spawns here and respawns after eating |
| `Chomp_PowerPellet` | a part | `Duration` (seconds) | Full Jaw pickup |
| `Chomp_Garage` | a part | `Slot` (1-8) | One player's home and bank |
| `Chomp_Gate` | a part | `Ring`, `Threat` | A super ghost stands here guarding this ring |
| `Chomp_Ring` | a big invisible part | `Ring`, `PelletValue` | Marks which ring an area belongs to |
| `Chomp_GhostSpawn` | a part | `Behaviour` (name) | A ghost of that personality starts here |
| `Chomp_Vehicle` | a model | `Tier`, `Bar`, `Power`, `Speed`, `Turn` | A drivable chassis |
| `Chomp_Mouth` | a part inside a vehicle | — | Marks which way the mouth faces |
| `Chomp_Ghost` | a model | `Behaviour` | A ghost's appearance |
| `Chomp_Decor` | anything | — | Purely visual. The engine never touches it |

`Chomp_Decor` earns its place by being useless: it is the explicit permission
slip that says *build whatever you like here and nothing will go wrong.*

---

## 3. Where things live

```
Workspace
└── Maps
    ├── ClassicGrid              ← one folder per map. Duplicate it to start a new one
    │   ├── Quadrant             ← THE ONLY PART A CHILD BUILDS
    │   │   ├── Walls
    │   │   ├── Pellets
    │   │   ├── Gates
    │   │   └── Decor
    │   └── Generated            ← the mirror tool writes the other three rotations here
    ├── LongHalls
    └── ...

ReplicatedStorage
├── ChompConfig                  ← one ModuleScript. Every tunable number in the game
├── Vehicles                     ← kid-built chassis models
└── Ghosts                       ← kid-built ghost models

ServerScriptService
└── ChompEngine                  ← the owner's code. Children never open this folder
    └── Behaviours               ← one small module per ghost personality
```

**Making a new level is duplicating a folder and renaming it.** That is the
whole workflow, and it is a thing a seven-year-old can do unaided on a Saturday
morning without asking anyone.

---

## 4. The mirror tool — fairness for free, and a quarter of the work

Children build **one quadrant**. A one-button tool copies it three times at 90°,
180° and 270° into `Generated`.

This is worth building early, for three reasons:

- The four-fold symmetry that makes a maze **fair** is guaranteed by the method
  rather than checked by an adult.
- It cuts the building work to a quarter, which matters enormously when the
  builder is seven and the maze is large.
- It is *visibly magic*. You place four walls and sixteen appear. That is the
  moment a child understands that the computer can do work for them, which is
  the actual lesson underneath all of this.

---

## 5. "Check My Maze" — the validator

A button that reads the tags and reports problems **in the child's language,
not in error codes**:

| Check | What it says when it fails |
|---|---|
| Every ring has gates | "Ring 3 has no doors! Nobody can get in." |
| Exactly four gates per ring | "Ring 2 has 3 doors. It needs 4, one on each side." |
| A garage per player slot | "Only 3 garages — the 4th player has nowhere to live." |
| Pellets not inside walls | "12 pellets are stuck inside a wall. Nobody can eat those." |
| Walls on the grid | "6 walls are wonky. Press Snap to fix them." |
| Quadrant stays in bounds | "Something is sticking out past the quadrant line." |
| Ghost behaviour exists | "One ghost is set to 'Sneaky' and there's no such ghost." |
| Pellet count per ring | "Ring 4 only has 8 pellets. It's supposed to be the treasure room." |
| Vehicle has one mouth | "This car has two mouths. Pick one." |
| No scripts in content | "There's a script hiding in this model. Delete it." |

The last check is the safety rule from §1 made automatic.

This is the same idea as `mbse/infrastructure/validate.py` — never trust that a
hand-built thing is internally consistent, compute the check — pointed at a
seven-year-old's maze instead of a requirements tree. It is also what lets her
iterate **without an adult sitting next to her**, which is the difference
between a project she helps with and a project she owns.

---

## 6. The tuning table

`ReplicatedStorage/ChompConfig` is one ModuleScript holding every number in the
game and nothing else — no logic:

```lua
return {
    HeadOnBarLoss      = 0.40,   -- how much of your bar a head-on costs
    BiteBarCost        = 0.30,   -- how much of your bar a side bite costs
    ChompScatter       = 0.50,   -- share of your carry dropped when destroyed
    GhostSteal         = 0.25,   -- share of your carry a ghost takes
    InvulnSeconds      = 1.50,
    FullJawSeconds     = 8.00,
    ComboWindow        = 1.50,
    ComboMax           = 5,
    RingThreat         = { [2] = 250, [3] = 500, [4] = 800 },
    RoundSeconds       = 360,
    RoundsPerMatch     = 5,
}
```

This file is for reading aloud and arguing about. "Ghosts take a quarter of your
sweets — is that too mean?" is a design conversation a seven-year-old can hold
an opinion in, and changing `0.25` to `0.15` and immediately playing it is the
tightest feedback loop in the whole project.

Every number lives here exactly once. If a number appears in the engine code as
a literal, that's a bug in the engine.

---

## 7. The ladder — three tiers of authoring

The kit is deliberately built so there is always a next rung:

**Tier A — build (age ~7).** Place walls, pellets, gates and garages. Recolour
and name things. Set attribute numbers. Press mirror, press check, press play.
No text, no logic, no reading required beyond the labels.

**Tier B — tune (age ~9-11).** Edit `ChompConfig`. Design a ring progression
and its Threat curve. Build a new chassis model and give it its stats. Balance
the thing: decide *why* Ring 3 should be worth the risk, then change numbers
until it is. This is systems thinking, and it is where most of the real
learning is.

**Tier C — extend (age ~12+).** Write a new ghost personality — one small
module, one function:

```lua
-- ServerScriptService/ChompEngine/Behaviours/Sneaky.lua
return function(ghost, junction, world)
    -- Called at every junction. Return one of world.directions.
    local target = world.playerWithMostCarried()
    return world.directionAvoidingMouth(junction, target)
end
```

Ten lines, no engine knowledge, and a new enemy appears in a game their sister
is already playing. That is the on-ramp from *placing things* to *writing
things*, and it exists because the engine has hook points rather than a
hard-coded list of four ghosts.

---

## 8. What this costs the owner

Building the kit is more work up front than hard-coding one maze — the tag
reader, the mirror tool, the validator and the config indirection are real
work that produces no visible gameplay on the first evening.

It is worth it here for one reason: **the alternative is that every change the
children want goes through you.** A hard-coded game means "Dad, can you make
the ghosts slower" is a request in a queue. The kit means it's a number she
changes herself while you're making dinner, and the game she plays on Sunday is
one she actually built.

Build the kit as v1, with a single ring and one ghost, and ship the rest as
content on top of it.
