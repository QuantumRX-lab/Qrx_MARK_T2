--!strict
--[[
	ArenaMap — CHAIN-MAZE

	A full two-deck arena to drive: a 32 x 32 cell ground maze, a raised
	16 x 16 ring 2, four ramps, four bridges you can drive off, and twelve
	garages. Everything derives from ChompConfig.Map, so a camera retune that
	moves WallHeight or DeckHeight regenerates the map rather than invalidating
	a weekend of building.

	THIS IS NOT THE v1 MAP. map_geometry.md's v1 map is hand-built by the child
	from the six prefabs, and that work is gated on CHOMP-TC-040 passing
	(RISK-CHOMP-012). This is generated geometry that exists so there is
	something real to drive first, and so it costs nothing to throw away.

	What it does honour from map_geometry.md, because those rules are what make
	the real map work:

	  * everything on the 8-stud grid
	  * walls on cell boundaries; one cell is one corridor width
	  * build one 16 x 16 quadrant, rotate it four times (D-CHOMP-030)
	  * wall height, deck height, ramp run and slab all from ChompConfig

	The maze is a braided spanning tree. A perfect maze has exactly one route
	between any two points, which is miserable to drive and worse to be chased
	through, so a fraction of the walls are opened into loops.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("ChompConfig"))
local M = Config.Map

if M.Layout ~= "Arena" then
	return   -- TestMap builds instead; see ChompConfig.Map.Layout
end

local CELL = M.CellSize
local WALL_H = M.WallHeight
local WALL_T = M.WallThickness
local DECK_H = M.DeckHeight
local SLAB = M.SlabThickness

local QUAD = M.QuadrantCells         -- 16, the authored quadrant
local FULL = M.GroundDeckCells       -- 32, after mirroring
local R2_HALF = M.Ring2InnerCells    -- 8, so ring 2 is 16 cells across
local R2_SIZE = R2_HALF * 2
local R2_LO = FULL // 2 - R2_HALF
local R2_HI = R2_LO + R2_SIZE - 1

local rng = Random.new(M.ArenaSeed)

local COLOUR_FLOOR = Color3.fromRGB(38, 42, 58)
local COLOUR_FLOOR2 = Color3.fromRGB(48, 44, 72)
local COLOUR_WALL = Color3.fromRGB(64, 92, 176)
local COLOUR_WALL2 = Color3.fromRGB(108, 84, 184)
local COLOUR_RAMP = Color3.fromRGB(84, 120, 200)
local COLOUR_BRIDGE = Color3.fromRGB(96, 104, 140)
local COLOUR_GARAGE = Color3.fromRGB(255, 176, 32)

type Cell = { x: number, z: number }
type EdgeSet = { [string]: boolean }

local function cells(n: number): number
	return n * CELL
end

local function part(name: string, size: Vector3, cf: CFrame, colour: Color3, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Anchored = true
	p.Material = Enum.Material.SmoothPlastic
	p.Color = colour
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- ── Connectivity ────────────────────────────────────────────────────────
-- Every cell is open floor. A wall is an edge NOT in the open set, which is
-- the model map_geometry.md describes: corridors are cells, walls sit on the
-- boundaries between them. Boundary planes use the same keys, so punching a
-- hole in a perimeter is just adding an edge.

local function planeX(x: number, z: number): string
	return ("V:%d:%d"):format(x, z)   -- wall plane at cell boundary x, spanning cell z
end

local function planeZ(x: number, z: number): string
	return ("H:%d:%d"):format(x, z)   -- wall plane at cell boundary z, spanning cell x
end

local function edgeKey(a: Cell, b: Cell): string
	if a.z == b.z then
		return planeX(math.max(a.x, b.x), a.z)
	end
	return planeZ(a.x, math.max(a.z, b.z))
end

local DIRS: { Cell } = {
	{ x = 1, z = 0 }, { x = -1, z = 0 }, { x = 0, z = 1 }, { x = 0, z = -1 },
}

local function id(c: Cell): string
	return ("%d,%d"):format(c.x, c.z)
end

-- Recursive backtracker, then braided so the maze has loops.
local function generateQuadrant(n: number, braid: number): EdgeSet
	local open: EdgeSet = {}
	local seen: { [string]: boolean } = {}
	local stack: { Cell } = { { x = 0, z = 0 } }
	seen[id(stack[1])] = true

	while #stack > 0 do
		local here = stack[#stack]
		local options: { Cell } = {}
		for _, d in DIRS do
			local n2 = { x = here.x + d.x, z = here.z + d.z }
			if n2.x >= 0 and n2.x < n and n2.z >= 0 and n2.z < n and not seen[id(n2)] then
				table.insert(options, n2)
			end
		end
		if #options == 0 then
			table.remove(stack)
		else
			local pick = options[rng:NextInteger(1, #options)]
			open[edgeKey(here, pick)] = true
			seen[id(pick)] = true
			table.insert(stack, pick)
		end
	end

	for x = 0, n - 1 do
		for z = 0, n - 1 do
			for _, d in DIRS do
				local n2 = { x = x + d.x, z = z + d.z }
				if n2.x >= 0 and n2.x < n and n2.z >= 0 and n2.z < n then
					local k = edgeKey({ x = x, z = z }, n2)
					if not open[k] and rng:NextNumber() < braid then
						open[k] = true
					end
				end
			end
		end
	end
	return open
end

-- The four rotations of a cell about the grid centre (D-CHOMP-030).
local function rotations(c: Cell, size: number): { Cell }
	local hi = size - 1
	return {
		{ x = c.x, z = c.z },
		{ x = hi - c.z, z = c.x },
		{ x = hi - c.x, z = hi - c.z },
		{ x = c.z, z = hi - c.x },
	}
end

local function mirror(quad: EdgeSet, n: number, size: number, offset: number): EdgeSet
	local open: EdgeSet = {}
	for x = 0, n - 1 do
		for z = 0, n - 1 do
			for _, d in DIRS do
				local b = { x = x + d.x, z = z + d.z }
				if b.x >= 0 and b.x < n and b.z >= 0 and b.z < n
					and quad[edgeKey({ x = x, z = z }, b)] then
					local ra = rotations({ x = x, z = z }, size)
					local rb = rotations(b, size)
					for i = 1, 4 do
						open[edgeKey(
							{ x = ra[i].x + offset, z = ra[i].z + offset },
							{ x = rb[i].x + offset, z = rb[i].z + offset })] = true
					end
				end
			end
		end
	end
	return open
end

-- Without this the four mirrored quadrants are sealed quarters. Symmetric
-- openings keep spawns fair.
local function openSeams(open: EdgeSet, size: number, offset: number, every: number)
	local mid = size // 2
	for i = 1, size - 2, every do
		open[edgeKey({ x = mid - 1 + offset, z = i + offset },
			{ x = mid + offset, z = i + offset })] = true
		open[edgeKey({ x = i + offset, z = mid - 1 + offset },
			{ x = i + offset, z = mid + offset })] = true
	end
end

-- ── Rendering ───────────────────────────────────────────────────────────
-- One pass over every cell, drawing all four boundary planes and de-duping.
-- Perimeter falls out of this for free, which is what lets a ramp or a bridge
-- punch through it simply by opening that edge.

local function renderWalls(parent: Instance, open: EdgeSet,
		lo: number, hi: number, deck: number, colour: Color3): number
	local y = deck * DECK_H + SLAB / 2 + WALL_H / 2
	local drawn: { [string]: boolean } = {}
	local count = 0

	for x = lo, hi do
		for z = lo, hi do
			for _, k in { planeX(x, z), planeX(x + 1, z) } do
				if not open[k] and not drawn[k] then
					drawn[k] = true
					local bx = tonumber(k:match("^V:(%d+):")) :: number
					part("Wall", Vector3.new(WALL_T, WALL_H, cells(1)),
						CFrame.new(cells(bx), y, cells(z) + CELL / 2), colour, parent)
					count += 1
				end
			end
			for _, k in { planeZ(x, z), planeZ(x, z + 1) } do
				if not open[k] and not drawn[k] then
					drawn[k] = true
					local bz = tonumber(k:match(":(%d+)$")) :: number
					part("Wall", Vector3.new(cells(1), WALL_H, WALL_T),
						CFrame.new(cells(x) + CELL / 2, y, cells(bz)), colour, parent)
					count += 1
				end
			end
		end
	end
	return count
end

local function flood(open: EdgeSet, from: Cell, lo: number, hi: number): { [string]: boolean }
	local seen: { [string]: boolean } = {}
	local stack: { Cell } = { from }
	seen[id(from)] = true
	while #stack > 0 do
		local c = table.remove(stack) :: Cell
		for _, d in DIRS do
			local n = { x = c.x + d.x, z = c.z + d.z }
			if n.x >= lo and n.x <= hi and n.z >= lo and n.z <= hi
				and not seen[id(n)] and open[edgeKey(c, n)] then
				seen[id(n)] = true
				table.insert(stack, n)
			end
		end
	end
	return seen
end

-- ── Build ───────────────────────────────────────────────────────────────

local function build()
	local maps = Workspace:FindFirstChild("Maps") or Instance.new("Folder")
	maps.Name = "Maps"
	maps.Parent = Workspace

	local existing = maps:FindFirstChild("Arena")
	if existing then existing:Destroy() end

	local map = Instance.new("Folder"); map.Name = "Arena"; map.Parent = maps
	local deck1 = Instance.new("Folder"); deck1.Name = "Deck1"; deck1.Parent = map
	local deck2 = Instance.new("Folder"); deck2.Name = "Deck2"; deck2.Parent = map
	local links = Instance.new("Folder"); links.Name = "Links"; links.Parent = map
	local bays = Instance.new("Folder"); bays.Name = "Garages"; bays.Parent = map

	local ground = mirror(generateQuadrant(QUAD, M.ArenaBraidChance), QUAD, FULL, 0)
	openSeams(ground, FULL, 0, 3)

	local ring2 = mirror(generateQuadrant(R2_HALF, M.ArenaBraidChance), R2_HALF, R2_SIZE, R2_LO)
	openSeams(ring2, R2_SIZE, R2_LO, 3)

	-- Garages: three per quadrant, 3 x 3 cells, hollowed out and opened to the
	-- maze on one side. Mirrored, that is the twelve of CHOMP-SYS-007.
	local G = M.GarageCells
	local garages: { Cell } = {}
	for _, corner in { { x = 1, z = 1 }, { x = 12, z = 1 }, { x = 1, z = 12 } } do
		for _, o in rotations(corner, FULL) do
			local x0 = math.clamp(o.x, 0, FULL - G)
			local z0 = math.clamp(o.z, 0, FULL - G)
			for x = x0, x0 + G - 1 do
				for z = z0, z0 + G - 1 do
					if x < x0 + G - 1 then
						ground[edgeKey({ x = x, z = z }, { x = x + 1, z = z })] = true
					end
					if z < z0 + G - 1 then
						ground[edgeKey({ x = x, z = z }, { x = x, z = z + 1 })] = true
					end
				end
			end
			-- one entrance, so a garage is a place rather than a sealed pocket
			local ex = math.min(x0 + G, FULL - 1)
			ground[edgeKey({ x = ex - 1, z = z0 + 1 }, { x = ex, z = z0 + 1 })] = true
			table.insert(garages, { x = x0, z = z0 })

			local floor = part("GarageFloor", Vector3.new(cells(G), 0.4, cells(G)),
				CFrame.new(cells(x0) + cells(G) / 2, SLAB / 2 + 0.2, cells(z0) + cells(G) / 2),
				COLOUR_GARAGE, bays)
			floor.Transparency = 0.55
			floor.CanCollide = false
			CollectionService:AddTag(floor, "Chomp_Garage")
		end
	end

	-- Ramps and bridges are defined once in quadrant terms as a PAIR of cells,
	-- then both ends rotated. That way the direction each one runs falls out of
	-- the rotation instead of being four hand-written special cases.
	local rampRun = cells(M.RampCells)
	local rampLength = math.sqrt(rampRun ^ 2 + DECK_H ^ 2)
	local rampAngle = math.atan2(DECK_H, rampRun)
	local rampBase = { x = R2_LO - M.RampCells, z = FULL // 2 + 4 }
	local rampLand = { x = R2_LO, z = FULL // 2 + 4 }
	local rampBases: { Cell } = {}

	local baseR = rotations(rampBase, FULL)
	local landR = rotations(rampLand, FULL)
	for i = 1, 4 do
		local a, b = baseR[i], landR[i]
		local dx = math.sign(b.x - a.x)
		local dz = math.sign(b.z - a.z)

		-- clear the ground approach, and punch the ring 2 perimeter at the top
		for step = 0, M.RampCells - 1 do
			local c1 = { x = a.x + dx * step, z = a.z + dz * step }
			local c2 = { x = a.x + dx * (step + 1), z = a.z + dz * (step + 1) }
			ground[edgeKey(c1, c2)] = true
		end
		ring2[edgeKey(b, { x = b.x - dx, z = b.z - dz })] = true

		-- Centre along the run, but centre WITHIN the cell across it. Using the
		-- same expression for both axes offsets the ramp by half a cell.
		local horizontal = dx ~= 0
		local mid = horizontal
			and Vector3.new((cells(a.x) + cells(b.x)) / 2, DECK_H / 2, cells(a.z) + CELL / 2)
			or Vector3.new(cells(a.x) + CELL / 2, DECK_H / 2, (cells(a.z) + cells(b.z)) / 2)
		local size = horizontal
			and Vector3.new(rampLength, SLAB, cells(1))
			or Vector3.new(cells(1), SLAB, rampLength)
		-- Rotating about Z by +angle lifts the +X end; rotating about X by
		-- +angle drops the +Z end, hence the asymmetry in these two signs.
		local tilt = horizontal
			and CFrame.Angles(0, 0, dx * rampAngle)
			or CFrame.Angles(-dz * rampAngle, 0, 0)
		local ramp = part("Ramp", size, CFrame.new(mid) * tilt, COLOUR_RAMP, links)
		CollectionService:AddTag(ramp, "Chomp_Link")
		table.insert(rampBases, a)
	end

	-- Bridges: attached to ring 2, cantilevered out over the ground corridors,
	-- ending in nothing. Driving off is the mechanic, not a mistake
	-- (CHOMP-SYS-049, CHOMP-TC-039).
	local bridgeIn = { x = R2_LO, z = FULL // 2 - 5 }
	local bridgeOut = { x = R2_LO - 5, z = FULL // 2 - 5 }
	local inR = rotations(bridgeIn, FULL)
	local outR = rotations(bridgeOut, FULL)
	for i = 1, 4 do
		local a, b = inR[i], outR[i]
		local dx = math.sign(b.x - a.x)
		local dz = math.sign(b.z - a.z)
		ring2[edgeKey(a, { x = a.x + dx, z = a.z + dz })] = true

		local span = math.max(math.abs(b.x - a.x), math.abs(b.z - a.z))
		local horizontal = dx ~= 0
		local mid = horizontal
			and Vector3.new((cells(a.x) + cells(b.x)) / 2, DECK_H, cells(a.z) + CELL / 2)
			or Vector3.new(cells(a.x) + CELL / 2, DECK_H, (cells(a.z) + cells(b.z)) / 2)
		local size = horizontal
			and Vector3.new(cells(span), SLAB, cells(M.BridgeWidthCells))
			or Vector3.new(cells(M.BridgeWidthCells), SLAB, cells(span))
		local bridge = part("Bridge", size, CFrame.new(mid), COLOUR_BRIDGE, links)
		CollectionService:AddTag(bridge, "Chomp_Link")
	end

	-- Floors, then walls — after every opening above has been applied.
	part("GroundSlab", Vector3.new(cells(FULL), SLAB, cells(FULL)),
		CFrame.new(cells(FULL) / 2, 0, cells(FULL) / 2), COLOUR_FLOOR, deck1)
	local groundWalls = renderWalls(deck1, ground, 0, FULL - 1, 0, COLOUR_WALL)

	part("Ring2Slab", Vector3.new(cells(R2_SIZE), SLAB, cells(R2_SIZE)),
		CFrame.new(cells(FULL) / 2, DECK_H, cells(FULL) / 2), COLOUR_FLOOR2, deck2)
	local ring2Walls = renderWalls(deck2, ring2, R2_LO, R2_HI, 1, COLOUR_WALL2)

	-- Spawn inside a garage: you start where you bank.
	local home = garages[1]
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "ArenaSpawn"
	spawn.Size = Vector3.new(cells(1), 1, cells(1))
	spawn.CFrame = CFrame.new(cells(home.x) + CELL / 2, SLAB + 0.5, cells(home.z) + CELL / 2)
	spawn.Anchored = true
	spawn.CanCollide = false
	spawn.Transparency = 0.7
	spawn.Parent = map

	-- Reachability is asserted, not assumed. A generated maze that seals a
	-- quadrant is a wasted playtest, and this costs a millisecond.
	local reached = flood(ground, home, 0, FULL - 1)
	local got = 0
	for _ in reached do got += 1 end
	if got < FULL * FULL then
		warn(("[ArenaMap] %d of %d ground cells unreachable from spawn - seed %d sealed a region")
			:format(FULL * FULL - got, FULL * FULL, M.ArenaSeed))
	end
	for _, base in rampBases do
		if not reached[id(base)] then
			warn(("[ArenaMap] ramp base %s is unreachable from spawn"):format(id(base)))
		end
	end

	print(("[ArenaMap] built: ground %dx%d (%d walls), ring 2 %dx%d (%d walls), " ..
		"4 ramps, 4 bridges, %d garages, %d/%d cells reachable. cell %d wall %d deck %d seed %d")
		:format(FULL, FULL, groundWalls, R2_SIZE, R2_SIZE, ring2Walls,
			#garages, got, FULL * FULL, CELL, WALL_H, DECK_H, M.ArenaSeed))
end

build()
