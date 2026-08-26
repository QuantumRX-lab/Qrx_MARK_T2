--!strict
--[[
	PickupFeedback — CHAIN-UI, CHOMP-SYS-056 (D-CHOMP-052)

	Floating numbers above the kart when something changes.

	CHOMP-SYS-056 asks that gains and losses explain themselves: the signed
	amount AND where it went. A total ticking up in a corner does not do that
	while your eyes are on a corridor, so the number appears where you are
	already looking — over your own vehicle — and says which pot it landed in.

	  +25          pink, gone to the risky carry
	  +$180 SAFE   gold, banked and untouchable
	  -40          red, a ghost took it
	  -14 HP       red, that hurt

	Colour is never the only signal. Each carries a sign, and banked carries the
	word SAFE, because the same objection applies here as to the HUD: colour
	alone fails a colour-blind player, and this game is meant for a child.

	Client-side and read-only. It reflects attributes the server wrote and
	decides nothing.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("ChompConfig"))
local P = Config.Palette

local player = Players.LocalPlayer

local function popup(text: string, colour: Color3)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end

	local anchor = Instance.new("Part")
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CFrame = root.CFrame * CFrame.new(0, 9, 0)
	anchor.Parent = workspace

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(0, 190, 0, 52)
	gui.AlwaysOnTop = true
	gui.Adornee = anchor
	gui.Parent = anchor

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 1, 0)
	label.Text = text
	label.TextColor3 = colour
	label.TextStrokeColor3 = P.Floor
	label.TextStrokeTransparency = 0.15
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.Parent = gui

	-- Rises and fades. Rising matters: a static number is easy to miss at speed,
	-- and movement is what the eye catches without being asked to look.
	local info = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(anchor, info, { CFrame = anchor.CFrame * CFrame.new(0, 8, 0) }):Play()
	TweenService:Create(label, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(1, function() anchor:Destroy() end)
end

local seen = { gained = 0, banked = 0, stolen = 0, hurt = 0 }

local function stamp(character: Model, name: string): number
	return (character:GetAttribute(name) :: number?) or 0
end

local function amount(character: Model, name: string): number
	return (character:GetAttribute(name) :: number?) or 0
end

RunService.Heartbeat:Connect(function()
	local character = player.Character
	if not character then return end

	local gained = stamp(character, "ChompGainedAt")
	if gained > seen.gained then
		seen.gained = gained
		popup("+" .. tostring(amount(character, "ChompGainedAmount")), P.NeonB)
	end

	local banked = stamp(character, "ChompBankedAt")
	if banked > seen.banked then
		seen.banked = banked
		popup("+$" .. tostring(amount(character, "ChompBankedAmount")) .. "  SAFE", P.Gold)
	end

	local stolen = stamp(character, "ChompStolenAt")
	if stolen > seen.stolen then
		seen.stolen = stolen
		popup("-" .. tostring(amount(character, "ChompStolenAmount")), P.Danger)
	end

	local hurt = stamp(character, "ChompHurtAt")
	if hurt > seen.hurt then
		seen.hurt = hurt
		popup("-" .. tostring(math.floor(Config.Ghosts.ContactDamage)) .. " HP", P.Danger)
	end
end)
