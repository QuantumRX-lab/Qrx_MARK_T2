--!strict

-- Produces a visually distinct, contract-compatible chassis from Standard.
-- Geometry remains inside the proven vehicle envelope while colour, armour and
-- upgrade ports communicate the tier until bespoke silhouettes replace these.

local Standard = require(script.Parent:WaitForChild("Standard"))

return function(id: string, body: Color3, accent: Color3, portCount: number)
	local spec = table.clone(Standard)
	spec.chassisId = id
	spec.parts = {}
	for _, source in Standard.parts do
		local p = table.clone(source)
		if p.name == "BodyShell" or p.name == "RearShell" or string.find(p.name, "Mouth") then
			if p.name ~= "MouthInterior" then p.color = body end
		elseif string.find(p.name, "WheelHub") or p.name == "TeamColour" then
			p.color = accent
		end
		table.insert(spec.parts, p)
	end
	local portOffsets = {
		Vector3.new(-2.5, 1.5, 0.9),
		Vector3.new(-2.5, 2.2, 0.9),
		Vector3.new(-2.5, 2.9, 0.9),
	}
	for i = 2, portCount do
		table.insert(spec.parts, {
			name = "UpgradePort" .. tostring(i), size = Vector3.new(0.35, 1.0, 1.0),
			shape = "Cylinder", offset = portOffsets[i - 1],
			color = accent, material = Enum.Material.Neon,
		})
	end
	return spec
end
