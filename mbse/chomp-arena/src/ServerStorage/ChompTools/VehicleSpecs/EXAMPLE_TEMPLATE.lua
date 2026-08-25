--!strict
--[[
	EXAMPLE_TEMPLATE — a worked chassis spec. Copy it, rename it to the chassis
	id, and change the shapes. Delete this file once real specs exist.

	COORDINATES: the model is built at the origin facing -Z.
	  -Z is FORWARD (where the mouth goes)      +Z is BACK
	  +Y is UP                                   -Y is DOWN
	  +X is RIGHT                                -X is LEFT

	The mouth must sit at NEGATIVE Z. The factory refuses to build it otherwise,
	because a backwards vehicle does not look wrong — it inverts combat.

	DO NOT put BaseSpeed, BaseTurn, Tier, BarCapacity, Power or MouthArcDegrees
	in here. The factory reads those from ChompConfig, so a model can never
	disagree with the numbers the game uses (D-CHOMP-019).
]]

local YELLOW = Color3.fromRGB(255, 205, 40)
local DARK = Color3.fromRGB(30, 28, 24)
local WHITE = Color3.fromRGB(245, 245, 245)

return {
	chassisId = "Standard",
	triangleCount = 0,          -- basic parts only; declare a real figure for meshes

	parts = {
		-- The chassis is the PrimaryPart and the only colliding part.
		{ name = "Chassis",      size = Vector3.new(4.0, 0.8, 4.6), offset = Vector3.new(0, 0.2, 0),
		  color = YELLOW, collide = true },

		{ name = "BodyShell",    size = Vector3.new(4.4, 2.2, 4.2), offset = Vector3.new(0, 1.0, 0.4),
		  shape = "Ball", color = YELLOW },

		-- The mouth: a wedge above and a wedge below, opening forward.
		-- Together these must be at least 30% of the frontal silhouette, and
		-- must read as directional in greyscale (RISK-CHOMP-001).
		{ name = "MouthUpper",   class = "WedgePart", size = Vector3.new(3.6, 1.1, 2.0),
		  offset = Vector3.new(0, 1.6, -1.6), rotation = Vector3.new(0, 180, 0), color = YELLOW },
		{ name = "MouthLower",   class = "WedgePart", size = Vector3.new(3.6, 1.1, 2.0),
		  offset = Vector3.new(0, 0.5, -1.6), rotation = Vector3.new(180, 180, 0), color = YELLOW },

		-- Dark interior so the open mouth reads as a hole, not a notch.
		{ name = "MouthInterior", size = Vector3.new(3.2, 1.0, 1.2), offset = Vector3.new(0, 1.05, -1.2),
		  color = DARK },

		-- Exactly one part named TeamColour, recoloured at runtime.
		{ name = "TeamColour",   size = Vector3.new(3.0, 0.5, 1.6), offset = Vector3.new(0, 2.0, 0.9),
		  color = WHITE },

		{ name = "EyeLeft",      size = Vector3.new(0.6, 0.6, 0.6), shape = "Ball",
		  offset = Vector3.new(-0.9, 2.0, -0.4), color = DARK },
		{ name = "EyeRight",     size = Vector3.new(0.6, 0.6, 0.6), shape = "Ball",
		  offset = Vector3.new(0.9, 2.0, -0.4), color = DARK },

		{ name = "SkidLeft",     size = Vector3.new(0.5, 0.5, 2.4), offset = Vector3.new(-1.6, -0.1, 0.2),
		  color = DARK },
		{ name = "SkidRight",    size = Vector3.new(0.5, 0.5, 2.4), offset = Vector3.new(1.6, -0.1, 0.2),
		  color = DARK },
	},
}
