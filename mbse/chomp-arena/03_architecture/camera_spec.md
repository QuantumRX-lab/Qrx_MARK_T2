# Camera Specification

`CHOMP-SYS-051`, `RISK-CHOMP-012`. **The highest-risk item in the project and
the first thing to build.** Everything else — wall heights, vehicle silhouettes,
map scale — is designed against what this camera can actually see, so it comes
first and on a throwaway test map.

## The shape of it

| | |
|---|---|
| Yaw | **World-locked. The camera never rotates with the vehicle** |
| Pitch | 35° down |
| Distance | 42 studs along the camera axis |
| Field of view | 55° |
| Target | The vehicle, plus 6 studs of look-ahead along its facing |
| Screen position | Vehicle sits at 0.55 of screen height — slightly low, so there is more room ahead than behind |

## Why world-locked yaw

This is the decision the whole spec turns on, and it goes against the instinct
to put the camera behind the vehicle.

In a maze you turn constantly. A camera that rotates to follow every turn
swings the entire world several times a second — it is nauseating on a tablet
held close to the face, and it destroys maze legibility, because the junction
you memorised is now facing a different way each time you approach it. Locked
yaw keeps the maze a stable, learnable place: north is always up. Classic
isometric arcade games do this for the same reason.

The cost is that **your facing is read from the model, not from the camera** —
which is precisely why the vehicle contract demands a mouth occupying 30% of
the silhouette that reads directionally in greyscale. The camera decision and
the vehicle readability rule are the same decision seen twice.

At 35°, corridors stay visible several cells ahead, walls read as walls rather
than as a flat plan, and vertical separation between decks is obvious.

## Deck transitions

Camera height is `deckIndex * DeckHeight` plus the base offset, eased with a
critically damped spring over 0.35 s.

Critically damped, not linear and not bouncy: a linear ease reads as a lurch at
both ends, and any overshoot on a tablet feels like the floor moved. The camera
should arrive at the new height and stop, once.

**No jump cuts, ever** — including when a player falls a deck. A fall is
already disorienting; a cut on top of it means the player has no idea where
they landed.

## Occlusion — the actual hard part

Every frame, raycast from the camera to the vehicle.

- Anything hit that is tagged `Chomp_Wall`, `Chomp_Decor` or is a bridge
  fades: `LocalTransparencyModifier` ramped to **0.75 over 0.12 s**, restored
  over 0.25 s once clear.
- **Never fade the player's own vehicle.** Never fade another player, a ghost,
  a guardian, a pellet or a gate — if it matters to a decision, it stays solid.
- Fade in fast, restore slow. Fast in because the requirement is a 0.2 s ceiling
  on full occlusion and 0.12 s leaves margin; slow out because rapid
  re-solidification behind a moving player flickers.

Fading is client-side and cosmetic only. It changes nothing the server knows.

### Wall height is a camera constraint

At 35° pitch, a wall one cell in front of the vehicle occludes it once the wall
is taller than roughly the vehicle height plus the cell size times `tan(35°)`.
With 8-stud cells and vehicles up to 6 studs tall, that lands at **7 studs**,
which is now fixed in `ChompConfig.Map.WallHeight`.

This closes an open question that has been sitting in the dashboard: wall
height was never an art choice. If a taller wall is ever wanted for a set
piece, it has to be tagged `Chomp_Decor` and placed where it cannot sit between
the camera and a corridor.

## Feedback

A hit shakes the camera by 0.6 studs over 0.15 s. That is small on purpose —
enough to register a hit you might have missed, not enough to cost you the
corner you are taking. There is a setting to disable it entirely.

## Verification — `CHOMP-TC-040`

Build this on a **two-deck test map** with four snapped walls, a ramp and a
bridge, before any real map exists.

1. Drive a full circuit of both decks, under the bridge and around a tower
   core, logging every occlusion event and its duration. **No full occlusion
   over 0.2 s.**
2. Ride the ramp both ways: no jump cut, no overshoot.
3. Fall off the bridge: the camera follows down, no cut.
4. Do all of it **on the iPad**, not in Studio. Studio's window is not the
   device, and the device is the reference platform.
5. Hand it to the seven-year-old and watch whether she loses her own vehicle.
   She is the acceptance test.

If the camera cannot pass this on a trivial map, the multi-level design is in
trouble and it is far cheaper to find that out now than after six maps exist.
That is the entire reason this is built first.
