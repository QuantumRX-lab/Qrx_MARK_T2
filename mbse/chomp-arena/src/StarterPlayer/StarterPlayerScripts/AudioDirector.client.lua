--!strict
--[[
	AudioDirector - local, attribute-driven game audio.

	The server already timestamps every player-facing event on the character.
	Listening to those stamps keeps sound out of the trusted combat path and
	avoids adding another RemoteEvent. Blank IDs are skipped cleanly until the
	experience owner uploads the curated files and fills ChompConfig.Audio.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage:WaitForChild("ChompConfig"))
local Audio = Config.Audio
local player = Players.LocalPlayer

local effectsGroup = Instance.new("SoundGroup")
effectsGroup.Name = "ChompEffects"
effectsGroup.Volume = Audio.EffectsVolume
effectsGroup.Parent = SoundService

local musicGroup = Instance.new("SoundGroup")
musicGroup.Name = "ChompMusic"
musicGroup.Volume = Audio.MusicVolume
musicGroup.Parent = SoundService

local function assetId(raw: string): string
	if raw == "" then return "" end
	if string.find(raw, "rbxassetid://", 1, true) == 1 then return raw end
	return "rbxassetid://" .. raw
end

local function sound(raw: string, group: SoundGroup, looped: boolean?): Sound?
	local id = assetId(raw)
	if id == "" then return nil end
	local instance = Instance.new("Sound")
	instance.SoundId = id
	instance.SoundGroup = group
	instance.Looped = looped == true
	instance.RollOffMode = Enum.RollOffMode.InverseTapered
	instance.Parent = SoundService
	return instance
end

local pools: { [string]: { sounds: { Sound }, cursor: number } } = {}

local function makePool(name: string, ids: { string }, voices: number)
	local entries = {}
	for _, id in ipairs(ids) do
		for _ = 1, voices do
			local instance = sound(id, effectsGroup)
			if instance then table.insert(entries, instance) end
		end
	end
	pools[name] = { sounds = entries, cursor = 0 }
end

local function asList(value: any): { string }
	if type(value) == "table" then return value end
	return { value }
end

for name, ids in pairs(Audio.Effects) do
	local voices = (name == "Pellet" or name == "Cannon") and 3 or 1
	makePool(name, asList(ids), voices)
end

local random = Random.new()
local function play(name: string, pitch: number?)
	local pool = pools[name]
	if not pool or #pool.sounds == 0 then return end
	pool.cursor = pool.cursor % #pool.sounds + 1
	local instance = pool.sounds[pool.cursor]
	instance.PlaybackSpeed = pitch or 1
	instance.TimePosition = 0
	instance:Play()
end

local exploration = sound(Audio.Music.Exploration, musicGroup, true)
if exploration then
	exploration.Volume = 1
	exploration:Play()
end

local seen: { [string]: number } = {}
local pelletStep = 0

local function stamp(character: Model, name: string): number
	return (character:GetAttribute(name) :: number?) or 0
end

local function changed(character: Model, name: string): boolean
	local value = stamp(character, name)
	if value <= (seen[name] or 0) then return false end
	seen[name] = value
	return true
end

local function bind(character: Model)
	table.clear(seen)
	pelletStep = 0

	character:GetAttributeChangedSignal("ChompGainedAt"):Connect(function()
		if not changed(character, "ChompGainedAt") then return end
		local powerStarted = stamp(character, "ChompFullJawStartedAt")
		if powerStarted > (seen.ChompFullJawStartedAt or 0) then
			seen.ChompFullJawStartedAt = powerStarted
			play("PowerPellet")
		else
			pelletStep = pelletStep % 5 + 1
			play("Pellet", 0.9 + pelletStep * 0.055)
		end
	end)
	character:GetAttributeChangedSignal("ChompBankedAt"):Connect(function()
		if changed(character, "ChompBankedAt") then play("Bank") end
	end)
	character:GetAttributeChangedSignal("ChompBoughtAt"):Connect(function()
		if changed(character, "ChompBoughtAt") then play("Purchase") end
	end)
	character:GetAttributeChangedSignal("ChompHurtAt"):Connect(function()
		if changed(character, "ChompHurtAt") then play("Hurt", random:NextNumber(0.94, 1.04)) end
	end)
	character:GetAttributeChangedSignal("ChompShieldBrokeAt"):Connect(function()
		if changed(character, "ChompShieldBrokeAt") then play("ShieldBreak") end
	end)
	character:GetAttributeChangedSignal("ChompJumpedAt"):Connect(function()
		if changed(character, "ChompJumpedAt") then play("JetPack") end
	end)
	character:GetAttributeChangedSignal("ChompDiedAt"):Connect(function()
		if changed(character, "ChompDiedAt") then play("Death") end
	end)
	character:GetAttributeChangedSignal("ChompWaveCleared"):Connect(function()
		if changed(character, "ChompWaveCleared") then play("WaveClear") end
	end)
	character:GetAttributeChangedSignal("ChompItemUsedAt"):Connect(function()
		if not changed(character, "ChompItemUsedAt") then return end
		local item = character:GetAttribute("ChompItemUsed")
		if item == "Cannon" then
			play("Cannon", random:NextNumber(0.97, 1.03))
		elseif item == "HomingBomb" then
			play("BombArm")
		elseif item == "Shield" then
			play("ShieldOn")
		elseif item == "JetPack" then
			play("JetPack")
		end
	end)
end

if player.Character then bind(player.Character) end
player.CharacterAdded:Connect(bind)
