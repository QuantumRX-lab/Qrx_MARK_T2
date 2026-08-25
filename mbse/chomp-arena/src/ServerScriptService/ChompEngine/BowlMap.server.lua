--!strict
--[[
	BowlMap — CHAIN-MAZE, Level 1 (D-CHOMP-041)

	Safety and reward as geography. A rim you can learn on, three concentric
	rings of easy maze to bank in, four broad slopes down into an open central
	bowl where the points and the fights are, and a guardian chamber off the rim
	on the route to Level 2.

	Everything is curved. That is not decoration: continuous steering
	(D-CHOMP-042) leans into a bend, and the rectilinear arena it replaces
	punished that by putting a flat wall and a square corner at the end of every
	corridor. A ring you can hold a line around is the shape this driving model
	was asking for.

	Built from ChompConfig.Level1, so a camera retune or a speed change
	regenerates it rather than invalidating it.

	Arcs are chords. A ring at radius r is drawn as segments of about
	SegmentStuds each, tangent to the circle — smaller segments are rounder and
	cost more parts, and that trade is the one knob worth having.

	EVERY wall is tagged Chomp_Wall. The camera fades only tagged parts and
	treats anything else as a hard occluder, which is what made an untagged
	arena look like a broken camera (D-CHOMP-043).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("ChompConfig"))
local M = Config.Map
local L = Config.Level1

if M.Layout ~= "Level1" then
	return   -- ArenaMap or TestMap builds instead; see ChompConfig.Map.Layout
end

local WALL_H = M.WallHeight
local WALL_T = M.WallThickness
local SLAB = M.SlabThickness
local TAU = math.pi * 2

local COLOUR_BOWL = Color3.fromRGB(31, 34, 48)
local COLOUR_RIM = Color3.fromRGB(44, 48, 66)
local COLOUR_WALL = Color3.fromRGB(64, 92, 176)
local COLOUR_OUTER = Color3.fromRGB(52, 62, 120)
local COLOUR_RAMP = Color3.fromRGB(84, 120, 200)
local COLOUR_GARAGE = Color3.fromRGB(255, 176, 32)
local COLOUR_CHAMBER = Color3.fromRGB(255, 61, 61)

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

local function onCircle(radius: number, angle: number, y: number): Vector3
	return Vector3.new(math.cos(angle) * radius, y, math.sin(angle) * radius)
end

-- A CFrame whose local Z runs TANGENT to the circle at `angle`.
-- CFrame.Angles(0, t, 0) puts local Z along (sin t, 0, cos t); the tangent is
-- (-sin a, 0, cos a), so t = -a.
local function tangentAt(radius: number, angle: number, y: number): CFrame
	return CFrame.new(onCircle(radius, angle, y)) * CFrame.Angles(0, -angle, 0)
end

-- A CFrame whose local Z runs OUTWARD along the radius at `angle`.
-- Local Z must be (cos a, 0, sin a), so t = pi/2 - a.
local function radialAt(radius: number, angle: number, y: number): CFrame
	return CFrame.new(onCircle(radius, angle, y)) * CFrame.Angles(0, math.pi / 2 - angle, 0)
end

-- ── Arcs ────────────────────────────────────────────────────────────────

local function arc(parent: Instance, name: string, radius: number, from: number, to: number,
		y: number, height: number, thickness: number, colour: Color3, tag: string?): number
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
			tangentAt(radius, mid, y), colour, parent)
		if tag then CollectionService:AddTag(p, tag) end
	end
	return segments
end

-- The rim floor is an annulus, drawn the same way: segments spanning the band.
local function annulus(parent: Instance, name: string, inner: number, outer: number,
		from: number, to: number, y: number, colour: Color3): number
	local mid = (inner + outer) / 2
	local band = outer - inner
	local span = to - from
	local segments = math.max(1, math.ceil(mid * span / L.SegmentStuds))
	for i = 0, segments - 1 do
		local a0 = from + span * (i / segments)
		local a1 = from + span * ((i + 1) / segments)
		local a = (a0 + a1) / 2
		local chord = 2 * mid * math.sin((a1 - a0) / 2)
		part(name, Vector3.new(band, SLAB, chord + 0.6), tangentAt(mid, a, y), colour, parent)
	end
	return segments
end

-- ── Build ───────────────────────────────────────────────────────────────

local function build()
	local maps = Workspace:FindFirstChild("Maps") or Instance.new("Folder")
	maps.Name = "Maps"
	maps.Parent = Workspace

	local existing = maps:FindFirstChild("Level1")
	if existing then existing:Destroy() end

	local map = Instance.new("Folder"); map.Name = "Level1"; map.Parent = maps
	local bowl = Instance.new("Folder"); bowl.Name = "Bowl"; bowl.Parent = map
	local rim = Instance.new("Folder"); rim.Name = "Rim"; rim.Parent = map
	local links = Instance.new("Folder"); links.Name = "Links"; links.Parent = map
	local bays = Instance.new("Folder"); bays.Name = "Garages"; bays.Parent = map

	-- The bowl floor is one cylinder covering everything; the rim is a raised
	-- annulus laid on top of it. That way the bowl is simply the part of the
	-- floor the rim does not cover, and no primitive needs a hole in it.
	local floor = part("BowlFloor", Vector3.new(SLAB, L.RimOuter * 2, L.RimOuter * 2),
		CFrame.new(0, 0, 0) * CFrame.Angles(0, 0, math.rad(90)), COLOUR_BOWL, bowl)
	floor.Shape = Enum.PartType.Cylinder

	-- Ramp mouths: the annulus and the inner lip are omitted across these spans
	-- so a slope has somewhere to land.
	local rampHalf = math.atan((L.RampWidthStuds / 2) / L.RimInner)
	local rampAngles = {}
	for i = 0, L.RampCount - 1 do
		table.insert(rampAngles, TAU * (i / L.RampCount) + math.pi / L.RampCount)
	end

	local function inRampMouth(a: number): boolean
		for _, r in rampAngles do
			local d = math.abs((a - r + math.pi) % TAU - math.pi)
			if d < rampHalf * 1.6 then return true end
		end
		return false
	end

	-- Rim floor and the inner lip, in spans between the ramp mouths.
	local rimSegments, lipSegments = 0, 0
	local steps = 240
	local runStart: number? = nil
	for i = 0, steps do
		local a = TAU * (i / steps)
		local blocked = inRampMouth(a) or i == steps
		if not blocked and runStart == nil then
			runStart = a
		elseif blocked and runStart ~= nil then
			rimSegments += annulus(rim, "RimFloor", L.RimInner, L.RimOuter,
				runStart, a, L.RimHeight, COLOUR_RIM)
			-- the inner lip is what stops you driving off the rim by accident;
			-- it is also the wall the camera has to fade when you hug it
			lipSegments += arc(rim, "RimLip", L.RimInner, runStart, a,
				L.RimHeight + SLAB / 2 + WALL_H / 2, WALL_H, WALL_T, COLOUR_WALL, "Chomp_Wall")
			runStart = nil
		end
	end

	-- Outer boundary: no gaps, this is the edge of the world.
	local outerSegments = arc(rim, "OuterWall", L.RimOuter,
		0, TAU, L.RimHeight + SLAB / 2 + WALL_H / 2, WALL_H, WALL_T, COLOUR_OUTER, "Chomp_Wall")

	-- ── The rim maze ─────────────────────────────────────────────────────
	-- Concentric rings with gaps, offset ring to ring so no single radial line
	-- is a free run from the outer wall to the bowl. Radial spokes stop each
	-- ring becoming a racetrack you can hold flat out.
	local ringSegments, radialSegments = 0, 0
	local y = L.RimHeight + SLAB / 2 + WALL_H / 2
	for ringIndex, radius in ipairs(L.RingRadii) do
		local gapHalf = math.atan((M.CellSize * 1.5) / radius)
		local offset = (TAU / L.GapsPerRing) * ((ringIndex - 1) / #L.RingRadii)
		for g = 0, L.GapsPerRing - 1 do
			local from = offset + TAU * (g / L.GapsPerRing) + gapHalf
			local to = offset + TAU * ((g + 1) / L.GapsPerRing) - gapHalf
			ringSegments += arc(rim, "RingWall", radius, from, to, y,
				WALL_H, WALL_T, COLOUR_WALL, "Chomp_Wall")
		end
	end

	local radials = L.RadialsPerQuadrant * 4
	for i = 0, radials - 1 do
		local a = TAU * (i / radials) + TAU / (radials * 2)
		if not inRampMouth(a) then
			-- a spoke spans one gap between rings, never the whole band, or the
			-- rim stops being navigable
			local r0 = L.RingRadii[1 + (i % (#L.RingRadii - 1))]
			local r1 = L.RingRadii[2 + (i % (#L.RingRadii - 1))]
			local mid = (r0 + r1) / 2
			local p = part("RadialWall", Vector3.new(WALL_T, WALL_H, r1 - r0),
				radialAt(mid, a, y), COLOUR_WALL, rim)
			CollectionService:AddTag(p, "Chomp_Wall")
			radialSegments += 1
		end
	end

	-- ── The slopes ───────────────────────────────────────────────────────
	-- Broad, gentle and unmissable. This is the commitment from safety into the
	-- bowl, so it should read as an invitation rather than a chute.
	local rampPitch = math.atan2(L.RimHeight, L.RampRunStuds)
	local rampLength = math.sqrt(L.RampRunStuds ^ 2 + L.RimHeight ^ 2)
	for _, a in rampAngles do
		local outer = L.RimInner
		local inner = L.RimInner - L.RampRunStuds
		local midRadius = (inner + outer) / 2
		local cf = radialAt(midRadius, a, L.RimHeight / 2)
			* CFrame.Angles(-rampPitch, 0, 0)
		local ramp = part("Ramp", Vector3.new(L.RampWidthStuds, SLAB, rampLength),
			cf, COLOUR_RAMP, links)
		CollectionService:AddTag(ramp, "Chomp_Link")
	end

	-- ── Garages, one per spawn quadrant, on the outer rim ────────────────
	local garages: { Vector3 } = {}
	for i = 0, L.GarageCount - 1 do
		local a = TAU * (i / L.GarageCount)
		local r = (L.RingRadii[#L.RingRadii] + L.RimOuter) / 2
		local pos = onCircle(r, a, L.RimHeight + SLAB / 2 + 0.2)
		local pad = part("GarageFloor", Vector3.new(M.CellSize * 2, 0.4, M.CellSize * 2),
			tangentAt(r, a, pos.Y), COLOUR_GARAGE, bays)
		pad.Transparency = 0.55
		pad.CanCollide = false
		CollectionService:AddTag(pad, "Chomp_Garage")
		table.insert(garages, pos)
	end

	-- ── Guardian chamber ─────────────────────────────────────────────────
	-- Adjacent to the rim rather than across the route, so meeting the guardian
	-- is a decision rather than a collision (D-CHOMP-041). The commitment
	-- boundary is visible from outside and is deliberately not a wall.
	local ga = math.rad(L.GuardianAngleDegrees)
	local chamberR = L.RimOuter + L.GuardianChamberStuds / 2
	local chamberCF = radialAt(chamberR, ga, L.RimHeight)
	part("GuardianFloor", Vector3.new(L.GuardianChamberStuds, SLAB, L.GuardianChamberStuds),
		chamberCF, COLOUR_RIM, map)

	local half = L.GuardianChamberStuds / 2
	local wallY = L.RimHeight + SLAB / 2 + WALL_H / 2
	for _, side in { -1, 1 } do
		local p = part("ChamberWall", Vector3.new(WALL_T, WALL_H, L.GuardianChamberStuds),
			radialAt(chamberR, ga, wallY) * CFrame.new(side * half, 0, 0), COLOUR_WALL, map)
		CollectionService:AddTag(p, "Chomp_Wall")
	end
	local back = part("ChamberWall", Vector3.new(L.GuardianChamberStuds, WALL_H, WALL_T),
		radialAt(chamberR, ga, wallY) * CFrame.new(0, 0, half), COLOUR_WALL, map)
	CollectionService:AddTag(back, "Chomp_Wall")

	-- The boundary you cross knowingly. Not collidable: crossing under-powered
	-- is meant to be possible and fatal, not blocked (D-CHOMP-041).
	local boundary = part("CommitmentBoundary",
		Vector3.new(L.GuardianChamberStuds, WALL_H, 1),
		radialAt(chamberR, ga, wallY) * CFrame.new(0, 0, -half), COLOUR_CHAMBER, map)
	boundary.Transparency = 0.65
	boundary.CanCollide = false
	CollectionService:AddTag(boundary, "Chomp_Boundary")

	-- The outer wall has to open where the chamber meets it.
	for _, p in rim:GetChildren() do
		if p.Name == "OuterWall" and p:IsA("BasePart") then
			local a = math.atan2(p.Position.Z, p.Position.X)
			local d = math.abs((a - ga + math.pi) % TAU - math.pi)
			if d < math.atan((L.GuardianChamberStuds / 2) / L.RimOuter) then
				p:Destroy()
			end
		end
	end

	-- ── Spawn ────────────────────────────────────────────────────────────
	local home = garages[1]
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Level1Spawn"
	spawn.Size = Vector3.new(M.CellSize, 1, M.CellSize)
	spawn.CFrame = CFrame.new(home + Vector3.new(0, 0.6, 0))
	spawn.Anchored = true
	spawn.CanCollide = false
	spawn.Transparency = 0.7
	spawn.Parent = map

	print(("[BowlMap] Level 1 built: bowl r%d, rim %d-%d at height %d, %d ring segments, " ..
		"%d radials, %d ramps, %d garages, outer %d segments. cell %d wall %d")
		:format(L.RimInner, L.RimInner, L.RimOuter, L.RimHeight, ringSegments,
			radialSegments, #rampAngles, #garages, outerSegments, M.CellSize, WALL_H))
end

build()
