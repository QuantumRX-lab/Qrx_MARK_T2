--!strict
-- Versioned cross-session vehicle progression. Studio uses an ephemeral
-- profile so local testing can never overwrite the live store.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("ChompConfig"))
local PROFILE = Config.Profile
local store = DataStoreService:GetDataStore(PROFILE.StoreName)
local loaded: { [Player]: boolean } = {}
local blocked: { [Player]: boolean } = {}

local function moduleList(raw: string): { string }
	local out, seen = {}, {}
	for track in string.gmatch(raw, "[^,]+") do
		if table.find(Config.Upgrades.PortTracks, track) and not seen[track] then
			seen[track] = true
			table.insert(out, track)
		end
	end
	return out
end

local function defaultProfile()
	local upgrades = {}
	for _, track in Config.Upgrades.Tracks do upgrades[track] = 0 end
	return {
		schemaVersion = PROFILE.SchemaVersion,
		bankedDollars = 0,
		ownedChassis = "Standard",
		equippedChassis = Config.StartingChassis,
		upgrades = upgrades,
		equippedModules = "",
	}
end

local function sanitize(raw: any)
	local out = defaultProfile()
	if typeof(raw) ~= "table" then return out end
	if typeof(raw.bankedDollars) == "number" then out.bankedDollars = math.max(0, math.floor(raw.bankedDollars)) end
	if typeof(raw.ownedChassis) == "string" then out.ownedChassis = raw.ownedChassis end
	if typeof(raw.equippedChassis) == "string" and Config.Chassis[raw.equippedChassis] then
		out.equippedChassis = raw.equippedChassis
	end
	if typeof(raw.upgrades) == "table" then
		for _, track in Config.Upgrades.Tracks do
			local value = raw.upgrades[track]
			if typeof(value) == "number" then out.upgrades[track] = math.clamp(math.floor(value), 0, Config.Upgrades.MaxLevel) end
		end
	end
	-- Migrate the old three session tracks when a captured v1 profile is used.
	if typeof(raw.upgrades) == "table" then
		out.upgrades.Engine = math.max(out.upgrades.Engine, tonumber(raw.upgrades.Speed) or 0)
		out.upgrades.Handling = math.max(out.upgrades.Handling, tonumber(raw.upgrades.Agility) or 0)
		out.upgrades.Boost = math.max(out.upgrades.Boost, tonumber(raw.upgrades.Consumption) or 0)
	end

	local ports = Config.Chassis[out.equippedChassis].ModulePorts
	local equipped = if typeof(raw.equippedModules) == "string"
		then moduleList(raw.equippedModules) else {}
	-- Schema 2 stored the field but never used it. Preserve the old always-on
	-- experience by filling available ports with owned modules during migration.
	if (tonumber(raw.schemaVersion) or 0) < 3 then
		table.clear(equipped)
		for _, track in Config.Upgrades.PortTracks do
			if out.upgrades[track] > 0 and #equipped < ports then table.insert(equipped, track) end
		end
	end
	local valid = {}
	for _, track in equipped do
		if out.upgrades[track] > 0 and #valid < ports then table.insert(valid, track) end
	end
	out.equippedModules = table.concat(valid, ",")
	return out
end

local function publish(player: Player, profile)
	player:SetAttribute("ChompDollarsPersist", profile.bankedDollars)
	player:SetAttribute("ChompOwnedChassis", profile.ownedChassis)
	player:SetAttribute("ChompEquippedChassis", profile.equippedChassis)
	player:SetAttribute("ChompEquippedModules", profile.equippedModules)
	for _, track in Config.Upgrades.Tracks do
		player:SetAttribute("ChompUpgrade" .. track, profile.upgrades[track])
	end
	player:SetAttribute("ChompProfileReady", true)
	player:SetAttribute("ChompProfileSaveBlocked", blocked[player] == true)
	local character = player.Character
	if character then
		character:SetAttribute("ChompDollars", profile.bankedDollars)
		character:SetAttribute("ChompChassis", profile.equippedChassis)
		character:SetAttribute("ChompEquippedModules", profile.equippedModules)
	end
end

local function capture(player: Player)
	local upgrades = {}
	for _, track in Config.Upgrades.Tracks do
		upgrades[track] = player:GetAttribute("ChompUpgrade" .. track) or 0
	end
	return {
		schemaVersion = PROFILE.SchemaVersion,
		bankedDollars = player:GetAttribute("ChompDollarsPersist") or 0,
		ownedChassis = player:GetAttribute("ChompOwnedChassis") or "Standard",
		equippedChassis = player:GetAttribute("ChompEquippedChassis") or Config.StartingChassis,
		equippedModules = player:GetAttribute("ChompEquippedModules") or "",
		upgrades = upgrades,
	}
end

local function save(player: Player)
	if RunService:IsStudio() or blocked[player] or not loaded[player] then return end
	local snapshot = capture(player)
	local ok, err = false, nil
	for attempt = 1, PROFILE.RetryCount do
		ok, err = pcall(function()
			store:UpdateAsync("player_" .. tostring(player.UserId), function()
				return snapshot
			end)
		end)
		if ok then break end
		if attempt < PROFILE.RetryCount then task.wait(PROFILE.RetryDelaySeconds) end
	end
	if not ok then warn("[ProfileService] save failed for " .. player.Name .. ": " .. tostring(err)) end
end

local function load(player: Player)
	player:SetAttribute("ChompProfileReady", false)
	local profile = defaultProfile()
	if not RunService:IsStudio() then
		local ok, result = false, nil
		for attempt = 1, PROFILE.RetryCount do
			ok, result = pcall(function()
				return store:GetAsync("player_" .. tostring(player.UserId))
			end)
			if ok then break end
			if attempt < PROFILE.RetryCount then task.wait(PROFILE.RetryDelaySeconds) end
		end
		if ok then profile = sanitize(result) else blocked[player] = true end
	end
	loaded[player] = true
	publish(player, profile)
	player.CharacterAdded:Connect(function()
		task.defer(function() if player.Parent then publish(player, capture(player)) end end)
	end)
end

-- load() must not be able to throw its way out of setting ChompProfileReady:
-- the launch bay waits on that attribute, so an error anywhere in here used to
-- be indistinguishable from an infinite DataStore call (D-CHOMP-066). The
-- pcall is the belt; PlayerSessionService's timeout is the braces.
local function safeLoad(player: Player)
	local ok, err = pcall(load, player)
	if not ok then
		warn("[ProfileService] load threw for " .. player.Name .. ": " .. tostring(err))
		blocked[player] = true
		loaded[player] = true
		publish(player, defaultProfile())
	end
end

Players.PlayerAdded:Connect(safeLoad)
-- Anyone already here when this script starts. In a live server nothing joins
-- before server scripts run, but Studio's Start Server and a mid-session
-- reload both produce a player with no profile and no one loading one.
for _, player in Players:GetPlayers() do
	task.spawn(safeLoad, player)
end
Players.PlayerRemoving:Connect(function(player)
	save(player)
	loaded[player], blocked[player] = nil, nil
end)

task.spawn(function()
	while true do
		task.wait(PROFILE.AutosaveSeconds)
		for _, player in Players:GetPlayers() do save(player) end
	end
end)

game:BindToClose(function()
	for _, player in Players:GetPlayers() do save(player) end
end)

print("[ProfileService] versioned profiles live; Studio is ephemeral")
