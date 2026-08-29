--!strict
-- Studio-runnable Build 3 checks for round order and value conservation.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("ChompConfig"))
local RoundRules = require(ReplicatedStorage:WaitForChild("ChompLogic"):WaitForChild("RoundRules"))

local RoundConformance = {}

type Check = { name: string, passed: boolean, detail: string? }

local function add(results: { Check }, name: string, passed: boolean, detail: string?)
	table.insert(results, { name = name, passed = passed, detail = detail })
end

function RoundConformance.checkAll(): { Check }
	local results: { Check } = {}
	local sequence = { "IDLE", "PREP", "WAVE", "CLEAR", "BANK", "INTERMISSION", "PREP" }
	for index = 1, #sequence - 1 do
		add(results, "transition." .. sequence[index] .. "-" .. sequence[index + 1],
			RoundRules.canTransition(sequence[index], sequence[index + 1]))
	end
	add(results, "transition.skip-rejected", not RoundRules.canTransition("WAVE", "BANK"))

	local deathSpill, deathBank = RoundRules.resolveRace("DEATH", 500)
	local clearSpill, clearBank = RoundRules.resolveRace("CLEAR", 500)
	add(results, "race.death-first", deathSpill == 500 and deathBank == 0)
	add(results, "race.clear-first", clearSpill == 0 and clearBank == 500)
	add(results, "race.value-conserved", deathSpill + deathBank == 500
		and clearSpill + clearBank == 500)

	local breakTotal = Config.Match.ClearSeconds + Config.Match.BankSeconds
		+ Config.Match.IntermissionSeconds
	add(results, "timing.break", math.abs(breakTotal - Config.Waves.BreakSeconds) < 0.001,
		string.format("state timing %.1fs; wave break %.1fs", breakTotal, Config.Waves.BreakSeconds))
	add(results, "guardian.five-rounds", Config.Match.RoundsPerMatch == 5)

	local state = Workspace:GetAttribute("ChompRoundState")
	add(results, "runtime.state", typeof(state) == "string" and table.find(
		{ "IDLE", "PREP", "WAVE", "CLEAR", "BANK", "INTERMISSION" }, state) ~= nil)
	local completed = (Workspace:GetAttribute("ChompCompletedRounds") :: number?) or 0
	local available = Workspace:GetAttribute("ChompGuardianAvailable") == true
	add(results, "runtime.guardian-gate", available == (completed >= Config.Match.RoundsPerMatch))
	return results
end

function RoundConformance.report(results: { Check }?): boolean
	results = results or RoundConformance.checkAll()
	local allPassed = true
	for _, check in results do
		if check.passed then
			print("  PASS  " .. check.name)
		else
			allPassed = false
			warn("  FAIL  " .. check.name .. (check.detail and ("  " .. check.detail) or ""))
		end
	end
	print(allPassed and "ROUND CONFORMANCE: PASS" or "ROUND CONFORMANCE: FAIL")
	return allPassed
end

return RoundConformance
