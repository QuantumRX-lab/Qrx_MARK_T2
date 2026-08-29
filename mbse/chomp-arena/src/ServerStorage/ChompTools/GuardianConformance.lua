--!strict
-- Studio-runnable Build 1 checks for guardian readability and attack fairness.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("ChompConfig"))
local G = Config.Guardian
local P = Config.Palette

local GuardianConformance = {}

type Check = { name: string, passed: boolean, detail: string? }

local function add(results: { Check }, name: string, passed: boolean, detail: string?)
	table.insert(results, { name = name, passed = passed, detail = detail })
end

local function luminance(colour: Color3): number
	return colour.R * 0.2126 + colour.G * 0.7152 + colour.B * 0.0722
end

local function hasPart(model: Model?, name: string): boolean
	return model ~= nil and model:FindFirstChild(name) ~= nil
end

function GuardianConformance.checkAll(): { Check }
	local results: { Check } = {}
	local guardian = Workspace:FindFirstChild("Guardian")
	local model = if guardian and guardian:IsA("Model") then guardian else nil

	add(results, "telegraph.minimum", G.TelegraphSeconds >= 1.5,
		string.format("configured %.2fs; minimum 1.50s", G.TelegraphSeconds))
	add(results, "attack.pounce-not-one-shot", G.PounceDamage > 0 and G.PounceDamage < 100)
	add(results, "attack.dash-not-one-shot", G.DashDamage > 0 and G.DashDamage < 100)
	add(results, "attack.hurl-not-one-shot", G.HurlDamage > 0 and G.HurlDamage < 100)
	add(results, "punish.window", G.VulnerableSeconds >= 2 and G.DashStunSeconds >= G.VulnerableSeconds)
	add(results, "chamber.contrast",
		math.abs(luminance(P.CavernFloor) - luminance(P.CavernCoverA)) >= 0.35,
		"cover must separate clearly from the floor")

	add(results, "runtime.guardian-present", model ~= nil,
		"press Play and wait for the guardian chamber to build")
	if model then
		for _, partName in { "Body", "Rim", "PupilLeft", "PupilRight", "MouthGlow", "MawCore", "UpperMaw", "LowerMaw" } do
			add(results, "model." .. string.lower(partName), hasPart(model, partName))
		end
		local phase = model:GetAttribute("Phase")
		add(results, "runtime.phase", typeof(phase) == "string" and phase ~= "",
			"guardian must publish its current attack phase")
		add(results, "runtime.weak-point", model:GetAttribute("WeakPoint") ~= nil,
			"guardian must publish OPEN or CLOSED")
	end

	return results
end

function GuardianConformance.report(results: { Check }?): boolean
	results = results or GuardianConformance.checkAll()
	local allPassed = true
	for _, check in results do
		if check.passed then
			print("  PASS  " .. check.name)
		else
			allPassed = false
			warn("  FAIL  " .. check.name .. (check.detail and ("  " .. check.detail) or ""))
		end
	end
	print(allPassed and "GUARDIAN CONFORMANCE: PASS" or "GUARDIAN CONFORMANCE: FAIL")
	return allPassed
end

return GuardianConformance
