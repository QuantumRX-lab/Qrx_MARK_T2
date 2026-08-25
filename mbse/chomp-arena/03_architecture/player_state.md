# The Player State Record

One record per connected player, held on the server, defined once in
`src/ReplicatedStorage/Types.lua` as `PlayerState`.

This document answers the question that otherwise gets answered ten different
ways by ten different agents: **who is allowed to write each field.**

## The single-writer rule

Every field has exactly one service that may write it. Any other service that
needs it changed **asks that service**, through the function named in the table.
There are no exceptions and no "just this once" direct writes.

This is not ceremony. Two services writing `carried` is how points quietly go
missing: combat subtracts, banking adds, both read a stale value, and one write
lands on top of the other. The bug appears weeks later as "she banked 400 and
only got 250", and it is close to untraceable.

| Field | Sole writer | Others request it via |
|---|---|---|
| `userId`, `garageSlot` | MatchService | `MatchService.assignGarage(player)` |
| `chassis`, `upgrades`, `power` | EconomyService | `EconomyService.purchase(player, item)` |
| `banked` | EconomyService | `EconomyService.bank(player)` |
| `carried` | EconomyService | `EconomyService.applyCarryDelta(player, delta, reason)` |
| `bar` | EconomyService | `EconomyService.applyBarDelta(player, delta, reason)` |
| `combo`, `comboExpiresAt` | EconomyService | `EconomyService.breakCombo(player)` |
| `garageLockedUntil` | EconomyService | — |
| `deck`, `ring` | MapService | — (derived from position, not set by anyone) |
| `invulnerableUntil`, `respawnAt` | CombatService | `CombatService.applyHit(...)` |
| `fullJawUntil` | CombatService | `CombatService.grantFullJaw(player, seconds)` |
| `gatePassUsed` | GateService | — |
| `joinedAtMatchTime` | MatchService | — |
| `saveBlocked` | DataService (v2) | — |

**The two that surprise people:** `bar` and `carried` are written by
EconomyService, not CombatService — even though combat is what removes them.
CombatService computes the deltas and hands them over. It keeps all arithmetic
on the two at-risk pools in one place, which is also the place the telemetry
for `CHOMP-TC-043` is emitted from.

Every mutating call takes a `reason` string (`"pellet"`, `"bite"`, `"ghost"`,
`"fall"`, `"guardian"`, `"bank"`, `"scatter"`, `"grant"`). That string is what
makes the fairness assertions possible — income by source is otherwise
unrecoverable after the fact.

## What the client is told

The client never receives another player's full record.

- **Own state:** everything (`OwnView`). The HUD renders it and holds none of
  it authoritatively (`CHOMP-SYS-030`).
- **Everyone else:** `PublicView` — chassis, power, deck, ring, whether Full Jaw
  is active, and a **carry band** rather than an exact carried total.

`carryBand` is `Light` (under 200), `Heavy` (200–599) or `Fat` (600+),
thresholds in ChompConfig.

### Why a band and not the number

You need to know who is worth chasing — that is half the strategy, and it is
what makes banking a real decision rather than a chore. You do not need the
exact figure, and sending it hands an exploiter a target list ranked by precise
value, plus the ability to compute exactly what a hit will yield before
committing to it. A band preserves the decision and removes the calculator.

It also happens to be kinder to a seven-year-old: "that one is Fat" is
readable at a glance in a way that "413" is not.

Logged as `D-CHOMP-013`.

## Lifecycle

| Moment | What happens |
|---|---|
| Join | MatchService assigns a garage slot, sets starting chassis, applies the catch-up grant, records `joinedAtMatchTime` |
| Eat | EconomyService raises `bar` (capped) and `carried` (uncapped), advances `combo` |
| Bank | `carried` → `banked` at 1:1, `bar` untouched, `garageLockedUntil` set |
| Purchase | `banked` reduced, `chassis`/`upgrades` changed, `power` recomputed immediately |
| Hit taken | CombatService sets `invulnerableUntil`, asks EconomyService for the bar and carry deltas, asks it to break the combo |
| Chomped | `respawnAt` set, 50% of `carried` scattered, upgrades **untouched** |
| Round end | Position and transient effects reset; progression persists |
| Match end | `chassis`, `upgrades`, `power`, `banked` all reset (`CHOMP-SYS-028`) |
| Leave | MatchService releases the garage slot; v2 DataService writes cosmetics only |

## Invariants

Assert these in a debug build. Each one is a bug that has already happened in
some other tycoon or arena game:

1. `bar` never exceeds the current chassis `BarCapacity` — and is re-clamped
   when a chassis downgrade happens at match end.
2. `carried` and `banked` are never negative. A delta that would go below zero
   clamps and logs, rather than wrapping into a negative fortune.
3. `power` always equals `computePower(chassis, upgrades)`. Never set it
   directly; recompute it.
4. A player with a non-nil `respawnAt` takes no damage and eats no pellets.
5. `invulnerableUntil` is only ever pushed forward, never backwards — otherwise
   a second hit in the same frame shortens the window it just created.
6. Scattered points always equal the points removed. Nothing is created or
   destroyed by combat, only moved to the floor.
