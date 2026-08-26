--!strict
--[[
	TargetReticle — CHAIN-COMBAT (D-CHOMP-054)

	The cannon's target marker: RED while it is tracking, GREEN when it locks.

	The server owns the lock and writes ChompLockState and ChompLockTarget onto
	the character. This draws them and decides nothing — a client that could
	declare its own target could declare its own hit.

	Red and green are the obvious choice and also the worst pair for a
	colour-blind player, so colour is never the only signal: tracking is a thin
	broken ring that spins, locked is a thick steady ring with corner brackets
	that snaps to size. Shape and motion carry the same message.
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
gui.Size = UDim2.new(0, 150, 0, 150)
gui.AlwaysOnTop = true
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

-- Four brackets rather than a circle: brackets read as "targeting" instantly,
-- and closing them inward is a motion everyone already understands.
local brackets: { Frame } = {}
for i = 1, 4 do
	local b = Instance.new("Frame")
	b.Size = UDim2.new(0, 34, 0, 6)
	b.BorderSizePixel = 0
	b.BackgroundColor3 = TRACKING
	b.Parent = gui
	table.insert(brackets, b)

	local stem = Instance.new("Frame")
	stem.Size = UDim2.new(0, 6, 0, 34)
	stem.BorderSizePixel = 0
	stem.BackgroundColor3 = TRACKING
	stem.Parent = b
end

local function ghostByName(name: string): Model?
	local folder = workspace:FindFirstChild("Ghosts")
	local found = folder and folder:FindFirstChild(name)
	return (found and found:IsA("Model")) and found or nil
end

local t = 0
RunService.RenderStepped:Connect(function(dt)
	t += dt
	local character = player.Character
	if not character then gui.Enabled = false return end

	local state = character:GetAttribute("ChompLockState")
	local targetName = character:GetAttribute("ChompLockTarget")
	if typeof(state) ~= "string" or state == "none" or typeof(targetName) ~= "string" or targetName == "" then
		gui.Enabled = false
		return
	end

	local ghost = ghostByName(targetName)
	if not ghost or ghost:GetAttribute("Dead") == true then
		gui.Enabled = false
		return
	end

	gui.Enabled = true
	gui.Adornee = ghost.PrimaryPart or ghost:FindFirstChildWhichIsA("BasePart")

	local locked = state == "locked"
	local colour = locked and LOCKED or TRACKING
	-- Locked closes the brackets in and holds them still. Tracking leaves them
	-- wide and turning, so the two states differ in MOTION as well as colour.
	local spread = locked and 34 or (46 + math.sin(t * 6) * 5)
	local spin = locked and 0 or t * 60

	for i, b in brackets do
		local corner = i - 1
		local x = (corner % 2 == 0) and -1 or 1
		local y = (corner < 2) and -1 or 1
		b.BackgroundColor3 = colour
		b.Rotation = spin
		b.AnchorPoint = Vector2.new(x < 0 and 0 or 1, y < 0 and 0 or 1)
		b.Position = UDim2.new(0.5, x * spread, 0.5, y * spread)
		local stem = b:FindFirstChildWhichIsA("Frame")
		if stem then
			stem.BackgroundColor3 = colour
			stem.AnchorPoint = b.AnchorPoint
			stem.Position = UDim2.new(x < 0 and 0 or 1, 0, y < 0 and 0 or 1, 0)
		end
	end
end)
