# Chomp Arena Audio Sourcing

Status: free prototype library approved; music download and Roblox upload remain
owner actions because Roblox requires owner-controlled asset IDs.

The temporary Roblox built-in sounds have been removed. They proved the event
wiring but do not meet the game's quality or identity target.

## Approved Free Prototype Stack

Use this stack for the first complete audio pass. No purchase is required.

### Sound effects: Kenney Digital Audio and Impact Sounds

- https://kenney.nl/assets/digital-audio
- https://kenney.nl/assets/impact-sounds
- License: CC0; attribution is not required.
- Local source archive: `C:\Users\wills\Documents\Codex\ChompArena-Audio-Sources`

The archives are intentionally outside the public repository. Upload only the
curated files below to Roblox; do not upload or redistribute either full pack.

| Chomp event | Kenney starting file/family |
|---|---|
| Pellet streak | `pepSound1` through `pepSound5` |
| Power pellet | `powerUp6` or `powerUp11` |
| Purchase/bank | `threeTone1`, `twoTone1`, `powerUp12` |
| Cannon fire | `laser4` through `laser6` |
| Cannon hit | `zap1` plus a light generic impact |
| Shield on | `phaserUp3` |
| Shield break | `impactGlass_heavy_001` |
| Jet pack | `phaseJump3` |
| Bomb warning | `lowThreeTone` or `phaserUp` |
| Bomb impact | heavy punch or metal impact |
| Vehicle chomp | medium soft impact plus punch impact |
| Wave clear | `powerUp12` or a three-tone cue |

Final filenames must be selected by ear in Studio. Randomise pitch and choose
several variants for repeated impacts so the game does not sound mechanical.

### Background music: VOiD1 FREE EDM Music Pack

https://void1gaming.itch.io/free-edm-music-pack

This is the primary free music recommendation: 15 seamless EDM loops supplied
for commercial and non-commercial projects. Download both the 335 MB archive
and its separate license PDF using **Download Now**, then **No thanks, just take
me to the downloads**. Keep the license beside the archive outside Git.

Audition for a bright, syncopated loop with a clear bass groove and no ominous
breakdown. Reject tracks with harsh festival drops or dense lead synths; they
will fatigue players and mask repeated combat effects. Select one exploration
loop and one higher-energy guardian loop before uploading anything to Roblox.

### Optional garage/intermission music: Clement Panchout

https://clement-panchout.itch.io/yet-another-free-music-pack

Use `Sweet 70s` only if it complements the chosen EDM loop. It is licensed CC BY
4.0 and therefore requires this visible game credit:

`Music by Clement Panchout - www.clementpanchout.com`

### Optional broad effects source: Sonniss GDC Bundle

https://sonniss.com/gameaudiogdc/

Use Sonniss only to fill a gap that Kenney cannot cover, such as a distinctive
guardian layer. The bundle allows commercial use without attribution, but its
many contributors make it harder to maintain one coherent sound palette.

## Audio Identity

Chomp Arena should sound like a toy-sized electro-funk chase:

- clean synthetic transients rather than 8-bit bleeps;
- elastic movement, crunchy bites and rounded impacts rather than military guns;
- short, pitchable pickup notes that become a musical streak;
- warm bass, syncopated drums, clav or guitar-like funk rhythm and bright synths;
- no vocals, horror drones, realistic gunfire or long cinematic tails;
- important sounds remain readable under music on an iPad speaker.

## Recommended Purchase

### Sound effects: Advanced Game Sounds, Epic Stock Media

Product: https://epicstockmedia.com/product/advanced-game-sounds/

Listed contents include 3,119 royalty-free, game-ready effects covering arcade
sounds, coins, pickups, positive cues, wins, UI, sci-fi mechanisms and movement.
It includes 16-bit/44.1 kHz WAV files suitable for Roblox import. Listed price at
review time: US$79.

Why this pack: it can furnish one coherent palette across the whole game instead
of mixing unrelated free sounds. It contains enough variants to pitch-map pellet
streaks without replaying one sample hundreds of times.

License checkpoint: the product states a single-user, royalty-free license and
prohibits resale of the source samples. The purchasing account and receipt must
be retained with the project records. Confirm the correct number of audio users
before purchase.

### Music: Future Dreams, PulseFire Studios

Product: https://pulsefirestudios.itch.io/future-dreams

Five electro-synth tracks with full, loop and ending versions, plus 11 stingers.
The description specifically combines electro funk, disco, soul, rock and
future electronica. Files are 16-bit/44.1 kHz WAV, with tracks under Roblox's
duration ceiling. Listed price at review time: US$20.

Recommended audition order:

1. `Cruisin - Loop` for normal maze and garage play.
2. `Future Dreams - Loop` for later waves or the centre arena.
3. `Ice Challenge - Loop` for guardian combat.
4. Pack stingers for wave clear and match results, if they share the chosen
   track's key and production character.

License checkpoint: the product states it is for game and media projects. Keep
the downloaded license and purchase receipt. Obtain written clarification from
the author if the included archive does not contain an explicit commercial,
royalty-free grant covering uploaded game audio.

## Alternatives

### Lower-cost effects: Sci-Fi Games, Epic Stock Media

https://epicstockmedia.com/product/sci-fi-games/

Listed at US$20 during review, with 485 UI, laser, notification, cartoon and
cinematic effects. Good for weapons and UI, but it lacks the breadth of economy,
vehicle and reward sounds needed for a complete game. Use only as a prototype or
combine it with another casual-game library.

### More overtly retro effects: Classic Arcade, SmartSoundFX

https://www.asoundeffect.com/sound-library/classic-arcade/

458 royalty-free effects at 24-bit/48 kHz, listed at US$59. Strong coverage of
jumps, power-ups, cartoon impacts, UI and expressive arcade sounds. Choose this
only if auditions confirm the game should lean nostalgic; the current visual
direction is more modern electro than pixel arcade.

### Budget music: Electro Pop Music Pack, Tomality

https://tomality.itch.io/electro-pop-music-pack

Seven tracks and 22 loops in WAV, MP3 and OGG, listed on sale at US$6 during
review. The page grants commercial use and editing, prohibits standalone resale
and Content ID registration, and requests credit when possible. It is upbeat and
child-friendly, but less specifically funky than Future Dreams.

### Free evaluation source: Sonniss GDC Game Audio Bundle

https://gdc.sonniss.com/

Royalty-free commercial sound-effect samples with no attribution requirement.
Useful for auditioning and temporary internal prototypes, but the multi-vendor
bundle is not a coherent sonic identity and should not be the final default.

## Event-to-Sound Map

| Event | Target sound |
|---|---|
| Pellet | 5 short tonal pops in one scale, under 180 ms |
| Power Pellet | pellet family plus bass bloom and upward shimmer |
| Bank | fast coin cascade resolving to a safe, warm chord |
| Purchase | compact register hit plus positive confirmation |
| Cannon | synthetic pulse with body, no realistic firearm crack |
| Cannon hit | dry crunchy zap, clearly different from firing |
| Bomb arm | rising electronic tick; detonation is rounded and wide |
| Shield on | glassy energy wrap; shield save adds crack and rebound |
| Jet Pack | compressed electric thrust with short tail |
| Ghost nearby | quiet positional pulse, never a constant alarm |
| Ghost hit | soft theft suction followed by warning knock |
| Ghost defeat | burst, descending creature chirp, reward accent |
| Vehicle chomp | mouth crunch plus elastic body impact |
| Death | short break-apart hit; avoid frightening screams |
| Wave clear | 1-2 second musical sting matched to background key |
| Guardian | heavier electro pulse and gated warning layer |

## Music Direction

Music is one looping background system with intensity layers, not unrelated songs
played back to back:

- exploration: drums, bass and sparse rhythm at low volume;
- wave pressure: add synth rhythm or select the higher-energy loop;
- final two ghosts: do not restart music; add a subtle percussion layer;
- wave clear: duck music by 5-7 dB, play sting, restore over 0.8 seconds;
- guardian: crossfade over 1.5 seconds to its loop at a musically safe boundary;
- garage sanctuary: low-pass or reduce to 60% volume rather than stopping.

Default mix targets for first Studio tuning:

- music: 0.22-0.28 Roblox volume;
- ordinary gameplay effects: 0.45-0.65;
- warning and damage: 0.65-0.8;
- UI: 0.3-0.45;
- no more than four pellet sounds overlap;
- cannon uses a small voice pool rather than creating a new Sound every shot.

The HUD must provide separate Music and Effects mute controls. Settings persist
on the local device; the server never needs them.

## Roblox Delivery Constraints

Roblox accepts MP3, OGG, WAV and FLAC, under 20 MB and under seven minutes, with
sample rate no greater than 48 kHz. Imported audio must be owned or licensed,
pass moderation, and be granted permission to the Chomp Arena experience. The
upload should be made by the organisation or final experience owner, not a
temporary developer account.

Before implementation:

1. Purchase under the long-term rights holder's account.
2. Archive invoice, EULA and exact pack version outside the public repository.
3. Audition and select files; do not upload entire packs.
4. Trim silence, normalise consistently and export mono for positional SFX,
   stereo for music and major non-positional stings.
5. Upload selected files through Roblox and grant the experience permission.
6. Record Roblox asset IDs in `ChompConfig.Audio`; source WAV files and license
   documents remain outside the public repo.
7. Test on iPad speakers and headphones before accepting the mix.
