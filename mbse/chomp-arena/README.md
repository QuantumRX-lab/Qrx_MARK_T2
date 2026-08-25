# Chomp Arena — MBSE Tree

Model-based systems engineering tree for a **combative multiplayer Pac-Man**
game built in Roblox: players drive a Pac-Man-shaped vehicle through a
multi-level maze, eat pellets for points, bank them, buy upgrades, and fight
each other by direction — mouth is the weapon, flank and back are the weak
spots. Ghosts rob you. Super ghosts guard the ramps to the richer decks above.

Same methodology as `mbse/infrastructure/` (INCOSE-style requirement IDs,
verification by test case, decision log, risk register, a validator that
recomputes every rollup), scoped to a game rather than to hosting.

## Read in this order

| | |
|---|---|
| `00_need/game_concept.md` | **Start here.** The design: loop, combat maths, ghosts, gates, the multi-level maze, match structure. Written to be read by a person, not parsed |
| `02_requirements/requirements.yaml` | 60 requirements — 8 stakeholder, 52 system — phased v1/v2/v3 |
| `03_architecture/authoring_kit.md` | v3: how the children build their own maps without scripting |
| `04_verification/test_cases.yaml` | 40 test cases. The source of truth for the trace |
| `05_risks/risk_register.yaml` | 13 open risks, including the honest ones about scope and about the children having no job until v3 |
| `06_decisions/decision_log.yaml` | 11 decisions with rationale, including one still open |

## Phases

Phases are the owner's decision (`D-CHOMP-001`) to build a good game first and
the children's authoring kit second.

- **v1 — the game.** Playable and fun as a hard-coded experience. One
  two-deck map, two ghosts, one gated ring. 53 requirements.
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

Three of its checks are specific to this tree:

- **`allocated_to` is a DataModel path, not a file path.** The artefact is a
  `.rbxl` place file on a laptop, not files in this repo, so allocations are
  checked against the real Roblox service list instead of the filesystem.
- **Phase ordering.** A requirement may not derive from a parent that ships
  later, and must be verified by at least one test case scheduled no later
  than itself. A v1 requirement whose only test arrives in v3 is not
  verified during v1 — it is merely claimed.
- **Method agreement.** A requirement's `verification_method` must actually be
  the method of one of the test cases that verify it.

`verified_by` lists in `requirements.yaml` are **generated** from the
`verifies` lists in `test_cases.yaml`, so the trace cannot become
one-directional by hand-editing. Edit the test case, then regenerate.

## What this tree cannot tell you

Almost every interesting number in it — bite cost, ring Threats, ghost steal
rate, round length, upgrade prices — is only verifiable in play, with real
players, most of them children (`RISK-CHOMP-011`). The tree can show that the
mechanics work. `CHOMP-TC-001` and `CHOMP-TC-002` are the only two things in
it that speak to whether the game is any good.
