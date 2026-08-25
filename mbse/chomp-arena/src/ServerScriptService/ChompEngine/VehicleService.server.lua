--!strict
--[[
	VehicleService — CHAIN-VEHICLE

	Puts the chassis on the player. Until now the four delivered models existed
	and nothing consumed them, so every playtest was driven as a plain avatar.

	The character stays the thing the engine moves. The chassis is built from
	its Luau spec (D-CHOMP-022), welded to HumanoidRootPart, and the avatar's
	own parts are made invisible. Nothing about locomotion changes: the client
	still owns its heading and hands it to Move() (D-CHOMP-025), and the server
	still owns the numbers (D-CHOMP-018). This is appearance, deliberately —
	putting a vehicle on the player should not quietly become a second physics
	authority, which is the mistake this project has now made twice.

	KNOWN LIMIT: collision is still the humanoid's, which is about two studs
	wide, while the chassis is nearer five. Corridors are eight, so you only
	notice it hugging a wall. Giving the vehicle its own collision body is a
	real change to how the character is built and is not worth doing before the
	camera acceptance run says the geometry survives at all.
]]

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("ChompConfig"))
local VehicleFactory = require(ServerStorage:WaitForChild("ChompTools"):WaitForChild("VehicleFactory"))

local SPECS = ServerStorage:WaitForChild("ChompTools"):WaitForChild("VehicleSpecs")

local function specFor(chassisId: string)
	local module = SPECS:FindFirstChild(chassisId)
	if module and module:IsA("ModuleScript") then
		return require(module)
	end
	return nil
end

-- The avatar still exists and is still what moves; it is simply not drawn.
local function hideAvatar(character: Model)
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") then
			d.Transparency = 1
		elseif d:IsA("Decal") or d:IsA("Texture") then
			d.Transparency = 1
		elseif d:IsA("Accessory") then
			d:Destroy()
		end
	end
end

local function fitVehicle(player: Player, character: Model)
	if character:FindFirstChild("Vehicle") then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (humanoid and root) then return end

	local chassisId = character:GetAttribute("ChompChassis") or Config.StartingChassis
	local spec = specFor(chassisId :: string)
	if not spec then
		warn(("[VehicleService] no spec for chassis '%s'; %s stays a plain avatar")
			:format(tostring(chassisId), player.Name))
		return
	end

	local ok, model = pcall(function()
		return VehicleFactory.build(spec)
	end)
	if not ok or not model then
		warn(("[VehicleService] could not build '%s': %s"):format(tostring(chassisId), tostring(model)))
		return
	end

	model.Name = "Vehicle"

	-- Massless and non-colliding throughout, so bolting a five-stud body onto
	-- the character cannot change how the character moves.
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.Massless = true
			d.CanQuery = false
			d.CanTouch = false
		end
	end

	hideAvatar(character)

	-- Sit the chassis on the ground the humanoid is standing on, not on the
	-- root part's centre, which floats at hip height.
	local drop = root.Size.Y / 2 + humanoid.HipHeight
	model:PivotTo(root.CFrame * CFrame.new(0, -drop, 0))

	local primary = model.PrimaryPart
	if not primary then
		warn("[VehicleService] built model has no PrimaryPart; the factory should always set one")
		model:Destroy()
		return
	end

	local weld = Instance.new("WeldConstraint")
	weld.Name = "ChompVehicleWeld"
	weld.Part0 = root
	weld.Part1 = primary
	weld.Parent = primary

	model.Parent = character
end

local function onCharacter(player: Player, character: Model)
	-- CharacterAdded can beat the descendants into existence.
	if not character:FindFirstChild("HumanoidRootPart") then
		character:WaitForChild("HumanoidRootPart", 10)
	end
	fitVehicle(player, character)
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	if player.Character then
		onCharacter(player, player.Character)
	end
end)

-- A player already present when this script starts never fires PlayerAdded.
for _, player in Players:GetPlayers() do
	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
end

print(("[VehicleService] running - chassis models are worn, collision is still the humanoid's"))
