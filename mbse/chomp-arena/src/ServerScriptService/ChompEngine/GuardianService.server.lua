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
		Color3.fromRGB(5, 5, 8), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	piece(model, "Crown", Vector3.new(18, 7, 12), CFrame.new(0, 13, 1),
		Color3.fromRGB(12, 12, 16), Enum.Material.Slate)
	for _, side in { -1, 1 } do
		piece(model, "Eye", Vector3.new(6.5, 7.5, 2.2), CFrame.new(side * 6.2, 5, -13.5),
			P.Gold, Enum.Material.Neon, Enum.PartType.Ball)
		piece(model, "Brow", Vector3.new(8, 2.5, 2.5),
			CFrame.new(side * 6, 9, -13) * CFrame.Angles(0, 0, side * -0.25),
			Color3.fromRGB(3, 3, 5), Enum.Material.Slate)
	end
	piece(model, "MouthGlow", Vector3.new(18, 7, 2), CFrame.new(0, -5, -14),
		P.Danger, Enum.Material.Neon)
	piece(model, "UpperMaw", Vector3.new(22, 4, 4), CFrame.new(0, -2, -14),
		Color3.fromRGB(4, 4, 6), Enum.Material.Slate)
	piece(model, "LowerMaw", Vector3.new(22, 4, 4), CFrame.new(0, -8, -14),
		Color3.fromRGB(4, 4, 6), Enum.Material.Slate)
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
local contactAt: { [Player]: number } = {}

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
	local look = heading
	if target then
		local flat = Vector3.new(target.Position.X - position.X, 0, target.Position.Z - position.Z)
		if flat.Magnitude > 0.1 then
			local desired = flat.Unit
			local angle = math.acos(math.clamp(heading:Dot(desired), -1, 1))
			local maxTurn = math.rad(G.TurnDegreesPerSecond) * dt
			if angle <= maxTurn then
				heading = desired
			elseif angle > 0.001 then
				-- A capped heading change makes the guardian commit to an attack
				-- line. Sharp player turns now produce an escape window instead of
				-- being matched by an instantaneous correction.
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
				position += wanted
			else
				local slide = wanted - hit.Normal * wanted:Dot(hit.Normal)
				if slide.Magnitude > 0.01 and not Workspace:Blockcast(model.PrimaryPart.CFrame,
					Vector3.new(25, 24, 25), slide, cast) then
					position += slide
				end
			end
		end
		local player = Players:GetPlayerFromCharacter(target.Parent)
		if player and nearest < G.ContactRadiusStuds
			and os.clock() - (contactAt[player] or 0) > G.ContactCooldownSeconds then
			local humanoid = target.Parent and target.Parent:FindFirstChildOfClass("Humanoid")
			local gate = target.Parent and CombatState.beginHit(target.Parent, "Guardian") or "Blocked"
			if humanoid and gate == "Apply" then humanoid:TakeDamage(G.ContactDamage) end
			if gate ~= "Blocked" then contactAt[player] = os.clock() end
		end
	end
	local bob = math.sin(os.clock() * 1.8) * 1.2
	local pivot = CFrame.lookAt(position + Vector3.new(0, bob, 0), position + Vector3.new(look.X, bob, look.Z))
	model:PivotTo(pivot)
	local gape = 2.2 + (math.sin(os.clock() * 5) + 1) * 1.6
	local upper = model:FindFirstChild("UpperMaw") :: BasePart?
	local lower = model:FindFirstChild("LowerMaw") :: BasePart?
	if upper then upper.CFrame = pivot * CFrame.new(0, -2 + gape / 2, -14) * CFrame.Angles(-0.12, 0, 0) end
	if lower then lower.CFrame = pivot * CFrame.new(0, -8 - gape / 2, -14) * CFrame.Angles(0.12, 0, 0) end
	publish(model, level, currentHealth, maxHealth)
end)

spawnGuardian()
print("[GuardianService] infinite chamber guardian live")
