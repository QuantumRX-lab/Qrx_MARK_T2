--!strict
--[[
	VehicleController — CHAIN-VEHICLE, CHOMP-SYS-001

	Grid driving (D-CHOMP-033). A direction IS the drive command: hold one and
	the vehicle faces that way and goes. Stopped, it snaps instantly. Moving, it
	turns at the chassis turn rate. Release and it coasts to a stop.

	That is how Pac-Man works, and it is the point. The scheme it replaces had a
	throttle and continuous steering, which meant reorienting in a dead end was a
	three-point turn, and lining a corridor up before committing to it was not
	possible at all. On an 8-stud grid, direction is the only steering input that
	means anything.

	The camera never rotates (D-CHOMP-016), so a direction on the keys or on the
	stick is always the same direction on screen. That is what makes an absolute
	scheme legible to a seven-year-old: left is left, not "left relative to
	something that just spun".

	Movement runs HERE, on the client that owns its own character, and it never
	writes a transform. The client integrates a heading and hands it to Move();
	the engine owns the transform and the solver has nothing to fight over
	(D-CHOMP-025). The server still owns the numbers — speed and turn rate — and
	validates the result (D-CHOMP-018).
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
local NORTH, WEST, SOUTH, EAST = 0, math.pi / 2, math.pi, -math.pi / 2
local TWO_PI = math.pi * 2
local PRESSED = 0.5   -- a stick past this counts as a direction, not a nudge

local heading = 0
local headingReady = false
local currentSpeed = 0
local desired: number? = nil     -- the direction being held, if any
local desiredAxis: string? = nil -- "x" or "z", so the newer press wins
local prevSteer = 0
local prevThrottle = 0

player.CharacterAdded:Connect(function()
	headingReady = false
	currentSpeed = 0
	desired, desiredAxis = nil, nil
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

-- Which way is being asked for, or nil for "nothing held, coast".
--
-- The most recent press wins, so cutting a corner by rolling from one key onto
-- another does what you meant rather than averaging the two into a diagonal
-- that no corridor can accept.
local function updateDesired(steer: number, throttle: number)
	local steerOn = math.abs(steer) > PRESSED
	local throttleOn = math.abs(throttle) > PRESSED
	local steerNew = steerOn and math.abs(prevSteer) <= PRESSED
	local throttleNew = throttleOn and math.abs(prevThrottle) <= PRESSED

	if steerNew then
		desired, desiredAxis = (steer > 0 and EAST or WEST), "x"
	elseif throttleNew then
		desired, desiredAxis = (throttle > 0 and NORTH or SOUTH), "z"
	elseif desiredAxis == "x" and not steerOn then
		-- the key we were following was let go; fall back to the other if held
		desired, desiredAxis = throttleOn and (throttle > 0 and NORTH or SOUTH) or nil,
			throttleOn and "z" or nil
	elseif desiredAxis == "z" and not throttleOn then
		desired, desiredAxis = steerOn and (steer > 0 and EAST or WEST) or nil,
			steerOn and "x" or nil
	elseif not steerOn and not throttleOn then
		desired, desiredAxis = nil, nil
	end

	prevSteer, prevThrottle = steer, throttle
end

-- Shortest signed angle from a to b, in (-pi, pi].
local function shortestTurn(from: number, to: number): number
	return (to - from + math.pi) % TWO_PI - math.pi
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

	updateDesired(state.steer or 0, state.throttle or 0)

	if desired then
		if math.abs(currentSpeed) < MOVE.SnapBelowSpeed then
			-- Stopped: snap. Lining a corridor up before committing to it should
			-- cost nothing, and a three-point turn in a dead end is not a skill
			-- anyone wants to teach a seven-year-old.
			heading = desired
		else
			-- Moving: turn at the chassis rate, so a direction press is a
			-- commitment rather than a teleport. A 180 falls out of this for
			-- free — it is just the opposite direction — which is why the old
			-- double-tap flip is gone.
			local diff = shortestTurn(heading, desired)
			local step = math.rad(turnRate) * dt
			heading = math.abs(diff) <= step and desired or heading + (diff > 0 and step or -step)
		end
	end

	-- Holding a direction is the throttle. Releasing coasts over Braking rather
	-- than stopping dead, so letting go mid-corner is a decision, not a
	-- punishment.
	local target = desired and topSpeed or 0
	local rate = (target > currentSpeed) and MOVE.Acceleration or MOVE.Braking
	if currentSpeed < target then
		currentSpeed = math.min(target, currentSpeed + rate * dt)
	else
		currentSpeed = math.max(target, currentSpeed - rate * dt)
	end

	-- MoveDirection magnitude scales speed, which is how analog input works, so
	-- the throttle rides on the vector length rather than on WalkSpeed.
	-- WalkSpeed stays the server's number and is never written from here.
	local fraction = topSpeed > 0 and math.clamp(currentSpeed / topSpeed, 0, 1) or 0
	humanoid:Move(Vector3.new(-math.sin(heading), 0, -math.cos(heading)) * fraction, false)
end)
