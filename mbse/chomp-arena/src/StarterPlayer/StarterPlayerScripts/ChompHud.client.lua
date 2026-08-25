--!strict
--[[
	ChompHud — CHAIN-UI, CHOMP-SYS-055 and -056 (D-CHOMP-050)

	The play HUD, in the zones Codex specified.

	  top left    what you are CARRYING, and what you are holding
	  top centre  one contextual objective
	  top right   what you have BANKED

	Carried and banked are the whole economy, so they are never the same colour,
	never the same size and never in the same corner. A child has to be able to
	answer "is that safe?" without reading a word.

	Nothing here decides anything. Every value is an attribute the SERVER wrote,
	read-only on this side (CHOMP-SYS-030). The HUD cannot make you richer.

	The bottom edge and both lower corners stay empty, because that is where
	thumbs live (CHOMP-SYS-032).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("ChompConfig"))
local P = Config.Palette
local ITEMS = Config.Items

local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "ChompHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 50
gui.Parent = player:WaitForChild("PlayerGui")

local function panel(name: string, anchor: Vector2, position: UDim2, size: UDim2): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = anchor
	f.Position = position
	f.Size = size
	f.BackgroundColor3 = P.Floor
	f.BackgroundTransparency = 0.25
	f.BorderSizePixel = 0
	f.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = f
	return f
end

local function label(parent: Instance, size: UDim2, position: UDim2, text: string,
		colour: Color3, textSize: number, align: Enum.TextXAlignment): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = size
	t.Position = position
	t.Text = text
	t.TextColor3 = colour
	t.TextSize = textSize
	t.Font = Enum.Font.GothamBold
	t.TextXAlignment = align
	t.Parent = parent
	return t
end

-- ── Top left: risky ─────────────────────────────────────────────────────
local left = panel("Carried", Vector2.new(0, 0), UDim2.new(0, 16, 0, 16), UDim2.new(0, 210, 0, 92))
local carriedValue = label(left, UDim2.new(1, -20, 0, 42), UDim2.new(0, 14, 0, 8),
	"0", P.NeonB, 36, Enum.TextXAlignment.Left)
label(left, UDim2.new(1, -20, 0, 18), UDim2.new(0, 14, 0, 48),
	"CARRYING — AT RISK", P.NeonB, 13, Enum.TextXAlignment.Left)
local itemLabel = label(left, UDim2.new(1, -20, 0, 20), UDim2.new(0, 14, 0, 68),
	"no item", P.Ghost, 15, Enum.TextXAlignment.Left)

-- ── Top right: safe ─────────────────────────────────────────────────────
local right = panel("Banked", Vector2.new(1, 0), UDim2.new(1, -16, 0, 16), UDim2.new(0, 210, 0, 72))
local bankedValue = label(right, UDim2.new(1, -20, 0, 42), UDim2.new(0, 6, 0, 8),
	"$0", P.Gold, 36, Enum.TextXAlignment.Right)
label(right, UDim2.new(1, -20, 0, 18), UDim2.new(0, 6, 0, 48),
	"BANKED — SAFE", P.Gold, 13, Enum.TextXAlignment.Right)

-- ── Top centre: one objective ───────────────────────────────────────────
local centre = panel("Objective", Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 16), UDim2.new(0, 280, 0, 48))
local objective = label(centre, UDim2.new(1, -20, 1, -12), UDim2.new(0, 10, 0, 6),
	"COLLECT", P.NeonA, 22, Enum.TextXAlignment.Center)

-- ── A flash when something is taken ─────────────────────────────────────
local flash = Instance.new("Frame")
flash.Name = "StolenFlash"
flash.Size = UDim2.new(1, 0, 1, 0)
flash.BackgroundColor3 = P.Danger
flash.BackgroundTransparency = 1
flash.BorderSizePixel = 0
flash.ZIndex = 0
flash.Parent = gui

local lastStolenAt = 0

local function attribute(name: string): number
	local character = player.Character
	if not character then return 0 end
	return (character:GetAttribute(name) :: number?) or 0
end

RunService.RenderStepped:Connect(function(dt)
	local character = player.Character
	if not character then return end

	local carried = attribute("ChompCarried")
	local banked = attribute("ChompDollars")
	carriedValue.Text = tostring(carried)
	bankedValue.Text = "$" .. tostring(banked)

	local itemId = character:GetAttribute("ChompItem")
	local charges = attribute("ChompItemCharges")
	if typeof(itemId) == "string" and itemId ~= "" then
		local def = ITEMS.Definitions[itemId]
		local name = def and def.label or string.upper(itemId)
		itemLabel.Text = charges > 1 and (name .. "  x" .. tostring(charges)) or name
		itemLabel.TextColor3 = P.NeonA
	else
		itemLabel.Text = "no item"
		itemLabel.TextColor3 = P.Brick
	end

	-- ONE objective, chosen by what is most urgent rather than listed.
	-- Carrying a lot outranks everything: the thing most likely to be lost is
	-- the thing worth being told about.
	if carried >= 250 then
		objective.Text = "BANK IT — GARAGE"
		objective.TextColor3 = P.Danger
	elseif carried > 0 then
		objective.Text = "COLLECT — THEN BANK"
		objective.TextColor3 = P.Gold
	else
		objective.Text = "COLLECT"
		objective.TextColor3 = P.NeonA
	end

	-- A theft has to be FELT, not read. The number changing is not enough when
	-- your eyes are on a corridor (CHOMP-SYS-056).
	local stolenAt = attribute("ChompStolenAt")
	if stolenAt > lastStolenAt then
		lastStolenAt = stolenAt
		flash.BackgroundTransparency = 0.55
	end
	if flash.BackgroundTransparency < 1 then
		flash.BackgroundTransparency = math.min(1, flash.BackgroundTransparency + dt * 1.6)
	end
end)
