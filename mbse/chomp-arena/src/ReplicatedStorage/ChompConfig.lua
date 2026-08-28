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

ChompConfig.ReleaseVersion = "0.3.8-alpha"

-- ── Chassis ─────────────────────────────────────────────────────────────
-- Bigger chassis carry more charge but turn worse, so a tier is a trade
-- rather than a straight upgrade. An Apex that has just respawned with an
-- empty bar is genuinely beatable by a topped-up Standard.

ChompConfig.Chassis = {
	Standard = { Tier = 1, ModulePorts = 1, BarCapacity = 100, Power = 100, BaseSpeed = 26.4, BaseTurn = 240, MouthArcDegrees = 90,  Cost = 0 },
	HeavyJaw = { Tier = 2, ModulePorts = 2, BarCapacity = 175, Power = 250, BaseSpeed = 25.3, BaseTurn = 220, MouthArcDegrees = 90,  Cost = 150000 },
	Ravener  = { Tier = 3, ModulePorts = 3, BarCapacity = 275, Power = 450, BaseSpeed = 28.6, BaseTurn = 200, MouthArcDegrees = 100, Cost = 300000 },
	Apex     = { Tier = 4, ModulePorts = 4, BarCapacity = 400, Power = 700, BaseSpeed = 30.8, BaseTurn = 185, MouthArcDegrees = 110, Cost = 600000 },
}

ChompConfig.StartingChassis = "Standard"

-- ── The kart ────────────────────────────────────────────────────────────
-- Scale is derived, not chosen (D-CHOMP-037, corrected in D-CHOMP-038).
--
-- The kart's true width is 5.84 studs, not the 5.3 of its widest body part:
-- the hover wheels stand proud of the shell. Measuring the body instead of the
-- bounding box is how the first attempt landed on 1.5, which breached both the
-- contract bounds and the turning sweep, so the factory refused to build it.
--
-- The sweep caps width at clear corridor minus turning radius, 14 - 5.7 = 8.27,
-- which caps scale at 1.416. 1.4 gives an 8.18-stud kart, 6.04 high - under the
-- 7-stud walls - and puts the canopy centre at 4.31, with the glass spanning
-- 2.7 to 6.0, so an R15 head at 4.5 to 5.0 sits inside it.
--
-- Re-derive if CellSize, BaseSpeed or BaseTurn move.
ChompConfig.Vehicle = {
	Scale = 1.4,
	ShowDriverHead = true,   -- the head stays visible through the glass canopy

	-- Making the driver read clearly is worth two knobs (D-CHOMP-039).
	-- The spec ships the canopy at 0.62, which is convincing glass and poor
	-- visibility; 0.85 keeps the highlight and the frame while letting the face
	-- through. Overridden after build so Codex's spec stays the source of truth
	-- for shape, and only the glass is tuned here.
	CanopyTransparency = 0.85,
	-- A kart driver reads as a driver mostly through head size. This is the
	-- R15 HeadScale, so it scales the head alone and leaves HipHeight - and
	-- therefore the chassis drop - untouched.
	-- 1.5 is the ceiling and it clears the canopy roof by 0.06 studs, which is
	-- not a margin when R15 head heights vary by avatar. 1.4 clears by 0.12.
	-- Above about 1.5 the head pushes through the glass.
	DriverHeadScale = 1.4,
	-- Wheels read as the vehicle's contact with the ground, and at 1.4 scale the
	-- kart's were lost under the shell. This multiplies wheels ONLY, on top of
	-- Scale (D-CHOMP-051).
	WheelScale = 1.45,
	NamePlate = true,          -- driver name floating above the kart
	MountHeldItem = true,      -- the cannon is visible, mounted on the roof
}

-- Movement shared by every chassis. Corridors are 16 studs wide and vehicles
-- are at most 6, so turning has to complete inside roughly a third of a
-- second or junctions become unmissable at speed.
ChompConfig.Movement = {
	Acceleration = 60,       -- studs/s^2, deliberately snappy: arcade, not simulation
	Braking = 90,
	-- Time for steering to reach the held value. Raised from 0.12 after the
	-- first real drive, which read as twitchy: on a keyboard the input is either
	-- 0 or full lock, so this ramp is the only thing standing between a tap and
	-- a full-rate rotation.
	--
	-- There is a ceiling on it. A corridor cell is crossed in CellSize/BaseSpeed
	-- seconds - about a third of a second at 8 studs and speed 24 - and steering
	-- that has not engaged by then cannot make a junction. Keep this comfortably
	-- under that, and re-derive it if either number moves.
	SteerRampSeconds = 0.24,
	-- Straightening is quicker than committing. Asymmetry is deliberate: the
	-- twitch people feel is usually the vehicle still turning after they let go,
	-- and a fast release fixes that without slowing the turn itself.
	SteerReleaseSeconds = 0.10,
	-- Below this speed the vehicle is "stopped", and a fresh direction press
	-- snaps it to face that way instead of steering it (D-CHOMP-033). The
	-- camera never rotates (D-CHOMP-016), so a direction on the keys or the
	-- stick is always the same direction on screen.
	SnapBelowSpeed = 1.5,
	ReverseFlipSeconds = 0.45,
	ReverseFlipSecondsAgile = 0.25,   -- with Agility II or better
	AgilityLevelForFastReverse = 2,
	ReverseSpeedFraction = 0.6,       -- reverse is slower than forward, so backing
	                                  -- out of a corner is never the fast route
}

-- ── Upgrades ────────────────────────────────────────────────────────────
-- Each track gives something and takes something. Per level, applied
-- additively on top of the chassis base.

ChompConfig.Upgrades = {
	Tracks = { "Engine", "Handling", "Armour", "Cannon", "Ordnance", "Jump", "Boost" },
	DisplayNames = {
		Engine = "SPEED", Handling = "HANDLING", Armour = "ARMOUR",
		Cannon = "FIRE POWER", Ordnance = "BOMBS", Jump = "JUMP", Boost = "BOOST",
	},
	-- Cannon owns the dedicated roof hardpoint. Every other performance system
	-- consumes one chassis module port when active.
	PortTracks = { "Engine", "Handling", "Armour", "Ordnance", "Jump", "Boost" },
	ModuleTracks = { "Engine", "Handling", "Armour", "Jump", "Boost" },
	Costs = { 800, 3500, 9500 },
	PowerPerLevel = 40,
	MaxLevel = 3,
	Engine = {
		SpeedFraction = { 0.05, 0.10, 0.15 },
		AccelerationFraction = { 0, 0.05, 0.10 },
		TurnPenaltyFraction = { 0, 0.04, 0.08 },
	},
	Handling = {
		TurnFraction = { 0.08, 0.16, 0.24 },
		SpeedPenaltyFraction = { 0, 0, 0.05 },
	},
	Armour = {
		MaxHealth = { 115, 135, 160 },
		GhostDamageReduction = { 0, 0.10, 0.20 },
		AccelerationPenaltyFraction = { 0, 0.04, 0.08 },
	},
	Cannon = {
		Barrels = { 1, 2, 3 },
		Magazine = { 14, 20, 30 },
		FireRateFraction = { 0, 0.15, 0.30 },
		Damage = { 1, 1, 1.25 },
	},
	Ordnance = {
		Charges = { 1, 2, 2 },
		BlastRadiusFraction = { 0, 0.15, 0.30 },
		Damage = { 1, 2, 3 },
	},
	Jump = {
		ImpulseFraction = { 0.08, 0.15, 0.20 },
		AirControlSeconds = { 0.15, 0.35, 0.60 },
		ForwardFraction = { 0, 0.10, 0.20 },
	},
	Boost = {
		ChargeRateFraction = { 0.10, 0.20, 0.30 },
		CapacityFraction = { 0, 0.15, 0.25 },
		CostReductionFraction = { 0, 0, 0.10 },
	},
}

ChompConfig.Profile = {
	SchemaVersion = 3,
	StoreName = "ChompPlayerProfileV2",
	AutosaveSeconds = 60,
	RetryCount = 3,
	RetryDelaySeconds = 0.5,
	-- How long the launch bay will wait for a profile before letting the player
	-- in anyway, degraded (D-CHOMP-066). Nothing may wait forever on a
	-- DataStore: three retries at half a second is the happy path, and this is
	-- the floor under everything that can go wrong beyond it - an outage, a
	-- throw, or a ProfileService that is not in the build at all.
	ReadyTimeoutSeconds = 10,
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
	-- Reach for eating and for banking, moved out of PelletService where they
	-- were literals against CHOMP-SYS-037 (D-CHOMP-066).
	PelletPickupRadiusStuds = 9,
	BankRadiusStuds = 22,
	ComboWindowSeconds = 1.5,
	ComboMax = 5,                       -- v2 (CHOMP-SYS-006)
	-- One value per LANE, counting inward (D-CHOMP-066). There are seven lanes
	-- and there were four values, clamped - so the inner FOUR lanes all paid
	-- 150 and the whole inner half of the map was flat. "Do I go one ring
	-- deeper" is the game's core question and it only had an answer across the
	-- outer three rings.
	--
	-- Each step inward is about 1.5x, so the gradient is felt rather than
	-- read, and the centre is unambiguously the jackpot it costs the most to
	-- reach. Add entries here if a map grows rings; PelletService indexes by
	-- #PelletValueByRing rather than a fixed 4.
	PelletValueByRing = { 10, 20, 35, 60, 90, 130, 180 },
	PowerPelletValue = 100,
	EdibleGhostValue = 200,
	GuardianBonus = 500,
}

-- ── Ghosts ──────────────────────────────────────────────────────────────

ChompConfig.Ghosts = {
	StealFraction = 0.25,
	-- Ghosts now HURT as well as steal (D-CHOMP-051). Contact damage is small
	-- and on a cooldown: the danger is being worn down while you are greedy,
	-- not being deleted by one mistake.
	ContactDamage = 14,
	-- Now read, at last (D-CHOMP-066). This is the PER-PLAYER window: however
	-- many ghosts are on you, one contact costs you one steal and one hit, and
	-- staying in the pack keeps costing. Worn down, not deleted.
	ContactCooldownSeconds = 1.6,
	Health = 1,                -- one clean hit; ghosts fly apart (D-CHOMP-054)
	KillRewardDollars = 200,   -- paid straight to BANKED, never to the carry
	RespawnSeconds = 12,
	Speed = 22.5,                       -- urgent, but still slower than every chassis
	-- Reach, rate and sight. These were literals inside GhostService against
	-- CHOMP-SYS-037, and they are three of the first numbers anyone reaches
	-- for when the game is too hard or too easy (D-CHOMP-066).
	StealRadiusStuds = 11,
	StealCooldownSeconds = 4,
	SenseRadiusStuds = 440,             -- aware across the full arena diameter
	FleeSpeed = 18,                     -- ring drift stays visibly active
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

-- Infinite Level 1 guardian encounter. Level 2 is not authored yet, so each
-- victory reforms the guardian with more health instead of opening a gate.
ChompConfig.Guardian = {
	RequiredPower = 500,
	BaseHealth = 120,
	HealthPerVictory = 40,
	RewardDollars = 15000,
	ReformSeconds = 8,
	MoveSpeed = 21.5,
	TurnDegreesPerSecond = 42,
	UnderpoweredDamageFraction = 0.25,
	ContactDamage = 28,
	ContactRadiusStuds = 20,
	ContactCooldownSeconds = 1.5,
	ChamberY = -260,
	ChamberHalfStuds = 200,
	HatchHalfStuds = 10,
	ShaftLengthStuds = 80,
	RevealY = -80,
	GuardianStartZ = -150,
	CoverRadii = { 82, 142 },
	PickupRadiusStuds = 112,
	PickupRespawnSeconds = 8,
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
	-- Re-derived for the 16-stud grid (D-CHOMP-038). The old 6 x 6 x 8 was set
	-- when corridors were 8 studs wide, and a kart scaled to fit a 16-stud
	-- corridor breached it, so the contract rejected a vehicle that was the
	-- right size for the map.
	--   X: turning sweep caps width at clear corridor minus turning radius,
	--      14 - 5.7 = 8.3
	--   Y: must stay under WallHeight (7) or the kart shows over the walls and
	--      the world-locked camera loses the maze
	--   Z: length is not sweep-limited the way width is; 10 leaves headroom
	VehicleBounds = Vector3.new(8.3, 7, 10),
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

-- ── Debug ───────────────────────────────────────────────────────────────
-- On by default while step 1 is being accepted. Turn CameraReadout off before
-- anyone plays this for fun rather than to measure it.
ChompConfig.Debug = {
	CameraReadout = false,  -- development-only camera diagnostics
}

ChompConfig.Controls = {
	-- Floating stick (D-CHOMP-027). Radius is a fraction of screen HEIGHT so the
	-- stick is the same physical size in portrait and landscape.
	StickRadiusFraction = 0.10,   -- drag this far from the anchor = full deflection
	StickDeadZoneFraction = 0.15, -- of the radius; below this the stick reads zero

	-- Retained for the HUD and for the old hold-to-turn scheme's tests.
	DeadZoneFraction = 0.20,      -- middle fifth of the screen steers nowhere
	FullLockFraction = 0.42,      -- past this from centre, full turn rate
	FlipDoubleTapSeconds = 0.35,
	-- Firing on touch is a TAP, not a button (D-CHOMP-045). A touch that ends
	-- quickly and barely moved was never a steering input, so it can mean
	-- "use what I am holding" without adding a control to a scheme whose whole
	-- premise is that there are none.
	TapFireSeconds = 0.22,
	TapFireSlopPixels = 14,  -- two taps this close on the far side = 180 flip
	ThumbSafeZoneFraction = 0.30, -- bottom corners the HUD must keep clear
}

-- ── Camera (D-CHOMP-016) ────────────────────────────────────────────────
-- World-locked yaw: the camera never rotates with the vehicle. Turning spins
-- the model, not the world.

-- ── Charge and the jump (D-CHOMP-059) ───────────────────────────────────
-- One big meter that fills as you eat. It is the only thing in the game that
-- rewards collecting for its own sake, and it pays out as a jump: the escape
-- move you spend rather than the weapon you carry.
ChompConfig.Charge = {
	PerPellet = 4,             -- a full bar is roughly 25 pellets
	Max = 100,
	-- 60, not 100 (D-CHOMP-064). A jump should still be a decision, but the
	-- first one has to ARRIVE: at a full bar the escape existed only for a
	-- player who had already survived 25 pellets' worth of driving, and a
	-- button that has never once lit up is indistinguishable from a broken one.
	-- 15 pellets is about half a corridor.
	JumpCost = 60,
	JumpImpulse = 110,
	JumpForwardStuds = 40,     -- carries you forward as well as up
}

-- ── Ghost waves (D-CHOMP-059) ───────────────────────────────────────────
-- Clearing a wave should feel like an achievement and the next one should
-- immediately make you nervous. Count and speed rise; the reward rises with
-- them so the risk stays worth taking.
ChompConfig.Waves = {
	-- Wave one has to bite (D-CHOMP-062). Four ghosts scattered around a
	-- 800-stud disc is an empty map with some distant shapes in it; the first
	-- thirty seconds decide whether anyone plays the second wave.
	StartCount = 12,
	AddPerWave = 4,
	StartCountByPlayers = {
		{ players = 1, count = 8 },
		{ players = 3, count = 10 },
		{ players = 6, count = 12 },
		{ players = 12, count = 16 },
	},
	-- Ghosts arrive AROUND the player rather than parked on rings, so a wave
	-- starts as an event instead of a rumour.
	SpawnNearPlayerStuds = 120,
	SpawnMinDistanceStuds = 45,
	MaxCount = 24,
	SpeedPerWave = 0.7,        -- studs/s added each wave
	MaxSpeed = 24,             -- always outrunnable by a Standard
	RewardPerWave = 60,        -- extra banked dollars per kill, per wave
	BreakSeconds = 15,         -- enough time to bank and read the next wave
	RevealLastAt = 4,            -- survivors stop drifting and actively find you
	SurvivorRegroupSeconds = 7,  -- retry if the final survivors become stranded
	SurvivorLostDistance = 130,  -- outside useful combat range, bring them back
	ItemRespawnReductionPerWave = 1.25,
	MinimumItemRespawnSeconds = 8,
}

-- Audio asset IDs are deliberately blank in source control. Roblox audio must
-- be uploaded by the experience owner and granted to this experience before an
-- rbxassetid can play. Paste only the resulting numeric IDs here; source audio
-- and licenses remain outside the repository (AUDIO-SOURCING-2026-08-26.md).
ChompConfig.Audio = {
	MusicVolume = 0.24,
	EffectsVolume = 0.55,
	Music = {
		Exploration = "94645663905351",
		Guardian = "125404032785476",
	},
	Effects = {
		Pellet = { "111478242587482", "106297992379380", "131776712928369",
			"106432309102763", "128293073466263" },
		PowerPellet = "72416914518123",
		Bank = "79168431123739",
		Purchase = "79168431123739",
		Cannon = { "86582069102792", "74202937516850", "94011105268340" },
		CannonHit = "138035988005770",
		BombArm = "94747791937634",
		BombBlast = "99326810430842",
		ShieldOn = "75193599106833",
		ShieldBreak = "139668926662281",
		JetPack = "140526400915279",
		Hurt = { "99885999815502", "109495522818192" },
		Death = "101291490507949",
		WaveClear = "72416914518123",
	},
}

-- ── The garage store (D-CHOMP-055) ──────────────────────
-- Everything buyable stands on a plinth you can drive up to and look at.
-- Prices are in banked dollars: the currency you earned by surviving.
--
-- RobuxPrice is DISPLAY ONLY. Nothing here charges anyone. Wiring a real
-- purchase is a monetisation decision with legal and parental consequences
-- and is not a thing to slip into an overnight build; the label exists so the
-- layout can be judged with it present.
ChompConfig.Store = {
	DwellSeconds = 1.2,        -- hold still at a plinth to buy; no button, no misclick
	PlinthRadiusStuds = 13,
	MaxPurchaseSpeed = 2.5,
	RefusalCooldownSeconds = 1.5,
	-- Weapons on plinths (D-CHOMP-064). Picking one up in the maze is luck;
	-- buying one is a plan. Prices are deliberately under a single good bank
	-- run, because the point of selling weapons is that a player who keeps
	-- dying can choose to arrive at the next wave armed - a shop that only the
	-- winner can afford makes losing worse.
	--
	-- Cheaper than the cheapest chassis, and every one of them is spent. A
	-- chassis is kept.
	ItemPrices = {
		Shield = 60,
		JetPack = 70,
		HomingBomb = 90,
		Cannon = 120,
	},
	-- Display only, and now not displayed (D-CHOMP-066). The plinths drew
	-- "or R$99" beside every dollar price while nothing in the game could
	-- charge Robux at all. Flip this to true on the day a real purchase is
	-- wired and a parent has decided it should be.
	ShowRobuxPrices = false,
	RobuxPrice = {
		HeavyJaw = 99,
		Ravener = 249,
		Apex = 499,
		Speed = 49,
		Agility = 49,
		Consumption = 49,
		Shield = 19,
		JetPack = 19,
		HomingBomb = 29,
		Cannon = 39,
	},
}

-- ── Items (D-CHOMP-045) ─────────────────────────────────────────────────
-- One slot. Picking anything up replaces what you were carrying, so the
-- decision is always "is this better than what I have", never inventory
-- management. Charges are spent per use and the slot empties at zero.
ChompConfig.Items = {
	-- Five slots, used in order (D-CHOMP-062). One slot made every pickup a
	-- judgement, which was right when there was nothing to survive; waves
	-- changed that. Now the judgement is what to spend and when, and a full
	-- belt is something you earned by driving well.
	SlotCount = 5,
	RespawnSeconds = 20,        -- a collected pad comes back, so the map stays stocked
	PickupRadiusStuds = 10,
	-- Palette KEYS, not Color3s, so ItemModels (server) and the HUD belt
	-- (client) tint the same item the same way without sharing a module
	-- (D-CHOMP-064).
	Colours = {
		JetPack = "NeonA",
		Cannon = "Gold",
		HomingBomb = "NeonB",
		Shield = "Shield",
	},
	UseRateLimit = 14,          -- per second, enforced server side. High because
	                            -- the cannon is a held-down machine gun; the gun
	                            -- has its own slower rate below (D-CHOMP-056).

	Definitions = {
		JetPack = {
			charges = 1,
			-- A hop, not flight. Clearing a wall is a shortcut worth having;
			-- flying over the maze would delete the maze.
			impulseStuds = 70,
			label = "JET",
		},
		Cannon = {
			charges = 10,
			label = "CANNON",
			-- A machine gun, not a lobbed orb (D-CHOMP-056). Small, fast, and
			-- fired by holding the key down.
			fireRatePerSecond = 9,
			projectileSpeed = 360,
			pelletSize = 0.9,
			pelletLength = 5,        -- drawn as a streak, so speed is visible
			spreadDegrees = 2.5,
			-- 170 studs, and it stops at walls (D-CHOMP-064). 300 was most of
			-- the way across the arena and passed through everything, so a
			-- player could hold the trigger down facing a wall and farm ghosts
			-- they could not see. A gun that kills what you cannot see is not a
			-- gun, it is a scoreboard.
			--
			-- Roughly four corridor widths: long enough to answer something
			-- coming at you down a ring, short enough that the far side of the
			-- arena is somewhere you have to DRIVE to.
			rangeStuds = 170,
			-- Shots inherit the kart's velocity, so firing sideways at speed
			-- makes them curve away from the nose. That is what firing from a
			-- moving vehicle actually looks like, and it means leading a target
			-- is a thing the player learns rather than a thing the game hides.
			inheritVelocity = 0.75,
			-- Auto-lock (D-CHOMP-054). The turret finds the nearest ghost in
			-- front of you, tracks it in red, and turns green when it has held
			-- it for LockSeconds. Aiming while steering a kart is not a skill
			-- worth demanding of a seven-year-old; CHOOSING when to fire is.
			-- Never longer than rangeStuds. A lock is a promise that firing will
			-- connect, and a reticle that goes green on something out of range
			-- teaches a child that the green light means nothing (D-CHOMP-064).
			lockRangeStuds = 160,
			-- 180 is a full circle of search: the turret turns all the way round,
			-- so there is no blind spot behind you and no reason to line a shot
			-- up by driving (D-CHOMP-059).
			lockAngleDegrees = 180,
			lockSeconds = 0.45,      -- continuous tracking before it goes green
			turretTurnDegrees = 220, -- how fast the barrel swings
			-- How far it can look up or down (D-CHOMP-061). Derived, not chosen:
			-- the jump apexes near 53 studs, ghosts hover at 8, and a ghost
			-- chasing you is CLOSE - at 10 studs of horizontal separation that
			-- is 77 degrees of down-pitch. At 60 the barrel could not point at
			-- the one thing the jump was for. 80 covers everything but straight
			-- down, and the jump carries you 40 studs forward anyway, so
			-- straight down is not where the target ends up.
			turretPitchDegrees = 80,
		},
		HomingBomb = {
			charges = 1,
			label = "BOMB",
			-- A DROPPED mine, not a chased missile (D-CHOMP-054). First tap
			-- drops it behind you, second tap detonates. That makes it a trap
			-- you place rather than a shot you aim, which is the thing a slower
			-- vehicle can actually use against something chasing it.
			dropBehindStuds = 14,
			blastRadiusStuds = 46,
			armSeconds = 0.35,       -- cannot detonate in your own face
			lifetimeSeconds = 20,
		},
		Shield = {
			charges = 1,
			durationSeconds = 8,
			label = "SHIELD",
		},
	},
}

-- ── Arrival bay and deployment ─────────────────────────────────────────
ChompConfig.Launch = {
	LoadingState = "PROFILE_LOADING",
	BayState = "IN_BAY",
	DeployingState = "DEPLOYING",
	ActiveState = "ACTIVE",
	DeploymentSeconds = 3,
	SpawnProtectionSeconds = 3,
	GateWidthStuds = 34,
	GateHeightStuds = 18,
}

-- ── Level 1: the bowl (D-CHOMP-041) ─────────────────────────────────────
-- Safety and reward as geography: learn and bank on the rim, take risks toward
-- the middle. Radii are in studs and everything is a multiple of CellSize so
-- the rim corridors are the same width as everywhere else.
ChompConfig.Level1 = {
	-- ONE LEVEL, fully enclosed. No decks, no drops, no way off the floor: the
	-- arena is a sealed disc and the only vertical thing in it is a wall
	-- (D-CHOMP-046).
	OuterRadius = 400,        -- the boundary wall; nothing exists beyond it
	CentreRadius = 120,       -- open arena in the middle, no rings inside this
	RingSpacing = 40,         -- 2.5 corridors between rings
	GapsPerRing = 6,          -- openings per ring, offset ring to ring
	SpokesPerRing = 5,        -- short radial walls so a ring is not a racetrack
	SegmentStuds = 14,        -- arc resolution; smaller is rounder and costs parts
	GarageCount = 4,
	-- Sanctuaries (D-CHOMP-065). Ghosts cannot enter, cannot spawn inside, and
	-- cannot steal from or hurt anyone standing in one.
	--
	-- The HOME garage is large because it has to hold the whole shop row: you
	-- spawn there, and a wave anchored on you put nine ghosts on top of a
	-- player who had not moved yet. Shopping needs 1.2 seconds of stillness,
	-- which is not a thing you can do while being chased.
	--
	-- The other three pads are small on purpose. Banking is a moment, so a
	-- moment is what they protect; a 150-stud bubble on all four would make a
	-- quarter of the outer ring a place ghosts may not go, and the outer ring
	-- is where the pellets are. A sanctuary you can hide in is a sanctuary that
	-- ends the game.
	HomeSafeRadiusStuds = 150,
	GarageSafeRadiusStuds = 60,
	GuardianChamberStuds = 72,
	GuardianAngleDegrees = 0,
	-- Ring surfaces, cycled outward from the centre arena (D-CHOMP-063).
	--
	-- Every ring is a different SURFACE, not a different colour of the same
	-- surface. At speed a driver reads texture before they read hue - brick
	-- catches the light in rows, cobblestone scatters it, neon does not catch
	-- it at all - so "the cobbled ring" is a place in a way that "the second
	-- teal ring" never was.
	--
	-- Neon is deliberately the minority. It was landmarks before and it is
	-- landmarks now, but a corridor of neon on neon has nothing to read
	-- against; the masonry is what makes the neon glow.
	--
	-- `colour` names a Palette key rather than holding a Color3, because
	-- Palette is defined further down this file.
	RingStyles = {
		{ material = Enum.Material.Neon,        colour = "NeonA"     },
		{ material = Enum.Material.Brick,       colour = "BrickWarm" },
		{ material = Enum.Material.Slate,       colour = "Slate"     },
		{ material = Enum.Material.Neon,        colour = "NeonB"     },
		{ material = Enum.Material.Cobblestone, colour = "Stone"     },
		{ material = Enum.Material.Brick,       colour = "Rust"      },
		{ material = Enum.Material.Concrete,    colour = "BrickDark" },
	},
	-- Spokes take the opposite treatment to the ring they hang off, so a
	-- junction always shows two surfaces meeting and never dissolves into one
	-- continuous wall.
	SpokeNeon   = { material = Enum.Material.Neon,  colour = "NeonB" },
	SpokeMasonry = { material = Enum.Material.Brick, colour = "Stone" },
}


-- ── Palette (D-CHOMP-046) ───────────────────────────────────────────────
-- Dark ground, hot neon, one gold accent. Driving fast past a lit wall is what
-- makes speed legible, so the walls carry the colour and the floor stays out of
-- the way.
ChompConfig.Palette = {
	Floor       = Color3.fromRGB(25, 20, 38),
	FloorCentre = Color3.fromRGB(88, 42, 116),
	NeonA       = Color3.fromRGB(76, 224, 210),
	NeonB       = Color3.fromRGB(208, 74, 255),
	Brick       = Color3.fromRGB(92, 72, 118),
	BrickDark   = Color3.fromRGB(58, 47, 76),
	-- Masonry (D-CHOMP-063). Kept dark and desaturated on purpose: these are
	-- what the neon is seen against, and a bright wall next to a lit one is
	-- two things competing rather than one lighting the other.
	BrickWarm   = Color3.fromRGB(128, 68, 78),
	Stone       = Color3.fromRGB(108, 103, 128),
	Slate       = Color3.fromRGB(82, 84, 110),
	Rust        = Color3.fromRGB(142, 78, 56),
	Boundary    = Color3.fromRGB(118, 82, 146),
	Gold        = Color3.fromRGB(255, 176, 32),
	Danger      = Color3.fromRGB(255, 61, 61),
	Ghost       = Color3.fromRGB(226, 232, 255),
	-- The one green in the game, and it means SAFE: the shield, and a lock that
	-- has closed. It was written out twice as a literal before (D-CHOMP-064).
	Shield      = Color3.fromRGB(126, 217, 87),
	CavernFloor = Color3.fromRGB(66, 72, 84),
	CavernWall  = Color3.fromRGB(158, 166, 180),
	CavernCoverA = Color3.fromRGB(232, 188, 82),
	CavernCoverB = Color3.fromRGB(72, 194, 205),
}

ChompConfig.Camera = {
	PitchDegrees = 38,
	Distance = 34,
	FieldOfView = 75,
	GuardianPitchDegrees = 46,
	GuardianDistance = 58,
	GuardianFieldOfView = 82,
	GuardianTransitionSeconds = 0.6,
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
	-- Corridor width, and it is derived rather than chosen (D-CHOMP-034).
	-- Turning radius is BaseSpeed / BaseTurn in radians: 24 / 4.19 = 5.7 studs.
	-- At cell 8 the clear width was 6 studs against a 4.8-stud vehicle - 0.6
	-- studs either side - so there was no room to arc and every corner was a
	-- pivot in place. 16 leaves 4.6 studs either side and the sweep fits.
	-- If BaseSpeed or BaseTurn move, re-derive this. Checked at +10% speed
	-- (D-CHOMP-057): turning radius rises 5.73 -> 6.30, and Level 1's corridors
	-- are 38 studs clear rather than this 14, so the sweep still fits with room
	-- to spare. CellSize now only sets garage pads and ring gap widths; the
	-- corridor width that matters lives in Level1.RingSpacing.
	CellSize = 16,
	WallHeight = 7,
	WallThickness = 2,
	DeckHeight = 16,              -- floor to floor
	SlabThickness = 2,
	RampCells = 2,                -- 32 studs run for a 16 stud rise, ~26.6 degrees
	BridgeWidthCells = 1,
	QuadrantCells = 16,           -- authored quadrant is 16 x 16 cells
	GroundDeckCells = 32,         -- full ground deck after mirroring
	Ring2InnerCells = 8,          -- central 16 x 16 becomes the raised ring
	GarageCells = 2,              -- 2 x 2 cells is 32 studs square at cell 16
	PelletsPerOpenCell = 1,

	-- Which map the server builds on start.
	--   "Test"   the throwaway two-deck map CHOMP-TC-040 was built against
	--   "Arena"  a generated rectilinear maze: ground maze, raised ring 2,
	--            ramps, bridges, garages
	--   "Level1" the bowl (D-CHOMP-041): rim maze, slopes into a central combat
	--            bowl, guardian chamber. This is the one being built.
	-- Arena is GENERATED, not authored. The v1 map in map_geometry.md is hand
	-- built by the child from prefabs; this exists so there is something real to
	-- drive before that work starts, and so it costs nothing to throw away when
	-- the camera forces a geometry change.
	Layout = "Level1",
	ArenaSeed = 20260825,         -- change for a different maze, same rules
	ArenaCells = 16,              -- full grid across; must be even, quadrant is half
	ArenaDecks = 1,               -- 1 = ground only. 2 adds ring 2, ramps and bridges
	ArenaBraidChance = 0.45,      -- higher is more loops and fewer dead ends
}

return ChompConfig
