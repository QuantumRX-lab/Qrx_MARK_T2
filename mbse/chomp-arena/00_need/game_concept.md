# Chomp Arena — Game Concept

**Working title only** — rename it once the family votes.

A combative multiplayer maze game built on Pac-Man's mechanics. Players drive a
Pac-Man-shaped vehicle through a walled maze, eat pellets for points, spend
points on upgrades, and fight each other by direction: **your mouth is your
weapon and your sides and back are your weak spots.**

This document is the design spine. Requirements (`02_requirements/`) are derived
from it and are the testable form of everything below.

---

## 1. The core loop

```
eat pellets ─→ points charge your BATTLE BAR and fill your CARRIED total
     │                                                    │
     │                                          drive home to the garage
     │                                                    │
     └──── spend BAR to attack ────┐                  BANK the carry
                                   │                      │
                          take carried points        buy upgrades
                          off other players               │
                                   │                      │
                                   └──────────────────────┘
```

Three currencies, and keeping them distinct is what gives the game its
tension:

| | What it is | Where it lives | At risk? |
|---|---|---|---|
| **Battle bar** | Combat charge, filled by eating | On the vehicle | Spent attacking, drained when hit |
| **Carried points** | Everything eaten since last bank | On the vehicle | **Yes — dropped when you're hit hard** |
| **Banked dollars** | Converted at your garage | Safe | No. Buys upgrades |

The single most important addition to the concept as described: **carried points
are not safe until you drive them home.** Without banking, points are just a
score counter and there is no reason to ever stop eating. With banking, every
minute of play is a greed decision — one more pellet run, or take the winnings
home before someone catches your back. That decision is the game.

---

## 2. Combat resolution

Every vehicle has a **facing**. Contact between two players is resolved by the
angle between them at the moment of impact, tested on the server.

### Head-on (mouth to mouth, within ±45°)
Both players are hurt — as specified. It's a contest of battle bars:

- Both lose **40% of their own bar**.
- The player with the **lower** bar additionally takes overflow damage equal to
  the difference between the two bars, taken out of carried points, which
  scatter as loose pellets at the impact point.
- Bars within 10% of each other: **clang** — both lose the 40%, neither loses
  points, both bounce backwards.

So charging blindly into someone is punished, a well-fed player wins the duel,
and winning still costs you — you cannot farm head-ons.

### Side or rear (attacker's mouth into victim's flank or back)
- The attacker **spends 30% of their bar** to bite.
- The victim loses that amount from **their** bar first; anything beyond what
  their bar can absorb comes out of **carried points** and scatters as loose
  pellets at the impact point.
- The victim gets **1.5 s of invulnerability** and a visible flash.

Attacking costs charge. That one rule does a lot of work: it stops a fast
player chain-rear-ending the lobby, it sends the attacker back to the pellets
to re-arm, and it makes each attack a decision rather than a reflex.

### Chomped (hit while the bar is empty)
The vehicle bursts, **50% of carried points scatter** at that spot, and the
player respawns at their own garage after 4 seconds with an empty bar.

**Nobody is ever eliminated.** With mixed ages in a lobby, sitting out a round
is the fastest way to lose a player for the evening.

### Why scatter instead of steal
The attacker does not receive the victim's points directly — the points hit the
floor as pellets anyone can eat, in the open, at the spot of the fight. The kill
is rewarding but not automatic, a third player can rob the winner, and it turns
every fight into a contested pile that pulls other players toward it. Direct
transfer would snowball the leader; scatter creates a second fight.

---

## 3. The battle bar

Fills as you eat: **1 point eaten = 1 charge**. Capacity is set by chassis tier,
not by the tuning upgrades — this is what "better vehicles have bigger battle
bars" means mechanically.

| Chassis | Bar capacity | Cost |
|---|---|---|
| Tier 1 — Standard | 100 | starting vehicle |
| Tier 2 — Heavy Jaw | 175 | $500 |
| Tier 3 — Ravener | 275 | $1,500 |
| Tier 4 — Apex | 400 | $3,500 |

A bigger bar is not free power. It takes longer to fill from empty, so a Tier 4
that has just respawned is *weaker* than a topped-up Tier 1 — an early-game
player can genuinely take a duel against a leader who just got chomped. That is
the comeback window, and it exists without any artificial rubber-banding.

---

## 4. Upgrades — three tracks, each with a real cost

Upgrades that only give benefits become a treadmill. Each track here trades
something away, so a build is a choice:

**Speed** — raises top speed. More pellets per minute, better at running down a
fleeing player and at escaping. *Cost:* higher speed widens your effective
turning circle, so you overshoot junctions and eat fewer pellets per pass in
tight mazes.

**Agility** — raises turn rate and unlocks a faster reverse. This is the
defensive track and the skill track: **turning to face an attacker converts a
side hit into a head-on**, which turns their free bite into a contest. *Cost:*
lower top speed ceiling — you win corners, you lose straights.

**Consumption** — widens the mouth arc and raises points per pellet, so you
charge faster and pick up scatter piles quickly. *Cost:* a wider mouth is a
bigger vulnerable profile — you are easier to hit from the side.

Levels I/II/III at **$150 / $400 / $900** per track.

---

## 5. Power pellets — the reversal, preserved

Four per maze, at symmetric positions, respawning every 45 s.

Eating one grants **8 seconds of Full Jaw**: every side of your vehicle counts
as mouth, so you cannot be flanked and every contact is an attack. You glow, a
siren plays, and every other player can see exactly who has it — the panic and
the rout is the point, and it is the classic Pac-Man reversal, kept intact.

Because they are visible, fixed and on a timer, power pellets become scheduled
fights. Everyone knows where and roughly when.

---

## 6. Ghosts — the maze fights back

Two to four AI ghosts patrol every maze. A ghost targets **the player carrying
the most unbanked points.**

That one targeting rule earns its place three times over:

1. It punishes hoarding, which is the exact behaviour banking is meant to
   discourage.
2. It hunts the leader automatically — catch-up without fake handicaps.
3. It gives the game something to do when only one player is online, which
   matters on a weeknight when only one kid is on. Solo, it is Pac-Man.

Ghost contact = chomped (scatter and respawn), with no attacker to benefit.
While Full Jaw is active, ghosts flee and are edible for **200 points**.

---

## 7. Mazes — fun, level-based, and provably fair

"Fair" in an arena means **symmetric**. The rule for every maze in the rotation:

- **Four-fold rotational symmetry.** Rotate the maze 90° and it is identical.
- Each garage sits at a symmetric position, equidistant from the centre.
- Power pellets at the four symmetric points.
- The **centre is the richest and most exposed** zone — highest pellet density,
  most sightlines, no cover. Reward for risk, in the one place everyone can
  reach equally.

Nobody can have a better spawn, because every spawn is the same spawn rotated.

Maze topology *is* combat design, because it decides which attacks are possible:

| Level | Shape | What it creates |
|---|---|---|
| 1 — **Classic Grid** | Even 4-way lattice, wide lanes | Teaches the basics. Escape is always available |
| 2 — **Long Halls** | Long straight corridors, few junctions | Chases and rear attacks. Speed builds shine |
| 3 — **The Spiral** | Concentric rings, few crossings | Commitment. You cannot easily turn back. Agility shines |
| 4 — **Crossroads** | Dense short blocks, junctions everywhere | Ambush. Constant flank threat, hardest map |
| 5 — **Gates** | Doors that open and close on a 20 s cycle | Route planning, traps, timed escapes |
| 6 — **Tunnels** | Wrap-around edges, Pac-Man style | Escape valves. Rewards knowing the map |

Rotate the maze every round so nobody wins on map memory alone.

**This is the job to hand to a child.** Maze building is placing and resizing
walls — genuinely within reach at seven — and it is the most gameplay-critical
asset in the project. Build one symmetric quadrant, then copy-rotate it three
times; the symmetry rule is enforced by the build method, and the fairness
requirement is satisfied by construction rather than by inspection.

---

## 8. Skill in the eating half: the combo

Without this, half the game is mindless. Each pellet eaten within **1.5 s** of
the previous one raises a multiplier: **x1 → x5**. It resets when you hit a
wall, stop, or take a hit.

Clean racing lines through the maze are now worth up to five times a sloppy
route, and a chase that forces someone into a wall costs them their combo before
it costs them any points. The chomp sound rises in pitch with the multiplier.

---

## 9. Match structure

- **5 rounds** of **6 minutes** on rotating mazes.
- **30 s garage intermission** between rounds — everyone spends, everyone sees
  the standings.
- Winner: **highest total banked across the match**.
- **Upgrades persist across the rounds of a match, then reset at match end.**

That last rule is the direct answer to "must be fair". Permanent power
progression across sessions means a player who has put in ten hours drives an
Apex against a first-timer's Standard, and the first-timer never touches a
pellet. Within a match everyone starts level, upgrades are earned in front of
each other, and the arc from Standard to Apex plays out in about half an hour.
Anything permanent should be **cosmetic** — colours, hats, mouth shapes, trails,
a name on a leaderboard.

---

## 10. Modes worth having

- **Free-for-all** — the default, 4-8 players.
- **Teams (2v2 / 3v3)** — shared bank, no friendly fire. The mode where a
  parent and a younger child can genuinely partner up.
- **Solo / co-op vs ghosts** — no PvP, ghost count doubled. The one-player-online
  fallback, and the gentlest introduction for a new player.

---

## 11. Technical stance (decisions to be logged, not open questions)

**The vehicle is not a physics vehicle.** Use the standard character controller
with a custom Pac-Man model and tuned speed/turn values. A real
VehicleSeat-and-wheels build gets flips, network-ownership jitter as ownership
passes between clients, and vehicles shoving each other through walls — and it
makes the facing angle, the thing the entire combat system reads, non-
deterministic. Speed and agility upgrades become two numbers on the server
instead of a suspension-tuning problem.

**The server decides every contact.** Facing angle, damage, scatter, banking and
pellet consumption are all resolved server-side from replicated positions. The
client predicts movement and plays effects; it never reports a hit. The rule
holds even in a private family game — the moment the place is Friends-visible,
a client that can assert "I hit them" is a client that can empty everyone's bank.

**Fixed post-hit invulnerability (1.5 s)** on every hit — otherwise one physical
collision registers across several frames and reads as four bites.

---

## 12. Open questions for the owner

1. **Player count target** — 4-8 in a lobby, or bigger?
2. **Who is this for?** If the 7-year-old is still a builder on this project,
   maze construction is her track and it is the most valuable one. If this is a
   solo project, the scope can go considerably further.
3. **Name.** "Chomp Arena" is a placeholder.
4. **Do ghosts ship in v1**, or is v1 pure PvP with ghosts in v2?
