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
	error("not implemented — CHAIN-COMBAT")
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
	error("not implemented — CHAIN-COMBAT")
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
	error("not implemented — CHAIN-COMBAT")
end

--[[
	resolveChomp(carried) -> ImpactResult
	A hit taken at an empty bar. ChompScatterFraction of carried scatters at
	the defender; the caller handles the respawn timer and leaves upgrades
	alone (CHOMP-SYS-015).
]]
function Impact.resolveChomp(carried: number): ImpactResult
	error("not implemented — CHAIN-COMBAT")
end

--[[
	resolveFall(carried) -> ImpactResult
	FallScatterFraction of carried, scattered where they land. Never lethal,
	never a respawn (CHOMP-SYS-049).
]]
function Impact.resolveFall(carried: number): ImpactResult
	error("not implemented — CHAIN-COMBAT")
end

return Impact
