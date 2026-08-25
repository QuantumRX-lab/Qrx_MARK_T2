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

-- Scale the SPEC rather than the built model. Scaling afterwards would mean
-- resizing parts that VehicleFactory has already welded to each other, and a
-- weld holds the offset it was made with — the kart would come apart.
--
-- Sizes and offsets scale; rotations do not, being degrees.
local function scaled(spec, k: number)
	if k == 1 then return spec end
	local parts = {}
	for i, p in ipairs(spec.parts) do
		local copy = table.clone(p)
		copy.size = p.size * k
		copy.offset = p.offset * k
		parts[i] = copy
	end
	local out = table.clone(spec)
	out.parts = parts
	return out
end

-- The driver's head shows through the canopy, which is what makes this a kart
-- with someone in it rather than an empty shell (D-CHOMP-037). Codex's spec was
-- built for this all along: the solid lower pod hides the legs and arms, and the
-- glass is only the upper half.
local function isDriverHead(d: Instance): boolean
	if d:IsA("BasePart") and d.Name == "Head" then
		return true
	end
	if (d:IsA("Decal") or d:IsA("Texture")) and d.Parent and d.Parent.Name == "Head" then
		return true
	end
	return false
end

-- The avatar still exists and is still what moves; it is simply not drawn, and
-- not animated.
local function hide(d: Instance)
	if Config.Vehicle and Config.Vehicle.ShowDriverHead and isDriverHead(d) then
		return
	end
	if d:IsA("BasePart") then
		d.Transparency = 1
	elseif d:IsA("Decal") or d:IsA("Texture") then
		d.Transparency = 1
	elseif d:IsA("Accessory") then
		d:Destroy()
	end
end

-- The vehicle is parented INTO the character, so every sweep has to skip it.
-- Missing this on one of the two paths is what made the vehicle vanish along
-- with the avatar: DescendantAdded excluded it, the appearance-loaded sweep did
-- not, and whichever ran last decided (D-CHOMP-036).
local function isVehicle(character: Model, d: Instance): boolean
	local vehicle = character:FindFirstChild("Vehicle")
	return vehicle ~= nil and (d == vehicle or d:IsDescendantOf(vehicle))
end

local function hideAll(character: Model)
	for _, d in character:GetDescendants() do
		if not isVehicle(character, d) then
			hide(d)
		end
	end
end

-- Hiding once at spawn is not enough. Body parts, decals and accessories can
-- arrive after CharacterAdded and after the appearance loads, and a limb that
-- appears a frame late is a leg visibly running inside the chassis.
local function hideAvatar(player: Player, character: Model)
	hideAll(character)

	character.DescendantAdded:Connect(function(d)
		if isVehicle(character, d) then return end
		hide(d)
	end)

	player.CharacterAppearanceLoaded:Once(function(loaded)
		if loaded == character then
			hideAll(character)
		end
	end)

	-- Stop the run cycle. An invisible humanoid still animates, and limbs
	-- swinging inside a welded chassis is what "the legs are still moving"
	-- actually is (D-CHOMP-034).
	local animate = character:FindFirstChild("Animate")
	if animate and animate:IsA("BaseScript") then
		animate.Disabled = true
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if animator then
		for _, track in animator:GetPlayingAnimationTracks() do
			track:Stop(0)
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

	local scale = (Config.Vehicle and Config.Vehicle.Scale) or 1
	local ok, model = pcall(function()
		return VehicleFactory.build(scaled(spec, scale))
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

	hideAvatar(player, character)

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
