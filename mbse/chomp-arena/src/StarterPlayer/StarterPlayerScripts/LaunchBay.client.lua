--!strict
-- Compact start guidance. The world remains the primary interface: shop row,
-- mounted equipment, and deployment arch are all visible behind this panel.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage:WaitForChild("ChompConfig"))
local P = Config.Palette

local gui = Instance.new("ScreenGui")
gui.Name = "LaunchBay"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 80
gui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Name = "BayPanel"
panel.AnchorPoint = Vector2.new(0.5, 0)
panel.Position = UDim2.new(0.5, 0, 0, 68)
panel.Size = UDim2.new(1, -24, 0, 112)
panel.BackgroundColor3 = P.Floor
panel.BackgroundTransparency = 0.08
panel.BorderSizePixel = 0
panel.Parent = gui
local size = Instance.new("UISizeConstraint")
size.MaxSize = Vector2.new(520, 112)
size.MinSize = Vector2.new(300, 104)
size.Parent = panel
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = panel
local stroke = Instance.new("UIStroke")
stroke.Color = P.Gold
stroke.Thickness = 3
stroke.Parent = panel

local function text(name: string, y: number, height: number, value: string,
		colour: Color3, textSize: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Position = UDim2.new(0, 14, 0, y)
	label.Size = UDim2.new(1, -28, 0, height)
	label.Text = value
	label.TextColor3 = colour
	label.TextSize = textSize
	label.Font = Enum.Font.GothamBlack
	label.TextWrapped = true
	label.Parent = panel
	return label
end

local title = text("Title", 10, 32, "LAUNCH BAY", P.Gold, 26)
local vehicle = text("Vehicle", 44, 24, "STANDARD", P.NeonA, 18)
local instruction = text("Instruction", 70, 34,
	"SHOP THE PLINTHS  •  DRIVE THROUGH THE GOLD GATE", P.Ghost, 15)

RunService.RenderStepped:Connect(function()
	local character = player.Character
	if not character then panel.Visible = false return end
	local state = player:GetAttribute("ChompSessionState")
	panel.Visible = state ~= Config.Launch.ActiveState
	if not panel.Visible then return end
	local chassis = player:GetAttribute("ChompEquippedChassis")
	vehicle.Text = typeof(chassis) == "string" and string.upper(chassis) or "STANDARD"
	if state == Config.Launch.DeployingState then
		local at = character:GetAttribute("ChompDeployAt")
		local elapsed = typeof(at) == "number" and os.clock() - at or 0
		local left = math.max(1, math.ceil(Config.Launch.DeploymentSeconds - elapsed))
		title.Text = tostring(left)
		instruction.Text = "SYSTEMS ARMED  •  GET READY"
		stroke.Color = P.NeonA
	else
		title.Text = "LAUNCH BAY"
		instruction.Text = "SHOP THE PLINTHS  •  DRIVE THROUGH THE GOLD GATE"
		stroke.Color = P.Gold
	end
end)
