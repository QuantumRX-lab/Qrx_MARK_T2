--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("ChompConfig"))
local P = Config.Palette
local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "ShopFeedback"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 65
gui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 1)
panel.Position = UDim2.new(0.5, 0, 1, -112)
panel.Size = UDim2.new(0, 360, 0, 86)
panel.BackgroundColor3 = P.Floor
panel.BackgroundTransparency = 0.08
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = panel

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.new(0, 14, 0, 8)
title.Size = UDim2.new(1, -28, 0, 28)
title.Font = Enum.Font.GothamBlack
title.TextColor3 = P.Ghost
title.TextSize = 21
title.Text = ""
title.Parent = panel

local hint = Instance.new("TextLabel")
hint.BackgroundTransparency = 1
hint.Position = UDim2.new(0, 14, 0, 38)
hint.Size = UDim2.new(1, -28, 0, 18)
hint.Font = Enum.Font.GothamBold
hint.TextColor3 = P.Gold
hint.TextSize = 14
hint.Text = ""
hint.Parent = panel

local track = Instance.new("Frame")
track.Position = UDim2.new(0, 14, 1, -20)
track.Size = UDim2.new(1, -28, 0, 8)
track.BackgroundColor3 = P.BrickDark
track.BorderSizePixel = 0
track.Parent = panel
local fill = Instance.new("Frame")
fill.Size = UDim2.fromScale(0, 1)
fill.BackgroundColor3 = P.NeonA
fill.BorderSizePixel = 0
fill.Parent = track

local toast = Instance.new("TextLabel")
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.Position = UDim2.new(0.5, 0, 0, 122)
toast.Size = UDim2.new(0, 520, 0, 54)
toast.BackgroundColor3 = P.Floor
toast.BackgroundTransparency = 0.06
toast.BorderSizePixel = 0
toast.Font = Enum.Font.GothamBlack
toast.TextSize = 24
toast.TextColor3 = P.Gold
toast.Visible = false
toast.Parent = gui
local toastCorner = Instance.new("UICorner")
toastCorner.CornerRadius = UDim.new(0, 8)
toastCorner.Parent = toast

local shownResult = 0
local shownAdvice = 0
local hideToastAt = 0

RunService.RenderStepped:Connect(function()
	local character = player.Character
	if not character then panel.Visible = false return end
	local offer = (character:GetAttribute("ChompShopOffer") :: string?) or ""
	local price = (character:GetAttribute("ChompShopPrice") :: number?) or 0
	panel.Visible = offer ~= ""
	title.Text = offer .. (price >= 0 and ("  $" .. tostring(price)) or "  MAX")
	hint.Text = (character:GetAttribute("ChompShopHint") :: string?) or ""
	fill.Size = UDim2.fromScale(math.clamp((character:GetAttribute("ChompShopProgress") :: number?) or 0, 0, 1), 1)

	local resultAt = (character:GetAttribute("ChompShopResultAt") :: number?) or 0
	if resultAt > shownResult then
		shownResult = resultAt
		local result = (character:GetAttribute("ChompShopResult") :: string?) or ""
		local bought = (character:GetAttribute("ChompBoughtAt") :: number?) or 0
		local what = (character:GetAttribute("ChompBoughtWhat") :: string?) or offer
		toast.Text = bought >= resultAt - 0.1 and (what .. " EQUIPPED") or result
		toast.TextColor3 = bought >= resultAt - 0.1 and P.Gold or P.Danger
		toast.Visible = true
		hideToastAt = os.clock() + 2.2
	end
	local adviceAt = (character:GetAttribute("ChompShopAdviceAt") :: number?) or 0
	if adviceAt > shownAdvice then
		shownAdvice = adviceAt
		toast.Text = (character:GetAttribute("ChompShopAdvice") :: string?) or "RESTOCK NOW"
		toast.TextColor3 = P.NeonA
		toast.Visible = true
		hideToastAt = os.clock() + 5
	end
	if toast.Visible and os.clock() >= hideToastAt then toast.Visible = false end
end)
