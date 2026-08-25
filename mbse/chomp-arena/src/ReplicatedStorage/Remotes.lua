--!strict
--[[
	Remotes — CHAIN-PLATFORM

	The entire client-to-server surface, created once and found by name. Three
	remotes, and none of them carries a quantity: no price, no amount, no
	power, no hit, no position. Everything a client can express is intent; the
	server supplies every number.

	Adding a fourth remote means extending the exploit regression suite
	(CHOMP-TC-042) in the same commit. That is not a guideline.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NAMES = { "RequestPurchase", "RequestBank", "SetInputDirection" }

local Remotes = {}

local folder = ReplicatedStorage:FindFirstChild("Remotes")
if not folder and RunService:IsServer() then
	folder = Instance.new("Folder")
	folder.Name = "Remotes"
	folder.Parent = ReplicatedStorage
end
if RunService:IsServer() then
	for _, name in ipairs(NAMES) do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
else
	folder = ReplicatedStorage:WaitForChild("Remotes")
end

for _, name in ipairs(NAMES) do
	Remotes[name] = folder:WaitForChild(name) :: RemoteEvent
end

-- Rate limits from service_contracts.md, enforced server-side.
Remotes.Limits = {
	RequestPurchase = 4,
	RequestBank = 2,
	SetInputDirection = 30,
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
