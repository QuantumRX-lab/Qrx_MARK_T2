--!strict
-- Server-owned battle bar, carry deltas, banking and pooled combat scatter.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("ChompConfig"))
local C = Config.Combat
local P = Config.Palette

local EconomyService = {}

local scatterFolder = Workspace:FindFirstChild("CombatScatter") :: Folder?
if not scatterFolder then
	scatterFolder = Instance.new("Folder")
	scatterFolder.Name = "CombatScatter"
	scatterFolder.Parent = Workspace
end
local scatterRoot = scatterFolder :: Folder

local token = 0

local function capacity(character: Model): number
	local value = character:GetAttribute("ChompBarCapacity")
	if typeof(value) == "number" then return math.max(0, value) end
	local chassis = character:GetAttribute("ChompChassis")
	local definition = Config.Chassis[typeof(chassis) == "string" and chassis or Config.StartingChassis]
	return definition and definition.BarCapacity or 100
end

function EconomyService.capacity(character: Model): number
	return capacity(character)
end

local function deactivate(part: BasePart)
	part:SetAttribute("Active", false)
	part:SetAttribute("Value", 0)
	part.Transparency = 1
	part.Position = Vector3.new(0, -1000, 0)
end

local function makeScatterPart(index: number): BasePart
	local part = Instance.new("Part")
	part.Name = "ScatterPellet" .. tostring(index)
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(1.5, 1.5, 1.5)
	part.Material = Enum.Material.Neon
	part.Color = P.Gold
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Parent = scatterRoot
	deactivate(part)
	return part
end

local function ensurePool()
	while #scatterRoot:GetChildren() < C.ScatterPoolSize do
		makeScatterPart(#scatterRoot:GetChildren() + 1)
	end
end

local function available(): { BasePart }
	ensurePool()
	local result = {}
	for _, child in scatterRoot:GetChildren() do
		if child:IsA("BasePart") and child:GetAttribute("Active") ~= true then
			table.insert(result, child)
		end
	end
	return result
end

function EconomyService.initialize(character: Model)
	if character:GetAttribute("ChompBattleBar") == nil then
		character:SetAttribute("ChompBattleBar", 0)
	end
end

function EconomyService.battleBar(character: Model): number
	return (character:GetAttribute("ChompBattleBar") :: number?) or 0
end

function EconomyService.carry(character: Model): number
	return (character:GetAttribute("ChompCarried") :: number?) or 0
end

function EconomyService.applyBattleBarDelta(character: Model, delta: number, reason: string?): number
	local before = EconomyService.battleBar(character)
	local after = math.clamp(before + delta, 0, capacity(character))
	character:SetAttribute("ChompBattleBar", after)
	if reason then character:SetAttribute("ChompBattleBarReason", reason) end
	return after - before
end

function EconomyService.applyCarryDelta(character: Model, delta: number, reason: string?): number
	local before = EconomyService.carry(character)
	local after = math.max(0, before + delta)
	character:SetAttribute("ChompCarried", after)
	if reason then character:SetAttribute("ChompCarryReason", reason) end
	return after - before
end

function EconomyService.bank(character: Model, rate: number): number
	local held = EconomyService.carry(character)
	local converted = math.floor(held * rate)
	if converted <= 0 then return 0 end
	local dollars = (character:GetAttribute("ChompDollars") :: number?) or 0
	character:SetAttribute("ChompDollars", dollars + converted)
	EconomyService.applyCarryDelta(character, -held, "bank")
	return converted
end

function EconomyService.scatter(position: Vector3, amount: number, reason: string): number
	amount = math.floor(math.max(0, amount) + 0.5)
	if amount <= 0 then return 0 end
	local free = available()
	local count = math.min(C.ScatterMaxPellets, math.max(1, math.ceil(amount / 10)))
	-- Death spill is value preservation, not a visual effect that may be skipped.
	-- Expand the reusable pool under an extreme simultaneous spill rather than
	-- deleting a haul because every preallocated pellet is temporarily active.
	while #free < count do
		local part = makeScatterPart(#scatterRoot:GetChildren() + 1)
		table.insert(free, part)
	end
	local base = math.floor(amount / count)
	local remainder = amount - base * count
	token += 1
	local spawnToken = token
	for i = 1, count do
		local part = free[i]
		local angle = (i / count) * math.pi * 2 + spawnToken * 0.37
		local radius = 2.5 + (i % 4) * 1.2
		part.Position = position + Vector3.new(math.cos(angle) * radius, -1.5, math.sin(angle) * radius)
		part.Transparency = 0
		part:SetAttribute("Active", true)
		part:SetAttribute("Value", base + (i <= remainder and 1 or 0))
		part:SetAttribute("Reason", reason)
		part:SetAttribute("SpawnToken", spawnToken)
		task.delay(C.ScatterLifetimeSeconds, function()
			if part.Parent and part:GetAttribute("SpawnToken") == spawnToken then deactivate(part) end
		end)
	end
	return amount
end

function EconomyService.collectScatter(character: Model, position: Vector3, radius: number): number
	local collected = 0
	for _, child in scatterRoot:GetChildren() do
		if child:IsA("BasePart") and child:GetAttribute("Active") == true
			and (child.Position - position).Magnitude <= radius then
			collected += (child:GetAttribute("Value") :: number?) or 0
			deactivate(child)
		end
	end
	if collected > 0 then
		EconomyService.applyCarryDelta(character, collected, "scatter")
		character:SetAttribute("ChompGainedAmount", collected)
		character:SetAttribute("ChompGainedAt", os.clock())
	end
	return collected
end

return EconomyService
