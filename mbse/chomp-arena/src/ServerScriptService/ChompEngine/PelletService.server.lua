--!strict
--[[
	PelletService — CHAIN-ECONOMY (D-CHOMP-048)

	Pellets to eat, points to carry, and a garage to bank them at.

	Carried points are RISKY and banked dollars are SAFE, and that distinction is
	the whole economy: a ghost can take what you are carrying and can never touch
	what you banked. Driving back to a garage with a full load is meant to be the
	tensest thing in the game.

	Value rises with the ring. The middle of the map is open, has nothing to hide
	behind, and is where the ghosts converge, so it pays more.

	Both totals live as attributes on the character. The HUD reads them and
	cannot write them (CHOMP-SYS-030): a number the client only ever reads is a
	number it cannot forge.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("ChompConfig"))
local L = Config.Level1
local E = Config.Economy
local P = Config.Palette

-- Reach, not taste, but still balance: how close counts as eating, and how
-- close counts as banking. Literals here breached CHOMP-SYS-037 (D-CHOMP-066).
local PELLET_RADIUS = E.PelletPickupRadiusStuds
local BANK_RADIUS = E.BankRadiusStuds

local folder = Instance.new("Folder")
folder.Name = "Pellets"
folder.Parent = Workspace

local function carried(character: Model): number
	return (character:GetAttribute("ChompCarried") :: number?) or 0
end

local function dollars(character: Model): number
	return (character:GetAttribute("ChompDollars") :: number?) or 0
end

local function makePellet(position: Vector3, value: number, power: boolean)
	local p = Instance.new("Part")
	p.Name = power and "PowerPellet" or "Pellet"
	p.Shape = Enum.PartType.Ball
	p.Size = power and Vector3.new(5, 5, 5) or Vector3.new(2.2, 2.2, 2.2)
	p.Position = position
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.Material = Enum.Material.Neon
	p.Color = power and P.Gold or P.NeonA
	p:SetAttribute("Value", value)
	p:SetAttribute("PowerPellet", power)
	-- Pellets are decisions, not scenery, but they are small enough that fading
	-- one never hides anything that matters — and an unfadeable pellet between
	-- the camera and the kart is a CHOMP-SYS-051 breach (D-CHOMP-043).
	CollectionService:AddTag(p, "Chomp_Decor")
	p.Parent = folder
	return p
end

-- Sanctuary circles, read the same way GhostService reads them. Pellets do not
-- go inside one (D-CHOMP-066).
--
-- D-CHOMP-065 made garages ghost-proof and dropped that circle straight on top
-- of four existing pellet lanes, one of them the richest on the map. The result
-- was about 1,750 points a sweep, next to the bank, respawning every 12
-- seconds, with nothing able to touch you - so the best possible play was to
-- orbit the spawn and never leave. That is the farm D-CHOMP-065's own
-- reasoning warned about: "a sanctuary you can hide in is a sanctuary that
-- ends the game."
local function sanctuaries(): { { centre: Vector3, radius: number } }
	local out = {}
	for _, pad in CollectionService:GetTagged("Chomp_Garage") do
		if pad:IsA("BasePart") then
			table.insert(out, {
				centre = Vector3.new(pad.Position.X, 0, pad.Position.Z),
				radius = pad:GetAttribute("Home") == true
					and L.HomeSafeRadiusStuds or L.GarageSafeRadiusStuds,
			})
		end
	end
	return out
end

local function layOut(): number
	local safe = sanctuaries()
	-- The rim value still appears inside a sanctuary. The first minute has to
	-- teach eat-then-bank somewhere, and a trail of the CHEAPEST pellets does
	-- that without paying anyone to stay home.
	local rimValue = E.PelletValueByRing[1]
	local function blocked(position: Vector3, value: number): boolean
		if value <= rimValue then return false end
		local flat = Vector3.new(position.X, 0, position.Z)
		for _, zone in safe do
			if (flat - zone.centre).Magnitude < zone.radius then return true end
		end
		return false
	end

	local radii = {}
	local r = L.CentreRadius
	while r <= L.OuterRadius - L.RingSpacing do
		table.insert(radii, r)
		r += L.RingSpacing
	end

	local made = 0
	for index, radius in ipairs(radii) do
		local lane = radius + L.RingSpacing / 2
		-- ring 1 is the innermost and pays most: value counts DOWN from the middle
		local tier = math.clamp(#radii - index + 1, 1, #E.PelletValueByRing)
		local value = E.PelletValueByRing[tier] or 10
		local spacing = 26
		local count = math.max(8, math.floor((2 * math.pi * lane) / spacing))
		for i = 0, count - 1 do
			local a = (math.pi * 2) * (i / count) + index * 0.13
			local at = Vector3.new(math.cos(a) * lane, 4, math.sin(a) * lane)
			if not blocked(at, value) then
				makePellet(at, value, false)
				made += 1
			end
		end
	end

	-- Power pellets in the open middle, where there is nowhere to hide.
	for i = 0, 3 do
		local a = (math.pi * 2) * (i / 4) + math.pi / 4
		makePellet(Vector3.new(math.cos(a) * (L.CentreRadius * 0.6), 4,
			math.sin(a) * (L.CentreRadius * 0.6)), E.PowerPelletValue, true)
		made += 1
	end
	return made
end

-- Collection and banking share a loop: both are "am I near a thing", and at
-- 0.1s that is cheap enough not to deserve two.
local function loop()
	local lastBank: { [Player]: number } = {}
	while true do
		task.wait(0.1)
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not (character and root) then continue end

			for _, pellet in folder:GetChildren() do
				if pellet:IsA("BasePart") and pellet.Transparency < 1
					and (pellet.Position - root.Position).Magnitude < PELLET_RADIUS then
					local baseValue = (pellet:GetAttribute("Value") :: number?) or 0
					local multiplier = (character:GetAttribute("ChompPelletMultiplier") :: number?) or 1
					local value = math.floor(baseValue * multiplier)
					character:SetAttribute("ChompCarried", carried(character) + value)
					if pellet:GetAttribute("PowerPellet") == true then
						character:SetAttribute("ChompFullJawUntil", os.clock() + Config.Ghosts.FullJawSeconds)
						character:SetAttribute("ChompFullJawStartedAt", os.clock())
					end
					-- Announce the GAIN, not just the new total. A number that
					-- ticks up in a corner is invisible to someone watching a
					-- corridor; "+25" above the kart is not (D-CHOMP-052).
					-- Every pellet also fills the charge meter (D-CHOMP-059). It is the
					-- only reward in the game that pays immediately rather than needing
					-- to be survived with, which gives a frightened player something to
					-- do other than run.
					local CH = Config.Charge
					character:SetAttribute("ChompCharge",
						math.min(CH.Max, ((character:GetAttribute("ChompCharge") :: number?) or 0) + CH.PerPellet))
					character:SetAttribute("ChompGainedAmount", value)
					character:SetAttribute("ChompGainedAt", os.clock())
					pellet.Transparency = 1
					task.delay(E.PelletRespawnSeconds, function()
						if pellet.Parent then pellet.Transparency = 0 end
					end)
				end
			end

			-- Banking: drive onto your garage pad and the carry becomes dollars.
			-- No button, no prompt — it is a consequence of driving somewhere
			-- (D-CHOMP-015's one surviving principle).
			local now = os.clock()
			if carried(character) > 0 and (now - (lastBank[player] or 0)) > E.GarageReentryCooldownSeconds then
				for _, pad in CollectionService:GetTagged("Chomp_Garage") do
					if pad:IsA("BasePart") and (pad.Position - root.Position).Magnitude < BANK_RADIUS then
						local banked = math.floor(carried(character) * E.BankRate)
						character:SetAttribute("ChompDollars", dollars(character) + banked)
						character:SetAttribute("ChompCarried", 0)
						character:SetAttribute("ChompBankedAmount", banked)
						character:SetAttribute("ChompBankedAt", now)
						lastBank[player] = now
						break
					end
				end
			end
		end
	end
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		-- Carried points do NOT survive death; dollars do. That is the risk.
		local keep = 0
		local previous = player:GetAttribute("ChompDollarsPersist")
		if typeof(previous) == "number" then keep = previous end
		character:SetAttribute("ChompCarried", 0)
		character:SetAttribute("ChompDollars", keep)
		character:GetAttributeChangedSignal("ChompDollars"):Connect(function()
			player:SetAttribute("ChompDollarsPersist", dollars(character))
		end)
	end)
end)

local count = layOut()
task.spawn(loop)

print(("[PelletService] %d pellets laid, values %s, bank rate %.1f")
	:format(count, "by ring from the middle out", E.BankRate))
