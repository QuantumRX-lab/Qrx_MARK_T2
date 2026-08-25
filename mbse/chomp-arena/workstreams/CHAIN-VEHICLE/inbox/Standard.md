# Standard chassis

Starter chassis with the lightest silhouette in the family: yellow body shell,
large split wedge jaw, contrasting mouth interior, transparent canopy, eyes,
team-colour brow band and two non-functional skids. The mouth projects along
the Chassis LookVector and remains the dominant directional feature under the
world-locked camera.

## Unusual

- Built entirely from basic Part and WedgePart instances: 11 parts, 10 welds,
  no textures, scripts, unions, seats or motion constraints.
- Chassis is the only colliding part and is transparent; visible parts are
  massless and non-colliding.
- TriangleCount is declared as 132 based on the authored primitive geometry.

## Decisions not covered by the contract

- A visible canopy communicates that this is a driven costume while preserving
  the character-controller implementation.
- Skids suggest locomotion without implying physics wheels.
- The team-recoloured area is a single brow band, keeping body colours stable.

## Verification status

Binary structure and contract fields were inspected statically. Awaiting the
owner's in-Studio VehicleConformance scan; this note is not an acceptance claim.

