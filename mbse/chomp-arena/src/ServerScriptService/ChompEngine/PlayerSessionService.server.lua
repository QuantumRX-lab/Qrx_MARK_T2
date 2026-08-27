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

--[[
	Wait for the profile, but never forever (D-CHOMP-066).

	This loop had no timeout and no fallback. ChompProfileReady has exactly one
	writer, ProfileService, so anything that stopped that script from setting it
	- a DataStore outage, an error thrown inside load(), or the file simply not
	being in the build - left every player parked on LOADING GARAGE for the rest
	of the session. There was no message, no retry and no way out, and the bay
	is the first thing anyone sees.

	It is not a hypothetical: ProfileService was untracked in git for a day, so
	every clean checkout of this branch built exactly that place.

	On timeout the player enters the bay DEGRADED rather than not at all. They
	can drive, fight and bank for the session; they cannot spend, because
	spending money that will not be saved is worse than not spending it.
	LAUNCH-READINESS section 2 phase A calls for the read-only practice bay,
	and this is it.
]]
local function watch(player: Player, character: Model)
	publish(player, character, Launch.LoadingState)
	task.spawn(function()
		local deadline = os.clock() + Config.Profile.ReadyTimeoutSeconds
		while player.Parent and player:GetAttribute("ChompProfileReady") ~= true do
			if os.clock() >= deadline then
				-- Degraded, and SAID so. A silent default profile is how someone
				-- concludes their progress was deleted.
				player:SetAttribute("ChompProfileSaveBlocked", true)
				player:SetAttribute("ChompProfileDegraded", true)
				warn(("[PlayerSessionService] %s waited %.0fs for a profile; entering the bay read-only")
					:format(player.Name, Config.Profile.ReadyTimeoutSeconds))
				break
			end
			task.wait(0.25)
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
