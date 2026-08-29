# Build Plan 1-6 and requirement tree

**Baseline:** `D-CHOMP-076`

**Purpose:** turn the six highest-impact improvements into independently
testable releases. Each build must pass its exit gate before the next begins.

## Product outcome

```text
1. READ THE BOSS
       |
2. READ THE GAME
       |
3. RISK A ROUND HAUL
       |
4. LEARN THE GHOSTS
       |
5. SEE THE VEHICLE GROW
       |
6. EARN A DIFFERENT LEVEL TWO
```

The dependency is intentional. More attacks are not useful until attacks can be
read; more progression is not desirable until purchases visibly change the
vehicle; height is not safe until the camera and ordinary arena are clear.

## Build 1 - Guardian and arena readability

**Player promise:** every guardian hit can be anticipated, avoided and
explained from what appeared on screen and what played in audio.

### Requirement branch

```text
BUILD-1
|- CHOMP-SYS-072  guardian silhouette, face, facing and weak point
|- CHOMP-SYS-073  1.5 s telegraphs and punish windows
`- CHOMP-SYS-074  chamber value hierarchy and restrained effects
```

### Delivery slices

1. Replace absolute-black guardian surfaces with charcoal forms, white/yellow
   tracking eyes, an emissive maw and a controlled rim light.
2. Add server phase attributes: `Stalk`, `PounceTell`, `Pounce`, `DashTell`,
   `Dash`, `HurlTell`, `Hurl`, `Vulnerable`, `Rage`.
3. Render a landing circle for Pounce, a lane marker for Dash, ghost pods for
   Hurl and one unambiguous weak-point state.
4. Revalue the chamber: medium-dark floor, pale cover, cyan safe navigation,
   red attack danger and gold rewards. Remove permanent fog and excessive bloom.

### Exit gate

- `CHOMP-TC-058` and `CHOMP-TC-059` pass.
- A seven-year-old can point to the face, weak point and safe escape route.
- No damaging move begins before its 1.5-second audiovisual tell completes.

## Build 2 - Reduced contextual HUD

**Player promise:** the arena is the largest thing on screen, and every visible
panel answers an immediate gameplay question.

### Requirement branch

```text
BUILD-2
|- CHOMP-SYS-075  permanent HUD occupies a controlled safe-area budget
|- CHOMP-SYS-076  boss, action and control states appear only when relevant
`- CHOMP-SYS-085  purchases preview a visible before/after transformation
```

### Delivery slices

1. Collapse Power, Bite and the three primary attributes into one compact strip.
2. Keep wave haul and safe dollars together, but distinguish risk using colour,
   icon, motion and words rather than colour alone.
3. Show guardian health and phase only inside the chamber.
4. Keep the belt immediately above Jump and Swap; brighten ready actions and
   give refused actions one short reason.
5. Show contextual centre prompts for tells, weak points, wave clear, spill,
   auto-bank and purchases; remove them when the context ends.

### Exit gate

- `CHOMP-TC-060` and `CHOMP-TC-068` pass at all target iPad landscapes.
- No required value overlaps Roblox chrome, a thumb control or another panel.
- At least 70% of the viewport remains unobstructed during ordinary driving.

## Build 3 - Wave haul, death spill and auto-bank

**Player promise:** every round is one wager: collect, survive and bank, or die
and visibly spill the complete haul.

### Requirement branch

```text
BUILD-3
|- CHOMP-SYS-077  PREP -> WAVE -> CLEAR -> BANK -> INTERMISSION state machine
|- CHOMP-SYS-078  full death spill and one survivor auto-bank
`- CHOMP-SYS-079  atomic transitions under death, leave and reconnect races
```

### Delivery slices

1. Treat one ghost wave as one scoring round. Five completed rounds unlock the
   Level 1 guardian attempt.
2. Start each round with zero wave haul; safe dollars and owned progression stay.
3. Death converts the full haul to neutral collectible scatter and returns the
   player with zero. The player continues; there is no spectator elimination.
4. At `CLEAR`, bank each surviving haul exactly once, then open the spend window.
5. Garages remain sanctuaries and shops, but do not bank an active-round haul.

### Exit gate

- `CHOMP-TC-061` and `CHOMP-TC-062` pass with two clients.
- No timing order can duplicate or preserve a dead player's haul.
- A solo player can complete five rounds, spend between them and reach the boss.

## Build 4 - Ghost personalities

**Player promise:** difficulty grows by asking different questions, not by
making the same ghost faster.

### Requirement branch

```text
BUILD-4
|- CHOMP-SYS-080  five server-owned behaviour strategies
|- CHOMP-SYS-081  distinct tells and authored wave composition
`- CHOMP-SYS-082  wall, reachability and living-count invariants
```

### Behaviour set

| Type | Decision it creates | Visual/audio tell |
|---|---|---|
| Chaser | route the direct pursuit | steady cyan eye and constant motor note |
| Greedy | protect the player with the largest haul | pulsing gold eye and coin rattle |
| Ambusher | change route before the next junction | magenta side fins and rising chirp |
| Bruiser | flank or use ordnance to clear a blocked lane | broad red armour band and heavy beat |
| Skittish | herd it toward a teammate or trap | flickering white eye and stuttering tone |

### Delivery slices

1. Keep path execution shared; inject only target and next-junction strategy.
2. Introduce one new type in isolation before mixing it into later rounds.
3. Announce a type only on its first appearance, then teach through behaviour.
4. Count only living, reachable ghosts; repair or despawn anything without a
   valid route instead of leaving an invisible wave blocker.

### Exit gate

- `CHOMP-TC-063`, `CHOMP-TC-064` and `CHOMP-TC-065` pass.
- A child identifies at least three types from behaviour without reading names.
- No ghost crosses a wall or keeps a cleared round alive while unreachable.

## Build 5 - Visible vehicle transformation

**Player promise:** spending money changes the toy, not only a number on the HUD.

### Requirement branch

```text
BUILD-5
|- CHOMP-SYS-083  deterministic appearance for every upgrade level
|- CHOMP-SYS-084  mounted geometry remains conformant and combat-readable
`- CHOMP-SYS-085  plinth and purchase feedback preview the transformation
```

### Visual ladder

| Track | Level I | Level II | Level III |
|---|---|---|---|
| Speed | intake fins | twin exhausts | animated thrust trail |
| Armour | side plates | jaw guards | reinforced shell band |
| Fire Power | compact cannon | twin cannon | three-cannon crown |
| Bombs | rear rack | armoured rack | high-yield warning core |
| Jump/Aero | small stabilisers | broad fins | active lift vanes |
| Boost | single jet | twin jets | bright vector nozzles |

Geometry is cosmetic evidence of server-owned state. It never carries tuning
values and cannot create damage or collision authority.

### Exit gate

- `CHOMP-TC-066`, `CHOMP-TC-067` and `CHOMP-TC-068` pass.
- Every purchase produces an obvious before/after difference at driving distance.
- Mouth direction, avatar visibility, turret travel and chassis bounds survive.

## Build 6 - Level Two

**Player promise:** defeating the guardian opens a visibly different place with
a different useful role, not merely the same maze with larger numbers.

### Requirement branch

```text
BUILD-6
|- CHOMP-SYS-086  participant unlock and group electric-grid passage
|- CHOMP-SYS-087  Level 2 swaps Bomb for wall-safe Homing Missile
|- CHOMP-SYS-088  optional floating firing blocks and harmless falls
|- CHOMP-SYS-089  Aero progression, SkyJaw and GridCrusher
`- CHOMP-SYS-090  distinct, crisp and greyscale-readable Level 2 palette
```

### Delivery slices

1. Guardian victory permanently credits participating players and disables the
   electric grid for the current server group.
2. A qualified player may escort friends through for that session; a guest gains
   permanent access only by participating in a guardian win.
3. Apply a level-scoped loadout. Level Two replaces the Bomb pad with Homing
   Missile; returning to Level One restores Bomb and removes Level Two weapons.
4. Build wide floating firing blocks reachable by Jump or Jet, with harmless
   falls, readable landing targets and no required progression on top.
5. Add Aero I-III, SkyJaw and GridCrusher with real trade-offs and visible forms.
6. Use graphite, cool white, teal, acid lime, coral, gold and violet with value
   contrast that remains readable in greyscale.

### Exit gate

- `CHOMP-TC-069` through `CHOMP-TC-073` pass.
- Bait, Sweeper and Gunner are all useful in a three-player session.
- A ground-only player can complete the level without falling behind.
- Missiles stop at walls and cannot be carried back to Level One.

## Trace summary

| Build | Requirements | Verification | Phase |
|---|---|---|---|
| 1 | 072-074 | TC-058, TC-059 | v1 |
| 2 | 075-076, 085 | TC-060, TC-068 | v1 |
| 3 | 077-079 | TC-061, TC-062 | v1 |
| 4 | 080-082 | TC-063 to TC-065 | v1 |
| 5 | 083-085 | TC-066 to TC-068 | v1 |
| 6 | 086-090 | TC-069 to TC-073 | v2 |

Build 2 and Build 5 share `CHOMP-SYS-085` deliberately: the plinth preview is a
HUD surface, while the transformation it previews is vehicle work. The UI may
ship its preview frame in Build 2; acceptance waits for Build 5 geometry.

## Change control

- A build may be divided into smaller commits, but its exit gate is indivisible.
- Failure evidence is recorded against the named test case; requirements are not
  marked verified because a neighbouring feature looked correct.
- Anything that changes authority, persisted state or economy requires a
  two-client Studio test and hostile-remote check.
- Build 6 cannot start until the target-iPad camera test passes on Level One.
