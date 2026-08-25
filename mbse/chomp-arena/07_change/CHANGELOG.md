# Chomp Arena — Change Log

## 2026-08-25 — Full tree, automation rule, and multi-agent workstreams
- **iPad is now the reference platform** (`CHOMP-STK-007` rewritten), not a
  port target. Touch controls promoted to their own CRITICAL requirement
  (`CHOMP-SYS-032`); pellet pooling stays in v1 because a tablet has less
  headroom than the laptop.
- **v1 trimmed** by moving the combo multiplier, the small-fry rule, the late
  join grant and Full Jaw gate passage to v2. v1 is 51 requirements.
- **Robust tests for high-risk requirements.** Test cases carry an
  `automation` field, and `validate.py` now fails if any CRITICAL or HIGH
  requirement lacks an AUTOMATED or HYBRID test without a recorded
  `automation_exempt_reason`. Added the exploit regression suite
  (`CHOMP-TC-042`), fairness telemetry assertions (`CHOMP-TC-043`) and the
  vehicle conformance scan (`CHOMP-TC-044`). 52 of 54 high/critical
  requirements are automated; the two exemptions are both human judgements
  about a seven-year-old.
- **Tree completed** to the sibling infrastructure tree's shape: need
  statement, stakeholders, system architecture, verification strategy, status
  dashboard.
- **Decomposition chains.** Every requirement carries a `chain`; ten chains,
  each with an append-only `workstreams/<chain>/log.yaml` whose stated
  requirement list is validated against the tree.
- **Vehicle workstream for Codex**: `03_architecture/vehicle_contract.md`,
  `workstreams/CHAIN-VEHICLE/BRIEF.md`, an `inbox/`, and `CHOMP-SYS-054` so
  models are accepted by scan rather than by eye.

## 2026-08-25 — Ghost count scales with player count
- `D-CHOMP-010` resolved: the server sets the ghost count from the current
  player count rather than offering a separate solo mode (`CHOMP-SYS-053`,
  v1). Alone, the maze becomes the opponent and the game is Pac-Man with
  upgrades and towers.
- `RISK-CHOMP-007` (a Friends-only 12-player PvP game usually has two players
  in it) closed.
- `CHOMP-SYS-041` narrowed to team play and an opt-out of PvP, since the
  empty-server case no longer needs a mode to solve it.

## 2026-08-25 — Multi-level maze
- Maps become vertically stacked decks with ramps and bridges rather than
  concentric rings on one plane (`D-CHOMP-011`). Rings ascend toward the
  centre, the Vault sits at the top of the central tower, and the progression
  is visible from the ground floor.
- Added `CHOMP-SYS-047` to `-052`: multi-deck maps, multi-deck ghost pathing,
  non-lethal falls, drop attacks classified as flanks, the camera contract,
  and off-deck player markers.
- Added `RISK-CHOMP-012` (the camera is the thing most likely to ruin this)
  and `RISK-CHOMP-013` (build cost per map).

## 2026-08-25 — Requirements tree established
- 60 requirements, 40 test cases, 13 risks, 11 decisions. `validate.py`
  passes with 0 errors, 0 warnings.
- Phasing set by `D-CHOMP-001`: the game first (v1, v2), the children's
  authoring kit second (v3).
- Lobby size fixed at 12 players, 3 garages per quadrant (`D-CHOMP-007`).
- `D-CHOMP-010` left open: whether a solo/co-op mode moves into v1, given
  that a Friends-only 12-player PvP game will usually have two players in it
  (`RISK-CHOMP-007`).

## 2026-08-25 — Concept established
- Combative multiplayer Pac-Man. Directional combat, three-currency economy
  with banking, scatter instead of transfer, ghosts as point thieves, super
  ghosts as gate guardians, per-match progression reset.
- Superseded an earlier kitty-coaster-tycoon concept, whose partial
  requirements draft is parked at
  `mbse/kitty-coaster-tycoon/02_requirements/requirements.yaml`.
