--!strict

-- The place must not inherit whatever daylight happened to be saved in a
-- Studio template. This restrained night rig gives neon a job while keeping
-- masonry and the floor readable on the iPad reference display.

local Lighting = game:GetService("Lighting")

Lighting.ClockTime = 0
Lighting.Brightness = 2
Lighting.Ambient = Color3.fromRGB(82, 68, 108)
Lighting.OutdoorAmbient = Color3.fromRGB(96, 84, 124)
Lighting.ColorShift_Top = Color3.fromRGB(22, 10, 34)
Lighting.ColorShift_Bottom = Color3.fromRGB(8, 18, 28)
Lighting.EnvironmentDiffuseScale = 0.45
Lighting.EnvironmentSpecularScale = 0.7
Lighting.GlobalShadows = true
Lighting.ShadowSoftness = 0.35
Lighting.ExposureCompensation = 0.2

local function effect(className: string, name: string): Instance
	local found = Lighting:FindFirstChild(name)
	if found then return found end
	local created = Instance.new(className)
	created.Name = name
	created.Parent = Lighting
	return created
end

local atmosphere = effect("Atmosphere", "ChompAtmosphere") :: Atmosphere
atmosphere.Density = 0.2
atmosphere.Offset = 0.05
atmosphere.Color = Color3.fromRGB(154, 132, 188)
atmosphere.Decay = Color3.fromRGB(48, 34, 70)
atmosphere.Glare = 0
atmosphere.Haze = 0.7

local bloom = effect("BloomEffect", "ChompBloom") :: BloomEffect
bloom.Intensity = 0.65
bloom.Size = 20
bloom.Threshold = 1.05

local grade = effect("ColorCorrectionEffect", "ChompGrade") :: ColorCorrectionEffect
grade.Brightness = 0.04
grade.Contrast = 0.14
grade.Saturation = 0.08
grade.TintColor = Color3.fromRGB(244, 238, 255)

print("[WorldLook] midnight contrast rig active")
