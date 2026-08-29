--!strict
--[[
	Level1Map — CHAIN-MAZE (D-CHOMP-046)

	One level, sealed, and big. A disc 800 studs across with a boundary wall you
	cannot get past, concentric ring corridors you can hold a line around, and an
	open arena in the middle where the reward is.

	The bowl this replaces was two levels with a drop between them, and a drop is
	a way to fall out of the map. Everything here is at y = 0. The only vertical
	thing in the arena is a wall.

	Each ring has its own SURFACE - brick, slate, cobblestone, concrete, with
	neon used sparingly as landmarks (D-CHOMP-063). That is navigation, not
	decoration: at speed a driver needs to know which ring they are on without
	stopping to count, and "the cobbled one" is a landmark in a way that "the
	third identical corridor" never is. Texture reads before colour does, and it
	keeps reading when the neon is behind you.

	Every wall is tagged Chomp_Wall so the camera can fade it (D-CHOMP-043).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("ChompConfig"))
local M = Config.Map
local L = Config.Level1
local P = Config.Palette

if M.Layout ~= "Level1" then
	return
end

Workspace:SetAttribute("ChompLevel1MapReady", false)

local WALL_H = M.WallHeight
local WALL_T = M.WallThickness
local SLAB = M.SlabThickness
local TAU = math.pi * 2
local WALL_Y = SLAB / 2 + WALL_H / 2

local function part(name: string, size: Vector3, cf: CFrame, colour: Color3,
		material: Enum.Material, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Anchored = true
	p.Material = material
	p.Color = colour
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function onCircle(radius: number, angle: number, y: number): Vector3
	return Vector3.new(math.cos(angle) * radius, y, math.sin(angle) * radius)
end

-- Local Z tangent to the circle: CFrame.Angles(0, t, 0) puts local Z along
-- (sin t, 0, cos t), and the tangent at `angle` is (-sin a, 0, cos a), so t = -a.
local function tangentAt(radius: number, angle: number, y: number): CFrame
	return CFrame.new(onCircle(radius, angle, y)) * CFrame.Angles(0, -angle, 0)
end

-- Local Z outward along the radius: local Z must be (cos a, 0, sin a), t = pi/2 - a.
local function radialAt(radius: number, angle: number, y: number): CFrame
	return CFrame.new(onCircle(radius, angle, y)) * CFrame.Angles(0, math.pi / 2 - angle, 0)
end

local function arc(parent: Instance, name: string, radius: number, from: number, to: number,
		y: number, height: number, thickness: number, colour: Color3,
		material: Enum.Material): number
	local span = to - from
	if span <= 0 then return 0 end
	local segments = math.max(1, math.ceil(radius * span / L.SegmentStuds))
	for i = 0, segments - 1 do
		local a0 = from + span * (i / segments)
		local a1 = from + span * ((i + 1) / segments)
		local mid = (a0 + a1) / 2
		-- chord, not arc length: the box is straight and must meet its neighbours
		local chord = 2 * radius * math.sin((a1 - a0) / 2)
		local p = part(name, Vector3.new(thickness, height, chord + 0.4),
			tangentAt(radius, mid, y), colour, material, parent)
		CollectionService:AddTag(p, "Chomp_Wall")
		-- From the 38-degree camera the wall TOP is the maze. Masonry used to
		-- disappear into the floor, so a thin cap traces every solid route without
		-- turning the whole wall into neon.
		if material ~= Enum.Material.Neon then
			local cap = part("WallCap", Vector3.new(thickness + 0.35, 0.38, chord + 0.55),
				tangentAt(radius, mid, y + height / 2 + 0.19), P.NeonA,
				Enum.Material.Neon, parent)
			cap.CanCollide = false
			cap.CanQuery = false
			cap.CastShadow = false
			CollectionService:AddTag(cap, "Chomp_Wall")
		end
	end
	return segments
end

local function styleAt(index: number)
	local styles = L.RingStyles
	if not styles or #styles == 0 then
		return { material = Enum.Material.Brick, colour = "Brick" }
	end
	return styles[((index - 1) % #styles) + 1]
end

local function build()
	local maps = Workspace:FindFirstChild("Maps") or Instance.new("Folder")
	maps.Name = "Maps"
	maps.Parent = Workspace
	for _, old in maps:GetChildren() do old:Destroy() end

	local map = Instance.new("Folder"); map.Name = "Level1"; map.Parent = maps
	local rings = Instance.new("Folder"); rings.Name = "Rings"; rings.Parent = map
	local bays = Instance.new("Folder"); bays.Name = "Garages"; bays.Parent = map

	-- ── Floor and centre hatch ───────────────────────────────────────────
	-- Four slabs leave a real opening. A single cylinder can look like a hole,
	-- but it cannot contain one, and the guardian entrance must be physical.
	local diameter = L.OuterRadius * 2
	local hatch = Config.Guardian.HatchHalfStuds
	local sideDepth = L.OuterRadius - hatch
	for _, z in { -(hatch + sideDepth / 2), hatch + sideDepth / 2 } do
		part("Floor", Vector3.new(diameter, SLAB, sideDepth),
			CFrame.new(0, 0, z), P.Floor, Enum.Material.Concrete, map)
	end
	for _, x in { -(hatch + sideDepth / 2), hatch + sideDepth / 2 } do
		part("Floor", Vector3.new(sideDepth, SLAB, hatch * 2),
			CFrame.new(x, 0, 0), P.Floor, Enum.Material.Concrete, map)
	end

	local rimWidth = 3
	for _, z in { -hatch, hatch } do
		local rim = part("GuardianHatchRim", Vector3.new(hatch * 2 + rimWidth * 2, 0.6, rimWidth),
			CFrame.new(0, SLAB / 2 + 0.3, z), P.Danger, Enum.Material.Neon, map)
		rim.CanCollide = false
	end
	for _, x in { -hatch, hatch } do
		local rim = part("GuardianHatchRim", Vector3.new(rimWidth, 0.6, hatch * 2),
			CFrame.new(x, SLAB / 2 + 0.3, 0), P.Danger, Enum.Material.Neon, map)
		rim.CanCollide = false
	end
	local guardianGate = part("GuardianRoundGate", Vector3.new(hatch * 2, 1, hatch * 2),
		CFrame.new(0, 0.35, 0), P.Danger, Enum.Material.Neon, map)
	local guardianAvailable = Workspace:GetAttribute("ChompGuardianAvailable") == true
	guardianGate.CanCollide = not guardianAvailable
	guardianGate.CanQuery = not guardianAvailable
	guardianGate.Transparency = guardianAvailable and 1 or 0.18
	guardianGate:SetAttribute("RequiredRounds", Config.Match.RoundsPerMatch)
	CollectionService:AddTag(guardianGate, "Chomp_Wall")
	local gateGui = Instance.new("SurfaceGui")
	gateGui.Name = "RoundGateLabel"
	gateGui.Face = Enum.NormalId.Top
	gateGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gateGui.PixelsPerStud = 18
	gateGui.Enabled = not guardianAvailable
	gateGui.Parent = guardianGate
	local gateText = Instance.new("TextLabel")
	gateText.Size = UDim2.fromScale(1, 1)
	gateText.BackgroundTransparency = 1
	gateText.Text = "GUARDIAN LOCKED\nCLEAR " .. tostring(Config.Match.RoundsPerMatch) .. " ROUNDS"
	gateText.TextColor3 = P.Ghost
	gateText.TextStrokeColor3 = P.Floor
	gateText.TextStrokeTransparency = 0
	gateText.TextScaled = true
	gateText.Font = Enum.Font.GothamBlack
	gateText.Parent = gateGui

	-- The shaft and chamber are authored as map geometry so bullets, vehicles,
	-- camera occlusion, and ghosts all agree about what is solid.
	local arena = Instance.new("Folder"); arena.Name = "GuardianArena"; arena.Parent = map
	local chamberY = Config.Guardian.ChamberY
	local chamberHalf = Config.Guardian.ChamberHalfStuds
	local shaftHeight = Config.Guardian.ShaftLengthStuds
	for _, x in { -(hatch + WALL_T / 2), hatch + WALL_T / 2 } do
		local wall = part("ShaftWall", Vector3.new(WALL_T, shaftHeight, hatch * 2 + WALL_T * 2),
			CFrame.new(x, -shaftHeight / 2, 0), P.BrickDark, Enum.Material.Slate, arena)
		CollectionService:AddTag(wall, "Chomp_Wall")
	end
	for _, z in { -(hatch + WALL_T / 2), hatch + WALL_T / 2 } do
		local wall = part("ShaftWall", Vector3.new(hatch * 2, shaftHeight, WALL_T),
			CFrame.new(0, -shaftHeight / 2, z), P.BrickDark, Enum.Material.Slate, arena)
		CollectionService:AddTag(wall, "Chomp_Wall")
	end
	part("GuardianFloor", Vector3.new(chamberHalf * 2, SLAB, chamberHalf * 2),
		CFrame.new(0, chamberY, 0), P.CavernFloor, Enum.Material.Concrete, arena)
	for _, x in { -chamberHalf, chamberHalf } do
		local wall = part("GuardianWall", Vector3.new(WALL_T * 2, 48, chamberHalf * 2),
			CFrame.new(x, chamberY + 24, 0), P.CavernWall, Enum.Material.Rock, arena)
		CollectionService:AddTag(wall, "Chomp_Wall")
	end
	for _, z in { -chamberHalf, chamberHalf } do
		local wall = part("GuardianWall", Vector3.new(chamberHalf * 2, 48, WALL_T * 2),
			CFrame.new(0, chamberY + 24, z), P.CavernWall, Enum.Material.Rock, arena)
		CollectionService:AddTag(wall, "Chomp_Wall")
	end
	for row, radius in Config.Guardian.CoverRadii do
		local count = if row == 1 then 10 else 16
		for i = 0, count - 1 do
			local angle = TAU * (i / count) + row * 0.18
			local block = part("ColosseumBlock", Vector3.new(18, 20, 12),
				CFrame.new(onCircle(radius, angle, chamberY + 10)) * CFrame.Angles(0, -angle, 0),
				row == 1 and P.CavernCoverA or P.CavernCoverB, Enum.Material.Concrete, arena)
			CollectionService:AddTag(block, "Chomp_Wall")
			local cap = part("ColosseumCap", Vector3.new(18.2, 1.2, 12.2),
				block.CFrame * CFrame.new(0, 10.4, 0), P.CavernEdge,
				Enum.Material.SmoothPlastic, arena)
			cap.CanCollide = false
			cap.CanQuery = false
		end
	end

	-- Broad pools of light keep the cavern readable without flattening it into
	-- daylight. The far pair silhouette the guardian during the open fall.
	for i, angle in { 0, math.pi / 2, math.pi, math.pi * 1.5 } do
		local position = onCircle(chamberHalf - 28, angle, chamberY + 18)
		local tower = part("CavernLight", Vector3.new(7, 36, 7), CFrame.new(position),
			P.CavernLight, Enum.Material.Neon, arena)
		tower.CanCollide = false
		local light = Instance.new("PointLight")
		light.Color = tower.Color
		light.Brightness = 3.5
		light.Range = 165
		light.Shadows = true
		light.Parent = tower
	end
	for _, x in { -1, 1 } do
		local guide = part("LandingGuide", Vector3.new(3, 0.5, 110),
			CFrame.new(x * 18, chamberY + SLAB / 2 + 0.3, -48),
			P.NeonA, Enum.Material.Neon, arena)
		guide.CanCollide = false
	end

	-- A deliberate way home. The long fall commits the player to the guardian
	-- encounter, but it must not trap them there forever.
	local exitPosition = Vector3.new(0, chamberY + SLAB / 2 + 0.6, chamberHalf - 30)
	local exitZone = part("GuardianExitZone", Vector3.new(24, 1, 24),
		CFrame.new(exitPosition), P.Shield, Enum.Material.Neon, arena)
	exitZone.CanCollide = false
	CollectionService:AddTag(exitZone, "Chomp_GuardianExit")
	local exitLight = Instance.new("PointLight")
	exitLight.Color = P.Shield
	exitLight.Brightness = 8
	exitLight.Range = 75
	exitLight.Parent = exitZone
	local exitLabel = Instance.new("BillboardGui")
	exitLabel.Name = "ExitLabel"
	exitLabel.Size = UDim2.fromOffset(180, 54)
	exitLabel.StudsOffset = Vector3.new(0, 7, 0)
	exitLabel.AlwaysOnTop = true
	exitLabel.Parent = exitZone
	local exitText = Instance.new("TextLabel")
	exitText.Size = UDim2.fromScale(1, 1)
	exitText.BackgroundTransparency = 1
	exitText.Text = "EXIT TO ARENA"
	exitText.TextColor3 = P.Ghost
	exitText.TextStrokeTransparency = 0
	exitText.TextScaled = true
	exitText.Font = Enum.Font.GothamBlack
	exitText.Parent = exitLabel

	-- ── Boundary: brick, taller than the rings, and unbroken ─────────────
	-- Nothing is outside this. The guardian chamber is carved INTO the band
	-- rather than hung off the edge, because anything outside the boundary is a
	-- way to leave the map (D-CHOMP-046).
	local outer = arc(map, "BoundaryWall", L.OuterRadius, 0, TAU,
		SLAB / 2 + WALL_H * 0.9, WALL_H * 1.8, WALL_T * 1.5, P.Boundary, Enum.Material.Cobblestone)

	-- ── Rings ────────────────────────────────────────────────────────────
	local radii = {}
	local r = L.CentreRadius
	while r <= L.OuterRadius - L.RingSpacing do
		table.insert(radii, r)
		r += L.RingSpacing
	end

	local guardianAngle = math.rad(L.GuardianAngleDegrees)
	local guardianHalf = math.atan((L.GuardianChamberStuds / 2) / (L.OuterRadius - L.RingSpacing))

	local segments, spokes = 0, 0

	for index, radius in ipairs(radii) do
		-- Cycle the surfaces so a map with more rings than styles still varies
		-- rather than running out and going plain.
		local style = styleAt(index)
		local colour = P[style.colour] or P.Brick
		local material = style.material
		local neon = material == Enum.Material.Neon
		local gapHalf = math.atan((M.CellSize * 1.6) / radius)
		-- offset gaps ring to ring so no radial line is a free run to the middle
		local offset = (TAU / L.GapsPerRing) * (index / #radii)

		for g = 0, L.GapsPerRing - 1 do
			local from = offset + TAU * (g / L.GapsPerRing) + gapHalf
			local to = offset + TAU * ((g + 1) / L.GapsPerRing) - gapHalf
			-- leave the guardian chamber's mouth open on the outermost ring
			local skip = index == #radii
				and math.abs((((from + to) / 2) - guardianAngle + math.pi) % TAU - math.pi) < guardianHalf
			if not skip then
					-- Masonry is built slightly thicker than neon. A brick wall
				-- that reads as heavy and a light strip that reads as thin is
				-- the whole difference between the two kinds of place.
				segments += arc(rings, "RingWall", radius, from, to, WALL_Y,
					WALL_H, neon and WALL_T or WALL_T * 1.25, colour, material)
			end
		end

		-- Short spokes between this ring and the next, so a ring cannot be held
		-- flat out all the way round.
		if index < #radii then
			local nextRadius = radii[index + 1]
			for k = 0, L.SpokesPerRing - 1 do
				local a = TAU * (k / L.SpokesPerRing) + (index * 0.21)
				local mid = (radius + nextRadius) / 2
				local sp = neon and L.SpokeMasonry or L.SpokeNeon
				local p = part("SpokeWall", Vector3.new(WALL_T, WALL_H, nextRadius - radius),
					radialAt(mid, a, WALL_Y), P[sp.colour] or P.Stone,
					sp.material, rings)
				CollectionService:AddTag(p, "Chomp_Wall")
				if sp.material ~= Enum.Material.Neon then
					local cap = part("WallCap", Vector3.new(WALL_T + 0.35, 0.38, nextRadius - radius),
						radialAt(mid, a, WALL_Y + WALL_H / 2 + 0.19), P.NeonB,
						Enum.Material.Neon, rings)
					cap.CanCollide = false
					cap.CanQuery = false
					cap.CastShadow = false
					CollectionService:AddTag(cap, "Chomp_Wall")
				end
				spokes += 1
			end
		end
	end

	-- ── Guardian chamber, carved into the outer band ─────────────────────
	local chamberR = L.OuterRadius - L.RingSpacing / 2
	local half = L.GuardianChamberStuds / 2
	for _, side in { -1, 1 } do
		local p = part("ChamberWall", Vector3.new(WALL_T, WALL_H, L.RingSpacing),
			radialAt(chamberR, guardianAngle, WALL_Y) * CFrame.new(side * half, 0, 0),
			P.Danger, Enum.Material.Neon, map)
		CollectionService:AddTag(p, "Chomp_Wall")
	end
	local boundary = part("CommitmentBoundary",
		Vector3.new(L.GuardianChamberStuds, WALL_H, 1),
		radialAt(chamberR, guardianAngle, WALL_Y) * CFrame.new(0, 0, -L.RingSpacing / 2),
		P.Danger, Enum.Material.Neon, map)
	boundary.Transparency = 0.6
	boundary.CanCollide = false
	CollectionService:AddTag(boundary, "Chomp_Boundary")

	-- ── Garages ──────────────────────────────────────────────────────────
	local garages: { Vector3 } = {}
	for i = 0, L.GarageCount - 1 do
		local a = TAU * (i / L.GarageCount) + math.pi / L.GarageCount
		local pos = onCircle(L.OuterRadius - L.RingSpacing / 2, a, SLAB / 2 + 0.2)
		local pad = part("GarageFloor", Vector3.new(M.CellSize * 2, 0.4, M.CellSize * 2),
			tangentAt(L.OuterRadius - L.RingSpacing / 2, a, pos.Y), P.Gold,
			Enum.Material.Neon, bays)
		pad.Transparency = 0.45
		pad.CanCollide = false
		-- The first pad is HOME: it holds the spawn and the shop row, and it is
		-- the one that gets the large sanctuary (D-CHOMP-065). Marked here
		-- rather than recomputed, because two services need to agree on which
		-- pad it is and an angle comparison would be two chances to disagree.
		pad:SetAttribute("Home", i == 0)
		CollectionService:AddTag(pad, "Chomp_Garage")
		table.insert(garages, pos)
	end

	local home = garages[1]
	-- Leaving the garage is the ENTER ARENA action. The threshold is visible in
	-- the world so deployment is spatial, not another menu button.
	local homeFlat = Vector3.new(home.X, 0, home.Z)
	local inward = -homeFlat.Unit
	local gateCentre = home + inward * L.HomeSafeRadiusStuds
	local gate = Instance.new("Model")
	gate.Name = "DeploymentGate"
	gate.Parent = bays
	local gateCF = CFrame.lookAt(gateCentre, gateCentre + inward)
	for _, side in { -1, 1 } do
		local post = part("DeployPost", Vector3.new(2, Config.Launch.GateHeightStuds, 2),
			gateCF * CFrame.new(side * Config.Launch.GateWidthStuds / 2,
				Config.Launch.GateHeightStuds / 2, 0), P.NeonA, Enum.Material.Neon, gate)
		post.CanCollide = false
	end
	local header = part("DeployHeader", Vector3.new(Config.Launch.GateWidthStuds + 2, 2, 2),
		gateCF * CFrame.new(0, Config.Launch.GateHeightStuds, 0),
		P.Gold, Enum.Material.Neon, gate)
	header.CanCollide = false

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Level1Spawn"
	spawn.Size = Vector3.new(M.CellSize, 1, M.CellSize)
	spawn.CFrame = CFrame.new(home + Vector3.new(0, 0.6, 0))
	spawn.Anchored = true
	spawn.CanCollide = false
	spawn.Transparency = 1
	spawn.Parent = map

	local exitDebounce: { [Player]: number } = {}
	exitZone.Touched:Connect(function(hit)
		local ancestor: Instance? = hit
		local player: Player? = nil
		while ancestor and ancestor ~= Workspace do
			if ancestor:IsA("Model") then
				player = Players:GetPlayerFromCharacter(ancestor)
				if player then break end
			end
			ancestor = ancestor.Parent
		end
		if not (player and player.Character) then return end
		if os.clock() - (exitDebounce[player] or 0) < 2 then return end
		exitDebounce[player] = os.clock()
		player.Character:PivotTo(spawn.CFrame + Vector3.new(0, 4, 0))
		local root = player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
		end
		player.Character:SetAttribute("ChompGuardianExitedAt", os.clock())
	end)

	-- Sibling server scripts start in no guaranteed order. GhostService uses
	-- this only after the final wall and garage tag exists, so its collision
	-- filter can never capture a half-built (or empty) maze.
	map:SetAttribute("ChompMapReady", true)
	Workspace:SetAttribute("ChompLevel1MapReady", true)

	local surfaces = {}
	for index = 1, #radii do table.insert(surfaces, styleAt(index).material.Name) end
	print(("[Level1Map] ring surfaces outward: %s"):format(table.concat(surfaces, ", ")))
	print(("[Level1Map] one level, sealed: r%d disc, %d rings, %d ring segments, " ..
		"%d spokes, boundary %d segments, %d garages. cell %d wall %d")
		:format(L.OuterRadius, #radii, segments, spokes, outer, #garages,
			M.CellSize, WALL_H))
end

build()
