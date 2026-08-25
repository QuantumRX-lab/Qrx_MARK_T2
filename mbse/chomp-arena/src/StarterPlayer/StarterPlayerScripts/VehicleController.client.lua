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

-- Written by InputController each frame. Steering intent only, -1 .. 1.
local state = _G.ChompInput or { steer = 0, flip = false }
_G.ChompInput = state

local smoothedSteer = 0
local flipRemaining = 0
local flipDirection = 1

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

	local _, turnRate = stats()

	-- Ramp the steering instead of applying it raw. Straight-through input is
	-- twitchy at any turn rate high enough to make a junction.
	local ramp = math.clamp(dt / MOVE.SteerRampSeconds, 0, 1)
	smoothedSteer += (state.steer - smoothedSteer) * ramp

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

	if yaw ~= 0 then
		root.CFrame = root.CFrame * CFrame.Angles(0, yaw, 0)
	end

	-- Always driving forward (D-CHOMP-015). Move() is given a flat world
	-- vector so slopes do not steal speed on the ramp.
	local facing = root.CFrame.LookVector
	local flat = Vector3.new(facing.X, 0, facing.Z)
	if flat.Magnitude > 0.001 then
		humanoid:Move(flat.Unit, false)
	end
end)
