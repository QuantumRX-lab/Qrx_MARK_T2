# Stakeholders

| Stakeholder | What they need from this | What breaks it for them |
|---|---|---|
| **The daughter (7)** | A game she wants to play, on the iPad, that she helped make and can point at parts of | Being unable to read the screen at speed; being farmed by an adult; losing a run to a fall or a bug; having no job for weeks while an engine gets written |
| **The father** | A project that stays finishable, that teaches something, and that he can hand pieces of to other agents without losing the thread | Unbounded scope; a design that only works with twelve players; discovering the camera is unusable after six maps are built |
| **Other children (friends, siblings)** | Somewhere to join in that doesn't need explanation | A game that assumes a full lobby; a mode menu they have to understand first |
| **Codex (vehicle design agent)** | An unambiguous contract for what a vehicle model must satisfy, and somewhere to deliver | Implicit expectations; discovering after delivery that the mouth orientation convention was different |
| **Future agents on other chains** | To know what has been decided, what is open, and who is holding what | Silent parallel edits; decisions made in a chat that never reached the tree |
| **Roblox (the platform)** | Compliance with content and moderation policy | Rendering unfiltered player text; unread third-party scripts |

## The tension that shapes the tree

The daughter's needs and the father's needs are not automatically aligned. The
engine-first ordering (`D-CHOMP-001`) is right for the game and wrong for her
involvement, and that conflict is logged honestly as `RISK-CHOMP-006` with a
mitigation — she builds maps from snapped prefab pieces from day one, long
before the authoring kit exists to formalise it — rather than being smoothed
over.

The second tension is fairness versus depth: every upgrade that makes an
experienced player stronger makes the lobby less fair for a beginner. That is
resolved mechanically rather than socially — ring gating sorts by strength, the
per-match reset stops veterans starting ahead, and the small-fry rule removes
the reward for bullying down.
