--!strict
--[[
	ChargeService — CHAIN-ECONOMY (D-CHOMP-059)

	The charge meter, and the jump you spend it on.

	Eating fills it. A full bar buys one jump — up and forward, over a wall, out
	of a corner, away from something that has you cornered.

	It is deliberately the only thing in the game that rewards collecting for its
	own sake. Pellets otherwise pay in points you then have to survive with; the
	charge pays immediately, in the one move that gets you out of trouble. That
	gives a frightened player something to do other than run.

	A jump costs JumpCost, not the whole bar (D-CHOMP-066). It used to zero the
	meter, which quietly taxed anyone who kept eating past the threshold up to
	40 charge - and the HUD draws the fill as charge/JumpCost, so the loss was
	not even visible. D-CHOMP-064 had already decided the jump costs 60 of 100;
	the code just never stopped zeroing.

	A full bar now buys a jump AND a 40-charge head start on the next one, which
	makes topping up worth doing. It is still a decision - 15 pellets is most of
	a corridor - but it is no longer "jump the instant it lights or waste it".
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage:WaitForChild("ChompConfig"))
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))

local C = Config.Charge

local limiter = Remotes.makeLimiter(3)

local function charge(character: Model): number
	return (character:GetAttribute("ChompCharge") :: number?) or 0
end

Remotes.UseCharge.OnServerEvent:Connect(function(player: Player)
	if not limiter(player) then return end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (character and root and humanoid) or humanoid.Health <= 0 then return end
	if charge(character) < C.JumpCost then return end

	character:SetAttribute("ChompCharge", charge(character) - C.JumpCost)
	character:SetAttribute("ChompJumpedAt", os.clock())

	-- Up AND forward. A purely vertical hop lands you where you were, which is
	-- exactly where the thing chasing you still is.
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = flat.Magnitude > 0.001 and flat.Unit or Vector3.new(0, 0, -1)

	local body = Instance.new("BodyVelocity")
	body.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
	body.Velocity = Vector3.new(0, C.JumpImpulse, 0) + flat * C.JumpForwardStuds
	body.Parent = root
	Debris:AddItem(body, 0.2)
end)

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		-- Charge does not survive death. It is the escape you did not use.
		character:SetAttribute("ChompCharge", 0)
	end)
end)

print(("[ChargeService] jump spends %d charge of %d max, %d per pellet"):format(C.JumpCost, C.Max, C.PerPellet))
