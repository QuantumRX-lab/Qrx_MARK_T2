# Level Two — the concept

**Status: concept. Nothing built.** Detail and build order live in
`03_architecture/round_two.md`.

---

## The idea in one line

**Beat the guardian once, and a second maze opens — one built around height,
where you jump or jet-pack up out of the chase and rain homing missiles down
into it.**

## How you get there

The guardian already exists. It sits in a chamber beneath the centre of Level 1,
behind a Power gate, and it gets harder every time you beat it — an endless
rematch with no destination.

Level Two gives it one:

> **The first victory unlocks the second maze, permanently. Every victory after
> that stays the ladder it already is.**

Nothing else about the guardian changes. The treadmill is still there for anyone
who wants it; it just now has a door at the end of the first lap.

## What that fixes

The game currently has **no ending**. Waves escalate until you die, so every
session finishes on a loss.

A guardian victory gives the evening a shape — *waves, boss, win* — and a
natural place to stop. For a game a seven-year-old plays before bed, that is
worth more than any new weapon.

## What makes the second maze different

Not "the same maze, harder". It asks a different question.

| Level One asks | Level Two asks |
|---|---|
| Can you route and bank under pressure? | Can you do it when the floor isn't all one place? |

**Floating blocks.** Raised blocks you reach with the two moves you already have — the
**charge jump** or the **jet pack**. No climbing, no platforming, no new
traversal to learn: the same button that saves you from a corner is the one that
puts you above the maze.

Once up there, the **homing missile** is the weapon. You stop, you lock, and you
send it down into the corridors. That is a genuinely different verb from
drive-and-chomp, and it costs you your mobility while you do it.

Rings, pellets, garages, sanctuaries and waves all carry over unchanged. The new
maze earns its place through the floating blocks and the new weapons — not through
novelty.

## Two new weapons

Two weapons, doing things the current belt cannot:

| Weapon | What it does | What it costs |
|---|---|---|
| **Flamethrower** | a held cone from the nose — hits **every** ghost in it, and lights the corridor while it burns | ~40 studs. They have to be close, and it drains fast |
| **Homing missile** | one slow shot that turns onto a locked target, at roughly twice the cannon's range | one charge, a long lock, and you are standing still to use it |

The flamethrower is the only weapon that hits more than one ghost. The missile
is the only one that reaches past the cannon, which is what makes it the weapon
worth being up on a block for.

## Why the floating blocks matter most

The game has one verb today, so in co-op everyone does the same thing — and the
least confident driver simply dies more often.

A block is a **stationary, ranged, safer** job — jump up, lock on, fire down. It
is the right role for whoever is worst at driving: the youngest player, or the
friend who keeps hitting walls. Getting up there needs one button press, not
skill.

A guardian fought by three people with three jobs — one holding its attention,
one clearing the ghosts it summons, one on a block hitting the weak point — is a
far better game than three people doing the same job badly.

**The goal: a child who is bad at driving still has something she is
unmistakably good at.**

## The risk, stated plainly

Height is what deleted the last map. The two-deck design was scrapped because a
drop is a way to fall out of the world and the camera could not follow between
levels.

So floating blocks come with rules: **falling is harmless**, you get up by jump or jet
pack rather than by platforming, a block is a place to stand rather than a route
to traverse, and **nothing you need is ever up there** — a player who never goes
up must not fall behind one who does.

And they are built **last**. The camera test has still never run, even on flat
ground. If it fails, the floating blocks do not happen.

## Level-scoped weapons - decided

Level Two weapons are level-scoped. Returning to Level One restores its weapon
set, including the bomb, so a missile cannot flatten the first maze's balance.

Chassis ownership, upgrades and the Level Two unlock can persist; the available
weapon pads depend on the level. This supports friends at mixed progression
without removing the excitement of earning new equipment.

## A cheaper idea worth weighing first

Every ghost in the game runs **one identical behaviour**. The config names
`Chaser` and `GreedyOne`, and nothing reads it.

Giving ghosts real variety — different pursuit patterns, visibly different
tells — might be a better second act than a second maze, and it costs a fraction
as much.
