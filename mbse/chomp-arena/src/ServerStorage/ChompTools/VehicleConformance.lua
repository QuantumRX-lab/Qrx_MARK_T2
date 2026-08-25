--[[
	VehicleConformance — the executable form of CHOMP-TC-044.

	Checks a delivered chassis model against 03_architecture/vehicle_contract.md
	so that models are accepted by scan rather than by eye (CHOMP-SYS-054).

	Usage, from a Studio command bar or a test script:

		local Scan = require(game.ServerStorage.ChompTools.VehicleConformance)
		Scan.report(Scan.checkAll())          -- every model in ReplicatedStorage.Vehicles
		Scan.report({ Scan.check(someModel) })

	Returns a plain table so it can also be driven from an automated harness:
		{ name = "Standard", pass = false, checks = { {id=..., pass=..., detail=...}, ... } }

	TWO HONEST LIMITS, both reported rather than hidden:

	  * Triangle count is not readable from Luau. The model must declare a
	    `TriangleCount` attribute; the scan checks the declared number against
	    the budget and marks it DECLARED, not measured. Verify the real figure
	    in the mesh tooling before trusting it.
	  * Silhouette fraction is approximated from bounding boxes along the camera
	    axis. It catches a mouth that is obviously too small; it cannot replace
	    looking at the thing on an iPad.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage:WaitForChild("ChompConfig"))

local VehicleConformance = {}

local REQUIRED_ATTRIBUTES = {
	"Tier", "BarCapacity", "Power", "BaseSpeed", "BaseTurn", "MouthArcDegrees",
}
local BANNED_CLASSES = {
	Script = true, LocalScript = true, ModuleScript = true,
	VehicleSeat = true, UnionOperation = true, NegateOperation = true,
	Motor6D = false,  -- allowed: animation joints are fine, motors driving wheels are not
	HingeConstraint = true, CylindricalConstraint = true, SpringConstraint = true,
	Torque = true, LinearVelocity = true, AngularVelocity = true, VectorForce = true,
}

local function result(id, pass, detail)
	return { id = id, pass = pass, detail = detail }
end

local function descendantsOfClass(model, className)
	local out = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA(className) then
			table.insert(out, d)
		end
	end
	return out
end

-- Is the mouth wedge on the forward side of the chassis?
-- The contract's single most important rule: the mouth faces
-- PrimaryPart.CFrame.LookVector. A model built backwards does not look wrong,
-- it inverts the combat system, so this is checked first and reported first.
local function checkMouthOrientation(model, checks)
	local primary = model.PrimaryPart
	local upper = model:FindFirstChild("MouthUpper", true)
	local lower = model:FindFirstChild("MouthLower", true)

	if not (upper and lower) then
		table.insert(checks, result("mouth.parts", false,
			"MouthUpper and MouthLower must both exist (found upper=" ..
			tostring(upper ~= nil) .. ", lower=" .. tostring(lower ~= nil) .. ")"))
		return
	end
	table.insert(checks, result("mouth.parts", true, "MouthUpper and MouthLower present"))

	if not primary then return end

	local originCF = primary.CFrame
	local mouthCentre = (upper.Position + lower.Position) / 2
	local localMouth = originCF:PointToObjectSpace(mouthCentre)

	-- LookVector is -Z in object space, so a forward mouth has negative Z.
	local forwardOffset = -localMouth.Z
	local lateralOffset = math.abs(localMouth.X)

	table.insert(checks, result("mouth.forward", forwardOffset > 0,
		string.format(
			"mouth centre is %.2f studs %s of the chassis origin along LookVector " ..
			"(must be forward; negative means the model is built backwards and combat will invert)",
			math.abs(forwardOffset), forwardOffset > 0 and "ahead" or "BEHIND")))

	table.insert(checks, result("mouth.centred", lateralOffset < 0.75,
		string.format("mouth is %.2f studs off the centre line (tolerance 0.75)", lateralOffset)))

	-- The jaw must open across the LookVector: upper above lower in object space.
	local dy = originCF:PointToObjectSpace(upper.Position).Y - originCF:PointToObjectSpace(lower.Position).Y
	table.insert(checks, result("mouth.wedge", dy > 0,
		string.format("MouthUpper sits %.2f studs above MouthLower (must be positive)", dy)))
end

local function checkAttributes(model, checks)
	local spec = Config.Chassis[model.Name]
	if not spec then
		table.insert(checks, result("attributes.known", false,
			"model name '" .. model.Name .. "' is not a chassis in ChompConfig.Chassis"))
		return
	end
	table.insert(checks, result("attributes.known", true, "matches ChompConfig.Chassis." .. model.Name))

	for _, key in ipairs(REQUIRED_ATTRIBUTES) do
		local actual = model:GetAttribute(key)
		local expected = spec[key]
		if actual == nil then
			table.insert(checks, result("attributes." .. key, false, "missing (expected " .. tostring(expected) .. ")"))
		elseif expected ~= nil and actual ~= expected then
			table.insert(checks, result("attributes." .. key, false,
				string.format("is %s, ChompConfig says %s — the model and the config disagree",
					tostring(actual), tostring(expected))))
		else
			table.insert(checks, result("attributes." .. key, true, tostring(actual)))
		end
	end
end

local function checkStructure(model, checks)
	local primary = model.PrimaryPart
	table.insert(checks, result("structure.primary", primary ~= nil and primary.Name == "Chassis",
		primary and ("PrimaryPart is '" .. primary.Name .. "' (must be 'Chassis')") or "PrimaryPart is not set"))

	table.insert(checks, result("structure.tag", CollectionService:HasTag(model, "Chomp_Vehicle"),
		"Chomp_Vehicle tag"))

	local teamColour = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d.Name == "TeamColour" then table.insert(teamColour, d) end
	end
	table.insert(checks, result("structure.teamcolour", #teamColour == 1,
		#teamColour .. " parts named TeamColour (must be exactly 1)"))

	local banned = {}
	for _, d in ipairs(model:GetDescendants()) do
		if BANNED_CLASSES[d.ClassName] then
			table.insert(banned, d.ClassName .. " '" .. d.Name .. "'")
		end
	end
	table.insert(checks, result("structure.banned", #banned == 0,
		#banned == 0 and "no scripts, unions, seats or motion constraints"
		or ("found " .. table.concat(banned, ", "))))
end

local function checkPhysics(model, checks)
	local primary = model.PrimaryPart
	local badMass, badCollide, anchored, unwelded = {}, {}, {}, {}

	for _, part in ipairs(descendantsOfClass(model, "BasePart")) do
		if part ~= primary then
			if not part.Massless then table.insert(badMass, part.Name) end
			if part.CanCollide then table.insert(badCollide, part.Name) end
			if #part:GetJoints() == 0 then table.insert(unwelded, part.Name) end
		end
		if part.Anchored then table.insert(anchored, part.Name) end
	end

	table.insert(checks, result("physics.massless", #badMass == 0,
		#badMass == 0 and "all non-primary parts Massless" or ("not Massless: " .. table.concat(badMass, ", "))))
	table.insert(checks, result("physics.collide", #badCollide == 0,
		#badCollide == 0 and "only Chassis collides" or ("CanCollide true on: " .. table.concat(badCollide, ", "))))
	table.insert(checks, result("physics.anchored", #anchored == 0,
		#anchored == 0 and "nothing anchored" or ("anchored: " .. table.concat(anchored, ", "))))
	table.insert(checks, result("physics.welded", #unwelded == 0,
		#unwelded == 0 and "all parts jointed to the chassis" or ("no joints: " .. table.concat(unwelded, ", "))))
end

local function checkBudgets(model, checks)
	local budgets = Config.Budgets
	local parts = descendantsOfClass(model, "BasePart")

	table.insert(checks, result("budget.parts", #parts <= budgets.VehicleParts,
		#parts .. " parts (limit " .. budgets.VehicleParts .. ")"))

	local _, size = model:GetBoundingBox()
	local limit = budgets.VehicleBounds
	local fits = size.X <= limit.X and size.Y <= limit.Y and size.Z <= limit.Z
	table.insert(checks, result("budget.bounds", fits,
		string.format("%.2f x %.2f x %.2f studs (limit %s)", size.X, size.Y, size.Z, tostring(limit))))

	local declared = model:GetAttribute("TriangleCount")
	if declared == nil then
		table.insert(checks, result("budget.triangles", false,
			"no TriangleCount attribute — Luau cannot measure this, so the model must declare it"))
	else
		table.insert(checks, result("budget.triangles", declared <= budgets.VehicleTriangles,
			string.format("DECLARED %d (limit %d) — declared, not measured; confirm in the mesh tooling",
				declared, budgets.VehicleTriangles)))
	end

	local textures = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Decal") or d:IsA("Texture") or (d:IsA("MeshPart") and d.TextureID ~= "") then
			textures += 1
		end
	end
	table.insert(checks, result("budget.textures", textures <= budgets.VehicleTextures,
		textures .. " textures (limit " .. budgets.VehicleTextures .. ")"))
end

-- Approximate: mouth frontal area over chassis frontal area, both measured
-- across the axes perpendicular to LookVector. Catches an obviously
-- unreadable mouth. Does not replace looking at it on the device.
local function checkSilhouette(model, checks)
	local upper = model:FindFirstChild("MouthUpper", true)
	local lower = model:FindFirstChild("MouthLower", true)
	if not (upper and lower) then return end

	local _, whole = model:GetBoundingBox()
	local wholeArea = whole.X * whole.Y
	local mouthArea = math.max(upper.Size.X, lower.Size.X) * (upper.Size.Y + lower.Size.Y)
	local fraction = wholeArea > 0 and (mouthArea / wholeArea) or 0
	local target = Config.Budgets.MouthSilhouetteFraction

	table.insert(checks, result("readability.silhouette", fraction >= target,
		string.format("mouth is approximately %.0f%% of the frontal silhouette (target %.0f%%) " ..
			"— APPROXIMATE, confirm visually on an iPad", fraction * 100, target * 100)))
end

function VehicleConformance.check(model)
	local checks = {}
	checkStructure(model, checks)
	checkMouthOrientation(model, checks)
	checkAttributes(model, checks)
	checkPhysics(model, checks)
	checkBudgets(model, checks)
	checkSilhouette(model, checks)

	local pass = true
	for _, c in ipairs(checks) do
		if not c.pass then pass = false end
	end
	return { name = model.Name, pass = pass, checks = checks }
end

function VehicleConformance.checkAll()
	local folder = ReplicatedStorage:FindFirstChild("Vehicles")
	if not folder then
		return {}, "ReplicatedStorage.Vehicles does not exist"
	end
	local results = {}
	for _, model in ipairs(folder:GetChildren()) do
		if model:IsA("Model") then
			table.insert(results, VehicleConformance.check(model))
		end
	end
	return results
end

function VehicleConformance.report(results)
	local allPass = true
	for _, r in ipairs(results) do
		print(("── %s: %s"):format(r.name, r.pass and "PASS" or "FAIL"))
		for _, c in ipairs(r.checks) do
			if not c.pass then
				print(("   FAIL  %-24s %s"):format(c.id, c.detail))
			end
		end
		if not r.pass then allPass = false end
	end
	if #results == 0 then
		print("no vehicle models found")
		allPass = false
	end
	print(allPass and "CONFORMANCE: PASS" or "CONFORMANCE: FAIL")
	return allPass
end

return VehicleConformance
