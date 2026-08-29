--!strict
-- Server-owned scoring-round state and exactly-once haul resolution.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("ChompConfig"))
local RoundRules = require(ReplicatedStorage:WaitForChild("ChompLogic"):WaitForChild("RoundRules"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))

local MatchService = {}

type PendingBank = { roundId: number, amount: number }

local roundId = 0
local roundNumber = 0
local completedRounds = 0
local state = "IDLE"
local stateEndsAt = 0
local pending: { [Player]: PendingBank } = {}
local bankedRound: { [Player]: number } = {}
local processedDeaths: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function updateGuardianGate()
	local gate = Workspace:FindFirstChild("GuardianRoundGate", true)
	if gate and gate:IsA("BasePart") then
		local available = completedRounds >= Config.Match.RoundsPerMatch
		gate.CanCollide = not available
		gate.CanQuery = not available
		gate.Transparency = available and 1 or 0.18
		local label = gate:FindFirstChild("RoundGateLabel")
		if label and label:IsA("SurfaceGui") then label.Enabled = not available end
	end
end

local function publishCharacter(character: Model)
	character:SetAttribute("ChompRoundId", roundId)
	character:SetAttribute("ChompRound", roundNumber)
	character:SetAttribute("ChompRoundState", state)
	character:SetAttribute("ChompRoundStateEndsAt", stateEndsAt)
	character:SetAttribute("ChompCompletedRounds", completedRounds)
	character:SetAttribute("ChompGuardianAvailable", completedRounds >= Config.Match.RoundsPerMatch)
end

local function publish()
	Workspace:SetAttribute("ChompRoundId", roundId)
	Workspace:SetAttribute("ChompRound", roundNumber)
	Workspace:SetAttribute("ChompRoundState", state)
	Workspace:SetAttribute("ChompRoundStateEndsAt", stateEndsAt)
	Workspace:SetAttribute("ChompCompletedRounds", completedRounds)
	Workspace:SetAttribute("ChompGuardianAvailable", completedRounds >= Config.Match.RoundsPerMatch)
	updateGuardianGate()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character then publishCharacter(character) end
	end
end

local function setState(nextState: string, duration: number)
	assert(RoundRules.canTransition(state, nextState),
		"illegal round transition " .. state .. " -> " .. nextState)
	state = nextState
	stateEndsAt = if duration > 0 then os.clock() + duration else 0
	publish()
end

function MatchService.prepare(nextRound: number)
	roundId += 1
	roundNumber = nextRound
	table.clear(pending)
	setState("PREP", Config.Match.PrepSeconds)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character then
			EconomyService.applyCarryDelta(character, -EconomyService.carry(character), "round-start")
			character:SetAttribute("ChompRoundOutcome", "")
		end
	end
end

function MatchService.beginWave(expectedRound: number): boolean
	if state ~= "PREP" or expectedRound ~= roundNumber then return false end
	setState("WAVE", 0)
	return true
end

function MatchService.clearRound(): boolean
	if state ~= "WAVE" then return false end
	completedRounds += 1
	setState("CLEAR", Config.Match.ClearSeconds)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if character and humanoid and humanoid.Health > 0 then
			local amount = EconomyService.carry(character)
			pending[player] = { roundId = roundId, amount = amount }
			-- Secure the value before a disconnect can race ProfileService. The
			-- character-facing dollar total changes only in the BANK state.
			if amount > 0 then
				local safe = (player:GetAttribute("ChompDollarsPersist") :: number?) or 0
				player:SetAttribute("ChompDollarsPersist", safe + amount)
			end
			character:SetAttribute("ChompRoundOutcome", "SURVIVED")
		end
	end
	return true
end

function MatchService.bankRound(): boolean
	if state ~= "CLEAR" then return false end
	setState("BANK", Config.Match.BankSeconds)
	for player, record in pending do
		if record.roundId == roundId and bankedRound[player] ~= roundId then
			bankedRound[player] = roundId
			local character = player.Character
			if character then
				EconomyService.applyCarryDelta(character, -EconomyService.carry(character), "round-bank")
				character:SetAttribute("ChompDollars",
					(player:GetAttribute("ChompDollarsPersist") :: number?) or 0)
				character:SetAttribute("ChompBankedAmount", record.amount)
				character:SetAttribute("ChompBankedAt", os.clock())
				character:SetAttribute("ChompRoundOutcome", "BANKED")
			end
		end
	end
	return true
end

function MatchService.intermission(): boolean
	if state ~= "BANK" then return false end
	setState("INTERMISSION", Config.Match.IntermissionSeconds)
	return true
end

function MatchService.spillDeath(player: Player, character: Model, position: Vector3): number
	if state ~= "WAVE" or processedDeaths[character] then return 0 end
	processedDeaths[character] = true
	local amount = EconomyService.carry(character)
	if amount <= 0 then return 0 end
	EconomyService.applyCarryDelta(character, -amount, "death-spill")
	local scattered = EconomyService.scatter(position, amount, "round-death")
	character:SetAttribute("ChompSpilledAmount", scattered)
	character:SetAttribute("ChompSpilledAt", os.clock())
	character:SetAttribute("ChompRoundOutcome", "SPILLED")
	player:SetAttribute("ChompLastSpilledAmount", scattered)
	player:SetAttribute("ChompLastSpilledAt", os.clock())
	return scattered
end

function MatchService.state(): string
	return state
end

function MatchService.roundId(): number
	return roundId
end

local function setupPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		publishCharacter(character)
		character:SetAttribute("ChompCarried", 0)
	end)
	if player.Character then
		publishCharacter(player.Character)
		player.Character:SetAttribute("ChompCarried", 0)
	end
end

Players.PlayerAdded:Connect(setupPlayer)
for _, player in Players:GetPlayers() do setupPlayer(player) end

publish()

return MatchService
