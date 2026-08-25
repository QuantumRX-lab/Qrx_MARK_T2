# Chomp Arena — Game Concept

**Working title only** — rename it once the family votes.

A combative multiplayer maze game built on Pac-Man's mechanics. Players drive a
Pac-Man-shaped vehicle through a walled maze, eat pellets for points, spend
points on upgrades, and fight each other by direction: **your mouth is your
weapon, your sides and back are your weak spots.** Ghosts roam and steal points.
The rich parts of the maze are locked behind **super ghosts** you must outgrow
before they let you through.

This document is the design spine. Requirements (`02_requirements/`) are the
testable form of everything below.

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
                                   │                 POWER goes up
                                   │                      │
                                   │            a super ghost lets you
                                   │            into a richer ring
                                   └──────────────────────┘
```

Four numbers, and keeping them distinct is what gives the game its tension:

| | What it is | Where it lives | At risk? |
|---|---|---|---|
| **Battle bar** | Combat charge, filled by eating | On the vehicle | Spent attacking, drained when hit |
| **Carried points** | Everything eaten since your last bank | On the vehicle | **Yes — dropped when you're hit hard, stolen by ghosts** |
| **Banked dollars** | Converted at your garage | Safe | No. Buys upgrades |
| **Power** | Your build score: chassis + upgrades | On your profile | No. It's what the gate ghosts measure |

The most important addition to the concept as described: **carried points are not
safe until you drive them home.** Without banking, points are a score counter and
there's never a reason to stop eating. With it, every minute is a greed decision
— one more run through the middle, or take the winnings home before something
finds your back.

And because Power only rises when you *spend* banked dollars, the gates at the
heart of the maze are driven by the banking loop. You cannot get deeper by
hoarding. You get deeper by making it home alive and spending.

---

## 2. Combat resolution

Every vehicle has a **facing**. Contact between two players is resolved by the
angle between them at the moment of impact, tested on the server.

### Head-on (mouth to mouth, within ±45°)
Both players are hurt, as specified — a contest of battle bars:

- Both lose **40% of their own bar**.
- The **lower** bar additionally takes overflow damage equal to the difference
  between the two bars, taken from carried points, which scatter as loose
  pellets at the impact point.
- Bars within 10% of each other: **clang** — both lose the 40%, neither loses
  points, both bounce backwards.

Charging blindly is punished, a well-fed player wins the duel, and winning still
costs you — you cannot farm head-ons.

### Side or rear (attacker's mouth into victim's flank or back)
- The attacker **spends 30% of their bar** to bite.
- The victim loses that amount from **their** bar first; anything beyond what
  their bar absorbs comes out of **carried points** and scatters at the impact
  point.
- The victim gets **1.5 s of invulnerability** and a visible flash.

Attacking costs charge. That one rule stops a fast player chain-rear-ending the
lobby, sends the attacker back to the pellets to re-arm, and makes each bite a
decision rather than a reflex.

### Chomped (hit while the bar is empty)
The vehicle bursts, **50% of carried points scatter**, and the player respawns at
their own garage after 4 seconds with an empty bar. **Nobody is ever
eliminated** — with mixed ages, sitting out a round loses you a player for the
evening.

### Points scatter, they never transfer
Lost points hit the floor as loose pellets anyone can eat. The kill is rewarding
but not automatic, a third player can rob the winner, and every fight becomes a
contested pile that drags other players in. Direct stealing would snowball
whoever is already ahead.

### No pickings from small fry
Chomping a player **more than 300 Power below you** scatters nothing. There is
no economic reason for a maxed-out player to sit outside a beginner's garage,
and no rule anyone has to be told — the reward simply isn't there.

---

## 3. The battle bar

Fills as you eat: **1 point eaten = 1 charge**. Capacity comes from the chassis,
not from the tuning upgrades — this is what "better vehicles have bigger battle
bars" means mechanically.

| Chassis | Bar capacity | Power | Cost |
|---|---|---|---|
| Tier 1 — Standard | 100 | 100 | starting vehicle |
| Tier 2 — Heavy Jaw | 175 | 250 | $500 |
| Tier 3 — Ravener | 275 | 450 | $1,500 |
| Tier 4 — Apex | 400 | 700 | $3,500 |

A bigger bar is not free power: it takes longer to fill from empty, so **a Tier 4
that just respawned is weaker than a topped-up Tier 1.** That's the comeback
window, and it exists without artificial rubber-banding.

---

## 4. Upgrades — three tracks, each with a real cost

Upgrades that only give benefits are a treadmill. Each track trades something,
so a build is a choice:

**Speed** — raises top speed. More pellets per minute, better at running down a
fleeing player and at escaping. *Cost:* a wider effective turning circle — you
overshoot junctions.

**Agility** — raises turn rate and unlocks a fast reverse. The defensive track
and the skill track: **turning to face an attacker converts a side hit into a
head-on**, turning their free bite into a contest. *Cost:* a lower top speed
ceiling — you win corners, you lose straights.

**Consumption** — widens the mouth arc and raises points per pellet, so you
charge faster and hoover up scatter piles. *Cost:* a wider mouth is a bigger
vulnerable profile — easier to flank.

Levels I/II/III at **$150 / $400 / $900** per track. Each level is **+40 Power**.

Maximum Power is therefore 700 (Apex) + 360 (nine upgrade levels) = **1,060**.

---

## 5. Ghosts

Four ghosts roam every maze. They are **spooky, not cute** — the fear is the
point, and it is the oldest working idea in the genre.

Ghost contact costs you **25% of your carried points**, which scatter on the
floor where you were hit, plus a knockback and 1.5 s of invulnerability. They do
not touch your bar and they do not destroy you: they rob you and drift away. A
ghost hit hurts most when you're fat and far from home, which is exactly when
you should have banked already.

**They are learnable, not random.** Each of the four has one targeting rule, and
a player who understands them can work the maze around them — the original
game's real insight, and the reason it is still fair after forty years:

| Ghost | Behaviour |
|---|---|
| **The Chaser** | Drives straight at your current position |
| **The Ambusher** | Aims four tiles ahead of your facing — cuts you off at the next junction |
| **The Flanker** | Approaches on a line that avoids your mouth arc. Attacks your blind side |
| **The Greedy One** | Ignores everyone except the player carrying the most unbanked points |

The Greedy One is the important one. It punishes hoarding, automatically hunts
whoever is winning — catch-up with no fake handicap — and it means the game still
works when one kid is online alone. Solo, this is Pac-Man.

During **Full Jaw** (see §7) all four flee and are edible for **200 points** each.

---

## 6. Super ghosts — the gate guardians

**The rings of the maze are locked, and a super ghost sits in every gate.**

A super ghost is bigger, slower, and never leaves its gate. It is a door with a
face. Above it floats one number: its **Threat**. On your HUD sits one number:
your **Power**. If your Power is below its Threat, that gate is not for you yet.

| Ring | Gate Threat | What's inside |
|---|---|---|
| **1 — Outer** | none | Garages, thin pellets, safe. Everyone starts here |
| **2 — Middle** | 250 | Denser pellets, two ghosts, first power pellets |
| **3 — Inner** | 500 | Rich pellets, all four ghosts, the best fights |
| **4 — The Vault** | 800 | Jackpot pellets, no walls to hide behind, total exposure |

**Touching a gate while under-powered:** the super ghost takes **50% of your
carried points** and shoves you back out. Painful, instant, and impossible to
misread — you weren't big enough.

**Touching a gate at or above its Threat:** you eat it. Huge points, and **the
gate stands open for 60 seconds for everybody** before the guardian reforms.

That last rule is deliberate and it is the best moment in the design. The
strongest player is the *key*. When they finally crack Ring 3, a door opens and
the whole lobby floods in behind them — a scheduled, visible, shouted-across-the-
room event, and the leader cannot quietly farm the rich zone alone because
breaking in announces it to everyone.

### Why gating by rings instead of by levels

The obvious reading of "levels guarded by super ghosts" is that each player
unlocks their own next level. **That would kill the game** — players separated
into different mazes cannot fight each other, and this is a combat game. One
continuous maze with gated rings keeps the whole lobby in one place and gets
something better besides:

**The gates sort the lobby by strength.** A beginner in Ring 1 cannot be hunted
by a maxed-out player who lives in Ring 3, because Ring 3 is where the rich
pellets are and nobody strong has any reason to come back out (and §2's small-fry
rule removes the last one). The 7-year-old farms in safety; the adults fight each
other over the Vault. That is age-fair matchmaking falling out of the map layout,
with no matchmaking code and no rule anyone has to enforce.

---

## 7. Power pellets — the reversal, preserved

Four per ring from Ring 2 inward, at symmetric positions, respawning every 45 s.

Eating one grants **8 seconds of Full Jaw**: every side of your vehicle counts as
mouth, so you cannot be flanked, every contact is an attack, and ghosts flee. You
glow, a siren plays, and everyone can see exactly who has it — the rout is the
point.

**And Full Jaw walks you through any one gate, whatever your Power.** A
weak player who wins the fight over a power pellet gets eight seconds in the deep
water: enormous pellets, and every shark in the map now knows they're in there
carrying. It's the best gamble in the game, and it hands the underdog the map's
richest ground for exactly as long as it takes to get out again.

---

## 8. Mazes — fun, level-based, and fair by construction

"Fair" in an arena means **symmetric**. The rule for every maze:

- **Four-fold rotational symmetry.** Rotate 90° and it is identical.
- Concentric rings, garages on the outer ring, **four gates per ring** at
  symmetric points, the Vault at the centre.
- The centre is the richest and the most exposed. Reward for risk, in the one
  place everyone can reach equally.

Nobody can have a better spawn, because every spawn is the same spawn rotated.
You get this free by building one quadrant and copy-rotating it three times.

Maze topology *is* combat design, because it decides which attacks are possible:

| Map | Shape | What it creates |
|---|---|---|
| 1 — **Classic Grid** | Even lattice, wide lanes | Teaches the basics. Escape always available |
| 2 — **Long Halls** | Long corridors, few junctions | Chases and rear attacks. Speed builds shine |
| 3 — **The Spiral** | Concentric coils, few crossings | Commitment — you can't turn back. Agility shines |
| 4 — **Crossroads** | Dense short blocks, junctions everywhere | Ambush. Constant flank threat. Hardest map |
| 5 — **Gates** | Doors on a 20 s cycle, on top of the ring gates | Route planning, traps, timed escapes |
| 6 — **Tunnels** | Wrap-around edges, Pac-Man style | Escape valves. Rewards knowing the map |

Rotate the map every round so nobody wins on memory alone.

**This is the job to hand to a child.** Maze building is placing and resizing
walls — genuinely within reach at seven — and it is the most gameplay-critical
asset in the project. The symmetry rule is enforced by the build method, not by
anyone's judgement.

---

## 9. Skill in the eating half: the combo

Each pellet eaten within **1.5 s** of the last raises a multiplier: **x1 → x5**.
It resets when you hit a wall, stop, or take a hit.

Clean racing lines are now worth five times a sloppy route, and a chase that
forces someone into a wall costs them their combo before it costs them a point.
The chomp sound rises in pitch with the multiplier.

---

## 10. Match structure

- **5 rounds** of **6 minutes** on rotating maps.
- **30 s garage intermission** between rounds — everyone spends, everyone sees
  the standings.
- Winner: **highest total banked across the match**.
- **Upgrades and Power persist across the rounds of a match, then reset at match
  end.**

That last rule is the answer to "keep it fair". Permanent progression means a
ten-hour veteran drives an Apex against a first-timer's Standard and the
first-timer never touches a pellet. Within a match everyone starts level, the
climb from Standard to Vault-capable plays out in about half an hour, and the
gates give that half hour a shape: Ring 2 by round two, Ring 3 by round three,
someone cracks the Vault in the last ten minutes.

Anything permanent should be **cosmetic** — colours, hats, mouth shapes, trails,
a name on a leaderboard.

*(If a persistent career is wanted later, it belongs in a separate mode played
against ghosts, not in the PvP arena.)*

---

## 11. Modes worth having

- **Free-for-all** — the default, 4-8 players.
- **Teams (2v2 / 3v3)** — shared bank, shared Power for gates, no friendly fire.
  The mode where a parent and a younger child genuinely partner up.
- **Solo / co-op vs ghosts** — no PvP, ghosts doubled, gates still gated. The
  one-player-online fallback and the gentlest way in for a new player.

---

## 12. Technical stance (decisions to log, not open questions)

**The vehicle is not a physics vehicle.** Use the standard character controller
with a custom Pac-Man model and tuned speed/turn values. A real
VehicleSeat-and-wheels build brings flips, network-ownership jitter as ownership
passes between clients, and vehicles shoving each other through walls — and it
makes the facing angle, the thing the entire combat system reads,
non-deterministic. Speed and agility upgrades become two numbers on the server
instead of a suspension-tuning problem.

**The server decides every contact.** Facing angle, damage, scatter, banking,
pellet consumption, Power, and every gate check are resolved server-side from
replicated positions. The client predicts movement and plays effects; it never
reports a hit and never asserts its own Power. The rule holds even in a private
family game — the moment the place is Friends-visible, a client that can claim
"my Power is 900" is a client that lives in the Vault.

**Fixed post-hit invulnerability (1.5 s)** on every hit, from players and ghosts
alike — otherwise one physical collision registers across several frames and
reads as four bites.

**Ghost pathing is grid-based.** Mazes are built on a grid, ghosts move
junction-to-junction on it and pick a direction at each one by their rule. This
is how the original worked, it costs almost nothing, and it makes ghosts
learnable rather than twitchy.

---

## 13. Open questions for the owner

1. **Player count target** — 4-8 in a lobby, or bigger? It sets maze scale.
2. ~~**Who is this for?**~~ **Answered:** the owner builds the mechanics; the
   children build mazes, vehicles and ghosts on top of them without scripting.
   See `03_architecture/authoring_kit.md` — that decision reshapes v1, which is
   now the authoring kit plus one ring, not the full game.
3. **Name.** "Chomp Arena" is a placeholder.
4. **Match length** — 5 x 6 min is ~35 minutes. Right for a school night?
5. **Do all four ring gates ship in v1**, or does v1 ship Rings 1-2 with one
   super ghost and prove the mechanic first?
