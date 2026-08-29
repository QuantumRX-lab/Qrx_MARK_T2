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
4. Delete the default Baseplate part. `Level1Map.server.lua` builds its own
   ground - a sealed 800-stud disc. `TestMap` and `ArenaMap` still exist but
   gate themselves off unless `ChompConfig.Map.Layout` names them.
5. There is no managed `Lighting` in the Baseplate template, and the game now
   builds its own at runtime (`WorldLook.server.lua`). If the arena looks like
   a bright afternoon rather than a neon night, that script did not run.

## Press play

Hit Play. In order, you should get:

1. **`LOADING GARAGE`** for a moment while the profile loads. In Studio this is
   instant and ephemeral - `ProfileService` deliberately skips the DataStore
   when `RunService:IsStudio()`, so nothing you do in Studio is ever saved.
2. **The launch bay**, which is the home garage pad: a panel reading
   `CHOOSE VEHICLE + LOADOUT`, the shop row of plinths in front of you, and the
   gold bank beacon overhead. You are safe here and ghosts cannot reach you.
3. **Deployment** the moment you drive off the yellow pad - a three-second
   countdown, then `CHOMP!` and three seconds of spawn protection. There is no
   button: leaving the pad IS the commitment. Wave one starts when the first
   player deploys, not at server boot.
4. **The arena**: one sealed disc 800 studs across, seven concentric ring
   corridors each in its own surface (neon, brick, slate, neon, cobblestone,
   brick, concrete), an open centre worth the most, and four garages ringed
   with a green sanctuary line.

Controls, keyboard: `W` `A` `S` `D` or the arrows steer proportionally - hold to
drive, pull back to reverse and swing round. `Space` fires and is **held**, not
tapped; the cannon is a machine gun and the server paces it (`D-CHOMP-042`,
`D-CHOMP-056`).

On touch it is a single **floating** stick that anchors wherever the thumb
lands, plus a **second finger anywhere to hold fire** (`D-CHOMP-027` as amended:
the second touch used to be discarded, which made the machine gun keyboard-only
on the one device this game is for). A quick tap of the stick finger also fires,
for one-handed play.

## What to actually test on the iPad

Studio's window is not the device, and the device is the reference platform.
Three things **cannot** be tested in Studio at all:

- **Persistence.** `ProfileService` skips the DataStore in Studio by design.
  Saving, rejoining and the degraded read-only path only exist on a published
  place.
- **Two-finger fire.** A mouse has one pointer.
- **Frame rate.** The 30 fps budget is a device number, not a desktop one.

### Getting it onto the device

1. `python guard.py && python validate.py`, then sync Rojo so the place is
   current.
2. Studio: **File → Publish to Roblox As…**, name it, create.
3. **create.roblox.com** → the experience → **Configure** → confirm privacy is
   **Private**. `CHOMP-SYS-035` says private now; anything wider is an explicit
   decision. Do not let it default to public.
4. Copy the experience link from the Creator Dashboard.
5. On the iPad, sign into the Roblox app **as the owner**, then open that link
   in Safari and tap Play. Private experiences do not appear in search, so the
   link is the only way in.

> **Private means "people with edit access", not "people with the link."** If
> she plays on her own Roblox account she will be refused, and it looks exactly
> like the game being broken. Either add her as a collaborator under
> **Configure → Access**, or sign the iPad in as the owner for now.

### The run

**A. Arrival and the bay.** Does the panel appear, does the profile resolve, can
you read the plinth prices at a glance? Drive the shop row: stop at a plinth and
hold still - the dwell bar fills and the purchase confirms. Buy something cheap.

**B. Deployment.** Drive off the pad. Countdown, then `CHOMP!`. Confirm ghosts
do not touch you inside the sanctuary line, and that the wave did not begin
before you left.

**C. Two-finger fire — the headline.** One thumb steering, a second finger
holding fire. This is the first time anyone has used it. Can she drive a
corridor and shoot a ghost at the same time, without stopping? If not, nothing
else on this list matters.

**D. Camera occlusion (`CHOMP-TC-040`).** Drive a full circuit of every ring,
through gaps, along the boundary and across the open centre. The readout is at
the top of the screen: worst occlusion, the limit, and a breach count, going red
the moment `CHOMP-SYS-051` fails. **Any breach is a failure.** `RESET` clears a
run without rejoining. There is no command bar on an iPad; the readout is the
device procedure (`D-CHOMP-029`).

**E. Frame rate under load.** Get a full wave on screen - nine ghosts or more,
pellets, lighting - and watch for stutter. `Budgets.TargetFPS` is 30.

**F. Persistence, the one Studio cannot do.** Earn, bank, buy a chassis, then
**fully close the experience and rejoin**. Money and chassis should still be
there. Then check the degraded path is survivable: it should be impossible to
reach a state where the bay never releases you.

**G. Hand it to her and say nothing.** She is the acceptance test; the numbers
are only evidence. Watch whether she ever loses track of her own vehicle, and
whether she works out what to do without being told.

Turn the readout off in `ChompConfig.Debug.CameraReadout` before anyone plays
this for fun rather than to measure it.

### What has no test case yet

The bay sequence, the deployment gate, profile persistence, the degraded
read-only path and two-finger fire are all **built and unspecified**: no
requirement covers them and no `CHOMP-TC` verifies them. Test them from this
list, and treat the gap as tree debt rather than as coverage.

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

## Guardian Build 1 check

Press Play, wait for the guardian to spawn, then run this in the Studio command
bar:

```lua
local C = require(game.ServerStorage.ChompTools.GuardianConformance)
C.report(C.checkAll())
```

The automated report checks the 1.5-second tell floor, non-one-shot attack
damage, punish-window duration, chamber contrast, guardian face geometry and
live phase attributes. It complements rather than replaces `CHOMP-TC-058` and
`CHOMP-TC-059`: visually confirm the Pounce circle, Dash lane and Ghost Hurl
landing marks are understandable from the play camera, then confirm cover stops
the dash and opens the glowing maw.

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

## Directional combat check

With the generated place open and stopped, run this in Studio's command bar:

```lua
local C = require(game.ServerStorage.ChompTools.CombatConformance)
C.report(C.checkAll())
```

That checks the pure angle and economy boundaries. It does not replace the
network test: use **Test > Clients and Servers > 2 players** for contact,
feedback, scatter collection, shield and touch-layout acceptance.
