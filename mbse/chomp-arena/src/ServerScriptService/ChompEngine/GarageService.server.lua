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
local Progression = require(ReplicatedStorage:WaitForChild("ChompLogic"):WaitForChild("Progression"))

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
	gui.MaxDistance = 600
	gui.Adornee = plinth
	gui.Parent = plinth
	local backing = Instance.new("Frame")
	backing.Size = UDim2.fromScale(1, 1)
	backing.BackgroundColor3 = P.Floor
	backing.BackgroundTransparency = 0.12
	backing.BorderSizePixel = 0
	backing.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = backing
	local stroke = Instance.new("UIStroke")
	stroke.Color = P.Gold
	stroke.Thickness = 2
	stroke.Transparency = 0.15
	stroke.Parent = backing

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
		t.ZIndex = 2
		t.Parent = gui
	end

	line(title, P.Ghost, 22, 0, Enum.Font.GothamBlack)
	line("$" .. tostring(dollars), P.Gold, 26, 26, Enum.Font.GothamBold)
	-- Robux lines are OFF (D-CHOMP-066, LAUNCH-READINESS P0). They never charged
	-- anyone - the store has always been dollars-only - so every one of them was
	-- an advertisement for a purchase that does not exist, priced in real money,
	-- on a plinth in a game built for a seven-year-old. Showing a child a real
	-- currency the game cannot take is the kind of thing you fix before the
	-- first stranger plays it, not after.
	--
	-- The prices stay in ChompConfig. Wiring a real purchase is a decision for
	-- a parent, and when someone makes it this flag is where it starts.
	if robux and STORE.ShowRobuxPrices then
		line("or R$" .. tostring(robux), P.NeonA, 16, 60, Enum.Font.Gotham)
	end
end

type Offer = { id: string, kind: string, title: string, dollars: number, robux: number? }

local TRACKS = Config.Upgrades.Tracks

local function upgradesOf(player: Player)
	return {
		Engine = (player:GetAttribute("ChompUpgradeEngine") :: number?) or 0,
		Handling = (player:GetAttribute("ChompUpgradeHandling") :: number?) or 0,
		Armour = (player:GetAttribute("ChompUpgradeArmour") :: number?) or 0,
		Cannon = (player:GetAttribute("ChompUpgradeCannon") :: number?) or 0,
		Ordnance = (player:GetAttribute("ChompUpgradeOrdnance") :: number?) or 0,
		Jump = (player:GetAttribute("ChompUpgradeJump") :: number?) or 0,
		Boost = (player:GetAttribute("ChompUpgradeBoost") :: number?) or 0,
	}
end

local function owns(player: Player, chassisId: string): boolean
	local raw = (player:GetAttribute("ChompOwnedChassis") :: string?) or "Standard"
	return string.find("," .. raw .. ",", "," .. chassisId .. ",", 1, true) ~= nil
end

local function addOwned(player: Player, chassisId: string)
	if owns(player, chassisId) then return end
	local raw = (player:GetAttribute("ChompOwnedChassis") :: string?) or "Standard"
	player:SetAttribute("ChompOwnedChassis", raw .. "," .. chassisId)
end

local function publishProgression(player: Player, character: Model)
	local chassisId = (player:GetAttribute("ChompEquippedChassis") :: string?) or Config.StartingChassis
	local upgrades = upgradesOf(player)
	local stats = Progression.effectiveStats(chassisId, upgrades)
	character:SetAttribute("ChompPower", Progression.computePower(chassisId, upgrades))
	character:SetAttribute("ChompBarCapacity", Config.Chassis[chassisId].BarCapacity)
	character:SetAttribute("ChompMouthArcDegrees", stats.mouthArcDegrees)
	character:SetAttribute("ChompPelletMultiplier", stats.pelletMultiplier)
	character:SetAttribute("ChompChargeMultiplier", stats.chargeMultiplier)
	character:SetAttribute("ChompChargeCapacity", stats.chargeCapacity)
	character:SetAttribute("ChompMaxHealth", stats.maxHealth)
	character:SetAttribute("ChompModulePorts", stats.modulePorts)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then humanoid.MaxHealth = stats.maxHealth end
end

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

	for _, track in TRACKS do
		table.insert(out, {
			id = track, kind = "upgrade", title = track .. " UPGRADE",
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
	-- Permanent unlocks get the hero row. Consumable refills sit on a shorter
	-- inner row. Fourteen offers on the old single row overlapped dwell radii,
	-- so stopping at one plinth could buy its neighbour as well.
	local permanentCount, itemCount = 0, 0
	for _, offer in list do
		if offer.kind == "item" then itemCount += 1 else permanentCount += 1 end
	end
	local permanentIndex, itemIndex = 0, 0
	local permanentStep = math.rad(4.4)
	local itemStep = math.rad(5.2)
	local shopPos = Vector3.new(math.cos(homeAngle) * radius, 0, math.sin(homeAngle) * radius)
	local beacon = part("ShopBeacon", Vector3.new(2, 90, 2),
		CFrame.new(shopPos + Vector3.new(0, 45, 0)), P.NeonB, Enum.Material.Neon, folder)
	beacon.Transparency = 0.42
	beacon.CanCollide = false
	beacon.CanQuery = false
	beacon.CastShadow = false
	CollectionService:AddTag(beacon, "Chomp_Decor")
	local shopGui = Instance.new("BillboardGui")
	shopGui.Size = UDim2.new(0, 420, 0, 110)
	shopGui.StudsOffsetWorldSpace = Vector3.new(0, 53, 0)
	shopGui.AlwaysOnTop = true
	shopGui.MaxDistance = 900
	shopGui.Adornee = beacon
	shopGui.Parent = beacon
	local shopLabel = Instance.new("TextLabel")
	shopLabel.Size = UDim2.fromScale(1, 1)
	shopLabel.BackgroundColor3 = P.Floor
	shopLabel.BackgroundTransparency = 0.08
	shopLabel.Text = "SHOP\nWEAPONS  •  VEHICLES  •  UPGRADES"
	shopLabel.TextColor3 = P.Gold
	shopLabel.TextStrokeColor3 = P.Floor
	shopLabel.TextStrokeTransparency = 0
	shopLabel.TextScaled = true
	shopLabel.Font = Enum.Font.GothamBlack
	shopLabel.Parent = shopGui

	for _, offer in ipairs(list) do
		local rowRadius, a
		if offer.kind == "item" then
			itemIndex += 1
			rowRadius = radius - 34
			a = homeAngle + itemStep * (itemIndex - (itemCount + 1) / 2)
		else
			permanentIndex += 1
			rowRadius = radius
			a = homeAngle + permanentStep * (permanentIndex - (permanentCount + 1) / 2)
		end
		local pos = Vector3.new(math.cos(a) * rowRadius, 0, math.sin(a) * rowRadius)
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
		local light = Instance.new("PointLight")
		light.Color = glowColour
		light.Brightness = 3
		light.Range = 28
		light.Shadows = false
		light.Parent = glow
		local column = part("OfferBeam", Vector3.new(0.8, 18, 0.8),
			CFrame.new(pos + Vector3.new(0, 14, 0)), glowColour, Enum.Material.Neon, folder)
		column.Transparency = 0.58
		column.CanCollide = false
		column.CanQuery = false
		column.CastShadow = false
		CollectionService:AddTag(column, "Chomp_Decor")
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
			model:ScaleTo(1.8)
			model:PivotTo(CFrame.new(pos + Vector3.new(0, 9.5, 0)) * facing)
			model.Parent = folder

		else
			-- Permanent upgrades show the actual module that will be mounted. Generic
			-- glowing cubes made seven distinct choices look identical.
			local model = ItemModels.buildUpgrade(offer.id, UP.MaxLevel)
			model:ScaleTo(1.35)
			model:PivotTo(CFrame.new(pos + Vector3.new(0, 9.5, 0)) * facing)
			model.Parent = folder
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

	-- ── The sanctuary line ──────────────────────────────────────────────
	-- A rule the player cannot see is not a mechanic, it is a surprise. Ghosts
	-- may not cross this, so it is drawn on the floor: a ring of light you pass
	-- over, wide enough to notice at speed (D-CHOMP-065).
	--
	-- Drawn as segments rather than one thin cylinder, because a 300-stud ring
	-- two studs wide disappears at any distance and this is a line whose exact
	-- position matters when something is chasing you.
	local safeRadius = pad:GetAttribute("Home") == true
		and L.HomeSafeRadiusStuds or L.GarageSafeRadiusStuds
	local segments = math.max(24, math.floor(safeRadius / 4))
	for i = 0, segments - 1 do
		local a = (math.pi * 2) * (i / segments)
		local chord = 2 * safeRadius * math.sin(math.pi / segments)
		local marker = part("SafeLine", Vector3.new(2.5, 0.3, chord + 0.6),
			CFrame.new(centre + Vector3.new(math.cos(a) * safeRadius, -0.3,
				math.sin(a) * safeRadius)) * CFrame.Angles(0, -a, 0),
			P.Shield, Enum.Material.Neon, folder)
		marker.Transparency = 0.35
		marker.CanCollide = false
		marker.CanQuery = false
		marker.CastShadow = false
		CollectionService:AddTag(marker, "Chomp_Decor")
	end

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

local function currentOffer(player: Player, offer: Offer): (string, number)
	if offer.kind ~= "upgrade" then return offer.title, offer.dollars end
	local level = (player:GetAttribute("ChompUpgrade" .. offer.id) :: number?) or 0
	local price = Progression.costOf(offer.id,
		(player:GetAttribute("ChompEquippedChassis") :: string?) or Config.StartingChassis,
		upgradesOf(player)) or -1
	return offer.id .. " " .. tostring(level + 1), price
end

local function buy(player: Player, offer: Offer): (boolean, string)
	local character = player.Character
	if not character then return false, "VEHICLE NOT READY" end
	-- Nothing permanent may be sold into a session that cannot save
	-- (D-CHOMP-066). A degraded profile still plays, banks and fights; it just
	-- does not spend, because a chassis bought and then gone at rejoin is worse
	-- than one never bought.
	if player:GetAttribute("ChompProfileSaveBlocked") == true then
		return false, "PROGRESS NOT SAVING - CANNOT BUY"
	end
	local dollars = (character:GetAttribute("ChompDollars") :: number?) or 0
	local displayTitle, price = currentOffer(player, offer)

	if offer.kind == "chassis" then
		if owns(player, offer.id) then
			player:SetAttribute("ChompEquippedChassis", offer.id)
			character:SetAttribute("ChompChassis", offer.id)
			publishProgression(player, character)
			refitVehicle(player)
			character:SetAttribute("ChompBoughtWhat", offer.title .. " EQUIPPED")
			character:SetAttribute("ChompBoughtAt", os.clock())
			return true, "EQUIPPED"
		end
		if not SPECS:FindFirstChild(offer.id) then return false, "MODEL NOT READY" end
		if dollars < price then return false, "NEED $" .. tostring(price - dollars) .. " MORE" end
		addOwned(player, offer.id)
		player:SetAttribute("ChompEquippedChassis", offer.id)
		character:SetAttribute("ChompChassis", offer.id)
		publishProgression(player, character)
		refitVehicle(player)
	elseif offer.kind == "item" then
		if dollars < price then return false, "NEED $" .. tostring(price - dollars) .. " MORE" end
		-- Hand it over FIRST. give() refuses a full belt, and a refusal must
		-- cost nothing - the player drives away with their money and the plinth
		-- still stocked (D-CHOMP-064).
		local hook = grantHook()
		if not hook then
			warn("[GarageService] ItemService has not published GrantItem; weapons unsellable")
			return false, "ITEM SYSTEM NOT READY"
		end
		local ok, granted = pcall(function()
			return hook:Invoke(player, offer.id, true)
		end)
		if not (ok and granted == true) then return false, "COULD NOT EQUIP" end
	else
		if price < 0 then return false, "MAX LEVEL" end
		if dollars < price then return false, "NEED $" .. tostring(price - dollars) .. " MORE" end
		local key = "ChompUpgrade" .. offer.id
		local level = (player:GetAttribute(key) :: number?) or 0
		player:SetAttribute(key, level + 1)
		character:SetAttribute(key, level + 1)
		publishProgression(player, character)
	end

	character:SetAttribute("ChompDollars", dollars - price)
	character:SetAttribute("ChompBoughtWhat", displayTitle)
	character:SetAttribute("ChompBoughtAt", os.clock())
	return true, "PURCHASED"
end

local function dwellLoop()
	local dwelling: { [Player]: { plinth: BasePart?, since: number, complete: boolean? } } = {}
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

			if nearOffer and character then
				local title, price = currentOffer(player, nearOffer)
				character:SetAttribute("ChompShopOffer", title)
				character:SetAttribute("ChompShopPrice", price)
			else
				character:SetAttribute("ChompShopOffer", "")
				character:SetAttribute("ChompShopProgress", 0)
			end

			local state = dwelling[player]
			local moving = root.AssemblyLinearVelocity.Magnitude > STORE.MaxPurchaseSpeed
			if nearPart and state and state.plinth == nearPart and state.complete then
				character:SetAttribute("ChompShopProgress", 1)
				character:SetAttribute("ChompShopHint", "PURCHASED - DRIVE AWAY")
			elseif nearPart and moving then
				dwelling[player] = { plinth = nearPart, since = os.clock() }
				character:SetAttribute("ChompShopProgress", 0)
				character:SetAttribute("ChompShopHint", "STOP TO BUY")
			elseif nearPart and state and state.plinth == nearPart then
				local elapsed = os.clock() - state.since
				character:SetAttribute("ChompShopProgress", math.clamp(elapsed / STORE.DwellSeconds, 0, 1))
				character:SetAttribute("ChompShopHint", "HOLD STILL")
				if elapsed >= STORE.DwellSeconds then
					local bought, reason = false, "NO OFFER"
					if nearOffer then bought, reason = buy(player, nearOffer) end
					if bought then
						character:SetAttribute("ChompShopResult", reason)
						character:SetAttribute("ChompShopResultAt", os.clock())
						dwelling[player] = { plinth = nearPart, since = 0, complete = true }
					else
						character:SetAttribute("ChompShopResult", reason)
						character:SetAttribute("ChompShopResultAt", os.clock())
						state.since = os.clock() + STORE.RefusalCooldownSeconds
					end
				end
			else
				dwelling[player] = { plinth = nearPart, since = os.clock() }
				character:SetAttribute("ChompShopProgress", 0)
			end
		end
	end
end

Players.PlayerAdded:Connect(function(player)
	if player:GetAttribute("ChompOwnedChassis") == nil then player:SetAttribute("ChompOwnedChassis", "Standard") end
	if player:GetAttribute("ChompEquippedChassis") == nil then
		player:SetAttribute("ChompEquippedChassis", Config.StartingChassis)
	end
	for _, track in TRACKS do
		if player:GetAttribute("ChompUpgrade" .. track) == nil then
			player:SetAttribute("ChompUpgrade" .. track, 0)
		end
	end
	player.CharacterAdded:Connect(function(character)
		character:SetAttribute("ChompChassis",
			player:GetAttribute("ChompEquippedChassis") or Config.StartingChassis)
		for _, track in TRACKS do
			character:SetAttribute("ChompUpgrade" .. track,
				player:GetAttribute("ChompUpgrade" .. track) or 0)
		end
		publishProgression(player, character)
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
