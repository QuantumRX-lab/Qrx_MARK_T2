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

| Remote | Signature | Rate limit | Server rejects when |
|---|---|---|---|
| `RequestPurchase` | `(itemId: string)` | 4/s | Not in intermission or at own garage; unknown item; insufficient **banked**; prerequisite unmet |
| `RequestBank` | `()` | 2/s | Not inside own garage volume; `garageLockedUntil` in the future; nothing carried |
| `SetInputDirection` | `(direction: Vector2)` | 30/s | Vector not unit-length or NaN; player is respawning |

**No remote carries a quantity.** No price, no amount, no power, no hit, no
position. Everything a remote can express is *intent*; the server supplies
every number.

Rejections return silently to the client (a refusal sound is played locally on
timeout) and are counted per player. A player exceeding a rate limit by 10x for
5 seconds is logged with their userId — in a Friends-only game that is a
conversation, not a ban.
