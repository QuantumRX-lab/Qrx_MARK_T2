# Brief — Vehicle Design (Codex)

**You own the chassis models.** Four of them. Everything the engine needs from
them is written down in `../../03_architecture/vehicle_contract.md`, and
acceptance is an automated scan (`CHOMP-TC-044`), not an opinion.

## What the game is, in one paragraph

Players drive a Pac-Man-shaped vehicle through a multi-level maze, eating
pellets. **Facing decides combat**: your mouth is your weapon, your flanks and
back are your weak spots. Mouth-to-mouth is a contest both players pay for; a
bite into someone's flank costs the biter charge and the victim points.
Upgrades tune speed, agility and mouth width. Four chassis tiers escalate from
a starter to an apex predator.

## Your requirements

| | |
|---|---|
| `CHOMP-SYS-001` | The vehicle is a character controller in a costume, not a physics vehicle |
| `CHOMP-SYS-002` | Movement stats are server-held |
| `CHOMP-SYS-003` | Walls hold at full speed |
| `CHOMP-SYS-051` | The camera keeps the player visible through a building of towers and bridges |
| `CHOMP-SYS-054` | Models are accepted by conformance scan |

Read them in `../../02_requirements/requirements.yaml`.

## The one thing that matters most

**The mouth faces `PrimaryPart.CFrame.LookVector`.**

Every combat classification, the pellet pickup arc, and drop-attack resolution
all read that vector. A model built facing the other way does not look wrong —
it silently inverts the combat system. This is the first thing the conformance
scan checks and the first thing to get right.

## The second thing that matters most

**Facing must be readable at a glance, in motion, on an iPad, at the game's
locked camera angle.** The mouth opening must be at least 30% of the
silhouette, and the shape must read as directional in greyscale — colour alone
is not enough. A player who cannot tell which way an opponent is pointing
cannot play this game at all (`RISK-CHOMP-001`).

## What you are free to decide

Style, decoration, eyes, teeth, trails, how the four tiers differ visually,
whether they escalate as machinery or as creatures. The contract constrains
budgets, orientation and legibility. Everything else is yours.

Note that the daughter is the art director on names and colours. If a tier
wants a name, propose one rather than fixing it — and expect it to be
overruled by a seven-year-old.

## Budgets, because the iPad is the reference platform

≤ 60 parts, ≤ 5000 triangles, ≤ 6×6×8 studs, ≤ 2 textures at 512×512, no
unions, no scripts. Twelve of these can be on screen at once on a tablet.

## Delivery

1. Export each model to `inbox/<ChassisId>.rbxm`.
2. Add `inbox/<ChassisId>.md` — what it is, anything unusual, and **anything
   the contract did not cover that you had to decide**. That last part is the
   valuable one.
3. Append an entry to `log.yaml` with `action: DELIVERED` and the requirement
   IDs.
4. Wait for `action: ACCEPTED` or `REJECTED` from the receiving agent, who runs
   the conformance scan first.

If the contract is wrong, ambiguous, or fights the design — say so in the log
with `action: BLOCKED` rather than guessing. A wrong assumption discovered at
acceptance costs a rebuild; the same question asked in the log costs a day.
