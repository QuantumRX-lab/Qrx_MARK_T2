# Handover — Chomp Arena

**From:** a remote Claude Code session (Linux container, cloud)
**To:** a local session on the Windows laptop
**Date:** 2026-08-25

The reason for the handover is simple: **the remote session cannot run Roblox
Studio.** Studio is Windows and Mac only, the container is Linux with no
display, and there is no headless Roblox runtime to substitute. Every
engine-level bug therefore cost a round trip through a human. A local session
can press Play itself.

---

## 1. What this is

**Chomp Arena** — a combative multiplayer Pac-Man for Roblox, built by a father
with his 7-year-old daughter, played on an iPad.

Drive a Pac-Man-shaped vehicle through a multi-level maze, eat pellets, bank
them at your garage, spend the takings on upgrades, and fight other players **by
direction**: your mouth is your weapon, your flanks and back are weak spots.
Ghosts steal your unbanked points. Super ghosts guard the ramps to the richer
decks above, and only let you past when your Power exceeds their Threat.

Read `00_need/game_concept.md` first. It is written for a person.

---

## 2. Where everything is

| | |
|---|---|
| Repo | `github.com/QuantumRX-lab/Qrx_MARK_T2` |
| Branch | `chomp-arena` |
| Project root | `mbse/chomp-arena/` |
| Working clones (Windows) | both `Qrx_MARK_T2` and `Qrx_MARK_T2_specs` under `Documents/Codex/2026-08-25/what/work/`, both on `chomp-arena` |

Both working clones are on `chomp-arena` and both push to it. The fossil
branches `claude/kitty-coaster-tycoon-7i4ebg` and
`codex/hud-gameplay-requirements` were merged and deleted on 2026-08-25.

Two other directories are NOT this project: `roblox-game` under the user
profile is a throwaway scaffold from the toolchain-install session, and
`C:/Qrx_MARK_T2` is a different repository entirely.

**Check which branch a clone is on before trusting a `git pull`.** A clone
sitting on another branch reports "Already up to date" while being several
commits behind the one the game is built from. That cost an evening.

### Layout

```
mbse/chomp-arena/
├── README.md                 tree guide
├── BUILDING.md               how to sync, run, and the Windows toolchain notes
├── HANDOVER.md               this file
├── validate.py               run after ANY edit to the tree
├── default.project.json      Rojo mapping
├── build/ChompArena.rbxlx    generated place — a convenience, goes stale
├── src/                      the actual game (DataModel-shaped, Rojo syncs it)
├── 00_need/                  need statement, game concept
├── 01_stakeholders/
├── 02_requirements/          requirements, phased v1/v2/v3
├── 03_architecture/          the specs that constrain the code
├── 04_verification/          test cases + the verification strategy
├── 05_risks/                 the risk register
├── 06_decisions/             every decision with rationale, plus a generated INDEX.md
├── 07_change/                changelog
├── 08_status/dashboard.yaml  rollups, checked by validate.py
└── workstreams/              one append-only log per decomposition chain
```

---

## 3. State right now

### Works
- Rojo builds; the place opens; the test map builds itself on run.
- Camera, input, movement and the test map are written and loading.
- Four chassis models delivered by Codex and geometrically verified.

### Verified
- All four vehicles pass mouth orientation, centring, wedge direction, bounds
  and part budget — computed from the built XML, not guessed.
- `validate.py` passes: 0 errors, 0 warnings.

### NOT verified — this is the immediate job
- **Nobody has confirmed the game is drivable since the last fix.** Steering was
  silently dead for two playtests (see §5), and the fix has not been played.
- `CHOMP-TC-040`, the camera acceptance run, has never completed.
- Nothing has been tested on the iPad, which is the reference platform.
- No requirement has `verification_status` above `NOT_STARTED`, deliberately.
  Code existing is not a requirement being verified.

---

## 4. Do these first

1. **Pull, sync, press Play, and answer one question: can you steer?**
   Then drive the circuit in `BUILDING.md` and run `_G.ChompCameraReport()`
   from the Command Bar with the Client/Server toggle set to **Client**. Any
   breach of the 0.2 s occlusion ceiling is a `CHOMP-SYS-051` failure and
   blocks building real map geometry.

2. **Run the vehicle conformance scan** in Edit mode:
   ```lua
   local S = require(game.ServerStorage.ChompTools.VehicleConformance) S.report(S.checkAll())
   ```
   This closes the last two open checks on Codex's models — the numeric
   attributes and the silhouette fraction. Record the result in
   `workstreams/CHAIN-VEHICLE/log.yaml`.

3. **Build the test harness that was about to be built when this handed over.**
   Two parts, and the first would have caught the bug that wasted two
   playtests:
   - a **static load-order guard**: every module-scope `WaitForChild` must
     resolve to something declared in `default.project.json` or created by a
     script that definitely runs;
   - **Luau unit specs** for `src/ReplicatedStorage/ChompLogic/`, whose stubs
     were written to be testable — plain numbers in, plain tables out.
   A local session can run these through Studio directly, or through
   `run-in-roblox`. The remote session was going to use Lune; use whatever is
   cheapest locally.

4. **Then the v1 build order**, from `RISK-CHOMP-005`. Each step ends with
   something playable, which matters because the audience is seven:
   camera and driving → drive and eat → bank and upgrade → directional combat
   → one ghost → one gate → rounds and a winner.
   **Do not start combat until banking is fun.**

---

## 5. Bugs already fixed — do not reintroduce them

Three cost real time. All three are logged as decisions.

**`D-CHOMP-018` — never drive a player's character from the server.**
`MovementService` originally wrote `root.CFrame` every heartbeat. Roblox gives
the client network ownership of its own character, so that is two authorities
writing one transform sixty times a second: jitter, rubber-banding, and a first
playtest that reported the handling as unusable. Steering now runs client-side.
The server still owns the *numbers* — it computes speed and turn, writes them
onto the character as attributes, re-asserts `WalkSpeed`, and flags impossible
travel. No security property was lost.

**`D-CHOMP-021` — instances that must exist belong in the project file.**
`Remotes.lua` created its three RemoteEvents at require time, on whichever side
required it first. Rewriting `MovementService` removed the last server-side
require, so nothing created them, and a client requiring the module yielded
forever — which silently disabled **all steering**, because `InputController`
requires it at the top of the file. It presented as an unrelated
`Infinite yield` warning, not as broken controls, which is why it survived a
playtest. The remotes are now declared in `default.project.json`, and input
acquires the module off-thread so the network can never block driving again.

**`D-CHOMP-019` — tuning values never live on a model.**
The contract required chassis models to mirror `BaseSpeed`/`BaseTurn`. The first
retune moved turn rates by more than half and would have failed all four
delivered models on a mismatch that says nothing about them. Models carry
identity and shape; `ChompConfig` carries tuning.

---

## 6. Ground rules

**The tree is the source of truth, not the code.** If work proves a requirement
wrong, amend `02_requirements/requirements.yaml` and add a decision explaining
why. A chain log records activity; the tree records truth.

**Run `python validate.py` after any edit to the tree.** It recomputes every
count and cross-reference from the atomic records and refuses to trust a
handwritten total. It has already caught a stale dashboard rollup in this
session. It also enforces:
- every `CRITICAL`/`HIGH` requirement has an `AUTOMATED` or `HYBRID` test, or a
  written `automation_exempt_reason` (only two exist, both honest);
- bidirectional requirement ↔ test traces;
- phase ordering — a requirement whose only test ships later would go out
  unverified;
- chain logs matching the tree, including that no entry cites another chain's
  requirement.

**Every number lives in `ChompConfig` exactly once** (`CHOMP-SYS-037`). A
balance literal in engine logic is a bug.

**No remote carries a quantity.** Three remotes, intent only, server supplies
every number. A fourth means extending the exploit suite in the same commit.

**Never write code in Studio's editor.** Sync is one-way; the next sync
overwrites it. Code lives in files.

**`Play` hides replication bugs** — it runs client and server in one process.
Anything touching remotes or player state needs Test → Clients and Servers → 2
players. For this design that is eventually everything.

---

## 7. The other agent

**Codex** owns `CHAIN-VEHICLE` model work — `CHOMP-SYS-003` and
`CHOMP-SYS-054`, and the four chassis. It has behaved well: twice it declined
to claim a conformance pass it could not honestly run, and logged `BLOCKED`
instead. Both blockers were real gaps in the contract.

A claim split is open and unacknowledged: the remote session took
`CHOMP-SYS-001`, `-002` and `-051` (movement and camera) because they were
blocking everything. That is logged in `workstreams/CHAIN-VEHICLE/log.yaml`.
Worth resolving explicitly.

Nine of the ten chains have no owner. If more agents are added, the interface
contracts in `03_architecture/service_contracts.md` are what stop them
colliding — and `workstreams/README.md` is the protocol: claim before working,
log `BLOCKED` rather than editing across a chain boundary, never edit an
existing log entry.

---

## 8. Environment

Full detail in `BUILDING.md`. The traps worth knowing up front:

- **PowerShell 5.1: `&&` is a parse error.** Use `;`.
- Function keys are in media mode — `F5` opens display options. Use the toolbar
  buttons or `Fn`+`F5`.
- `rojo serve` holds a terminal. Use a second window for git.
- **Rojo disconnects when you press Play.** Expected. Reconnect after stopping.
- A stale `rojo serve` from another project will hold port 34872 and happily
  sync Studio with the wrong project. `Stop-Process -Name rojo -Force`.
- winget cannot install Roblox Studio; its manifest pins a hash for a rolling
  URL. Use the roblox.com download.
- Studio account: `GlitchWarden43`. Publish **Private**; Friends-only later, and
  only by an explicit decision (`CHOMP-SYS-035`).

---

## 9. What the remote session could not do, and you can

- **Press Play.** Everything about feel, physics, replication and the camera
  needs the engine.
- **Test on the iPad** — the reference platform (`CHOMP-STK-007`). Studio's
  window is not the device, and touch is the primary control scheme
  (`D-CHOMP-015`: hold to turn, always driving forward, no buttons).
- **Watch the seven-year-old play.** `CHOMP-TC-001` and `CHOMP-TC-002` are the
  only two tests in the tree that can say whether the game is any good, and
  both are exempt from automation for the honest reason that no machine can
  judge them.

The remote session could build the place with Rojo, read the resulting XML to
verify model geometry, and reason about the code. That is enough to be sure it
loads and the numbers are right. It is not enough to know whether it drives
well — and that gap is the whole reason you are reading this.
