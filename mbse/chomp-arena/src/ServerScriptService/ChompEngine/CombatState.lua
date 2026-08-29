--!strict
-- Shared server gate for every source of player damage.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("ChompConfig"))

local CombatState = {}

export type HitGate = "Apply" | "Shielded" | "Blocked"

function CombatState.canHit(character: Model, now: number?): boolean
	now = now or os.clock()
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return false end
	if character:GetAttribute("ChompSafe") == true then return false end
	if character:GetAttribute("ChompInLaunchBay") == true then return false end
	if now < ((character:GetAttribute("ChompProtectedUntil") :: number?) or 0) then return false end
	if now < ((character:GetAttribute("ChompInvulnerableUntil") :: number?) or 0) then return false end
	return true
end

function CombatState.beginHit(character: Model, source: string, now: number?): HitGate
	now = now or os.clock()
	if not CombatState.canHit(character, now) then return "Blocked" end
	local shieldUntil = (character:GetAttribute("ChompShieldUntil") :: number?) or 0
	if now < shieldUntil then
		character:SetAttribute("ChompShieldUntil", 0)
		character:SetAttribute("ChompShieldBrokeAt", now)
		character:SetAttribute("ChompCombatKind", "SHIELDED")
		character:SetAttribute("ChompCombatRole", "DEFENDER")
		character:SetAttribute("ChompCombatAt", now)
		return "Shielded"
	end
	character:SetAttribute("ChompInvulnerableUntil", now + Config.Combat.InvulnerabilitySeconds)
	character:SetAttribute("ChompHurtSource", source)
	character:SetAttribute("ChompHurtAt", now)
	return "Apply"
end

function CombatState.initialize(character: Model)
	character:SetAttribute("ChompInvulnerableUntil", 0)
end

return CombatState
