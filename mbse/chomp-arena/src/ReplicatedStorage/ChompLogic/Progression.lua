--!strict
--[[
	ChompLogic.Progression — CHAIN-ECONOMY

	Pure functions over chassis and upgrade levels. No player objects.

	STATUS: signatures and specification only. CHAIN-ECONOMY implements.
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
	error("not implemented — CHAIN-ECONOMY")
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
	error("not implemented — CHAIN-ECONOMY")
end

--[[
	costOf(itemId, upgrades) -> number?
	itemId is either a chassis id or "Speed"/"Agility"/"Consumption". For a
	track, the cost is the next unowned level's price; nil when already at
	MaxLevel or when a chassis is already owned or is a downgrade.
]]
function Progression.costOf(itemId: string, chassis: Types.ChassisId, upgrades: Types.UpgradeLevels): number?
	error("not implemented — CHAIN-ECONOMY")
end

--[[
	carryBand(carried) -> "Light" | "Heavy" | "Fat"
	What other players are allowed to see (D-CHOMP-013).
]]
function Progression.carryBand(carried: number): string
	error("not implemented — CHAIN-ECONOMY")
end

--[[
	catchUpGrant(matchElapsedSeconds) -> number
	Dollars given to a player joining mid-match, scaled to elapsed time so that
	a round-four joiner is not driving a Standard against Raveners with nothing
	(CHOMP-SYS-029, v2). Zero at match start; never enough to leapfrog the
	leader.
]]
function Progression.catchUpGrant(matchElapsedSeconds: number): number
	error("not implemented — CHAIN-ECONOMY")
end

return Progression
