--!strict
--[[
	ShieldEffect — CHAIN-COMBAT (D-CHOMP-051)

	The shield you can see: a ring of light around the kart that turns, pulses
	and shimmers while it is up.

	Built on the client because it decides nothing. The server owns whether the
	shield is active and writes ChompShieldUntil onto the character; this reads
	that and draws. A shield that LOOKS active while the server thinks otherwise
	would be a lie, so the only value here is the server's.

	Shimmer is three things out of phase — rotation, a transparency wave running
	round the ring, and a slow rise and fall of the whole thing. One alone reads
	as a spinning prop; together they read as energy.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("ChompConfig"))
local P = Config.Palette

local SEGMENTS = 18
local RADIUS = 7.5
local COLOUR = Color3.fromRGB(126, 217, 87)

local player = Players.LocalPlayer

local rig = Instance.new("Model")
rig.Name = "ChompShieldRig"
rig.Parent = workspace:FindFirstChild("Camera") or workspace

local blades: { BasePart } = {}
for i = 1, SEGMENTS do
	local p = Instance.new("Part")
	p.Name = "ShieldBlade"
	p.Size = Vector3.new(0.45, 3.2, 2.6)
	p.Color = COLOUR
	p.Material = Enum.Material.Neon
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Parent = rig
	table.insert(blades, p)
end

local function hide()
	for _, blade in blades do
		if blade.Transparency < 1 then blade.Transparency = 1 end
	end
end

local t = 0
RunService.RenderStepped:Connect(function(dt)
	t += dt

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (character and root) then hide() return end

	local until_ = (character:GetAttribute("ChompShieldUntil") :: number?) or 0
	local remaining = until_ - os.clock()
	if remaining <= 0 then hide() return end

	-- The last second flickers. A shield about to fail should say so while you
	-- can still do something about it, rather than simply stopping.
	local failing = remaining < 1 and (math.sin(t * 40) > 0)

	local centre = root.Position
	for i, blade in blades do
		local a = (math.pi * 2) * ((i - 1) / SEGMENTS) + t * 1.6
		local wave = math.sin(a * 3 - t * 6)
		local lift = math.sin(t * 2.2) * 0.5

		blade.CFrame = CFrame.new(
			centre.X + math.cos(a) * RADIUS,
			centre.Y - 1.2 + lift + wave * 0.4,
			centre.Z + math.sin(a) * RADIUS
		) * CFrame.Angles(0, -a, 0) * CFrame.Angles(0, 0, wave * 0.25)

		blade.Transparency = failing and 1 or (0.35 + wave * 0.28)
	end
end)
