--!strict
--[[
	GhostService — CHAIN-GHOSTS (D-CHOMP-049)

	Ghosts hunt what you are carrying.

	They are point thieves, not killers. Being caught costs you the risky half of
	your money and nothing else, which is what makes a full carry frightening
	rather than merely inconvenient — you can always drive away, you just cannot
	drive away with everything.

	Making them scary is a design requirement, not decoration. Three things do
	the work and none of them is speed:

	  they are always looking at you   eyes track the nearest kart, so a ghost
	                                   across the arena is still watching
	  they never stop coming           no pathing cleverness, just relentless
	  they go quiet when close         a ghost about to reach you stops bobbing
	                                   and steadies, which reads as intent

	They are deliberately SLOWER than a Standard chassis (Ghosts.Speed 21 against
	BaseSpeed 24). A ghost that can outrun you is a tax; one that can only catch
	the careless is a threat you can play against.

	Ghosts are NEVER tagged fadeable. The camera fades walls so you can see your
	kart; fading the thing hunting you would be actively hostile (D-CHOMP-043).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage:WaitForChild("ChompConfig"))
local G = Config.Ghosts
local W = Config.Waves
local L = Config.Level1
local P = Config.Palette

-- These were literals here, against CHOMP-SYS-037's rule that no balance value
-- may appear in engine logic. They govern how close a ghost has to get, how
-- often one may take from you, and how far one can see - three of the numbers
-- most likely to be reached for in a balancing pass (D-CHOMP-066).
local STEAL_RADIUS = G.StealRadiusStuds
local STEAL_COOLDOWN = G.StealCooldownSeconds
local SENSE_RADIUS = G.SenseRadiusStuds

local folder = Instance.new("Folder")
folder.Name = "Ghosts"
folder.Parent = Workspace

type Ghost = {
	model: Model,
	body: BasePart,
	eyes: { BasePart },
	angle: number,
	radius: number,
	lastSteal: number,
}

local ghosts: { Ghost } = {}
local wave = 0
local waveActive = false

local function activePlayers(): { Player }
	local out = {}
	for _, player in Players:GetPlayers() do
		if player:GetAttribute("ChompSessionState") == Config.Launch.ActiveState then
			table.insert(out, player)
		end
	end
	return out
end

-- ── Sanctuaries (D-CHOMP-065) ───────────────────────────────────────────
-- A garage is somewhere ghosts may not go. Not "spawn away from", which only
-- buys a second - may not GO: no spawning inside, no walking in, no stealing
-- from and no hurting anyone who is inside one.
--
-- The reason is the spawn. A wave anchors on a random player and arrives in a
-- ring 55 to 150 studs around them, and a player who has just spawned has not
-- moved yet, so nine ghosts landed on top of somebody sitting still in the
-- shop. That is not difficulty, it is arriving dead.
--
-- Read once and cached: the pads are built by Level1Map before this runs and
-- never move. If a future map builds them late, this is the thing to revisit.
local sanctuaries: { { centre: Vector3, radius: number } } = {}
local function readSanctuaries()
	table.clear(sanctuaries)
	for _, pad in CollectionService:GetTagged("Chomp_Garage") do
		if pad:IsA("BasePart") then
			local home = pad:GetAttribute("Home") == true
			table.insert(sanctuaries, {
				centre = Vector3.new(pad.Position.X, 0, pad.Position.Z),
				radius = home and L.HomeSafeRadiusStuds or L.GarageSafeRadiusStuds,
			})
		end
	end
end

-- The sanctuary a point is inside, or nil.
local function sanctuaryAt(position: Vector3): { centre: Vector3, radius: number }?
	local flat = Vector3.new(position.X, 0, position.Z)
	for _, s in sanctuaries do
		if (flat - s.centre).Magnitude < s.radius then return s end
	end
	return nil
end

-- Push a point to the nearest spot OUTSIDE every sanctuary. Used for spawning:
-- a ghost that would appear in the garage appears at its edge instead, which
-- keeps the wave the size it was meant to be rather than quietly dropping it.
local function pushClear(position: Vector3): Vector3
	local flat = Vector3.new(position.X, 0, position.Z)
	for _ = 1, #sanctuaries + 1 do
		local inside = sanctuaryAt(flat)
		if not inside then break end
		local out = flat - inside.centre
		out = out.Magnitude > 0.001 and out.Unit or Vector3.new(1, 0, 0)
		flat = inside.centre + out * (inside.radius + 6)
	end
	return Vector3.new(flat.X, position.Y, flat.Z)
end

local function piece(parent: Instance, name: string, size: Vector3, colour: Color3,
		material: Enum.Material, shape: Enum.PartType?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = colour
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	if shape then p.Shape = shape end
	p.Parent = parent
	return p
end

local function buildGhost(): Ghost
	local model = Instance.new("Model")
	model.Name = "Ghost"

	-- A hood, not a ball: the silhouette has to read as a figure at distance.
	local body = piece(model, "Body", Vector3.new(9, 9, 9), P.Ghost, Enum.Material.Neon, Enum.PartType.Ball)
	body.Transparency = 0.28
	local skirt = piece(model, "Skirt", Vector3.new(9, 7, 9), P.Ghost, Enum.Material.Neon)
	skirt.Transparency = 0.35

	-- A ragged hem. Four lobes is enough to read as cloth and cheap enough to
	-- put a dozen of these in a map.
	for i = 0, 5 do
		local a = (math.pi * 2) * (i / 6)
		local lobe = piece(model, "Hem", Vector3.new(3.2, 3.2, 3.2), P.Ghost,
			Enum.Material.Neon, Enum.PartType.Ball)
		lobe.Transparency = 0.4
		lobe:SetAttribute("HemAngle", a)
	end

	local eyes: { BasePart } = {}
	for _, side in { -1, 1 } do
		local eye = piece(model, "Eye", Vector3.new(2.1, 2.6, 1.2), P.Danger,
			Enum.Material.Neon, Enum.PartType.Ball)
		eye:SetAttribute("Side", side)
		table.insert(eyes, eye)
	end

	model.PrimaryPart = body
	model:SetAttribute("Health", G.Health)
	model:SetAttribute("Dead", false)
	-- Tagged so weapons can find them. NOT tagged fadeable: the camera must
	-- never hide the thing hunting you (D-CHOMP-043).
	CollectionService:AddTag(model, "Chomp_Ghost")
	model.Parent = folder
	return {
		model = model, body = body, eyes = eyes,
		angle = 0, radius = 0, lastSteal = 0,
	}
end

local function waveStartCount(): number
	local count = math.max(1, #activePlayers())
	for _, row in W.StartCountByPlayers do
		if count <= row.players then return row.count end
	end
	return W.StartCount
end

local function nearestKart(from: Vector3): (BasePart?, number)
	local best, bestDistance = nil, math.huge
	for _, player in activePlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local d = (root.Position - from).Magnitude
			if d < bestDistance then best, bestDistance = root, d end
		end
	end
	return best, bestDistance
end

local function clearGhosts()
	for _, g in ghosts do
		if g.model.Parent then g.model:Destroy() end
	end
	table.clear(ghosts)
end

local function startWave(n: number)
	wave = n
	waveActive = true
	clearGhosts()

	local wanted = math.min(W.MaxCount, waveStartCount() + W.AddPerWave * (n - 1))

	-- Arrive AROUND somebody (D-CHOMP-062). Ghosts parked on distant rings made
	-- a wave a rumour: you were told it started and then drove for ten seconds
	-- looking for it. A ring of them appearing at the edge of your vision is an
	-- event. SpawnMinDistanceStuds keeps them off your bonnet, because arriving
	-- ON someone is a cheap hit rather than a threat.
	local anchorPoint = Vector3.new(0, 8, 0)
	local players = activePlayers()
	if #players > 0 then
		local who = players[math.random(1, #players)]
		local root = who.Character and who.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then anchorPoint = Vector3.new(root.Position.X, 8, root.Position.Z) end
	end

	for index = 0, wanted - 1 do
		local g = buildGhost()
		g.model.Name = "Ghost_" .. tostring(index + 1)

		local a = (math.pi * 2) * (index / wanted) + math.random() * 0.4
		-- If the anchor is standing in a garage, spawn from the OUTSIDE of it
		-- rather than close in (D-CHOMP-065). Relying on pushClear alone would
		-- shove the whole wave onto the sanctuary line - a wall of ghosts
		-- waiting exactly where the player has to come out, which is worse than
		-- what it was meant to fix.
		local anchorSafe = sanctuaryAt(anchorPoint)
		local near = anchorSafe and (anchorSafe.radius + 40) or W.SpawnMinDistanceStuds
		local far = math.max(near + 40, W.SpawnNearPlayerStuds)
		local spread = near + math.random() * (far - near)
		local x = anchorPoint.X + math.cos(a) * spread
		local z = anchorPoint.Z + math.sin(a) * spread

		-- Never inside a garage, however the anchor fell (D-CHOMP-065).
		local clear = pushClear(Vector3.new(x, 0, z))
		x, z = clear.X, clear.Z

		-- Keep them inside the arena; a ghost outside the boundary wall cannot
		-- reach anyone and just looks broken.
		local limit = L.OuterRadius - L.RingSpacing
		local here = Vector3.new(x, 0, z)
		if here.Magnitude > limit then
			here = here.Unit * limit
			x, z = here.X, here.Z
		end

		g.radius = Vector3.new(x, 0, z).Magnitude
		g.angle = math.atan2(z, x)
		g.model:PivotTo(CFrame.new(x, 8, z))
		table.insert(ghosts, g)
	end

	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character then
			character:SetAttribute("ChompWave", wave)
			character:SetAttribute("ChompWaveCount", wanted)
			character:SetAttribute("ChompWaveAlive", wanted)
		end
	end
	print(("[GhostService] wave %d: %d ghosts, speed %.1f, kill pays $%d")
		:format(wave, wanted, math.min(W.MaxSpeed, G.Speed + W.SpeedPerWave * (n - 1)),
			G.KillRewardDollars + W.RewardPerWave * (n - 1)))
end

local function aliveCount(): number
	local n = 0
	for _, g in ghosts do
		if g.model.Parent and g.model:GetAttribute("Dead") ~= true then n += 1 end
	end
	return n
end

-- Watch for a cleared wave. A break between waves is not politeness, it is the
-- moment you bank what you just earned.
task.spawn(function()
	while true do
		task.wait(1)
		local alive = aliveCount()
		for _, player in Players:GetPlayers() do
			local character = player.Character
			if character then character:SetAttribute("ChompWaveAlive", alive) end
		end
		if waveActive and #ghosts > 0 and alive == 0 then
			waveActive = false
			for _, player in Players:GetPlayers() do
				local character = player.Character
				if character then
					local nextWave = wave + 1
					local advice = if nextWave % 3 == 0 then "SHIELD ADVISED"
						elseif nextWave % 2 == 0 then "CANNON ADVISED"
						else "RESTOCK YOUR BELT"
					character:SetAttribute("ChompWaveCleared", os.clock())
					character:SetAttribute("ChompShopAdvice",
						"WAVE " .. tostring(nextWave) .. " IN " .. tostring(W.BreakSeconds) .. "s  -  " .. advice)
					character:SetAttribute("ChompShopAdviceAt", os.clock())
				end
			end
			task.delay(W.BreakSeconds, function()
				while #activePlayers() == 0 do task.wait(0.5) end
				startWave(wave + 1)
			end)
		end
	end
end)

local t = 0
RunService.Heartbeat:Connect(function(dt)
	t += dt
	for index, g in ghosts do
		if not g.model.Parent then continue end
		-- A dead ghost is invisible and unreachable, and until now it kept
		-- moving and puppeting all ten of its parts every frame until the wave
		-- ended - the Dead check sat AFTER the movement it was meant to skip.
		-- At 22 ghosts that is 220 anchored parts replicating for nothing
		-- (D-CHOMP-066).
		-- Safe to skip everything: the kill-detection block below only ever
		-- fires on a ghost that is NOT yet Dead, so nothing is missed.
		if g.model:GetAttribute("Dead") == true then continue end

		local here = g.model:GetPivot().Position
		local target, distance = nearestKart(here)

		local speed = G.Speed
		local goal: Vector3
		local targetCharacter = target and target.Parent
		local fullJaw = targetCharacter
			and os.clock() < (((targetCharacter :: Model):GetAttribute("ChompFullJawUntil") :: number?) or 0)
		local sense = aliveCount() <= W.RevealLastAt and math.huge or SENSE_RADIUS
		if target and fullJaw then
			local away = here - target.Position
			goal = here + (away.Magnitude > 0.01 and away.Unit or Vector3.new(1, 0, 0)) * 80
			speed = G.FleeSpeed
		elseif target and distance < sense then
			goal = target.Position
		else
			-- No one in range: drift around a ring, so the map always looks
			-- inhabited rather than empty until something notices you.
			g.angle += (dt * 0.25) * (index % 2 == 0 and 1 or -1)
			goal = Vector3.new(math.cos(g.angle) * g.radius, 8, math.sin(g.angle) * g.radius)
			speed = G.FleeSpeed
		end

		speed = math.min(W.MaxSpeed, speed + W.SpeedPerWave * math.max(0, wave - 1))

		local flat = Vector3.new(goal.X - here.X, 0, goal.Z - here.Z)
		local step = flat.Magnitude > 1 and flat.Unit * speed * dt or Vector3.zero

		-- A ghost may not walk into a garage (D-CHOMP-065). Rather than
		-- stopping dead at the line, strip the component pointing at the pad
		-- and keep the rest, so it CIRCLES the sanctuary waiting for you to
		-- come out. That is the behaviour worth having: it reads as patient
		-- rather than broken, and it makes leaving the garage a decision.
		if step.Magnitude > 0 then
			local blocking = sanctuaryAt(Vector3.new(here.X + step.X, 0, here.Z + step.Z))
			if blocking and not sanctuaryAt(here) then
				local inward = blocking.centre - Vector3.new(here.X, 0, here.Z)
				if inward.Magnitude > 0.001 then
					inward = inward.Unit
					step = step - inward * math.max(0, step:Dot(inward))
				end
			end
		end

		-- Close in, the bobbing stops. A ghost that steadies as it arrives reads
		-- as deliberate, and deliberate is what makes it frightening.
		local closing = target and distance < 60
		local bob = closing and 0 or math.sin(t * 1.6 + index) * 1.6
		local y = 8 + bob

		local look = flat.Magnitude > 1 and flat.Unit or Vector3.new(0, 0, -1)
		local pivot = CFrame.lookAt(Vector3.new(here.X + step.X, y, here.Z + step.Z),
			Vector3.new(here.X + step.X + look.X, y, here.Z + step.Z + look.Z))
		g.model:PivotTo(pivot)

		-- Parts are positioned relative to the pivot each frame rather than
		-- welded, because the whole thing is anchored and there is no physics to
		-- respect — this is a puppet, not a body.
		local base = pivot
		for _, d in g.model:GetDescendants() do
			if d:IsA("BasePart") then
				if d.Name == "Skirt" then
					d.CFrame = base * CFrame.new(0, -4.2, 0)
				elseif d.Name == "Hem" then
					local a = (d:GetAttribute("HemAngle") :: number?) or 0
					local wobble = math.sin(t * 4 + a * 3) * 0.8
					d.CFrame = base * CFrame.new(math.cos(a) * 3.4, -7.4 + wobble, math.sin(a) * 3.4)
				elseif d.Name == "Eye" then
					local side = (d:GetAttribute("Side") :: number?) or 1
					d.CFrame = base * CFrame.new(side * 2.1, 1.4, -3.6)
				end
			end
		end

		-- Killed by a weapon: hide, then come back. Ghosts are a pressure, not a
		-- population to exterminate, so clearing one buys time rather than
		-- removing it from the game (D-CHOMP-051).
		if ((g.model:GetAttribute("Health") :: number?) or 1) <= 0
			and g.model:GetAttribute("Dead") ~= true then
			g.model:SetAttribute("Dead", true)

			-- Fly apart. A ghost that simply vanishes is a bug; one that comes
			-- to pieces is a kill, and the difference is entirely in whether
			-- the player believes they did it (D-CHOMP-054).
			local centre = g.model:GetPivot().Position
			for i = 1, 9 do
				local shard = Instance.new("Part")
				shard.Size = Vector3.new(2.4, 2.4, 2.4)
				shard.Shape = Enum.PartType.Ball
				shard.Color = i <= 2 and P.Danger or P.Ghost
				shard.Material = Enum.Material.Neon
				shard.Transparency = 0.25
				shard.CanCollide = false
				shard.CanQuery = false
				shard.Position = centre + Vector3.new(
					math.random(-30, 30) / 10, math.random(-20, 30) / 10, math.random(-30, 30) / 10)
				shard.AssemblyLinearVelocity = Vector3.new(
					math.random(-60, 60), math.random(20, 70), math.random(-60, 60))
				CollectionService:AddTag(shard, "Chomp_Decor")
				shard.Parent = Workspace
				Debris:AddItem(shard, 1.6)
			end

			-- Paid to BANKED, not to the carry. A kill is earned and should not
			-- then be stealable by the next ghost along.
			local killerId = g.model:GetAttribute("KilledBy")
			if typeof(killerId) == "number" then
				local killer = Players:GetPlayerByUserId(killerId)
				local character = killer and killer.Character
				if character then
					local now = (character:GetAttribute("ChompDollars") :: number?) or 0
					local reward = G.KillRewardDollars + W.RewardPerWave * math.max(0, wave - 1)
					character:SetAttribute("ChompDollars", now + reward)
					character:SetAttribute("ChompBankedAmount", reward)
					character:SetAttribute("ChompBankedAt", os.clock())
				end
			end
			g.model:SetAttribute("KilledBy", nil)

			for _, d in g.model:GetDescendants() do
				if d:IsA("BasePart") then d.Transparency = 1 end
			end
			-- No individual respawn any more: a ghost killed stays killed until the
			-- WAVE is cleared, so clearing one is progress you can see rather
			-- than a timer you are racing (D-CHOMP-059).
		end
		if g.model:GetAttribute("Dead") == true then continue end

		-- Contact STEALS and HURTS. Carried only for the theft: banked dollars
		-- are never touchable, which is the entire point of banking
		-- (CHOMP-SYS-005). Damage is small and on a cooldown, so the danger is
		-- being worn down while greedy rather than deleted by one mistake.
		-- Inside a garage nothing can be taken and nothing can be hurt
		-- (D-CHOMP-065). Belt and braces over the movement rule: a ghost that
		-- was already inside when the pads were read, or one carried in by a
		-- shove, still cannot touch you there.
		local safe = target and sanctuaryAt(target.Position) ~= nil
		local character = target and target.Parent :: Model
		local targetPlayer = character and Players:GetPlayerFromCharacter(character)
		local protectedUntil = character and character:GetAttribute("ChompProtectedUntil")
		local protected = typeof(protectedUntil) == "number" and os.clock() < protectedUntil
		local targetActive = targetPlayer ~= nil
			and targetPlayer:GetAttribute("ChompSessionState") == Config.Launch.ActiveState
		-- TWO cooldowns, and they answer different questions (D-CHOMP-066).
		-- g.lastSteal stops ONE ghost machine-gunning you. The per-character
		-- window stops a PACK doing in one instant what a ghost may only do
		-- every few seconds: four ghosts used to land four independent steals
		-- and four lots of damage in the same frame, which is 68% of a carry
		-- and 56 of 100 health from a single brush. The config already carried
		-- ContactCooldownSeconds for exactly this and nothing read it.
		local lastContact = character
			and ((character:GetAttribute("ChompLastContactAt") :: number?) or 0) or 0
		local packReady = (os.clock() - lastContact) > G.ContactCooldownSeconds

		local fullJawActive = character
			and os.clock() < ((character:GetAttribute("ChompFullJawUntil") :: number?) or 0)
		if character and targetActive and not protected and not safe
			and distance < STEAL_RADIUS and fullJawActive then
			local eater = Players:GetPlayerFromCharacter(character)
			if eater then
				g.model:SetAttribute("KilledBy", eater.UserId)
				g.model:SetAttribute("Health", 0)
			end
		elseif character and targetActive and not protected and not safe
			and distance < STEAL_RADIUS and packReady
			and (os.clock() - g.lastSteal) > STEAL_COOLDOWN then
			-- The shield is checked FIRST, and it stops the whole contact
			-- (D-CHOMP-066). It used to be consulted after the theft had
			-- already happened, so it swapped damage for a knockback and let
			-- 25% of the carry go anyway. Ghosts are point thieves - the steal
			-- IS the hit - so a shield that does not stop it does nothing on
			-- the one run you bought it for. D-CHOMP-051 said "absorbs the
			-- contact"; this is that.
			local shieldUntil = (character:GetAttribute("ChompShieldUntil") :: number?) or 0
			if os.clock() < shieldUntil then
				character:SetAttribute("ChompShieldUntil", 0)
				character:SetAttribute("ChompShieldBrokeAt", os.clock())
				g.model:PivotTo(g.model:GetPivot() * CFrame.new(0, 0, 40))
			else
				local held = (character:GetAttribute("ChompCarried") :: number?) or 0
				if held > 0 then
					local taken = math.floor(held * G.StealFraction)
					character:SetAttribute("ChompCarried", held - taken)
					character:SetAttribute("ChompStolenAt", os.clock())
					character:SetAttribute("ChompStolenAmount", taken)
				end

				local humanoid = character:FindFirstChildOfClass("Humanoid")
				if humanoid and humanoid.Health > 0 then
					humanoid:TakeDamage(G.ContactDamage)
					character:SetAttribute("ChompHurtAt", os.clock())
				end
			end
			character:SetAttribute("ChompLastContactAt", os.clock())
			g.lastSteal = os.clock()
		end
	end
end)

-- Tell the player they are safe (D-CHOMP-065). The ring on the floor says
-- WHERE the sanctuary is; this says you are in it, which is the thing you want
-- confirmed when something has been chasing you. Written by the server, like
-- every other value the HUD reads.
task.spawn(function()
	while true do
		task.wait(0.2)
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if character and root then
				character:SetAttribute("ChompSafe", sanctuaryAt(root.Position) ~= nil)
			end
		end
	end
end)

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		character:SetAttribute("ChompWave", wave)
		character:SetAttribute("ChompWaveAlive", aliveCount())
	end)
end)

readSanctuaries()
task.spawn(function()
	while wave == 0 do
		task.wait(0.2)
		if #activePlayers() > 0 then startWave(1) end
	end
end)
print(("[GhostService] waves live: %d sanctuaries, %d%% stolen per catch, " ..
	"base speed %d vs kart %.1f")
	:format(#sanctuaries, math.floor(G.StealFraction * 100), G.Speed,
		Config.Chassis[Config.StartingChassis].BaseSpeed))
