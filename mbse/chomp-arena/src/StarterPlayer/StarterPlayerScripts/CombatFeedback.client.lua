--!strict
-- Local presentation for server-owned combat results.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("ChompConfig"))
local P = Config.Palette
local localPlayer = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "CombatFeedback"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 70
gui.Parent = localPlayer:WaitForChild("PlayerGui")

local toast = Instance.new("TextLabel")
toast.Name = "CombatToast"
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.Position = UDim2.new(0.5, 0, 0, 122)
toast.Size = UDim2.new(0, 380, 0, 48)
toast.BackgroundColor3 = P.Floor
toast.BackgroundTransparency = 1
toast.TextTransparency = 1
toast.TextStrokeTransparency = 1
toast.TextScaled = true
toast.Font = Enum.Font.GothamBlack
toast.ZIndex = 20
toast.Parent = gui
local limit = Instance.new("UITextSizeConstraint")
limit.MinTextSize = 14
limit.MaxTextSize = 28
limit.Parent = toast

local colours = {
	["BITE"] = P.Gold,
	["AMBUSHED"] = P.Danger,
	["CLANG"] = P.NeonA,
	["HEAD-ON"] = P.NeonA,
	["CHOMP"] = P.Gold,
	["CHOMPED"] = P.Danger,
	["SHIELDED"] = P.Shield,
	["NO REWARD"] = P.Ghost,
	["PROTECTED"] = P.Shield,
}

local generation = 0

local function directionWord(character: Model): string
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local x = character:GetAttribute("ChompHitFromX")
	local z = character:GetAttribute("ChompHitFromZ")
	local camera = workspace.CurrentCamera
	if not (root and camera and typeof(x) == "number" and typeof(z) == "number") then return "" end
	local toward = Vector3.new(x, root.Position.Y, z) - root.Position
	if toward.Magnitude < 0.01 then return "" end
	toward = toward.Unit
	local right = camera.CFrame.RightVector * Vector3.new(1, 0, 1)
	local forward = camera.CFrame.LookVector * Vector3.new(1, 0, 1)
	if right.Magnitude < 0.01 or forward.Magnitude < 0.01 then return "" end
	right = right.Unit
	forward = forward.Unit
	if math.abs(toward:Dot(right)) > math.abs(toward:Dot(forward)) then
		return toward:Dot(right) > 0 and "  FROM RIGHT" or "  FROM LEFT"
	end
	return toward:Dot(forward) > 0 and "  FROM FRONT" or "  FROM REAR"
end

local function worldPopup(character: Model, kind: string, colour: Color3)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "CombatPopup"
	billboard.Adornee = root
	billboard.Size = UDim2.new(0, 190, 0, 54)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 8, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 220
	billboard.Parent = root
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Text = kind
	text.TextColor3 = colour
	text.TextStrokeColor3 = P.Floor
	text.TextStrokeTransparency = 0
	text.TextScaled = true
	text.Font = Enum.Font.GothamBlack
	text.Parent = billboard
	TweenService:Create(billboard, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ StudsOffsetWorldSpace = Vector3.new(0, 13, 0) }):Play()
	TweenService:Create(text, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.45),
		{ TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(billboard, 0.85)

	local highlight = Instance.new("Highlight")
	highlight.Name = "CombatFlash"
	highlight.Adornee = character:FindFirstChild("Vehicle") or character
	highlight.FillColor = colour
	highlight.FillTransparency = 0.35
	highlight.OutlineColor = P.Ghost
	highlight.OutlineTransparency = 0.1
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = character
	TweenService:Create(highlight, TweenInfo.new(0.25), { FillTransparency = 1, OutlineTransparency = 1 }):Play()
	Debris:AddItem(highlight, 0.3)
end

local function showLocal(character: Model, kind: string, colour: Color3)
	generation += 1
	local mine = generation
	local barLoss = (character:GetAttribute("ChompCombatBarLoss") :: number?) or 0
	local carryLoss = (character:GetAttribute("ChompCombatCarryLoss") :: number?) or 0
	local suffix = ""
	if barLoss > 0 then suffix ..= "  -" .. tostring(barLoss) .. " BITE" end
	if carryLoss > 0 then suffix ..= "  -" .. tostring(carryLoss) .. " CARRY" end
	toast.Text = kind .. suffix .. directionWord(character)
	toast.TextColor3 = colour
	toast.BackgroundTransparency = 0.18
	toast.TextTransparency = 0
	toast.TextStrokeTransparency = 0.35
	if _G.ChompCameraShake and character:GetAttribute("ChompCombatRole") ~= "ATTACKER" then
		_G.ChompCameraShake()
	end
	task.delay(0.9, function()
		if mine ~= generation then return end
		TweenService:Create(toast, TweenInfo.new(0.2), {
			BackgroundTransparency = 1, TextTransparency = 1, TextStrokeTransparency = 1,
		}):Play()
	end)
end

local function bind(character: Model, isLocal: boolean)
	local seen = 0
	character:GetAttributeChangedSignal("ChompCombatAt"):Connect(function()
		local stamp = (character:GetAttribute("ChompCombatAt") :: number?) or 0
		if stamp <= seen then return end
		seen = stamp
		local kind = tostring(character:GetAttribute("ChompCombatKind") or "HIT")
		local colour = colours[kind] or P.Ghost
		worldPopup(character, kind, colour)
		if isLocal then showLocal(character, kind, colour) end
	end)
end

local function watch(player: Player)
	player.CharacterAdded:Connect(function(character) bind(character, player == localPlayer) end)
	if player.Character then bind(player.Character, player == localPlayer) end
end

for _, player in Players:GetPlayers() do watch(player) end
Players.PlayerAdded:Connect(watch)
