--!strict
--[[
	MovementService — CHAIN-VEHICLE, CHOMP-SYS-002

	The server owns the NUMBERS. The client applies them to the character it
	already owns.

	This is a correction (D-CHOMP-018). The first version rotated the character
	from the server every heartbeat, which fought the client's network
	ownership of its own character and produced the jitter that made the game
	feel broken. Roblox's replication model does not allow a server to smoothly
	drive a player's own character, and pretending otherwise does not make the
	game more secure — it just makes it feel bad.

	What the server keeps:
	  * it decides the speed and turn rate for a chassis and its upgrades
	  * it writes them onto the character as attributes, and re-asserts them
	  * it clamps WalkSpeed, so a client raising its own is corrected
	  * it watches horizontal travel per second and flags the impossible

	What the server does NOT do: write the character's CFrame.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("ChompConfig"))

type Tracked = {
	chassis: string,
	lastPosition: Vector3?,
	lastCheck: number,
	strikes: number,
}

local tracked: { [Player]: Tracked } = {}

-- TODO(CHAIN-ECONOMY): swap to Progression.effectiveStats once implemented,
-- so upgrades apply. Chassis base is correct for an unupgraded player.
local function statsFor(chassisId: string): (number, number)
	local chassis = Config.Chassis[chassisId] or Config.Chassis[Config.StartingChassis]
	return chassis.BaseSpeed, chassis.BaseTurn
end

local function apply(player: Player, character: Model)
	local record = tracked[player]
	if not record then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local speed, turn = statsFor(record.chassis)
	humanoid.WalkSpeed = speed
	-- AutoRotate turns the character to face its MoveDirection, and since
	-- D-CHOMP-025 that direction IS the vehicle's heading — the client hands the
	-- engine a heading vector rather than writing the transform itself. Facing is
	-- still the vehicle's; the engine is just the thing that applies it.
	humanoid.AutoRotate = true
	humanoid.JumpPower = 0
	humanoid.UseJumpPower = true

	-- The client reads these; it never chooses them.
	character:SetAttribute("ChompSpeed", speed)
	character:SetAttribute("ChompTurn", turn)
end

local function onCharacter(player: Player, character: Model)
	tracked[player] = tracked[player] or { chassis = Config.StartingChassis, lastCheck = 0, strikes = 0 }
	tracked[player].lastPosition = nil
	apply(player, character)
end

Players.PlayerAdded:Connect(function(player)
	tracked[player] = { chassis = Config.StartingChassis, lastCheck = 0, strikes = 0 }
	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	if player.Character then onCharacter(player, player.Character) end
end)

Players.PlayerRemoving:Connect(function(player)
	tracked[player] = nil
end)

-- Re-assert and sanity-check. WalkSpeed is the most exploited property in
-- Roblox, so it is enforced on a timer rather than set once (CHOMP-SYS-002).
RunService.Heartbeat:Connect(function()
	local now = os.clock()
	for player, record in tracked do
		local character = player.Character
		if not character then continue end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not (humanoid and root) then continue end

		if now - record.lastCheck < 0.25 then continue end
		local elapsed = now - record.lastCheck
		record.lastCheck = now

		local speed = statsFor(record.chassis)
		if humanoid.WalkSpeed ~= speed then
			apply(player, character)
		end

		local previous = record.lastPosition
		record.lastPosition = root.Position
		if previous then
			local flat = (root.Position - previous) * Vector3.new(1, 0, 1)
			local travelled = flat.Magnitude / elapsed
			-- 1.6x covers slope, knockback and ordinary network variance.
			if travelled > speed * 1.6 then
				record.strikes += 1
				if record.strikes % 8 == 0 then
					warn(("[MovementService] %s travelling %.1f studs/s against a limit of %.1f")
						:format(player.Name, travelled, speed))
				end
			else
				record.strikes = math.max(0, record.strikes - 1)
			end
		end
	end
end)

print("[MovementService] running — server owns the numbers, the client owns its own character")
