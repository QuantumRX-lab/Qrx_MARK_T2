--!strict
-- Server-owned arrival and deployment lifecycle.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage:WaitForChild("ChompConfig"))
local Launch = Config.Launch
local homeCentre: Vector3? = nil

local function findHome(): Vector3?
	for _, pad in CollectionService:GetTagged("Chomp_Garage") do
		if pad:IsA("BasePart") and pad:GetAttribute("Home") == true then
			return Vector3.new(pad.Position.X, 0, pad.Position.Z)
		end
	end
	return nil
end

local function publish(player: Player, character: Model, state: string)
	player:SetAttribute("ChompSessionState", state)
	character:SetAttribute("ChompSessionState", state)
	character:SetAttribute("ChompInLaunchBay", state == Launch.BayState)
end

local function enterBay(player: Player, character: Model)
	publish(player, character, Launch.BayState)
	character:SetAttribute("ChompDeployAt", 0)
	character:SetAttribute("ChompProtectedUntil", 0)
	character:SetAttribute("ChompLaunchMessage", "CHOOSE VEHICLE + LOADOUT")
end

local function deploy(player: Player, character: Model)
	if player:GetAttribute("ChompSessionState") ~= Launch.BayState then return end
	publish(player, character, Launch.DeployingState)
	character:SetAttribute("ChompDeployAt", os.clock())
	character:SetAttribute("ChompLaunchMessage", "DEPLOYING")
	task.delay(Launch.DeploymentSeconds, function()
		if player.Character ~= character or not character.Parent then return end
		publish(player, character, Launch.ActiveState)
		character:SetAttribute("ChompProtectedUntil", os.clock() + Launch.SpawnProtectionSeconds)
		character:SetAttribute("ChompLaunchMessage", "CHOMP!")
		character:SetAttribute("ChompDeployedAt", os.clock())
	end)
end

local function watch(player: Player, character: Model)
	enterBay(player, character)
end

Players.PlayerAdded:Connect(function(player)
	player:SetAttribute("ChompSessionState", Launch.BayState)
	player.CharacterAdded:Connect(function(character) watch(player, character) end)
	if player.Character then watch(player, player.Character) end
end)

RunService.Heartbeat:Connect(function()
	homeCentre = homeCentre or findHome()
	if not homeCentre then return end
	for _, player in Players:GetPlayers() do
		if player:GetAttribute("ChompSessionState") ~= Launch.BayState then continue end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not character or not root then continue end
		local flat = Vector3.new(root.Position.X, 0, root.Position.Z)
		local fromHome = flat - homeCentre
		if fromHome.Magnitude >= Launch.ExitRadiusStuds
			and flat.Magnitude < homeCentre.Magnitude then
			deploy(player, character)
		end
	end
end)

print("[PlayerSessionService] protected launch bay and deployment live")
