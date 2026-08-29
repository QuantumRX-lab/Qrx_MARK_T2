--!strict
-- Client-side measurement for the Build 2 permanent HUD budget.

local Players = game:GetService("Players")

local HudConformance = {}

type Check = { name: string, passed: boolean, detail: string? }

local function add(results: { Check }, name: string, passed: boolean, detail: string?)
	table.insert(results, { name = name, passed = passed, detail = detail })
end

local function overlap(a: GuiObject, b: GuiObject): boolean
	local ap, as = a.AbsolutePosition, a.AbsoluteSize
	local bp, bs = b.AbsolutePosition, b.AbsoluteSize
	return ap.X < bp.X + bs.X and bp.X < ap.X + as.X
		and ap.Y < bp.Y + bs.Y and bp.Y < ap.Y + as.Y
end

function HudConformance.checkAll(): { Check }
	local results: { Check } = {}
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:WaitForChild("ChompHud") :: ScreenGui
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1, 1)
	local permanent: { GuiObject } = {}
	local summedArea = 0

	for _, child in gui:GetChildren() do
		if child:IsA("GuiObject") and child.Visible and child:GetAttribute("HudPermanent") == true then
			table.insert(permanent, child)
			summedArea += child.AbsoluteSize.X * child.AbsoluteSize.Y
		end
	end

	local safeArea = viewport.X * math.max(1, viewport.Y - 68)
	local fraction = summedArea / safeArea
	add(results, "area.permanent", fraction <= 0.30,
		string.format("%.1f%% occupied; maximum 30%%", fraction * 100))
	add(results, "area.playfield", 1 - fraction >= 0.70,
		string.format("%.1f%% unobstructed; minimum 70%%", (1 - fraction) * 100))

	for i = 1, #permanent do
		for j = i + 1, #permanent do
			add(results, "overlap." .. permanent[i].Name .. "." .. permanent[j].Name,
				not overlap(permanent[i], permanent[j]))
		end
	end

	return results
end

function HudConformance.report(results: { Check }?): boolean
	results = results or HudConformance.checkAll()
	local allPassed = true
	for _, check in results do
		if check.passed then
			print("  PASS  " .. check.name)
		else
			allPassed = false
			warn("  FAIL  " .. check.name .. (check.detail and ("  " .. check.detail) or ""))
		end
	end
	print(allPassed and "HUD CONFORMANCE: PASS" or "HUD CONFORMANCE: FAIL")
	return allPassed
end

return HudConformance
