-- StarterPlayer.StarterPlayerScripts.HubClient (LocalScript) — ТОЛЬКО В МЕСТЕ-ХАБЕ
-- Игрок в хабе:
--   • E у магазина / храма / доски квестов / подарка / ящика кодов / знамени → открывает нужное окно меню
--   • кнопка PLAY → выбрать карту → тебя переносит в круг её портала (сложность выбирают уже в матче)
--   • панель отряда: сколько игроков, отсчёт, START (для лидера) и LEAVE
--   • экран телепорта, подсказки
--   • в мире всё живое: кристалл и осколки, сундуки, подарок, мельница, лодка, облака

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TeleportService = game:GetService("TeleportService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))
local MapConfig = require(ReplicatedStorage:WaitForChild("MapConfig"))
local PlaceConfig = require(ReplicatedStorage:WaitForChild("PlaceConfig"))

local new, corner, stroke, tween, text, icon, rgb = UIKit.new, UIKit.corner, UIKit.stroke, UIKit.tween, UIKit.text, UIKit.icon, UIKit.rgb
local WHITE = Color3.new(1, 1, 1)
local INK = UIKit.C.Ink
local function mapOf(id) return MapConfig.get(id) or MapConfig[MapConfig.Default] end

---------------------------------------------------------------- шина меню: E у предмета → окно меню

local function getBus()
	local holder = player:WaitForChild("PlayerScripts")
	local bus = holder:FindFirstChild("MenuBus")
	if not bus then
		bus = Instance.new("BindableEvent")
		bus.Name = "MenuBus"
		bus.Parent = holder
	end
	return bus
end
local bus = getBus()

ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
	if who ~= player then return end
	local id = prompt:GetAttribute("MenuId")
	if typeof(id) == "string" then
		bus:Fire(id)
	end
end)

---------------------------------------------------------------- интерфейс

local gui = new("ScreenGui", {
	Name = "HubGui",
	ResetOnSpawn = false,
	DisplayOrder = 5,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

local function toast(msg, kind)
	UIKit.toast(gui, msg, {
		Color = kind == "error" and rgb(255, 180, 185) or WHITE,
		Icon = kind == "error" and "warning" or "flag",
		Time = 3.2,
		Y = 90,
	})
end

local notifyRemote = ReplicatedStorage:WaitForChild("HubNotify", 20)
local actionRemote = ReplicatedStorage:WaitForChild("HubAction", 20)
if notifyRemote then
	notifyRemote.OnClientEvent:Connect(function(msg, kind)
		if typeof(msg) == "string" then toast(msg, kind) end
	end)
else
	warn("[HubClient] нет HubService на сервере — порталы работать не будут")
end

-- всё нижнее меню в одной рамке, подгоняется под размер экрана
local bottom = new("Frame", {
	Name = "Bottom",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -18),
	Size = UDim2.fromOffset(560, 300),
	BackgroundTransparency = 1,
}, gui)
UIKit.fitScale(new("UIScale", {}, bottom), 820, 0.55, 1)

-- кнопка PLAY
local play = UIKit.button(bottom, {
	Name = "Play",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, 0),
	Size = UDim2.fromOffset(240, 78),
	Color = "green",
	Text = "PLAY",
	Icon = "swords",
	IconSize = 46,
	Font = UIKit.Font.Title,
	TextSize = 40,
	Radius = 22,
	Depth = 7,
})
UIKit.pulse(new("UIScale", {}, play.Face), 1.04, 0.7)

-- выбор карты
local picker = UIKit.panel(bottom, {
	Name = "Picker",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -92),
	Size = UDim2.fromOffset(560, 278),
	Visible = false,
}, rgb(120, 205, 255), rgb(60, 95, 235), { Radius = 22, OutlineThickness = 5, GlossHeight = 36 })
text(picker, {
	Position = UDim2.fromOffset(0, 8),
	Size = UDim2.new(1, 0, 0, 34),
	Text = "CHOOSE A MAP — PLAY NOW!",
	Font = UIKit.Font.Title,
	TextSize = 30,
})
local pickRow = new("Frame", {
	Position = UDim2.fromOffset(14, 50),
	Size = UDim2.new(1, -28, 0, 214),
	BackgroundTransparency = 1,
}, picker)
new("UIGridLayout", {
	CellSize = UDim2.new(0.5, -5, 0, 47),
	CellPadding = UDim2.fromOffset(10, 8),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, pickRow)

---------------------------------------------------------------- панель отряда

local queuePanel = UIKit.panel(bottom, {
	Name = "Queue",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, 0),
	Size = UDim2.fromOffset(520, 150),
	Visible = false,
}, rgb(110, 90, 200), rgb(45, 30, 110), { Radius = 22, OutlineThickness = 5, GlossHeight = 30 })
local qIcon = icon(queuePanel, "swords", {
	Position = UDim2.fromOffset(14, 10),
	Size = UDim2.fromOffset(56, 56),
	ZIndex = 3,
	Visible = UIKit.IconsReady,
})
local qTitle = UIKit.title(queuePanel, {
	Position = UDim2.fromOffset(UIKit.IconsReady and 78 or 18, 12),
	Size = UDim2.fromOffset(230, 46),
	TextSize = 40,
	Text = "EASY",
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 3,
})
local qTier = text(queuePanel, {
	Name = "Tier",
	Position = UDim2.fromOffset(20, -26),
	Size = UDim2.fromOffset(300, 24),
	TextSize = 22,
	Font = UIKit.Font.Title,
	Text = "",
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 3,
})
local qPlayers = text(queuePanel, {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -18, 0, 14),
	Size = UDim2.fromOffset(200, 26),
	TextSize = 22,
	Text = "PLAYERS 1/4",
	TextXAlignment = Enum.TextXAlignment.Right,
	ZIndex = 3,
})
-- точки игроков
local dotsRow = new("Frame", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -18, 0, 44),
	Size = UDim2.fromOffset(200, 22),
	BackgroundTransparency = 1,
	ZIndex = 3,
}, queuePanel)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Right,
	Padding = UDim.new(0, 6),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, dotsRow)
local dots = {}
for i = 1, math.max(1, PlaceConfig.MaxParty) do
	local d = new("Frame", {
		Size = UDim2.fromOffset(22, 22),
		BackgroundColor3 = rgb(60, 50, 110),
		BorderSizePixel = 0,
		LayoutOrder = i,
		ZIndex = 3,
	}, dotsRow)
	corner(d, 11)
	stroke(d, INK, 2.5)
	dots[i] = d
end
local qTimer = text(queuePanel, {
	Position = UDim2.fromOffset(18, 70),
	Size = UDim2.fromOffset(222, 30),
	TextSize = 26,
	Font = UIKit.Font.Title,
	Text = "STARTING IN 15",
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = rgb(255, 230, 120),
	ZIndex = 3,
})
local qHint = text(queuePanel, {
	Position = UDim2.fromOffset(18, 104),
	Size = UDim2.fromOffset(222, 22),
	TextSize = 16,
	TextScaled = true,
	Text = "Friends can join the circle!",
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = rgb(225, 220, 255),
	ZIndex = 3,
})
new("UITextSizeConstraint", { MaxTextSize = 16 }, qHint)
local startBtn = UIKit.button(queuePanel, {
	Name = "Start",
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -150, 1, -14),
	Size = UDim2.fromOffset(120, 58),
	Color = "yellow",
	Text = "START",
	Font = UIKit.Font.Title,
	TextSize = 26,
	ZIndex = 4,
})
local leaveBtn = UIKit.button(queuePanel, {
	Name = "Leave",
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -16, 1, -14),
	Size = UDim2.fromOffset(124, 58),
	Color = "red",
	Text = "LEAVE",
	Font = UIKit.Font.Title,
	TextSize = 26,
	ZIndex = 4,
	Shine = false,
})

---------------------------------------------------------------- экран телепорта

local function makeTeleportScreen(id)
	local d = mapOf(id)
	local sg = new("ScreenGui", { Name = "HubTeleport", IgnoreGuiInset = true, DisplayOrder = 100, ResetOnSpawn = false })
	local bg = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, sg)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(d.Color:Lerp(rgb(30, 20, 70), 0.35), rgb(14, 8, 34)) }, bg)
	local holder = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.48),
		Size = UDim2.fromOffset(600, 260),
		BackgroundTransparency = 1,
	}, bg)
	UIKit.fitScale(new("UIScale", {}, holder), 760, 0.5, 1)
	UIKit.rays(holder, d.Color:Lerp(WHITE, 0.4), 700, 18, { Position = UDim2.fromScale(0.5, 0.35), ImageTransparency = 0.55 })
	local ic = icon(holder, d.Icon or "swords", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.25),
		Size = UDim2.fromOffset(110, 110),
		Visible = UIKit.IconsReady,
		ZIndex = 2,
	})
	UIKit.wobble(ic, 8, 0.8)
	UIKit.title(holder, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 0, 0, 70),
		TextSize = 64,
		Text = string.upper(d.Name),
		Colors = { d.Color:Lerp(WHITE, 0.7), d.Color:Lerp(WHITE, 0.2) },
		ZIndex = 2,
	})
	text(holder, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.79),
		Size = UDim2.new(1, 0, 0, 30),
		TextSize = 26,
		Text = d.Tagline or "",
		TextColor3 = d.Color:Lerp(WHITE, 0.6),
		ZIndex = 2,
	})
	text(holder, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.94),
		Size = UDim2.new(1, 0, 0, 30),
		TextSize = 26,
		Text = "MAP LEVEL: " .. MapConfig.tier(id).Name .. "   •   Teleporting...",
		ZIndex = 2,
	})
	return sg
end

local tpScreen = nil
local function showTeleport(id)
	if tpScreen then return end
	tpScreen = makeTeleportScreen(id)
	pcall(function()
		TeleportService:SetTeleportGui(makeTeleportScreen(id))
	end)
	tpScreen.Parent = playerGui
	local bg = tpScreen:FindFirstChildOfClass("Frame")
	if bg then
		bg.BackgroundTransparency = 1
		tween(bg, 0.4, { BackgroundTransparency = 0 })
	end
end
local function hideTeleport()
	if tpScreen then
		tpScreen:Destroy()
		tpScreen = nil
	end
end

---------------------------------------------------------------- PLAY → перенос в круг портала

local hub = workspace:WaitForChild("Hub", 60)

local function portalModel(id)
	local portals = hub and hub:FindFirstChild("Portals")
	return portals and portals:FindFirstChild(id)
end

local flash = new("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = WHITE,
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ZIndex = 50,
	Visible = false,
}, gui)

-- PLAY → карта: сразу в бой (с отрядом, если он есть). Правила проверяет сервер.
local playMap -- задаётся ниже, после интерфейса отряда
local function goToPortal(id)
	local ch = player.Character
	if not (portalModel(id) and ch and ch:FindFirstChild("HumanoidRootPart") and actionRemote) then
		toast("Walk into a portal circle to play!")
		return
	end
	flash.Visible = true
	flash.BackgroundTransparency = 0.1
	actionRemote:FireServer("go", id) -- переносит сервер (так надёжнее)
	local tw = tween(flash, 0.5, { BackgroundTransparency = 1 })
	tw.Completed:Once(function() flash.Visible = false end)
end

for i, id in ipairs(MapConfig.Order) do
	local d = mapOf(id)
	local b = UIKit.button(pickRow, {
		Name = id,
		Color = d.Button or "blue",
		Icon = d.Icon,
		IconSize = 32,
		Text = string.upper(d.Name),
		Font = UIKit.Font.Title,
		TextSize = 21,
		LayoutOrder = i,
		Radius = 14,
	})
	local tier = MapConfig.tier(id)
	text(b.Button, {
		Name = "Tier",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 3),
		Size = UDim2.fromOffset(90, 16),
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = tier.Name,
		TextColor3 = tier.Color:Lerp(WHITE, 0.25),
		ZIndex = 20,
	})
	b.Button.MouseButton1Click:Connect(function()
		picker.Visible = false
		playMap(id)
	end)
end

play.Button.MouseButton1Click:Connect(function()
	picker.Visible = not picker.Visible
	if picker.Visible then
		UIKit.pop(picker, 0.7, 0.3)
	end
end)

startBtn.Button.MouseButton1Click:Connect(function()
	if actionRemote then actionRemote:FireServer("start") end
	UIKit.pop(startBtn.Button, 0.85, 0.25)
end)
leaveBtn.Button.MouseButton1Click:Connect(function()
	if actionRemote then actionRemote:FireServer("leave") end
end)

---------------------------------------------------------------- обновление панели

local lastQueue = nil
local function refresh()
	local id = player:GetAttribute("HubQueue")
	local teleporting = player:GetAttribute("HubTeleporting")
	if teleporting then
		showTeleport(teleporting)
	else
		hideTeleport()
	end

	local model = id and portalModel(id)
	local inQueue = model ~= nil and not teleporting
	queuePanel.Visible = inQueue
	play.Button.Visible = not inQueue and not teleporting
	if inQueue then picker.Visible = false end
	if not inQueue then
		lastQueue = nil
		return
	end

	local d = mapOf(id)
	if lastQueue ~= id then
		lastQueue = id
		local pal = UIKit.Palette[d.Button or "blue"]
		local grad = queuePanel:FindFirstChildOfClass("UIGradient")
		if grad and pal then
			grad.Color = ColorSequence.new(pal[1]:Lerp(rgb(40, 30, 90), 0.35), pal[3]:Lerp(rgb(20, 12, 50), 0.4))
		end
		UIKit.setIcon(qIcon, d.Icon or "swords")
		qTitle.Text = string.upper(d.Name or id)
		local tier = MapConfig.tier(id)
		qTier.Text = "MAP LEVEL: " .. tier.Name
		qTier.TextColor3 = tier.Color:Lerp(WHITE, 0.2)
		UIKit.pop(queuePanel, 0.6, 0.35)
	end

	local count = model:GetAttribute("Count") or 0
	local max = model:GetAttribute("Max") or PlaceConfig.MaxParty
	local endsAt = model:GetAttribute("EndsAt") or 0
	local state = model:GetAttribute("State")
	local leader = (model:GetAttribute("Leader") or 0) == player.UserId
	qPlayers.Text = string.format("PLAYERS %d/%d", count, max)
	for i, dot in ipairs(dots) do
		dot.Visible = i <= max
		dot.BackgroundColor3 = i <= count and rgb(120, 255, 140) or rgb(60, 50, 110)
	end
	if state == "teleporting" then
		qTimer.Text = "TELEPORTING..."
	else
		local left = math.max(0, math.ceil(endsAt - workspace:GetServerTimeNow()))
		qTimer.Text = endsAt > 0 and ("STARTING IN " .. left) or "WAITING..."
	end
	startBtn.Button.Visible = leader and state ~= "teleporting"
	qHint.Text = leader and "You lead! START or wait for friends" or "Friends can join the circle!"
end

player:GetAttributeChangedSignal("HubQueue"):Connect(refresh)
player:GetAttributeChangedSignal("HubTeleporting"):Connect(refresh)
task.spawn(function()
	while true do
		local ok, err = pcall(refresh)
		if not ok then warn("[HubClient] " .. tostring(err)) end
		task.wait(0.2)
	end
end)

---------------------------------------------------------------- отряд (party): друзья играют вместе без портала

local partyRemote = ReplicatedStorage:WaitForChild("HubParty", 20)
local partyData = nil -- { leader = UserId, members = { {id, name, user} }, max }
local invitedAt = {}  -- [UserId] = os.clock() — кого я уже пригласил (кнопка серая)
local PURPLE_TOP, PURPLE_BOTTOM = rgb(205, 165, 255), rgb(115, 60, 230)

local function inParty(userId)
	if not partyData then return false end
	for _, m in ipairs(partyData.members) do
		if m.id == userId then return true end
	end
	return false
end
local function iAmLeader()
	return partyData == nil or partyData.leader == player.UserId
end

-- кнопка PARTY справа от PLAY
local partyBtn = UIKit.button(bottom, {
	Name = "Party",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0.5, 134, 1, -6),
	Size = UDim2.fromOffset(148, 64),
	Color = "purple",
	Text = "PARTY",
	Icon = "crown",
	IconSize = 34,
	Font = UIKit.Font.Title,
	TextSize = 26,
	Radius = 18,
})

-- маленький список отряда над кнопкой
local hud = new("Frame", {
	Name = "PartyHud",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0.5, 134, 1, -80),
	Size = UDim2.fromOffset(160, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	Visible = false,
}, bottom)
new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Bottom }, hud)

local function chip(parent, m, order)
	local f = new("Frame", {
		Size = UDim2.fromOffset(160, 28),
		BackgroundColor3 = rgb(40, 26, 90),
		BackgroundTransparency = 0.15,
		LayoutOrder = order,
	}, parent)
	corner(f, 14)
	stroke(f, INK, 2.5)
	icon(f, m.id == partyData.leader and "crown" or "star", {
		Position = UDim2.fromOffset(4, 2),
		Size = UDim2.fromOffset(24, 24),
		Visible = UIKit.IconsReady,
	})
	text(f, {
		Position = UDim2.fromOffset(32, 0),
		Size = UDim2.new(1, -38, 1, 0),
		TextSize = 17,
		Text = m.name,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextColor3 = m.id == player.UserId and rgb(255, 230, 120) or WHITE,
	})
	return f
end

-- окно отряда
local win = UIKit.window(gui, {
	Name = "PartyWindow",
	Title = "Party",
	Icon = "crown",
	Width = 640,
	Height = 420,
	Theme = { PURPLE_TOP, PURPLE_BOTTOM },
	Ribbon = "pink",
})
win.Root.ZIndex = 20
win.Close.Button.MouseButton1Click:Connect(function() win.hide() end)

local leftWell = UIKit.well(win.Content, { Position = UDim2.fromOffset(0, 30), Size = UDim2.new(0.44, -6, 1, -96) })
local rightWell = UIKit.well(win.Content, { Position = UDim2.new(0.44, 6, 0, 30), Size = UDim2.new(0.56, -6, 1, -96) })
text(win.Content, { Position = UDim2.fromOffset(4, 0), Size = UDim2.new(0.44, -10, 0, 28), Text = "YOUR PARTY", Font = UIKit.Font.Title, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left })
text(win.Content, { Position = UDim2.new(0.44, 10, 0, 0), Size = UDim2.new(0.56, -10, 0, 28), Text = "PLAYERS ON THIS SERVER", Font = UIKit.Font.Title, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left })

local membersList = new("Frame", { Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -16, 1, -16), BackgroundTransparency = 1 }, leftWell)
new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, membersList)
local playersList = new("ScrollingFrame", {
	Position = UDim2.fromOffset(8, 8),
	Size = UDim2.new(1, -16, 1, -16),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 6,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, rightWell)
new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, playersList)

local partyHint = text(win.Content, {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 4, 1, -4),
	Size = UDim2.new(1, -170, 0, 56),
	TextSize = 18,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "",
})
local leaveParty = UIKit.button(win.Content, {
	Name = "LeaveParty",
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, 0, 1, -6),
	Size = UDim2.fromOffset(150, 52),
	Color = "red",
	Text = "LEAVE",
	Font = UIKit.Font.Title,
	TextSize = 24,
	Visible = false,
})
leaveParty.Button.MouseButton1Click:Connect(function()
	if partyRemote then partyRemote:FireServer("leave") end
end)

local function row(parent, order, name, sub, isMe)
	local r = new("Frame", {
		Size = UDim2.new(1, -6, 0, 48),
		BackgroundColor3 = isMe and rgb(70, 50, 150) or rgb(50, 36, 110),
		BackgroundTransparency = 0.2,
		LayoutOrder = order,
	}, parent)
	corner(r, 12)
	stroke(r, INK, 2)
	text(r, {
		Position = UDim2.fromOffset(12, 3),
		Size = UDim2.new(1, -120, 0, 24),
		TextSize = 20,
		Text = name,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextColor3 = isMe and rgb(255, 230, 120) or WHITE,
	})
	text(r, {
		Position = UDim2.fromOffset(12, 25),
		Size = UDim2.new(1, -120, 0, 18),
		TextSize = 14,
		Text = sub or "",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = rgb(200, 190, 240),
	})
	return r
end

local function smallButton(parent, label, color, onClick)
	local b = UIKit.button(parent, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -6, 0.5, 0),
		Size = UDim2.fromOffset(98, 38),
		Color = color,
		Text = label,
		Font = UIKit.Font.Title,
		TextSize = 18,
		Radius = 12,
		Depth = 4,
		Shine = false,
	})
	b.Button.MouseButton1Click:Connect(onClick)
	return b
end

local function rebuildParty()
	for _, c in ipairs(membersList:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
	for _, c in ipairs(playersList:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
	for _, c in ipairs(hud:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end

	local max = (partyData and partyData.max) or PlaceConfig.MaxParty
	-- мой отряд
	if partyData then
		for i, m in ipairs(partyData.members) do
			local lead = m.id == partyData.leader
			local r = row(membersList, i, m.name, lead and "Party leader" or "@" .. (m.user or ""), m.id == player.UserId)
			if iAmLeader() and m.id ~= player.UserId then
				smallButton(r, "KICK", "red", function() partyRemote:FireServer("kick", m.id) end)
			elseif lead then
				icon(r, "crown", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(32, 32), Visible = UIKit.IconsReady })
			end
			chip(hud, m, i)
		end
	else
		row(membersList, 1, player.DisplayName, "Just you — invite friends!", true)
	end
	hud.Visible = partyData ~= nil
	leaveParty.Button.Visible = partyData ~= nil
	partyBtn.setText(partyData and string.format("PARTY %d/%d", #partyData.members, max) or "PARTY")

	-- игроки на сервере
	local order = 0
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player then
			order += 1
			local member = inParty(p.UserId)
			local clan = p:GetAttribute("Clan")
			local r = row(playersList, order, p.DisplayName, (clan and ("[" .. clan .. "] ") or "") .. "@" .. p.Name, false)
			if member then
				text(r, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(98, 30), Text = "IN PARTY", Font = UIKit.Font.Title, TextSize = 16, TextColor3 = rgb(140, 255, 160) })
			elseif not iAmLeader() then
				-- приглашать может только лидер
			elseif partyData and #partyData.members >= max then
				text(r, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(98, 30), Text = "FULL", Font = UIKit.Font.Title, TextSize = 16, TextColor3 = rgb(255, 170, 170) })
			else
				local recent = invitedAt[p.UserId] and os.clock() - invitedAt[p.UserId] < 30
				local b
				b = smallButton(r, recent and "SENT" or "INVITE", recent and "grey" or "green", function()
					if invitedAt[p.UserId] and os.clock() - invitedAt[p.UserId] < 5 then return end
					invitedAt[p.UserId] = os.clock()
					partyRemote:FireServer("invite", p.UserId)
					b.setText("SENT")
					b.setColor("grey")
				end)
			end
		end
	end
	if order == 0 then
		local r = row(playersList, 1, "Nobody else here yet", "Invite friends to this server with the Roblox menu", false)
		r.BackgroundTransparency = 0.6
	end

	if partyData and not iAmLeader() then
		partyHint.Text = "Wait for the leader to press PLAY and pick a map — you'll all go together!"
	elseif partyData then
		partyHint.Text = "Press PLAY and pick a map — your whole party goes together!"
	else
		partyHint.Text = "Invite friends, then press PLAY and pick a map — you all go together!"
	end
end

partyBtn.Button.MouseButton1Click:Connect(function()
	if win.Root.Visible then
		win.hide()
	else
		picker.Visible = false
		rebuildParty()
		win.show()
	end
end)
Players.PlayerAdded:Connect(function() if win.Root.Visible then rebuildParty() end end)
Players.PlayerRemoving:Connect(function() task.defer(function() if win.Root.Visible then rebuildParty() end end) end)

-- приглашение: плашка сверху с кнопками ACCEPT / DECLINE
local inviteBox = UIKit.panel(gui, {
	Name = "PartyInvite",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 150),
	Size = UDim2.fromOffset(470, 132),
	Visible = false,
	ZIndex = 30,
}, PURPLE_TOP, PURPLE_BOTTOM, { Radius = 20, OutlineThickness = 4, GlossHeight = 30 })
UIKit.fitScale(new("UIScale", {}, inviteBox), 760, 0.6, 1)
local inviteText = text(inviteBox, {
	Position = UDim2.fromOffset(16, 10),
	Size = UDim2.new(1, -32, 0, 56),
	TextSize = 24,
	TextWrapped = true,
	RichText = true,
	Text = "",
	ZIndex = 31,
})
local acceptBtn = UIKit.button(inviteBox, {
	AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(0.5, -6, 1, -12), Size = UDim2.fromOffset(170, 50),
	Color = "green", Text = "ACCEPT", Font = UIKit.Font.Title, TextSize = 24, ZIndex = 31,
})
local declineBtn = UIKit.button(inviteBox, {
	AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0.5, 6, 1, -12), Size = UDim2.fromOffset(170, 50),
	Color = "red", Text = "DECLINE", Font = UIKit.Font.Title, TextSize = 24, ZIndex = 31, Shine = false,
})
local currentInvite = nil
local inviteToken = 0
local function closeInvite()
	currentInvite = nil
	inviteBox.Visible = false
end
acceptBtn.Button.MouseButton1Click:Connect(function()
	if currentInvite and partyRemote then partyRemote:FireServer("accept", currentInvite.id) end
	closeInvite()
end)
declineBtn.Button.MouseButton1Click:Connect(function()
	if currentInvite and partyRemote then partyRemote:FireServer("decline", currentInvite.id) end
	closeInvite()
end)

if partyRemote then
	partyRemote.OnClientEvent:Connect(function(kind, data)
		if kind == "state" then
			partyData = (type(data) == "table" and type(data.members) == "table") and data or nil
			rebuildParty()
		elseif kind == "invite" and type(data) == "table" and typeof(data.id) == "number" then
			currentInvite = data
			inviteToken += 1
			local token = inviteToken
			inviteText.Text = string.format("<b>%s</b> invites you to a party!", tostring(data.name))
			inviteBox.Visible = true
			UIKit.pop(inviteBox, 0.6, 0.3)
			task.delay(tonumber(data.time) or 30, function()
				if token == inviteToken then closeInvite() end
			end)
		end
	end)
	partyRemote:FireServer("sync")
else
	partyBtn.Button.Visible = false
end
rebuildParty()

playMap = function(id)
	if partyData and partyData.leader ~= player.UserId then
		toast("Only the party leader can start the game", "error")
		return
	end
	if actionRemote then actionRemote:FireServer("play", id) end
end

-- кнопку PARTY прячем вместе с PLAY (в круге портала и при телепорте)
task.spawn(function()
	while true do
		partyBtn.Button.Visible = play.Button.Visible and partyRemote ~= nil
		hud.Visible = partyData ~= nil and play.Button.Visible and not picker.Visible
		task.wait(0.2)
	end
end)

---------------------------------------------------------------- картинки на табличках

local function fillIcon(img)
	if img:IsA("ImageLabel") and img:GetAttribute("IconName") then
		UIKit.setIcon(img, img:GetAttribute("IconName"))
		img.Visible = UIKit.IconsReady
	end
end

---------------------------------------------------------------- оживляем мир

local floaters, orbiters, rotors, drifters = {}, {}, {}, {}

local function baseOf(obj)
	local b = obj:GetAttribute("HubBase")
	if typeof(b) == "CFrame" then return b end
	if obj:IsA("Model") then return obj:GetPivot() end
	return obj.CFrame
end

local function track(obj)
	if obj:GetAttribute("HubFloat") then
		floaters[obj] = {
			base = baseOf(obj),
			amp = obj:GetAttribute("HubFloat") or 1,
			spin = math.rad(obj:GetAttribute("HubSpin") or 0),
			speed = obj:GetAttribute("HubSpeed") or 1,
			phase = obj:GetAttribute("HubPhase") or 0,
		}
	end
	if obj:GetAttribute("OrbitCenter") then
		orbiters[obj] = {
			center = obj:GetAttribute("OrbitCenter"),
			radius = obj:GetAttribute("OrbitRadius") or 6,
			speed = obj:GetAttribute("OrbitSpeed") or 1,
			phase = obj:GetAttribute("OrbitPhase") or 0,
			bob = obj:GetAttribute("OrbitBob") or 1,
		}
	end
	if obj:GetAttribute("HubRotor") then
		rotors[obj] = { base = baseOf(obj), speed = math.rad(obj:GetAttribute("HubRotor")) }
	end
	if obj:GetAttribute("HubDrift") then
		drifters[obj] = { base = baseOf(obj), speed = math.rad(obj:GetAttribute("HubDrift") * 0.25) }
	end
	fillIcon(obj)
end

local function place(obj, cf)
	if obj:IsA("Model") then
		obj:PivotTo(cf)
	elseif obj:IsA("BasePart") then
		obj.CFrame = cf
	end
end

if hub then
	for _, d in ipairs(hub:GetDescendants()) do track(d) end
	track(hub)
	hub.DescendantAdded:Connect(track)
	hub.DescendantRemoving:Connect(function(d)
		floaters[d], orbiters[d], rotors[d], drifters[d] = nil, nil, nil, nil
	end)

	local TAU = math.pi * 2
	RunService.RenderStepped:Connect(function()
		local t = workspace:GetServerTimeNow() - 1.7e9 -- общее время у всех игроков
		for obj, f in pairs(floaters) do
			if obj.Parent then
				-- вверх-вниз по вертикали мира и поворот вокруг неё
				local y = math.sin((t * f.speed + f.phase) % TAU) * f.amp
				local spin = CFrame.Angles(0, (t * f.spin) % TAU, 0)
				place(obj, CFrame.new(f.base.Position + Vector3.new(0, y, 0)) * spin * f.base.Rotation)
			end
		end
		for obj, o in pairs(orbiters) do
			if obj.Parent then
				local a = (o.phase + t * o.speed) % TAU
				local pos = o.center + Vector3.new(math.cos(a) * o.radius, math.sin((t * 1.3 + o.phase) % TAU) * o.bob, math.sin(a) * o.radius)
				obj.CFrame = CFrame.new(pos) * CFrame.Angles((t * 1.1) % TAU, (t * 1.7) % TAU, (t * 0.6) % TAU)
			end
		end
		for obj, r in pairs(rotors) do
			if obj.Parent then
				place(obj, r.base * CFrame.Angles(0, 0, (t * r.speed) % TAU))
			end
		end
		for obj, dr in pairs(drifters) do
			if obj.Parent then
				place(obj, CFrame.Angles(0, (t * dr.speed) % TAU, 0) * dr.base)
			end
		end
	end)
else
	warn("[HubClient] нет workspace.Hub — добавь скрипт HubBuilder в ServerScriptService")
end

---------------------------------------------------------------- приветствие

task.delay(4, function()
	if not player:GetAttribute("HubQueue") then
		toast("Press PLAY or walk into a portal!")
	end
end)
