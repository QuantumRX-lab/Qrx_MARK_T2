--!strict
--[[
	CameraReadout — CHAIN-UI, supports CHOMP-TC-040

	The camera acceptance figures, on screen, because the device has no command
	bar (D-CHOMP-029).

	BUILDING.md told the tester to call _G.ChompCameraReport() from the Studio
	command bar. That instruction was written by a session that could not test on
	a device, and it does not survive contact with one: an iPad has no command
	bar, and the fallback — typing Lua into the /console overlay while holding a
	vehicle on a steering stick — is a juggling act, not a test procedure. Worse,
	the camera warns on every breach, so the log is noisiest exactly when the
	numbers matter most.

	So the run becomes: drive the circuit, look at the corner, read the number
	out. That is something you can do one-handed, and something a seven-year-old
	can do while you watch her drive rather than while you fight a console.

	Gated on ChompConfig.Debug.CameraReadout. Turn it off before anyone plays
	this for fun rather than to measure it.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("ChompConfig"))

if not (Config.Debug and Config.Debug.CameraReadout) then
	return
end

local LIMIT = Config.Camera.MaxOcclusionSeconds
local player = Players.LocalPlayer

local OK = Color3.fromRGB(126, 217, 87)
local NEAR = Color3.fromRGB(255, 176, 32)
local BAD = Color3.fromRGB(255, 61, 61)

local gui = Instance.new("ScreenGui")
gui.Name = "ChompCameraReadout"
gui.ResetOnSpawn = false        -- a respawn mid-circuit must not lose the run
gui.IgnoreGuiInset = true
gui.DisplayOrder = 100
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

-- Top centre. The control scheme reserves the bottom corners for thumbs
-- (ThumbSafeZoneFraction), and this must never sit where a hand does.
local frame = Instance.new("Frame")
frame.AnchorPoint = Vector2.new(0.5, 0)
frame.Position = UDim2.new(0.5, 0, 0, 8)
frame.Size = UDim2.new(0, 300, 0, 62)
frame.BackgroundColor3 = Color3.fromRGB(21, 14, 31)
frame.BackgroundTransparency = 0.25
frame.BorderSizePixel = 0
frame.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = frame

local label = Instance.new("TextLabel")
label.BackgroundTransparency = 1
label.Position = UDim2.new(0, 12, 0, 6)
label.Size = UDim2.new(1, -84, 1, -12)
label.Font = Enum.Font.Code
label.TextSize = 16
label.TextXAlignment = Enum.TextXAlignment.Left
label.TextYAlignment = Enum.TextYAlignment.Top
label.RichText = true
label.Text = ""
label.Parent = frame

local reset = Instance.new("TextButton")
reset.AnchorPoint = Vector2.new(1, 0.5)
reset.Position = UDim2.new(1, -10, 0.5, 0)
reset.Size = UDim2.new(0, 58, 0, 40)
reset.BackgroundColor3 = Color3.fromRGB(48, 36, 64)
reset.BorderSizePixel = 0
reset.Font = Enum.Font.GothamBold
reset.TextSize = 13
reset.TextColor3 = Color3.fromRGB(242, 238, 245)
reset.Text = "RESET"
reset.Parent = frame

local resetCorner = Instance.new("UICorner")
resetCorner.CornerRadius = UDim.new(0, 8)
resetCorner.Parent = reset

-- Safe to have a button here: InputController drops touches whose
-- gameProcessedEvent is true, so pressing this never also drives the vehicle.
reset.Activated:Connect(function()
	if _G.ChompCameraReset then
		_G.ChompCameraReset()
	end
end)

local accumulator = 0
local RATE = 1 / 5   -- five times a second is legible without flickering

RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator < RATE then return end
	accumulator = 0

	if not _G.ChompCameraStats then
		label.Text = "<font color='#FF3D3D'>camera not reporting</font>"
		return
	end

	local worst, breaches, hiddenFor = _G.ChompCameraStats()

	local colour = OK
	if breaches > 0 then
		colour = BAD
	elseif worst > LIMIT * 0.8 then
		colour = NEAR
	end
	local hex = string.format("#%02X%02X%02X",
		math.floor(colour.R * 255), math.floor(colour.G * 255), math.floor(colour.B * 255))

	-- "HIDDEN" while occluded, so a tester can see WHICH bit of geometry did it
	-- rather than only that something did, which is the difference between a
	-- number to report and a thing to fix.
	local live = hiddenFor > 0
		and string.format("  <font color='#FF3D3D'>HIDDEN %.2fs</font>", hiddenFor)
		or ""

	label.Text = string.format(
		"<font color='%s'>CAM  worst %.2fs / limit %.2fs</font>%s\n<font color='%s'>breaches %d</font>  <font color='#9C8FAE'>%s</font>",
		hex, worst, LIMIT, live, hex, breaches,
		breaches > 0 and "CHOMP-SYS-051 FAIL" or "passing so far")
end)
