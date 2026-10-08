-- StarterPlayer.StarterPlayerScripts.ReturnUI (LocalScript) — ТОЛЬКО В МЕСТЕ С КАРТОЙ МАТЧА
-- После матча внизу экрана: отсчёт до возвращения в хаб, кнопки PLAY AGAIN и LOBBY.
-- Плюс экран телепорта и подсказки от сервера (MatchLink).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))
local MapConfig = require(ReplicatedStorage:WaitForChild("MapConfig"))

local new, text, rgb = UIKit.new, UIKit.text, UIKit.rgb
local WHITE = Color3.new(1, 1, 1)

local voteRemote = ReplicatedStorage:WaitForChild("MatchVote", 30)
local notifyRemote = ReplicatedStorage:WaitForChild("HubNotify", 30)
if not voteRemote then
	warn("[ReturnUI] нет MatchLink на сервере — кнопки возврата в лобби не появятся")
	return
end

local gui = new("ScreenGui", {
	Name = "ReturnGui",
	ResetOnSpawn = false,
	DisplayOrder = 35, -- поверх экрана победы / поражения
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

local function toast(msg, kind)
	UIKit.toast(gui, msg, {
		Color = kind == "error" and rgb(255, 180, 185) or WHITE,
		Icon = kind == "error" and "warning" or "flag",
		Time = 3.2,
		Y = 70,
	})
end
if notifyRemote then
	notifyRemote.OnClientEvent:Connect(function(msg, kind)
		if typeof(msg) == "string" then toast(msg, kind) end
	end)
end

---------------------------------------------------------------- панель

local holder = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -16),
	Size = UDim2.fromOffset(560, 128),
	BackgroundTransparency = 1,
	Visible = false,
}, gui)
UIKit.fitScale(new("UIScale", {}, holder), 820, 0.55, 1)

local panel = UIKit.panel(holder, {
	Size = UDim2.fromScale(1, 1),
}, rgb(110, 90, 200), rgb(45, 30, 110), { Radius = 22, OutlineThickness = 5, GlossHeight = 28 })

local title = text(panel, {
	Position = UDim2.fromOffset(18, 12),
	Size = UDim2.fromOffset(260, 32),
	Font = UIKit.Font.Title,
	TextSize = 28,
	Text = "BACK TO LOBBY IN 30",
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = rgb(255, 230, 120),
	ZIndex = 3,
})
local sub = text(panel, {
	Position = UDim2.fromOffset(18, 50),
	Size = UDim2.fromOffset(260, 24),
	TextSize = 18,
	Text = "Play again: 0/1",
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = rgb(225, 220, 255),
	ZIndex = 3,
})
local hint = text(panel, {
	Position = UDim2.fromOffset(18, 82),
	Size = UDim2.fromOffset(260, 22),
	TextSize = 16,
	Text = "Same team, same map!",
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = rgb(200, 195, 240),
	ZIndex = 3,
})

local replayBtn = UIKit.button(panel, {
	Name = "Replay",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -150, 0.5, 0),
	Size = UDim2.fromOffset(130, 64),
	Color = "green",
	Text = "PLAY<br/>AGAIN",
	Font = UIKit.Font.Title,
	TextSize = 22,
	ZIndex = 4,
})
local lobbyBtn = UIKit.button(panel, {
	Name = "Lobby",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -14, 0.5, 0),
	Size = UDim2.fromOffset(124, 64),
	Color = "blue",
	Text = "LOBBY",
	Icon = "flag",
	IconSize = 30,
	Font = UIKit.Font.Title,
	TextSize = 22,
	ZIndex = 4,
})

replayBtn.Button.MouseButton1Click:Connect(function()
	voteRemote:FireServer("replay")
	UIKit.pop(replayBtn.Button, 0.85, 0.25)
end)
lobbyBtn.Button.MouseButton1Click:Connect(function()
	voteRemote:FireServer("lobby")
	UIKit.pop(lobbyBtn.Button, 0.85, 0.25)
end)

---------------------------------------------------------------- экран телепорта

local function makeScreen(kind)
	local d = MapConfig.get(workspace:GetAttribute("MapId")) or MapConfig[MapConfig.Default]
	local sg = new("ScreenGui", { Name = "MatchTeleport", IgnoreGuiInset = true, DisplayOrder = 100, ResetOnSpawn = false })
	local bg = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, sg)
	local top = kind == "replay" and d.Color:Lerp(rgb(30, 20, 70), 0.35) or rgb(90, 150, 255)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(top, rgb(14, 8, 34)) }, bg)
	local box = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.48),
		Size = UDim2.fromOffset(600, 240),
		BackgroundTransparency = 1,
	}, bg)
	UIKit.fitScale(new("UIScale", {}, box), 760, 0.5, 1)
	UIKit.rays(box, WHITE, 700, 16, { Position = UDim2.fromScale(0.5, 0.35), ImageTransparency = 0.7 })
	UIKit.title(box, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.32),
		Size = UDim2.new(1, 0, 0, 70),
		TextSize = 60,
		Text = kind == "replay" and string.upper(d.Name) or "LOBBY",
		ZIndex = 2,
	})
	text(box, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.68),
		Size = UDim2.new(1, 0, 0, 34),
		TextSize = 30,
		Text = kind == "replay" and "Starting a new battle..." or kind == "redirect" and "Loading the lobby..." or "Going back to the lobby...",
		ZIndex = 2,
	})
	return sg
end

local screen = nil
local function refreshTeleport()
	local kind = player:GetAttribute("Teleporting")
	if kind and not screen then
		screen = makeScreen(kind)
		pcall(function()
			TeleportService:SetTeleportGui(makeScreen(kind))
		end)
		screen.Parent = playerGui
	elseif not kind and screen then
		screen:Destroy()
		screen = nil
	end
end
player:GetAttributeChangedSignal("Teleporting"):Connect(refreshTeleport)

---------------------------------------------------------------- обновление

task.spawn(function()
	while true do
		local returnAt = workspace:GetAttribute("ReturnAt")
		holder.Visible = returnAt ~= nil and player:GetAttribute("Teleporting") == nil
		if holder.Visible then
			local left = math.max(0, math.ceil(returnAt - workspace:GetServerTimeNow()))
			local mine = player:GetAttribute("WantsReplay") == true
			title.Text = (mine and "NEW BATTLE IN " or "BACK TO LOBBY IN ") .. left
			sub.Text = string.format("Play again: %d/%d", workspace:GetAttribute("ReplayVotes") or 0, workspace:GetAttribute("ReplayTotal") or #Players:GetPlayers())
			replayBtn.setText(mine and "CANCEL" or "PLAY<br/>AGAIN")
			replayBtn.setColor(mine and "grey" or "green")
			hint.Text = workspace:GetAttribute("CanReturn") == false and "Lobby works in the published game" or "Same team, same map!"
		end
		task.wait(0.2)
	end
end)
