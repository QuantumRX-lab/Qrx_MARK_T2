# Chomp Arena launch readiness and player start sequence

**Status:** accepted build baseline, 2026-08-27  
**Release target:** private Roblox playtest first; public release only after the
P0 gates below pass on the published experience.

## 1. Recommended release shape

Use **one Roblox place** for the first release. The launch bay and arena remain
in the same server, so a player can see the match, prepare safely, and deploy
without a loading screen or teleport failure. The bay is mechanically separate:
players in it are not valid ghost targets, cannot deal or receive combat damage,
do not contribute to wave scaling, and cannot bank arena rewards.

The four visual bay lanes are retained as part of the fantasy. Each lane has
three parking pads so a full 12-player server can prepare without stacking
vehicles. A player gets the next free pad; ownership of a particular corner has
no gameplay effect.

The first wave SHALL NOT start at server boot. It starts when the first prepared
player crosses a deployment gate. Players joining an active server prepare at
their own pace and enter the wave already in progress. They never hold up the
players already fighting.

## 2. Full player start sequence

### Phase A - arrival and profile load (target: 0-3 seconds)

1. Show the arena from the bay entrance while the server loads the profile.
2. Place the player in a non-driving preview vehicle on an assigned bay pad.
3. Display `LOADING GARAGE` and disable purchase, equip, and deploy actions.
4. On success, show banked dollars, owned chassis, equipped chassis, permanent
   upgrades, weapon licences, and the last valid loadout.
5. On a transient load failure, keep the player in a read-only practice bay.
   Do not create or save a blank profile over existing data. Offer retry.

### Phase B - choose the vehicle (target: 3-10 seconds returning player)

1. The equipped vehicle sits on a slowly rotating, well-lit turntable.
2. Left/right controls cycle the four chassis: Standard, HeavyJaw, Ravener,
   and Apex. Touch, controller, keyboard, and mouse get equivalent controls.
3. The panel shows five stable bars: Speed, Agility, Armour, Boost, and Jump.
4. An owned chassis says `EQUIP`; the equipped one says `EQUIPPED` and visibly
   changes the model. A locked chassis shows the dollar price and progress to
   it, for example `$820 / $1,500`.
5. Standard is always owned. No purchase is required to enter the arena.

### Phase C - fit weapons and equipment (target: 5-15 seconds)

1. Move from the turntable to a three-station equipment rack: **Weapon**,
   **Defence**, and **Mobility**. The first release should use three readable
   choices rather than exposing all five belt slots at once.
2. Equipping an item physically mounts it on the preview vehicle. The cannon
   performs a short tracking sweep; shield plates close once; the jet pack
   fires a harmless pulse. A loadout is understood from the vehicle, not only
   from text.
3. A new profile receives a starter Cannon with 10 shots and one Shield charge.
   This is enough to understand combat without shopping first.
4. Persistent progression unlocks chassis, upgrades, and weapon licences.
   Ammunition and consumable charges are match supplies bought with banked
   dollars. This preserves long-term progress without removing the restock loop.
5. Purchases require an explicit confirm action in the bay. Driving over a
   display can highlight it but does not spend currency.

### Phase D - systems check and deploy (target: under 45 seconds first visit)

1. The exit ramp shows `ENTER ARENA`; it is the primary action and is always
   visible from the equipment rack.
2. First-time players complete three actions on the pad: steer, fire, and boost
   or jump. Each action lights one large indicator. Returning players may drive
   straight to the ramp.
3. Crossing the gate locks the selected chassis and loadout, plays a short
   deployment sting, and starts a `3 - 2 - 1 - CHOMP!` camera transition.
4. Spawn on a clear arena entry point with three seconds of protection. The
   protection ends early if the player fires or bites another player.
5. Show the immediate objective for three seconds: wave number, ghosts left,
   and the next useful reward. Do not cover steering space on a tablet.

### Phase E - death and return

1. On defeat, carried points are resolved by the current risk/banking rules;
   banked dollars and persistent unlocks remain.
2. Return the player to their bay pad, not directly into combat.
3. Show the cause of defeat and one useful suggestion, then permit chassis and
   loadout changes. The current global wave continues.
4. Redeployment uses the same countdown and protection. A repeated death never
   creates a purchase requirement or an unskippable tutorial.

## 3. Server-controlled state model

Every player has exactly one authoritative server state:

| State | Combat target | Counts for wave scaling | May purchase | May deploy |
|---|---:|---:|---:|---:|
| `PROFILE_LOADING` | No | No | No | No |
| `BAY_VEHICLE` | No | No | Yes | No |
| `BAY_LOADOUT` | No | No | Yes | Yes |
| `DEPLOYING` | No | No | No | No |
| `ACTIVE` | Yes | Yes, from next wave | No | No |
| `DEFEATED` | No | No | No | No |

The server owns every transition. Client UI requests an action but cannot grant
an item, spend dollars, change ownership, mark itself active, or create spawn
protection. Joining during a wave does not increase that wave's spawn count;
the player is included when the next wave is calculated.

When no active players remain, pause wave advancement and remove or park active
ghosts. The next deployment resumes the existing wave; it does not provide an
unlimited wave-one farming reset.

## 4. Persistent profile boundary

The minimum versioned profile is:

```text
schemaVersion
bankedDollars
ownedChassis
equippedChassis
chassisUpgradeLevels
weaponLicences
lastLoadout
cosmetics
lifetimeStatistics
settings
```

Current-wave ghosts, carried points, temporary protection, ammunition already
spent, and bay assignment are server-session state. Save after confirmed
purchases and equips, periodically while active, when the player leaves, and
during server shutdown. All writes need retries, validation, and an update
operation that cannot replace a newer profile with an older server copy.

Studio must use a separately published test experience/data namespace. It must
never be given write access to the production profile store.

## 5. Wave and group rules

- A fresh server waits in `WAITING FOR DEPLOYMENT` until one player enters.
- The first deployment starts wave 1 after the countdown.
- Friends may deploy together, but no ready vote is required. One child who is
  browsing vehicles cannot trap the rest of the server in the bay.
- Bay and defeated players are absent from ghost targeting and reward splits.
- Mid-wave arrivals see the current wave and estimated difficulty before they
  deploy. Their presence affects the next wave only.
- Between waves, provide a short arena restock window and a clear return-to-bay
  route. Returning is optional; remaining players should not be teleported.
- The guardian gate remains locked until its point requirement is met. Entering
  underpowered must give an unmistakable warning before the lethal boundary.

## 6. Economy and monetisation decisions before release

The current Robux labels are display-only. Before any public build, either hide
them completely or implement real Roblox products with server-side receipt
handling and persistence. A display that looks purchasable but cannot complete
is not acceptable.

For the first private playtest, use only earned dollars. Balance so a solo
player can buy a meaningful restock every 1-2 waves and reach their first
permanent upgrade in the first 10-15 minutes. Group rewards must not divide so
sharply that playing with friends slows progression.

Recommended later monetisation boundary: permanent cosmetic chassis finishes
or convenience, never the combat power needed to survive the next wave. Every
purchase must show one item, one price, and one explicit confirmation.

## 7. Launch gates

### P0 - required for a private external playtest

- Implement `PlayerSessionService` (the state model and deployment authority).
- Build the four-lane launch bay, selection turntable, equipment rack, and gate.
- Implement versioned profile persistence and the read-failure safe mode.
- Gate wave startup; exclude bay players from targets, damage, and scaling.
- Implement clear mid-wave joining, death return, and spawn protection.
- Provide visible starter equipment and confirm that cannon tracking replicates.
- Hide all display-only Robux prices.
- Add an actual guardian encounter and a result for defeating it; the current
  repository contains chamber geometry and tuning but no guardian service.
- Define a playable end condition or level transition after the guardian.
- Verify every owned audio asset is moderated, permitted for this experience,
  audible on device, and mixed below dialogue and combat cues.
- Pass two-player and 12-player Studio server tests plus a 30-minute soak test.
- Pass keyboard/mouse, controller, and tablet selection/deployment tests.
- Publish from the owner's experience as Private and test the published build,
  including persistence, rejoin, shutdown save, and a forced load failure.

### P0 - additionally required before public access

- Complete experience metadata, icon, thumbnails, description, and the current
  Roblox maturity/compliance questionnaire accurately.
- Decide and configure the supported audience and server access policy.
- Review all text, audio, images, and models after moderation in the live place.
- Add basic analytics for join, profile load result, bay duration, deploy,
  defeat, wave completion, purchase, and guardian attempt/completion.
- Establish a rollback procedure: retain the last known-good published place
  version and keep profile migrations backward-readable.
- Run an exploit pass against purchase, fire, equip, deploy, reward, and save
  requests. No client claim may directly award value.

### Roblox release path (current as of 2026-08-27)

1. **Personal/private:** publish the owner's experience privately and test with
   accounts that have edit permission. This is the engineering test channel.
2. **Trusted friends and verified 16+:** confirm the owner has completed the
   required age check and that the account is in good standing, then use this
   audience for real-device and real-network validation.
3. **All ages:** because Chomp Arena is intended for children, the owner must
   satisfy Roblox's current all-ages eligibility, including identity
   verification, two-factor authentication, the applicable subscription or
   refundable publishing-fee route, and Roblox's evaluation process. The
   experience must complete the maturity and compliance questionnaire; target
   a Minimal or Mild label if younger Roblox Kids accounts are in scope.
4. Check the live eligibility status in Account Settings and the experience's
   Audience Reach panel immediately before each release. Platform requirements
   can change, so this document is not a substitute for that live status.

### P1 - the first post-playtest iteration

- Tune wave rewards and costs from completion and abandonment data.
- Add party deployment celebrations and clearer friend locations.
- Add loadout presets and cosmetic bay personalisation.
- Add a first-session guided voice/text sequence only where observed players
  fail; avoid turning the bay into a long tutorial.

## 8. Acceptance targets

- Returning player reaches active control in **12 seconds or less** without
  opening a menu.
- A first-time player can deploy in **45 seconds or less** without reading a
  paragraph or making a purchase.
- 100% of equipped chassis and weapons are visibly different on the turntable
  and on the replicated arena vehicle.
- A player can state their chassis, weapon, dollars, wave, and next unlock from
  the screen at a glance.
- No ghost targets, damages, or scales from a player before `ACTIVE`.
- Rejoining after a confirmed purchase restores it; a failed profile load never
  overwrites it.
- All primary bay actions work at tablet size without overlap and with touch
  targets of at least 44 pixels.

## 9. Current repository gap summary

The build is not yet at this launch baseline. `GhostService` starts wave 1 at
server boot, `Level1Map` supplies one shared spawn, garage ownership and upgrades
are player attributes held for the session, and `ItemService` holds its belt in
server memory. The existing garages are useful arena shops but are not the safe,
stateful arrival bay defined here. Those are the first implementation changes;
visual polish comes after the lifecycle is reliable.
