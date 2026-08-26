--!strict
--[[
	ItemService — CHAIN-COMBAT, CHOMP-SYS-058 to -061

	Four items lie around the map. You carry one. Picking anything up replaces
	what you had, so the decision is always "is this better than what I am
	holding" and never inventory management — which is the right shape for a
	seven-year-old and, incidentally, for anyone driving at speed.

	  JetPack     one hop, enough to clear a wall
	  Cannon      three shots, straight along the heading
	  HomingBomb  one shot, slower, steers toward the nearest target
	  Shield      absorbs the next hit, or expires

	THE SERVER OWNS EVERYTHING. The client sends UseItem with no arguments: it
	is the intent "use whatever I am holding", nothing more. It does not say
	which item, how many charges remain, where the shot goes or what it hit. All
	of that is here, because a remote that carried any of it would be a remote
	worth forging (CHOMP-SYS-034, and the rule in service_contracts.md).

	The heading a shot travels along is read from the character's attributes,
	which the server itself wrote — not from anything the client said.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage:WaitForChild("ChompConfig"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))

local ITEMS = Config.Items
local DEFS = ITEMS.Definitions

local P = Config.Palette

local COLOURS = {
	JetPack = P.NeonA,
	Cannon = P.Gold,
	HomingBomb = P.NeonB,
	Shield = Color3.fromRGB(126, 217, 87),
}

-- Each item is BUILT to look like what it does (D-CHOMP-047). Colour alone is
-- not a capability: a child at speed reads silhouette long before hue, and
-- three glowing balls in three colours is a memory test rather than a game.
local function bit(model: Model, name: string, size: Vector3, offset: CFrame,
		colour: Color3, material: Enum.Material, shape: Enum.PartType?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = colour
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	if shape then p.Shape = shape end
	p.CFrame = offset
	p.Parent = model
	return p
end

local function buildItemModel(id: string): Model
	local model = Instance.new("Model")
	model.Name = "Item_" .. id
	local c = COLOURS[id]

	if id == "JetPack" then
		-- Two thrusters and a pack. It points DOWN, because that is the way the
		-- thrust goes and the way you are about to go is up.
		bit(model, "Pack", Vector3.new(3, 3.4, 1.6), CFrame.new(0, 0.4, 0), c, Enum.Material.Metal)
		for _, side in { -1, 1 } do
			bit(model, "Thruster", Vector3.new(1.1, 2.6, 1.1),
				CFrame.new(side * 1.9, -0.2, 0) * CFrame.Angles(0, 0, math.rad(90)),
				c, Enum.Material.Neon, Enum.PartType.Cylinder)
			bit(model, "Flame", Vector3.new(0.9, 1.4, 0.9),
				CFrame.new(side * 1.9, -2.1, 0), P.Gold, Enum.Material.Neon, Enum.PartType.Ball)
		end

	elseif id == "Cannon" then
		-- A barrel on a mount. Long, straight and obviously pointing somewhere.
		bit(model, "Mount", Vector3.new(2.6, 1.4, 2.6), CFrame.new(0, -1.2, 0),
			P.BrickDark, Enum.Material.Metal)
		bit(model, "Barrel", Vector3.new(1.8, 5.6, 1.8),
			CFrame.new(0, 0.6, -1.2) * CFrame.Angles(math.rad(90), 0, 0),
			c, Enum.Material.Metal, Enum.PartType.Cylinder)
		bit(model, "Muzzle", Vector3.new(2.2, 0.8, 2.2),
			CFrame.new(0, 0.6, -3.9) * CFrame.Angles(math.rad(90), 0, 0),
			P.Danger, Enum.Material.Neon, Enum.PartType.Cylinder)

	elseif id == "HomingBomb" then
		-- A finned bomb. Fins say it steers; a plain ball would not.
		bit(model, "Body", Vector3.new(3.2, 3.2, 3.2), CFrame.new(0, 0, 0),
			c, Enum.Material.Metal, Enum.PartType.Ball)
		bit(model, "Eye", Vector3.new(1.2, 1.2, 1.2), CFrame.new(0, 0, -1.5),
			P.NeonA, Enum.Material.Neon, Enum.PartType.Ball)
		for i = 0, 3 do
			local a = (math.pi / 2) * i
			bit(model, "Fin", Vector3.new(0.35, 1.8, 2.2),
				CFrame.new(math.cos(a) * 1.5, 0, math.sin(a) * 1.5) * CFrame.Angles(0, -a, 0),
				P.BrickDark, Enum.Material.Metal)
		end

	else -- Shield
		-- A ring around a core: something that surrounds you rather than fires.
		bit(model, "Core", Vector3.new(1.8, 1.8, 1.8), CFrame.new(0, 0, 0),
			c, Enum.Material.Neon, Enum.PartType.Ball)
		local segments = 12
		for i = 0, segments - 1 do
			local a = (math.pi * 2) * (i / segments)
			bit(model, "Ring", Vector3.new(0.5, 0.5, 1.5),
				CFrame.new(math.cos(a) * 2.6, 0, math.sin(a) * 2.6) * CFrame.Angles(0, -a, 0),
				c, Enum.Material.Neon)
		end
	end

	local primary = model:FindFirstChildWhichIsA("BasePart")
	model.PrimaryPart = primary
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then CollectionService:AddTag(d, "Chomp_Decor") end
	end
	return model
end

type Held = { id: string, charges: number }
local held: { [Player]: Held } = {}
local shieldUntil: { [Player]: number } = {}

local limiter = Remotes.makeLimiter(ITEMS.UseRateLimit)

-- ── Pads ────────────────────────────────────────────────────────────────

local padsFolder = Instance.new("Folder")
padsFolder.Name = "ItemPads"
padsFolder.Parent = Workspace

local function makePad(id: string, position: Vector3)
	local model = buildItemModel(id)
	model:SetAttribute("ItemId", id)
	model:SetAttribute("HomeY", position.Y)
	model:PivotTo(CFrame.new(position))
	model.Parent = padsFolder
	return model
end

-- Spin and bob. A static prop reads as scenery; a moving one reads as a thing
-- you are meant to drive into.
local function animatePads()
	local t = 0
	RunService.Heartbeat:Connect(function(dt)
		t += dt
		for _, model in padsFolder:GetChildren() do
			if model:IsA("Model") and model.PrimaryPart and model.PrimaryPart.Transparency < 1 then
				local homeY = model:GetAttribute("HomeY")
				if typeof(homeY) == "number" then
					local pivot = model:GetPivot()
					model:PivotTo(CFrame.new(pivot.Position.X, homeY + math.sin(t * 2) * 1.2, pivot.Position.Z)
						* CFrame.Angles(0, t * 1.4, 0))
				end
			end
		end
	end)
end

-- Laid out by ring, with the better items further in. The centre arena is the
-- exposed place with no walls to hide behind, so what is found there has to be
-- worth standing in the open for (D-CHOMP-046).
local function setCollected(model: Model, collected: boolean)
	model:SetAttribute("Collected", collected)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Transparency = collected and 1 or 0
		end
	end
end

local function layOutPads(): number
	local L = Config.Level1
	if not L then return 0 end

	local radii = {}
	local r = L.CentreRadius
	while r <= L.OuterRadius - L.RingSpacing do
		table.insert(radii, r)
		r += L.RingSpacing
	end
	if #radii == 0 then return 0 end

	local mid = function(i: number) return radii[math.clamp(i, 1, #radii)] + L.RingSpacing / 2 end
	local plan = {
		{ id = "Shield", radius = mid(#radii), count = 6, y = 4 },
		{ id = "Shield", radius = mid(#radii - 1), count = 4, y = 4 },
		{ id = "JetPack", radius = mid(#radii - 2), count = 5, y = 4 },
		{ id = "Cannon", radius = mid(#radii - 3), count = 5, y = 4 },
		{ id = "Cannon", radius = mid(2), count = 4, y = 4 },
		{ id = "HomingBomb", radius = L.CentreRadius * 0.55, count = 3, y = 4 },
	}

	local made = 0
	for _, entry in plan do
		for i = 0, entry.count - 1 do
			local a = (math.pi * 2) * (i / entry.count) + (made * 0.41)
			makePad(entry.id, Vector3.new(
				math.cos(a) * entry.radius, entry.y, math.sin(a) * entry.radius))
			made += 1
		end
	end
	return made
end

-- ── Carrying ────────────────────────────────────────────────────────────

local function publish(player: Player)
	-- Attributes rather than a remote: the HUD reads them, and a value the
	-- client only ever READS cannot be forged into the server (CHOMP-SYS-030).
	local character = player.Character
	if not character then return end
	local h = held[player]
	character:SetAttribute("ChompItem", h and h.id or "")
	character:SetAttribute("ChompItemCharges", h and h.charges or 0)
end

-- What you are holding should be visible ON the kart, not only in the HUD
-- (D-CHOMP-051). A cannon that appears bolted to the roof tells everyone in the
-- arena what you can do to them, which is most of what makes carrying one feel
-- like something.
local function unmount(character: Model)
	local vehicle = character:FindFirstChild("Vehicle")
	local existing = vehicle and vehicle:FindFirstChild("MountedItem")
	if existing then existing:Destroy() end
end

local function mount(character: Model, id: string)
	if not (Config.Vehicle and Config.Vehicle.MountHeldItem) then return end
	unmount(character)
	local vehicle = character:FindFirstChild("Vehicle")
	local point = vehicle and vehicle:FindFirstChild("ItemMount") :: BasePart?
	if not (vehicle and point) then return end

	local model = buildItemModel(id)
	model.Name = "MountedItem"
	-- Smaller than the pickup, and facing forward: a mounted gun points where
	-- the kart points, which is also where it fires.
	local scale = 0.85
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Size = d.Size * scale
			d.Massless = true
			d.Anchored = false
		end
	end
	model:PivotTo(point.CFrame)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = point
			weld.Part1 = d
			weld.Parent = d
		end
	end
	model.Parent = vehicle
end

local function give(player: Player, id: string)
	local def = DEFS[id]
	if not def then return end
	held[player] = { id = id, charges = def.charges }
	publish(player)
	if player.Character then mount(player.Character, id) end
end

local function clear(player: Player)
	held[player] = nil
	publish(player)
	if player.Character then unmount(player.Character) end
end

-- ── Using ───────────────────────────────────────────────────────────────

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- The direction a shot travels. Taken from the character's own transform, which
-- the server can see, rather than from anything the client sent.
local function facing(root: BasePart): Vector3
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	return flat.Magnitude > 0.001 and flat.Unit or Vector3.new(0, 0, -1)
end

local function nearestTarget(player: Player, from: Vector3, maxRange: number): BasePart?
	local best, bestDistance = nil, maxRange
	for _, other in Players:GetPlayers() do
		if other ~= player then
			local root = rootOf(other)
			if root then
				local d = (root.Position - from).Magnitude
				if d < bestDistance then best, bestDistance = root, d end
			end
		end
	end
	return best
end

local function fireProjectile(player: Player, id: string)
	local def = DEFS[id]
	local root = rootOf(player)
	if not root then return end

	local shot = Instance.new("Part")
	shot.Name = "ChompShot_" .. id
	shot.Shape = Enum.PartType.Ball
	shot.Size = Vector3.new(3, 3, 3)
	shot.Color = COLOURS[id]
	shot.Material = Enum.Material.Neon
	shot.CanCollide = false
	shot.Anchored = true
	shot.CFrame = CFrame.new(root.Position + facing(root) * 8)
	CollectionService:AddTag(shot, "Chomp_Decor")
	shot.Parent = Workspace
	Debris:AddItem(shot, 6)

	-- A locked cannon fires at the LOCK, not at the nose. That is the whole
	-- point of locking, and the direction is computed here from positions the
	-- server holds (D-CHOMP-054).
	local direction = facing(root)
	if id == "Cannon" then
		local target = lockTarget[player]
		local character = player.Character
		if target and target.Parent and character
			and character:GetAttribute("ChompLockState") == "locked" then
			local to = target:GetPivot().Position - root.Position
			local flat = Vector3.new(to.X, 0, to.Z)
			if flat.Magnitude > 0.001 then direction = flat.Unit end
		end
	end
	local travelled = 0
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function(dt)
		if not shot.Parent then connection:Disconnect() return end

		if id == "HomingBomb" then
			local target = nearestTarget(player, shot.Position, def.rangeStuds)
			if target then
				-- Steer, do not snap. A bomb that turns instantly is not a
				-- weapon, it is a guaranteed hit, and nothing you can dodge is
				-- worth picking up to avoid.
				local want = (target.Position - shot.Position)
				want = Vector3.new(want.X, 0, want.Z)
				if want.Magnitude > 0.001 then
					local maxTurn = math.rad(def.turnRateDegrees) * dt
					local current = direction
					local angle = math.acos(math.clamp(current:Dot(want.Unit), -1, 1))
					local t = angle > 0 and math.min(maxTurn / angle, 1) or 1
					direction = current:Lerp(want.Unit, t).Unit
				end
			end
		end

		local step = def.projectileSpeed * dt
		travelled += step
		shot.CFrame = CFrame.new(shot.Position + direction * step)

		if travelled >= def.rangeStuds then
			shot:Destroy()
			connection:Disconnect()
			return
		end

		-- Ghosts are what these weapons are actually FOR. A ghost takes damage
		-- from the cannon and dies outright to the bomb, which is the whole
		-- reason the bomb is a single charge (D-CHOMP-051).
		for _, ghost in CollectionService:GetTagged("Chomp_Ghost") do
			if ghost:IsA("Model") and ghost:GetAttribute("Dead") ~= true then
				local pivot = ghost:GetPivot()
				if (pivot.Position - shot.Position).Magnitude < 11 then
					local hp = ((ghost:GetAttribute("Health") :: number?) or 1) - 1
					ghost:SetAttribute("KilledBy", player.UserId)
					ghost:SetAttribute("Health", hp)
					ghost:SetAttribute("HitAt", os.clock())
					shot:Destroy()
					connection:Disconnect()
					return
				end
			end
		end

		-- Hits are decided HERE, from positions the server holds. A client
		-- never claims a hit (CHOMP-TC-042 covers the forged-hit attack).
		for _, other in Players:GetPlayers() do
			if other ~= player then
				local otherRoot = rootOf(other)
				if otherRoot and (otherRoot.Position - shot.Position).Magnitude < 7 then
					if os.clock() < (shieldUntil[other] or 0) then
						shieldUntil[other] = 0   -- the shield spends itself absorbing this
					else
						local humanoid = other.Character
							and other.Character:FindFirstChildOfClass("Humanoid")
						if humanoid then
							humanoid:TakeDamage(20)
						end
					end
					shot:Destroy()
					connection:Disconnect()
					return
				end
			end
		end
	end)
end

-- ── Auto-lock (D-CHOMP-054) ─────────────────────────────────────────────
-- The turret finds the nearest ghost in front, tracks it, and locks after
-- holding it. Aiming while steering is not a skill worth demanding of a
-- seven-year-old; deciding WHEN to fire is.
--
-- The lock lives on the SERVER. The client draws a reticle from it and cannot
-- create one: a client-declared target would be a client-declared hit.
local lockTarget: { [Player]: Model? } = {}
local lockSince: { [Player]: number } = {}

local function ghostsAlive(): { Model }
	local out: { Model } = {}
	for _, g in CollectionService:GetTagged("Chomp_Ghost") do
		if g:IsA("Model") and g:GetAttribute("Dead") ~= true then
			table.insert(out, g)
		end
	end
	return out
end

local function updateLock(player: Player, dt: number)
	local h = held[player]
	local root = rootOf(player)
	local character = player.Character
	if not (character and root and h and h.id == "Cannon") then
		lockTarget[player] = nil
		lockSince[player] = 0
		if character then
			character:SetAttribute("ChompLockState", "none")
			character:SetAttribute("ChompLockTarget", "")
		end
		return
	end

	local def = DEFS.Cannon
	local forward = facing(root)
	local best, bestDistance = nil, def.lockRangeStuds
	for _, ghost in ghostsAlive() do
		local to = ghost:GetPivot().Position - root.Position
		local flat = Vector3.new(to.X, 0, to.Z)
		local distance = flat.Magnitude
		if distance < bestDistance and distance > 1 then
			local angle = math.deg(math.acos(math.clamp(forward:Dot(flat.Unit), -1, 1)))
			if angle <= def.lockAngleDegrees then
				best, bestDistance = ghost, distance
			end
		end
	end

	if best ~= lockTarget[player] then
		lockTarget[player] = best
		lockSince[player] = best and os.clock() or 0
	end

	local state = "none"
	if best then
		state = (os.clock() - (lockSince[player] or 0)) >= def.lockSeconds and "locked" or "tracking"
	end
	character:SetAttribute("ChompLockState", state)
	character:SetAttribute("ChompLockTarget", best and best.Name or "")

	-- Swing the barrel. Turning at a rate rather than snapping is what makes a
	-- lock feel earned instead of automatic.
	local vehicle = character:FindFirstChild("Vehicle")
	local primary = vehicle and vehicle:FindFirstChild("Chassis") :: BasePart?
	local motor = primary and primary:FindFirstChild("TurretMotor") :: Motor6D?
	if motor then
		local wanted = 0
		if best then
			local to = best:GetPivot().Position - root.Position
			local flat = Vector3.new(to.X, 0, to.Z)
			if flat.Magnitude > 0.001 then
				local worldYaw = math.atan2(-flat.Unit.X, -flat.Unit.Z)
				local kartYaw = math.atan2(-forward.X, -forward.Z)
				wanted = (worldYaw - kartYaw + math.pi) % (math.pi * 2) - math.pi
			end
		end
		local _, current = motor.Transform:ToOrientation()
		local diff = (wanted - current + math.pi) % (math.pi * 2) - math.pi
		local step = math.rad(def.turretTurnDegrees) * dt
		local applied = math.abs(diff) <= step and wanted or current + (diff > 0 and step or -step)
		motor.Transform = CFrame.Angles(0, applied, 0)
	end
end

RunService.Heartbeat:Connect(function(dt)
	for _, player in Players:GetPlayers() do
		updateLock(player, dt)
	end
end)

-- ── The dropped bomb ────────────────────────────────────────────────────
local deployed: { [Player]: BasePart? } = {}

local function detonate(player: Player, bomb: BasePart)
	deployed[player] = nil
	local centre = bomb.Position
	local def = DEFS.HomingBomb

	local blast = Instance.new("Part")
	blast.Shape = Enum.PartType.Ball
	blast.Size = Vector3.new(def.blastRadiusStuds * 2, def.blastRadiusStuds * 2, def.blastRadiusStuds * 2)
	blast.Position = centre
	blast.Anchored = true
	blast.CanCollide = false
	blast.CanQuery = false
	blast.Material = Enum.Material.Neon
	blast.Color = P.NeonB
	blast.Transparency = 0.55
	CollectionService:AddTag(blast, "Chomp_Decor")
	blast.Parent = Workspace
	Debris:AddItem(blast, 0.35)
	bomb:Destroy()

	for _, ghost in ghostsAlive() do
		if (ghost:GetPivot().Position - centre).Magnitude < def.blastRadiusStuds then
			ghost:SetAttribute("KilledBy", player.UserId)
			ghost:SetAttribute("Health", 0)
		end
	end
end

local function dropBomb(player: Player)
	local root = rootOf(player)
	if not root then return end
	local def = DEFS.HomingBomb

	local bomb = Instance.new("Part")
	bomb.Name = "ChompBomb"
	bomb.Shape = Enum.PartType.Ball
	bomb.Size = Vector3.new(4.5, 4.5, 4.5)
	bomb.Position = root.Position - facing(root) * def.dropBehindStuds
	bomb.Anchored = true
	bomb.CanCollide = false
	bomb.CanQuery = false
	bomb.Material = Enum.Material.Neon
	bomb.Color = P.NeonB
	bomb:SetAttribute("ArmedAt", os.clock() + def.armSeconds)
	CollectionService:AddTag(bomb, "Chomp_Decor")
	bomb.Parent = Workspace
	deployed[player] = bomb

	-- It expires on its own, so a forgotten bomb does not sit in the map
	-- forever holding a charge hostage.
	task.delay(def.lifetimeSeconds, function()
		if deployed[player] == bomb then
			deployed[player] = nil
			if bomb.Parent then bomb:Destroy() end
			local h = held[player]
			if h and h.id == "HomingBomb" then clear(player) end
		end
	end)
end

local function useHeld(player: Player)
	if not limiter(player) then return end        -- flood protection, server side

	local h = held[player]
	if not h then return end                      -- firing with nothing is a no-op
	local root = rootOf(player)
	if not root then return end
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	local def = DEFS[h.id]
	if not def then clear(player) return end

	if h.id == "HomingBomb" then
		-- Two taps: drop, then detonate. The first costs nothing until the
		-- second, so a bomb you never set off is a bomb you still have.
		local bomb = deployed[player]
		if bomb and bomb.Parent then
			if os.clock() < ((bomb:GetAttribute("ArmedAt") :: number?) or 0) then
				return   -- still arming; refuse rather than blow yourself up
			end
			detonate(player, bomb)
			h.charges -= 1
			if h.charges <= 0 then clear(player) else publish(player) end
		else
			dropBomb(player)
		end
		return
	end

	if h.id == "JetPack" then
		-- A hop. The character is the thing the engine moves, so this is an
		-- impulse on it rather than a new mover (D-CHOMP-025).
		local body = Instance.new("BodyVelocity")
		body.MaxForce = Vector3.new(0, math.huge, 0)
		body.Velocity = Vector3.new(0, def.impulseStuds, 0)
		body.Parent = root
		Debris:AddItem(body, 0.18)
	elseif h.id == "Shield" then
		shieldUntil[player] = os.clock() + def.durationSeconds
		if player.Character then
			player.Character:SetAttribute("ChompShieldUntil", shieldUntil[player])
		end
	else
		fireProjectile(player, h.id)
	end

	h.charges -= 1
	if h.charges <= 0 then
		clear(player)
	else
		publish(player)
	end
end

-- ── Collection ──────────────────────────────────────────────────────────

local function collectionLoop()
	while true do
		task.wait(0.12)
		for _, player in Players:GetPlayers() do
			local root = rootOf(player)
			if root then
				for _, model in padsFolder:GetChildren() do
					if model:IsA("Model") and model:GetAttribute("Collected") ~= true then
						local pivot = model:GetPivot()
						if (pivot.Position - root.Position).Magnitude < ITEMS.PickupRadiusStuds then
							local id = model:GetAttribute("ItemId")
							if typeof(id) == "string" then
								give(player, id)
								-- hidden and restored rather than destroyed and
								-- rebuilt, so the map restocks without anything
								-- having to remember where a pad was
								setCollected(model, true)
								task.delay(ITEMS.RespawnSeconds, function()
									if model.Parent then setCollected(model, false) end
								end)
							end
						end
					end
				end
			end
		end
	end
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function()
		clear(player)
		shieldUntil[player] = 0
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	held[player] = nil
	shieldUntil[player] = nil
end)

Remotes.UseItem.OnServerEvent:Connect(function(player: Player)
	-- No arguments. Anything a client sent here would be a number worth forging.
	useHeld(player)
end)

local count = layOutPads()
animatePads()
task.spawn(collectionLoop)

print(("[ItemService] running - %d pads, one slot, %d item types, %d/s use limit")
	:format(count, 4, ITEMS.UseRateLimit))
