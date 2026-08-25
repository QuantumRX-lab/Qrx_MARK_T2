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
- A vehicle driven by direction. `W` `A` `S` `D` or the arrows are north, west,
  south and east: hold one and it goes that way, release and it coasts to a
  stop. Stopped, a direction press snaps it round instantly; moving, it turns at
  the chassis rate. Push the opposite direction to turn around.

On touch this is a single **floating** stick: it anchors wherever the finger
lands, so there is nothing to find and nothing to lose (`D-CHOMP-027`, which
supersedes the always-forward rule of `D-CHOMP-015` and the hold-to-drive
scheme of `D-CHOMP-026`).

## What to actually test — `CHOMP-TC-040`

This is the camera acceptance run, and it is the highest-risk item in the
project (`RISK-CHOMP-012`). Do it **on the iPad**, not in Studio. Studio's
window is not the device, and the device is the reference platform.

### Getting it onto the device

1. Sync Rojo so the place is current, then run `python guard.py`.
2. Studio: **File → Publish to Roblox As…**, name it, create.
3. **create.roblox.com** → the experience → **Configure** → confirm privacy is
   **Private**. `CHOMP-SYS-035` says private now; Friends-only later and only by
   an explicit decision. Do not let it default to public.
4. Copy the experience link from the Creator Dashboard.
5. On the iPad, sign into the Roblox app as the owner, then open that link in
   Safari and tap Play. Private experiences do not appear in search, so the link
   is the only way in.

### The run

1. Drive a full circuit of both decks. Go **under the bridge**, **around the
   tower core**, and up and down the ramp.
2. Read the figures off the **top of the screen**. The readout shows worst
   occlusion, the limit, and a breach count, and turns red the moment
   `CHOMP-SYS-051` fails. **Any breach is a failure.** While the vehicle is
   actually hidden it shows `HIDDEN` and a running duration, so you can see
   *which* piece of geometry did it rather than only that something did.

   There is no command bar on an iPad. `_G.ChompCameraReport()` still works in
   Studio, but the readout is the device procedure (`D-CHOMP-029`). **RESET**
   clears the run so you can go again without rejoining.
3. Watch for a jump cut on the ramp, in either direction. There should be
   none — deck height eases on a critically damped spring.
4. Drive off the bridge. The camera should follow you down without cutting.
5. Hand the iPad to your daughter and watch whether she ever loses track of her
   own vehicle. She is the acceptance test; the numbers are only the evidence.
   This is also the first time the touch controls have ever been used: the stick
   floats and anchors wherever her thumb lands, a second finger is ignored, and
   pulling back reverses and swings the vehicle around (`D-CHOMP-027`). None of
   that has been felt by anyone — Studio only ever tested the keyboard.

Turn the readout off in `ChompConfig.Debug.CameraReadout` before anyone plays
this for fun rather than to measure it.

If the camera cannot pass this on a map this trivial, the multi-level design is
in trouble — and finding that out now, before any real geometry exists, is the
entire reason this is built first.

## Before you playtest

```
python guard.py
```

Builds the place and refuses it if two children of one parent share a name, or
if a `WaitForChild` target does not exist. Both are silent at runtime and loud
here. Exit code is 0 on pass, 1 on failure, so it drops straight into a hook or
a CI step. `--no-build` checks the existing place; `--quiet` prints errors only.

Run `python validate.py` too if you touched the tree. The two are separate on
purpose: `validate.py` checks the MBSE records agree with each other,
`guard.py` checks the built game agrees with the code that reads it.

## Gotchas that cost real time

**`rojo serve` reads `default.project.json` once, at startup.** Editing a file
under a `$path` syncs live; changing the *project file* — adding, renaming or
removing a declared instance — does not. The old tree keeps being served and the
symptom is an instance that is "missing" no matter how many times you reconnect.
Restart the server after any project-file edit.

**Never give a declared instance the same name as a module syncing into the same
parent.** Rojo creates both, and `WaitForChild` then picks arbitrarily between
them. This cost two playtests: a `Remotes` folder declared alongside
`Remotes.lua` meant `WaitForChild("Remotes")` returned the ModuleScript, which
has no children (`D-CHOMP-024`).

**A stale `rojo serve` from another project holds port 34872** and will happily
sync Studio with the wrong tree. `Stop-Process -Name rojo -Force`.

**Studio's Plugin Management window lists only Marketplace plugins.** A locally
placed `.rbxm` works but never appears there — its absence is not a problem.

**PowerShell 5.1: `&&` is a parse error.** Use `;`.

**Function keys may be in media mode** — `F5` opens display options rather than
playtesting. Use the toolbar buttons, or `Fn`+`F5`.

**Rojo disconnects when you press Play.** Expected. Reconnect after stopping.

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
