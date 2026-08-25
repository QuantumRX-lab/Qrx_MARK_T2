# Vehicle Contract

**This is the interface a chassis model must satisfy to be drivable by the
engine.** It is written to be handed to an external agent (currently Codex, see
`workstreams/CHAIN-VEHICLE/`) and to be checked automatically rather than by
eye — see `CHOMP-SYS-054` and `CHOMP-TC-044`.

Anything not specified here is a free choice. Shape, style, decoration and
colour are deliberately unconstrained.

## 1. Identity and placement

| | |
|---|---|
| Location | `ReplicatedStorage/Vehicles/<ChassisId>` |
| `ChassisId` | `Standard`, `HeavyJaw`, `Ravener`, `Apex` |
| Tag | `Chomp_Vehicle` on the Model |
| Scripts | **None.** Not one, anywhere inside the model |

## 2. Required attributes on the Model

| Attribute | Type | Standard | HeavyJaw | Ravener | Apex |
|---|---|---|---|---|---|
| `Tier` | number | 1 | 2 | 3 | 4 |
| `BarCapacity` | number | 100 | 175 | 275 | 400 |
| `Power` | number | 100 | 250 | 450 | 700 |
| `MouthArcDegrees` | number | 90 | 90 | 100 | 110 |
| `TriangleCount` | number | your measured triangle count, at most 5000 |

Numbers are owned by `src/ReplicatedStorage/ChompConfig.lua`; the attributes
exist so the conformance scan can catch a model that disagrees with the config.
**Read the values from that file, not from this table** — if the two ever
diverge, the config is right and this table is stale.

`TriangleCount` has to be declared because Luau cannot measure it.

**Amended 2026-08-25 (`D-CHOMP-019`):** `BaseSpeed` and `BaseTurn` were
originally required here too. They have been removed. They are tuning values
that change every playtest — the first retune moved turn rates by more than
half — and a model carrying a stale copy would fail conformance for a reason
that says nothing about the model. **A chassis model carries identity and
shape; `ChompConfig` carries tuning.**

## 3. Geometry and orientation

- **`PrimaryPart` must be set**, and must be named `Chassis`.
- **The mouth faces `PrimaryPart.CFrame.LookVector`.** This is the single most
  important line in this document. Combat classification, pellet pickup arc and
  drop-attack resolution all read that vector. A model built facing the wrong
  way is not a cosmetic error — it inverts the game.
- The model's pivot sits at the **centre of the ground contact patch**, not at
  the visual centre.
- Two parts named `MouthUpper` and `MouthLower` form the jaw. The client rotates
  them about their own pivots to animate the chomp; they must be positioned so
  that rotating them opens a wedge along the LookVector.

## 4. Budgets

These come from the iPad being the reference platform (`CHOMP-STK-007`), with
twelve vehicles potentially on screen at once.

| | Limit |
|---|---|
| Bounding box | ≤ 6 × 6 × 8 studs (corridors are 8 wide) |
| Parts per model | ≤ 60 |
| Triangles per model | ≤ 5000 total |
| Unions | Avoid. MeshParts or basic parts preferred |
| Textures | ≤ 2, ≤ 512×512 |

## 5. Physics properties

- Every part except `Chassis` is `Massless = true` and `CanCollide = false`.
- Every part is welded to `Chassis`; nothing is anchored, nothing free-floating.
- No constraints, no motors, no `VehicleSeat`, no wheels. Locomotion is the
  character controller (`D-CHOMP-002`) — the model is a costume on a character,
  not a vehicle in the physics sense.

## 6. Readability

The mouth must be legible at the game's locked camera angle from standard
follow distance, because a player who cannot tell which way an opponent is
facing cannot play the combat system at all (`RISK-CHOMP-001`).

- The mouth opening must occupy **≥ 30% of the silhouette** when viewed from
  the camera angle.
- The mouth must be a contrasting colour to the body, and must not rely on
  colour alone — the silhouette must read facing at a glance in greyscale.
- One part named `TeamColour` (any size, anywhere) is recoloured at runtime to
  the player's colour. Do not use the player's colour anywhere else.

## 7. Delivery

Deliver straight into the synced source tree:

- `src/ReplicatedStorage/Vehicles/<ChassisId>.rbxm` — the exported model
- `workstreams/CHAIN-VEHICLE/inbox/<ChassisId>.md` — a short note: what it is,
  anything unusual, and **anything the contract did not cover that had to be
  decided**. That last part is the valuable one

**Amended 2026-08-25:** this contract originally said to deliver the `.rbxm`
into `inbox/` as well. `src/` did not exist when it was written; now that Rojo
syncs the source tree (`D-CHOMP-012`), a model in `Vehicles/` is testable by
pressing play, and a second copy in `inbox/` would only be a copy that can
drift. The note still goes to `inbox/`.

**Check it yourself before delivering.** The conformance scan is
`src/ServerStorage/ChompTools/VehicleConformance.lua`. Put the model in
`ReplicatedStorage.Vehicles`, then from the Studio command bar:

```lua
local Scan = require(game.ServerStorage.ChompTools.VehicleConformance)
Scan.report(Scan.checkAll())
```

It prints every failure with its reason, then `CONFORMANCE: PASS` or `FAIL`.
Two of its checks are honest approximations and say so in their own output:
triangle count is the number you declared rather than one it measured, and the
silhouette fraction is computed from bounding boxes — it catches an obviously
too-small mouth but does not replace looking at the vehicle on an iPad.

Then append an entry to `workstreams/CHAIN-VEHICLE/log.yaml` recording the
delivery, and the receiving agent re-runs the scan before accepting.

## 8. What the contract deliberately does not constrain

Silhouette style, decoration, eyes, teeth, trails, how the four tiers differ
visually. The only hard visual rule is that facing must be readable. Tier
progression *should* look like escalation, but how is the designer's call.
