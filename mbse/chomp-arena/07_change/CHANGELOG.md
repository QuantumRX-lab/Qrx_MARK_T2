# Chomp Arena — Change Log

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
