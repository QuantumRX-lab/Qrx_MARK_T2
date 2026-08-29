--!strict
-- Studio-runnable pure combat checks. No characters or map required.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Impact = require(ReplicatedStorage:WaitForChild("ChompLogic"):WaitForChild("Impact"))

local CombatConformance = {}

type Check = { name: string, passed: boolean, detail: string? }

local function facing(degrees: number): Vector3
	local radians = math.rad(degrees)
	return Vector3.new(math.sin(radians), 0, -math.cos(radians))
end

local function near(a: number, b: number): boolean
	return math.abs(a - b) < 0.001
end

local function add(results: { Check }, name: string, passed: boolean, detail: string?)
	table.insert(results, { name = name, passed = passed, detail = detail })
end

function CombatConformance.checkAll(): { Check }
	local results: { Check } = {}
	add(results, "angle.44", Impact.classify(facing(0), facing(136), false) == "HeadOn")
	add(results, "angle.46", Impact.classify(facing(0), facing(134), false) == "Flank")
	add(results, "above.flank", Impact.classify(facing(0), facing(180), true) == "Flank")

	local headOn = Impact.resolveHeadOn(100, 40, 200, 200)
	add(results, "headon.bar-a", near(headOn.attackerBarLoss, 40))
	add(results, "headon.bar-b", near(headOn.defenderBarLoss, 16))
	add(results, "headon.carry", headOn.defenderCarryLoss == 60 and headOn.scatterAmount == 60)

	local clang = Impact.resolveHeadOn(100, 95, 100, 100)
	add(results, "headon.clang", clang.kind == "Clang" and clang.scatterAmount == 0)

	local flank = Impact.resolveFlank(100, 20, 300, 0)
	add(results, "flank.cost", near(flank.attackerBarLoss, 30))
	add(results, "flank.overflow", near(flank.defenderBarLoss, 20)
		and flank.defenderCarryLoss == 10 and flank.scatterAmount == 10)
	local smallFry = Impact.resolveFlank(100, 20, 300, 300)
	add(results, "flank.small-fry-inclusive", smallFry.defenderCarryLoss == 0 and smallFry.scatterAmount == 0)
	add(results, "flank.empty-attacker", Impact.resolveFlank(0, 20, 300, 0).kind == "None")
	add(results, "chomp.half", Impact.resolveChomp(301).scatterAmount == 151)

	local rear = Impact.classifyContact({
		positionA = Vector3.new(0, 0, 4), positionB = Vector3.zero,
		facingA = facing(0), facingB = facing(0),
		velocityA = facing(0) * 20, velocityB = facing(0) * 10,
		mouthArcA = 90, mouthArcB = 90, aboveThreshold = 4, minimumAttackSpeed = 4,
	})
	add(results, "contact.rear-end", rear.kind == "Flank" and rear.attacker == "A")
	local reverse = Impact.classifyContact({
		positionA = Vector3.new(0, 0, 4), positionB = Vector3.zero,
		facingA = facing(180), facingB = facing(0),
		velocityA = facing(0) * 20, velocityB = Vector3.zero,
		mouthArcA = 90, mouthArcB = 90, aboveThreshold = 4, minimumAttackSpeed = 4,
	})
	add(results, "contact.reverse", reverse.kind == "None")
	local still = Impact.classifyContact({
		positionA = Vector3.new(0, 0, 4), positionB = Vector3.zero,
		facingA = facing(0), facingB = facing(180),
		velocityA = Vector3.zero, velocityB = Vector3.zero,
		mouthArcA = 90, mouthArcB = 90, aboveThreshold = 4, minimumAttackSpeed = 4,
	})
	add(results, "contact.stationary", still.kind == "None")
	return results
end

function CombatConformance.report(results: { Check }?): boolean
	results = results or CombatConformance.checkAll()
	local allPassed = true
	for _, check in results do
		if check.passed then
			print("  PASS  " .. check.name)
		else
			allPassed = false
			warn("  FAIL  " .. check.name .. (check.detail and ("  " .. check.detail) or ""))
		end
	end
	print(allPassed and "COMBAT CONFORMANCE: PASS" or "COMBAT CONFORMANCE: FAIL")
	return allPassed
end

return CombatConformance
