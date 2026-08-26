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
	local levels = upgrades.Speed + upgrades.Agility + upgrades.Consumption
	return base.Power + levels * Config.Upgrades.PowerPerLevel
end

--[[
	effectiveStats(chassis, upgrades) -> {speed, turn, mouthArcDegrees, hitboxRadius, pelletMultiplier}

	Applies the upgrade deltas to the chassis base, INCLUDING the costs: Speed
	levels reduce turn, Agility levels reduce speed. Clamp so no stat can go
	below half its chassis base — a player who dumps everything into Agility
	must still be able to move.

	Boundary cases: no upgrades returns the chassis base unchanged; three
	Agility levels on Apex still leaves speed above the floor; Consumption
	widens the mouth arc and the hitbox together, since a bigger mouth is a
	bigger target (that trade is the point).
]]
function Progression.effectiveStats(chassis: Types.ChassisId, upgrades: Types.UpgradeLevels)
	local base = Config.Chassis[chassis]
	assert(base, "unknown chassis: " .. tostring(chassis))
	local speed = base.BaseSpeed
		+ upgrades.Speed * Config.Upgrades.Speed.Speed
		+ upgrades.Agility * Config.Upgrades.Agility.Speed
	local turn = base.BaseTurn
		+ upgrades.Speed * Config.Upgrades.Speed.Turn
		+ upgrades.Agility * Config.Upgrades.Agility.Turn
	return {
		speed = math.max(base.BaseSpeed * 0.5, speed),
		turn = math.max(base.BaseTurn * 0.5, turn),
		mouthArcDegrees = base.MouthArcDegrees
			+ upgrades.Consumption * Config.Upgrades.Consumption.MouthArcDegrees,
		hitboxRadius = upgrades.Consumption * Config.Upgrades.Consumption.HitboxRadius,
		pelletMultiplier = 1
			+ upgrades.Consumption * Config.Upgrades.Consumption.PelletMultiplier,
	}
end

--[[
	costOf(itemId, upgrades) -> number?
	itemId is either a chassis id or "Speed"/"Agility"/"Consumption". For a
	track, the cost is the next unowned level's price; nil when already at
	MaxLevel or when a chassis is already owned or is a downgrade.
]]
function Progression.costOf(itemId: string, chassis: Types.ChassisId, upgrades: Types.UpgradeLevels): number?
	local track = Config.Upgrades[itemId]
	if track then
		local level = if itemId == "Speed" then upgrades.Speed
			elseif itemId == "Agility" then upgrades.Agility
			else upgrades.Consumption
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
