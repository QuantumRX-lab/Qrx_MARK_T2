# Verification Strategy

The owner's rule: **every high-risk requirement gets a robust test that runs
during development, not a promise to check it later.**

Mechanically that is enforced by `validate.py`, which fails if any requirement
of `CRITICAL` or `HIGH` priority lacks a test case marked `AUTOMATED` or
`HYBRID` — unless the requirement carries an explicit
`automation_exempt_reason` saying why a machine cannot judge it.

Only two requirements hold such an exemption, and both are honest ones: whether
a seven-year-old understands the game without being told, and whether she can
read the HUD at speed. Nothing else gets to be unautomated.

## The five levels

**L0 — Static conformance scans.** Scripts that read the place and assert
structure. No gameplay involved. Cheap, fast, run on every save:

- no script instances anywhere in content folders
- no balance literals in engine logic; every number resolves to `ChompConfig`
- no hardcoded instance paths into `Workspace`
- vehicle models satisfy the vehicle contract
- map geometry: rings ascend, garages symmetric, walls on-grid, no pellets
  inside walls, no voids or death planes

**L1 — Unit specs on pure logic.** The maths of this game is separable from
Roblox and must be kept that way: impact classification from two facing vectors,
head-on and bite resolution, scatter amounts, Power computation, combo state,
ghost direction choice at a junction. Each is a pure function over plain tables
and each gets a spec with its boundary cases — notably the 44°/46° head-on
boundary, bar-difference overflow, and the small-fry threshold.

Keeping these pure is a design constraint, not a testing convenience: logic
that reaches into the DataModel cannot be tested without a running game, and
logic that cannot be tested cheaply does not get tested.

**L2 — Integration harness with scripted players.** Bot clients driven by a
script, playing a real server: bank, buy, collide at specified angles, take
ghost hits, crack gates, fall off bridges, join and leave to move the ghost
count. This is where the exploit regression suite (`CHOMP-TC-042`) lives, and
it is what runs before every publish.

**L3 — Device and performance.** On the iPad first, because the iPad is the
reference platform: frame rate in a full lobby, part counts, pellet instance
stability, thumb occlusion, HUD legibility in both orientations, camera
occlusion across every deck.

**L4 — Acceptance with actual children.** The only level that can say whether
the game is any good: `CHOMP-TC-001` (understood without explanation) and
`CHOMP-TC-002` (a child and an adult share a lobby fairly). Backed, not
replaced, by the fairness telemetry assertions in `CHOMP-TC-043` — automated
checks that every player banked every round, that no player absorbed more than
30% of a round's hits, and that the leader is not winning primarily by combat.

## The publish gate

L0, L1 and L2 run before every publish. A failure blocks the publish. No
exceptions for "it's only the family" — the whole point of an automated gate is
that it does not negotiate.

L3 runs before any session where the daughter will play. L4 runs whenever there
is a child in the room, and its findings go into `ChompConfig` as number changes
rather than into a backlog.

## What "robust" means for the highest-risk items

| Risk | Robust test |
|---|---|
| `RISK-CHOMP-001` combat unreadable | L4 with a child, plus L0 asserting mouth ≥30% of silhouette |
| `RISK-CHOMP-002` hits feel unfair on bad connection | L2 with simulated latency, asserting predicted and authoritative outcomes agree above a threshold |
| `RISK-CHOMP-003` fast player snowballs | L2 telemetry assertions (`CHOMP-TC-043`), every playtest |
| `RISK-CHOMP-012` camera ruins it | L3 occlusion log across every deck, on the iPad, before any real map is built |
| Client forgery | L2 exploit regression suite (`CHOMP-TC-042`), extended whenever a remote is added |
