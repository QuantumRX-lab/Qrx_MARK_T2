--!strict
--[[
	TargetReticle — CHAIN-COMBAT (D-CHOMP-059)

	A red crosshair that snaps onto whatever the turret has found, and turns
	green the moment it locks.

	The server owns the lock and writes ChompLockState and ChompLockTarget onto
	the character. This draws them and decides nothing — a client that could
	declare its own target could declare its own hit.

	Red and green is the obvious pair and the worst one for a colour-blind
	player, so colour is never the only signal. Tracking is a crosshair with a
	GAP at the centre and arms that breathe; locked closes the gap, adds a centre
	dot and holds still. The shape says it, the motion says it, and the colour
	agrees with both.

	Snapping rather than easing is deliberate. A reticle that slides between
	targets looks smooth and tells you nothing about the moment acquisition
	happened, which is the only moment that matters.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("ChompConfig"))
local P = Config.Palette

local TRACKING = P.Danger
local LOCKED = Color3.fromRGB(126, 217, 87)

local player = Players.LocalPlayer

local gui = Instance.new("BillboardGui")
gui.Name = "ChompReticle"
gui.Size = UDim2.new(0, 190, 0, 190)
gui.AlwaysOnTop = true
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local function bar(): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.BackgroundColor3 = TRACKING
	f.Parent = gui
	return f
end

-- Four arms and a centre dot. Arms, not a circle: a cross points AT something.
local arms = { bar(), bar(), bar(), bar() }
local dot = bar()
dot.Size = UDim2.new(0, 8, 0, 8)
dot.Position = UDim2.new(0.5, 0, 0.5, 0)

local function findTarget(name: string): Instance?
	local ghosts = workspace:FindFirstChild("Ghosts")
	local ghost = ghosts and ghosts:FindFirstChild(name)
	if ghost then return ghost end
	-- Friendly fire: the target may be another player's character, which is
	-- named after the player.
	local other = Players:FindFirstChild(name)
	if other and other:IsA("Player") then return other.Character end
	return workspace:FindFirstChild(name)
end

local t = 0
RunService.RenderStepped:Connect(function(dt)
	t += dt
	local character = player.Character
	if not character then gui.Enabled = false return end

	local state = character:GetAttribute("ChompLockState")
	local targetName = character:GetAttribute("ChompLockTarget")
	if typeof(state) ~= "string" or state == "none"
		or typeof(targetName) ~= "string" or targetName == "" then
		gui.Enabled = false
		return
	end

	local target = findTarget(targetName)
	if not target or (target:IsA("Model") and target:GetAttribute("Dead") == true) then
		gui.Enabled = false
		return
	end

	local adornee = target:IsA("Model")
		and (target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart"))
		or target
	if not adornee then gui.Enabled = false return end

	gui.Enabled = true
	gui.Adornee = adornee

	local locked = state == "locked"
	local colour = locked and LOCKED or TRACKING
	-- Tracking breathes and holds a gap; locked closes to a tight, still cross.
	local gap = locked and 16 or (30 + math.sin(t * 7) * 4)
	local length = locked and 30 or 22
	local thickness = locked and 5 or 3

	for i, arm in arms do
		arm.BackgroundColor3 = colour
		local vertical = i > 2
		local sign = (i % 2 == 0) and 1 or -1
		if vertical then
			arm.Size = UDim2.new(0, thickness, 0, length)
			arm.Position = UDim2.new(0.5, 0, 0.5, sign * (gap + length / 2))
		else
			arm.Size = UDim2.new(0, length, 0, thickness)
			arm.Position = UDim2.new(0.5, sign * (gap + length / 2), 0.5, 0)
		end
	end

	dot.BackgroundColor3 = colour
	dot.Visible = locked
end)
