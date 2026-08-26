--!strict

-- Small, immediate sounds turn attribute changes into events the player feels.
-- Packaged Roblox sounds avoid external asset permissions and work in Studio.

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local PING = "rbxasset://sounds/electronicpingshort.wav"
local BUTTON = "rbxasset://sounds/button.wav"
local IMPACT = "rbxasset://sounds/impact_generic.mp3"
local HURT = "rbxasset://sounds/uuhhh.mp3"
local SWOOSH = "rbxasset://sounds/swoosh.wav"

local function play(id: string, volume: number, speed: number)
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume
	sound.PlaybackSpeed = speed
	sound.Parent = SoundService
	sound.Ended:Once(function() sound:Destroy() end)
	sound:Play()
	task.delay(5, function()
		if sound.Parent then sound:Destroy() end
	end)
end

local function watch(character: Model, attribute: string, callback: () -> ())
	local previous = character:GetAttribute(attribute)
	character:GetAttributeChangedSignal(attribute):Connect(function()
		local current = character:GetAttribute(attribute)
		if current ~= previous then
			previous = current
			callback()
		end
	end)
end

local function bind(character: Model)
	local streak = 0
	local lastPellet = 0
	watch(character, "ChompGainedAt", function()
		local now = os.clock()
		streak = now - lastPellet < 1.5 and math.min(5, streak + 1) or 1
		lastPellet = now
		play(PING, 0.32, 0.88 + streak * 0.08)
	end)
	watch(character, "ChompBankedAt", function()
		play(PING, 0.65, 0.72)
		task.delay(0.1, function() play(PING, 0.55, 1.12) end)
	end)
	watch(character, "ChompStolenAt", function() play(IMPACT, 0.65, 0.78) end)
	watch(character, "ChompHurtAt", function() play(HURT, 0.5, 1.05) end)
	watch(character, "ChompBoughtAt", function() play(BUTTON, 0.65, 1.0) end)
	watch(character, "ChompJumpedAt", function() play(SWOOSH, 0.58, 1.15) end)
	watch(character, "ChompDiedAt", function() play(IMPACT, 0.9, 0.62) end)
	watch(character, "ChompItemUsedAt", function()
		local item = character:GetAttribute("ChompItemUsed")
		if item == "Cannon" then
			play(BUTTON, 0.28, 1.7)
		elseif item == "HomingBomb" then
			play(IMPACT, 0.8, 0.72)
		elseif item == "JetPack" then
			play(SWOOSH, 0.62, 1.3)
		else
			play(PING, 0.62, 1.35)
		end
	end)
	watch(character, "ChompWaveCleared", function()
		for i, pitch in { 0.8, 1.0, 1.28 } do
			task.delay((i - 1) * 0.14, function() play(PING, 0.75, pitch) end)
		end
	end)
end

player.CharacterAdded:Connect(bind)
if player.Character then bind(player.Character) end

print("[SoundFeedback] gameplay sounds active")
