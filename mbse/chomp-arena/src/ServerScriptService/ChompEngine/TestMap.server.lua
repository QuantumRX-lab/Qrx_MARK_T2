--!strict
--[[
	TestMap — CHAIN-MAZE

	Builds the throwaway two-deck test map that CHOMP-TC-040 needs: snapped
	walls, a ramp, a bridge crossing a corridor, and a tower core to drive
	around. Everything comes from ChompConfig.Map, so if the grid or the wall
	height changes, this map changes with it.

	This is not the v1 map. It exists so the camera — the highest-risk item in
	the tree (RISK-CHOMP-012) — can be built and judged before anybody spends a
	weekend building real geometry against a camera that turns out not to work.

	Set ChompConfig.Map.BuildTestMap or just leave this script in place; it
	builds on server start into Workspace/Maps/TestMap.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("ChompConfig"))
local M = Config.Map

local CELL = M.CellSize
local WALL_H = M.WallHeight
local WALL_T = M.WallThickness
local DECK_H = M.DeckHeight
local SLAB = M.SlabThickness

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

local COLOUR_FLOOR = Color3.fromRGB(38, 42, 58)
local COLOUR_WALL = Color3.fromRGB(64, 92, 176)
local COLOUR_RAMP = Color3.fromRGB(84, 120, 200)
local COLOUR_BRIDGE = Color3.fromRGB(96, 104, 140)
local COLOUR_TOWER = Color3.fromRGB(52, 58, 80)

-- A wall runs along +X or +Z from a cell corner, `length` cells long.
local function wall(parent: Instance, x: number, z: number, length: number, axis: string, deck: number)
	local y = deck * DECK_H + SLAB / 2 + WALL_H / 2
	local size, centre
	if axis == "X" then
		size = Vector3.new(cells(length), WALL_H, WALL_T)
		centre = Vector3.new(cells(x) + cells(length) / 2, y, cells(z))
	else
		size = Vector3.new(WALL_T, WALL_H, cells(length))
		centre = Vector3.new(cells(x), y, cells(z) + cells(length) / 2)
	end
	local p = part("Wall", size, CFrame.new(centre), COLOUR_WALL, parent)
	CollectionService:AddTag(p, "Chomp_Wall")
	return p
end

local function slab(parent: Instance, x: number, z: number, w: number, d: number, deck: number, colour: Color3?)
	local y = deck * DECK_H
	local p = part("Floor",
		Vector3.new(cells(w), SLAB, cells(d)),
		CFrame.new(cells(x) + cells(w) / 2, y, cells(z) + cells(d) / 2),
		colour or COLOUR_FLOOR, parent)
	return p
end

if M.Layout ~= "Test" then
	return   -- ArenaMap builds instead; see ChompConfig.Map.Layout
end

local function build()
	local maps = Workspace:FindFirstChild("Maps") or Instance.new("Folder")
	maps.Name = "Maps"
	maps.Parent = Workspace

	local existing = maps:FindFirstChild("TestMap")
	if existing then existing:Destroy() end

	local map = Instance.new("Folder")
	map.Name = "TestMap"
	map.Parent = maps

	local deck1 = Instance.new("Folder"); deck1.Name = "Deck1"; deck1.Parent = map
	local deck2 = Instance.new("Folder"); deck2.Name = "Deck2"; deck2.Parent = map
	local links = Instance.new("Folder"); links.Name = "Links"; links.Parent = map

	-- ── Deck 1: a 24 x 24 cell ground plate ──────────────────────────────
	slab(deck1, 0, 0, 24, 24, 0)

	-- Perimeter walls
	wall(deck1, 0, 0, 24, "X", 0)
	wall(deck1, 0, 24, 24, "X", 0)
	wall(deck1, 0, 0, 24, "Z", 0)
	wall(deck1, 24, 0, 24, "Z", 0)

	-- A corridor to drive down, and something to hide behind. The bridge
	-- above crosses this corridor, which is the occlusion case that matters.
	wall(deck1, 6, 8, 12, "X", 0)
	wall(deck1, 6, 16, 12, "X", 0)

	-- Tower core: the camera has to fade this when you drive behind it.
	local towerY = SLAB / 2 + (DECK_H * 1.5) / 2
	local tower = part("TowerCore",
		Vector3.new(cells(4), DECK_H * 1.5, cells(4)),
		CFrame.new(cells(10) + cells(2), towerY, cells(10) + cells(2)),
		COLOUR_TOWER, deck1)
	CollectionService:AddTag(tower, "Chomp_Wall")

	-- ── Ramp: 4 cells of run for a 16 stud rise (about 26.6 degrees) ─────
	local rampRun = cells(M.RampCells)
	local rampRise = DECK_H
	local rampLength = math.sqrt(rampRun ^ 2 + rampRise ^ 2)
	local rampAngle = math.atan2(rampRise, rampRun)
	local rampCentre = Vector3.new(
		cells(20) + cells(2),
		rampRise / 2,
		cells(4) + rampRun / 2 - rampRun / 2 + cells(2)
	)
	local ramp = part("Ramp",
		Vector3.new(cells(2), SLAB, rampLength),
		CFrame.new(rampCentre) * CFrame.Angles(-rampAngle, 0, 0),
		COLOUR_RAMP, links)
	CollectionService:AddTag(ramp, "Chomp_Link")

	-- ── Deck 2: a raised 8 x 8 cell platform, reached by the ramp ─────────
	slab(deck2, 16, 0, 8, 8, 1)
	wall(deck2, 16, 0, 8, "X", 1)
	wall(deck2, 24, 0, 8, "Z", 1)

	-- ── Bridge: crosses the deck-1 corridor at deck-2 height ─────────────
	-- No railings. Falling off is a mechanic (CHOMP-SYS-049), and this is
	-- where CHOMP-TC-039 gets tested.
	local bridge = part("Bridge",
		Vector3.new(cells(M.BridgeWidthCells), SLAB, cells(12)),
		CFrame.new(cells(18), DECK_H, cells(8) + cells(6)),
		COLOUR_BRIDGE, links)
	CollectionService:AddTag(bridge, "Chomp_Link")

	-- ── Spawn ────────────────────────────────────────────────────────────
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "TestSpawn"
	spawn.Size = Vector3.new(cells(1), 1, cells(1))
	spawn.CFrame = CFrame.new(cells(3), SLAB + 0.5, cells(3))
	spawn.Anchored = true
	spawn.CanCollide = false
	spawn.Transparency = 0.6
	spawn.Parent = map

	print(("[TestMap] built: 24x24 ground deck, %d-cell ramp, bridge, tower core. " ..
		"Cell %d, wall %d, deck height %d."):format(M.RampCells, CELL, WALL_H, DECK_H))
end

build()
