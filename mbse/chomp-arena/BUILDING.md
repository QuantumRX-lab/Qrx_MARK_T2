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


---

# Working on this machine

Notes from actually getting the toolchain up on the Windows laptop, so nobody
has to rediscover them.

## Installed here

| Component | Version | Notes |
|---|---|---|
| Roblox Studio | 0.735.0.7351131 | Installed from roblox.com, **not** winget |
| Rojo CLI | 7.7.0 | winget (`Rojo.Rojo`) |
| Rojo Studio plugin | 7.7.0 | `Rojo.rbxm` dropped into `%LOCALAPPDATA%\Roblox\Plugins` |

Studio account: `GlitchWarden43`.

## Install traps, already hit

- **winget cannot install Roblox Studio.** It fails with `Installer hash does
  not match`: the manifest pins a hash for a rolling URL Roblox republishes
  continuously, so it goes stale within days. Use the roblox.com download and
  verify the Authenticode signature (`CN=Roblox Corporation`) instead — that is
  stronger evidence than the hash that failed.
- **`rojo plugin install` fails on a fresh Studio** with `Couldn't find registry
  keys`. It looks for `HKCU:\Software\Roblox\RobloxStudioBrowser`, which only
  exists after Studio has been launched *and signed into*. Either sign in first
  or drop `Rojo.rbxm` into the plugins folder by hand.
- **Studio's Plugin Management shows "You haven't installed any plugins yet"**
  even when a local plugin is working. It only lists Marketplace plugins.
- **winget appends to PATH**, so terminals opened before the install will not
  find `rojo`. Open a new one.

## PowerShell and keyboard quirks

- Windows PowerShell 5.1: **`&&` is a parse error.** Use `;`.
- The function keys are in media mode, so `F5` and `F8` open display options
  rather than playtesting. Use the toolbar buttons, or `Fn`+`F5`.

## Rules that bite

- **Stop the playtest before editing.** Changes do not apply to an already
  running session.
- **Never write code in Studio's editor.** Sync is one-way, files to Studio;
  the next sync overwrites anything typed in Studio. Code lives in files.
  Studio is for the 3D world and for testing.
- **`Play` runs client and server in one process, which hides replication
  bugs.** Anything touching remotes or player state must be tested with
  **Test tab → Clients and Servers → 2 players**. For this project that is
  everything: the economy, combat and gate systems are all server-authoritative
  by design, and a single-process test cannot show you a broken boundary.

## Test modes

| Mode | How | What it gives you |
|---|---|---|
| Play | toolbar / Fn+F5 | Your character spawns. Everyday testing |
| Play Here | Test tab | Spawns at the camera. Useful in a large map |
| Run | Fn+F8 | World runs, no character. Server logic only |
| Clients and Servers | Test tab | Separate processes. The real network boundary |

## Not set up yet

No automated test harness. The verification strategy calls for TestEZ specs
over the pure logic in `ChompLogic/` plus a scripted-bot integration harness
(`04_verification/verification_strategy.md`), and `run-in-roblox` is the usual
way to drive them headlessly. Worth adding once `Impact` and `Progression` have
real implementations to regress — the stubs are shaped for it, which is why
they take plain numbers and return plain tables.
