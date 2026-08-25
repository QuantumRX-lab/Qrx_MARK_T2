--!strict
--[[
	MovementService — CHAIN-VEHICLE, CHOMP-SYS-001 and CHOMP-SYS-002

	The vehicle is the standard character controller in a costume, never a
	physics vehicle (D-CHOMP-002). Locomotion here is: the server holds the
	speed and turn rate, the client sends steering intent only, and the server
	rotates the character and drives it forward every heartbeat.

	Always driving forward is the control scheme, not a placeholder
	(D-CHOMP-015). There is no accelerator and no brake.

	WalkSpeed is the single most exploited property in Roblox, so it is
	re-asserted from server state on a timer rather than set once.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("ChompConfig"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))

local MOVE = Config.Movement

type Intent = {
	steer: number,
	flipUntil: number,
	flipFrom: CFrame?,
	chassis: string,
	lastAssert: number,
}

local intents: { [Player]: Intent } = {}
local allowInput = Remotes.makeLimiter(Remotes.Limits.SetInputDirection)

-- TODO(CHAIN-ECONOMY): once Progression.effectiveStats is implemented, take
-- speed and turn from it so upgrades apply. Until then these are the chassis
-- base values, which is correct for a player with no upgrades.
local function statsFor(chassisId: string)
	local chassis = Config.Chassis[chassisId] or Config.Chassis[Config.StartingChassis]
	return chassis.BaseSpeed, chassis.BaseTurn
end

local function intentFor(player: Player): Intent
	local intent = intents[player]
	if not intent then
		intent = {
			steer = 0,
			flipUntil = 0,
			flipFrom = nil,
			chassis = Config.StartingChassis,
			lastAssert = 0,
		}
		intents[player] = intent
	end
	return intent
end

Remotes.SetInputDirection.OnServerEvent:Connect(function(player, payload)
	if not allowInput(player) then return end

	-- Validate shape before anything else. A client may send whatever it likes.
	if typeof(payload) ~= "Vector2" then return end
	if payload.X ~= payload.X or payload.Y ~= payload.Y then return end -- NaN
	if math.abs(payload.X) > 1.001 then return end

	local intent = intentFor(player)
	intent.steer = math.clamp(payload.X, -1, 1)

	if payload.Y >= 0.5 and os.clock() >= intent.flipUntil then
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local _, turn = statsFor(intent.chassis)
			local agile = false -- TODO(CHAIN-ECONOMY): read Agility level
			local duration = agile and MOVE.ReverseFlipSecondsAgile or MOVE.ReverseFlipSeconds
			intent.flipFrom = root.CFrame
			intent.flipUntil = os.clock() + duration
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	intents[player] = nil
end)

RunService.Heartbeat:Connect(function(dt)
	local now = os.clock()
	for player, intent in intents do
		local character = player.Character
		if not character then continue end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not (humanoid and root) then continue end

		local speed, turnRate = statsFor(intent.chassis)

		-- Re-assert server-held movement values (CHOMP-SYS-002). A client that
		-- sets its own WalkSpeed is corrected well inside the 1 second the
		-- requirement allows.
		if now - intent.lastAssert > 0.25 then
			if humanoid.WalkSpeed ~= speed then
				humanoid.WalkSpeed = speed
			end
			humanoid.AutoRotate = false
			intent.lastAssert = now
		end

		if now < intent.flipUntil and intent.flipFrom then
			-- A flip is a rotation the server owns outright; steering is
			-- ignored until it completes, so a flip cannot be steered out of.
			local duration = MOVE.ReverseFlipSeconds
			local elapsed = duration - (intent.flipUntil - now)
			local alpha = math.clamp(elapsed / duration, 0, 1)
			root.CFrame = CFrame.new(root.Position)
				* (intent.flipFrom - intent.flipFrom.Position)
				* CFrame.Angles(0, math.pi * alpha, 0)
		else
			intent.flipFrom = nil
			if intent.steer ~= 0 then
				local yaw = -math.rad(turnRate) * intent.steer * dt
				root.CFrame = CFrame.new(root.Position)
					* (root.CFrame - root.Position)
					* CFrame.Angles(0, yaw, 0)
			end
		end

		-- Always forward. This is the game, not a placeholder.
		local facing = root.CFrame.LookVector
		humanoid:Move(Vector3.new(facing.X, 0, facing.Z), false)
	end
end)

print("[MovementService] running — server-held speed and turn, always forward")
