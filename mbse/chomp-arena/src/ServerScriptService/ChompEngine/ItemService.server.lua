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

local COLOURS = {
	JetPack = Color3.fromRGB(76, 224, 210),
	Cannon = Color3.fromRGB(255, 176, 32),
	HomingBomb = Color3.fromRGB(255, 61, 138),
	Shield = Color3.fromRGB(126, 217, 87),
}

type Held = { id: string, charges: number }
local held: { [Player]: Held } = {}
local shieldUntil: { [Player]: number } = {}

local limiter = Remotes.makeLimiter(ITEMS.UseRateLimit)

-- ── Pads ────────────────────────────────────────────────────────────────

local padsFolder = Instance.new("Folder")
padsFolder.Name = "ItemPads"
padsFolder.Parent = Workspace

local function makePad(id: string, position: Vector3)
	local pad = Instance.new("Part")
	pad.Name = "ItemPad_" .. id
	pad.Shape = Enum.PartType.Ball
	pad.Size = Vector3.new(6, 6, 6)
	pad.Position = position
	pad.Anchored = true
	pad.CanCollide = false
	pad.Material = Enum.Material.Neon
	pad.Color = COLOURS[id] or Color3.new(1, 1, 1)
	pad.Transparency = 0.25
	pad:SetAttribute("ItemId", id)
	-- Fadeable, or the camera treats a floating ball as a hard occluder and
	-- reports a CHOMP-SYS-051 breach for it (D-CHOMP-043).
	CollectionService:AddTag(pad, "Chomp_Decor")
	pad.Parent = padsFolder
	return pad
end

-- Laid out by ring so the good items are further in: the bowl is where the
-- reward is, and an item is a reward (D-CHOMP-041).
local function layOutPads()
	local L = Config.Level1
	if not L then return 0 end
	local plan = {
		{ id = "Shield", radius = L.RingRadii[3], count = 4, y = L.RimHeight + 4 },
		{ id = "JetPack", radius = L.RingRadii[2], count = 4, y = L.RimHeight + 4 },
		{ id = "Cannon", radius = L.RingRadii[1], count = 4, y = L.RimHeight + 4 },
		{ id = "Cannon", radius = L.RimInner * 0.62, count = 4, y = 4 },
		{ id = "HomingBomb", radius = L.RimInner * 0.28, count = 2, y = 4 },
	}
	local made = 0
	for _, entry in plan do
		for i = 0, entry.count - 1 do
			local a = (math.pi * 2) * (i / entry.count) + (made * 0.37)
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

local function give(player: Player, id: string)
	local def = DEFS[id]
	if not def then return end
	held[player] = { id = id, charges = def.charges }
	publish(player)
end

local function clear(player: Player)
	held[player] = nil
	publish(player)
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

	local direction = facing(root)
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
		task.wait(0.15)
		for _, player in Players:GetPlayers() do
			local root = rootOf(player)
			if root then
				for _, pad in padsFolder:GetChildren() do
					if pad:IsA("BasePart") and pad.Transparency < 1
						and (pad.Position - root.Position).Magnitude < ITEMS.PickupRadiusStuds then
						local id = pad:GetAttribute("ItemId")
						if typeof(id) == "string" then
							give(player, id)
							-- The pad is hidden and comes back, rather than being
							-- destroyed and rebuilt: the map stays stocked without
							-- anything having to remember where pads went.
							pad.Transparency = 1
							task.delay(ITEMS.RespawnSeconds, function()
								if pad.Parent then pad.Transparency = 0.25 end
							end)
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
task.spawn(collectionLoop)

print(("[ItemService] running - %d pads, one slot, %d item types, %d/s use limit")
	:format(count, 4, ITEMS.UseRateLimit))
