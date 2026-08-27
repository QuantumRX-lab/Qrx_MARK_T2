# Service Contracts

The vehicle contract did this for models. This does it for code.

Each service below states what it **owns**, what it **exposes**, and what it
**must not touch**. A chain works inside its own service. If it needs something
from another, it calls the exposed function — it does not reach into the other
service's state, and it does not add a second writer to a field it does not own
(see `player_state.md`).

## MatchService — CHAIN-MATCH

**Owns:** round and match state, the clock, standings, garage slot assignment,
the catch-up grant, per-match reset.

```lua
MatchService.assignGarage(player)        --> slot: number
MatchService.releaseGarage(player)
MatchService.currentRound()              --> {index, secondsRemaining, mapName}
MatchService.matchElapsed()              --> seconds
MatchService.standings()                 --> { {userId, banked}, ... } sorted
MatchService.isIntermission()            --> boolean
```

**Emits:** `RoundStarted(index, mapName)`, `RoundEnded(index, standings)`,
`MatchEnded(standings)`, `IntermissionStarted(seconds)`.

**Must not:** touch `bar`, `carried` or `banked` directly — the catch-up grant
goes through `EconomyService.applyBankDelta(player, amount, "grant")`.

## EconomyService — CHAIN-ECONOMY

**Owns:** every number a player can gain or lose. Pellets, the bar, carried,
banked, chassis, upgrades, power, combo, garage lock.

```lua
EconomyService.applyBarDelta(player, delta, reason)     --> applied: number
EconomyService.applyCarryDelta(player, delta, reason)   --> applied: number
EconomyService.applyBankDelta(player, delta, reason)    --> applied: number
EconomyService.bank(player)                             --> converted: number
EconomyService.purchase(player, itemId)                 --> ok: boolean, why: string?
EconomyService.breakCombo(player)
EconomyService.scatter(position, amount, reason)        --> spawned: number
EconomyService.canAfford(player, itemId)                --> boolean
```

Every delta function returns **what was actually applied** after clamping. A
caller that assumes its requested amount was applied will drift from the truth
the first time a clamp bites.

**Emits:** `Banked(userId, amount)`, `Purchased(userId, itemId, newPower)`,
`IncomeRecorded(userId, amount, reason)` — the last is what
`CHOMP-TC-043` consumes.

**Must not:** decide whether a hit landed, or what a hit costs. It applies
deltas that CombatService computed.

## CombatService — CHAIN-COMBAT

**Owns:** contact detection, impact classification, invulnerability, respawn,
Full Jaw state, falls, drop attacks.

```lua
CombatService.applyHit(attacker, defender, impact: ImpactResult)
CombatService.applyGhostHit(player, ghostId)
CombatService.applyFall(player, fromDeck, toDeck)
CombatService.grantFullJaw(player, seconds)
CombatService.isInvulnerable(player)                    --> boolean
CombatService.isFullJaw(player)                         --> boolean
```

**Emits:** `HitLanded(attackerId, defenderId, kind)`, `Chomped(userId, by)`,
`FullJawStarted(userId)`, `FullJawEnded(userId)`.

**Must not:** write `bar` or `carried`. It computes an `ImpactResult` with the
pure logic in `ChompLogic.Impact`, then hands the deltas to EconomyService.
This is the boundary that keeps the combat maths unit-testable.

## GhostService — CHAIN-GHOSTS

**Owns:** ghost spawning, the ghost count, movement along the deck graph,
behaviour module dispatch, flee state.

```lua
GhostService.setGhostCount(n)
GhostService.recomputeCountForPlayers(playerCount)      --> n: number
GhostService.spawn(behaviourName, junction)             --> ghostId: string
GhostService.despawn(ghostId)
GhostService.worldView()                                --> WorldView
```

Behaviour modules live in `ServerScriptService/ChompEngine/Behaviours/` and
receive only the `WorldView` (see `Types.lua`). A behaviour that calls
`game:GetService` is a contract violation — it breaks unit testing now and
breaks the v3 child-authoring story later.

**Must not:** apply damage. Ghost contact goes to
`CombatService.applyGhostHit`.

## GateService — CHAIN-GATES

**Owns:** guardians, Threat comparison, the open window, guardian reform, the
Full Jaw gate pass.

```lua
GateService.threatOf(gateId)                            --> number
GateService.attemptPassage(player, gateId)              --> "Passed" | "Ejected" | "Cracked"
GateService.isOpen(gateId)                              --> boolean
```

**Emits:** `GateCracked(gateId, byUserId)`, `GateClosed(gateId)`.

**Must not:** read a Power value supplied by a client, ever. It reads
`PlayerState.power`, which EconomyService computed.

## MapService — CHAIN-MAZE

**Owns:** map loading, content discovery by tag, the deck graph, ring
membership, garage and gate registries.

```lua
MapService.load(mapName)
MapService.junctions()                                  --> { Junction }
MapService.junctionAt(position)                         --> Junction?
MapService.ringAt(position)                             --> number
MapService.deckAt(position)                             --> number
MapService.garages()                                    --> { {slot, cframe, volume} }
MapService.gates()                                      --> { {gateId, ring, cframe} }
```

Everything is found by tag, never by hardcoded path (`CHOMP-SYS-038`).

## Client side

| Controller | Chain | Owns | Must not |
|---|---|---|---|
| `VehicleController` | CHAIN-VEHICLE | Input, local movement prediction, mouth animation, chomp effects | Decide a pellet was eaten or a hit landed |
| `CameraController` | CHAIN-VEHICLE | Angle, follow, deck transitions, occlusion fade | Move the character |
| `HudController` | CHAIN-UI | Rendering replicated values, touch controls, gate colour, off-deck markers | Hold any authoritative value, or do economy arithmetic |

## The remote surface — complete

Three remotes. That is the entire client-to-server attack surface, and adding a
fourth means extending the exploit suite (`CHOMP-TC-042`) in the same commit.

**The remotes are declared in `default.project.json`, not created at runtime.**
They were originally created by whichever side required the module first, which
was a race waiting to fire — and it fired: when `MovementService` was rewritten
and stopped requiring the module, nothing on the server created them any more,
so a client requiring it yielded forever and took the input controller down
with it. Declaring them in the project file means they exist before any code
runs.

**Nothing on the critical path may block on a remote.** Input in particular
acquires the module off-thread and drives locally regardless — a player should
never be unable to steer because the network surface is not ready.

| Remote | Signature | Rate limit | Server rejects when |
|---|---|---|---|
| `RequestPurchase` | `(itemId: string)` | 4/s | Not in intermission or at own garage; unknown item; insufficient **banked**; prerequisite unmet |
| `RequestBank` | `()` | 2/s | Not inside own garage volume; `garageLockedUntil` in the future; nothing carried |
| `SetInputDirection` | `(intent: Vector2)` | 30/s | Not a Vector2; either component NaN; `X` outside [-1, 1]; player is respawning |
| `UseItem` | `()` | 14/s | Over the rate limit; no item carried; charges exhausted; player dead or respawning; ANY argument present |
| `UseCharge` | `()` | 3/s | Over the rate limit; charge below JumpCost; player dead or respawning; ANY argument present |
| `ToggleFriendlyFire` | `()` | 2/s | Over the rate limit; ANY argument present |
| `SelectItem` | `(slot: number)` | 6/s | Not a number; NaN; below 1; beyond the belt the SERVER holds |
| `ToggleModule` | `(track: string)` | 4/s | Not in a sanctuary; unknown track; licence not owned; no free chassis port |

`SetInputDirection`'s `X` is steering intent in [-1, 1] and `Y` is 1 on the
frame a flip is requested. Neither is a quantity the server trusts for anything
beyond intent: the server owns speed, turn rate and position, and a flip in
progress is a rotation the server drives to completion.

**No remote carries a quantity.** No price, no amount, no power, no hit, no
position. Everything a remote can express is *intent*; the server supplies
every number.

`UseItem` takes that to its conclusion and carries *nothing at all* — not the
item, not the charge count, not an aim vector, not a target. It means only "use
what I am holding". The server knows what that is, how many charges remain, and
which way the vehicle points, the last of which it reads from the character
transform it wrote itself. A client that appends arguments is rejected rather
than ignored, because a message that grew a field is a client that was modified
(`D-CHOMP-045`, `CHOMP-SYS-059`).

`SelectItem` and `ToggleModule` carry selections, not quantities. A slot index
asserts nothing about price, damage, charge or position, and the server still
owns what is in that slot. A module track names the licence the player wants to
fit or remove; the server owns the licence level, chassis port count and current
loadout. Forged selections therefore change nothing (`D-CHOMP-062`).

`UseCharge` and `ToggleFriendlyFire` follow the same rule and carry nothing
either. The first means "spend my charge if I have it" and the second means
"flip my own switch"; the server holds the meter and the switch, so neither
message contains a value worth forging (`D-CHOMP-059`).

Rejections return silently to the client (a refusal sound is played locally on
timeout) and are counted per player. A player exceeding a rate limit by 10x for
5 seconds is logged with their userId — in a Friends-only game that is a
conversation, not a ban.
