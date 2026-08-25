--!strict
--[[
	CameraController — CHAIN-VEHICLE, CHOMP-SYS-051

	The implementation of 03_architecture/camera_spec.md, and the highest-risk
	item in the project (RISK-CHOMP-012).

	World-locked yaw: the camera never rotates with the vehicle. In a maze you
	turn constantly, and a camera that follows every turn swings the whole world
	several times a second — nauseating on a tablet and fatal to junction
	learnability. The cost is that facing is read from the model, which is why
	the vehicle's mouth has to be 30% of its silhouette.

	Every number comes from ChompConfig.Camera. Nothing here is a literal.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("ChompConfig"))
local C = Config.Camera
local MAP = Config.Map

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- ── Fixed world-space offset ────────────────────────────────────────────
-- Yaw is locked, so this vector never changes. North is always up.
local pitch = math.rad(C.PitchDegrees)
local OFFSET = Vector3.new(0, math.sin(pitch) * C.Distance, math.cos(pitch) * C.Distance)

-- To sit the vehicle at TargetScreenHeight (below centre) the camera looks
-- slightly above it. Roblox FieldOfView is vertical, so the angular offset is
-- the fraction of the screen we want to shift by, times the vertical FOV.
local FOCUS_RAISE = math.tan(math.rad((C.TargetScreenHeight - 0.5) * C.FieldOfView)) * C.Distance

-- ── Critically damped spring for deck changes ───────────────────────────
-- Critically damped, not linear and not bouncy: a linear ease lurches at both
-- ends, and any overshoot on a tablet reads as the floor moving.
local OMEGA = 4 / C.DeckEaseSeconds

-- Horizontal follow and look-ahead are smoothed separately from deck height.
-- Without this the camera copies the character's physics jitter frame for
-- frame, and the look-ahead snaps around the moment you turn — which reads as
-- the world sliding sideways rather than the vehicle turning.
local followX, followZ = nil, nil
local aheadVector = Vector3.zero
local springY = 0
local springV = 0
local springReady = false

local function stepSpring(target: number, dt: number): number
	if not springReady then
		springY, springV, springReady = target, 0, true
		return springY
	end
	-- semi-implicit, stable at large dt
	local accel = -2 * OMEGA * springV - (OMEGA * OMEGA) * (springY - target)
	springV += accel * dt
	springY += springV * dt
	return springY
end

-- ── Occluder fading ─────────────────────────────────────────────────────
-- Fade in fast (0.12 s, leaving margin under the 0.2 s ceiling), restore slow
-- (0.25 s) so geometry does not flicker behind a moving player.
local faded: { [BasePart]: number } = {}

local FADEABLE_TAGS = { Chomp_Wall = true, Chomp_Decor = true, Chomp_Link = true }

local function isFadeable(part: BasePart): boolean
	-- Never fade anything a decision depends on: players, ghosts, guardians,
	-- pellets, gates. If it matters, it stays solid.
	if part:IsDescendantOf(workspace) == false then return false end
	local model = part:FindFirstAncestorOfClass("Model")
	if model and Players:GetPlayerFromCharacter(model) then return false end
	for tag in FADEABLE_TAGS do
		if part:HasTag(tag) then return true end
	end
	return false
end

local function updateFades(obscuring: { BasePart }, dt: number)
	local nowObscuring: { [BasePart]: boolean } = {}
	for _, part in ipairs(obscuring) do
		if isFadeable(part) then
			nowObscuring[part] = true
			local current = faded[part] or 0
			local step = dt / C.OccluderFadeInSeconds * C.OccluderTransparency
			local nextValue = math.min(current + step, C.OccluderTransparency)
			faded[part] = nextValue
			part.LocalTransparencyModifier = nextValue
		end
	end

	for part, value in faded do
		if not nowObscuring[part] then
			local step = dt / C.OccluderFadeOutSeconds * C.OccluderTransparency
			local nextValue = value - step
			if nextValue <= 0 or not part.Parent then
				if part.Parent then part.LocalTransparencyModifier = 0 end
				faded[part] = nil
			else
				faded[part] = nextValue
				part.LocalTransparencyModifier = nextValue
			end
		end
	end
end

-- ── Occlusion measurement (CHOMP-TC-040) ────────────────────────────────
-- The requirement is a hard ceiling on how long the vehicle can be hidden.
-- Measuring it is the only way to know, so the camera logs its own failures.
local occludedFor = 0
local worstOcclusion = 0
local breaches = 0

local function measureOcclusion(obscuring: { BasePart }, dt: number)
	local hidden = false
	for _, part in ipairs(obscuring) do
		if isFadeable(part) then
			if (faded[part] or 0) < C.OccluderTransparency * 0.5 then
				hidden = true
				break
			end
		else
			hidden = true -- something unfadeable is in the way: a real breach
			break
		end
	end

	if hidden then
		occludedFor += dt
		if occludedFor > worstOcclusion then worstOcclusion = occludedFor end
		if occludedFor > C.MaxOcclusionSeconds and occludedFor - dt <= C.MaxOcclusionSeconds then
			breaches += 1
			warn(("[Camera] occlusion breach #%d: hidden for %.2fs (limit %.2fs)")
				:format(breaches, occludedFor, C.MaxOcclusionSeconds))
		end
	else
		occludedFor = 0
	end
end

-- Call from the command bar after a test circuit.
_G.ChompCameraReport = function()
	print(("[Camera] worst occlusion %.3fs, breaches over %.2fs: %d")
		:format(worstOcclusion, C.MaxOcclusionSeconds, breaches))
	return worstOcclusion, breaches
end

-- ── Hit shake ───────────────────────────────────────────────────────────
local shakeUntil = 0
local function shakeOffset(): Vector3
	if os.clock() >= shakeUntil then return Vector3.zero end
	local remaining = (shakeUntil - os.clock()) / C.HitShakeSeconds
	local magnitude = C.HitShakeStuds * remaining
	return Vector3.new(
		(math.random() - 0.5) * 2 * magnitude,
		(math.random() - 0.5) * 2 * magnitude,
		0
	)
end

_G.ChompCameraShake = function()
	shakeUntil = os.clock() + C.HitShakeSeconds
end

-- ── The loop ────────────────────────────────────────────────────────────
local function onRenderStep(dt: number)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		springReady = false
		followX, followZ = nil, nil
		aheadVector = Vector3.zero
		return
	end

	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = C.FieldOfView

	-- Deck is derived from height, so a fall eases down exactly as a ramp
	-- eases up. No jump cuts, including when a player falls (CHOMP-SYS-049).
	-- floor, not round: rounding flips the deck halfway up a ramp and again
	-- mid-fall, which sets the spring chasing a target that keeps changing.
	local deck = math.floor(root.Position.Y / MAP.DeckHeight + 0.25)
	local deckY = stepSpring(deck * MAP.DeckHeight, dt)

	local facing = root.CFrame.LookVector
	local flatFacing = Vector3.new(facing.X, 0, facing.Z)
	if flatFacing.Magnitude > 0.01 then
		flatFacing = flatFacing.Unit
	else
		flatFacing = Vector3.new(0, 0, -1)
	end

	-- Ease the look-ahead toward the new facing rather than snapping to it.
	local targetAhead = flatFacing * C.LookAheadStuds
	local aheadAlpha = math.clamp(dt / C.LookAheadEaseSeconds, 0, 1)
	aheadVector = aheadVector:Lerp(targetAhead, aheadAlpha)

	-- Ease horizontal follow, so character physics jitter never reaches the
	-- camera. Vertical is handled by the deck spring above.
	local followAlpha = math.clamp(dt / C.FollowEaseSeconds, 0, 1)
	followX = followX and (followX + (root.Position.X - followX) * followAlpha) or root.Position.X
	followZ = followZ and (followZ + (root.Position.Z - followZ) * followAlpha) or root.Position.Z

	local focus = Vector3.new(followX, deckY, followZ)
		+ aheadVector
		+ Vector3.new(0, FOCUS_RAISE, 0)

	local position = focus + OFFSET + shakeOffset()
	camera.CFrame = CFrame.lookAt(position, focus)

	local obscuring = camera:GetPartsObscuringTarget({ root.Position }, { character })
	updateFades(obscuring, dt)
	measureOcclusion(obscuring, dt)
end

RunService:BindToRenderStep("ChompCamera", Enum.RenderPriority.Camera.Value, onRenderStep)

player.CharacterRemoving:Connect(function()
	for part in faded do
		if part.Parent then part.LocalTransparencyModifier = 0 end
	end
	table.clear(faded)
	springReady = false
	followX, followZ = nil, nil
	aheadVector = Vector3.zero
end)
