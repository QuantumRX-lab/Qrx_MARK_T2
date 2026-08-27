--!strict
-- Server-owned arrival and deployment lifecycle.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage:WaitForChild("ChompConfig"))
local Launch = Config.Launch
local homePad: BasePart? = nil

local function findHome(): BasePart?
	for _, pad in CollectionService:GetTagged("Chomp_Garage") do
		if pad:IsA("BasePart") and pad:GetAttribute("Home") == true then
			return pad
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
	character:SetAttribute("ChompLaunchCountdown", Launch.DeploymentSeconds)
	character:SetAttribute("ChompLaunchMessage", "DEPLOYING")
	for count = Launch.DeploymentSeconds - 1, 1, -1 do
		task.delay(Launch.DeploymentSeconds - count, function()
			if player.Character == character and character.Parent then
				character:SetAttribute("ChompLaunchCountdown", count)
			end
		end)
	end
	task.delay(Launch.DeploymentSeconds, function()
		if player.Character ~= character or not character.Parent then return end
		publish(player, character, Launch.ActiveState)
		character:SetAttribute("ChompProtectedUntil", os.clock() + Launch.SpawnProtectionSeconds)
		character:SetAttribute("ChompLaunchMessage", "CHOMP!")
		character:SetAttribute("ChompLaunchCountdown", 0)
		character:SetAttribute("ChompDeployedAt", os.clock())
	end)
end

local function watch(player: Player, character: Model)
	publish(player, character, Launch.LoadingState)
	task.spawn(function()
		while player.Parent and player:GetAttribute("ChompProfileReady") ~= true do
			player:GetAttributeChangedSignal("ChompProfileReady"):Wait()
		end
		if player.Parent and player.Character == character then enterBay(player, character) end
	end)
end

Players.PlayerAdded:Connect(function(player)
	player:SetAttribute("ChompSessionState", Launch.LoadingState)
	player.CharacterAdded:Connect(function(character) watch(player, character) end)
	if player.Character then watch(player, player.Character) end
end)

RunService.Heartbeat:Connect(function()
	homePad = homePad or findHome()
	if not homePad then return end
	for _, player in Players:GetPlayers() do
		if player:GetAttribute("ChompSessionState") ~= Launch.BayState then continue end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not character or not root then continue end
		-- Use the actual rotated yellow floor, not the much larger ghost sanctuary.
		-- The countdown begins on the first frame the vehicle centre leaves it.
		local localPosition = homePad.CFrame:PointToObjectSpace(root.Position)
		local outside = math.abs(localPosition.X) > homePad.Size.X / 2
			or math.abs(localPosition.Z) > homePad.Size.Z / 2
		if outside then
			deploy(player, character)
		end
	end
end)

print("[PlayerSessionService] protected launch bay and deployment live")
