--[[
	ChompConfig — every tunable number in the game, defined exactly once.

	CHOMP-SYS-037: no balance value may appear as a literal anywhere in engine
	logic. If you find yourself typing a number into a service, it belongs here.

	This file is the authoritative source for the vehicle attributes required by
	03_architecture/vehicle_contract.md. A delivered chassis model must mirror
	these values in its attributes, and VehicleConformance.lua checks that it
	does — that mirroring exists so a model and the config cannot silently
	disagree.

	Units:
		speed      studs per second
		turn       degrees per second
		arc        degrees, total width (45 either side of LookVector for 90)
		durations  seconds
]]

local ChompConfig = {}

-- ── Chassis ─────────────────────────────────────────────────────────────
-- Bigger chassis carry more charge but turn worse, so a tier is a trade
-- rather than a straight upgrade. An Apex that has just respawned with an
-- empty bar is genuinely beatable by a topped-up Standard.

ChompConfig.Chassis = {
	Standard = { Tier = 1, BarCapacity = 100, Power = 100, BaseSpeed = 24, BaseTurn = 240, MouthArcDegrees = 90,  Cost = 0 },
	HeavyJaw = { Tier = 2, BarCapacity = 175, Power = 250, BaseSpeed = 23, BaseTurn = 220, MouthArcDegrees = 90,  Cost = 500 },
	Ravener  = { Tier = 3, BarCapacity = 275, Power = 450, BaseSpeed = 26, BaseTurn = 200, MouthArcDegrees = 100, Cost = 1500 },
	Apex     = { Tier = 4, BarCapacity = 400, Power = 700, BaseSpeed = 28, BaseTurn = 185, MouthArcDegrees = 110, Cost = 3500 },
}

ChompConfig.StartingChassis = "Standard"

-- Movement shared by every chassis. Corridors are 8 studs wide and vehicles
-- are at most 6, so turning has to complete inside roughly a third of a
-- second or junctions become unmissable at speed.
ChompConfig.Movement = {
	Acceleration = 60,       -- studs/s^2, deliberately snappy: arcade, not simulation
	Braking = 90,
	SteerRampSeconds = 0.12,      -- time for steering to reach the held value
	ReverseFlipSeconds = 0.45,
	ReverseFlipSecondsAgile = 0.25,   -- with Agility II or better
	AgilityLevelForFastReverse = 2,
}

-- ── Upgrades ────────────────────────────────────────────────────────────
-- Each track gives something and takes something. Per level, applied
-- additively on top of the chassis base.

ChompConfig.Upgrades = {
	Costs = { 150, 400, 900 },        -- level I, II, III
	PowerPerLevel = 40,
	MaxLevel = 3,

	Speed       = { Speed =  3, Turn = -12 },              -- faster, wider turning circle
	Agility     = { Turn  = 30, Speed = -1.5 },            -- corners better, lower top speed
	Consumption = { MouthArcDegrees = 10, PelletMultiplier = 0.25, HitboxRadius = 0.25 },
}

-- ── Combat ──────────────────────────────────────────────────────────────

ChompConfig.Combat = {
	HeadOnArcDegrees = 45,     -- within this of nose-to-nose is a head-on
	HeadOnBarLoss = 0.40,      -- both players, of their own bar
	ClangToleranceFraction = 0.10,
	BiteBarCost = 0.30,        -- the attacker spends this to bite
	ChompScatterFraction = 0.50,
	InvulnerabilitySeconds = 1.50,
	RespawnSeconds = 4.0,
	ScatterLifetimeSeconds = 20,
	SmallFryPowerGap = 300,    -- above this gap, a hit scatters nothing
	FallScatterFraction = 0.10,
}

-- ── Economy ─────────────────────────────────────────────────────────────

ChompConfig.Economy = {
	BankRate = 1.0,                     -- carried to dollars
	GarageReentryCooldownSeconds = 5,
	PelletRespawnSeconds = 12,
	ComboWindowSeconds = 1.5,
	ComboMax = 5,                       -- v2 (CHOMP-SYS-006)
	PelletValueByRing = { [1] = 10, [2] = 25, [3] = 60, [4] = 150 },
	PowerPelletValue = 100,
	EdibleGhostValue = 200,
	GuardianBonus = 500,
}

-- ── Ghosts ──────────────────────────────────────────────────────────────

ChompConfig.Ghosts = {
	StealFraction = 0.25,
	Speed = 21,                         -- slower than a Standard chassis on purpose
	FleeSpeed = 14,
	FullJawSeconds = 8,
	-- CHOMP-SYS-053: the maze fills up when the lobby empties.
	-- Highest player count whose threshold is met wins.
	CountByPlayers = {
		{ players = 2,  ghosts = 6 },
		{ players = 5,  ghosts = 5 },
		{ players = 8,  ghosts = 4 },
		{ players = 12, ghosts = 2 },
	},
	RecalculateWithinSeconds = 10,
	V1Behaviours = { "Chaser", "GreedyOne" },
}

-- ── Rings and gate guardians ────────────────────────────────────────────

ChompConfig.Rings = {
	Threat = { [2] = 250, [3] = 500, [4] = 800 },
	UnderPoweredScatterFraction = 0.50,
	GateOpenSeconds = 60,
	GuardianReformSeconds = 60,
}

-- ── Match ───────────────────────────────────────────────────────────────

ChompConfig.Match = {
	RoundSeconds = 360,
	RoundsPerMatch = 5,
	IntermissionSeconds = 30,
	MaxPlayers = 12,
	GaragesPerQuadrant = 3,
}

-- ── Budgets (the iPad is the reference platform, CHOMP-STK-007) ─────────

ChompConfig.Budgets = {
	VehicleParts = 60,
	VehicleTriangles = 5000,
	VehicleBounds = Vector3.new(6, 6, 8),
	VehicleTextures = 2,
	VehicleTextureResolution = 512,
	MouthSilhouetteFraction = 0.30,
	PlaceParts = 4000,
	TargetFPS = 30,
	CorridorWidth = 8,
}

-- ── Controls (D-CHOMP-015) ──────────────────────────────────────────────
-- Hold to turn, always driving forward. There is no accelerator, no brake and
-- no action button in the entire game.

ChompConfig.Controls = {
	DeadZoneFraction = 0.20,      -- middle fifth of the screen steers nowhere
	FullLockFraction = 0.42,      -- past this from centre, full turn rate
	FlipDoubleTapSeconds = 0.35,  -- two taps this close on the far side = 180 flip
	ThumbSafeZoneFraction = 0.30, -- bottom corners the HUD must keep clear
}

-- ── Camera (D-CHOMP-016) ────────────────────────────────────────────────
-- World-locked yaw: the camera never rotates with the vehicle. Turning spins
-- the model, not the world.

ChompConfig.Camera = {
	PitchDegrees = 38,
	Distance = 34,
	FieldOfView = 75,
	TargetScreenHeight = 0.55,    -- vehicle sits slightly below centre
	LookAheadStuds = 5,
	LookAheadEaseSeconds = 0.45,  -- the look-ahead must NOT snap round with the vehicle
	FollowEaseSeconds = 0.09,     -- smooths character physics jitter out of the camera
	DeckEaseSeconds = 0.35,
	OccluderFadeInSeconds = 0.12,
	OccluderFadeOutSeconds = 0.25,
	OccluderTransparency = 0.75,
	MaxOcclusionSeconds = 0.20,   -- CHOMP-SYS-051 hard limit
	HitShakeSeconds = 0.15,
	HitShakeStuds = 0.6,
}

-- ── Map geometry (D-CHOMP-017) ──────────────────────────────────────────
-- Everything on an 8-stud grid. Wall height is a camera constraint, not an
-- art choice: taller than this and the camera cannot see over it at 35 degrees.

ChompConfig.Map = {
	CellSize = 8,
	WallHeight = 7,
	WallThickness = 2,
	DeckHeight = 16,              -- floor to floor
	SlabThickness = 2,
	RampCells = 4,                -- 32 studs run for a 16 stud rise, ~26.6 degrees
	BridgeWidthCells = 1,
	QuadrantCells = 16,           -- authored quadrant is 16 x 16 cells
	GroundDeckCells = 32,         -- full ground deck after mirroring
	Ring2InnerCells = 8,          -- central 16 x 16 becomes the raised ring
	GarageCells = 3,              -- garages are 3 x 3 cells
	PelletsPerOpenCell = 1,
}

return ChompConfig
