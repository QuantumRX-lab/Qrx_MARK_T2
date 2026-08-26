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
	-- Far more of them than there were (D-CHOMP-059). A map you can cross
	-- without finding a weapon teaches you that weapons are incidental, and the
	-- waves make that a losing lesson. Cannons are everywhere; bombs and shields
	-- are worth driving toward.
	local plan = {
		{ id = "Cannon", radius = mid(#radii), count = 10, y = 4 },
		{ id = "Shield", radius = mid(#radii), count = 6, y = 4 },
		{ id = "Cannon", radius = mid(#radii - 1), count = 9, y = 4 },
		{ id = "JetPack", radius = mid(#radii - 1), count = 5, y = 4 },
		{ id = "Shield", radius = mid(#radii - 2), count = 6, y = 4 },
		{ id = "Cannon", radius = mid(#radii - 3), count = 8, y = 4 },
		{ id = "HomingBomb", radius = mid(#radii - 3), count = 4, y = 4 },
		{ id = "JetPack", radius = mid(2), count = 5, y = 4 },
		{ id = "Cannon", radius = mid(2), count = 8, y = 4 },
		{ id = "HomingBomb", radius = L.CentreRadius * 0.55, count = 5, y = 4 },
		{ id = "Shield", radius = L.CentreRadius * 0.55, count = 4, y = 4 },
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
	-- The bomb rides at the back where you can see you are carrying it; guns and
	-- packs go on the roof (D-CHOMP-056).
	local pointName = (id == "HomingBomb") and "RearMount" or "ItemMount"
	local point = vehicle and vehicle:FindFirstChild(pointName) :: BasePart?
	if not (vehicle and point) then return end

	local model = buildItemModel(id)
	model.Name = "MountedItem"
	-- Smaller than the pickup, and facing forward: a mounted gun points where
	-- the kart points, which is also where it fires.
	-- Bigger than it was. A mounted gun that nobody can see is not a mounted gun.
	local scale = (id == "HomingBomb") and 1.25 or 1.15
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

-- ── Auto-lock (D-CHOMP-054) ─────────────────────────────────────────────
-- The turret finds the nearest ghost in front, tracks it, and locks after
-- holding it. Aiming while steering is not a skill worth demanding of a
-- seven-year-old; deciding WHEN to fire is.
--
-- The lock lives on the SERVER. The client draws a reticle from it and cannot
-- create one: a client-declared target would be a client-declared hit.
local friendlyFire: { [Player]: boolean } = {}
local lastShot: { [Player]: number } = {}
local lockTarget: { [Player]: Instance? } = {}
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

-- A target is a ghost model or another player's character; both answer to a
-- pivot, so one helper keeps the rest of the code from caring which it is.
local function mountPosition(character: Model): Vector3?
	local vehicle = character:FindFirstChild("Vehicle")
	local mount = vehicle and vehicle:FindFirstChild("ItemMount") :: BasePart?
	return mount and mount.Position or nil
end

local function targetPosition(thing: Instance): Vector3
	if thing:IsA("Model") then return thing:GetPivot().Position end
	if thing:IsA("BasePart") then return thing.Position end
	return Vector3.zero
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
	local best: Instance? = nil
	local bestDistance = def.lockRangeStuds

	-- Distance in THREE dimensions (D-CHOMP-060). Measuring on the ground plan
	-- meant a ghost directly below a jumping kart read as zero away and a ghost
	-- across the arena read the same whether it was level with you or not.
	local function consider(thing: Instance, position: Vector3)
		local to = position - root.Position
		local distance = to.Magnitude
		if distance >= bestDistance or distance <= 1 then return end
		-- The cone is still measured on the ground plan, because the turret
		-- yaws freely and only pitches within limits: what matters for
		-- acquisition is whether it can face you, not whether it is level.
		local flat = Vector3.new(to.X, 0, to.Z)
		if flat.Magnitude < 0.001 then
			best, bestDistance = thing, distance
			return
		end
		local angle = math.deg(math.acos(math.clamp(forward:Dot(flat.Unit), -1, 1)))
		if angle <= def.lockAngleDegrees then
			best, bestDistance = thing, distance
		end
	end

	for _, ghost in ghostsAlive() do
		consider(ghost, ghost:GetPivot().Position)
	end

	-- Friendly fire is OFF by default and is a deliberate switch (D-CHOMP-059).
	-- Locking onto a friend by accident is how a co-op game turns into an
	-- argument, so it never happens unless someone chose it.
	if friendlyFire[player] then
		for _, other in Players:GetPlayers() do
			if other ~= player then
				local otherRoot = rootOf(other)
				if otherRoot then consider(otherRoot.Parent :: Instance, otherRoot.Position) end
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
	character:SetAttribute("ChompFriendlyFire", friendlyFire[player] == true)

	-- Swing the barrel. Turning at a rate rather than snapping is what makes a
	-- lock feel earned instead of automatic.
	local vehicle = character:FindFirstChild("Vehicle")
	local primary = vehicle and vehicle:FindFirstChild("Chassis") :: BasePart?
	local motor = primary and primary:FindFirstChild("TurretMotor") :: Motor6D?
	if motor then
		local wantedYaw, wantedPitch = 0, 0
		if best then
			local to = targetPosition(best) - (mountPosition(character) or root.Position)
			local flat = Vector3.new(to.X, 0, to.Z)
			if flat.Magnitude > 0.001 then
				local worldYaw = math.atan2(-flat.Unit.X, -flat.Unit.Z)
				local kartYaw = math.atan2(-forward.X, -forward.Z)
				wantedYaw = (worldYaw - kartYaw + math.pi) % (math.pi * 2) - math.pi
				-- Pitch DOWN at something below you. Without this the barrel
				-- stays level while jumping and every shot sails over the top
				-- (D-CHOMP-060).
				wantedPitch = math.clamp(math.atan2(to.Y, flat.Magnitude),
					math.rad(-def.turretPitchDegrees), math.rad(def.turretPitchDegrees))
			end
		end

		local currentPitch, currentYaw = motor.Transform:ToOrientation()
		local step = math.rad(def.turretTurnDegrees) * dt

		local yawDiff = (wantedYaw - currentYaw + math.pi) % (math.pi * 2) - math.pi
		local yaw = math.abs(yawDiff) <= step and wantedYaw
			or currentYaw + (yawDiff > 0 and step or -step)

		local pitchDiff = wantedPitch - currentPitch
		local pitch = math.abs(pitchDiff) <= step and wantedPitch
			or currentPitch + (pitchDiff > 0 and step or -step)

		-- Yaw about the kart, then pitch about the barrel's own axis.
		motor.Transform = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
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
	-- Drop it on the FLOOR, not at the height you happened to be (D-CHOMP-060).
	-- A bomb left hanging in the air after a jump is a mine nobody will ever
	-- drive into, which quietly makes the jump and the bomb mutually exclusive.
	local behind = root.Position - facing(root) * def.dropBehindStuds
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character :: Instance, Workspace:FindFirstChild("Ghosts") :: Instance }
	local hit = Workspace:Raycast(behind + Vector3.new(0, 6, 0), Vector3.new(0, -400, 0), params)
	bomb.Position = hit and (hit.Position + Vector3.new(0, 2.4, 0)) or behind
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

-- Where the barrel actually points. Shots leave the MUZZLE, not the middle of
-- the kart, or they read as something dropped rather than fired (D-CHOMP-056).
local function muzzle(player: Player, root: BasePart): (Vector3, Vector3)
	local character = player.Character
	local vehicle = character and character:FindFirstChild("Vehicle")
	local mount = vehicle and vehicle:FindFirstChild("ItemMount") :: BasePart?
	if mount then
		-- The FULL look vector, pitch included. Flattening it here was what made
		-- an airborne shot fly level (D-CHOMP-060).
		local look = mount.CFrame.LookVector
		if look.Magnitude > 0.001 then
			return mount.Position + look.Unit * 5, look.Unit
		end
	end
	return root.Position + facing(root) * 9 + Vector3.new(0, 3, 0), facing(root)
end

local function fireCannon(player: Player)
	local def = DEFS.Cannon
	local root = rootOf(player)
	if not root then return end

	local origin, direction = muzzle(player, root)

	-- A locked cannon fires at the LOCK. The turret is usually already pointing
	-- there; this matters while the barrel is still catching up.
	local target = lockTarget[player]
	local character = player.Character
	if target and target.Parent and character
		and character:GetAttribute("ChompLockState") == "locked" then
		-- Aim at the target, not at its shadow.
		local to = targetPosition(target) - origin
		if to.Magnitude > 0.001 then direction = to.Unit end
	end

	-- A little spread, so a held trigger looks like fire rather than a laser.
	local spread = math.rad(def.spreadDegrees)
	direction = (CFrame.Angles(0, (math.random() - 0.5) * 2 * spread, 0) * direction).Unit

	-- Inherit the kart's motion. Firing sideways at speed curves the stream away
	-- from the nose, which is what shooting from something moving looks like, and
	-- it makes leading a target something the player learns rather than something
	-- the game hides.
	local velocity = direction * def.projectileSpeed
		+ root.AssemblyLinearVelocity * def.inheritVelocity

	local pellet = Instance.new("Part")
	pellet.Name = "ChompPellet"
	pellet.Size = Vector3.new(def.pelletSize, def.pelletSize, def.pelletLength)
	pellet.Color = P.Gold
	pellet.Material = Enum.Material.Neon
	pellet.Anchored = true
	pellet.CanCollide = false
	pellet.CanQuery = false
	pellet.CastShadow = false
	pellet.CFrame = CFrame.lookAt(origin, origin + velocity)
	CollectionService:AddTag(pellet, "Chomp_Decor")
	pellet.Parent = Workspace
	Debris:AddItem(pellet, 3)

	local travelled = 0
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function(dt)
		if not pellet.Parent then connection:Disconnect() return end
		local step = velocity * dt
		travelled += step.Magnitude
		local nextPos = pellet.Position + step
		pellet.CFrame = CFrame.lookAt(nextPos, nextPos + velocity)

		if travelled >= def.rangeStuds then
			pellet:Destroy()
			connection:Disconnect()
			return
		end

		for _, ghost in ghostsAlive() do
			-- 3D, so a shot angled down from a jump connects (D-CHOMP-060).
			if (ghost:GetPivot().Position - pellet.Position).Magnitude < 11 then
				ghost:SetAttribute("KilledBy", player.UserId)
				ghost:SetAttribute("Health", ((ghost:GetAttribute("Health") :: number?) or 1) - 1)
				pellet:Destroy()
				connection:Disconnect()
				return
			end
		end

		for _, other in Players:GetPlayers() do
			if other ~= player then
				local otherRoot = rootOf(other)
				if otherRoot and (otherRoot.Position - pellet.Position).Magnitude < 7 then
					local humanoid = other.Character
						and other.Character:FindFirstChildOfClass("Humanoid")
					if humanoid then humanoid:TakeDamage(8) end
					pellet:Destroy()
					connection:Disconnect()
					return
				end
			end
		end
	end)
end

local function useHeld(player: Player)
	if not limiter(player) then return end        -- flood protection, server side

	-- A DEPLOYED bomb answers first, whatever you are holding now (D-CHOMP-059).
	-- Picking up a cannon should not strand a live bomb in the map: you placed
	-- it, so you can always set it off.
	local live = deployed[player]
	if live and live.Parent then
		if os.clock() >= ((live:GetAttribute("ArmedAt") :: number?) or 0) then
			detonate(player, live)
			local bomb = held[player]
			if bomb and bomb.id == "HomingBomb" then
				bomb.charges -= 1
				if bomb.charges <= 0 then clear(player) else publish(player) end
			end
			return
		end
	end

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
		-- Detonation is handled above, so reaching here means nothing is
		-- deployed: drop one.
		dropBomb(player)
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
		-- The gun has its own rate, slower than the remote's limit, so holding the
		-- key gives a steady stream rather than whatever the network allows.
		local interval = 1 / DEFS.Cannon.fireRatePerSecond
		if os.clock() - (lastShot[player] or 0) < interval then return end
		lastShot[player] = os.clock()
		fireCannon(player)
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

Remotes.ToggleFriendlyFire.OnServerEvent:Connect(function(player: Player)
	friendlyFire[player] = not friendlyFire[player]
	local character = player.Character
	if character then
		character:SetAttribute("ChompFriendlyFire", friendlyFire[player])
	end
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
