# Work Instruction — building and testing chassis models

**Chain:** `CHAIN-VEHICLE`
**Requirements:** `CHOMP-SYS-054` (models accepted by scan), `CHOMP-SYS-001`
**Contract:** `03_architecture/vehicle_contract.md` — binding, read it first
**Test case:** `CHOMP-TC-044`
**Log:** `workstreams/CHAIN-VEHICLE/log.yaml` — append-only

---

## 1. What changed, and why

Chassis models are now authored as **Luau spec tables**, not as `.rbxm` binaries
(`D-CHOMP-022`).

The first four models were delivered as `.rbxm`, which worked but has three
problems worth fixing before there are more of them:

- **A binary cannot be reviewed.** Nobody can see in a diff what changed.
- **A binary cannot be rebuilt.** A retune, or a change to the mouth convention,
  means re-emitting a file by hand.
- **An agent with no Roblox runtime cannot inspect what it just produced**, so
  it either guesses or blocks — and this chain has correctly blocked twice.

A spec table is text. It diffs, it reviews, it regenerates, and one command in
Studio turns it into a model you can look at.

---

## 2. Where things live

```
src/ServerStorage/ChompTools/
├── VehicleFactory.lua          builds a model from a spec. Do not edit
├── VehicleConformance.lua      the CHOMP-TC-044 scan. Do not edit
└── VehicleSpecs/
    ├── EXAMPLE_TEMPLATE.lua    a worked example — copy this
    ├── Standard.lua            ← your work
    ├── HeavyJaw.lua
    ├── Ravener.lua
    └── Apex.lua
```

The factory and the scan belong to the engine. **Your work is entirely inside
`VehicleSpecs/`.** If you believe the factory or the contract is wrong, log
`BLOCKED` and say so — do not edit across the boundary.

---

## 3. Writing a spec

Copy `EXAMPLE_TEMPLATE.lua`, rename it to the chassis id, change the shapes.

### Coordinates

The model is built at the origin facing **-Z**.

```
        -Z  FORWARD — the mouth goes here
         ↑
  -X ←   ●   → +X            +Y up, -Y down
         ↓
        +Z  BACK
```

**The mouth must sit at negative Z.** The factory refuses to build a model with
the mouth at Z ≥ 0 and says why. This is the single rule that matters most: a
backwards vehicle does not look wrong, it silently inverts the combat system,
because every impact classification reads `PrimaryPart.CFrame.LookVector`.

### What the spec must contain

- exactly one part named **`Chassis`** — the PrimaryPart, and the only part
  that collides
- **`MouthUpper`** and **`MouthLower`**, upper above lower, both forward
- exactly one part named **`TeamColour`**, recoloured at runtime
- `triangleCount`, declared — Luau cannot measure it

### What the spec must NOT contain

- **No `Tier`, `BarCapacity`, `Power`, `MouthArcDegrees`, `BaseSpeed` or
  `BaseTurn`.** The factory reads all of those from `ChompConfig`, so a model
  can never disagree with the numbers the game actually uses (`D-CHOMP-019`).
  This is why the turn-rate retune did not invalidate the delivered models.
- **No scripts.** Content carries no scripts, ever. The factory throws.
- Nothing over budget: 60 parts, 5000 triangles, 6 × 6 × 8 studs, 2 textures.

### What is yours to decide

Silhouette, style, decoration, eyes, teeth, how the four tiers escalate. The
contract constrains orientation, budgets and legibility. Everything else is a
design choice, and the tier escalation you inferred in the first four — longer,
taller, mouth further forward — was a good one that nobody asked for.

---

## 4. Testing it in Studio

This is the part the previous round could not do. Now it is three lines.

**1.** Sync (`rojo serve` running, Studio connected), then in the **Command Bar**:

```lua
local F = require(game.ServerStorage.ChompTools.VehicleFactory) F.buildAll()
```

✅ `[VehicleFactory] built Standard` for each spec. An error here means the
spec violates the contract, and the message says which rule.

**2.** Run the full scan:

```lua
local S = require(game.ServerStorage.ChompTools.VehicleConformance) S.report(S.checkAll())
```

✅ `CONFORMANCE: PASS`.

**3.** Look at it — the one check no machine can make:

```lua
local F = require(game.ServerStorage.ChompTools.VehicleFactory) F.preview("Apex")
```

It drops the model in front of the camera. Set the camera to roughly the game's
angle — 38° down — and ask: **from behind and above, at speed, can a
seven-year-old tell which way this thing is pointing?** The mouth must be at
least 30% of the silhouette and must read directionally in greyscale
(`RISK-CHOMP-001`). If it only reads because of colour, it fails.

---

## 5. Logging it

Append to `workstreams/CHAIN-VEHICLE/log.yaml`. **Never edit an existing
entry** — correct one by adding another.

```yaml
- date: '2026-08-26'
  agent: Codex (vehicle design)
  action: DELIVERED           # CLAIMED | DELIVERED | BLOCKED | NOTE
  requirements: [CHOMP-SYS-054]
  summary: >
    What you built, what you decided where the contract was silent, and what
    you could not verify.
  status: OPEN                # OPEN | DONE | BLOCKED
  handoff: >
    What the next agent needs to know.
```

Then run `python validate.py` from `mbse/chomp-arena/`. It checks your log
against the requirements tree — that every ID exists, and that it belongs to
this chain. **A failing validator is a failing delivery.**

### If you cannot run Studio

Say so and log `BLOCKED`, as you did twice before. Both times the blocker was a
real gap in the contract, and both times stopping was worth more than
delivering. State exactly which checks you could and could not perform. Do not
claim a conformance pass you did not see.

---

## 6. Definition of done

A chassis is done when all five hold:

1. `VehicleFactory.buildAll()` builds it without error
2. `VehicleConformance` reports `CONFORMANCE: PASS`
3. A human has looked at it at the game's camera angle and can read its facing
4. A `DELIVERED` entry is in the chain log
5. `python validate.py` passes

Only then does its requirement move off `NOT_STARTED`. A model existing is not
a requirement being verified.

---

## 7. Migrating the four existing models

The four delivered `.rbxm` files stay where they are and keep working until
replaced. Re-author them as specs one at a time, in this order — **Standard
first**, because the camera work needs a real vehicle to follow and it is the
one every new player sees.

For each: write the spec, build it, scan it, look at it, and only then delete
the `.rbxm`. Do not delete four binaries and then discover the factory disagrees
with your reading of the mouth convention.
