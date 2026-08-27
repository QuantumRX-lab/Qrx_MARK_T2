--!strict
--[[
	ChompLogic.Progression — CHAIN-ECONOMY

	Pure functions over chassis and upgrade levels. No player objects.

	This module is the one source of truth for derived progression values.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("Types"))
local Config = require(ReplicatedStorage:WaitForChild("ChompConfig"))

local Progression = {}

--[[
	computePower(chassis, upgrades) -> number

	Chassis Power plus PowerPerLevel for every upgrade level held. This is the
	ONLY place power is calculated; PlayerState.power is a cache of it and is
	asserted equal in debug builds.

	Boundary cases: fresh Standard is exactly 100; Apex with all nine levels is
	exactly 1060; an unknown chassis id is an error, not a zero.
]]
function Progression.computePower(chassis: Types.ChassisId, upgrades: Types.UpgradeLevels): number
	local base = Config.Chassis[chassis]
	assert(base, "unknown chassis: " .. tostring(chassis))
	local levels = upgrades.Engine + upgrades.Handling + upgrades.Armour
		+ upgrades.Cannon + upgrades.Ordnance + upgrades.Jump + upgrades.Boost
	return base.Power + levels * Config.Upgrades.PowerPerLevel
end

--[[
	effectiveStats(chassis, upgrades) -> {speed, turn, mouthArcDegrees, hitboxRadius, pelletMultiplier}

	Applies the upgrade deltas to the chassis base, INCLUDING the costs: Speed
	levels reduce turn, Agility levels reduce speed. Clamp so no stat can go
	below half its chassis base — a player who dumps everything into Agility
	must still be able to move.

	Boundary cases: no upgrades returns the chassis base unchanged; Handling III
	on Apex still leaves speed above the floor; Armour sets health rather than
	quietly adding another independent damage system.
]]
function Progression.effectiveStats(chassis: Types.ChassisId, upgrades: Types.UpgradeLevels)
	local base = Config.Chassis[chassis]
	assert(base, "unknown chassis: " .. tostring(chassis))
	local function rung(track: any, level: number, field: string): number
		if level <= 0 then return 0 end
		local values = track[field]
		return values and values[math.clamp(level, 1, Config.Upgrades.MaxLevel)] or 0
	end
	local speed = base.BaseSpeed * (1
		+ rung(Config.Upgrades.Engine, upgrades.Engine, "SpeedFraction")
		- rung(Config.Upgrades.Handling, upgrades.Handling, "SpeedPenaltyFraction"))
	local turn = base.BaseTurn * (1
		+ rung(Config.Upgrades.Handling, upgrades.Handling, "TurnFraction")
		- rung(Config.Upgrades.Engine, upgrades.Engine, "TurnPenaltyFraction"))
	local maxHealth = if upgrades.Armour > 0
		then Config.Upgrades.Armour.MaxHealth[upgrades.Armour] else 100
	return {
		speed = math.max(base.BaseSpeed * 0.5, speed),
		turn = math.max(base.BaseTurn * 0.5, turn),
		mouthArcDegrees = base.MouthArcDegrees,
		hitboxRadius = 0,
		pelletMultiplier = 1,
		chargeMultiplier = 1 + rung(Config.Upgrades.Boost, upgrades.Boost, "ChargeRateFraction"),
		chargeCapacity = Config.Charge.Max * (1
			+ rung(Config.Upgrades.Boost, upgrades.Boost, "CapacityFraction")),
		maxHealth = maxHealth,
		modulePorts = base.ModulePorts,
	}
end

--[[
	costOf(itemId, upgrades) -> number?
	itemId is either a chassis id or one of Config.Upgrades.Tracks. For a
	track, the cost is the next unowned level's price; nil when already at
	MaxLevel or when a chassis is already owned or is a downgrade.
]]
function Progression.costOf(itemId: string, chassis: Types.ChassisId, upgrades: Types.UpgradeLevels): number?
	local track = Config.Upgrades[itemId]
	if track and table.find(Config.Upgrades.Tracks, itemId) then
		local level = upgrades[itemId]
		if typeof(level) ~= "number" or level >= Config.Upgrades.MaxLevel then return nil end
		return Config.Upgrades.Costs[level + 1]
	end
	local current = Config.Chassis[chassis]
	local wanted = Config.Chassis[itemId]
	if not (current and wanted) or wanted.Tier <= current.Tier then return nil end
	return wanted.Cost
end

--[[
	carryBand(carried) -> "Light" | "Heavy" | "Fat"
	What other players are allowed to see (D-CHOMP-013).
]]
function Progression.carryBand(carried: number): string
	if carried < 200 then return "Light" end
	if carried < 600 then return "Heavy" end
	return "Fat"
end

--[[
	catchUpGrant(matchElapsedSeconds) -> number
	Dollars given to a player joining mid-match, scaled to elapsed time so that
	a round-four joiner is not driving a Standard against Raveners with nothing
	(CHOMP-SYS-029, v2). Zero at match start; never enough to leapfrog the
	leader.
]]
function Progression.catchUpGrant(matchElapsedSeconds: number): number
	-- A modest $100 per elapsed round, capped below Ravener's price. MatchService
	-- may clamp this further against the live median when it owns standings.
	local rounds = math.floor(math.max(0, matchElapsedSeconds) / Config.Match.RoundSeconds)
	return math.min(1000, rounds * 100)
end

return Progression
