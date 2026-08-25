--!strict
--[[
	InputController — CHAIN-UI, CHOMP-SYS-032

	One stick. Push forward to drive, left and right to turn, back to turn
	around (D-CHOMP-027).

	On touch the stick FLOATS: it anchors wherever the finger lands and reads
	displacement from that anchor, so there is no fixed puck to find and nothing
	to lose if the thumb drifts. That was the real objection to a thumbstick in
	D-CHOMP-015, and a floating origin answers it without giving up a throttle.

	This publishes intent on two axes and nothing more. What a direction MEANS —
	snap when stopped, turn at the chassis rate when moving — is
	VehicleController's business. Two earlier schemes died here: one gated
	movement on steering, so every path was an arc and driving straight was
	impossible; the next split direction from throttle, so reorienting in a dead
	end was a three-point turn.

	The client sends INTENT ONLY. It never sends a speed, a position or a turn
	rate — the server owns all three (CHOMP-SYS-002).
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("ChompConfig"))
local CONTROLS = Config.Controls

-- Acquired off the critical path. Steering must work whether or not the
-- network surface is ready: a module that yields at require time took the
-- whole controller down once already, and driving is not something that
-- should ever wait on a RemoteEvent.
local Remotes = nil
task.spawn(function()
	local ok, result = pcall(function()
		return require(ReplicatedStorage:WaitForChild("Remotes"))
	end)
	if ok then
		Remotes = result
	else
		warn("[InputController] remotes unavailable, driving locally only: " .. tostring(result))
	end
end)

local player = Players.LocalPlayer

-- VehicleController reads this every frame to steer the character we own.
-- The server still gets the same intent through SetInputDirection, so it can
-- validate; this table is how the local character turns without waiting for a
-- round trip (D-CHOMP-018).
local shared = _G.ChompInput or { steer = 0, throttle = 0, flip = false }
_G.ChompInput = shared

local sendRate = 20  -- two thirds of the server's 30/s limit
local sendInterval = 1 / sendRate

-- ── Floating stick (touch) ──────────────────────────────────────────────
-- One finger drives. A second finger is ignored rather than averaged in:
-- averaging two touches is how a panicking player ends up going straight.
local stickTouch: any = nil
local stickOrigin = Vector2.zero
local stickCurrent = Vector2.zero

-- Returns steer (-1..1) and throttle (-1..1) from the stick, or 0, 0.
local function stickAxes(): (number, number)
	if not stickTouch then
		return 0, 0
	end
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize
	if not viewport or viewport.Y <= 0 then
		return 0, 0
	end

	-- Radius is a fraction of screen HEIGHT, so the stick is the same physical
	-- size in portrait and landscape rather than stretching with width.
	local radius = viewport.Y * CONTROLS.StickRadiusFraction
	if radius <= 0 then
		return 0, 0
	end

	local v = (stickCurrent - stickOrigin) / radius
	if v.Magnitude > 1 then
		v = v.Unit
	end

	local dead = CONTROLS.StickDeadZoneFraction
	local magnitude = v.Magnitude
	if magnitude <= dead then
		return 0, 0
	end

	-- Rescale so the dead-zone edge is zero and the rim is full deflection.
	-- Without this the stick jumps to a noticeable value the instant it leaves
	-- the dead zone, which reads as twitchy under a thumb.
	local scaled = (magnitude - dead) / (1 - dead)
	v = v.Unit * scaled

	-- Screen Y grows downward, so forward is negative Y.
	return v.X, -v.Y
end

UserInputService.TouchStarted:Connect(function(touch, processed)
	if processed or stickTouch then return end
	stickTouch = touch
	stickOrigin = Vector2.new(touch.Position.X, touch.Position.Y)
	stickCurrent = stickOrigin
end)

UserInputService.TouchMoved:Connect(function(touch)
	if touch == stickTouch then
		stickCurrent = Vector2.new(touch.Position.X, touch.Position.Y)
	end
end)

local function endTouch(touch)
	if touch == stickTouch then
		stickTouch = nil
		stickOrigin = Vector2.zero
		stickCurrent = Vector2.zero
	end
end
UserInputService.TouchEnded:Connect(endTouch)

-- ── Keyboard, for building in Studio ────────────────────────────────────
local heldKeys: { [Enum.KeyCode]: boolean } = {}
local LEFT = { [Enum.KeyCode.A] = true, [Enum.KeyCode.Left] = true }
local RIGHT = { [Enum.KeyCode.D] = true, [Enum.KeyCode.Right] = true }
local FORWARD = { [Enum.KeyCode.W] = true, [Enum.KeyCode.Up] = true }
local BACK = { [Enum.KeyCode.S] = true, [Enum.KeyCode.Down] = true }

local keyboardSteer = 0
local keyboardThrottle = 0

local function recomputeKeyboard()
	local left, right, forward, back = false, false, false, false
	for key in heldKeys do
		if LEFT[key] then left = true end
		if RIGHT[key] then right = true end
		if FORWARD[key] then forward = true end
		if BACK[key] then back = true end
	end
	-- Both sides held cancels to straight, which is what a panicking player
	-- does with two thumbs. Forward and back cancel the same way.
	keyboardSteer = (right and 1 or 0) - (left and 1 or 0)
	keyboardThrottle = (forward and 1 or 0) - (back and 1 or 0)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or input.UserInputType ~= Enum.UserInputType.Keyboard then return end
	heldKeys[input.KeyCode] = true
	recomputeKeyboard()

end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
	heldKeys[input.KeyCode] = nil
	recomputeKeyboard()
end)

-- ── Send ────────────────────────────────────────────────────────────────
-- X is steer in [-1, 1]. Y is the flip flag service_contracts.md specifies and
-- is now always zero: a 180 is just the opposite direction under grid driving,
-- so the double-tap gesture retired with D-CHOMP-033. The remote's shape is
-- unchanged, so no contract amendment and no exploit-suite change.
-- Neither is a quantity the server trusts for anything but intent.
--
-- Throttle is deliberately NOT on the wire yet. The remote's shape is fixed by
-- service_contracts.md, and nothing server-side consumes input today; widening
-- it means amending the contract and extending the exploit suite in the same
-- commit (CHOMP-TC-042). Until MovementService validates travel against
-- throttle, sending it would be a contract change that buys nothing.
local accumulator = 0
local lastSent = Vector2.zero

RunService.Heartbeat:Connect(function(dt)
	accumulator += dt

	local stickX, stickY = stickAxes()
	local steer = math.clamp(keyboardSteer + stickX, -1, 1)
	local throttle = math.clamp(keyboardThrottle + stickY, -1, 1)

	shared.steer = steer
	shared.throttle = throttle
	local payload = Vector2.new(steer, 0)

	local changed = math.abs(payload.X - lastSent.X) > 0.02
	if accumulator >= sendInterval and changed and Remotes then
		Remotes.SetInputDirection:FireServer(payload)
		lastSent = payload
		accumulator = 0
	elseif accumulator >= sendInterval then
		accumulator = 0
	end
end)
