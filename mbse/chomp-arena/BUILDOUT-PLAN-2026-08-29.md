# Chomp Arena build-out plan

> **Build order superseded by `D-CHOMP-076`.** Product choices in this document
> remain active; the authoritative 1-6 delivery and requirement tree is
> [`BUILD-PLAN-1-6-REQUIREMENT-TREE.md`](BUILD-PLAN-1-6-REQUIREMENT-TREE.md).

**Baseline:** `0.4.0-alpha`

**Decision:** `D-CHOMP-075`
**Goal:** a private Roblox release with a complete Level 1 session, followed by
a Level 2 that changes how the game is played rather than only raising numbers.

## The game loop we are building

```text
ARRIVAL BAY
  choose vehicle and loadout
        |
        v
WAVE
  collect a wave haul -> fight ghosts and players -> survive or spill it
        |
        v
ROUND BREAK
  survivors auto-bank -> everyone upgrades -> next wave
        |
        v
GUARDIAN
  read telegraphs -> survive attack modes -> hit the open weak point
        |
        v
LEVEL 2 GRID OPENS
  new palette -> vertical firing positions -> homing missiles -> new builds
```

The wave haul is the tension. It is separate from safe dollars. A death empties
the entire current-wave haul into collectible scatter; nothing from that wave is
banked for the defeated player. Anything not collected before expiry disappears.
Surviving players auto-bank at the wave-end break. Garages remain sanctuaries,
shops and loadout spaces, but no longer erase the risk in the middle of a wave.

## Release sequence

### 0.4.0-alpha - directional combat baseline

**Built, awaiting Studio acceptance.**

- Server-owned head-on and ambush classification.
- Battle bar, pooled scatter, shared shield and hit protection.
- Jump and Cycle touch/keyboard actions.
- Combat result and incoming-direction feedback.

Exit: `CombatConformance` passes and two Studio clients complete the directional
combat circuit without a replication or HUD failure.

### 0.5.0-alpha - waves become rounds

- Add explicit `PREP`, `WAVE`, `CLEAR`, `BANK` and `INTERMISSION` states.
- Reset wave haul to zero at wave start.
- On death, scatter the full haul and record the player as defeated for that wave.
- At clear, auto-bank every surviving player's haul once.
- Show `WAVE HAUL - AT RISK`, survivor status and a short banking celebration.
- Allow spending and loadout changes during intermission.
- Remove ordinary mid-wave banking from garage pads.

Exit: no double bank, no retained haul after death, disconnected players cannot
duplicate value, and a solo player can complete five waves and reach the boss.

### 0.6.0-alpha - ghosts with personalities

Every personality has a different silhouette accent, movement tell and sound.
Speed alone is not a personality.

| Ghost | Behaviour | Tell | Counterplay |
|---|---|---|---|
| **Chaser** | follows the nearest reachable player | steady cyan eye | route it into walls and corners |
| **Greedy** | hunts the largest wave haul | gold pulsing eye | let a low-haul teammate intercept |
| **Ambusher** | predicts the next junction and cuts across | magenta side fins | reverse or change ring early |
| **Bruiser** | slow, wide, resists one hit and blocks lanes | red armour band | flank it or use a bomb |
| **Skittish** | retreats from a facing mouth, returns from the side | flickering white eye | herd it toward a teammate |

Wave composition is authored, not random soup: introduce one behaviour at a
time, then combine them. The HUD announces the first appearance of a new type.

Exit: a child can name at least three types by what they do, and no ghost crosses
a wall, disappears from the wave count, or remains unreachable.

### 0.7.0-alpha - guardian as a readable boss

The guardian uses a server state machine and never changes mode without at least
1.5 seconds of light, animation and sound telegraphing.

| Mode | Action | Escape | Punish window |
|---|---|---|---|
| **Stalk** | slow pursuit, limited turn rate | keep moving around cover | none; learn spacing |
| **Pounce** | locks the player's predicted position, then leaps | leave the marked landing circle | maw weak point opens for 2.5 s |
| **Lane Dash** | marks a straight lane and charges without steering | cross behind cover or jump aside | collision with cover stuns it for 3 s |
| **Ghost Hurl** | stops and throws three ghost pods into open lanes | shoot pods or change lane | eye weak point opens while throwing |
| **Rage** | below 30% health, shorter recovery but same telegraphs | combine the learned counters | both weak points take full damage |

Contact cannot one-shot a full-health starter vehicle. Damage, current mode and
the weak point are visible. The guardian turns slowly enough that a Standard can
escape after making the correct read.

Exit: solo and three-player groups can win without exploiting geometry; every
hit can be explained by a visible telegraph; no unavoidable chained contact.

### 0.8.0-alpha - clarity and style pass

The target is a crisp arcade-toy look, not realism through blur.

- Remove depth-of-field and excessive bloom; use short restrained glow only on
  interactables, hazards and projectiles.
- Give floors, walls, cover and danger surfaces distinct values in greyscale.
- Add bevelled wall caps, hard contact shadows and thin emissive navigation edges.
- Reduce simultaneous neon colours in Level 1 and reserve gold for rewards.
- Use particles as event punctuation, not permanent fog.
- Add stronger material and silhouette detail to plinth items, ghosts, weapons
  and the guardian while preserving collision simplicity.
- Give combat sounds distance, variation and priority so important tells cut
  through the background track.

Level 1 palette: charcoal floor, brick-red walls, cyan navigation edges, warm
gold rewards, magenta combat warnings and clean white vehicle highlights.

Exit: maze boundaries remain readable at speed on the target iPad, screenshots
are sharp without blown-out neon, and each combat category is identifiable in
greyscale as well as colour.

### 0.9.0-alpha - the Level 2 threshold

- First guardian victory credits every participating player with the permanent
  Level 2 unlock.
- Victory disables a large visible electric grid for the current server group.
- The grid changes from red arcing energy to a quiet cyan frame and opens the
  route; it never becomes an invisible collision wall.
- A qualified player may bring a not-yet-unlocked friend through during that
  server session, but the guest earns permanent access only by participating in
  a guardian victory.
- Re-entry and respawn preserve the correct side of the gate.

Exit: forged client unlocks fail, party passage works, and permanent access
survives a full leave and rejoin.

### 1.0.0 - Level 2 vertical combat

Level 2 swaps the bomb pad for the homing missile. Weapons are level-scoped:
returning to Level 1 restores the Level 1 loadout, preventing missiles from
flattening its balance.

**Floating firing blocks**

- Reached by charge jump or jet pack, never by precision platforming.
- Wide enough to land safely, with a visible lip and a marked landing target.
- No required pellets, shops or progression live on them.
- Falling is harmless and returns the player to a readable route.
- A stationary player can lock missiles downward while teammates bait or sweep.

**New progression**

| Unlock | Identity | Gameplay |
|---|---|---|
| **Homing Missile** | long-range precision | slow visible projectile, long lock, walls stop it |
| **Flamethrower** | close crowd control | short held cone, limited fuel, lights nearby corridors |
| **Aero I-III** | longer airtime | +15%, +30%, +50% controlled airtime; no infinite hover |
| **Missile I-III** | specialist firepower | faster lock, second charge, tighter turning cap |
| **SkyJaw** | aerial sniper chassis | longer airtime and lock stability, lower armour |
| **GridCrusher** | ground support chassis | high armour and knockback resistance, slower climb |

**Level 2 palette**

Deep graphite floor, cool white wall faces, electric teal routes, acid-lime
landing targets, coral-red hazards, gold loot and violet enemy technology.
Lighting stays brighter and cleaner than the guardian chamber; the new identity
comes from material, edge colour and height, not darkness.

Exit: the Gunner, Sweeper and Bait roles are all useful; ground-only players can
still progress; the camera passes every block ascent, landing and fall; missiles
never pass through walls.

## Cross-cutting rules

1. The server owns wave state, haul, death, banking, boss state, unlocks, damage
   and purchases. Clients send intent and render replicated outcomes.
2. Every damaging boss move has a 1.5-second minimum audiovisual telegraph.
3. Nothing important is identified by colour alone.
4. New geometry must pass camera, collision and ghost-reachability checks before
   content is placed on it.
5. No feature is accepted from a solo Play session when it crosses a network
   boundary; use at least two Studio clients.
6. Each milestone is playable and shippable before the next begins.

## Immediate next build

Finish the `0.4.0-alpha` Studio circuit, then execute Build 1, Guardian and arena
readability, from the authoritative 1-6 tree. The round-state and wave-haul
slice follows after the contextual HUD in Build 3.
