# Vehicle progression and play-screen scope

**Status:** design proposal for CHAIN-VEHICLE, CHAIN-UI and CHAIN-ECONOMY.
This document does not change their binding requirements or tuning values.

## 1. Player promise

A child should understand the next useful action in under two seconds:

- eat glowing things to raise the risky score and battle charge;
- return home to turn risky points into safe dollars;
- spend dollars on a stronger or more specialised vehicle;
- raise Power to challenge the next gate;
- watch the opponent's mouth, because sides and backs are vulnerable.

The interface should celebrate gains loudly and explain losses briefly. It
should not ask a seven-year-old to compare raw engineering numbers while driving.

## 2. Vehicle families

| Vehicle | Role | Personality | Current values | Proposed visible ports |
|---|---|---|---|---:|
| **Standard** | Friendly all-rounder | Bright bubble pod, easy to read | 100 bar, 100 Power, speed 24, turn 240 | 1 |
| **HeavyJaw** | Brawler | Armoured cheeks, heavy bite, planted stance | 175 bar, 250 Power, speed 23, turn 220 | 3 |
| **Ravener** | Ambush hunter | Longer mouth, teeth, lean pursuit shape | 275 bar, 450 Power, speed 26, turn 200 | 5 |
| **Apex** | End-game powerhouse | Crown profile, largest jaw and energy core | 400 bar, 700 Power, speed 28, turn 185 | 7 |

Port counts are a visual/progression proposal, not current gameplay state. A
port should be a large glowing socket that visibly changes when a module is
installed. Empty ports should look inviting, not broken.

## 3. Stats players should see

Use five named bars in the garage. Bars communicate relative strengths; exact
numbers can appear in a smaller detail view for older players.

| Display bar | Current source | Child-facing meaning |
|---|---|---|
| **Speed** | BaseSpeed plus Speed/Agility trade-offs | How fast it goes |
| **Turning** | BaseTurn plus upgrade trade-offs | How sharply it corners |
| **Toughness** | BarCapacity | How much battle charge it can hold |
| **Bite Power** | Power | How strong it is against players and gates |
| **Chomp Reach** | MouthArcDegrees / Consumption | How easily it collects and catches |

This is honest for v1. **Armour, Boost and Jump do not currently exist as
mechanics.** They should not appear as live numeric stats until CHAIN-ECONOMY
defines their effects, costs, counters and server authority.

## 4. Future module modes

Modes are memorable loadout identities, not separate currencies.

| Mode | Visual treatment | Intended strengths | Intended weakness |
|---|---|---|---|
| **Beast Mode** | Jaw armour, broad shoulders, red charge glow | Armour, bite force, short jump-slam | Heavy and slow to turn |
| **Goblin Mode** | Green scrap plates, crooked teeth, magnet pack | Agility, pickup radius, ambush rewards | Low protection in a head-on |
| **Rocket Mode** | Twin jet pack, cyan exhaust, narrow body | Boost speed and escape | Wide turns and fast charge drain |
| **Guardian Mode** | Shield plates and warning lights | Protect carried points, resist ghosts | Lower pellet income and speed |

A mode should change the silhouette and sound, not merely recolour the chassis.
The fitted modules should be visible on the physical ports.

## 5. What appears during play

Keep both bottom corners and the bottom edge clear for touch controls.

### Top left: immediate survival

- Large **BATTLE** bar with a mouth icon.
- Bar changes from cool yellow to hot orange when an attack is affordable.
- Tiny capacity label only when useful: `72 / 100`.
- On spending charge, remove chunks visibly rather than smoothly draining.

### Upper left, below the bar: risky points

- Pellet icon plus **CARRY 340**.
- Label it `AT RISK` after crossing a meaningful carry band.
- When hit: red shake, `-85`, then show the scattered pellets in the world.
- Near the garage: pulse `BANK IT!` with a home arrow.

### Top centre: next objective

Show one contextual objective, never a list:

- `HEAVYJAW  $350 / $500` with a short progress bar; or
- `NEXT GATE  POWER 220 / 300`; or
- `RETURN HOME TO BANK 340` when carrying a valuable haul.

The objective swaps based on the player's most useful next action. Chassis are
bought with **safe dollars**; gates open with **Power**. Do not describe either
as generic "points needed" because that hides the game's central distinction.

### Top right: safe progression

- Dollar icon plus **$350 SAFE**.
- Match timer and compact position/standings.
- Safe dollars never shake or turn red when the player is hit.

### Over the vehicle and in the world

- Pellet pickup: quick `+10` or `+25` that arcs toward CARRY.
- Banking: a satisfying count-up from CARRY into `$ SAFE`, with `BANKED!`.
- Purchase: socket fills, vehicle flashes, `POWER +40` or `HEAVYJAW UNLOCKED`.
- Ambush: `SIDE CHOMP!`, `REAR CHOMP!`, or `CLANG!` for head-on contact.
- Gate: show its Threat above the guardian; green when Power is enough, red
  when it is not, without relying on colour alone (open/locked icon as well).

## 6. Garage screen

The garage is the only place for detailed comparison.

- Large rotatable vehicle preview in the centre.
- Current vehicle and next vehicle shown side-by-side through five stat bars.
- Price button says `$500`, followed by `$150 TO GO` when unaffordable.
- Installed modules appear in physical port positions around the preview.
- Selecting a module previews both its gain and trade-off before purchase.
- One primary command: `BUY`, `EQUIP`, or `DRIVE` depending on state.
- No paragraph tutorials. Demonstrate changes through bars, animation and sound.

## 7. Reward rhythm

Use three celebration sizes so constant pickups remain satisfying without every
event becoming noisy:

1. **Micro:** pellet sparkle, soft tick, small `+10`.
2. **Medium:** banking burst, upgrade socket activation, Power bar step.
3. **Major:** new chassis reveal, gate eaten, new maze ring opened.

Loss feedback should be shorter than reward feedback. Show what was lost and
why, then return control immediately; nobody is eliminated from the round.

## 8. Decisions required before implementation

1. Are visible port counts purely cosmetic in v1, or do they limit equipped modules?
2. Do chassis purchases require only dollars, or both dollars and a Power threshold?
3. Which single next objective wins when a player can afford an upgrade but is
   also carrying a large risky haul?
4. Are Armour, Boost and Jump v2 module tracks, replacements for the current
   three tracks, or temporary match pickups?
5. Does Jump mean a tactical hop over hazards, a vertical deck transition, or
   a Beast-mode attack? Those are different mechanics and need different rules.

## 9. Level 1 gameplay shape

Level 1 is one continuous open arena with four readable zones:

1. **Four outer spawn quadrants:** three garages per quadrant support the
   twelve-player cap while still reading as four team-colour corners.
2. **Easy rim maze:** broad junctions, low-value pellets and enough cover for a
   new player to learn steering, eating, banking and mouth direction.
3. **Central bowl:** a visible inward slope ending in open combat space, richer
   pellets, stronger ghost pressure and fewer walls to protect a player's flank.
4. **Adjacent guardian chamber:** a deliberate side destination on the route to
   Level 2, visible from its approach but separated from ordinary maze traffic.

The resulting loop is `spawn -> eat safely -> risk the bowl -> bank -> buy ->
raise Power -> challenge guardian -> unlock Level 2`.

## 10. Guardian chamber interaction

The approach shows the guardian, `THREAT 250`, the player's own Power, and a
marked commitment boundary. A locked-mouth/skull symbol supports the red/green
state so readiness never depends on colour alone.

- **Below Threat:** crossing remains possible after a clear warning. The
  guardian performs an immediate one-hit chomp; 50% of carried points scatter
  and the player respawns at their own garage within four seconds.
- **At or above Threat:** the chamber fight begins. Frontal attacks clang;
  readable side and rear openings take damage. Defeat produces a major pellet
  burst and personally unlocks the Level 2 passage.
- **During the fight:** the HUD replaces its normal next objective with a small
  guardian health/readiness panel. It must not cover either touch zone.

Still to decide: whether multiple qualified players may cooperate, whether
other players can interfere, and whether Full Jaw bypasses the fight or merely
waives its Power threshold.
