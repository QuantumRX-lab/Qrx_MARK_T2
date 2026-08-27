--!strict
--[[
	Remotes — CHAIN-PLATFORM

	The entire client-to-server surface. Three remotes, and none of them
	carries a quantity: no price, no amount, no power, no hit, no position.
	Everything a client can express is intent; the server supplies every number.

	Adding a fourth remote means extending the exploit regression suite
	(CHOMP-TC-042) in the same commit. That is not a guideline.

	The remotes are DECLARED IN default.project.json, not created here, in a
	folder named RemoteEvents — NOT "Remotes". This module is itself named
	Remotes, and two children of ReplicatedStorage sharing one name makes
	WaitForChild("Remotes") ambiguous: it returned this ModuleScript, which has
	no children, so the lookup below timed out and took the network surface
	down with it (D-CHOMP-024).

	They used to be created at require time by whichever side got there first.
	That was a latent race, and it fired the moment MovementService stopped
	requiring this module: nothing on the server created them any more, so a
	client requiring this module yielded forever on WaitForChild — which took
	the entire input controller down with it, because it requires this at the
	top of the file. Declaring them in the project file means they exist in the
	DataModel before any code runs, and there is nothing left to race.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NAMES = { "RequestPurchase", "RequestBank", "SetInputDirection", "UseItem",
	"UseCharge", "ToggleFriendlyFire", "SelectItem", "ToggleModule" }
local TIMEOUT = 10

local Remotes = {}

local folder = ReplicatedStorage:WaitForChild("RemoteEvents", TIMEOUT)
if not folder then
	error("[Remotes] ReplicatedStorage.RemoteEvents is missing. It is declared in " ..
		"default.project.json — if it is absent, the Rojo sync did not apply.")
end

for _, name in ipairs(NAMES) do
	local remote = folder:WaitForChild(name, TIMEOUT)
	if not remote then
		error(("[Remotes] %s is missing from ReplicatedStorage.RemoteEvents"):format(name))
	end
	Remotes[name] = remote :: RemoteEvent
end

-- Rate limits from service_contracts.md, enforced server-side.
Remotes.Limits = {
	RequestPurchase = 4,
	RequestBank = 2,
	SetInputDirection = 30,
	UseItem = 14,
	UseCharge = 3,
	ToggleFriendlyFire = 2,
	SelectItem = 6,
	ToggleModule = 4,
}

--[[
	makeLimiter(perSecond) -> (player) -> boolean

	Returns false when the caller is over budget. A rejected call is dropped
	silently; the client plays its own refusal feedback on timeout. Sustained
	abuse is logged with the userId — in a Friends-only game that is a
	conversation, not a ban.
]]
function Remotes.makeLimiter(perSecond: number)
	local counts: { [number]: { n: number, windowStart: number, warned: boolean } } = {}
	return function(player: Player): boolean
		local now = os.clock()
		local record = counts[player.UserId]
		if not record or now - record.windowStart >= 1 then
			counts[player.UserId] = { n = 1, windowStart = now, warned = false }
			return true
		end
		record.n += 1
		if record.n <= perSecond then
			return true
		end
		if record.n > perSecond * 10 and not record.warned then
			record.warned = true
			warn(("[Remotes] %s (%d) exceeded a rate limit tenfold")
				:format(player.Name, player.UserId))
		end
		return false
	end
end

return Remotes
