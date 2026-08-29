--!strict
--[[
	ChompLogic.Impact — CHAIN-COMBAT

	Pure functions. No DataModel access, no services, no os.clock. Given two
	facings and two bars, return the deltas to apply. This is what makes
	CHOMP-TC-016 and CHOMP-TC-017 writable as unit specs rather than as
	"load the game and drive into someone".

	STATUS: signatures and specification only. CHAIN-COMBAT implements.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("Types"))
local Config = require(ReplicatedStorage:WaitForChild("ChompConfig"))

type ImpactResult = Types.ImpactResult

local Impact = {}

local function flatUnit(value: Vector3): Vector3
	local flat = value * Vector3.new(1, 0, 1)
	if flat.Magnitude < 0.001 then return Vector3.zero end
	return flat.Unit
end

local function rounded(value: number): number
	return math.floor(math.max(0, value) + 0.5)
end

local function empty(kind: Types.ImpactKind?): ImpactResult
	return {
		kind = kind or "None",
		attackerBarLoss = 0,
		defenderBarLoss = 0,
		defenderCarryLoss = 0,
		attackerCarryLoss = 0,
		scatterAt = "None",
		scatterAmount = 0,
	}
end

--[[
	classify(facingA, facingB, aboveB) -> ImpactKind

	facingA, facingB : unit XZ vectors, each vehicle's LookVector
	aboveB           : true when A initiated contact from a higher deck

	Rules:
	  * aboveB is true                     -> "Flank" (a mouth never points at
	                                          the ceiling, CHOMP-SYS-050)
	  * angle between the two facings is
	    within 180 +/- HeadOnArcDegrees    -> "HeadOn" (nose to nose)
	  * otherwise                          -> "Flank"

	Boundary cases the spec must cover: exactly 44 degrees off nose-to-nose
	classifies HeadOn, exactly 46 does not; identical facings (one rear-ending
	another) is Flank; a drop attack from above is Flank regardless of facings.
]]
function Impact.classify(facingA: Vector3, facingB: Vector3, aboveB: boolean): Types.ImpactKind
	if aboveB then return "Flank" end
	local a = flatUnit(facingA)
	local b = flatUnit(facingB)
	if a == Vector3.zero or b == Vector3.zero then return "None" end
	local threshold = -math.cos(math.rad(Config.Combat.HeadOnArcDegrees))
	return a:Dot(b) <= threshold and "HeadOn" or "Flank"
end

-- Classifies a real contact, including which mouth initiated it. Facing alone
-- can distinguish nose-to-nose from parallel vehicles, but it cannot tell a
-- rear-end from a reverse collision or an unaimed scrape.
function Impact.classifyContact(sample: Types.ContactSample): Types.ContactClassification
	local aToB = flatUnit(sample.positionB - sample.positionA)
	if aToB == Vector3.zero then return { kind = "None", attacker = "None" } end
	local facingA = flatUnit(sample.facingA)
	local facingB = flatUnit(sample.facingB)
	if facingA == Vector3.zero or facingB == Vector3.zero then
		return { kind = "None", attacker = "None" }
	end

	local vertical = sample.positionA.Y - sample.positionB.Y
	if vertical >= sample.aboveThreshold then return { kind = "Flank", attacker = "A" } end
	if vertical <= -sample.aboveThreshold then return { kind = "Flank", attacker = "B" } end

	local speedA = flatUnit(sample.velocityA) == Vector3.zero and 0
		or sample.velocityA:Dot(facingA)
	local speedB = flatUnit(sample.velocityB) == Vector3.zero and 0
		or sample.velocityB:Dot(facingB)
	local aimedA = facingA:Dot(aToB) >= math.cos(math.rad(sample.mouthArcA * 0.5))
	local aimedB = facingB:Dot(-aToB) >= math.cos(math.rad(sample.mouthArcB * 0.5))
	local movingA = speedA >= sample.minimumAttackSpeed
	local movingB = speedB >= sample.minimumAttackSpeed

	if Impact.classify(facingA, facingB, false) == "HeadOn"
		and aimedA and aimedB and movingA and movingB then
		return { kind = "HeadOn", attacker = "None" }
	end

	local scoreA = aimedA and movingA and (speedA * math.max(0, facingA:Dot(aToB))) or 0
	local scoreB = aimedB and movingB and (speedB * math.max(0, facingB:Dot(-aToB))) or 0
	if scoreA <= 0 and scoreB <= 0 then return { kind = "None", attacker = "None" } end
	if scoreA >= scoreB then return { kind = "Flank", attacker = "A" } end
	return { kind = "Flank", attacker = "B" }
end

--[[
	resolveHeadOn(barA, barB) -> ImpactResult

	Both lose HeadOnBarLoss of their OWN bar. The lower bar additionally loses
	carried points equal to the difference between the two bars. Bars within
	ClangToleranceFraction of each other are a "Clang": bar loss only, no carry
	loss, both bounce.

	Scatter goes to "Midpoint" for a head-on, since neither player owns the
	fight's location.

	Boundary cases: equal bars (clang, symmetric result); one bar at zero
	(the empty player is chomped — the caller checks that, this function still
	returns the deltas); bar difference larger than the loser's carry (clamps,
	and scatterAmount equals what was actually taken, never more).
]]
function Impact.resolveHeadOn(barA: number, barB: number, carryA: number, carryB: number): ImpactResult
	barA = math.max(0, barA)
	barB = math.max(0, barB)
	local result = empty("HeadOn")
	result.attackerBarLoss = barA * Config.Combat.HeadOnBarLoss
	result.defenderBarLoss = barB * Config.Combat.HeadOnBarLoss

	local largest = math.max(barA, barB)
	local difference = math.abs(barA - barB)
	if largest == 0 or difference <= largest * Config.Combat.ClangToleranceFraction then
		result.kind = "Clang"
		return result
	end

	if barA < barB then
		result.attackerCarryLoss = math.min(rounded(carryA), rounded(difference))
		result.scatterAmount = result.attackerCarryLoss
		result.scatterAt = result.scatterAmount > 0 and "Midpoint" or "None"
	else
		result.defenderCarryLoss = math.min(rounded(carryB), rounded(difference))
		result.scatterAmount = result.defenderCarryLoss
		result.scatterAt = result.scatterAmount > 0 and "Midpoint" or "None"
	end
	return result
end

--[[
	resolveFlank(attackerBar, defenderBar, defenderCarry, powerGap) -> ImpactResult

	The attacker spends BiteBarCost of their own bar. That amount comes off the
	defender's bar first and their carried points second. Scatter is at
	"Defender".

	powerGap = attackerPower - defenderPower. Above SmallFryPowerGap the result
	is a valid hit that scatters NOTHING and awards nothing (CHOMP-SYS-016) —
	the defender still gets invulnerability, so a strong player can still shove
	a weak one out of the way, they just cannot farm them.

	Boundary cases: attacker bar empty (no bite is possible, return kind
	"None"); defender bar absorbs the whole bite (zero carry loss); powerGap
	exactly at the threshold (inclusive — at exactly 300 nothing scatters).
]]
function Impact.resolveFlank(
	attackerBar: number,
	defenderBar: number,
	defenderCarry: number,
	powerGap: number
): ImpactResult
	attackerBar = math.max(0, attackerBar)
	defenderBar = math.max(0, defenderBar)
	if attackerBar <= 0 then return empty() end

	local cost = attackerBar * Config.Combat.BiteBarCost
	local result = empty("Flank")
	result.attackerBarLoss = cost
	result.defenderBarLoss = math.min(defenderBar, cost)

	if powerGap < Config.Combat.SmallFryPowerGap then
		local overflow = math.max(0, cost - result.defenderBarLoss)
		result.defenderCarryLoss = math.min(rounded(defenderCarry), rounded(overflow))
		result.scatterAmount = result.defenderCarryLoss
		result.scatterAt = result.scatterAmount > 0 and "Defender" or "None"
	end
	return result
end

--[[
	resolveChomp(carried) -> ImpactResult
	A hit taken at an empty bar. ChompScatterFraction of carried scatters at
	the defender; the caller handles the respawn timer and leaves upgrades
	alone (CHOMP-SYS-015).
]]
function Impact.resolveChomp(carried: number): ImpactResult
	local result = empty("Flank")
	result.defenderCarryLoss = math.min(rounded(carried), rounded(carried * Config.Combat.ChompScatterFraction))
	result.scatterAmount = result.defenderCarryLoss
	result.scatterAt = result.scatterAmount > 0 and "Defender" or "None"
	return result
end

--[[
	resolveFall(carried) -> ImpactResult
	FallScatterFraction of carried, scattered where they land. Never lethal,
	never a respawn (CHOMP-SYS-049).
]]
function Impact.resolveFall(carried: number): ImpactResult
	local result = empty("Flank")
	result.defenderCarryLoss = math.min(rounded(carried), rounded(carried * Config.Combat.FallScatterFraction))
	result.scatterAmount = result.defenderCarryLoss
	result.scatterAt = result.scatterAmount > 0 and "Defender" or "None"
	return result
end

return Impact
