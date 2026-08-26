--!strict
--[[
	GarageService — CHAIN-ECONOMY (D-CHOMP-055)

	The garage you start in, and the store you spend in.

	Everything buyable stands on a lit plinth with its price above it. You buy by
	driving up and holding still — no button, no menu, no confirmation dialog,
	which is the rule banking already follows and the reason this game has no UI
	to get lost in.

	Dwelling rather than touching matters. A child driving at speed will clip
	every plinth in the row, so requiring a second of stillness means a purchase
	is always something you meant.

	THE SERVER OWNS THE PRICE. The plinth carries a label; the label is not what
	is charged. A client cannot name a price, a discount, or an item it has not
	afforded (CHOMP-SYS-034).

	Robux prices are DISPLAYED and nothing more. Wiring a real purchase is a
	monetisation decision with consequences for a parent, not something to slip
	into an overnight build.

	The row sells WEAPONS as well as vehicles (D-CHOMP-064). Finding a cannon on
	a pad is luck; buying one is a plan, and a player who keeps dying can choose
	to arrive at the next wave armed instead of hoping. Items are the cheap end
	of the row for that reason - a shop only the winner can afford makes losing
	worse.

	A weapon purchase can be REFUSED by ItemService when the belt is full. The
	money is only taken after the grant succeeds, because a shop that charges
	for something it did not hand over is the one bug a child will never forgive.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("ChompConfig"))
local VehicleFactory = require(ServerStorage:WaitForChild("ChompTools"):WaitForChild("VehicleFactory"))
local ItemModels = require(ServerStorage:WaitForChild("ChompTools"):WaitForChild("ItemModels"))

local L = Config.Level1
local P = Config.Palette
local STORE = Config.Store
local UP = Config.Upgrades

local SPECS = ServerStorage:WaitForChild("ChompTools"):WaitForChild("VehicleSpecs")

local folder = Instance.new("Folder")
folder.Name = "Garage"
folder.Parent = Workspace

local function part(name: string, size: Vector3, cf: CFrame, colour: Color3,
		material: Enum.Material, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = colour
	p.Material = material
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function priceLabel(plinth: BasePart, title: string, dollars: number, robux: number?)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(0, 220, 0, 96)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 12, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 300
	gui.Adornee = plinth
	gui.Parent = plinth

	local function line(text: string, colour: Color3, size: number, y: number, font: Enum.Font)
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.new(1, 0, 0, size + 6)
		t.Position = UDim2.new(0, 0, 0, y)
		t.Text = text
		t.TextColor3 = colour
		t.TextStrokeColor3 = P.Floor
		t.TextStrokeTransparency = 0.2
		t.TextSize = size
		t.Font = font
		t.Parent = gui
	end

	line(title, P.Ghost, 22, 0, Enum.Font.GothamBlack)
	line("$" .. tostring(dollars), P.Gold, 26, 26, Enum.Font.GothamBold)
	if robux then
		line("or R$" .. tostring(robux), P.NeonA, 16, 60, Enum.Font.Gotham)
	end
end

type Offer = { id: string, kind: string, title: string, dollars: number, robux: number? }

-- Resolved lazily: this script and ItemService are both server scripts with no
-- guaranteed order, so asking for the hook at require time is a race.
local function grantHook(): BindableFunction?
	local tools = ServerStorage:FindFirstChild("ChompTools")
	local hook = tools and tools:FindFirstChild("GrantItem")
	return hook and hook:IsA("BindableFunction") and hook or nil
end

local function offers(): { Offer }
	local out: { Offer } = {}
	for id, chassis in Config.Chassis do
		if chassis.Cost and chassis.Cost > 0 then
			table.insert(out, {
				id = id, kind = "chassis", title = id,
				dollars = chassis.Cost, robux = STORE.RobuxPrice[id],
			})
		end
	end
	-- Cheapest first, so the row reads as a ladder rather than a shelf.
	table.sort(out, function(a, b) return a.dollars < b.dollars end)

	-- Weapons at the near end. They are the cheapest thing here and the thing a
	-- struggling player most needs, so they are what you reach first.
	local weapons: { Offer } = {}
	for id, dollars in STORE.ItemPrices do
		local def = Config.Items.Definitions[id]
		if def then
			table.insert(weapons, {
				id = id, kind = "item", title = def.label,
				dollars = dollars, robux = STORE.RobuxPrice[id],
			})
		end
	end
	table.sort(weapons, function(a, b) return a.dollars < b.dollars end)
	for i = #weapons, 1, -1 do
		table.insert(out, 1, weapons[i])
	end

	for _, track in { "Speed", "Agility", "Consumption" } do
		table.insert(out, {
			id = track, kind = "upgrade", title = track .. " I",
			dollars = UP.Costs[1], robux = STORE.RobuxPrice[track],
		})
	end
	return out
end

local plinths: { { part: BasePart, offer: Offer } } = {}

local function build(): number
	-- Beside the spawn pad, so the first thing you see is what you are working
	-- towards.
	local homeAngle = math.pi / L.GarageCount
	local radius = L.OuterRadius - L.RingSpacing / 2 - 22
	local list = offers()
	-- Tightened from 4.2 degrees when weapons joined the row (D-CHOMP-064): ten
	-- plinths at the old spacing ran most of the way round the ring. At this
	-- radius 2.9 degrees is about 38 studs, comfortably more than the 13-stud
	-- dwell radius, so a kart is never inside two offers at once.
	local step = math.rad(2.9)

	for i, offer in ipairs(list) do
		local a = homeAngle + step * (i - (#list + 1) / 2)
		local pos = Vector3.new(math.cos(a) * radius, 0, math.sin(a) * radius)
		local facing = CFrame.Angles(0, -a, 0)

		local base = part("Plinth", Vector3.new(9, 6, 9),
			CFrame.new(pos + Vector3.new(0, 3, 0)) * facing,
			P.BrickDark, Enum.Material.Metal, folder)
		-- The glow says WHAT KIND of thing this is before you can read the sign:
		-- gold for a vehicle, the item's own colour for a weapon, teal for a
		-- tuning upgrade.
		local glowColour = if offer.kind == "chassis" then P.Gold
			elseif offer.kind == "item" then ItemModels.colour(offer.id)
			else P.NeonA
		local glow = part("PlinthGlow", Vector3.new(9.4, 0.6, 9.4),
			CFrame.new(pos + Vector3.new(0, 6.2, 0)) * facing,
			glowColour, Enum.Material.Neon, folder)
		glow.CanCollide = false
		CollectionService:AddTag(base, "Chomp_Decor")
		CollectionService:AddTag(glow, "Chomp_Decor")

		if offer.kind == "chassis" then
			-- Show the actual vehicle. Buying something you have looked at is a
			-- different decision from buying a name in a list.
			local module = SPECS:FindFirstChild(offer.id)
			if module and module:IsA("ModuleScript") then
				local ok, model = pcall(function()
					return VehicleFactory.build(require(module) :: any)
				end)
				if ok and model then
					for _, d in model:GetDescendants() do
						if d:IsA("BasePart") then
							d.Anchored = true
							d.CanCollide = false
							d.CanQuery = false
							CollectionService:AddTag(d, "Chomp_Decor")
						end
					end
					model:PivotTo(CFrame.new(pos + Vector3.new(0, 9, 0)) * facing)
					model.Parent = folder
				end
			end
		elseif offer.kind == "item" then
			-- The SAME model that stands on a pad in the maze and bolts to your
			-- roof, from the shared factory (D-CHOMP-064). A shop that shows a
			-- different shape from the thing it sells is a shop that lies.
			local model = ItemModels.build(offer.id)
			model:PivotTo(CFrame.new(pos + Vector3.new(0, 9.5, 0)) * facing)
			model.Parent = folder

		else
			-- Upgrades have no model. A clear token beats a misleading one.
			local token = part("UpgradeToken", Vector3.new(4, 4, 4),
				CFrame.new(pos + Vector3.new(0, 9.5, 0)) * facing * CFrame.Angles(0.5, 0, 0.5),
				P.NeonA, Enum.Material.Neon, folder)
			token.CanCollide = false
			CollectionService:AddTag(token, "Chomp_Decor")
		end

		priceLabel(base, offer.title, offer.dollars, offer.robux)
		table.insert(plinths, { part = base, offer = offer })
	end
	return #plinths
end

-- ── Bank beacons ────────────────────────────────────────────────────────
-- A pillar of light with a chest turning inside it, over every garage pad.
--
-- Banking has no button and no prompt by design (D-CHOMP-048), which leaves it
-- with a discoverability problem: a player carrying points has to already know
-- that driving onto a pad is the thing that saves them. A beam visible across
-- the arena and a chest that obviously holds money answers that without adding
-- a single word of UI.
local chests: { Model } = {}

local function buildBeacon(pad: BasePart)
	local centre = pad.Position

	local beam = part("BankBeam", Vector3.new(1, 260, 1),
		CFrame.new(centre + Vector3.new(0, 130, 0)), P.Gold, Enum.Material.Neon, folder)
	beam.Shape = Enum.PartType.Cylinder
	beam.Size = Vector3.new(260, 26, 26)
	beam.CFrame = CFrame.new(centre + Vector3.new(0, 130, 0)) * CFrame.Angles(0, 0, math.rad(90))
	beam.Transparency = 0.86
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CastShadow = false
	CollectionService:AddTag(beam, "Chomp_Decor")

	local chest = Instance.new("Model")
	chest.Name = "BankChest"

	local body = part("ChestBody", Vector3.new(7, 4.6, 5),
		CFrame.new(centre + Vector3.new(0, 13, 0)), Color3.fromRGB(96, 58, 32),
		Enum.Material.Wood, chest)
	local lid = part("ChestLid", Vector3.new(7.2, 1.8, 5.2),
		CFrame.new(centre + Vector3.new(0, 16.2, -0.4)) * CFrame.Angles(math.rad(-22), 0, 0),
		Color3.fromRGB(112, 68, 38), Enum.Material.Wood, chest)
	local gold = part("ChestGold", Vector3.new(5.6, 1.6, 3.8),
		CFrame.new(centre + Vector3.new(0, 15, 0)), P.Gold, Enum.Material.Neon, chest)
	for _, band in { -2.2, 2.2 } do
		part("ChestBand", Vector3.new(0.8, 5, 5.3),
			CFrame.new(centre + Vector3.new(band, 13.4, 0)), P.Gold, Enum.Material.Metal, chest)
	end

	for _, d in chest:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			CollectionService:AddTag(d, "Chomp_Decor")
		end
	end
	chest.PrimaryPart = body
	chest:SetAttribute("HomeY", centre.Y + 13)
	chest.Parent = folder
	table.insert(chests, chest)

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(0, 210, 0, 44)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 7, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 400
	gui.Adornee = body
	gui.Parent = body
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.new(1, 0, 1, 0)
	t.Text = "BANK HERE"
	t.TextColor3 = P.Gold
	t.TextStrokeColor3 = P.Floor
	t.TextStrokeTransparency = 0.2
	t.TextScaled = true
	t.Font = Enum.Font.GothamBlack
	t.Parent = gui
end

local function animateChests()
	local clock = 0
	game:GetService("RunService").Heartbeat:Connect(function(dt)
		clock += dt
		for _, chest in chests do
			local homeY = chest:GetAttribute("HomeY")
			if typeof(homeY) == "number" and chest.PrimaryPart then
				local pivot = chest:GetPivot()
				chest:PivotTo(CFrame.new(pivot.Position.X, homeY + math.sin(clock * 1.5) * 1.8, pivot.Position.Z)
					* CFrame.Angles(0, clock * 0.9, 0))
			end
		end
	end)
end

local function refitVehicle(player: Player)
	-- VehicleService builds the kart on spawn from ChompChassis. Rather than
	-- duplicating that here, drop the old kart and let it rebuild.
	local character = player.Character
	local vehicle = character and character:FindFirstChild("Vehicle")
	if vehicle then vehicle:Destroy() end
	if character then character:SetAttribute("ChompRefit", os.clock()) end
end

local function buy(player: Player, offer: Offer): boolean
	local character = player.Character
	if not character then return false end
	local dollars = (character:GetAttribute("ChompDollars") :: number?) or 0
	if dollars < offer.dollars then return false end

	if offer.kind == "chassis" then
		if character:GetAttribute("ChompChassis") == offer.id then return false end
		character:SetAttribute("ChompChassis", offer.id)
		refitVehicle(player)
	elseif offer.kind == "item" then
		-- Hand it over FIRST. give() refuses a full belt, and a refusal must
		-- cost nothing - the player drives away with their money and the plinth
		-- still stocked (D-CHOMP-064).
		local hook = grantHook()
		if not hook then
			warn("[GarageService] ItemService has not published GrantItem; weapons unsellable")
			return false
		end
		local ok, granted = pcall(function()
			return hook:Invoke(player, offer.id)
		end)
		if not (ok and granted == true) then return false end
	else
		local key = "ChompUpgrade" .. offer.id
		local level = (character:GetAttribute(key) :: number?) or 0
		if level >= UP.MaxLevel then return false end
		character:SetAttribute(key, level + 1)
	end

	character:SetAttribute("ChompDollars", dollars - offer.dollars)
	character:SetAttribute("ChompBoughtWhat", offer.title)
	character:SetAttribute("ChompBoughtAt", os.clock())
	return true
end

local function dwellLoop()
	local dwelling: { [Player]: { plinth: BasePart?, since: number } } = {}
	while true do
		task.wait(0.15)
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not root then continue end

			local nearOffer: Offer? = nil
			local nearPart: BasePart? = nil
			for _, entry in plinths do
				if (entry.part.Position - root.Position).Magnitude < STORE.PlinthRadiusStuds then
					nearOffer, nearPart = entry.offer, entry.part
					break
				end
			end

			local state = dwelling[player]
			if nearPart and state and state.plinth == nearPart then
				if os.clock() - state.since >= STORE.DwellSeconds then
					if nearOffer and buy(player, nearOffer) then
						dwelling[player] = { plinth = nil, since = 0 }
					else
						-- Refused: back off rather than retrying every tick.
						state.since = os.clock() + 3
					end
				end
			else
				dwelling[player] = { plinth = nearPart, since = os.clock() }
			end
		end
	end
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		-- Everyone starts in the basic chassis, in the garage, with the ladder
		-- in front of them.
		if character:GetAttribute("ChompChassis") == nil then
			character:SetAttribute("ChompChassis", Config.StartingChassis)
		end
	end)
end)

local count = build()
for _, pad in CollectionService:GetTagged("Chomp_Garage") do
	if pad:IsA("BasePart") then buildBeacon(pad) end
end
animateChests()
task.spawn(dwellLoop)

local sellable = 0
for _ in STORE.ItemPrices do sellable += 1 end
print(("[GarageService] %d plinths (%d of them weapons), dwell %.1fs to buy, " ..
	"Robux labels are display only"):format(count, sellable, STORE.DwellSeconds))
