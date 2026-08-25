--!strict
--[[
	VehicleController — CHAIN-VEHICLE, CHOMP-SYS-001

	Continuous steering (D-CHOMP-042). Hold forward to drive, steer left and
	right proportionally, pull back to reverse. You lean into a bend rather than
	snapping between four headings.

	This is the fifth control scheme and the last reversal has a reason rather
	than a preference behind it. Level 1 is a bowl with a rim (D-CHOMP-041), and
	a curve has no cardinal directions to snap to — grid driving cannot follow
	one, it can only chord across it. Weapons settle the rest: a cannon that
	points where you are facing needs a heading finer than four steps.

	What survives from grid driving is the thing that was always right: the
	client integrates a heading and hands it to Move(). It never writes a
	transform, so the physics solver has nothing to fight over (D-CHOMP-025).
	The server still owns speed and turn rate and validates the result
	(D-CHOMP-018).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("ChompConfig"))
local MOVE = Config.Movement

local player = Players.LocalPlayer

-- Roblox's default control script drives the same Humanoid this controller
-- does. It calls humanoid:Move() every frame from its own input, and with no
-- key held that call is Vector3.zero — which cancels the drive below, so the
-- vehicle only moved while a key was down and never steered. Disabling it makes
-- this the single writer of locomotion.
--
-- This is D-CHOMP-018 again in a different property: the fix moved rotation off
-- the server, but left a second authority calling Move() on the client. One
-- writer per value, or the value is whatever ran last (D-CHOMP-023).
task.spawn(function()
	local ok, err = pcall(function()
		local playerScripts = player:WaitForChild("PlayerScripts", 10)
		if not playerScripts then error("PlayerScripts never appeared") end
		local module = playerScripts:WaitForChild("PlayerModule", 10)
		if not module then error("PlayerModule never appeared") end
		require(module):GetControls():Disable()
	end)
	if ok then
		print("[VehicleController] default controls disabled — this is the only mover")
	else
		-- Loud, because the symptom otherwise reads as "the handling is bad"
		-- rather than "something else is steering".
		warn("[VehicleController] could not disable default controls, expect a fight: " .. tostring(err))
	end
end)

-- Written by InputController each frame. Intent only, -1 .. 1 on each axis.
local state = _G.ChompInput or { steer = 0, throttle = 0, flip = false }
_G.ChompInput = state

-- CFrame.Angles(0, h, 0) has a LookVector of (-sin h, 0, -cos h), so north
-- (towards -Z) is zero and the compass runs anticlockwise from there.
local heading = 0
local headingReady = false
local currentSpeed = 0
local smoothedSteer = 0

player.CharacterAdded:Connect(function()
	headingReady = false
	currentSpeed = 0
	smoothedSteer = 0
end)

local function stats()
	-- The server holds the authoritative values and writes them onto the
	-- character as attributes; this is a read, not a decision.
	local character = player.Character
	local speed = character and character:GetAttribute("ChompSpeed")
	local turn = character and character:GetAttribute("ChompTurn")
	local chassis = Config.Chassis[Config.StartingChassis]
	return speed or chassis.BaseSpeed, turn or chassis.BaseTurn
end

RunService.RenderStepped:Connect(function(dt)
	local character = player.Character
	if not character then return end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not (root and humanoid) then return end
	if humanoid.Health <= 0 then return end

	local topSpeed, turnRate = stats()

	if not headingReady then
		local _, y = root.CFrame:ToOrientation()
		heading = y
		headingReady = true
	end

	-- Engaging and releasing use different rates (D-CHOMP-032). Committing to a
	-- turn should take a moment; coming out of one should not, because a vehicle
	-- that keeps turning after the key is released is what reads as twitchy.
	local steerTarget = state.steer or 0
	local engaging = math.abs(steerTarget) > math.abs(smoothedSteer)
	local rampSeconds = engaging and MOVE.SteerRampSeconds or MOVE.SteerReleaseSeconds
	local ramp = math.clamp(dt / rampSeconds, 0, 1)
	smoothedSteer += (steerTarget - smoothedSteer) * ramp

	heading += -math.rad(turnRate) * smoothedSteer * dt

	-- Signed throttle: forward drives, back reverses at a fraction of top speed,
	-- centre coasts to a stop over Braking. Accelerating means moving away from
	-- zero; anything else brakes, which is the stronger rate, so reversing out
	-- of a forward roll slows first and only then picks up speed backwards.
	local demand = state.throttle or 0
	local target = topSpeed * demand
	if demand < 0 then
		target = target * MOVE.ReverseSpeedFraction
	end
	local rate = (math.abs(target) > math.abs(currentSpeed)) and MOVE.Acceleration or MOVE.Braking
	if currentSpeed < target then
		currentSpeed = math.min(target, currentSpeed + rate * dt)
	else
		currentSpeed = math.max(target, currentSpeed - rate * dt)
	end

	-- MoveDirection magnitude carries the throttle, so WalkSpeed stays the
	-- server's number and is never written from here. A negative fraction points
	-- the vector backwards along the heading and AutoRotate swings the vehicle
	-- to face where it is actually going.
	local fraction = topSpeed > 0 and math.clamp(currentSpeed / topSpeed, -1, 1) or 0
	humanoid:Move(Vector3.new(-math.sin(heading), 0, -math.cos(heading)) * fraction, false)
end)

-- Weapons need to know where the kart is pointing without re-deriving it from a
-- transform the solver may be mid-way through resolving.
_G.ChompHeading = function(): number
	return heading
end
