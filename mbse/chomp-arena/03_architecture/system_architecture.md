# System Architecture

## Where everything lives

```
game
├── Workspace
│   └── Maps
│       └── <MapName>
│           ├── Deck1 … DeckN      one grid per deck
│           ├── Links              ramps, bridges, shafts — explicit deck-to-deck edges
│           ├── Gates              guardian positions, Threat attributes
│           ├── Garages            12, three per quadrant
│           └── Decor              never read by the engine
├── ReplicatedStorage
│   ├── ChompConfig                every tunable number, exactly once
│   ├── Remotes                    the only client→server surface
│   └── Vehicles                   chassis models (Codex's deliverable)
├── ServerScriptService
│   └── ChompEngine
│       ├── EconomyService         pellets, carry, bank, upgrades, Power
│       ├── CombatService          angle classification, damage, scatter, invulnerability
│       ├── GhostService           spawning, scaling, pathing
│       │   └── Behaviours         one module per personality
│       ├── GateService            guardians, Threat checks, open windows
│       ├── MatchService           rounds, intermissions, reset, standings
│       └── MapService             discovery by tag, deck graph construction
├── ServerStorage
│   └── ChompTools                 v3: mirror tool, Check My Maze
├── StarterPlayer
│   ├── ChompVehicle               local movement prediction and effects
│   └── ChompCamera                locked angle, deck-following, occlusion fade
└── StarterGui
    └── ChompHud                   display only
```

The tree position **is** the security boundary: anything under `ServerStorage`
or `ServerScriptService` never reaches a client. That is why every authoritative
number lives there and the HUD holds none of them.

## The one rule everything else follows

**The client predicts and displays. The server decides and remembers.**

The client may move the vehicle, play a chomp sound, flash a hit, and animate a
mouth. It may never decide that a pellet was eaten, that a hit landed, what a
purchase cost, or what a player's Power is. Every remote handler re-derives
what it trusts from server state and rate-limits the caller.

This is not paranoia about a family game. It is that the moment the place is
Friends-visible, a single client asserting `myPower = 900` lives in the Vault,
and a competitive game whose scores can be forged is not a game.

## Client → server surface

The entire surface is small on purpose. Each remote carries identity and intent
only — never a quantity:

| Remote | Client sends | Server decides |
|---|---|---|
| `RequestPurchase` | upgrade or chassis identifier | price, affordability, whether it applies, new Power |
| `RequestBank` | nothing | whether the player is in their own garage, and what converts |
| `RequestBoard` / movement | input direction only | speed, turn rate, resulting position authority |

Pellet consumption, combat resolution, gate checks, ghost behaviour and match
state have **no client entry point at all**. They are server-side consequences
of server-observed positions.

## The deck graph

Ghost pathing treats each deck as a grid and each ramp, bridge or shaft as an
explicit edge between decks, built by `MapService` at load time from tagged
`Links`. Ghosts choose a direction at each junction by their behaviour rule; the
rule's candidate set simply includes vertical edges where they exist.

Keeping the vertical edges as authored data rather than something inferred from
geometry is what keeps multi-level pathing cheap — and it is why maps are built
from snapped prefab pieces (`RISK-CHOMP-008`).

## Content discovery

`MapService` finds everything by tag or folder convention, never by hardcoded
instance path (`CHOMP-SYS-038`). Adding a pellet, a gate or a whole deck is a
content change. This costs nothing now and is the difference between v3 being an
exposure of what already exists and v3 being a rewrite.
