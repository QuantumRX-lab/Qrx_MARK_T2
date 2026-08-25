# Chomp Arena — Change Log

## 2026-08-25 — Structural faults now fail the build

`guard.py`, the static load-order guard (`D-CHOMP-028`). Builds the place and
refuses it on two things that are silent at runtime and expensive to find by
playing:

- two children of one parent sharing a name (`D-CHOMP-024`)
- a `WaitForChild` target that does not exist (`D-CHOMP-021`)

Verified in both directions rather than only on a clean tree: with the
`D-CHOMP-024` collision reintroduced it reports the duplicate name and all three
now-unreachable remotes, including the names reached through a `for ... in
ipairs(NAMES)` loop. Exit 0 on pass, 1 on failure.

Listed as an L0 scan in `verification_strategy.md`. No requirement or test case
was added — the guard checks that the artefact is internally consistent, which
is not a shall statement, and inventing a requirement to justify a tool would
put a false trace in the tree.

## 2026-08-25 — It drives

First session run from a local machine, which is the first time anyone could
press Play. Four faults stood between the written code and a drivable vehicle,
and none of them were findable by reading — the decisive evidence in every case
came from instrumenting the running game.

- `D-CHOMP-023` — Roblox's default control script was never disabled and was
  calling `humanoid:Move()` on the same Humanoid every frame. With no key held
  that call is `Vector3.zero`, which cancelled the forward drive. `AutoRotate`
  had been handled; `Move()` had not.
- `D-CHOMP-024` — `D-CHOMP-021` declared the RemoteEvents in a folder named
  `Remotes`, colliding with the `Remotes` ModuleScript that syncs into the same
  parent. `WaitForChild("Remotes")` returned the module, which has no children,
  so the network surface was unreachable on every client. Folder renamed to
  `RemoteEvents`.
- `D-CHOMP-025` — `VehicleController` wrote `root.CFrame` every `RenderStepped`
  and the physics solver reverted it, so measured yaw never accumulated past a
  few degrees and the vehicle drove permanently north into a wall. It now
  integrates a heading and hands it to `Move()`; the transform is the engine's.
- `D-CHOMP-026`, then `D-CHOMP-027` — the control scheme went through two
  shapes before settling. Hold-to-drive gated movement on steering, which means
  every path is an arc and driving straight is impossible; it was wrong from
  the design alone and should not have reached a playtest. Replaced with a
  single floating stick: forward drives, left and right steer, back reverses
  and the vehicle swings to face its travel direction.

Also: `Acceleration`, `Braking` and the new `ReverseSpeedFraction` now do work
instead of sitting unused; `BUILDING.md` gained a Gotchas section covering the
Rojo, PowerShell and Studio traps that cost time here; `control_scheme.md`
rewritten twice and now records why fixed-origin thumbsticks stay rejected while
a floating one does not.

No requirement moved off `NOT_STARTED`. `CHOMP-TC-040` has still never run, the
touch stick has never been played on a device, and two camera occlusion breaches
of exactly 0.20 s were observed in Studio on a trivial map.

## 2026-08-25 — Build starts: camera, driving, test map
- `default.project.json` — Rojo sync of `src/` into the DataModel.
- `TestMap.server.lua` — the throwaway two-deck test map, built procedurally
  from `ChompConfig.Map`: ground deck, corridor, tower core, ramp, raised deck,
  and a bridge crossing the corridor below.
- `CameraController.client.lua` — `camera_spec.md` implemented in full:
  world-locked yaw, critically damped deck easing, occluder fading, and its own
  measurement of the 0.2 s occlusion ceiling with `_G.ChompCameraReport()`.
- `MovementService.server.lua` — server-held speed and turn, always driving
  forward, WalkSpeed re-asserted every 0.25 s.
- `InputController.client.lua` — hold-to-turn with dead zone, multi-touch
  cancelling, double-tap flip, keyboard equivalents.
- `Remotes.lua` — the three remotes and their rate limiters.
- `BUILDING.md` — how to sync, run, and perform the `CHOMP-TC-040` camera
  acceptance run on the iPad.
- Contract correction: `SetInputDirection` was specified as rejecting a
  non-unit vector, which is wrong for a steering scalar. The contract now
  matches what the server validates.

## 2026-08-25 — Controls, camera and map geometry decided; v1 decomposition complete
- `D-CHOMP-015` **Hold to turn, always driving forward, no action buttons.**
  Steering gets the whole screen because turning is the entire skill of the
  game. A brake and swipe-to-turn were considered and rejected, with reasons.
- `D-CHOMP-016` **World-locked camera yaw at 35°.** The camera never rotates
  with the vehicle: a maze camera that follows every turn is nauseating on a
  tablet and destroys the learnability of junctions. The cost is that facing
  is read from the model, which is why the 30% mouth silhouette rule in the
  vehicle contract is load-bearing.
- `D-CHOMP-017` **8-stud grid, six prefab pieces, one two-deck v1 map.** Wall
  height is fixed at 7 studs — derived from the camera angle, not chosen. This
  closes the open question that had been sitting in the dashboard.
- New: `control_scheme.md`, `camera_spec.md`, `map_geometry.md`, and the
  `Controls`, `Camera` and `Map` sections of `ChompConfig`.
- **v1 decomposition is complete.** Building starts with the camera, on a
  two-deck test map, on the iPad.

## 2026-08-25 — Design decomposition: state, contracts, pure logic
- `src/ReplicatedStorage/Types.lua` — the shared vocabulary: `PlayerState`,
  `OwnView`, `PublicView`, `ImpactResult`, `Junction`, `WorldView`,
  `GhostBehaviour`. The `WorldView` a ghost behaviour receives is now actually
  defined rather than referenced in two documents and specified in neither.
- `03_architecture/player_state.md` — the single-writer ownership table
  (`D-CHOMP-014`), the client view split, lifecycle, and six invariants worth
  asserting in a debug build.
- `03_architecture/service_contracts.md` — per-service owns / exposes / must
  not touch, and the complete three-remote client surface with rate limits and
  rejection rules. No remote carries a quantity.
- `src/ReplicatedStorage/ChompLogic/Impact.lua` and `Progression.lua` — typed
  pure-function stubs with their boundary cases specified, so the unit specs
  for `CHOMP-TC-016`, `-017` and the progression maths can be written before
  the implementations exist.
- `D-CHOMP-013`: other players' carried totals are shown as a band
  (Light/Heavy/Fat), not a number.

## 2026-08-25 — CHAIN-VEHICLE blocker resolved; source moves into the repo
- CHAIN-VEHICLE claimed its requirements and correctly logged `BLOCKED` rather
  than guessing: the vehicle contract asked for attributes mirroring a
  ChompConfig that existed nowhere readable, and for conformance against a test
  case that was written but not runnable. Both gaps were real.
- `D-CHOMP-012`: authored Luau now lives in the repo under `src/`, in a
  DataModel-shaped tree, synced into Studio. A `.rbxl` cannot be diffed or
  shared between agents, so the place file becomes a build output rather than
  the source of truth.
- Added `src/ReplicatedStorage/ChompConfig.lua` — every tunable number defined
  once, including the four-chassis table. Chassis are shaped as trades, not
  straight upgrades: bigger tiers are faster but turn worse.
- Added `src/ServerStorage/ChompTools/VehicleConformance.lua` — the executable
  form of `CHOMP-TC-044`, with two limits reported rather than hidden
  (triangle count is declared not measured; silhouette is a bounding-box
  approximation).
- Vehicle contract updated with the real numbers and with how to run the scan
  before delivering.

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
