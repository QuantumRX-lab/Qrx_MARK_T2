--!strict
--[[
	Standard — starter chassis spec.

	Built at the origin facing -Z. The mouth is the dominant silhouette feature
	for the world-locked camera; colour is secondary to the projecting split jaw.
	All tuning and identity attributes come from ChompConfig via VehicleFactory.
]]

local YELLOW = Color3.fromRGB(255, 199, 8)
local LOWER_YELLOW = Color3.fromRGB(242, 148, 5)
local MOUTH = Color3.fromRGB(31, 10, 13)
local DARK = Color3.fromRGB(26, 31, 38)
local WHITE = Color3.fromRGB(242, 250, 255)
local CANOPY = Color3.fromRGB(89, 199, 255)

return {
	chassisId = "Standard",
	triangleCount = 0, -- basic parts only

	parts = {
		-- Ground-contact pivot and sole collision body.
		{ name = "Chassis", size = Vector3.new(4.6, 0.4, 5.4), offset = Vector3.new(0, 0.2, 0),
		  color = YELLOW, transparency = 1, collide = true },

		{ name = "BodyShell", size = Vector3.new(4.8, 2.4, 3.2), offset = Vector3.new(0, 1.55, 0.75),
		  color = YELLOW },

		-- A large split wedge projects forward. The asymmetric vertical positions
		-- keep facing legible in greyscale from the 38-degree camera pitch.
		{ name = "MouthUpper", class = "WedgePart", size = Vector3.new(5.2, 1.25, 2.7),
		  offset = Vector3.new(0, 2.55, -2.15), rotation = Vector3.new(0, 180, 0), color = YELLOW },
		{ name = "MouthLower", class = "WedgePart", size = Vector3.new(5.2, 1.1, 2.7),
		  offset = Vector3.new(0, 0.75, -2.15), rotation = Vector3.new(180, 180, 0), color = LOWER_YELLOW },
		{ name = "MouthInterior", size = Vector3.new(4.7, 0.5, 2.35), offset = Vector3.new(0, 1.6, -2.0),
		  color = MOUTH },

		-- The only runtime-recoloured part.
		{ name = "TeamColour", size = Vector3.new(4.9, 0.35, 1.15), offset = Vector3.new(0, 2.7, 0.65),
		  color = WHITE },

		{ name = "EyeLeft", size = Vector3.new(0.65, 0.65, 0.35), shape = "Ball",
		  offset = Vector3.new(-1.25, 2.55, -3.5), color = WHITE },
		{ name = "EyeRight", size = Vector3.new(0.65, 0.65, 0.35), shape = "Ball",
		  offset = Vector3.new(1.25, 2.55, -3.5), color = WHITE },

		{ name = "Canopy", size = Vector3.new(3.5, 1.45, 2.25), offset = Vector3.new(0, 2.55, 0.65),
		  color = CANOPY, transparency = 0.48 },
		{ name = "SkidLeft", size = Vector3.new(0.55, 0.55, 3.7), offset = Vector3.new(-2.15, 0.45, 0.25),
		  color = DARK },
		{ name = "SkidRight", size = Vector3.new(0.55, 0.55, 3.7), offset = Vector3.new(2.15, 0.45, 0.25),
		  color = DARK },
	},
}
