# Map Geometry

Everything is on an **8-stud grid**. That single fact is what makes ghost
pathing cheap, symmetry automatic, and prefab building possible for a child.

## The numbers

| | Studs | Notes |
|---|---|---|
| Cell | 8 | Corridor width. Vehicles are at most 6 wide |
| Wall height | 7 | **A camera constraint, not an art choice** — see `camera_spec.md` |
| Wall thickness | 1 | Sits on the cell boundary |
| Deck height | 16 | Floor to floor |
| Slab | 2 | So 14 studs of clear headroom per deck |
| Ramp | 4 cells (32) | For a 16-stud rise: about 26.6°, comfortable at full speed |
| Bridge | 1 cell wide | No railings. Falling is a mechanic (`CHOMP-SYS-049`) |
| Garage | 3 × 3 cells | One entrance, on the outer deck |

## The prefab set

Six pieces. That is the entire kit a map is built from, and it is what
guarantees walls land on the grid.

| Piece | Size (studs) |
|---|---|
| `Wall_Straight` | 8 × 7 × 1 |
| `Wall_Corner` | L, 8 × 7 × 1 both arms |
| `Wall_Cap` | 1 × 7 × 1 end stub |
| `Floor_Slab` | 8 × 2 × 8 |
| `Ramp_Section` | 8 × 2 × 8, rising 4 studs |
| `Bridge_Span` | 8 × 2 × 8, no sides |

Build with Studio's move and rotate snap set to 8. That is the whole "prefab
system" — a snap increment and six models, not a tool anyone has to write.

## The v1 map

One map, two decks. Four-fold rotationally symmetric about the vertical axis.

```
        ┌─────────────────────────────────┐
        │  Ring 1 — ground deck, 32 × 32  │
        │   garages ×12, 3 per quadrant   │
        │     ┌───────────────────┐       │
        │     │  Ring 2 — deck 2  │       │
        │     │      16 × 16      │       │
        │     │   raised 16 studs │       │
        │     └───────────────────┘       │
        │   4 ramps, one per quadrant,    │
        │   each with a gate at its base  │
        └─────────────────────────────────┘
```

- **Ring 1**: the outer band of the ground deck. 12 garages around the edge,
  three per quadrant. Pellet value 10.
- **Ring 2**: the central 16 × 16, raised one deck. Pellet value 25. Reached by
  four ramps at symmetric positions, each guarded by a super ghost with Threat
  250.
- **Bridges** cross over Ring 1 corridors at deck-2 height, giving the drop
  attacks and the scouting views that justified building upward.

Rings 3 and 4 are v2. The engine handles N decks from the start; v1 simply
ships two.

## The authoring rule

**Build one quadrant. 16 × 16 cells. Mirror it.**

Rotate the authored quadrant 90°, 180° and 270° about the map centre. Four-fold
symmetry — and therefore fair spawns — becomes a property of the build method
rather than something an adult has to check. It also cuts the building work to
a quarter, which matters enormously when the builder is seven.

In v1 the mirror is done by hand (select, duplicate, rotate 90 about the
centre, repeat). `CHOMP-SYS-044` automates it in v3; the workflow is identical
either way, which is the point.

## Pellets

One pellet per open cell centre, value by ring from `ChompConfig`. Power
pellets at the four symmetric positions on Ring 2, respawning every 45 s.

A 32 × 32 ground deck with roughly 60% open cells gives on the order of 600
pellets — well inside the part budget once they are pooled
(`CHOMP-SYS-033`), and enough that twelve players do not strip a ring bare
between respawns (`CHOMP-TC-029`).

## The deck graph

`MapService` builds the graph at load:

- Each deck contributes a grid of junctions at cell centres where two or more
  corridors meet.
- Every `Ramp_Section` run and `Bridge_Span` run contributes an **explicit
  vertical or crossing edge** between the junctions at its ends.

Ghosts choose a direction at each junction from that junction's real exits, so
vertical movement needs no special case — "Up" is just another exit
(`CHOMP-SYS-048`).

This only stays cheap because the links are authored data. A map built with
free-form or off-grid walls produces ghosts that stick at ramp mouths, and the
failure only appears once ghosts exist — potentially after a lot of building
(`RISK-CHOMP-008`). Build from the six pieces, with snap on, from the first
wall.

## Checks — `CHOMP-TC-024`, `CHOMP-TC-037`

1. Rotate the finished map 90° in the viewport; it must be identical.
2. Pellet value rises strictly inward per ring.
3. All 12 garages on Ring 1, three per quadrant.
4. Four gates on Ring 2, one per quadrant.
5. Every wall on the 8-stud grid.
6. No pellet inside a wall.
7. No void, no death plane, nothing you can fall off and not land on.
8. A higher ring is visible from every garage — the whole argument for
   building upward is that a player can see what they are working toward.
