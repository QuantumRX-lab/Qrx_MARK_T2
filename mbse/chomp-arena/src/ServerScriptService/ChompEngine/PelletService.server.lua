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

local PELLET_RADIUS = 9
local BANK_RADIUS = 22

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
	-- Pellets are decisions, not scenery, but they are small enough that fading
	-- one never hides anything that matters — and an unfadeable pellet between
	-- the camera and the kart is a CHOMP-SYS-051 breach (D-CHOMP-043).
	CollectionService:AddTag(p, "Chomp_Decor")
	p.Parent = folder
	return p
end

local function layOut(): number
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
		local tier = math.clamp(#radii - index + 1, 1, 4)
		local value = E.PelletValueByRing[tier] or 10
		local spacing = 26
		local count = math.max(8, math.floor((2 * math.pi * lane) / spacing))
		for i = 0, count - 1 do
			local a = (math.pi * 2) * (i / count) + index * 0.13
			makePellet(Vector3.new(math.cos(a) * lane, 4, math.sin(a) * lane), value, false)
			made += 1
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
					local value = (pellet:GetAttribute("Value") :: number?) or 0
					character:SetAttribute("ChompCarried", carried(character) + value)
					-- Announce the GAIN, not just the new total. A number that
					-- ticks up in a corner is invisible to someone watching a
					-- corridor; "+25" above the kart is not (D-CHOMP-052).
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
