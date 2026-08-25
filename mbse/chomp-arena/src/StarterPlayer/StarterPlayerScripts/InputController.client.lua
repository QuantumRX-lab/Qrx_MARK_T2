--!strict
--[[
	InputController — CHAIN-UI, CHOMP-SYS-032

	Hold to turn, always driving forward, no buttons (D-CHOMP-015).

	Touch anywhere left of a dead zone to turn left, right to turn right, with
	the turn rate proportional to how far out you hold. There is no origin to
	lose, which is the entire reason this beats a virtual thumbstick for a
	seven-year-old: any touch on the correct side works.

	The client sends INTENT ONLY. It never sends a speed, a position or a turn
	rate — the server owns all three (CHOMP-SYS-002).
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("ChompConfig"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local CONTROLS = Config.Controls

local player = Players.LocalPlayer
local sendRate = Remotes.Limits.SetInputDirection * 0.66  -- stay inside the limit
local sendInterval = 1 / sendRate

local activeTouches: { [any]: Vector2 } = {}
local keyboardSteer = 0
local flipQueued = false
local lastTapSide = 0
local lastTapAt = 0

-- Screen x (0..1) -> steer (-1..1), with a dead zone and a linear ramp to
-- full lock. Both sides held at once cancels to straight, which is what a
-- panicking player does with two thumbs.
local function steerFromFraction(x: number): number
	local fromCentre = x - 0.5
	local dead = CONTROLS.DeadZoneFraction / 2
	local full = CONTROLS.FullLockFraction
	local magnitude = math.abs(fromCentre)
	if magnitude <= dead then
		return 0
	end
	local ramped = math.clamp((magnitude - dead) / (full - dead), 0, 1)
	return ramped * (fromCentre > 0 and 1 or -1)
end

local function currentSteer(): number
	local sum = keyboardSteer
	local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
	if viewport and viewport.X > 0 then
		for _, position in activeTouches do
			sum += steerFromFraction(position.X / viewport.X)
		end
	end
	return math.clamp(sum, -1, 1)
end

-- ── Touch ───────────────────────────────────────────────────────────────
UserInputService.TouchStarted:Connect(function(touch, processed)
	if processed then return end
	activeTouches[touch] = Vector2.new(touch.Position.X, touch.Position.Y)

	local viewport = workspace.CurrentCamera.ViewportSize
	local side = (touch.Position.X / viewport.X) > 0.5 and 1 or -1
	local now = os.clock()
	if side == lastTapSide and now - lastTapAt <= CONTROLS.FlipDoubleTapSeconds then
		flipQueued = true
		lastTapSide, lastTapAt = 0, 0
	else
		lastTapSide, lastTapAt = side, now
	end
end)

UserInputService.TouchMoved:Connect(function(touch)
	if activeTouches[touch] then
		activeTouches[touch] = Vector2.new(touch.Position.X, touch.Position.Y)
	end
end)

local function endTouch(touch)
	activeTouches[touch] = nil
end
UserInputService.TouchEnded:Connect(endTouch)

-- ── Keyboard, for building in Studio ────────────────────────────────────
local heldKeys: { [Enum.KeyCode]: boolean } = {}
local LEFT = { [Enum.KeyCode.A] = true, [Enum.KeyCode.Left] = true }
local RIGHT = { [Enum.KeyCode.D] = true, [Enum.KeyCode.Right] = true }

local function recomputeKeyboard()
	local left = false
	local right = false
	for key in heldKeys do
		if LEFT[key] then left = true end
		if RIGHT[key] then right = true end
	end
	keyboardSteer = (right and 1 or 0) - (left and 1 or 0)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or input.UserInputType ~= Enum.UserInputType.Keyboard then return end
	heldKeys[input.KeyCode] = true
	recomputeKeyboard()

	local side = LEFT[input.KeyCode] and -1 or (RIGHT[input.KeyCode] and 1 or 0)
	if side ~= 0 then
		local now = os.clock()
		if side == lastTapSide and now - lastTapAt <= CONTROLS.FlipDoubleTapSeconds then
			flipQueued = true
			lastTapSide, lastTapAt = 0, 0
		else
			lastTapSide, lastTapAt = side, now
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
	heldKeys[input.KeyCode] = nil
	recomputeKeyboard()
end)

-- ── Send ────────────────────────────────────────────────────────────────
-- X is steer in [-1, 1]. Y is 1 on the frame a flip is requested, else 0.
-- Neither is a quantity the server trusts for anything but intent.
local accumulator = 0
local lastSent = Vector2.zero

RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	local steer = currentSteer()
	local flip = flipQueued and 1 or 0
	local payload = Vector2.new(steer, flip)

	local changed = math.abs(payload.X - lastSent.X) > 0.02 or flip == 1
	if accumulator >= sendInterval and changed then
		Remotes.SetInputDirection:FireServer(payload)
		lastSent = payload
		accumulator = 0
		flipQueued = false
	elseif accumulator >= sendInterval then
		accumulator = 0
	end
end)
