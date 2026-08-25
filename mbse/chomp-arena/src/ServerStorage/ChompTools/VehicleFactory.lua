--!strict
--[[
	VehicleFactory — CHAIN-VEHICLE

	Builds a chassis model from a declarative spec table, so a vehicle is text
	in git rather than a binary blob (D-CHOMP-022).

	Why this exists: a .rbxm cannot be diffed, reviewed, or rebuilt after a
	tuning change, and an agent without a Roblox runtime cannot inspect what it
	just produced. A spec table can be read, reviewed, regenerated and tested
	with one command.

	It also removes a whole class of conformance failure by construction:

	  * attributes are taken from ChompConfig, never written by hand, so a
	    model can never disagree with the config (D-CHOMP-019)
	  * every non-primary part is welded, Massless and non-colliding
	  * the tag and PrimaryPart are always set
	  * the mouth is asserted to sit forward of the origin before the model is
	    returned — backwards does not look wrong, it inverts combat, so it is
	    caught here rather than in a playtest

	Usage, from the Studio command bar:

		local F = require(game.ServerStorage.ChompTools.VehicleFactory)
		F.buildAll()          -- every spec -> ReplicatedStorage.Vehicles
		F.preview("Apex")     -- one, dropped in front of the camera to look at
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("ChompConfig"))

export type PartSpec = {
	name: string,
	class: string?,          -- "Part" (default) or "WedgePart"
	shape: string?,          -- Block, Ball, Cylinder — Part only
	size: Vector3,
	offset: Vector3,         -- from the chassis origin. -Z is FORWARD
	rotation: Vector3?,      -- degrees, optional
	color: Color3,
	material: Enum.Material?,
	transparency: number?,
	collide: boolean?,       -- only the chassis should ever be true
}

export type VehicleSpec = {
	chassisId: string,
	triangleCount: number,
	parts: { PartSpec },
}

local VehicleFactory = {}

local function specsFolder(): Folder
	return ServerStorage.ChompTools:FindFirstChild("VehicleSpecs") :: Folder
end

local function makePart(spec: PartSpec): BasePart
	local class = spec.class or "Part"
	local part = Instance.new(class) :: BasePart
	part.Name = spec.name
	part.Size = spec.size
	part.Color = spec.color
	part.Material = spec.material or Enum.Material.SmoothPlastic
	part.Transparency = spec.transparency or 0
	part.Anchored = false
	part.CanCollide = spec.collide == true
	part.CanQuery = false
	part.CanTouch = false
	if class == "Part" and spec.shape then
		(part :: Part).Shape = (Enum.PartType :: any)[spec.shape]
	end
	if part:IsA("Part") then
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
	end
	return part
end

--[[
	build(spec) -> Model

	Assembles the model at the origin, facing -Z, then welds everything to the
	chassis. Throws on anything the vehicle contract forbids, because a model
	that violates the contract should never reach a place file at all.
]]
function VehicleFactory.build(spec: VehicleSpec): Model
	local chassisConfig = Config.Chassis[spec.chassisId]
	if not chassisConfig then
		error(("[VehicleFactory] '%s' is not a chassis in ChompConfig.Chassis"):format(spec.chassisId))
	end

	local model = Instance.new("Model")
	model.Name = spec.chassisId

	local primary: BasePart? = nil
	local built: { BasePart } = {}

	for _, partSpec in ipairs(spec.parts) do
		local part = makePart(partSpec)
		local cf = CFrame.new(partSpec.offset)
		if partSpec.rotation then
			cf = cf * CFrame.Angles(
				math.rad(partSpec.rotation.X),
				math.rad(partSpec.rotation.Y),
				math.rad(partSpec.rotation.Z))
		end
		part.CFrame = cf
		part.Parent = model
		table.insert(built, part)
		if partSpec.name == "Chassis" then
			primary = part
		end
	end

	if not primary then
		error(("[VehicleFactory] %s has no part named 'Chassis'"):format(spec.chassisId))
	end
	model.PrimaryPart = primary

	-- Weld everything to the chassis, and enforce the physics rules rather
	-- than trusting the spec to have got them right.
	for _, part in ipairs(built) do
		if part ~= primary then
			part.Massless = true
			part.CanCollide = false
			local weld = Instance.new("WeldConstraint")
			weld.Name = "Weld" .. part.Name
			weld.Part0 = primary
			weld.Part1 = part
			weld.Parent = primary
		end
	end

	-- Attributes come from the config. They are never hand-written, so a model
	-- cannot drift from the numbers the game actually uses (D-CHOMP-019).
	model:SetAttribute("Tier", chassisConfig.Tier)
	model:SetAttribute("BarCapacity", chassisConfig.BarCapacity)
	model:SetAttribute("Power", chassisConfig.Power)
	model:SetAttribute("MouthArcDegrees", chassisConfig.MouthArcDegrees)
	model:SetAttribute("TriangleCount", spec.triangleCount)
	CollectionService:AddTag(model, "Chomp_Vehicle")

	VehicleFactory.assertContract(model, spec)
	return model
end

--[[
	assertContract(model, spec)

	The checks cheap enough to run at build time. The full scan lives in
	VehicleConformance (CHOMP-TC-044); this is the subset that should stop a
	bad model existing rather than merely reporting it later.
]]
function VehicleFactory.assertContract(model: Model, spec: VehicleSpec)
	local budgets = Config.Budgets
	local upper = model:FindFirstChild("MouthUpper") :: BasePart?
	local lower = model:FindFirstChild("MouthLower") :: BasePart?
	if not (upper and lower) then
		error(("[VehicleFactory] %s needs both MouthUpper and MouthLower"):format(model.Name))
	end

	-- THE check. -Z is forward, so a forward mouth has a negative Z offset.
	local mouthZ = (upper.Position.Z + lower.Position.Z) / 2
	if mouthZ >= 0 then
		error(("[VehicleFactory] %s has its mouth at Z=%.2f. The mouth must be FORWARD " ..
			"(negative Z). A backwards vehicle does not look wrong — it inverts combat.")
			:format(model.Name, mouthZ))
	end
	if upper.Position.Y <= lower.Position.Y then
		error(("[VehicleFactory] %s: MouthUpper must sit above MouthLower"):format(model.Name))
	end

	local teamColour = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d.Name == "TeamColour" then teamColour += 1 end
		if d:IsA("LuaSourceContainer") then
			error(("[VehicleFactory] %s contains a script. Content carries no scripts.")
				:format(model.Name))
		end
	end
	if teamColour ~= 1 then
		error(("[VehicleFactory] %s has %d parts named TeamColour, needs exactly 1")
			:format(model.Name, teamColour))
	end

	local parts = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then parts += 1 end
	end
	if parts > budgets.VehicleParts then
		error(("[VehicleFactory] %s has %d parts, limit %d"):format(model.Name, parts, budgets.VehicleParts))
	end
	if spec.triangleCount > budgets.VehicleTriangles then
		error(("[VehicleFactory] %s declares %d triangles, limit %d")
			:format(model.Name, spec.triangleCount, budgets.VehicleTriangles))
	end

	local _, size = model:GetBoundingBox()
	local limit = budgets.VehicleBounds
	if size.X > limit.X or size.Y > limit.Y or size.Z > limit.Z then
		error(("[VehicleFactory] %s is %.2f x %.2f x %.2f, limit %s")
			:format(model.Name, size.X, size.Y, size.Z, tostring(limit)))
	end
end

--[[ buildAll() -> { Model }  — every spec into ReplicatedStorage.Vehicles ]]
function VehicleFactory.buildAll(): { Model }
	local vehicles = ReplicatedStorage:FindFirstChild("Vehicles")
	if not vehicles then
		vehicles = Instance.new("Folder")
		vehicles.Name = "Vehicles"
		vehicles.Parent = ReplicatedStorage
	end

	local built = {}
	for _, module in ipairs(specsFolder():GetChildren()) do
		if module:IsA("ModuleScript") then
			local spec = require(module) :: VehicleSpec
			local existing = vehicles:FindFirstChild(spec.chassisId)
			if existing then existing:Destroy() end
			local model = VehicleFactory.build(spec)
			model.Parent = vehicles
			table.insert(built, model)
			print(("[VehicleFactory] built %s"):format(spec.chassisId))
		end
	end
	if #built == 0 then
		warn("[VehicleFactory] no specs found in ServerStorage.ChompTools.VehicleSpecs")
	end
	return built
end

--[[ preview(chassisId) — drop one in front of the camera to look at it ]]
function VehicleFactory.preview(chassisId: string): Model?
	local module = specsFolder():FindFirstChild(chassisId)
	if not module or not module:IsA("ModuleScript") then
		warn(("[VehicleFactory] no spec named %s"):format(chassisId))
		return nil
	end
	local model = VehicleFactory.build(require(module) :: VehicleSpec)
	local camera = Workspace.CurrentCamera
	local where = camera and (camera.CFrame * CFrame.new(0, 0, -16)) or CFrame.new(0, 5, 0)
	model:PivotTo(where)
	model.Parent = Workspace
	return model
end

return VehicleFactory
