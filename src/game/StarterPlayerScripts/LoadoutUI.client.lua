-- StarterPlayer.StarterPlayerScripts.LoadoutUI (LocalScript)
-- Экран выбора юнитов перед матчем: голосование за сложность, карточки, 6 слотов, таймер, кнопка READY.
-- Брать можно только своих юнитов (выбитых в Summon). Чужие показаны с замком — чтобы было что собирать.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local TowerData = require(ReplicatedStorage:WaitForChild("TowerData"))
local RarityData = require(ReplicatedStorage:WaitForChild("RarityData"))
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))
local DifficultyData = require(ReplicatedStorage:WaitForChild("DifficultyData"))
local submit = ReplicatedStorage:WaitForChild("SubmitLoadout")
local voteDifficulty = ReplicatedStorage:WaitForChild("VoteDifficulty")

local new, corner, stroke, tween = UIKit.new, UIKit.corner, UIKit.stroke, UIKit.tween
local text, icon, rgb = UIKit.text, UIKit.icon, UIKit.rgb

while workspace:GetAttribute("Phase") == nil do
	task.wait(0.1)
end
if workspace:GetAttribute("Phase") ~= "Selection" then return end

local MAX_UNITS = workspace:GetAttribute("MaxUnits") or 6
local WHITE = Color3.new(1, 1, 1)
local INK = UIKit.C.Ink
local GOLD = UIKit.C.Gold
local DIFF_COLOR = { Easy = "green", Normal = "blue", Hard = "orange", Nightmare = "purple" }

local selected = {}

-- свои юниты: папка Data.Units (её создаёт сервер, сколько копий у игрока)
local unitsFolder = nil
task.spawn(function()
	local data = player:WaitForChild("Data", 15)
	unitsFolder = data and data:WaitForChild("Units", 5)
end)
local function isOwned(name)
	return unitsFolder ~= nil and unitsFolder:FindFirstChild(name) ~= nil
end
local locked = false
local cards = {}
local toggle -- объявляем заранее

---------------------------------------------------------------- каркас

local gui = new("ScreenGui", {
	Name = "LoadoutGui",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 20,
}, player:WaitForChild("PlayerGui"))

local dim = new("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = WHITE,
	BorderSizePixel = 0,
	Active = true,
}, gui)
new("UIGradient", { Rotation = 90, Color = ColorSequence.new(rgb(70, 40, 160), rgb(20, 10, 60)) }, dim)
UIKit.rays(dim, rgb(170, 140, 255), 1600, 6, { ImageTransparency = 0.8 })
UIKit.sparkles(dim, rgb(220, 210, 255), 3, 2)

local panel = UIKit.panel(dim, {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.94, 0.92),
}, rgb(110, 200, 255), rgb(50, 85, 225), { Radius = 26, OutlineThickness = 5, GlossHeight = 50 })
new("UISizeConstraint", { MaxSize = Vector2.new(1080, 690) }, panel)

local titleRow = new("Frame", {
	Position = UDim2.fromOffset(20, 10),
	Size = UDim2.new(0.62, 0, 0, 50),
	BackgroundTransparency = 1,
}, panel)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	Padding = UDim.new(0, 8),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, titleRow)
local titleIcon = icon(titleRow, "swords", { Size = UDim2.fromOffset(48, 48), LayoutOrder = 1 })
UIKit.wobble(titleIcon, 6, 1)
UIKit.title(titleRow, {
	Text = "CHOOSE YOUR TEAM!",
	AutomaticSize = Enum.AutomaticSize.X,
	Size = UDim2.new(0, 0, 1, 0),
	TextSize = 38,
	LayoutOrder = 2,
})

local countLabel = text(panel, {
	Position = UDim2.fromOffset(24, 60),
	Size = UDim2.new(0.62, 0, 0, 22),
	TextSize = 17,
	TextXAlignment = Enum.TextXAlignment.Left,
	RichText = true,
})

local timerPill = new("Frame", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -22, 0, 16),
	Size = UDim2.fromOffset(150, 52),
	BackgroundColor3 = rgb(35, 22, 80),
	BorderSizePixel = 0,
}, panel)
corner(timerPill, 26)
local timerStroke = stroke(timerPill, GOLD, 4)
icon(timerPill, "stopwatch", {
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, -10, 0.5, 0),
	Size = UDim2.fromOffset(56, 56),
	ZIndex = 2,
})
local timerLabel = text(timerPill, {
	Position = UDim2.fromOffset(40, 0),
	Size = UDim2.new(1, -46, 1, 0),
	Font = UIKit.Font.Title,
	TextSize = 30,
	TextColor3 = GOLD,
	Text = "...",
})
local timerScale = new("UIScale", {}, timerPill)

---------------------------------------------------------------- выбор сложности (голосование)

local diffRow = new("Frame", {
	Position = UDim2.fromOffset(22, 90),
	Size = UDim2.new(1, -44, 0, 56),
	BackgroundTransparency = 1,
}, panel)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	Padding = UDim.new(0, 12),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, diffRow)

local diffButtons = {}
for i, id in ipairs(DifficultyData.Order) do
	local d = DifficultyData[id]
	local b = UIKit.button(diffRow, {
		Name = id,
		Size = UDim2.new(0.25, -9, 1, 0),
		Color = DIFF_COLOR[id] or "blue",
		Icon = UIKit.DifficultyIcon[id],
		IconSize = 34,
		Text = d.Name,
		TextSize = 19,
		LayoutOrder = i,
		Radius = 16,
	})
	text(b.Content, {
		Text = d.Waves .. " waves",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		TextSize = 14,
		TextColor3 = rgb(240, 240, 255),
		LayoutOrder = 3,
	})
	local faceStroke = b.Face:FindFirstChildOfClass("UIStroke")

	local votes = new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 8, 0, -12),
		Size = UDim2.fromOffset(52, 28),
		BackgroundColor3 = rgb(255, 60, 90),
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 4,
	}, b.Button)
	corner(votes, 14)
	stroke(votes, WHITE, 2.5)
	icon(votes, "hand", { Position = UDim2.fromOffset(2, 1), Size = UDim2.fromOffset(26, 26), ZIndex = 5 })
	local votesText = text(votes, { Position = UDim2.fromOffset(26, 0), Size = UDim2.new(1, -28, 1, 0), Font = UIKit.Font.Title, TextSize = 17, ZIndex = 5 })

	b.Button.MouseButton1Click:Connect(function()
		voteDifficulty:FireServer(id)
	end)
	diffButtons[id] = { api = b, faceStroke = faceStroke, votes = votes, votesText = votesText, last = 0 }
end

local function renderDifficulty()
	local mine = player:GetAttribute("DiffVote")
	local leader = workspace:GetAttribute("DiffLeader") or DifficultyData.Default
	for id, info in pairs(diffButtons) do
		local count = workspace:GetAttribute("DiffVotes_" .. id) or 0
		info.api.setColor((leader == id) and (DIFF_COLOR[id] or "blue") or "night")
		info.faceStroke.Color = (mine == id) and WHITE or INK
		info.faceStroke.Thickness = (mine == id) and 5 or 3
		info.votes.Visible = count > 0
		info.votesText.Text = tostring(count)
		if count > info.last then
			UIKit.pop(info.votes, 1.5, 0.35)
		end
		info.last = count
	end
end

for _, id in ipairs(DifficultyData.Order) do
	workspace:GetAttributeChangedSignal("DiffVotes_" .. id):Connect(renderDifficulty)
end
workspace:GetAttributeChangedSignal("DiffLeader"):Connect(renderDifficulty)
player:GetAttributeChangedSignal("DiffVote"):Connect(renderDifficulty)
renderDifficulty()

---------------------------------------------------------------- сетка карточек

local well = UIKit.well(panel, {
	Position = UDim2.fromOffset(22, 158),
	Size = UDim2.new(1, -44, 1, -158 - 156),
})
local scroller = new("ScrollingFrame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 8,
	ScrollBarImageColor3 = rgb(255, 220, 90),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	CanvasSize = UDim2.new(),
}, well)
new("UIGridLayout", {
	CellSize = UDim2.fromOffset(150, 200),
	CellPadding = UDim2.fromOffset(14, 14),
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder,
}, scroller)
new("UIPadding", { PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 12) }, scroller)

local infoLabel = text(panel, {
	Position = UDim2.new(0, 24, 1, -150),
	Size = UDim2.new(1, -48, 0, 32),
	TextSize = 16,
	TextWrapped = true,
	RichText = true,
	TextColor3 = rgb(235, 240, 255),
	Text = "Tap a unit to add it to your team!",
})

---------------------------------------------------------------- нижняя панель (слоты + READY)

local bottom = UIKit.well(panel, {
	Position = UDim2.new(0, 22, 1, -112),
	Size = UDim2.new(1, -44, 0, 96),
	BackgroundTransparency = 0.3,
}, 20)

local slotsFrame = new("Frame", {
	Position = UDim2.fromOffset(14, 0),
	Size = UDim2.new(1, -240, 1, 0),
	BackgroundTransparency = 1,
}, bottom)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	Padding = UDim.new(0, 10),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, slotsFrame)

local ready = UIKit.button(bottom, {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -14, 0.5, 0),
	Size = UDim2.fromOffset(210, 70),
	Color = "green",
	Icon = "check",
	IconSize = 40,
	Text = "READY!",
	Font = UIKit.Font.Title,
	TextSize = 32,
	Radius = 20,
	Depth = 6,
})
local readyPulse = UIKit.pulse(new("UIScale", {}, ready.Face), 1.05, 0.6)

---------------------------------------------------------------- логика

local function send(isReady)
	submit:FireServer(selected, isReady)
end

local function renderSlots()
	for _, child in ipairs(slotsFrame:GetChildren()) do
		if child:IsA("GuiObject") then child:Destroy() end
	end

	for i = 1, MAX_UNITS do
		local name = selected[i]
		local slot = new("TextButton", {
			Name = "Slot" .. i,
			Text = "",
			AutoButtonColor = false,
			Size = UDim2.fromOffset(74, 74),
			BackgroundTransparency = 1,
			LayoutOrder = i,
		}, slotsFrame)

		if name then
			local rar = RarityData[TowerData[name].Rarity] or RarityData.Common
			local back = UIKit.rarityBack(slot, rar.Color)
			local holder = new("Frame", { Size = UDim2.new(1, 0, 1, -14), BackgroundTransparency = 1, ZIndex = 2 }, back)
			UIKit.makeIcon(holder, name)
			text(back, {
				Text = name,
				Size = UDim2.new(1, -4, 0, 16),
				Position = UDim2.new(0, 2, 1, -18),
				TextSize = 12,
				TextTruncate = Enum.TextTruncate.AtEnd,
				ZIndex = 3,
			})
			slot.MouseButton1Click:Connect(function()
				if not locked then toggle(name) end
			end)
		else
			local empty = new("Frame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = rgb(60, 45, 130),
				BackgroundTransparency = 0.3,
				BorderSizePixel = 0,
			}, slot)
			corner(empty, 16)
			stroke(empty, rgb(170, 160, 255), 3, 0.3)
			text(empty, {
				Text = tostring(i),
				Size = UDim2.fromScale(1, 1),
				Font = UIKit.Font.Title,
				TextSize = 30,
				TextColor3 = rgb(150, 140, 230),
			})
		end
	end
end

local function render()
	for name, c in pairs(cards) do
		local on = table.find(selected, name) ~= nil
		c.stroke.Color = on and WHITE or INK
		c.stroke.Thickness = on and 5 or 3
		c.badge.Visible = on
		tween(c.scale, 0.15, { Scale = on and 1.04 or 1 })
	end
	-- карта матча (её выбрал портал в хабе)
	local mapName = workspace:GetAttribute("MapName")
	local prefix = (typeof(mapName) == "string" and mapName ~= "") and string.format('<font color="#FFE06E">MAP: %s</font>    ', string.upper(mapName)) or ""
	countLabel.Text = prefix .. string.format("Pick up to %d units   %d / %d selected", MAX_UNITS, #selected, MAX_UNITS)
	renderSlots()
end

toggle = function(name)
	local idx = table.find(selected, name)
	if not idx and not isOwned(name) then
		return
	end
	if idx then
		table.remove(selected, idx)
	elseif #selected < MAX_UNITS then
		table.insert(selected, name)
	else
		UIKit.shake(bottom)
		return
	end
	render()
	send(false)
end

for order, name in ipairs(UIKit.sortedTowerNames(TowerData)) do
	local cfg = TowerData[name]
	local rar = RarityData[cfg.Rarity] or RarityData.Common

	local card = new("TextButton", {
		Name = name,
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
	}, scroller)
	local back = UIKit.rarityBack(card, rar.Color)
	local st = back:FindFirstChildOfClass("UIStroke")
	local scale = new("UIScale", {}, card)
	if (UIKit.Rank[cfg.Rarity] or 1) >= 4 then
		UIKit.sparkles(back, rar.Color:Lerp(WHITE, 0.5), 2, 5)
	end

	local holder = new("Frame", {
		Position = UDim2.fromOffset(4, 6),
		Size = UDim2.new(1, -8, 0, 92),
		BackgroundTransparency = 1,
		ZIndex = 2,
	}, back)
	UIKit.makeIcon(holder, name)

	text(back, { Text = name, Position = UDim2.fromOffset(0, 98), Size = UDim2.new(1, 0, 0, 22), TextSize = 18, ZIndex = 3 })
	text(back, {
		Text = string.upper(cfg.Rarity or "Common"),
		Position = UDim2.fromOffset(0, 120),
		Size = UDim2.new(1, 0, 0, 18),
		Font = UIKit.Font.Title,
		TextSize = 15,
		TextColor3 = rar.Color:Lerp(WHITE, 0.35),
		ZIndex = 3,
	})
	icon(back, "lightning", { Position = UDim2.fromOffset(6, 140), Size = UDim2.fromOffset(20, 20), ZIndex = 3 })
	text(back, {
		Text = cfg.Ability or "",
		Position = UDim2.fromOffset(28, 140),
		Size = UDim2.new(1, -34, 0, 20),
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = rgb(240, 235, 255),
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 3,
	})

	local pricePill = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.new(0.7, 0, 0, 26),
		BackgroundColor3 = rgb(35, 22, 80),
		BorderSizePixel = 0,
		ZIndex = 3,
	}, back)
	corner(pricePill, 13)
	stroke(pricePill, GOLD, 2.5)
	icon(pricePill, "coin", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, -8, 0.5, 0), Size = UDim2.fromOffset(30, 30), ZIndex = 4 })
	text(pricePill, {
		Text = tostring(cfg.Price),
		Position = UDim2.fromOffset(16, 0),
		Size = UDim2.new(1, -18, 1, 0),
		Font = UIKit.Font.Title,
		TextSize = 17,
		TextColor3 = rgb(255, 235, 140),
		ZIndex = 4,
	})

	local badge = icon(back, "check", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 8, 0, -8),
		Size = UDim2.fromOffset(38, 38),
		Visible = false,
		ZIndex = 6,
	})

	-- замок на чужом юните
	local lock = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = rgb(20, 12, 45),
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		ZIndex = 7,
		Visible = false,
	}, back)
	corner(lock, 16)
	icon(lock, "lock", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.38),
		Size = UDim2.fromOffset(58, 58),
		ZIndex = 8,
	})
	text(lock, {
		Text = "GET IN SHOP",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.62, 0),
		Size = UDim2.new(1, -8, 0, 22),
		Font = UIKit.Font.Title,
		TextSize = 15,
		TextColor3 = rgb(255, 225, 120),
		ZIndex = 8,
	})

	local function showInfo()
		local owned = isOwned(name)
		infoLabel.Text = string.format('<font color="#FFE066">%s</font> - %s: %s%s', name, cfg.Ability or "", cfg.Description or "",
			owned and "" or '  <font color="#FF9AA8">(open chests in the Shop to get it!)</font>')
	end
	card.MouseEnter:Connect(showInfo)
	card.MouseButton1Click:Connect(function()
		showInfo()
		if not isOwned(name) then
			UIKit.shake(card)
			return
		end
		if not locked then
			toggle(name)
			if table.find(selected, name) then
				UIKit.pop(badge, 2, 0.4)
			end
		end
	end)

	cards[name] = { card = card, stroke = st, badge = badge, scale = scale, lock = lock, order = order }
end

-- свои — первыми, чужие — в конце с замком
local function refreshLocks()
	local changed = false
	for name, c in pairs(cards) do
		local owned = isOwned(name)
		c.lock.Visible = not owned
		c.card.LayoutOrder = owned and c.order or (100 + c.order)
		local idx = table.find(selected, name)
		if idx and not owned then
			table.remove(selected, idx)
			changed = true
		end
	end
	if changed then
		render()
		send(false)
	end
end

task.spawn(function()
	local waited = 0
	while not unitsFolder and waited < 20 do
		waited += task.wait(0.2)
	end
	refreshLocks()
	if unitsFolder then
		unitsFolder.ChildAdded:Connect(refreshLocks)
		unitsFolder.ChildRemoved:Connect(refreshLocks)
	end
end)

ready.Button.MouseButton1Click:Connect(function()
	if not locked then
		if #selected == 0 then
			UIKit.shake(bottom)
			return
		end
		locked = true
		ready.setText("WAITING...")
		ready.setIcon("hourglass")
		ready.setColor("grey")
		readyPulse:Cancel()
		send(true)
	else
		locked = false
		ready.setText("READY!")
		ready.setIcon("check")
		ready.setColor("green")
		readyPulse:Play()
		send(false)
	end
end)

render()

---------------------------------------------------------------- таймер и закрытие

local lastLeft = nil
local conn
conn = RunService.Heartbeat:Connect(function()
	local endsAt = workspace:GetAttribute("SelectionEndsAt")
	if not endsAt then
		timerLabel.Text = "..."
		return
	end
	local left = math.max(0, math.ceil(endsAt - workspace:GetServerTimeNow()))
	timerLabel.Text = left .. "s"
	local hurry = left <= 10
	timerLabel.TextColor3 = hurry and rgb(255, 110, 120) or GOLD
	timerStroke.Color = hurry and rgb(255, 80, 100) or GOLD
	if hurry and left ~= lastLeft then
		UIKit.pop(timerPill, 1.15, 0.3)
	end
	lastLeft = left
end)

local function closeIfPlaying()
	if workspace:GetAttribute("Phase") == "Playing" then
		conn:Disconnect()
		gui:Destroy()
	end
end
workspace:GetAttributeChangedSignal("Phase"):Connect(closeIfPlaying)
workspace:GetAttributeChangedSignal("MapName"):Connect(render)
closeIfPlaying()
