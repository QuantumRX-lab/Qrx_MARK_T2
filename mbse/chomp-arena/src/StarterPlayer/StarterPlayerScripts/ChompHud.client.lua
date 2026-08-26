--!strict
--[[
	ChompHud — CHAIN-UI, CHOMP-SYS-055 and -056 (D-CHOMP-050)

	The play HUD, in the zones Codex specified.

	  bottom right  what you are CARRYING, what you have BANKED, health, item
	  top centre    one contextual objective

	The values moved out of the top corners because Roblox puts its own chrome
	there — the menu button, the chat toggle and the close control sat directly
	on top of them, and a value you cannot read is not a HUD (D-CHOMP-053).

	This DISAGREES with CHOMP-SYS-055, which specifies top-left and top-right,
	and with CHOMP-SYS-032's reserved lower corners. Both are recorded as
	conflicts in the CHAIN-UI log rather than quietly ignored: the requirement
	was written before anyone had seen the game with Roblox's own UI on top of
	it, and on a touch device the bottom-right stack will need revisiting.

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
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
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

-- ── Bottom right: one stack, safest value at the bottom ─────────────────
-- Banked sits lowest because it is the number you check least often and the
-- one you most want to end the round looking at.
local stack = panel("Values", Vector2.new(1, 1), UDim2.new(1, -16, 1, -16), UDim2.new(0, 236, 0, 168))

local carriedValue = label(stack, UDim2.new(1, -24, 0, 40), UDim2.new(0, 14, 0, 10),
	"0", P.NeonB, 34, Enum.TextXAlignment.Right)
label(stack, UDim2.new(1, -24, 0, 16), UDim2.new(0, 14, 0, 48),
	"CARRYING — AT RISK", P.NeonB, 12, Enum.TextXAlignment.Right)

-- ── The belt: five slots, spent left to right ───────────────────────────
-- Order is the whole point (D-CHOMP-062), so the slots are laid out in the
-- order they will be used and the active one is unmistakable. A child should be
-- able to answer "what happens when I press fire" by looking, not remembering.
local SLOTS = ITEMS.SlotCount
local beltStrip = Instance.new("Frame")
beltStrip.Name = "Belt"
beltStrip.AnchorPoint = Vector2.new(1, 1)
beltStrip.Position = UDim2.new(1, -16, 1, -212)
beltStrip.Size = UDim2.new(0, 236, 0, 56)
beltStrip.BackgroundTransparency = 1
beltStrip.Parent = gui

local slotButtons: { TextButton } = {}
local slotCharges: { TextLabel } = {}
for i = 1, SLOTS do
	local b = Instance.new("TextButton")
	b.Name = "Slot" .. tostring(i)
	b.Size = UDim2.new(0, 42, 0, 52)
	b.Position = UDim2.new(0, (i - 1) * 47, 0, 0)
	b.BackgroundColor3 = P.Floor
	b.BackgroundTransparency = 0.3
	b.BorderSizePixel = 0
	b.Text = ""
	b.AutoButtonColor = false
	b.Parent = beltStrip
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 10)
	c.Parent = b

	local name = Instance.new("TextLabel")
	name.Name = "Label"
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, -4, 0, 30)
	name.Position = UDim2.new(0, 2, 0, 4)
	name.Text = ""
	name.TextScaled = true
	name.Font = Enum.Font.GothamBlack
	name.TextColor3 = P.Ghost
	name.Parent = b

	local charge = Instance.new("TextLabel")
	charge.BackgroundTransparency = 1
	charge.Size = UDim2.new(1, -4, 0, 16)
	charge.Position = UDim2.new(0, 2, 1, -18)
	charge.Text = ""
	charge.TextSize = 13
	charge.Font = Enum.Font.GothamBold
	charge.TextColor3 = P.Gold
	charge.Parent = b

	b.Activated:Connect(function()
		-- A slot index is a selection, not a value. The server owns what is in
		-- the slot and rejects an index it does not hold.
		if Remotes and Remotes.SelectItem then
			Remotes.SelectItem:FireServer(i)
		end
	end)

	table.insert(slotButtons, b)
	table.insert(slotCharges, charge)
end

local bankedValue = label(stack, UDim2.new(1, -24, 0, 40), UDim2.new(0, 14, 0, 112),
	"$0", P.Gold, 34, Enum.TextXAlignment.Right)
label(stack, UDim2.new(1, -24, 0, 16), UDim2.new(0, 14, 0, 148),
	"BANKED — SAFE", P.Gold, 12, Enum.TextXAlignment.Right)

-- ── Bottom left: the two big buttons ────────────────────────────────────
-- Buttons DO belong in the thumb zone. CHOMP-SYS-032 reserves the lower corners
-- so that nothing you need to READ sits under a hand — a thing you need to
-- PRESS wants to be exactly there (D-CHOMP-059).
--
-- Both are deliberately oversized. They are pressed while driving, by a child,
-- on a tablet, and the cost of a missed press is a wall.

local chargeButton = Instance.new("TextButton")
chargeButton.Name = "ChargeButton"
chargeButton.AnchorPoint = Vector2.new(0, 1)
chargeButton.Position = UDim2.new(0, 20, 1, -20)
chargeButton.Size = UDim2.new(0, 150, 0, 150)
chargeButton.BackgroundColor3 = P.Floor
chargeButton.BackgroundTransparency = 0.15
chargeButton.BorderSizePixel = 0
chargeButton.Text = ""
chargeButton.AutoButtonColor = false
chargeButton.Parent = gui
local cbCorner = Instance.new("UICorner")
cbCorner.CornerRadius = UDim.new(1, 0)
cbCorner.Parent = chargeButton

-- The fill rises from the bottom, because a meter that fills upward is one
-- nobody has to be taught to read.
local chargeFill = Instance.new("Frame")
chargeFill.Name = "Fill"
chargeFill.AnchorPoint = Vector2.new(0, 1)
chargeFill.Position = UDim2.new(0, 0, 1, 0)
chargeFill.Size = UDim2.new(1, 0, 0, 0)
chargeFill.BackgroundColor3 = P.NeonA
chargeFill.BackgroundTransparency = 0.35
chargeFill.BorderSizePixel = 0
chargeFill.ZIndex = 0
chargeFill.Parent = chargeButton
local cfCorner = Instance.new("UICorner")
cfCorner.CornerRadius = UDim.new(1, 0)
cfCorner.Parent = chargeFill

local chargeLabel = Instance.new("TextLabel")
chargeLabel.BackgroundTransparency = 1
chargeLabel.Size = UDim2.new(1, 0, 1, 0)
chargeLabel.Text = "CHARGE"
chargeLabel.TextColor3 = P.Ghost
chargeLabel.TextScaled = true
chargeLabel.Font = Enum.Font.GothamBlack
chargeLabel.ZIndex = 2
chargeLabel.Parent = chargeButton
local chargePadding = Instance.new("UIPadding")
chargePadding.PaddingLeft = UDim.new(0, 26)
chargePadding.PaddingRight = UDim.new(0, 26)
chargePadding.PaddingTop = UDim.new(0, 52)
chargePadding.PaddingBottom = UDim.new(0, 52)
chargePadding.Parent = chargeLabel

chargeButton.Activated:Connect(function()
	-- Intent only. The server decides whether there is charge to spend.
	if Remotes and Remotes.UseCharge then
		Remotes.UseCharge:FireServer()
	end
end)

local ffButton = Instance.new("TextButton")
ffButton.Name = "FriendlyFire"
ffButton.AnchorPoint = Vector2.new(0, 1)
ffButton.Position = UDim2.new(0, 20, 1, -184)
ffButton.Size = UDim2.new(0, 150, 0, 52)
ffButton.BackgroundColor3 = P.Floor
ffButton.BackgroundTransparency = 0.15
ffButton.BorderSizePixel = 0
ffButton.Text = "FRIENDLY FIRE"
ffButton.TextColor3 = P.Brick
ffButton.TextSize = 15
ffButton.Font = Enum.Font.GothamBold
ffButton.AutoButtonColor = false
ffButton.Parent = gui
local ffCorner = Instance.new("UICorner")
ffCorner.CornerRadius = UDim.new(0, 14)
ffCorner.Parent = ffButton

ffButton.Activated:Connect(function()
	if Remotes and Remotes.ToggleFriendlyFire then
		Remotes.ToggleFriendlyFire:FireServer()
	end
end)

-- ── Top centre: one objective ───────────────────────────────────────────
local centre = panel("Objective", Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 16), UDim2.new(0, 280, 0, 48))
local objective = label(centre, UDim2.new(1, -20, 1, -12), UDim2.new(0, 10, 0, 6),
	"COLLECT", P.NeonA, 22, Enum.TextXAlignment.Center)

local wavePanel = panel("Wave", Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 72), UDim2.new(0, 200, 0, 38))
local waveLabel = label(wavePanel, UDim2.new(1, -20, 1, -10), UDim2.new(0, 10, 0, 5),
	"WAVE 1", P.Ghost, 18, Enum.TextXAlignment.Center)

-- ── A flash when something is taken ─────────────────────────────────────
local flash = Instance.new("Frame")
flash.Name = "StolenFlash"
flash.Size = UDim2.new(1, 0, 1, 0)
flash.BackgroundColor3 = P.Danger
flash.BackgroundTransparency = 1
flash.BorderSizePixel = 0
flash.ZIndex = 0
flash.Parent = gui

-- Health sits under the carry, because both answer "how much trouble am I in".
local healthBack = Instance.new("Frame")
healthBack.Name = "HealthBack"
healthBack.AnchorPoint = Vector2.new(1, 1)
healthBack.Position = UDim2.new(1, -16, 1, -190)
healthBack.Size = UDim2.new(0, 236, 0, 14)
healthBack.BackgroundColor3 = P.Floor
healthBack.BackgroundTransparency = 0.25
healthBack.BorderSizePixel = 0
healthBack.Parent = gui
local hbCorner = Instance.new("UICorner")
hbCorner.CornerRadius = UDim.new(0, 7)
hbCorner.Parent = healthBack

local healthFill = Instance.new("Frame")
healthFill.Name = "HealthFill"
healthFill.Position = UDim2.new(0, 3, 0, 3)
healthFill.Size = UDim2.new(1, -6, 1, -6)
healthFill.BackgroundColor3 = P.NeonA
healthFill.BorderSizePixel = 0
healthFill.Parent = healthBack
local hfCorner = Instance.new("UICorner")
hfCorner.CornerRadius = UDim.new(0, 5)
hfCorner.Parent = healthFill

local lastStolenAt = 0
local lastHurtAt = 0

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

	-- The belt arrives as one string, "Cannon:10,Shield:1", because an attribute
	-- cannot hold a list.
	local beltRaw = character:GetAttribute("ChompBelt")
	local activeSlot = attribute("ChompActiveSlot")
	local entries: { { id: string, charges: number } } = {}
	if typeof(beltRaw) == "string" and beltRaw ~= "" then
		for chunk in string.gmatch(beltRaw, "[^,]+") do
			local id, count = string.match(chunk, "^(.-):(%d+)$")
			if id then
				table.insert(entries, { id = id, charges = tonumber(count) or 0 })
			end
		end
	end

	for i = 1, SLOTS do
		local button = slotButtons[i]
		local entry = entries[i]
		local isActive = (i == activeSlot) and entry ~= nil

		if entry then
			local def = ITEMS.Definitions[entry.id]
			button.Label.Text = string.sub(def and def.label or string.upper(entry.id), 1, 4)
			button.Label.TextColor3 = isActive and P.Floor or P.Ghost
			slotCharges[i].Text = entry.charges > 1 and tostring(entry.charges) or ""
			slotCharges[i].TextColor3 = isActive and P.Floor or P.Gold
			-- The active slot is filled rather than outlined: a child reads a
			-- solid block faster than a border, and it survives a small screen.
			button.BackgroundColor3 = isActive and P.NeonA or P.Floor
			button.BackgroundTransparency = isActive and 0.05 or 0.3
		else
			button.Label.Text = ""
			slotCharges[i].Text = ""
			button.BackgroundColor3 = P.Floor
			button.BackgroundTransparency = 0.55
		end
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

	-- Charge. Full is the only state that matters, so full is the only state
	-- that changes the words: below it the button says CHARGE and does nothing,
	-- at it the button says JUMP and glows.
	local CH = Config.Charge
	local charge = attribute("ChompCharge")
	local ready = charge >= CH.JumpCost
	chargeFill.Size = UDim2.new(1, 0, math.clamp(charge / CH.Max, 0, 1), 0)
	chargeFill.BackgroundColor3 = ready and P.Gold or P.NeonA
	chargeLabel.Text = ready and "JUMP" or "CHARGE"
	chargeLabel.TextColor3 = ready and P.Floor or P.Ghost
	chargeButton.BackgroundTransparency = ready and 0.05 or 0.15

	local ff = character:GetAttribute("ChompFriendlyFire") == true
	ffButton.TextColor3 = ff and P.Danger or P.Brick
	ffButton.Text = ff and "FRIENDLY FIRE: ON" or "FRIENDLY FIRE"
	ffButton.BackgroundTransparency = ff and 0.05 or 0.15

	local waveNumber = attribute("ChompWave")
	waveLabel.Text = waveNumber > 0 and ("WAVE " .. tostring(waveNumber)) or "WAVE 1"

	-- Health. Colour carries the reading, so a glance is enough: green is fine,
	-- gold is careful, red is one more hit.
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.MaxHealth > 0 then
		local fraction = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
		healthFill.Size = UDim2.new(fraction, -6, 1, -6)
		healthFill.BackgroundColor3 = if fraction > 0.6 then P.NeonA
			elseif fraction > 0.3 then P.Gold
			else P.Danger
	end

	-- A hit has to be FELT, not read: a number changing is not enough when your
	-- eyes are on a corridor (CHOMP-SYS-056). Two flashes, because they mean
	-- different things - losing points is pink, like the carry it came from,
	-- and taking damage is red.
	local stolenAt = attribute("ChompStolenAt")
	if stolenAt > lastStolenAt then
		lastStolenAt = stolenAt
		flash.BackgroundColor3 = P.NeonB
		flash.BackgroundTransparency = 0.6
	end
	local hurtAt = attribute("ChompHurtAt")
	if hurtAt > lastHurtAt then
		lastHurtAt = hurtAt
		flash.BackgroundColor3 = P.Danger
		flash.BackgroundTransparency = 0.45
	end
	if flash.BackgroundTransparency < 1 then
		flash.BackgroundTransparency = math.min(1, flash.BackgroundTransparency + dt * 1.6)
	end
end)
