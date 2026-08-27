--!strict
--[[
	ItemModels — CHAIN-COMBAT (D-CHOMP-064)

	One factory for the four item silhouettes, so the thing standing on a pad in
	the maze, the thing bolted to your roof, and the thing turning on a shop
	plinth are all the SAME object.

	This was inline in ItemService until the garage started selling items. Two
	copies of a shape is how a cannon on a plinth quietly stops looking like the
	cannon you pick up, and the whole reason these are modelled rather than
	coloured is that a child reads silhouette long before hue (D-CHOMP-047).

	Colours come from Config.Items.Colours, which names Palette keys, so the HUD
	belt can tint a slot with the same colour without importing this module -
	the HUD runs on the client and this never should.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage:WaitForChild("ChompConfig"))
local P = Config.Palette

local ItemModels = {}

function ItemModels.colour(id: string): Color3
	local key = Config.Items.Colours[id]
	return (key and P[key]) or P.Ghost
end

local function bit(model: Model, name: string, size: Vector3, offset: CFrame,
		colour: Color3, material: Enum.Material, shape: Enum.PartType?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = colour
	p.Material = material
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	if shape then p.Shape = shape end
	p.CFrame = offset
	p.Parent = model
	return p
end

function ItemModels.build(id: string): Model
	local model = Instance.new("Model")
	model.Name = "Item_" .. id
	local c = ItemModels.colour(id)

	if id == "JetPack" then
		-- Two thrusters and a pack. It points DOWN, because that is the way the
		-- thrust goes and the way you are about to go is up.
		bit(model, "Pack", Vector3.new(3, 3.4, 1.6), CFrame.new(0, 0.4, 0), c, Enum.Material.Metal)
		bit(model, "Tank", Vector3.new(1.4, 2.8, 1.4), CFrame.new(0, 0.35, 0.9),
			P.BrickDark, Enum.Material.Metal, Enum.PartType.Cylinder)
		for _, side in { -1, 1 } do
			bit(model, "Thruster", Vector3.new(1.1, 2.6, 1.1),
				CFrame.new(side * 1.9, -0.2, 0) * CFrame.Angles(0, 0, math.rad(90)),
				P.BrickDark, Enum.Material.Metal, Enum.PartType.Cylinder)
			bit(model, "Nozzle", Vector3.new(0.8, 0.8, 0.8),
				CFrame.new(side * 1.9, -1.6, 0), c, Enum.Material.Neon, Enum.PartType.Cylinder)
		end

	elseif id == "Cannon" then
		-- A low rotating base, armoured receiver and long barrel. Cylinder length
		-- is its X dimension in Roblox, so the 90-degree yaw points it forward.
		bit(model, "Mount", Vector3.new(2.5, 0.8, 2.5), CFrame.new(0, -0.85, 0),
			P.BrickDark, Enum.Material.Metal)
		bit(model, "BaseRing", Vector3.new(1.0, 3.4, 3.4),
			CFrame.new(0, -1.0, 0) * CFrame.Angles(0, 0, math.rad(90)),
			P.BrickDark, Enum.Material.Metal, Enum.PartType.Cylinder)
		bit(model, "Receiver", Vector3.new(2.6, 1.9, 3.0), CFrame.new(0, 0.25, -0.35),
			c, Enum.Material.Metal)
		bit(model, "Barrel", Vector3.new(1.25, 1.25, 5.8),
			CFrame.new(0, 0.45, -3.6), P.Ghost, Enum.Material.Metal)
		bit(model, "Muzzle", Vector3.new(0.9, 1.8, 1.8),
			CFrame.new(0, 0.45, -6.65) * CFrame.Angles(0, math.rad(90), 0),
			P.Danger, Enum.Material.Neon, Enum.PartType.Cylinder)
		bit(model, "Sight", Vector3.new(0.45, 0.45, 1.5), CFrame.new(0, 1.45, -1.0),
			P.NeonA, Enum.Material.Neon)

	elseif id == "HomingBomb" then
		-- A finned bomb. Fins say it steers; a plain ball would not.
		bit(model, "Body", Vector3.new(3.2, 3.2, 3.2), CFrame.new(0, 0, 0),
			c, Enum.Material.Metal, Enum.PartType.Ball)
		bit(model, "Eye", Vector3.new(1.2, 1.2, 1.2), CFrame.new(0, 0, -1.5),
			P.NeonA, Enum.Material.Neon, Enum.PartType.Ball)
		bit(model, "Band", Vector3.new(0.5, 3.5, 3.5), CFrame.new(0, 0, 0),
			P.BrickDark, Enum.Material.Metal, Enum.PartType.Cylinder)
		for i = 0, 3 do
			local a = (math.pi / 2) * i
			bit(model, "Fin", Vector3.new(0.35, 1.8, 2.2),
				CFrame.new(math.cos(a) * 1.5, 0, math.sin(a) * 1.5) * CFrame.Angles(0, -a, 0),
				P.BrickDark, Enum.Material.Metal)
		end

	else -- Shield
		-- A ring around a core: something that surrounds you rather than fires.
		bit(model, "Core", Vector3.new(1.8, 1.8, 1.8), CFrame.new(0, 0, 0),
			c, Enum.Material.Neon, Enum.PartType.Ball)
		bit(model, "Projector", Vector3.new(2.2, 0.7, 2.2), CFrame.new(0, -1.35, 0),
			P.BrickDark, Enum.Material.Metal, Enum.PartType.Cylinder)
		local segments = 12
		for i = 0, segments - 1 do
			local a = (math.pi * 2) * (i / segments)
			bit(model, "Ring", Vector3.new(0.5, 0.5, 1.5),
				CFrame.new(math.cos(a) * 2.6, 0, math.sin(a) * 2.6) * CFrame.Angles(0, -a, 0),
				c, Enum.Material.Neon)
		end
	end

	local primary = model:FindFirstChildWhichIsA("BasePart")
	model.PrimaryPart = primary
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then CollectionService:AddTag(d, "Chomp_Decor") end
	end
	return model
end

return ItemModels
