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
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage:WaitForChild("ChompConfig"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))

local ITEMS = Config.Items
local DEFS = ITEMS.Definitions

local P = Config.Palette

-- Item silhouettes come from ItemModels, which the GARAGE also uses to stand
-- the same object on a plinth (D-CHOMP-064). Two copies of a shape is how the
-- cannon you buy stops looking like the cannon you pick up.
local ItemModels = require(ServerStorage:WaitForChild("ChompTools"):WaitForChild("ItemModels"))
local buildItemModel = ItemModels.build

type Held = { id: string, charges: number }

-- A BELT of up to SlotCount items, spent in order (D-CHOMP-062). The active
-- slot is what fires; when it empties it is removed and the next one slides
-- into place, so a player who never touches the selector still works their way
-- through what they picked up.
local belt: { [Player]: { Held } } = {}
local active: { [Player]: number } = {}
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

local function beltOf(player: Player): { Held }
	local b = belt[player]
	if not b then
		b = {}
		belt[player] = b
	end
	return b
end

local function activeItem(player: Player): Held?
	local b = beltOf(player)
	local i = active[player] or 1
	return b[i]
end

local function publish(player: Player)
	-- Attributes rather than a remote: the HUD reads them, and a value the
	-- client only ever READS cannot be forged into the server (CHOMP-SYS-030).
	--
	-- The belt goes over as one string - "Cannon:10,Shield:1" - because an
	-- attribute cannot hold a list and inventing a folder of values for a HUD
	-- to read would be a lot of instances for a comma.
	local character = player.Character
	if not character then return end
	local b = beltOf(player)
	local parts = {}
	for _, entry in b do
		table.insert(parts, entry.id .. ":" .. tostring(entry.charges))
	end
	character:SetAttribute("ChompBelt", table.concat(parts, ","))
	character:SetAttribute("ChompActiveSlot", math.clamp(active[player] or 1, 1, math.max(1, #b)))

	-- Kept for anything still reading the single-slot attributes.
	local current = activeItem(player)
	character:SetAttribute("ChompItem", current and current.id or "")
	character:SetAttribute("ChompItemCharges", current and current.charges or 0)
end

-- Returns false when the belt is full, so the pad stays where it is and can be
-- come back for. Silently eating a pickup you cannot carry is worse than
-- refusing it.
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
	model.Parent = vehicle

	if id == "Cannon" then
		local base = model:FindFirstChild("Mount") :: BasePart?
		local receiver = model:FindFirstChild("Receiver") :: BasePart?
		local barrel = model:FindFirstChild("Barrel") :: BasePart?
		if not (base and receiver and barrel) then model:Destroy() return end

		local yaw = Instance.new("Motor6D")
		yaw.Name = "TurretMotor"
		yaw.Part0 = point
		yaw.Part1 = base
		yaw.C0 = point.CFrame:ToObjectSpace(base.CFrame)
		yaw:SetAttribute("BaseC0", yaw.C0)
		yaw:SetAttribute("Angle", 0)
		yaw.Parent = base

		local receiverWeld = Instance.new("WeldConstraint")
		receiverWeld.Part0 = base
		receiverWeld.Part1 = receiver
		receiverWeld.Parent = receiver

		local pitch = Instance.new("Motor6D")
		pitch.Name = "BarrelMotor"
		pitch.Part0 = receiver
		pitch.Part1 = barrel
		pitch.C0 = receiver.CFrame:ToObjectSpace(barrel.CFrame)
		pitch:SetAttribute("BaseC0", pitch.C0)
		pitch:SetAttribute("Angle", 0)
		pitch.Parent = barrel

		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d ~= base and d ~= receiver and d ~= barrel then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = if d.Name == "BaseRing" then base else barrel
				weld.Part1 = d
				weld.Parent = d
			end
		end
	else
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = point
				weld.Part1 = d
				weld.Parent = d
			end
		end
	end
end

local function give(player: Player, id: string, replaceActiveIfFull: boolean?): boolean
	local def = DEFS[id]
	if not def then return false end
	local b = beltOf(player)
	if #b >= ITEMS.SlotCount then
		if not replaceActiveIfFull then return false end
		local i = math.clamp(active[player] or 1, 1, #b)
		b[i] = { id = id, charges = def.charges }
	else
		table.insert(b, { id = id, charges = def.charges })
	end
	if #b == 1 then active[player] = 1 end
	publish(player)
	if player.Character then mount(player.Character, (activeItem(player) :: Held).id) end
	return true
end

-- Spend the active slot. When it empties it leaves the belt and whatever was
-- behind it becomes active, which is what "used in order" means in practice.
local function consumeActive(player: Player)
	local b = beltOf(player)
	local i = math.clamp(active[player] or 1, 1, math.max(1, #b))
	local entry = b[i]
	if not entry then return end

	entry.charges -= 1
	if entry.charges <= 0 then
		table.remove(b, i)
		if i > #b then active[player] = math.max(1, #b) end
	end
	publish(player)

	local current = activeItem(player)
	if player.Character then
		if current then
			mount(player.Character, current.id)
		else
			unmount(player.Character)
		end
	end
end

local function clearBelt(player: Player)
	belt[player] = {}
	active[player] = 1
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
	local h = activeItem(player)
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
	local mounted = vehicle and vehicle:FindFirstChild("MountedItem")
	local base = mounted and mounted:FindFirstChild("Mount") :: BasePart?
	local barrel = mounted and mounted:FindFirstChild("Barrel") :: BasePart?
	local motor = base and base:FindFirstChild("TurretMotor") :: Motor6D?
	local barrelMotor = barrel and barrel:FindFirstChild("BarrelMotor") :: Motor6D?
	if motor and barrelMotor then
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

		local currentYaw = (motor:GetAttribute("Angle") :: number?) or 0
		local currentPitch = (barrelMotor:GetAttribute("Angle") :: number?) or 0
		local step = math.rad(def.turretTurnDegrees) * dt

		local yawDiff = (wantedYaw - currentYaw + math.pi) % (math.pi * 2) - math.pi
		local yaw = math.abs(yawDiff) <= step and wantedYaw
			or currentYaw + (yawDiff > 0 and step or -step)

		local pitchDiff = wantedPitch - currentPitch
		local pitch = math.abs(pitchDiff) <= step and wantedPitch
			or currentPitch + (pitchDiff > 0 and step or -step)

		-- Yaw about the kart, then pitch about the barrel's own axis.
		-- Transform is an animation channel and does not reliably replicate from a
		-- server-owned Motor6D. C0 does, so every client sees the same turret that
		-- the authoritative targeting code is using.
		local yawBase = (motor:GetAttribute("BaseC0") :: CFrame?) or motor.C0
		local pitchBase = (barrelMotor:GetAttribute("BaseC0") :: CFrame?) or barrelMotor.C0
		motor.C0 = yawBase * CFrame.Angles(0, yaw, 0)
		barrelMotor.C0 = pitchBase * CFrame.Angles(pitch, 0, 0)
		motor:SetAttribute("Angle", yaw)
		barrelMotor:SetAttribute("Angle", pitch)
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

	-- The switch covers explosions as well as shots (D-CHOMP-064). Off, a bomb
	-- is a ghost trap you can stand in; on, it is a bomb.
	if friendlyFire[player] then
		for _, other in Players:GetPlayers() do
			if other ~= player then
				local otherRoot = rootOf(other)
				local humanoid = other.Character
					and other.Character:FindFirstChildOfClass("Humanoid")
				if otherRoot and humanoid
					and (otherRoot.Position - centre).Magnitude < def.blastRadiusStuds then
					humanoid:TakeDamage(35)
				end
			end
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
			-- The charge is spent even though it never went off. You placed it;
			-- forgetting about it is a decision too.
			local b = beltOf(player)
			for i, entry in b do
				if entry.id == "HomingBomb" then
					entry.charges -= 1
					if entry.charges <= 0 then
						table.remove(b, i)
						if (active[player] or 1) > #b then active[player] = math.max(1, #b) end
					end
					break
				end
			end
			publish(player)
		end
	end)
end

-- Where the barrel actually points. Shots leave the MUZZLE, not the middle of
-- the kart, or they read as something dropped rather than fired (D-CHOMP-056).
local function muzzle(player: Player, root: BasePart): (Vector3, Vector3)
	local character = player.Character
	local vehicle = character and character:FindFirstChild("Vehicle")
	local mounted = vehicle and vehicle:FindFirstChild("MountedItem")
	local muzzlePart = mounted and mounted:FindFirstChild("Muzzle") :: BasePart?
	local mount = vehicle and vehicle:FindFirstChild("ItemMount") :: BasePart?
	if muzzlePart then
		-- The cannon barrel is a Cylinder, whose length axis is local X.
		local look = muzzlePart.CFrame.RightVector
		if look.Magnitude > 0.001 then
			return muzzlePart.Position + look.Unit * 1.2, look.Unit
		end
	elseif mount then
		-- The FULL look vector, pitch included. Flattening it here was what made
		-- an airborne shot fly level (D-CHOMP-060).
		local look = mount.CFrame.LookVector
		if look.Magnitude > 0.001 then
			return mount.Position + look.Unit * 5, look.Unit
		end
	end
	return root.Position + facing(root) * 9 + Vector3.new(0, 3, 0), facing(root)
end

-- Where a shot ENDED. A bullet that stops has to leave a mark, or the player
-- learns nothing from the wall it hit and nothing from the range it ran out at
-- (D-CHOMP-064).
local function sparkAt(position: Vector3, colour: Color3)
	local spark = Instance.new("Part")
	spark.Shape = Enum.PartType.Ball
	spark.Size = Vector3.new(1.6, 1.6, 1.6)
	spark.Position = position
	spark.Anchored = true
	spark.CanCollide = false
	spark.CanQuery = false
	spark.CastShadow = false
	spark.Material = Enum.Material.Neon
	spark.Color = colour
	spark.Transparency = 0.25
	CollectionService:AddTag(spark, "Chomp_Decor")
	spark.Parent = Workspace
	Debris:AddItem(spark, 0.12)
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

	-- Walls stop bullets (D-CHOMP-064). Without this a held trigger reached
	-- most of the way across the arena THROUGH the maze, so the safest way to
	-- clear a wave was to face a wall and never look at what you were killing.
	-- The maze only means something if it blocks shots as well as karts.
	local cast = RaycastParams.new()
	cast.FilterType = Enum.RaycastFilterType.Exclude
	cast.FilterDescendantsInstances = { pellet, character, Workspace:FindFirstChild("Ghosts") }
	cast.IgnoreWater = true

	local travelled = 0
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function(dt)
		if not pellet.Parent then connection:Disconnect() return end
		local step = velocity * dt
		local nextPos = pellet.Position + step

		-- Swept, not sampled. At 360 studs a second a per-frame position test
		-- steps straight over a 2-stud wall roughly every other frame.
		local hit = Workspace:Raycast(pellet.Position, step, cast)
		if hit then
			sparkAt(hit.Position, P.Gold)
			pellet:Destroy()
			connection:Disconnect()
			return
		end

		travelled += step.Magnitude
		pellet.CFrame = CFrame.lookAt(nextPos, nextPos + velocity)

		-- Out of range fizzles where it stopped rather than blinking out, so
		-- the edge of the gun is something you can SEE and learn.
		if travelled >= def.rangeStuds then
			sparkAt(pellet.Position, P.NeonB)
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

		-- Friendly fire gates the HIT, not just the lock (D-CHOMP-064). It only
		-- gated acquisition before, so with the switch off you still could not
		-- aim at a friend but a stray burst went straight through them for full
		-- damage. In a game two children play together that is the single worst
		-- bug in the file: it punishes the shot you did not mean to take.
		if friendlyFire[player] then
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
			if player.Character then
				player.Character:SetAttribute("ChompItemUsed", "HomingBomb")
				player.Character:SetAttribute("ChompItemUsedAt", os.clock())
			end
			-- Spending the bomb comes off whichever slot holds it, not
			-- necessarily the active one: you may have picked up a cannon since
			-- placing it (D-CHOMP-059).
			local b = beltOf(player)
			for i, entry in b do
				if entry.id == "HomingBomb" then
					entry.charges -= 1
					if entry.charges <= 0 then
						table.remove(b, i)
						if (active[player] or 1) > #b then active[player] = math.max(1, #b) end
					end
					break
				end
			end
			publish(player)
			return
		end
	end

	local h = activeItem(player)
	if not h then return end                      -- firing with nothing is a no-op
	local root = rootOf(player)
	if not root then return end
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	local def = DEFS[h.id]
	if not def then clearBelt(player) return end

	if h.id == "HomingBomb" then
		-- Two taps: drop, then detonate. The first costs nothing until the
		-- second, so a bomb you never set off is a bomb you still have.
		-- Detonation is handled above, so reaching here means nothing is
		-- deployed: drop one.
		dropBomb(player)
		if player.Character then
			player.Character:SetAttribute("ChompItemUsed", h.id)
			player.Character:SetAttribute("ChompItemUsedAt", os.clock())
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
		-- The gun has its own rate, slower than the remote's limit, so holding the
		-- key gives a steady stream rather than whatever the network allows.
		local interval = 1 / DEFS.Cannon.fireRatePerSecond
		if os.clock() - (lastShot[player] or 0) < interval then return end
		lastShot[player] = os.clock()
		fireCannon(player)
	end
	if player.Character then
		player.Character:SetAttribute("ChompItemUsed", h.id)
		player.Character:SetAttribute("ChompItemUsedAt", os.clock())
	end

	consumeActive(player)
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
							if typeof(id) == "string" and give(player, id) then
								-- hidden and restored rather than destroyed and
								-- rebuilt, so the map restocks without anything
								-- having to remember where a pad was
								setCollected(model, true)
								local wave = math.max(1, (player.Character
									and player.Character:GetAttribute("ChompWave") :: number?) or 1)
								local respawn = math.max(Config.Waves.MinimumItemRespawnSeconds,
									ITEMS.RespawnSeconds - Config.Waves.ItemRespawnReductionPerWave * (wave - 1))
								task.delay(respawn, function()
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
	belt[player] = belt[player] or {}
	active[player] = active[player] or 1
	player.CharacterAdded:Connect(function(character)
		-- The belt is match loadout, not character state. Death rebuilds its HUD
		-- and roof mount without erasing weapons the player already earned.
		shieldUntil[player] = 0
		task.defer(function()
			if character.Parent then
				publish(player)
				local current = activeItem(player)
				if current then mount(character, current.id) end
			end
		end)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	belt[player] = nil
	active[player] = nil
	shieldUntil[player] = nil
end)

Remotes.ToggleFriendlyFire.OnServerEvent:Connect(function(player: Player)
	friendlyFire[player] = not friendlyFire[player]
	local character = player.Character
	if character then
		character:SetAttribute("ChompFriendlyFire", friendlyFire[player])
	end
end)

Remotes.SelectItem.OnServerEvent:Connect(function(player: Player, slot: any)
	-- A slot index is a SELECTION, not a quantity: it asserts nothing about
	-- value, and the server still owns what is in that slot. It is validated
	-- against the belt the SERVER holds, so a forged index selects nothing
	-- (D-CHOMP-062).
	if typeof(slot) ~= "number" or slot ~= slot then return end
	local b = beltOf(player)
	local i = math.floor(slot)
	if i < 1 or i > #b then return end

	active[player] = i
	publish(player)
	if player.Character then
		local current = activeItem(player)
		if current then mount(player.Character, current.id) end
	end
end)

Remotes.UseItem.OnServerEvent:Connect(function(player: Player)
	-- No arguments. Anything a client sent here would be a number worth forging.
	useHeld(player)
end)

-- ── The shop's way in ───────────────────────────────────────────────────
-- GarageService sells items and this service owns the belt. A BindableFunction
-- rather than a shared table, because `give` has to be able to REFUSE - a full
-- belt must not take a player's money (D-CHOMP-064).
--
-- Server to server only. It lives in ServerStorage, which no client can see,
-- and it is not a remote: nothing here widens the client surface.
local grant = Instance.new("BindableFunction")
grant.Name = "GrantItem"
grant.OnInvoke = function(player: Player, id: string, replaceActiveIfFull: boolean?): boolean
	if typeof(id) ~= "string" or not DEFS[id] then return false end
	return give(player, id, replaceActiveIfFull == true)
end
grant.Parent = ServerStorage:WaitForChild("ChompTools")

local count = layOutPads()
animatePads()
task.spawn(collectionLoop)

print(("[ItemService] running - %d pads, %d slots, %d item types, %d/s use limit")
	:format(count, ITEMS.SlotCount, 4, ITEMS.UseRateLimit))
