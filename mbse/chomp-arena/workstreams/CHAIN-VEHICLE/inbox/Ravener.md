# Ravener chassis

Tier-three pursuit chassis with a longer jaw, four visible front teeth and a
rear fin. The teeth make forward direction unmistakable in greyscale while the
fin creates a lower visual tail behind the driver.

## Unusual

- Built from 18 basic parts and 17 welds with no textures or scripted content.
- Four non-colliding wedge teeth sit at the front edge of the mouth.
- TriangleCount is declared as 228 from the authored primitive geometry.

## Decisions not covered by the contract

- The larger MouthArcDegrees value is communicated with a longer, wider jaw,
  while the actual combat arc remains server-owned.
- A single rear fin distinguishes the silhouette without competing with the
  mouth as the primary facing cue.

## Verification status

Binary structure, attributes, budgets and orientation geometry were inspected
statically. Awaiting the owner's in-Studio VehicleConformance scan.

