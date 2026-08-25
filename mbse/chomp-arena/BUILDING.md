# Building and running it

## One-time setup

1. Install **Roblox Studio** and **Rojo** (`rojo.space`) — Rojo syncs the
   `src/` folder into Studio, which is how the code in this repo becomes a
   running game (`D-CHOMP-012`).
2. Clone this repo, open a terminal in `mbse/chomp-arena/`, and run:

   ```
   rojo serve
   ```

3. In Studio: new Baseplate → Plugins → Rojo → **Connect**. The tree from
   `default.project.json` appears in the Explorer.
4. Delete the default Baseplate part. `TestMap.server.lua` builds its own
   ground.

## Press play

Hit Play. You should get:

- A 24 × 24 cell ground deck with a corridor, a tower core, a ramp up to a
  raised deck, and a bridge crossing the corridor below.
- A camera locked to world north, 35° down, that follows you.
- A vehicle that **drives forward on its own**. Hold `A`/`D` (or the arrow
  keys) to steer. Double-tap the opposite direction to flip 180°.

There is no accelerator and no brake. That is the design (`D-CHOMP-015`).

## What to actually test — `CHOMP-TC-040`

This is the camera acceptance run, and it is the highest-risk item in the
project (`RISK-CHOMP-012`). Do it **on the iPad**, not in Studio: publish
privately, open it on the device, and play it there. Studio's window is not the
device, and the device is the reference platform.

1. Drive a full circuit of both decks. Go **under the bridge**, **around the
   tower core**, and up and down the ramp.
2. From the command bar afterwards:

   ```lua
   _G.ChompCameraReport()
   ```

   It prints the worst occlusion duration and how many times the 0.2 s ceiling
   was breached. **Any breach is a failure**, and the camera warns in the
   output the moment one happens, with how long you were hidden.
3. Watch for a jump cut on the ramp, in either direction. There should be
   none — deck height eases on a critically damped spring.
4. Drive off the bridge. The camera should follow you down without cutting.
5. Hand the iPad to your daughter and watch whether she ever loses track of her
   own vehicle. She is the acceptance test; the numbers are only the evidence.

If the camera cannot pass this on a map this trivial, the multi-level design is
in trouble — and finding that out now, before any real geometry exists, is the
entire reason this is built first.

## Tuning it

Everything is in `src/ReplicatedStorage/ChompConfig.lua`. Change a number,
re-sync, play. `Camera.PitchDegrees` and `Camera.Distance` are the two worth
experimenting with first; if you change either, **re-derive `Map.WallHeight`**,
because wall height is a camera constraint rather than an art choice
(`camera_spec.md`).

## What is not here yet

Pellets, the bar, banking, combat, ghosts, gates, rounds and the HUD. The v1
build order is deliberate (`RISK-CHOMP-005`), and each step ends with something
playable:

1. **Camera and driving** ← you are here
2. Drive and eat
3. Bank and upgrade
4. Directional combat
5. One ghost
6. One gate
7. Rounds and a winner

Do not start step 4 until step 3 is fun.
