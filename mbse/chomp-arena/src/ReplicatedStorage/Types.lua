--!strict
--[[
	Types — the shared vocabulary of the whole game.

	Every service reads and writes the same player record, and every pure logic
	module takes and returns the shapes defined here. If a chain invents its own
	shape for something in this file, two chains will disagree and the bug will
	surface as "points went missing" three weeks later.

	See 03_architecture/player_state.md for which service is allowed to WRITE
	each field. Anyone may read.
]]

export type Direction = "North" | "South" | "East" | "West" | "Up" | "Down"

export type ChassisId = "Standard" | "HeavyJaw" | "Ravener" | "Apex"

export type UpgradeTrack = "Speed" | "Agility" | "Consumption"

export type UpgradeLevels = {
	Speed: number,       -- 0..3
	Agility: number,     -- 0..3
	Consumption: number, -- 0..3
}

-- The authoritative per-player record. Server-side only; clients receive the
-- filtered views below.
export type PlayerState = {
	userId: number,
	garageSlot: number,          -- 1..12, assigned on join

	-- progression
	chassis: ChassisId,
	upgrades: UpgradeLevels,
	power: number,               -- derived from chassis + upgrades, cached
	banked: number,              -- safe dollars

	-- at risk
	bar: number,                 -- 0..chassis BarCapacity
	carried: number,             -- unbanked points

	-- position in the world
	deck: number,                -- 1 = ground
	ring: number,                -- 1 = outer

	-- transient effects, all absolute timestamps from os.clock()
	combo: number,               -- 1..ComboMax
	comboExpiresAt: number,
	invulnerableUntil: number,
	fullJawUntil: number,
	garageLockedUntil: number,
	gatePassUsed: boolean,       -- Full Jaw's one free gate, consumed
	respawnAt: number?,          -- nil while alive

	-- bookkeeping
	joinedAtMatchTime: number,   -- seconds into the match, for the catch-up grant
	saveBlocked: boolean,        -- a failed profile read must never be written back
}

-- What a client is told about ITSELF: everything.
export type OwnView = PlayerState

-- What a client is told about EVERYONE ELSE. Deliberately not the full record:
-- see D-CHOMP-013. Enough to decide who to hunt, not enough to compute the
-- exact value of hitting them.
export type PublicView = {
	userId: number,
	chassis: ChassisId,
	power: number,
	deck: number,
	ring: number,
	fullJawActive: boolean,
	carryBand: "Light" | "Heavy" | "Fat",
}

-- ── Combat ──────────────────────────────────────────────────────────────

export type ImpactKind = "HeadOn" | "Clang" | "Flank" | "None"

export type ImpactResult = {
	kind: ImpactKind,
	-- Deltas to APPLY, never the resulting values. Positive numbers are
	-- losses; the caller subtracts. Keeping these as deltas is what lets the
	-- pure function be unit-tested without a player object.
	attackerBarLoss: number,
	defenderBarLoss: number,
	defenderCarryLoss: number,
	attackerCarryLoss: number,
	scatterAt: "Attacker" | "Defender" | "Midpoint" | "None",
	scatterAmount: number,
}

-- ── Ghosts ──────────────────────────────────────────────────────────────

export type Junction = {
	id: string,
	position: Vector3,
	deck: number,
	ring: number,
	exits: { Direction },       -- only directions that actually lead somewhere
}

-- The read-only window a ghost behaviour module gets. A behaviour may call
-- nothing else — no game:GetService, no direct DataModel access — which is
-- what keeps behaviours pure, testable, and safe to hand to a child in v3.
export type WorldView = {
	junctionAt: (position: Vector3) -> Junction?,
	neighbour: (junction: Junction, direction: Direction) -> Junction?,

	players: () -> { PublicView },
	positionOf: (userId: number) -> Vector3?,
	facingOf: (userId: number) -> Vector3?,
	playerWithMostCarried: () -> PublicView?,
	nearestPlayer: (position: Vector3) -> PublicView?,

	-- Direction helpers. Each returns nil when no exit satisfies it, and the
	-- behaviour must then fall back to something; never assume non-nil.
	directionToward: (junction: Junction, target: Vector3) -> Direction?,
	directionAhead: (junction: Junction, userId: number, tiles: number) -> Direction?,
	directionAvoidingMouth: (junction: Junction, userId: number) -> Direction?,
	directionAwayFrom: (junction: Junction, target: Vector3) -> Direction?,

	-- Deterministic per-ghost randomness, so a behaviour stays reproducible in
	-- a unit spec. Behaviours must not call math.random directly.
	random: (ghostId: string) -> number,
}

export type GhostBehaviour = (ghostId: string, junction: Junction, world: WorldView) -> Direction

return {}
