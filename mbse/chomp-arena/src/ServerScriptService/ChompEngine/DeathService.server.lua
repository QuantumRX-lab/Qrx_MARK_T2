--!strict
--[[
	DeathService — CHAIN-COMBAT (D-CHOMP-066)

	Being caught, made into an event.

	Until now nothing in the game handled death at all. The humanoid died, the
	default five-second Roblox respawn ran, and the world-locked camera sat on
	the corpse the whole time with no message. A child went from fine to frozen
	to back-at-the-garage with an empty belt and no idea what had happened - and
	since a pack could land its whole wave of damage in about a second, "fine"
	and "dead" were often the same moment.

	That is the single most likely place for a session to end in tears, so it
	gets the same treatment every other important moment gets: a burst you can
	see, a stamp the HUD can read, and a countdown that says you are coming
	back.

	Combat.RespawnSeconds has been sitting in ChompConfig unread since the
	beginning. Four seconds instead of five is not the point; being TOLD is.

	This amends D-CHOMP-051's "an ordinary Roblox death and respawn", which was
	decided before waves existed and before anything could swarm you.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage:WaitForChild("ChompConfig"))
local P = Config.Palette

Players.RespawnTime = Config.Combat.RespawnSeconds

-- The same fly-apart the ghosts get, in your colours. A kart that simply stops
-- is a freeze; one that comes to pieces is a death, and the difference is
-- whether the player believes something happened to them (D-CHOMP-054).
local function burst(at: Vector3)
	for i = 1, 12 do
		local shard = Instance.new("Part")
		shard.Size = Vector3.new(2.2, 2.2, 2.2)
		shard.Shape = Enum.PartType.Ball
		shard.Color = i <= 4 and P.Danger or P.Gold
		shard.Material = Enum.Material.Neon
		shard.Transparency = 0.2
		shard.CanCollide = false
		shard.CanQuery = false
		shard.CastShadow = false
		shard.Position = at + Vector3.new(
			math.random(-30, 30) / 10, math.random(-10, 40) / 10, math.random(-30, 30) / 10)
		shard.AssemblyLinearVelocity = Vector3.new(
			math.random(-70, 70), math.random(30, 80), math.random(-70, 70))
		CollectionService:AddTag(shard, "Chomp_Decor")
		shard.Parent = Workspace
		Debris:AddItem(shard, 1.8)
	end
end

local function watch(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then return end
	humanoid.Died:Connect(function()
		-- The stamp is what the HUD counts down from. The server owns it, like
		-- every other value the HUD reads (CHOMP-SYS-030).
		character:SetAttribute("ChompDiedAt", os.clock())
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then burst(root.Position) end
	end)
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(watch)
	if player.Character then watch(player.Character) end
end)

print(("[DeathService] respawn %.1fs, announced"):format(Config.Combat.RespawnSeconds))
