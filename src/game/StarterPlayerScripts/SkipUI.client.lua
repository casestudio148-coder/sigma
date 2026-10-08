-- StarterPlayer.StarterPlayerScripts.SkipUI (LocalScript)
-- Кнопка «Skip» под панелью волн + окошко голосования Accept / Decline.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))
local skipEvent = ReplicatedStorage:WaitForChild("SkipVote")
local new, corner, stroke = UIKit.new, UIKit.corner, UIKit.stroke
local text, icon, rgb = UIKit.text, UIKit.icon, UIKit.rgb

local WHITE = Color3.new(1, 1, 1)

local gui = new("ScreenGui", {
	Name = "SkipGui",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 5,
	Enabled = false,
}, player:WaitForChild("PlayerGui"))

---------------------------------------------------------------- кнопка Skip

local skip = UIKit.button(gui, {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 74),
	Size = UDim2.fromOffset(190, 46),
	Color = "cyan",
	Icon = "skip",
	IconSize = 32,
	Text = "SKIP WAVE",
	Font = UIKit.Font.Title,
	TextSize = 20,
	Radius = 23,
	Depth = 4,
	Visible = false,
})
local skipBtn = skip.Button

skipBtn.MouseButton1Click:Connect(function()
	if skipBtn.Active then
		skipEvent:FireServer("start")
	end
end)

---------------------------------------------------------------- окно голосования

local card = UIKit.panel(gui, {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 74),
	Size = UDim2.fromOffset(360, 132),
	Visible = false,
}, rgb(120, 205, 255), rgb(60, 80, 220), { Radius = 20, GlossHeight = 22 })

local titleRow = new("Frame", {
	Position = UDim2.fromOffset(0, 8),
	Size = UDim2.new(1, 0, 0, 30),
	BackgroundTransparency = 1,
}, card)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	Padding = UDim.new(0, 6),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, titleRow)
icon(titleRow, "skip", { Size = UDim2.fromOffset(28, 28), LayoutOrder = 1 })
local titleLabel = text(titleRow, {
	AutomaticSize = Enum.AutomaticSize.X,
	Size = UDim2.new(0, 0, 1, 0),
	TextSize = 18,
	LayoutOrder = 2,
})
local countLabel = text(card, {
	Position = UDim2.fromOffset(0, 38),
	Size = UDim2.new(1, 0, 0, 20),
	TextSize = 15,
	TextColor3 = rgb(235, 240, 255),
})

local accept = UIKit.button(card, {
	Position = UDim2.new(0, 14, 0, 62),
	Size = UDim2.new(0.5, -20, 0, 46),
	Color = "green",
	Icon = "check",
	IconSize = 30,
	Text = "YES",
	Font = UIKit.Font.Title,
	TextSize = 20,
	Depth = 4,
})
local decline = UIKit.button(card, {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -14, 0, 62),
	Size = UDim2.new(0.5, -20, 0, 46),
	Color = "red",
	Icon = "close",
	IconSize = 30,
	Text = "NO",
	Font = UIKit.Font.Title,
	TextSize = 20,
	Depth = 4,
})

local waitRow = new("Frame", {
	Position = UDim2.fromOffset(0, 64),
	Size = UDim2.new(1, 0, 0, 40),
	BackgroundTransparency = 1,
}, card)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	Padding = UDim.new(0, 6),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, waitRow)
local hourglass = icon(waitRow, "hourglass", { Size = UDim2.fromOffset(30, 30), LayoutOrder = 1 })
UIKit.wobble(hourglass, 12, 0.6)
text(waitRow, {
	AutomaticSize = Enum.AutomaticSize.X,
	Size = UDim2.new(0, 0, 1, 0),
	TextSize = 17,
	Text = "Waiting for others...",
	LayoutOrder = 2,
})

local timerBar = UIKit.bar(card, {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -8),
	Size = UDim2.new(1, -36, 0, 12),
}, rgb(255, 240, 120), rgb(255, 160, 20))

accept.Button.MouseButton1Click:Connect(function()
	skipEvent:FireServer("yes")
end)
decline.Button.MouseButton1Click:Connect(function()
	skipEvent:FireServer("no")
end)

---------------------------------------------------------------- обновление

local wasCard = false
RunService.Heartbeat:Connect(function()
	gui.Enabled = workspace:GetAttribute("Phase") == "Playing"
	if not gui.Enabled then return end

	local canSkip = workspace:GetAttribute("CanSkip") == true
	local active = workspace:GetAttribute("SkipVoteActive") == true
	local now = workspace:GetServerTimeNow()
	local cooldownLeft = (workspace:GetAttribute("SkipCooldownUntil") or 0) - now

	card.Visible = active and canSkip
	skipBtn.Visible = canSkip and not active
	if card.Visible and not wasCard then
		UIKit.pop(card, 0.5, 0.35)
	end
	wasCard = card.Visible

	if skipBtn.Visible then
		if cooldownLeft > 0 then
			skip.setText("SKIP  " .. math.ceil(cooldownLeft) .. "s")
			skip.setColor("grey")
			skipBtn.Active = false
		else
			skip.setText("SKIP WAVE")
			skip.setColor("cyan")
			skipBtn.Active = true
		end
	end

	if card.Visible then
		local starter = Players:GetPlayerByUserId(workspace:GetAttribute("SkipVoteStarter") or 0)
		titleLabel.Text = (starter and starter.DisplayName or "Someone") .. " wants to skip!"
		countLabel.Text = string.format("%d / %d said yes", workspace:GetAttribute("SkipYes") or 0, workspace:GetAttribute("SkipTotal") or 1)

		local voted = player:GetAttribute("SkipChoice") ~= nil
		accept.Button.Visible = not voted
		decline.Button.Visible = not voted
		waitRow.Visible = voted

		local endsAt = workspace:GetAttribute("SkipVoteEndsAt") or now
		local duration = workspace:GetAttribute("SkipVoteTime") or 8
		timerBar.set(math.clamp((endsAt - now) / duration, 0, 1), 0.05)
	end
end)
