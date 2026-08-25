--!strict
--[[
	VehicleController — CHAIN-VEHICLE, CHOMP-SYS-001

	Steering runs HERE, on the client that owns its own character.

	It used to run on the server, which wrote root.CFrame every heartbeat. That
	was wrong and it is why the handling felt broken: Roblox gives the client
	network ownership of its own character, so a server writing that same
	transform every frame is two authorities fighting over one value, and the
	result is jitter and rubber-banding. Rotating your own character locally is
	both smooth and correctly replicated.

	The server has not given up authority (D-CHOMP-018). It still owns the
	numbers — speed and turn rate — re-asserts WalkSpeed, and validates that
	the movement the client produced is possible. What moved to the client is
	the application of rotation, not the right to decide how fast you go.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("ChompConfig"))
local MOVE = Config.Movement

local player = Players.LocalPlayer

-- Roblox's default control script drives the same Humanoid this controller
-- does. It calls humanoid:Move() every frame from its own input, and with no
-- key held that call is Vector3.zero — which cancels the forward drive below,
-- so the vehicle only moved while a key was down and never steered. Disabling
-- it makes this the single writer of locomotion.
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

-- Written by InputController each frame. Steering intent only, -1 .. 1.
local state = _G.ChompInput or { steer = 0, throttle = 0, flip = false }
_G.ChompInput = state

local smoothedSteer = 0
local heading = 0          -- world yaw in radians. Ours, not the solver's.
local headingReady = false -- seeded from the character on first frame
local currentSpeed = 0     -- studs/s, ramped by Acceleration and Braking
local flipRemaining = 0
local flipDirection = 1

player.CharacterAdded:Connect(function()
	headingReady = false
	currentSpeed = 0
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

	-- Ramp the steering instead of applying it raw. Straight-through input is
	-- twitchy at any turn rate high enough to make a junction.
	--
	-- Engaging and releasing use different rates (D-CHOMP-032). Committing to a
	-- turn should take a moment; coming out of one should not, because a vehicle
	-- that keeps turning after the key is released is what actually reads as
	-- twitchy.
	local steerTarget = state.steer or 0
	local engaging = math.abs(steerTarget) > math.abs(smoothedSteer)
	local rampSeconds = engaging and MOVE.SteerRampSeconds or MOVE.SteerReleaseSeconds
	local ramp = math.clamp(dt / rampSeconds, 0, 1)
	smoothedSteer += (steerTarget - smoothedSteer) * ramp

	if state.flip and flipRemaining <= 0 then
		flipRemaining = MOVE.ReverseFlipSeconds
		flipDirection = smoothedSteer >= 0 and 1 or -1
	end
	state.flip = false

	local yaw
	if flipRemaining > 0 then
		-- A flip is a fixed rotation over a fixed time. It cannot be steered
		-- out of, which is what makes it a commitment rather than a dodge.
		local slice = math.min(dt, flipRemaining)
		yaw = math.pi * (slice / MOVE.ReverseFlipSeconds) * flipDirection
		flipRemaining -= slice
	else
		yaw = -math.rad(turnRate) * smoothedSteer * dt
	end

	-- The heading is ours; the transform is the engine's (D-CHOMP-025).
	--
	-- This used to write root.CFrame every RenderStepped. That is a third
	-- authority problem, and the physics solver won: the rotation was reverted
	-- on the following step, so yaw never accumulated past a few degrees and the
	-- vehicle drove permanently north into a wall no matter how hard you steered.
	-- Being wedged in that wall made it worse, because the solver was also
	-- resolving penetration every step.
	--
	-- So we never touch the transform. We integrate a heading angle and hand it
	-- to Move() as a direction; AutoRotate turns the character to match. Move()
	-- is a request the solver honours rather than a value it has to reconcile.
	heading += yaw

	-- CFrame.Angles(0, h, 0).LookVector is (-sin h, 0, -cos h). Flat by
	-- construction, so slopes cannot steal speed on the ramp (D-CHOMP-015).
	-- Signed throttle from the stick (D-CHOMP-027). Forward drives, back reverses
	-- at a fraction of top speed, centre coasts to a stop over Braking. Releasing
	-- coasts rather than stopping dead, so letting go mid-corner is a decision
	-- rather than a punishment. Acceleration and Braking had been declared in
	-- ChompConfig since the start and unused while speed was constant.
	local demand = state.throttle or 0
	local target = topSpeed * demand
	if demand < 0 then
		target = target * MOVE.ReverseSpeedFraction
	end

	-- Accelerating means moving away from zero; anything else is braking, which
	-- is the stronger rate. Reversing from a forward roll therefore brakes first
	-- and only then picks up speed backwards, which is what a vehicle does.
	local rate = (math.abs(target) > math.abs(currentSpeed)) and MOVE.Acceleration or MOVE.Braking
	if currentSpeed < target then
		currentSpeed = math.min(target, currentSpeed + rate * dt)
	else
		currentSpeed = math.max(target, currentSpeed - rate * dt)
	end

	-- MoveDirection magnitude scales speed, which is how analog input works, so
	-- the throttle rides on the vector length rather than on WalkSpeed. WalkSpeed
	-- stays the server's number and is never written from here. A negative
	-- fraction points the vector backwards along the heading, and AutoRotate then
	-- swings the vehicle to face where it is actually going — which is what makes
	-- holding back read as "turn around" rather than as moonwalking.
	local fraction = topSpeed > 0 and math.clamp(currentSpeed / topSpeed, -1, 1) or 0
	humanoid:Move(Vector3.new(-math.sin(heading), 0, -math.cos(heading)) * fraction, false)
end)
