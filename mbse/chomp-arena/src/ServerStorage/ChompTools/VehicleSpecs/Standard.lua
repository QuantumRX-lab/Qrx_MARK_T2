--!strict
--[[
	Standard — starter chassis spec.

	The original visual mock-up is the design reference: an open bubble cockpit
	inside a Pac-shaped shell, a deep contrasting mouth, chunky teeth, round
	light-eyes, and one large modular socket. Built facing -Z; all tuning and
	identity attributes come from ChompConfig through VehicleFactory.
]]

local YELLOW = Color3.fromRGB(255, 201, 18)
local LOWER_YELLOW = Color3.fromRGB(232, 145, 9)
local RED = Color3.fromRGB(116, 19, 24)
local DARK = Color3.fromRGB(27, 31, 38)
local METAL = Color3.fromRGB(80, 91, 103)
local WHITE = Color3.fromRGB(245, 241, 224)
local GLASS = Color3.fromRGB(105, 205, 238)
local PORT = Color3.fromRGB(54, 231, 218)

return {
	chassisId = "Standard",
	triangleCount = 0,
	parts = {
		{ name = "Chassis", size = Vector3.new(4.6, 0.4, 5.4), offset = Vector3.new(0, 0.2, 0),
		  color = YELLOW, transparency = 1, collide = true },

		-- Lower pod and rear shell leave the upper-front cockpit visually open.
		{ name = "BodyShell", size = Vector3.new(5.3, 2.55, 4.5), shape = "Ball",
		  offset = Vector3.new(0, 1.25, 0.3), color = YELLOW },
		-- A thin rear bulkhead closes the pod without filling the glass cockpit.
		{ name = "RearShell", size = Vector3.new(4.55, 3.3, 0.9), shape = "Ball",
		  offset = Vector3.new(0, 2.1, 1.65), color = YELLOW },

		-- Compact jaws form an open V instead of a long aircraft nose.
		{ name = "MouthUpper", class = "WedgePart", size = Vector3.new(4.8, 1.15, 1.45),
		  offset = Vector3.new(0, 2.35, -1.65), rotation = Vector3.new(0, 180, 0), color = YELLOW },
		{ name = "MouthLower", class = "WedgePart", size = Vector3.new(4.8, 0.95, 1.55),
		  offset = Vector3.new(0, 0.75, -1.7), rotation = Vector3.new(180, 180, 0), color = LOWER_YELLOW },
		{ name = "MouthInterior", size = Vector3.new(4.3, 0.78, 1.35),
		  offset = Vector3.new(0, 1.45, -1.75), color = RED },

		-- Broad teeth echo the mock-up and make facing readable without colour.
		{ name = "Tooth1", size = Vector3.new(0.55, 0.38, 0.42), offset = Vector3.new(-1.75, 1.22, -2.38), color = WHITE },
		{ name = "Tooth2", size = Vector3.new(0.55, 0.38, 0.42), offset = Vector3.new(-1.05, 1.18, -2.43), color = WHITE },
		{ name = "Tooth3", size = Vector3.new(0.55, 0.38, 0.42), offset = Vector3.new(-0.35, 1.16, -2.45), color = WHITE },
		{ name = "Tooth4", size = Vector3.new(0.55, 0.38, 0.42), offset = Vector3.new(0.35, 1.16, -2.45), color = WHITE },
		{ name = "Tooth5", size = Vector3.new(0.55, 0.38, 0.42), offset = Vector3.new(1.05, 1.18, -2.43), color = WHITE },
		{ name = "Tooth6", size = Vector3.new(0.55, 0.38, 0.42), offset = Vector3.new(1.75, 1.22, -2.38), color = WHITE },

		-- Friendly circular light-eyes on the brow panel.
		{ name = "EyeLeft", size = Vector3.new(0.75, 0.75, 0.38), shape = "Ball",
		  offset = Vector3.new(-1.35, 2.55, -2.28), color = WHITE, material = Enum.Material.Neon },
		{ name = "EyeRight", size = Vector3.new(0.75, 0.75, 0.38), shape = "Ball",
		  offset = Vector3.new(1.35, 2.55, -2.28), color = WHITE, material = Enum.Material.Neon },

		-- A visible seat and dashboard make the scale and rider volume unambiguous.
		{ name = "SeatBase", size = Vector3.new(1.7, 0.45, 1.35),
		  offset = Vector3.new(0, 1.25, 0.55), color = RED },
		{ name = "SeatBack", size = Vector3.new(1.75, 1.65, 0.4),
		  offset = Vector3.new(0, 2.05, 1.15), color = RED },
		{ name = "Dashboard", size = Vector3.new(2.4, 0.45, 0.5),
		  offset = Vector3.new(0, 1.85, -0.45), color = DARK, material = Enum.Material.Metal },

		-- Glass occupies only the upper half of the cockpit: the solid lower pod
		-- hides the avatar's legs while the head and shoulders remain visible.
		{ name = "Canopy", size = Vector3.new(4.25, 2.35, 3.35), shape = "Ball",
		  offset = Vector3.new(0, 3.08, 0.25), color = GLASS,
		  material = Enum.Material.Glass, transparency = 0.62 },
		{ name = "CanopyRailTop", size = Vector3.new(0.4, 0.32, 3.55),
		  offset = Vector3.new(0, 4.0, 0.3), color = YELLOW, material = Enum.Material.Metal },
		{ name = "CanopyRailLeft", size = Vector3.new(0.28, 2.15, 0.35),
		  offset = Vector3.new(-2.12, 2.65, 0.35), color = YELLOW, material = Enum.Material.Metal },
		{ name = "CanopyRailRight", size = Vector3.new(0.28, 2.15, 0.35),
		  offset = Vector3.new(2.12, 2.65, 0.35), color = YELLOW, material = Enum.Material.Metal },

		{ name = "TeamColour", size = Vector3.new(1.1, 0.22, 1.0),
		  offset = Vector3.new(0, 4.18, 0.55), color = WHITE },

		-- Four cylindrical hover-wheel pods are visual only: no constraints, motors
		-- or wheel physics. Yellow hubs keep them readable from the game camera.
		{ name = "HoverWheelFrontLeft", size = Vector3.new(0.52, 1.18, 1.18), shape = "Cylinder",
		  offset = Vector3.new(-2.35, 0.58, -1.15), color = DARK },
		{ name = "HoverWheelRearLeft", size = Vector3.new(0.52, 1.18, 1.18), shape = "Cylinder",
		  offset = Vector3.new(-2.35, 0.58, 1.15), color = DARK },
		{ name = "HoverWheelFrontRight", size = Vector3.new(0.52, 1.18, 1.18), shape = "Cylinder",
		  offset = Vector3.new(2.35, 0.58, -1.15), color = DARK },
		{ name = "HoverWheelRearRight", size = Vector3.new(0.52, 1.18, 1.18), shape = "Cylinder",
		  offset = Vector3.new(2.35, 0.58, 1.15), color = DARK },
		{ name = "WheelHubFrontLeft", size = Vector3.new(0.56, 0.58, 0.58), shape = "Cylinder",
		  offset = Vector3.new(-2.64, 0.58, -1.15), color = YELLOW, material = Enum.Material.Metal },
		{ name = "WheelHubRearLeft", size = Vector3.new(0.56, 0.58, 0.58), shape = "Cylinder",
		  offset = Vector3.new(-2.64, 0.58, 1.15), color = YELLOW, material = Enum.Material.Metal },
		{ name = "WheelHubFrontRight", size = Vector3.new(0.56, 0.58, 0.58), shape = "Cylinder",
		  offset = Vector3.new(2.64, 0.58, -1.15), color = YELLOW, material = Enum.Material.Metal },
		{ name = "WheelHubRearRight", size = Vector3.new(0.56, 0.58, 0.58), shape = "Cylinder",
		  offset = Vector3.new(2.64, 0.58, 1.15), color = YELLOW, material = Enum.Material.Metal },

		-- Standard has one conspicuous side socket for a plug-in module.
		{ name = "UpgradePort", size = Vector3.new(0.35, 1.25, 1.25), shape = "Cylinder",
		  offset = Vector3.new(2.5, 1.85, 0.95), color = METAL, material = Enum.Material.Metal },
		{ name = "UpgradePortCore", size = Vector3.new(0.38, 0.76, 0.76), shape = "Cylinder",
		  offset = Vector3.new(2.7, 1.85, 0.95), color = PORT, material = Enum.Material.Neon },
	},
}
