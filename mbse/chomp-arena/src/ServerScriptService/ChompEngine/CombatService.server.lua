--!strict
-- Server-owned directional contact combat.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("ChompConfig"))
local Impact = require(ReplicatedStorage:WaitForChild("ChompLogic"):WaitForChild("Impact"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))
local CombatState = require(script.Parent:WaitForChild("CombatState"))

local C = Config.Combat

type Driver = {
	player: Player,
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	position: Vector3,
	facing: Vector3,
	velocity: Vector3,
	mouthArc: number,
}

local previous: { [Player]: Vector3 } = {}
local touching: { [string]: boolean } = {}

local function pairKey(a: Player, b: Player): string
	local low = math.min(a.UserId, b.UserId)
	local high = math.max(a.UserId, b.UserId)
	return tostring(low) .. ":" .. tostring(high)
end

local function chassisDefinition(character: Model)
	local id = character:GetAttribute("ChompChassis")
	return Config.Chassis[typeof(id) == "string" and id or Config.StartingChassis]
end

local function driver(player: Player, dt: number): Driver?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (character and humanoid and root) or humanoid.Health <= 0 then
		previous[player] = nil
		return nil
	end
	if character:GetAttribute("ChompSessionState") ~= Config.Launch.ActiveState
		or character:GetAttribute("ChompSafe") == true
		or character:GetAttribute("ChompInGuardianArena") == true
		or os.clock() < ((character:GetAttribute("ChompProtectedUntil") :: number?) or 0) then
		previous[player] = nil
		return nil
	end

	local vehicle = character:FindFirstChild("Vehicle")
	local primary = vehicle and vehicle:IsA("Model") and vehicle.PrimaryPart
	if not primary then return nil end
	local last = previous[player]
	local observed = last and ((root.Position - last) / math.max(dt, 1 / 240)) or Vector3.zero
	previous[player] = root.Position
	local velocity = root.AssemblyLinearVelocity
	if velocity.Magnitude < 0.5 and observed.Magnitude > velocity.Magnitude then velocity = observed end
	local chassis = chassisDefinition(character)
	return {
		player = player,
		character = character,
		humanoid = humanoid,
		root = root,
		position = root.Position,
		facing = primary.CFrame.LookVector,
		velocity = velocity,
		mouthArc = chassis and chassis.MouthArcDegrees or 90,
	}
end

local function announce(character: Model, kind: string, role: string, barLoss: number, carryLoss: number,
	otherPosition: Vector3)
	character:SetAttribute("ChompCombatKind", kind)
	character:SetAttribute("ChompCombatRole", role)
	character:SetAttribute("ChompCombatBarLoss", math.floor(barLoss + 0.5))
	character:SetAttribute("ChompCombatCarryLoss", math.floor(carryLoss + 0.5))
	character:SetAttribute("ChompHitFromX", otherPosition.X)
	character:SetAttribute("ChompHitFromZ", otherPosition.Z)
	character:SetAttribute("ChompCombatAt", os.clock())
end

local function spend(character: Model, barLoss: number, carryLoss: number, reason: string)
	if barLoss > 0 then EconomyService.applyBattleBarDelta(character, -barLoss, reason) end
	if carryLoss > 0 then EconomyService.applyCarryDelta(character, -carryLoss, reason) end
	character:SetAttribute("ChompPelletMultiplier", 1)
end

local function knock(driverInfo: Driver, awayFrom: Vector3, speed: number)
	local direction = (driverInfo.position - awayFrom) * Vector3.new(1, 0, 1)
	if direction.Magnitude < 0.01 then direction = -driverInfo.facing end
	direction = direction.Unit
	driverInfo.character:SetAttribute("ChompStunnedUntil", os.clock() + C.ImpactStunSeconds)
	driverInfo.root:ApplyImpulse(direction * driverInfo.root.AssemblyMass * speed)
end

local function chomp(victim: Driver, attacker: Driver, attackerBarLoss: number)
	local gate = CombatState.beginHit(victim.character, "PlayerChomp")
	if gate == "Blocked" then return end
	if attackerBarLoss > 0 then
		EconomyService.applyBattleBarDelta(attacker.character, -attackerBarLoss, "chomp")
	end
	if gate == "Shielded" then
		announce(attacker.character, "BITE", "ATTACKER", attackerBarLoss, 0, victim.position)
		return
	end
	local result = Impact.resolveChomp(EconomyService.carry(victim.character))
	spend(victim.character, 0, result.defenderCarryLoss, "chomp")
	EconomyService.scatter(victim.position, result.scatterAmount, "chomp")
	announce(attacker.character, "CHOMP", "ATTACKER", attackerBarLoss, 0, victim.position)
	announce(victim.character, "CHOMPED", "DEFENDER", 0, result.defenderCarryLoss, attacker.position)
	victim.character:SetAttribute("ChompChompedAt", os.clock())
	victim.humanoid.Health = 0
end

local function resolveFlank(attacker: Driver, defender: Driver)
	local attackerBar = EconomyService.battleBar(attacker.character)
	if attackerBar <= 0 then return end
	local powerA = (attacker.character:GetAttribute("ChompPower") :: number?) or 0
	local powerB = (defender.character:GetAttribute("ChompPower") :: number?) or 0
	local powerGap = powerA - powerB
	if EconomyService.battleBar(defender.character) <= 0 then
		if powerGap >= C.SmallFryPowerGap then
			local gate = CombatState.beginHit(defender.character, "PlayerBite")
			if gate == "Blocked" then return end
			local cost = math.min(attackerBar, EconomyService.capacity(attacker.character) * C.BiteBarCost)
			spend(attacker.character, cost, 0, "small-fry")
			if gate == "Apply" then knock(defender, attacker.position, C.FlankKnockbackSpeed) end
			announce(attacker.character, "NO REWARD", "ATTACKER", cost, 0, defender.position)
			announce(defender.character, gate == "Shielded" and "SHIELDED" or "PROTECTED", "DEFENDER",
				0, 0, attacker.position)
			return
		end
		chomp(defender, attacker,
			math.min(attackerBar, EconomyService.capacity(attacker.character) * C.BiteBarCost))
		return
	end
	local gate = CombatState.beginHit(defender.character, "PlayerBite")
	if gate == "Blocked" then return end
	local result = Impact.resolveFlank(attackerBar, EconomyService.battleBar(defender.character),
		EconomyService.carry(defender.character), powerGap,
		EconomyService.capacity(attacker.character))
	spend(attacker.character, result.attackerBarLoss, 0, "bite")
	if gate == "Apply" then
		spend(defender.character, result.defenderBarLoss, result.defenderCarryLoss, "ambushed")
		EconomyService.scatter(defender.position, result.scatterAmount, "ambush")
		knock(defender, attacker.position, C.FlankKnockbackSpeed)
	end
	announce(attacker.character, "BITE", "ATTACKER", result.attackerBarLoss, 0, defender.position)
	announce(defender.character, gate == "Shielded" and "SHIELDED" or "AMBUSHED", "DEFENDER",
		gate == "Apply" and result.defenderBarLoss or 0,
		gate == "Apply" and result.defenderCarryLoss or 0, attacker.position)
end

local function resolveHeadOn(a: Driver, b: Driver)
	local barA = EconomyService.battleBar(a.character)
	local barB = EconomyService.battleBar(b.character)
	if barA <= 0 then
		chomp(a, b, math.min(barB, EconomyService.capacity(b.character) * C.BiteBarCost))
	end
	if barB <= 0 then
		chomp(b, a, math.min(barA, EconomyService.capacity(a.character) * C.BiteBarCost))
	end
	if barA <= 0 or barB <= 0 then return end
	if not CombatState.canHit(a.character) or not CombatState.canHit(b.character) then return end
	local gateA = CombatState.beginHit(a.character, "HeadOn")
	local gateB = CombatState.beginHit(b.character, "HeadOn")
	if gateA == "Blocked" or gateB == "Blocked" then return end
	local result = Impact.resolveHeadOn(barA, barB, EconomyService.carry(a.character), EconomyService.carry(b.character))
	if gateA == "Apply" then spend(a.character, result.attackerBarLoss, result.attackerCarryLoss, "head-on") end
	if gateB == "Apply" then spend(b.character, result.defenderBarLoss, result.defenderCarryLoss, "head-on") end
	local scatterAmount = 0
	if gateA == "Apply" then scatterAmount += result.attackerCarryLoss end
	if gateB == "Apply" then scatterAmount += result.defenderCarryLoss end
	EconomyService.scatter((a.position + b.position) * 0.5, scatterAmount, "head-on")
	knock(a, b.position, C.BounceSpeed)
	knock(b, a.position, C.BounceSpeed)
	local kind = result.kind == "Clang" and "CLANG" or "HEAD-ON"
	announce(a.character, gateA == "Shielded" and "SHIELDED" or kind, "CONTEST",
		gateA == "Apply" and result.attackerBarLoss or 0,
		gateA == "Apply" and result.attackerCarryLoss or 0, b.position)
	announce(b.character, gateB == "Shielded" and "SHIELDED" or kind, "CONTEST",
		gateB == "Apply" and result.defenderBarLoss or 0,
		gateB == "Apply" and result.defenderCarryLoss or 0, a.position)
end

local function resolve(a: Driver, b: Driver)
	local classification = Impact.classifyContact({
		positionA = a.position,
		positionB = b.position,
		facingA = a.facing,
		facingB = b.facing,
		velocityA = a.velocity,
		velocityB = b.velocity,
		mouthArcA = a.mouthArc,
		mouthArcB = b.mouthArc,
		aboveThreshold = C.AboveAttackHeightStuds,
		minimumAttackSpeed = C.MinimumAttackSpeed,
	})
	if classification.kind == "HeadOn" then
		resolveHeadOn(a, b)
	elseif classification.kind == "Flank" and classification.attacker == "A" then
		resolveFlank(a, b)
	elseif classification.kind == "Flank" and classification.attacker == "B" then
		resolveFlank(b, a)
	end
end

local function onCharacter(player: Player, character: Model)
	previous[player] = nil
	EconomyService.initialize(character)
	CombatState.initialize(character)
	character:SetAttribute("ChompStunnedUntil", 0)
end

local function bindPlayer(player: Player)
	player.CharacterAdded:Connect(function(character) onCharacter(player, character) end)
	if player.Character then onCharacter(player, player.Character) end
end

for _, player in Players:GetPlayers() do bindPlayer(player) end
Players.PlayerAdded:Connect(bindPlayer)

Players.PlayerRemoving:Connect(function(player)
	previous[player] = nil
	local marker = tostring(player.UserId)
	for key in touching do
		if string.find(key, marker, 1, true) then touching[key] = nil end
	end
end)

RunService.Heartbeat:Connect(function(dt)
	local drivers: { Driver } = {}
	for _, player in Players:GetPlayers() do
		local info = driver(player, dt)
		if info then table.insert(drivers, info) end
	end
	local seenPairs: { [string]: boolean } = {}
	for i = 1, #drivers - 1 do
		for j = i + 1, #drivers do
			local a, b = drivers[i], drivers[j]
			local key = pairKey(a.player, b.player)
			seenPairs[key] = true
			local distance = (a.position - b.position).Magnitude
			if distance <= C.ContactRadiusStuds then
				if not touching[key] then
					touching[key] = true
					resolve(a, b)
				end
			elseif distance >= C.ContactReleaseRadiusStuds then
				touching[key] = nil
			end
		end
	end
	for key in touching do
		if not seenPairs[key] then touching[key] = nil end
	end
end)

print("[CombatService] directional player contact live")
