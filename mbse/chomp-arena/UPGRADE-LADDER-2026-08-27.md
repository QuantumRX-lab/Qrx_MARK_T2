# Vehicle upgrade ladder and personal garage scope

**Status:** proposed progression baseline, 2026-08-27

## Core structure

Separate three concepts that the current shop mixes together:

1. **Chassis ownership** is permanent: Standard, HeavyJaw, Ravener, Apex.
2. **Upgrade licences** are permanent: buying Cannon II unlocks it forever.
3. **Match supplies** are expendable: cannon ammunition, bomb charges, shields.

Every chassis has one dedicated roof-weapon hardpoint. This does not consume a
module port. Its cannon visibly changes from one to two to three smaller barrels
as the Cannon licence improves.

| Chassis | Module ports | Intended identity |
|---|---:|---|
| Standard | 1 | nimble specialist; one clear build choice |
| HeavyJaw | 2 | durable early-wave fighter |
| Ravener | 3 | aggressive flexible hunter |
| Apex | 4 | late-game multi-system vehicle |

A player may own every module but only equip as many as their chassis has
ports. Do not permit two copies of the same module. Swapping owned modules in
the garage is free, so experimentation is encouraged.

## Recommended three-rung ladders

Percentages apply to the chassis base and do not compound level over level.

### Engine: Speed

| Rung | Name | Effect | Visible change |
|---|---|---|---|
| I | Tuned Drive | +5% top speed | brighter rear motor coil |
| II | Twin Drive | +10% speed, +5% acceleration | twin side exhausts |
| III | Overdrive | +15% speed, +10% acceleration, boost trail | large rear turbine |

Engine II and III reduce turn rate by 4% and 8%. Speed creates a different
driving line rather than erasing the Agility choice.

### Handling: Agility

| Rung | Name | Effect | Visible change |
|---|---|---|---|
| I | Grip Fins | +8% turn rate | small steering fins |
| II | Vector Hubs | +16% turn rate, faster reverse flip | glowing wheel hubs |
| III | Snap Vector | +24% turn rate, 20% shorter steering ramp | active front vanes |

Handling III reduces top speed by 5%. It is the maze and ambush build; Engine
is the open-centre and escape build.

### Armour

| Rung | Name | Effect | Visible change |
|---|---|---|---|
| I | Side Plates | 115 maximum health | side armour plates |
| II | Jaw Guard | 135 health, 10% less flank bite loss | jaw and rear guards |
| III | Fortress Shell | 160 health, 20% less ghost damage | full shell and damage glow |

Armour II and III reduce acceleration by 4% and 8%. Armour must be obvious on
the body and health bar; silently changing health is not enough.

### Cannon: roof weapon

| Rung | Name | Effect | Visible change |
|---|---|---|---|
| I | Chomp Cannon | 1 barrel, 10 rounds, current damage | one compact turret |
| II | Twin Chomp | 2 alternating barrels, 18 rounds, +15% fire rate | twin barrels |
| III | Tri-Chomp | 3 alternating barrels, 30 rounds, +30% fire rate, +25% elite damage | three barrels |

The barrels should be about 70% of the current width and 80% of its length.
Multiple barrels alternate shots; they do not multiply projectiles per ammo
unit. That makes the upgrade stronger without tripling damage or network load.

Ghosts currently have one health, so damage upgrades have no meaning yet. Add
2-health ghosts from wave 4 and 3-health brutes from wave 7 before enabling the
Cannon III elite-damage bonus.

### Ordnance: bombs

| Rung | Name | Effect | Visible change |
|---|---|---|---|
| I | Chomp Mine | 1 charge, current blast | one finned bomb |
| II | Heavy Mine | 2 charges, +15% radius, 2 elite damage | paired bomb rack |
| III | Nova Mine | 2 charges, +30% radius, 3 elite damage, stronger knockback | striped heavy rack |

Bombs remain placed traps: tap once to drop, tap again to detonate. Nova Mine
needs a loud arming cue and a danger ring visible to every player.

### Jump

| Rung | Name | Effect | Visible change |
|---|---|---|---|
| I | Lift Jets | +8% impulse, +0.15 s air control | two lift nozzles |
| II | Air Step | +15% impulse, +0.35 s control, +10% forward travel | four nozzles and fins |
| III | Sky Chomp | +20% impulse, +0.60 s control, +20% travel | articulated jet pack |

Longer air time must not allow leaving the sealed arena. Test every rung at the
outer wall and guardian chamber.

### Boost

| Rung | Name | Effect | Visible change |
|---|---|---|---|
| I | Quick Charge | battle charge fills 10% faster | one capacitor |
| II | Power Bank | fills 20% faster, holds 15% more | twin capacitors |
| III | Surge Cell | fills 30% faster, holds 25% more, boost costs 10% less | animated core |

This replaces the current Consumption track's mostly invisible pellet bonus.
Mouth-size collection can remain a chassis trait or become a later Collector
module, but should not displace one of these six readable ladders.

## Prices and pacing

The current economy pays about $1,000 for clearing solo wave 1 before pellets,
so the existing $150/$400/$900 ladder is awarded almost immediately.

| Rung | Suggested price | Intended moment |
|---|---:|---|
| I | $800 | one choice after wave 1 |
| II | $3,500 | specialist build around waves 3-4 |
| III | $9,500 | aspirational build around waves 6-7 |

| Match supply | Suggested price |
|---|---:|
| Cannon refill | $120 / $180 / $260 by rung |
| Bomb refill | $180 / $300 / $480 by rung |
| Shield charge | $160 |

Instrument dollars earned, purchase wave, deaths before purchase, and unspent
balance. Tune toward one meaningful choice per wave, not one mandatory build.

## Personal garage beyond the outer rim

Create a protected **service ring** outside the arena wall. Four garage courts
sit around the arena, each with three pads for the 12-player limit. A short
deployment tunnel is the only controlled opening through the boundary.

Each personal pad contains:

- a rotating vehicle turntable showing the equipped chassis;
- a roof-weapon station showing Cannon I, II, and III as real models;
- six upgrade towers with owned rungs illuminated;
- a module rack linked visibly to the vehicle's occupied ports;
- a low restock counter for ammo, bombs, and shields;
- a deployment exit visible from every purchase position.

Displays are personalised client-side, while the server validates every
purchase and equip request. The arena remains sealed; the service ring is a
second protected space. Ghosts, projectiles, pellets, and combat rewards never
cross into it.

## Plinth behaviour

Reserve tall plinths for permanent, desirable unlocks: chassis and upgrades.
Move expendable items to the compact restock counter.

Each upgrade tower shows all three rungs vertically. Owned rungs are lit; the
next rung rotates with its price and exact improvement; later rungs remain
visible silhouettes. The equipped rung sends a light path to its vehicle port.
Purchasing mounts the new component immediately and plays its mechanism.

## Required implementation changes

1. Implement persistent profiles before permanent upgrade sales.
2. Replace the three global upgrade attributes with versioned licence levels
   and an equipped-module list.
3. Extend `Progression.effectiveStats` for Speed, Agility, Armour, Boost, Jump,
   Cannon, and Ordnance.
4. Add server-owned health, damage reduction, magazine, fire rate, bomb damage,
   charge capacity, and air-control values.
5. Split permanent weapon rungs from expendable ammunition and charges.
6. Build compact single-, twin-, and triple-barrel cannon variants.
7. Add elite ghost health tiers so weapon damage has a purpose.
8. Build the outer service ring, four courts, twelve pads, and tunnels.
9. Replace generic cubes with the actual modules mounted on the vehicle.
10. Update the HUD with before/after stats and `used / available` ports.
11. Test forged rung, slot, price, ammo, damage, and equip requests plus rejoin.
12. Re-run vehicle conformance and tablet-camera tests with a fully fitted Apex.

## Build order

1. Profile schema and migration from the existing upgrade attributes.
2. Pure stat calculations and automated balance tests.
3. Compact cannon variants and visible module mounting.
4. Server purchase, equip, ammunition, and damage contracts.
5. Exterior service ring and upgrade towers.
6. HUD comparison, port, ammo, and ownership feedback.
7. Elite enemies and wave/economy tuning.
8. Multiplayer, persistence, exploit, performance, and readability tests.

Do not build the exterior showroom before persistence and upgrade contracts. A
beautiful garage attached to session-only ownership would sell progress that
disappears on rejoin, which is worse than having no showroom yet.
