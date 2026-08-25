# Chomp Arena — MBSE Tree

Model-based systems engineering tree for a **combative multiplayer Pac-Man**
game built in Roblox: players drive a Pac-Man-shaped vehicle through a
multi-level maze, eat pellets for points, bank them, buy upgrades, and fight
each other by direction — mouth is the weapon, flank and back are the weak
spots. Ghosts rob you. Super ghosts guard the ramps to the richer decks above.

Same methodology as `mbse/infrastructure/` (INCOSE-style requirement IDs,
verification by test case, decision log, risk register, a validator that
recomputes every rollup), scoped to a game rather than to hosting.

**Taking this over?** Read `HANDOVER.md` first.

**Building it:** see `BUILDING.md` — Rojo sync, press play, and the camera
acceptance run.

## Read in this order

| | |
|---|---|
| `00_need/need_statement.md` | Why this exists, what success looks like, what is out of scope |
| `00_need/game_concept.md` | **Start here.** The design: loop, combat maths, ghosts, gates, the multi-level maze, match structure. Written to be read by a person, not parsed |
| `01_stakeholders/stakeholders.md` | Who depends on this and what breaks it for them, including the tensions between them |
| `02_requirements/requirements.yaml` | 62 requirements — 8 stakeholder, 54 system — phased v1/v2/v3, each on a decomposition chain |
| `03_architecture/system_architecture.md` | Where everything lives in the DataModel, the client/server rule, the whole remote surface |
| `03_architecture/player_state.md` | The player record, which service may write each field, and the invariants |
| `03_architecture/service_contracts.md` | What each service owns, exposes and must not touch. The complete three-remote client surface |
| `03_architecture/control_scheme.md` | Hold to turn, always forward, no buttons. What was rejected and why |
| `03_architecture/camera_spec.md` | **Build this first.** World-locked yaw, 35°, occluder fading, and why wall height is a camera constraint |
| `03_architecture/map_geometry.md` | The 8-stud grid, the six prefab pieces, and the v1 two-deck map |
| `03_architecture/vehicle_contract.md` | The interface a chassis model must satisfy. Handed to an external agent, checked by scan |
| `03_architecture/authoring_kit.md` | v3: how the children build their own maps without scripting |
| `04_verification/verification_strategy.md` | The five test levels and the publish gate |
| `04_verification/test_cases.yaml` | 44 test cases, 41 automated or hybrid. The source of truth for the trace |
| `05_risks/risk_register.yaml` | 12 open risks, including the honest ones about scope and about the children having no job until v3 |
| `06_decisions/decision_log.yaml` | 11 decisions with rationale |
| `08_status/dashboard.yaml` | Hand-maintained rollup, checked against the records on every validate run |
| `workstreams/` | One folder and one append-only log per decomposition chain. How several agents work this tree without colliding |
| `src/` | Authored Luau, DataModel-shaped, synced into Studio (`D-CHOMP-012`). `ChompConfig` is the authoritative numbers; `ChompLogic/` holds the pure functions; `ChompTools/` holds the conformance scan |

## Phases

Phases are the owner's decision (`D-CHOMP-001`) to build a good game first and
the children's authoring kit second.

- **v1 — the game.** Playable and fun as a hard-coded experience. One
  two-deck map, two ghosts, one gated ring. 51 requirements.
- **v2 — content and modes.** The remaining maps, ghosts and rings; team and
  solo modes; cosmetic persistence.
- **v3 — the authoring kit.** Tags, attributes, the mirror tool, Check My
  Maze. The children build their own content.

Two v1 requirements exist purely as the down payment on v3 — `CHOMP-SYS-037`
(every tunable number in one config table) and `CHOMP-SYS-038` (the engine
finds content by tag, never by hardcoded path). Both cost almost nothing now
and are expensive to retrofit later.

## Keeping it honest

```
python validate.py
```

Requires PyYAML. Run it after any manual edit. It recomputes every count and
cross-reference from the atomic records rather than trusting a handwritten
total — the same principle, and the same reason, as
`mbse/infrastructure/validate.py` (`D-INFRA-009`).

Its checks specific to this tree:

- **`allocated_to` is a DataModel path, not a file path.** The artefact is a
  `.rbxl` place file on a laptop, not files in this repo, so allocations are
  checked against the real Roblox service list instead of the filesystem.
- **Phase ordering.** A requirement may not derive from a parent that ships
  later, and must be verified by at least one test case scheduled no later
  than itself. A v1 requirement whose only test arrives in v3 is not
  verified during v1 — it is merely claimed.
- **Method agreement.** A requirement's `verification_method` must actually be
  the method of one of the test cases that verify it.
- **Automation coverage.** Every `CRITICAL` or `HIGH` requirement must be
  covered by an `AUTOMATED` or `HYBRID` test case, or carry an explicit
  `automation_exempt_reason`. Two requirements hold an exemption and both are
  honest ones — whether a seven-year-old understands the game unprompted, and
  whether she can read the HUD at speed. Nothing else gets to be unautomated.
- **Chains and their logs.** Every requirement names a decomposition chain,
  every chain has an append-only log in `workstreams/`, and each log's stated
  requirement list is checked against the tree — including that an entry never
  cites a requirement belonging to somebody else's chain.
- **Dashboard rollups.** Every count in `08_status/dashboard.yaml` is
  recomputed from the records.

The validator is negative-tested: seeding a wrong rollup, a wrong chain count,
a cross-chain citation and a downgraded test automation flag produces seven
distinct failures.

`verified_by` lists in `requirements.yaml` are **generated** from the
`verifies` lists in `test_cases.yaml`, so the trace cannot become
one-directional by hand-editing. Edit the test case, then regenerate.

## What this tree cannot tell you

Almost every interesting number in it — bite cost, ring Threats, ghost steal
rate, round length, upgrade prices — is only verifiable in play, with real
players, most of them children (`RISK-CHOMP-011`). The tree can show that the
mechanics work. `CHOMP-TC-001` and `CHOMP-TC-002` are the only two things in
it that speak to whether the game is any good.
