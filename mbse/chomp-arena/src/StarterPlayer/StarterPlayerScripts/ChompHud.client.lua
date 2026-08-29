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
local UserInputService = game:GetService("UserInputService")
local TextChatService = game:GetService("TextChatService")
local StarterGui = game:GetService("StarterGui")

local Config = require(ReplicatedStorage:WaitForChild("ChompConfig"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local P = Config.Palette
local ITEMS = Config.Items

local player = Players.LocalPlayer

local CONTROLS = Config.Controls

local gui = Instance.new("ScreenGui")
gui.Name = "ChompHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 50
-- Landscape only (D-CHOMP-071). CHOMP-SYS-032 asked for both orientations; the
-- action buttons make the right column too tall for a portrait iPad, so the
-- requirement was amended to name landscape rather than quietly broken.
if CONTROLS.LockLandscape then
	gui.ScreenOrientation = Enum.ScreenOrientation.LandscapeSensor
end
gui.Parent = player:WaitForChild("PlayerGui")

-- Keep Roblox's own chat, but move it away from the attribute panel and jump
-- control. This configures the platform UI rather than maintaining a second
-- chat implementation.
local chatWindow = TextChatService:FindFirstChildOfClass("ChatWindowConfiguration")
if chatWindow then
	chatWindow.Enabled = true
	chatWindow.HorizontalAlignment = Enum.HorizontalAlignment.Right
	chatWindow.VerticalAlignment = Enum.VerticalAlignment.Top
end

-- Studio can still run the legacy chat implementation. SetCore is registered
-- asynchronously, so retry briefly; the modern configuration above remains
-- the path used by current published clients.
task.spawn(function()
	for _ = 1, 20 do
		local ok = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, true)
			StarterGui:SetCore("ChatActive", true)
			StarterGui:SetCore("ChatWindowPosition", UDim2.new(1, -430, 0, 10))
			StarterGui:SetCore("ChatWindowSize", UDim2.new(0, 410, 0, 180))
		end)
		if ok then return end
		task.wait(0.25)
	end
end)

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
-- The right column now sits ABOVE the action buttons. CHOMP-SYS-055 wants the
-- lower corners kept "clear for touch input", and buttons ARE touch input - it
-- is the numbers that should not be under a thumb, which is what moving them up
-- finally fixes (D-CHOMP-071).
local COLUMN_BASE = CONTROLS.ButtonMarginPx * 2 + CONTROLS.JumpButtonPx  -- 160

local stack = panel("Values", Vector2.new(1, 1),
	UDim2.new(1, -16, 1, -(COLUMN_BASE + 236)), UDim2.new(0, 236, 0, 168))

local carriedValue = label(stack, UDim2.new(1, -24, 0, 40), UDim2.new(0, 14, 0, 10),
	"0", P.NeonB, 34, Enum.TextXAlignment.Right)
label(stack, UDim2.new(1, -24, 0, 16), UDim2.new(0, 14, 0, 48),
	"CARRYING — AT RISK", P.NeonB, 12, Enum.TextXAlignment.Right)

-- ── The belt: five slots, spent left to right ───────────────────────────
-- Order is the whole point (D-CHOMP-062), so the slots are laid out in the
-- order they will be used and the active one is unmistakable. A child should be
-- able to answer "what happens when I press fire" by looking, not remembering.
local SLOTS = ITEMS.SlotCount

-- Sizes come first because they are the whole fix (D-CHOMP-064). The old strip
-- was 236 pixels for five slots - 42 each - with the item name TextScaled into
-- 38 of them and then TRUNCATED to four characters, so "CANNON" read as "CANN"
-- at about nine pixels a letter. On an iPad, at speed, that is not a label.
--
-- 64 a slot is close to Apple's 44-point minimum touch target with room for a
-- word, and the slots are tappable (D-CHOMP-062), so they have to be pressable
-- as well as readable.
local SLOT_W, SLOT_H, SLOT_GAP = 64, 68, 6
local BELT_W = SLOTS * SLOT_W + (SLOTS - 1) * SLOT_GAP

local function itemColour(id: string): Color3
	local key = ITEMS.Colours and ITEMS.Colours[id]
	return (key and P[key]) or P.Ghost
end

local beltStrip = Instance.new("Frame")
beltStrip.Name = "Belt"
beltStrip.AnchorPoint = Vector2.new(1, 1)
beltStrip.Position = UDim2.new(1, -16, 1, -COLUMN_BASE)
beltStrip.Size = UDim2.new(0, BELT_W, 0, SLOT_H)
beltStrip.BackgroundTransparency = 1
beltStrip.Parent = gui

local slotButtons: { TextButton } = {}
local slotCharges: { TextLabel } = {}
local slotBars: { Frame } = {}
for i = 1, SLOTS do
	local b = Instance.new("TextButton")
	b.Name = "Slot" .. tostring(i)
	b.Size = UDim2.new(0, SLOT_W, 0, SLOT_H)
	b.Position = UDim2.new(0, (i - 1) * (SLOT_W + SLOT_GAP), 0, 0)
	b.BackgroundColor3 = P.Floor
	b.BackgroundTransparency = 0.3
	b.BorderSizePixel = 0
	b.Text = ""
	b.AutoButtonColor = false
	b.Parent = beltStrip
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 10)
	c.Parent = b

	-- A colour bar across the top, in the item's own colour - the same colour
	-- it glows on its pad and on its plinth. Colour is never the only signal,
	-- but it is the FAST one, and a slot has to be identifiable in the corner
	-- of an eye that is busy driving.
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Size = UDim2.new(1, -12, 0, 5)
	bar.Position = UDim2.new(0, 6, 0, 6)
	bar.BorderSizePixel = 0
	bar.BackgroundTransparency = 1
	bar.Parent = b
	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(1, 0)
	barCorner.Parent = bar

	local name = Instance.new("TextLabel")
	name.Name = "Label"
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, -8, 0, 26)
	name.Position = UDim2.new(0, 4, 0, 16)
	name.Text = ""
	name.TextScaled = true
	name.Font = Enum.Font.GothamBlack
	name.TextColor3 = P.Ghost
	name.Parent = b
	-- TextScaled alone will happily render "SHIELD" at 26 points and "JET" at
	-- 26 too, but it will also blow a short word up to fill the box. Capping it
	-- keeps the five slots looking like one row rather than five posters.
	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = 17
	cap.MinTextSize = 8
	cap.Parent = name

	local charge = Instance.new("TextLabel")
	charge.Name = "Charges"
	charge.BackgroundTransparency = 1
	charge.Size = UDim2.new(1, -8, 0, 20)
	charge.Position = UDim2.new(0, 4, 1, -24)
	charge.Text = ""
	charge.TextSize = 17
	charge.Font = Enum.Font.GothamBlack
	charge.TextColor3 = P.Gold
	charge.Parent = b

	local order = Instance.new("TextLabel")
	order.Name = "Order"
	order.BackgroundTransparency = 1
	order.Size = UDim2.new(0, 16, 0, 14)
	order.Position = UDim2.new(0, 6, 1, -20)
	order.Text = tostring(i)
	order.TextSize = 11
	order.TextXAlignment = Enum.TextXAlignment.Left
	order.Font = Enum.Font.GothamBold
	order.TextColor3 = P.Boundary
	order.Parent = b

	b.Activated:Connect(function()
		-- A slot index is a selection, not a value. The server owns what is in
		-- the slot and rejects an index it does not hold.
		if Remotes and Remotes.SelectItem then
			Remotes.SelectItem:FireServer(i)
		end
	end)

	table.insert(slotButtons, b)
	table.insert(slotCharges, charge)
	table.insert(slotBars, bar)
end

local bankedValue = label(stack, UDim2.new(1, -24, 0, 40), UDim2.new(0, 14, 0, 112),
	"$0", P.Gold, 34, Enum.TextXAlignment.Right)
label(stack, UDim2.new(1, -24, 0, 16), UDim2.new(0, 14, 0, 148),
	"BANKED — SAFE", P.Gold, 12, Enum.TextXAlignment.Right)

-- ── Bottom RIGHT: the action buttons (D-CHOMP-071) ──────────────────────
-- Moved from the bottom left, where they were stealing the steering thumb.
--
-- The stick FLOATS: it anchors wherever a finger lands, so every button on the
-- left shrinks the area you can start steering in, and worse, you had to let go
-- of the wheel to press the one control that exists to save you. The escape
-- move must never cost you the steering.
--
-- Bottom-right is also where Roblox's own touch jump button lives, so it is
-- where a child who plays other Roblox games already reaches. Convention beats
-- our preference when the audience already has muscle memory.
--
-- Sized by urgency: the jump is a panic button pressed without looking, so it
-- is the largest thing on screen. Cycling is a planning action done between
-- fights, so it is smaller and sits beside rather than under the thumb.

local chargeButton = Instance.new("TextButton")
chargeButton.Name = "ChargeButton"
chargeButton.AnchorPoint = Vector2.new(1, 1)
chargeButton.Position = UDim2.new(1, -CONTROLS.ButtonMarginPx, 1, -CONTROLS.ButtonMarginPx)
chargeButton.Size = UDim2.new(0, CONTROLS.JumpButtonPx, 0, CONTROLS.JumpButtonPx)
chargeButton.BackgroundColor3 = P.BrickDark
chargeButton.BackgroundTransparency = 0.05
chargeButton.BorderSizePixel = 0
chargeButton.Text = ""
chargeButton.AutoButtonColor = false
chargeButton.ClipsDescendants = true
chargeButton.Parent = gui
local cbCorner = Instance.new("UICorner")
cbCorner.CornerRadius = UDim.new(1, 0)
cbCorner.Parent = chargeButton
local chargeStroke = Instance.new("UIStroke")
chargeStroke.Name = "ActiveOutline"
chargeStroke.Color = P.NeonA
chargeStroke.Thickness = 4
chargeStroke.Transparency = 0
chargeStroke.Parent = chargeButton

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
chargeLabel.Name = "Word"
chargeLabel.BackgroundTransparency = 1
chargeLabel.Size = UDim2.new(1, -28, 0, 32)
chargeLabel.Position = UDim2.new(0, 14, 0, 34)
chargeLabel.Text = "CHARGE"
chargeLabel.TextColor3 = P.Ghost
chargeLabel.TextScaled = true
chargeLabel.Font = Enum.Font.GothamBlack
chargeLabel.ZIndex = 2
chargeLabel.Parent = chargeButton

-- The percentage is the point (D-CHOMP-064). A ring that fills slowly with no
-- number on it, on a button that does nothing until it is full, is a button a
-- player decides is broken - which is exactly what happened. Now it counts up
-- to the jump in front of you, so the wait is visibly a wait.
local chargePercent = Instance.new("TextLabel")
chargePercent.Name = "Percent"
chargePercent.BackgroundTransparency = 1
chargePercent.Size = UDim2.new(1, -22, 0, 36)
chargePercent.Position = UDim2.new(0, 11, 0, 70)
chargePercent.Text = "0%"
chargePercent.TextColor3 = P.NeonA
chargePercent.TextSize = 13
chargePercent.TextWrapped = true
chargePercent.Font = Enum.Font.GothamBold
chargePercent.ZIndex = 2
chargePercent.Parent = chargeButton

-- Pressing it IS the jump - finger or mouse, one control (D-CHOMP-064).
-- Activated covers both, and neither the fill nor the two labels can swallow
-- the press: a TextLabel does not consume input, so the whole 150-pixel circle
-- is live all the way to its edge.
local refusedAt = 0
local function pressCharge()
	if Remotes and Remotes.UseCharge then
		-- Intent only. The server decides whether there is charge to spend, and
		-- the server is the only thing that knows.
		Remotes.UseCharge:FireServer()
	end
	-- A press with an empty bar has to ANSWER. Silence reads as broken; a red
	-- pulse reads as "not yet", which is the truth.
	local character = player.Character
	local level = character and (character:GetAttribute("ChompCharge") :: number?) or 0
	if level < Config.Charge.JumpCost then
		refusedAt = os.clock()
	end
end
chargeButton.Activated:Connect(pressCharge)

-- ── The cycle button ────────────────────────────────────────────────────
-- One button, one direction, wrapping. A back-cycle would double the controls
-- to save half a second, and the belt is spent in ORDER (D-CHOMP-062) - the
-- whole design depends on that order staying predictable, so cycling is purely
-- positional and never helpfully skips to something with more charges.
--
-- It sends a slot INDEX through the existing SelectItem remote, which the
-- server already validates against the belt it holds. No new network surface
-- and nothing for the exploit suite to learn (D-CHOMP-071).

local function beltEntries(): ({ string }, number)
	local character = player.Character
	local raw = character and character:GetAttribute("ChompBelt")
	local ids: { string } = {}
	if typeof(raw) == "string" and raw ~= "" then
		for chunk in string.gmatch(raw, "[^,]+") do
			local id = string.match(chunk, "^(.-):%d+$")
			table.insert(ids, id or "")
		end
	end
	local active = character and (character:GetAttribute("ChompActiveSlot") :: number?) or 1
	return ids, active
end

local cycleRefusedAt = 0
local function cycleItem()
	local ids, active = beltEntries()
	if #ids <= 1 then
		-- Nothing to cycle to. Say so with a pulse rather than doing nothing,
		-- because silence is what a child reads as broken.
		cycleRefusedAt = os.clock()
		return
	end
	-- Not named `next`: that is a Lua builtin, and shadowing it inside a loop
	-- is the kind of thing that reads fine and confuses whoever edits it later.
	local target = active
	for _ = 1, #ids do
		target = (target % #ids) + 1
		if ids[target] and ids[target] ~= "" then break end
	end
	if target ~= active and Remotes and Remotes.SelectItem then
		Remotes.SelectItem:FireServer(target)
	end
end

local cycleButton = Instance.new("TextButton")
cycleButton.Name = "CycleButton"
cycleButton.AnchorPoint = Vector2.new(1, 1)
cycleButton.Position = UDim2.new(1, -(CONTROLS.ButtonMarginPx * 2 + CONTROLS.JumpButtonPx),
	1, -CONTROLS.ButtonMarginPx)
cycleButton.Size = UDim2.new(0, CONTROLS.CycleButtonPx, 0, CONTROLS.CycleButtonPx)
cycleButton.BackgroundColor3 = P.BrickDark
cycleButton.BackgroundTransparency = 0.1
cycleButton.BorderSizePixel = 0
cycleButton.Text = ""
cycleButton.AutoButtonColor = false
cycleButton.Parent = gui
local cyCorner = Instance.new("UICorner")
cyCorner.CornerRadius = UDim.new(1, 0)
cyCorner.Parent = cycleButton

local cycleGlyph = Instance.new("TextLabel")
cycleGlyph.Name = "Glyph"
cycleGlyph.BackgroundTransparency = 1
cycleGlyph.Size = UDim2.new(1, 0, 0, 40)
cycleGlyph.Position = UDim2.new(0, 0, 0, 14)
-- An arrow going round, not a word. This button is pressed by someone who is
-- driving and cannot read it.
cycleGlyph.Text = "\u{27F3}"
cycleGlyph.TextColor3 = P.Ghost
cycleGlyph.TextSize = 34
cycleGlyph.Font = Enum.Font.GothamBlack
cycleGlyph.Parent = cycleButton

local cycleWord = Instance.new("TextLabel")
cycleWord.Name = "Word"
cycleWord.BackgroundTransparency = 1
cycleWord.Size = UDim2.new(1, -10, 0, 16)
cycleWord.Position = UDim2.new(0, 5, 1, -28)
cycleWord.Text = "SWAP"
cycleWord.TextColor3 = P.Boundary
cycleWord.TextSize = 12
cycleWord.Font = Enum.Font.GothamBold
cycleWord.Parent = cycleButton

cycleButton.Activated:Connect(cycleItem)

-- ── Keys ────────────────────────────────────────────────────────────────
-- Bound here rather than in InputController because the button and its keyboard
-- equivalent are the same control, and cycling needs the belt state this file
-- already reads every frame. InputController still owns steering and firing.
UserInputService.InputBegan:Connect(function(input, processed)
	if processed or input.UserInputType ~= Enum.UserInputType.Keyboard then return end
	if input.KeyCode == CONTROLS.CycleKey then
		cycleItem()
	elseif input.KeyCode == CONTROLS.JumpKey or input.KeyCode == CONTROLS.JumpKeyAlt then
		pressCharge()
	end
end)

-- ── Portrait fallback ───────────────────────────────────────────────────
-- The orientation is locked to landscape, so this should never fire. If a
-- device reports portrait anyway, the CYCLE button is the one that goes: you
-- can still choose an item by tapping its slot, but the jump is an escape and
-- there is no other way to reach it.
local function fitOrientation()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize
	if not viewport or viewport.Y <= 0 then return end
	cycleButton.Visible = (viewport.X / viewport.Y) >= CONTROLS.HideCycleBelowAspect
end
fitOrientation()
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fitOrientation)
end


-- ── Top centre: one objective ───────────────────────────────────────────
local centre = panel("Objective", Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 16), UDim2.new(0, 280, 0, 48))
local objective = label(centre, UDim2.new(1, -20, 1, -12), UDim2.new(0, 10, 0, 6),
	"COLLECT", P.NeonA, 22, Enum.TextXAlignment.Center)

local wavePanel = panel("Wave", Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 72), UDim2.new(0, 200, 0, 38))
local waveLabel = label(wavePanel, UDim2.new(1, -20, 1, -10), UDim2.new(0, 10, 0, 5),
	"WAVE 1", P.Ghost, 18, Enum.TextXAlignment.Center)

local ROTATING_TIPS = {
	{ text = "CHOMP GHOSTS FOR POINTS", colour = P.NeonA },
	{ text = "AMBUSH FROM THE SIDE", colour = P.Gold },
	{ text = "TAP BOMB TWICE", colour = P.NeonB },
	{ text = "JUMP TO ESCAPE", colour = P.NeonA },
	{ text = "YELLOW ZONES BANK CASH", colour = P.Shield },
}
local TIP_SECONDS = 5

-- The module selector used to occupy this space. Progression is the useful
-- information here: three continuous bars, finely ticked but never fragmented.
local levelPanel = panel("Attributes", Vector2.zero,
	UDim2.new(0, 16, 0, 170), UDim2.new(0, 218, 0, 150))
local powerLabel = label(levelPanel, UDim2.new(1, -20, 0, 24), UDim2.new(0, 10, 0, 6),
	"POWER 100", P.Gold, 16, Enum.TextXAlignment.Center)
local primaryAttributes = {
	{ track = "Engine", name = "SPEED" },
	{ track = "Armour", name = "ARMOUR" },
	{ track = "Cannon", name = "FIRE POWER" },
}
local attributeLabels: { [string]: TextLabel } = {}
local attributeBars: { [string]: Frame } = {}
for index, spec in primaryAttributes do
	local y = 34 + (index - 1) * 37
	attributeLabels[spec.track] = label(levelPanel, UDim2.new(1, -24, 0, 16),
		UDim2.new(0, 12, 0, y), spec.name .. "  LV 0", P.Ghost, 12,
		Enum.TextXAlignment.Left)
	local back = Instance.new("Frame")
	back.Name = spec.track .. "Bar"
	back.Position = UDim2.new(0, 12, 0, y + 18)
	back.Size = UDim2.new(1, -24, 0, 12)
	back.BackgroundColor3 = P.BrickDark
	back.BorderSizePixel = 0
	back.ClipsDescendants = true
	back.Parent = levelPanel
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = P.Gold
	fill.BorderSizePixel = 0
	fill.Parent = back
	for tick = 1, 11 do
		local mark = Instance.new("Frame")
		mark.Name = "Tick"
		mark.Position = UDim2.new(tick / 12, 0, 0, 0)
		mark.Size = UDim2.new(0, 1, 1, 0)
		mark.BackgroundColor3 = P.Ghost
		mark.BackgroundTransparency = 0.55
		mark.BorderSizePixel = 0
		mark.ZIndex = 2
		mark.Parent = back
	end
	attributeBars[spec.track] = fill
end

local guardianPanel = panel("Guardian", Vector2.new(0.5, 0),
	UDim2.new(0.5, 0, 0, 16), UDim2.new(0, 520, 0, 66))
local guardianLabel = label(guardianPanel, UDim2.new(1, -20, 0, 26), UDim2.new(0, 10, 0, 3),
	"GUARDIAN", P.Ghost, 19, Enum.TextXAlignment.Center)
local guardianBack = Instance.new("Frame")
guardianBack.Position = UDim2.new(0, 12, 0, 36)
guardianBack.Size = UDim2.new(1, -24, 0, 20)
guardianBack.BackgroundColor3 = P.BrickDark
guardianBack.BorderSizePixel = 0
guardianBack.Parent = guardianPanel
local guardianStroke = Instance.new("UIStroke")
guardianStroke.Color = P.Ghost
guardianStroke.Thickness = 2
guardianStroke.Transparency = 0.25
guardianStroke.Parent = guardianBack
local guardianFill = Instance.new("Frame")
guardianFill.Size = UDim2.fromScale(1, 1)
guardianFill.BackgroundColor3 = P.Danger
guardianFill.BorderSizePixel = 0
guardianFill.Parent = guardianBack
guardianPanel.Visible = false

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
healthBack.Position = UDim2.new(1, -16, 1, -(COLUMN_BASE + 252))
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
			local colour = itemColour(entry.id)
			-- The WHOLE label, never a truncation (D-CHOMP-064). "CANN" is not
			-- a shorter way of saying cannon, it is a different word.
			button.Label.Text = def and def.label or string.upper(entry.id)
			-- Active: filled in the item's colour with dark text on it.
			-- Waiting: dark, with the item's colour on the text and the bar.
			-- Either way the colour on screen is the colour of the thing.
			button.Label.TextColor3 = isActive and P.Floor or colour
			slotCharges[i].Text = entry.charges > 1 and ("x" .. tostring(entry.charges)) or ""
			slotCharges[i].TextColor3 = isActive and P.Floor or P.Gold
			slotBars[i].BackgroundColor3 = colour
			slotBars[i].BackgroundTransparency = isActive and 0.4 or 0
			button.BackgroundColor3 = isActive and colour or P.Floor
			button.BackgroundTransparency = isActive and 0.05 or 0.25
		else
			button.Label.Text = ""
			slotCharges[i].Text = ""
			slotBars[i].BackgroundTransparency = 1
			button.BackgroundColor3 = P.Floor
			button.BackgroundTransparency = 0.6
		end
	end

	-- ONE objective, chosen by what is most urgent rather than listed.
	-- Carrying a lot outranks everything: the thing most likely to be lost is
	-- the thing worth being told about.
	-- Safe outranks everything, including a big carry: the whole reason to know
	-- you are safe is that you were not a moment ago (D-CHOMP-065).
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local inGuardian = root ~= nil and root.Position.Y < Config.Guardian.RevealY
	local power = attribute("ChompPower")
	local requiredPower = attribute("ChompGuardianRequiredPower")
	if inGuardian and power < requiredPower then
		objective.Text = "POWER " .. tostring(requiredPower) .. " REQUIRED"
		objective.TextColor3 = P.Danger
	elseif inGuardian then
		objective.Text = "DESTROY THE GUARDIAN"
		objective.TextColor3 = P.Gold
	elseif character:GetAttribute("ChompSafe") == true then
		objective.Text = "SAFE — SHOP OR BANK"
		objective.TextColor3 = P.Shield
	else
		local tipIndex = math.floor(os.clock() / TIP_SECONDS) % #ROTATING_TIPS + 1
		local tip = ROTATING_TIPS[tipIndex]
		objective.Text = tip.text
		objective.TextColor3 = tip.colour
	end

	-- Charge. Full is the only state that matters, so full is the only state
	-- that changes the words: below it the button says CHARGE and does nothing,
	-- at it the button says JUMP and glows.
	local CH = Config.Charge
	local charge = attribute("ChompCharge")
	local ready = charge >= CH.JumpCost
	-- The fill measures progress toward the JUMP, not toward the cap. A bar
	-- that is only ever four fifths full when the thing it buys is available
	-- is a bar that lies about what it is for.
	local progress = math.clamp(charge / CH.JumpCost, 0, 1)
	chargeFill.Size = UDim2.new(1, 0, progress, 0)
	chargeFill.BackgroundColor3 = ready and P.Gold or P.NeonA
	chargeLabel.Text = ready and "JUMP" or "CHARGE"
	chargeLabel.TextColor3 = ready and P.Floor or P.Ghost
	local jumpLevel = attribute("ChompUpgradeJump")
	chargePercent.Text = "LV " .. tostring(jumpLevel) .. "  •  "
		.. (ready and "TAP TO JUMP" or (math.floor(progress * 100) .. "%"))
	chargePercent.TextColor3 = ready and P.Floor or P.NeonA
	chargeButton.Active = true
	chargeButton.BackgroundTransparency = ready and 0.02 or 0.05
	chargeStroke.Color = ready and P.Gold or P.NeonA

	-- Cycle refusal: the same language the charge button speaks, so a press
	-- that cannot do anything still answers.
	local sinceCycle = os.clock() - cycleRefusedAt
	cycleButton.BackgroundColor3 = sinceCycle < 0.3 and P.Danger or P.BrickDark

	-- Refusal pulse: 0.35 seconds of red, then back to whatever it was.
	local sinceRefused = os.clock() - refusedAt
	if sinceRefused < 0.35 then
		chargeButton.BackgroundColor3 = P.Danger
		chargeButton.BackgroundTransparency = 0.25 + sinceRefused
	else
		chargeButton.BackgroundColor3 = P.BrickDark
	end

	local waveNumber = attribute("ChompWave")
	local waveAlive = attribute("ChompWaveAlive")
	waveLabel.Text = (waveNumber > 0 and ("WAVE " .. tostring(waveNumber)) or "WAVE 1")
		.. "  •  " .. tostring(waveAlive) .. " LEFT"
	wavePanel.Visible = not inGuardian
	centre.Visible = not inGuardian

	powerLabel.Text = "POWER " .. tostring(math.floor(power))
	for _, spec in primaryAttributes do
		local level = (player:GetAttribute("ChompUpgrade" .. spec.track) :: number?) or 0
		attributeLabels[spec.track].Text = spec.name .. "  LV " .. tostring(level)
		attributeLabels[spec.track].TextColor3 = level > 0 and P.Gold or P.Ghost
		attributeBars[spec.track].Size = UDim2.new(
			math.clamp(level / Config.Upgrades.MaxLevel, 0, 1), 0, 1, 0)
	end

	guardianPanel.Visible = inGuardian
	if inGuardian then
		local guardianLevel = attribute("ChompGuardianLevel")
		local health = attribute("ChompGuardianHealth")
		local maxHealth = math.max(1, attribute("ChompGuardianMaxHealth"))
		guardianLabel.Text = "GUARDIAN " .. tostring(guardianLevel) .. "  •  "
			.. tostring(math.ceil(health)) .. "/" .. tostring(math.ceil(maxHealth))
		guardianFill.Size = UDim2.new(math.clamp(health / maxHealth, 0, 1), 0, 1, 0)
		guardianFill.BackgroundColor3 = P.Danger
	end

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
