--!strict
--[[
	VehicleAppearance — CHAIN-VEHICLE

	Keeps the driver's own avatar invisible on their own screen.

	VehicleService already sets Transparency = 1 on every avatar part, and that
	is the right thing for what everyone else sees. It is not sufficient for
	what YOU see. Roblox renders the local player's own character through
	LocalTransparencyModifier, which the default PlayerModule's transparency
	controller writes to as the camera moves — so the legs kept showing through
	the chassis on the driving client while looking correctly hidden to anyone
	watching (D-CHOMP-035).

	Two authorities writing one visual property, which is the same shape of bug
	as D-CHOMP-023 and D-CHOMP-025 in a different register. The fix is the same:
	be the last writer, every frame, and stop guessing.

	The vehicle itself is excluded, since it is parented into the character.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local character: Model? = nil
local hidden: { BasePart } = {}
local decals: { Decal | Texture } = {}

local function isVehicle(d: Instance): boolean
	local vehicle = character and character:FindFirstChild("Vehicle")
	return vehicle ~= nil and (d == vehicle or d:IsDescendantOf(vehicle))
end

-- The head shows through the glass canopy (D-CHOMP-037). The server leaves it
-- visible; this has to agree, or the driver is invisible on their own screen
-- and visible to everyone else — the same split D-CHOMP-035 was about.
--
-- Unconditional rather than config-gated: if the server decides to hide the
-- head, its Transparency does that on every screen, and leaving the modifier
-- alone here costs nothing.
local function isDriverHead(d: Instance): boolean
	if d:IsA("BasePart") and d.Name == "Head" then
		return true
	end
	if (d:IsA("Decal") or d:IsA("Texture")) and d.Parent and d.Parent.Name == "Head" then
		return true
	end
	return false
end

local function collect()
	table.clear(hidden)
	table.clear(decals)
	if not character then return end
	for _, d in character:GetDescendants() do
		local mine = isVehicle(d) or isDriverHead(d)
		if d:IsA("BasePart") then
			if mine then
				-- The vehicle is parented in AFTER the character spawns, so an
				-- early sweep can catch its parts. Clearing the modifier here
				-- matters: dropping a part from the list stops us writing to it
				-- but leaves whatever we last wrote, which would be an
				-- invisible vehicle.
				d.LocalTransparencyModifier = 0
			else
				table.insert(hidden, d)
			end
		elseif d:IsA("Decal") or d:IsA("Texture") then
			if not mine then
				table.insert(decals, d)
			end
		end
	end
end

local function onCharacter(c: Model)
	character = c
	collect()
	-- Parts and accessories arrive late, so recollect rather than assume the
	-- first sweep saw everything.
	c.DescendantAdded:Connect(function()
		task.defer(collect)
	end)

	-- The run cycle is stopped server-side too, but a track that was already
	-- playing when the script was disabled keeps going until it is told not to.
	local humanoid = c:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if animator then
		for _, track in animator:GetPlayingAnimationTracks() do
			track:Stop(0)
		end
	end
end

if player.Character then
	onCharacter(player.Character)
end
player.CharacterAdded:Connect(onCharacter)

-- Last writer wins, so write last. Fifteen parts a frame is nothing, and the
-- alternative is racing a controller whose update schedule is not ours to know.
RunService.RenderStepped:Connect(function()
	for _, part in hidden do
		if part.LocalTransparencyModifier ~= 1 then
			part.LocalTransparencyModifier = 1
		end
	end
	for _, decal in decals do
		if decal.Transparency ~= 1 then
			decal.Transparency = 1
		end
	end
end)
