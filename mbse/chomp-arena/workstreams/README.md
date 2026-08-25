# Workstreams — how several agents work this tree without colliding

Every requirement in `02_requirements/requirements.yaml` carries a `chain`
field naming its decomposition chain. Each chain has a folder here, and each
folder has an append-only `log.yaml`. That is the whole coordination mechanism.

| Chain | Scope | Owner |
|---|---|---|
| `CHAIN-VEHICLE` | Chassis models, movement stats, the camera | **Codex** (external) |
| `CHAIN-COMBAT` | Impact classification, damage, scatter, falls | unassigned |
| `CHAIN-ECONOMY` | Pellets, bar, carry, banking, upgrades, Power | unassigned |
| `CHAIN-GHOSTS` | Pathing, personalities, robbery, ghost scaling | unassigned |
| `CHAIN-GATES` | Rings, guardians, Threat vs Power | unassigned |
| `CHAIN-MAZE` | Decks, symmetry, garages, prefab pieces | unassigned |
| `CHAIN-MATCH` | Rounds, standings, reset, teams | unassigned |
| `CHAIN-UI` | HUD, touch controls, readability, markers | unassigned |
| `CHAIN-PLATFORM` | Server authority, performance, safety, config | unassigned |
| `CHAIN-KIT` | v3 authoring kit | unassigned |

## The protocol

**1. Claim before you work.** Append an entry with `action: CLAIMED` naming the
requirement IDs you are taking. If someone else holds an open claim on the same
IDs, do not start — resolve it in the log first.

**2. Work only inside your chain's requirements.** If the work needs a change
in another chain, do not make it. Append an entry with `action: BLOCKED` naming
the other chain and what you need, and stop. Cross-chain edits made quietly are
the failure mode this whole structure exists to prevent.

**3. Log what you did, including what you decided.** An entry that says
"implemented CHOMP-SYS-011" is nearly useless. An entry that says what you
chose where the requirement was ambiguous, and what you assumed, is what the
next agent actually needs.

**4. A requirement change is a tree change, not a log entry.** If the work
proves a requirement wrong, say so in the log **and** amend
`02_requirements/requirements.yaml`, and add a decision to
`06_decisions/decision_log.yaml` explaining why. The log records activity; the
tree records truth.

**5. Run `python validate.py` before you finish.** It checks your log against
the requirements tree — that every ID you cite exists, that it belongs to your
chain, and that your `requirement_count` matches reality.

## Entry format

```yaml
- date: 2026-08-25              # YYYY-MM-DD
  agent: "Codex (vehicle design)"
  action: CLAIMED               # CLAIMED | DELIVERED | ACCEPTED | REJECTED
                                # | BLOCKED | DECIDED | ESTABLISHED | NOTE
  requirements: [CHOMP-SYS-054] # must exist, and belong to this chain
  summary: >
    What was done, what was decided, what was assumed.
  status: OPEN                  # OPEN | DONE | BLOCKED
  handoff: >                    # optional: what the next agent needs to know
    ...
```

**Append-only.** Never edit or delete an existing entry. If an entry was wrong,
add a new one saying so. The log is a record of what happened, not a summary of
the current state — the current state lives in the requirements tree.

## Why per-chain rather than one log

One shared log across ten chains becomes a feed nobody reads, and two agents
editing the same file is a merge conflict on every commit. Per-chain logs mean
an agent reads only its own history, and two agents working different chains
never touch the same file.
