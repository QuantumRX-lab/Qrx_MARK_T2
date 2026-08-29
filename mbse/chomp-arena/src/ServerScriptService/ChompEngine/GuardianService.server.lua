--!strict
-- Infinite guardian encounter beneath the Level 1 centre hatch.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage:WaitForChild("ChompConfig"))
local ItemModels = require(ServerStorage:WaitForChild("ChompTools"):WaitForChild("ItemModels"))
local CombatState = require(script.Parent:WaitForChild("CombatState"))
local G = Config.Guardian
local P = Config.Palette

while Workspace:GetAttribute("ChompLevel1MapReady") ~= true do
	Workspace:GetAttributeChangedSignal("ChompLevel1MapReady"):Wait()
end

local ghostFolder = Workspace:FindFirstChild("Ghosts")
while not ghostFolder do
	task.wait(0.1)
	ghostFolder = Workspace:FindFirstChild("Ghosts")
end
local maps = Workspace:FindFirstChild("Maps")
local pickupFolder = Instance.new("Folder")
pickupFolder.Name = "GuardianPickups"
pickupFolder.Parent = Workspace
local telegraphFolder = Instance.new("Folder")
telegraphFolder.Name = "GuardianTelegraphs"
telegraphFolder.Parent = Workspace
local projectileFolder = Instance.new("Folder")
projectileFolder.Name = "GuardianProjectiles"
projectileFolder.Parent = Workspace

local function piece(model: Model, name: string, size: Vector3, offset: CFrame,
		colour: Color3, material: Enum.Material, shape: Enum.PartType?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = offset
	p.Color = colour
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = true
	if shape then p.Shape = shape end
	p.Parent = model
	return p
end

local function guardianModel(): Model
	local model = Instance.new("Model")
	model.Name = "Guardian"
	local body = piece(model, "Body", Vector3.new(30, 30, 30), CFrame.new(),
		P.GuardianBody, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	local rim = piece(model, "Rim", Vector3.new(31.2, 31.2, 31.2), CFrame.new(),
		P.GuardianRim, Enum.Material.ForceField, Enum.PartType.Ball)
	rim.Transparency = 0.72
	piece(model, "Crown", Vector3.new(18, 7, 12), CFrame.new(0, 13, 1),
		P.GuardianFace, Enum.Material.Slate)
	for _, side in { -1, 1 } do
		local eye = piece(model, "Eye", Vector3.new(6.5, 7.5, 2.2), CFrame.new(side * 6.2, 5, -14.4),
			P.Gold, Enum.Material.Neon, Enum.PartType.Ball)
		local eyeLight = Instance.new("PointLight")
		eyeLight.Color = P.Gold
		eyeLight.Brightness = 1.8
		eyeLight.Range = 34
		eyeLight.Parent = eye
		piece(model, side < 0 and "PupilLeft" or "PupilRight", Vector3.new(2.4, 2.8, 1.2),
			CFrame.new(side * 6.2, 5, -16), P.Ghost, Enum.Material.Neon, Enum.PartType.Ball)
		piece(model, "Brow", Vector3.new(8, 2.5, 2.5),
			CFrame.new(side * 6, 9, -14.2) * CFrame.Angles(0, 0, side * -0.25),
			P.GuardianFace, Enum.Material.Slate)
	end
	piece(model, "MouthGlow", Vector3.new(18, 7, 2), CFrame.new(0, -5, -14.8),
		P.Danger, Enum.Material.Neon)
	local weak = piece(model, "MawCore", Vector3.new(10, 6, 2.4), CFrame.new(0, -5, -16),
		P.GuardianWeak, Enum.Material.Neon, Enum.PartType.Ball)
	weak.Transparency = 1
	piece(model, "UpperMaw", Vector3.new(22, 4, 4), CFrame.new(0, -2, -14),
		P.GuardianFace, Enum.Material.Slate)
	piece(model, "LowerMaw", Vector3.new(22, 4, 4), CFrame.new(0, -8, -14),
		P.GuardianFace, Enum.Material.Slate)
	for row = -1, 1, 2 do
		for tooth = -3, 3 do
			piece(model, "Tooth", Vector3.new(2.1, 3.8, 2.1),
				CFrame.new(tooth * 2.5, -5 + row * 2.3, -16),
				P.Gold, Enum.Material.Neon)
		end
	end
	model.PrimaryPart = body
	model:SetAttribute("Dead", false)
	model:SetAttribute("Guardian", true)
	model:SetAttribute("Phase", "STALK")
	model:SetAttribute("WeakPoint", "CLOSED")
	model:SetAttribute("PhaseEndsAt", 0)
	local outline = Instance.new("Highlight")
	outline.Name = "GuardianOutline"
	outline.Adornee = model
	outline.DepthMode = Enum.HighlightDepthMode.Occluded
	outline.FillTransparency = 1
	outline.OutlineColor = P.GuardianRim
	outline.OutlineTransparency = 0.18
	outline.Parent = model
	CollectionService:AddTag(model, "Chomp_Ghost")
	return model
end

local function chamberPlayers(): { Player }
	local out = {}
	for _, player in Players:GetPlayers() do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and root.Position.Y < G.ChamberY + 45 then table.insert(out, player) end
	end
	return out
end

local function publish(model: Model, level: number, health: number, maxHealth: number)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character then
			character:SetAttribute("ChompGuardianLevel", level)
			character:SetAttribute("ChompGuardianHealth", math.max(0, health))
			character:SetAttribute("ChompGuardianMaxHealth", maxHealth)
			character:SetAttribute("ChompGuardianRequiredPower", G.RequiredPower)
			character:SetAttribute("ChompGuardianPhase", model:GetAttribute("Phase") or "STALK")
			character:SetAttribute("ChompGuardianWeakPoint", model:GetAttribute("WeakPoint") or "CLOSED")
			character:SetAttribute("ChompGuardianPhaseEndsAt",
				(model:GetAttribute("PhaseEndsAt") :: number?) or 0)
			character:SetAttribute("ChompInGuardianArena",
				(character:GetPivot().Position.Y < G.RevealY))
		end
	end
	model:SetAttribute("GuardianLevel", level)
end

local function burst(at: Vector3)
	for i = 1, 28 do
		local shard = Instance.new("Part")
		shard.Size = Vector3.new(3, 3, 3) * math.random(8, 18) / 10
		shard.Shape = Enum.PartType.Ball
		shard.Color = i <= 8 and P.Gold or Color3.fromRGB(4, 4, 7)
		shard.Material = i <= 8 and Enum.Material.Neon or Enum.Material.Slate
		shard.Position = at + Vector3.new(math.random(-80, 80) / 10,
			math.random(-60, 80) / 10, math.random(-80, 80) / 10)
		shard.CanCollide = false
		shard.AssemblyLinearVelocity = Vector3.new(math.random(-100, 100),
			math.random(35, 120), math.random(-100, 100))
		CollectionService:AddTag(shard, "Chomp_Decor")
		shard.Parent = Workspace
		Debris:AddItem(shard, 2.2)
	end
end

local function grantHook(): BindableFunction?
	local hook = ServerStorage:WaitForChild("ChompTools"):FindFirstChild("GrantItem")
	return hook and hook:IsA("BindableFunction") and hook or nil
end

local pickupPlan = {
	{ id = "Cannon", angle = 0 }, { id = "HomingBomb", angle = math.pi / 2 },
	{ id = "Cannon", angle = math.pi }, { id = "Shield", angle = math.pi * 1.5 },
	{ id = "JetPack", angle = math.pi * 0.25 },
	{ id = "Cannon", angle = math.pi * 0.75 },
	{ id = "HomingBomb", angle = math.pi * 1.25 },
	{ id = "Shield", angle = math.pi * 1.75 },
}

for _, entry in pickupPlan do
	local position = Vector3.new(math.cos(entry.angle) * G.PickupRadiusStuds, G.ChamberY + 3,
		math.sin(entry.angle) * G.PickupRadiusStuds)
	local holder = Instance.new("Model")
	holder.Name = "GuardianPickup_" .. entry.id
	holder.Parent = pickupFolder
	local pad = piece(holder, "Pad", Vector3.new(10, 1, 10), CFrame.new(position),
		ItemModels.colour(entry.id), Enum.Material.Neon)
	local display = ItemModels.build(entry.id)
	display:ScaleTo(1.8)
	display:PivotTo(CFrame.new(position + Vector3.new(0, 5, 0)))
	display.Parent = holder
	local available = true
	task.spawn(function()
		while holder.Parent do
			task.wait(0.2)
			if not available then continue end
			for _, player in chamberPlayers() do
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root and (root.Position - position).Magnitude < 11 then
					local hook = grantHook()
					local ok, granted = false, false
					if hook then ok, granted = pcall(function() return hook:Invoke(player, entry.id, false) end) end
					if ok and granted then
						available = false
						for _, d in holder:GetDescendants() do
							if d:IsA("BasePart") then d.Transparency = 1 end
						end
						task.delay(G.PickupRespawnSeconds, function()
							if not holder.Parent then return end
							available = true
							for _, d in holder:GetDescendants() do
								if d:IsA("BasePart") then d.Transparency = 0 end
							end
						end)
						break
					end
				end
			end
		end
	end)
	pad.CanCollide = false
end

local level = 0
local guardian: Model? = nil
local currentHealth = 0
local maxHealth = 0
local position = Vector3.new(0, G.ChamberY + 17, G.GuardianStartZ)
local heading = Vector3.new(0, 0, 1)
local phase = "STALK"
local phaseStartedAt = 0
local phaseEndsAt = 0
local phaseFrom = position
local phaseTarget = position
local attackCursor = 0
local phaseHit: { [Player]: boolean } = {}

local function chamberPoint(value: Vector3): Vector3
	local limit = G.ChamberHalfStuds - 32
	return Vector3.new(math.clamp(value.X, -limit, limit), G.ChamberY + 17,
		math.clamp(value.Z, -limit, limit))
end

local function diskMarker(name: string, at: Vector3, diameter: number, colour: Color3): BasePart
	local marker = Instance.new("Part")
	marker.Name = name
	marker.Shape = Enum.PartType.Cylinder
	marker.Size = Vector3.new(0.35, diameter, diameter)
	marker.CFrame = CFrame.new(at.X, G.ChamberY + 1.05, at.Z) * CFrame.Angles(0, 0, math.pi / 2)
	marker.Color = colour
	marker.Material = Enum.Material.Neon
	marker.Transparency = 0.25
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanQuery = false
	marker.CastShadow = false
	marker.Parent = telegraphFolder
	return marker
end

local function laneMarker(from: Vector3, to: Vector3): BasePart
	local flatFrom = Vector3.new(from.X, G.ChamberY + 1.1, from.Z)
	local flatTo = Vector3.new(to.X, G.ChamberY + 1.1, to.Z)
	local distance = (flatTo - flatFrom).Magnitude
	local middle = (flatFrom + flatTo) * 0.5
	local marker = Instance.new("Part")
	marker.Name = "DashLane"
	marker.Size = Vector3.new(G.DashWidthStuds, 0.35, distance)
	marker.CFrame = CFrame.lookAt(middle, flatTo)
	marker.Color = P.Danger
	marker.Material = Enum.Material.Neon
	marker.Transparency = 0.3
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanQuery = false
	marker.CastShadow = false
	marker.Parent = telegraphFolder
	return marker
end

local function phaseLabel(value: string): string
	if value == "POUNCE_TELL" then return "POUNCE INCOMING" end
	if value == "DASH_TELL" then return "DASH LANE" end
	if value == "HURL_TELL" then return "GHOST HURL" end
	if value == "VULNERABLE" then return "MAW OPEN" end
	return value
end

local function setPhase(model: Model, nextPhase: string, duration: number)
	phase = nextPhase
	phaseStartedAt = os.clock()
	phaseEndsAt = phaseStartedAt + duration
	table.clear(phaseHit)
	telegraphFolder:ClearAllChildren()
	model:SetAttribute("Phase", phaseLabel(nextPhase))
	model:SetAttribute("PhaseEndsAt", phaseEndsAt)
	local vulnerable = nextPhase == "VULNERABLE"
	model:SetAttribute("WeakPoint", vulnerable and "MAW" or "CLOSED")
	local core = model:FindFirstChild("MawCore") :: BasePart?
	local glow = model:FindFirstChild("MouthGlow") :: BasePart?
	if core then core.Transparency = vulnerable and 0 or 1 end
	if glow then glow.Color = vulnerable and P.GuardianWeak or P.Danger end
	if nextPhase == "POUNCE_TELL" then
		diskMarker("PounceLanding", phaseTarget, G.PounceRadiusStuds * 2, P.Danger)
	elseif nextPhase == "DASH_TELL" then
		laneMarker(position, phaseTarget)
	elseif nextPhase == "HURL_TELL" then
		local direction = Vector3.new(phaseTarget.X - position.X, 0, phaseTarget.Z - position.Z)
		local right = direction.Magnitude > 0.1 and Vector3.new(-direction.Unit.Z, 0, direction.Unit.X)
			or Vector3.new(1, 0, 0)
		for offset = -1, 1 do
			diskMarker("HurlLanding", chamberPoint(phaseTarget + right * offset * G.HurlSpreadStuds),
				G.HurlRadiusStuds * 2, P.NeonB)
		end
	end
	for _, player in chamberPlayers() do
		local character = player.Character
		if character then
			character:SetAttribute("ChompGuardianPhase", phaseLabel(nextPhase))
			character:SetAttribute("ChompGuardianWeakPoint", vulnerable and "MAW" or "CLOSED")
			character:SetAttribute("ChompGuardianPhaseEndsAt", phaseEndsAt)
			if string.find(nextPhase, "_TELL", 1, true) then
				character:SetAttribute("ChompGuardianTellAt", phaseStartedAt)
			elseif vulnerable then
				character:SetAttribute("ChompGuardianVulnerableAt", phaseStartedAt)
			end
		end
	end
end

local function damagePlayer(player: Player, damage: number, source: string)
	if phaseHit[player] then return end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (character and humanoid) then return end
	local gate = CombatState.beginHit(character, source)
	if gate == "Apply" then humanoid:TakeDamage(damage) end
	if gate ~= "Blocked" then
		phaseHit[player] = true
	end
end

local function damageAt(at: Vector3, radius: number, damage: number, source: string)
	for _, player in chamberPlayers() do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local delta = Vector3.new(root.Position.X - at.X, 0, root.Position.Z - at.Z)
			if delta.Magnitude <= radius then damagePlayer(player, damage, source) end
		end
	end
end

local function ghostPod(from: Vector3, to: Vector3)
	task.spawn(function()
		local pod = Instance.new("Model")
		pod.Name = "GuardianGhostPod"
		local body = piece(pod, "Body", Vector3.new(8, 8, 8), CFrame.new(from),
			P.NeonB, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		for _, side in { -1, 1 } do
			piece(pod, "Eye", Vector3.new(1.6, 2, 1), CFrame.new(from + Vector3.new(side * 1.8, 1, -3.7)),
				P.Ghost, Enum.Material.Neon, Enum.PartType.Ball)
		end
		pod.PrimaryPart = body
		pod.Parent = projectileFolder
		local started = os.clock()
		while pod.Parent do
			local alpha = math.clamp((os.clock() - started) / G.HurlFlightSeconds, 0, 1)
			local base = from:Lerp(to, alpha)
			local arc = math.sin(alpha * math.pi) * 28
			pod:PivotTo(CFrame.lookAt(base + Vector3.new(0, arc, 0), to))
			if alpha >= 1 then break end
			RunService.Heartbeat:Wait()
		end
		if pod.Parent then
			damageAt(to, G.HurlRadiusStuds, G.HurlDamage, "GuardianHurl")
			pod:Destroy()
		end
	end)
end

local function launchHurl()
	local direction = Vector3.new(phaseTarget.X - position.X, 0, phaseTarget.Z - position.Z)
	local right = direction.Magnitude > 0.1 and Vector3.new(-direction.Unit.Z, 0, direction.Unit.X)
		or Vector3.new(1, 0, 0)
	for offset = -1, 1 do
		ghostPod(position + Vector3.new(0, 8, 0),
			chamberPoint(phaseTarget + right * offset * G.HurlSpreadStuds) - Vector3.new(0, 14, 0))
	end
end

local function spawnGuardian()
	level += 1
	maxHealth = G.BaseHealth + G.HealthPerVictory * (level - 1)
	currentHealth = maxHealth
	position = Vector3.new(0, G.ChamberY + 17, G.GuardianStartZ)
	heading = Vector3.new(0, 0, 1)
	local model = guardianModel()
	guardian = model
	model:SetAttribute("Health", maxHealth)
	model:PivotTo(CFrame.lookAt(position, Vector3.new(0, position.Y, 0)))
	model.Parent = ghostFolder
	projectileFolder:ClearAllChildren()
	phaseFrom = position
	phaseTarget = position
	attackCursor = 0
	setPhase(model, "STALK", G.StalkSeconds)
	publish(model, level, currentHealth, maxHealth)

	local changing = false
	model:GetAttributeChangedSignal("Health"):Connect(function()
		if changing or model:GetAttribute("Dead") == true then return end
		local proposed = (model:GetAttribute("Health") :: number?) or currentHealth
		if proposed >= currentHealth then currentHealth = proposed return end
		local killerId = model:GetAttribute("KilledBy")
		local killer = typeof(killerId) == "number" and Players:GetPlayerByUserId(killerId) or nil
		local character = killer and killer.Character
		local power = character and ((character:GetAttribute("ChompPower") :: number?) or 0) or 0
		if not killer then
			changing = true
			model:SetAttribute("Health", currentHealth)
			changing = false
			model:SetAttribute("KilledBy", nil)
			return
		end
		if phase ~= "VULNERABLE" then
			changing = true
			model:SetAttribute("Health", currentHealth)
			changing = false
			model:SetAttribute("KilledBy", nil)
			if character then
				character:SetAttribute("ChompGuardianBlockedAt", os.clock())
			end
			return
		end
		if power < G.RequiredPower then
			local damage = (currentHealth - proposed) * G.UnderpoweredDamageFraction
			currentHealth = math.max(1, currentHealth - damage)
			changing = true
			model:SetAttribute("Health", currentHealth)
			changing = false
			if character then
				character:SetAttribute("ChompGuardianDeniedAt", os.clock())
				character:SetAttribute("ChompGuardianRequiredPower", G.RequiredPower)
			end
			model:SetAttribute("KilledBy", nil)
			publish(model, level, currentHealth, maxHealth)
			return
		end
		currentHealth = math.max(0, proposed)
		publish(model, level, currentHealth, maxHealth)
		if currentHealth > 0 then return end
		model:SetAttribute("Dead", true)
		telegraphFolder:ClearAllChildren()
		projectileFolder:ClearAllChildren()
		burst(model:GetPivot().Position)
		local dollars = (character:GetAttribute("ChompDollars") :: number?) or 0
		character:SetAttribute("ChompDollars", dollars + G.RewardDollars)
		character:SetAttribute("ChompBankedAmount", G.RewardDollars)
		character:SetAttribute("ChompBankedAt", os.clock())
		character:SetAttribute("ChompGuardianDefeatedAt", os.clock())
		model:Destroy()
		guardian = nil
		task.delay(G.ReformSeconds, spawnGuardian)
	end)
end

RunService.Heartbeat:Connect(function(dt)
	local model = guardian
	if not (model and model.Parent and model.PrimaryPart) then return end
	local players = chamberPlayers()
	local target: BasePart? = nil
	local nearest = math.huge
	for _, player in players do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local distance = (root.Position - position).Magnitude
			if distance < nearest then nearest, target = distance, root end
		end
	end
	local now = os.clock()
	local look = heading
	local flat = target and Vector3.new(target.Position.X - position.X, 0, target.Position.Z - position.Z)
		or Vector3.zero
	if flat.Magnitude > 0.1 and phase == "STALK" then
		local desired = flat.Unit
		local angle = math.acos(math.clamp(heading:Dot(desired), -1, 1))
		local maxTurn = math.rad(G.TurnDegreesPerSecond) * dt
		if angle <= maxTurn then
			heading = desired
		elseif angle > 0.001 then
			heading = heading:Lerp(desired, maxTurn / angle).Unit
		end
		look = heading
		local wanted = look * math.min(flat.Magnitude, G.MoveSpeed * dt)
		local cast = RaycastParams.new()
		cast.FilterType = Enum.RaycastFilterType.Include
		cast.FilterDescendantsInstances = if maps then { maps } else {}
		local hit = maps and Workspace:Blockcast(model.PrimaryPart.CFrame,
			Vector3.new(25, 24, 25), wanted, cast) or nil
		if not hit then
			position = chamberPoint(position + wanted)
		else
			local slide = wanted - hit.Normal * wanted:Dot(hit.Normal)
			if slide.Magnitude > 0.01 and not Workspace:Blockcast(model.PrimaryPart.CFrame,
				Vector3.new(25, 24, 25), slide, cast) then
				position = chamberPoint(position + slide)
			end
		end
	end

	if phase == "STALK" and target and now >= phaseEndsAt then
		attackCursor = attackCursor % 3 + 1
		local velocity = target.AssemblyLinearVelocity * Vector3.new(1, 0, 1)
		local predicted = chamberPoint(target.Position + velocity * G.PounceLeadSeconds)
		phaseFrom = position
		if attackCursor == 1 then
			phaseTarget = predicted
			setPhase(model, "POUNCE_TELL", G.TelegraphSeconds)
		elseif attackCursor == 2 then
			local direction = flat.Magnitude > 0.1 and flat.Unit or heading
			phaseTarget = chamberPoint(position + direction * G.DashDistanceStuds)
			setPhase(model, "DASH_TELL", G.TelegraphSeconds)
		else
			phaseTarget = predicted
			setPhase(model, "HURL_TELL", G.TelegraphSeconds)
		end
	elseif phase == "POUNCE_TELL" and now >= phaseEndsAt then
		phaseFrom = position
		setPhase(model, "POUNCE", G.PounceSeconds)
	elseif phase == "DASH_TELL" and now >= phaseEndsAt then
		phaseFrom = position
		local direction = phaseTarget - phaseFrom
		if direction.Magnitude > 0.1 then heading = Vector3.new(direction.Unit.X, 0, direction.Unit.Z) end
		setPhase(model, "DASH", G.DashSeconds)
	elseif phase == "HURL_TELL" and now >= phaseEndsAt then
		launchHurl()
		setPhase(model, "HURL", G.HurlFlightSeconds)
	elseif phase == "POUNCE" then
		local alpha = math.clamp((now - phaseStartedAt) / G.PounceSeconds, 0, 1)
		local ground = phaseFrom:Lerp(phaseTarget, alpha)
		position = ground + Vector3.new(0, math.sin(alpha * math.pi) * 30, 0)
		local direction = phaseTarget - phaseFrom
		if direction.Magnitude > 0.1 then look = direction.Unit end
		if alpha >= 1 then
			position = chamberPoint(phaseTarget)
			damageAt(position, G.PounceRadiusStuds, G.PounceDamage, "GuardianPounce")
			setPhase(model, "VULNERABLE", G.VulnerableSeconds)
		end
	elseif phase == "DASH" then
		local alpha = math.clamp((now - phaseStartedAt) / G.DashSeconds, 0, 1)
		local proposed = chamberPoint(phaseFrom:Lerp(phaseTarget, alpha))
		local step = proposed - position
		local cast = RaycastParams.new()
		cast.FilterType = Enum.RaycastFilterType.Include
		cast.FilterDescendantsInstances = if maps then { maps } else {}
		local hit = step.Magnitude > 0.01 and maps and Workspace:Blockcast(model.PrimaryPart.CFrame,
			Vector3.new(25, 24, 25), step, cast) or nil
		if hit then
			setPhase(model, "VULNERABLE", G.DashStunSeconds)
		else
			position = proposed
		end
		look = heading
		damageAt(position, G.DashWidthStuds * 0.65, G.DashDamage, "GuardianDash")
		if phase == "DASH" and alpha >= 1 then setPhase(model, "VULNERABLE", G.VulnerableSeconds) end
	elseif phase == "HURL" and now >= phaseEndsAt then
		setPhase(model, "VULNERABLE", G.VulnerableSeconds)
	elseif phase == "VULNERABLE" and now >= phaseEndsAt then
		position = chamberPoint(position)
		setPhase(model, "STALK", G.StalkSeconds)
	end

	if phase ~= "POUNCE" then position = chamberPoint(position) end
	local bob = math.sin(os.clock() * 1.8) * 1.2
	if flat.Magnitude > 0.1 and phase ~= "DASH" and phase ~= "POUNCE" then look = heading end
	local pivotPosition = position + Vector3.new(0, phase == "POUNCE" and 0 or bob, 0)
	local pivot = CFrame.lookAt(pivotPosition, pivotPosition + Vector3.new(look.X, 0, look.Z))
	model:PivotTo(pivot)
	if target then
		local localTarget = pivot:PointToObjectSpace(target.Position)
		local eyeShiftX = math.clamp(localTarget.X / 55, -1, 1) * 1.3
		local eyeShiftY = math.clamp(localTarget.Y / 40, -1, 1) * 1.1
		local leftPupil = model:FindFirstChild("PupilLeft") :: BasePart?
		local rightPupil = model:FindFirstChild("PupilRight") :: BasePart?
		if leftPupil then
			leftPupil.CFrame = pivot * CFrame.new(-6.2 + eyeShiftX, 5 + eyeShiftY, -16.2)
		end
		if rightPupil then
			rightPupil.CFrame = pivot * CFrame.new(6.2 + eyeShiftX, 5 + eyeShiftY, -16.2)
		end
	end
	local gape = phase == "VULNERABLE" and 8 or (2.2 + (math.sin(os.clock() * 5) + 1) * 1.6)
	local upper = model:FindFirstChild("UpperMaw") :: BasePart?
	local lower = model:FindFirstChild("LowerMaw") :: BasePart?
	if upper then upper.CFrame = pivot * CFrame.new(0, -2 + gape / 2, -14) * CFrame.Angles(-0.12, 0, 0) end
	if lower then lower.CFrame = pivot * CFrame.new(0, -8 - gape / 2, -14) * CFrame.Angles(0.12, 0, 0) end
	publish(model, level, currentHealth, maxHealth)
end)

spawnGuardian()
print("[GuardianService] infinite chamber guardian live")
