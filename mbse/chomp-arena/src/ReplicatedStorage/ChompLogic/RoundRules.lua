--!strict
-- Pure round transitions and first-event-wins economy outcomes.

local RoundRules = {}

local NEXT: { [string]: string } = {
	IDLE = "PREP",
	PREP = "WAVE",
	WAVE = "CLEAR",
	CLEAR = "BANK",
	BANK = "INTERMISSION",
	INTERMISSION = "PREP",
}

function RoundRules.canTransition(from: string, to: string): boolean
	return NEXT[from] == to
end

function RoundRules.resolveRace(firstEvent: string, amount: number): (number, number)
	amount = math.max(0, math.floor(amount))
	if firstEvent == "DEATH" then return amount, 0 end
	if firstEvent == "CLEAR" then return 0, amount end
	return 0, 0
end

return RoundRules
