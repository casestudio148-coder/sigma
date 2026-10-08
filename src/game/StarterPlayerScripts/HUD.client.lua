-- StarterPlayer.StarterPlayerScripts.HUD (LocalScript)
-- Яркий HUD, который не перекрывает игру:
--   • сверху по центру строка: [сложность]  [флаг] WAVE 3 / 20  │  [сердце] полоска HP  │  [таймер / враги]
--   • слева плашка монет матча с большой монетой
--   • экран победы / поражения с лучами, наградами и конфетти (внизу файла)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))
local DifficultyData = require(ReplicatedStorage:WaitForChild("DifficultyData"))
local resultEvent = ReplicatedStorage:WaitForChild("MatchResult")
local mobsFolder = workspace:WaitForChild("Mobs")

local new, corner, stroke, tween = UIKit.new, UIKit.corner, UIKit.stroke, UIKit.tween
local text, icon, rgb = UIKit.text, UIKit.icon, UIKit.rgb

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local INK = UIKit.C.Ink
local GOLD = UIKit.C.Gold
local NAVY = rgb(34, 22, 78)

local function bounce(scaleObj, from, time)
	scaleObj.Scale = from
	TweenService:Create(scaleObj, TweenInfo.new(time or 0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

local function hlist(parent, padding)
	return new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, padding or 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, parent)
end

---------------------------------------------------------------- экраны

local gui = new("ScreenGui", {
	Name = "GameHUD",
	ResetOnSpawn = false,
	IgnoreGuiInset = false, -- монеты ниже кнопок Roblox
	DisplayOrder = 4,
	Enabled = false,
}, playerGui)

local topGui = new("ScreenGui", {
	Name = "GameTopBar",
	ResetOnSpawn = false,
	IgnoreGuiInset = true, -- верхняя строка на одном уровне с кнопками Roblox
	DisplayOrder = 4,
	Enabled = false,
}, playerGui)

---------------------------------------------------------------- монеты

local coinPill = new("Frame", {
	Name = "Coins",
	Position = UDim2.fromOffset(30, 10),
	Size = UDim2.fromOffset(0, 44),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundColor3 = NAVY,
	BackgroundTransparency = 0.05,
	BorderSizePixel = 0,
}, gui)
corner(coinPill, 22)
stroke(coinPill, GOLD, 3)
new("UIPadding", { PaddingLeft = UDim.new(0, 40), PaddingRight = UDim.new(0, 18) }, coinPill)
hlist(coinPill, 8)
local pillScale = new("UIScale", {}, coinPill)

-- монета не участвует в раскладке: лежит в пустой рамке и выступает за левый край плашки
local coinHolder = new("Frame", { Size = UDim2.fromOffset(0, 44), BackgroundTransparency = 1, LayoutOrder = 0 }, coinPill)
local coinIcon = icon(coinHolder, "coin", {
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, -48, 0.5, 0),
	Size = UDim2.fromOffset(60, 60),
	ZIndex = 2,
})
UIKit.wobble(coinIcon, 6, 1.4)

local coinText = UIKit.title(coinPill, {
	Size = UDim2.fromScale(0, 1),
	AutomaticSize = Enum.AutomaticSize.X,
	Text = "0",
	TextSize = 28,
	LayoutOrder = 2,
})

local shown = Instance.new("NumberValue")
shown.Changed:Connect(function(v)
	coinText.Text = UIKit.commas(v + 0.5)
end)

local lastCoins = 0
local function setCoins(value)
	local delta = value - lastCoins
	lastCoins = value
	tween(shown, 0.35, { Value = value })

	if delta > 0 then
		bounce(pillScale, 1.1, 0.3)
		UIKit.pop(coinIcon, 1.4, 0.35)
		local pop = text(gui, {
			Text = "+" .. UIKit.commas(delta),
			Position = UDim2.fromOffset(60, 58),
			Size = UDim2.fromOffset(160, 26),
			Font = UIKit.Font.Title,
			TextSize = 24,
			TextColor3 = rgb(140, 255, 130),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		local st = pop:FindFirstChildOfClass("UIStroke")
		tween(pop, 0.8, { Position = UDim2.fromOffset(60, 78), TextTransparency = 1 })
		if st then tween(st, 0.8, { Transparency = 1 }) end
		Debris:AddItem(pop, 0.9)
	elseif delta < 0 then
		bounce(pillScale, 0.92, 0.2)
	end
end

task.spawn(function()
	local stats = player:WaitForChild("leaderstats")
	local coins = stats:WaitForChild("Coins")
	lastCoins = coins.Value
	shown.Value = coins.Value
	coinText.Text = UIKit.commas(coins.Value)
	coins:GetPropertyChangedSignal("Value"):Connect(function()
		setCoins(coins.Value)
	end)
end)

---------------------------------------------------------------- верхняя строка

local bar = new("Frame", {
	Name = "TopBar",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 10),
	Size = UDim2.fromOffset(0, 52),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundColor3 = NAVY,
	BackgroundTransparency = 0.05,
	BorderSizePixel = 0,
}, topGui)
corner(bar, 26)
stroke(bar, WHITE, 3)
new("UIGradient", { Rotation = 90, Color = ColorSequence.new(rgb(90, 70, 190), rgb(40, 25, 95)) }, bar)
new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 18) }, bar)
hlist(bar, 12)
local barScale = new("UIScale", {}, bar)

local function divider(order)
	local d = new("Frame", {
		Size = UDim2.fromOffset(3, 28),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.7,
		BorderSizePixel = 0,
		LayoutOrder = order,
	}, bar)
	corner(d, 2)
end

-- 1. значок сложности
local diffBadge = new("Frame", { Size = UDim2.fromOffset(42, 42), BorderSizePixel = 0, LayoutOrder = 1 }, bar)
corner(diffBadge, 21)
local diffGrad = new("UIGradient", { Rotation = 90 }, diffBadge)
diffBadge.BackgroundColor3 = WHITE
local diffStroke = stroke(diffBadge, INK, 3)
local diffIcon = icon(diffBadge, "swords", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(34, 34),
})

-- 2. номер волны
local waveIcon = icon(bar, "flag", { Size = UDim2.fromOffset(34, 34), LayoutOrder = 2 })
local waveText = text(bar, {
	Size = UDim2.fromScale(0, 1),
	AutomaticSize = Enum.AutomaticSize.X,
	RichText = true,
	Font = UIKit.Font.Title,
	Text = "WAVE 1",
	TextSize = 28,
	LayoutOrder = 3,
})
local waveScale = new("UIScale", {}, waveText)

divider(4)

-- 3. HP базы
local hpBlock = new("Frame", { Size = UDim2.fromOffset(176, 36), BackgroundTransparency = 1, LayoutOrder = 5 }, bar)
local hpBar = UIKit.bar(hpBlock, {
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 22, 0.5, 0),
	Size = UDim2.new(1, -22, 0, 22),
})
local heart = icon(hpBlock, "heart", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0, 16, 0.5, 0),
	Size = UDim2.fromOffset(40, 40),
	ZIndex = 4,
})
local heartScale = new("UIScale", {}, heart)

divider(6)

-- 4. статус: таймер до волны или сколько врагов осталось
local statusIcon = icon(bar, "enemy", { Size = UDim2.fromOffset(34, 34), LayoutOrder = 7 })
local status = text(bar, {
	Size = UDim2.fromScale(0, 1),
	AutomaticSize = Enum.AutomaticSize.X,
	Font = UIKit.Font.Title,
	TextSize = 24,
	Text = "",
	LayoutOrder = 8,
})

---------------------------------------------------------------- обновление

local lastWave, lastHp = nil, nil

local function currentDifficulty()
	local id = workspace:GetAttribute("DifficultyName") or ""
	if DifficultyData[id] then return DifficultyData[id], id end
	id = workspace:GetAttribute("Difficulty") or ""
	if DifficultyData[id] then return DifficultyData[id], id end
	return DifficultyData[DifficultyData.Default], DifficultyData.Default
end

local function difficultyId(d)
	for _, id in ipairs(DifficultyData.Order) do
		if DifficultyData[id] == d then return id end
	end
	return DifficultyData.Default
end

local function refreshDifficulty()
	local d, id = currentDifficulty()
	UIKit.setIcon(diffIcon, UIKit.DifficultyIcon[id] or "swords")
	diffGrad.Color = ColorSequence.new(d.Color:Lerp(WHITE, 0.45), d.Color)
	diffStroke.Color = d.Color:Lerp(BLACK, 0.55)
end

local function refreshWave()
	local wave = workspace:GetAttribute("Wave") or 1
	local maxWaves = workspace:GetAttribute("MaxWaves") or 20
	waveText.Text = string.format('WAVE %d<font size="18" color="#C9C2FF">  / %d</font>', wave, maxWaves)
	if lastWave and wave ~= lastWave then
		bounce(waveScale, 1.4, 0.45)
		bounce(barScale, 1.06, 0.35)
		UIKit.pop(waveIcon, 1.6, 0.45)
	end
	lastWave = wave
end

local function hpColors(r)
	if r > 0.6 then
		return rgb(160, 255, 120), rgb(30, 190, 70)
	elseif r > 0.3 then
		return rgb(255, 235, 100), rgb(255, 150, 20)
	end
	return rgb(255, 140, 140), rgb(230, 30, 60)
end

local function refreshHP()
	local hp = workspace:GetAttribute("BaseHP") or 0
	local maxHp = math.max(workspace:GetAttribute("MaxBaseHP") or 1, 1)
	local r = math.clamp(hp / maxHp, 0, 1)
	hpBar.set(r, 0.3)
	hpBar.setColors(hpColors(r))
	hpBar.Label.Text = tostring(hp)
	if lastHp and hp < lastHp then
		bounce(heartScale, 1.7, 0.4)
		UIKit.shake(hpBlock)
	end
	lastHp = hp
end

local function setStatus(iconName, msg, color)
	UIKit.setIcon(statusIcon, iconName)
	status.Text = msg
	status.TextColor3 = color
end

local function refreshStatus()
	local hp = workspace:GetAttribute("BaseHP") or 1
	local s = workspace:GetAttribute("StatusText") or ""

	if hp <= 0 then
		setStatus("explosion", "LOST", rgb(255, 120, 120))
	elseif string.find(s, "VICTORY") then
		setStatus("trophy", "WIN!", rgb(150, 255, 150))
	elseif s ~= "" then
		local secs = string.match(s, "in (%d+)")
		if secs then
			setStatus("stopwatch", secs .. "s", GOLD)
		else
			setStatus("hourglass", s, GOLD)
		end
	else
		local alive = 0
		for _, m in ipairs(mobsFolder:GetChildren()) do
			local h = m:FindFirstChildOfClass("Humanoid")
			if h and h.Health > 0 then alive += 1 end
		end
		setStatus("enemy", tostring(alive), WHITE)
	end
end

for _, attr in ipairs({ "Wave", "MaxWaves" }) do
	workspace:GetAttributeChangedSignal(attr):Connect(refreshWave)
end
for _, attr in ipairs({ "BaseHP", "MaxBaseHP" }) do
	workspace:GetAttributeChangedSignal(attr):Connect(refreshHP)
end
for _, attr in ipairs({ "DifficultyName", "Difficulty" }) do
	workspace:GetAttributeChangedSignal(attr):Connect(refreshDifficulty)
end
workspace:GetAttributeChangedSignal("StatusText"):Connect(refreshStatus)

local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc >= 0.4 then
		acc = 0
		if topGui.Enabled then refreshStatus() end
	end
end)

refreshDifficulty()
refreshWave()
refreshHP()
refreshStatus()

local function refreshPhase()
	local playing = workspace:GetAttribute("Phase") == "Playing"
	gui.Enabled = playing
	topGui.Enabled = playing
end
workspace:GetAttributeChangedSignal("Phase"):Connect(refreshPhase)
refreshPhase()

---------------------------------------------------------------- ЭКРАН ПОБЕДЫ / ПОРАЖЕНИЯ

local resultGui = new("ScreenGui", {
	Name = "MatchResultGui",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 30,
	Enabled = false,
}, playerGui)

local function confetti(parent)
	local colors = { rgb(255, 90, 110), rgb(255, 210, 60), rgb(90, 200, 255), rgb(140, 255, 120), rgb(210, 120, 255), rgb(255, 150, 220) }
	for _ = 1, 90 do
		local x = math.random()
		local c = new("Frame", {
			Size = UDim2.fromOffset(math.random(8, 15), math.random(12, 24)),
			Position = UDim2.new(x, 0, 0, -30),
			BackgroundColor3 = colors[math.random(#colors)],
			BorderSizePixel = 0,
			Rotation = math.random(0, 360),
			ZIndex = 20,
		}, parent)
		corner(c, 3)
		local t = 1.8 + math.random() * 1.6
		TweenService:Create(c, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, math.random() * 0.9), {
			Position = UDim2.new(x + (math.random() - 0.5) * 0.25, 0, 1.1, 0),
			Rotation = c.Rotation + math.random(-540, 540),
		}):Play()
		Debris:AddItem(c, t + 1.2)
	end
end

local function rewardBox(parent, order, iconName, amount, color)
	local box = new("Frame", {
		Size = UDim2.fromOffset(160, 110),
		BackgroundColor3 = rgb(30, 18, 70),
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		LayoutOrder = order,
	}, parent)
	corner(box, 18)
	stroke(box, color, 4)
	UIKit.glow(box, color, UDim2.fromScale(1.2, 1.2), { Position = UDim2.fromScale(0.5, 0.35), ImageTransparency = 0.45 })

	local img = icon(box, iconName, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 34),
		Size = UDim2.fromOffset(62, 62),
		ZIndex = 2,
	})
	UIKit.wobble(img, 7, 0.9)

	local value = Instance.new("NumberValue")
	local amountText = UIKit.title(box, {
		Position = UDim2.fromOffset(0, 66),
		Size = UDim2.new(1, 0, 0, 36),
		TextSize = 32,
		Text = "+0",
		Colors = { color:Lerp(WHITE, 0.6), color },
		ZIndex = 2,
	})
	value.Changed:Connect(function(v)
		amountText.Text = "+" .. UIKit.commas(v + 0.5)
	end)
	TweenService:Create(value, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0.4), { Value = amount }):Play()
	return box
end

local function showResult(data)
	if typeof(data) ~= "table" then return end
	resultGui:ClearAllChildren()
	resultGui.Enabled = true

	local victory = data.victory == true
	local d = DifficultyData[data.difficulty or ""] or (currentDifficulty())
	local dId = DifficultyData[data.difficulty or ""] and data.difficulty or difficultyId(d)

	local dim = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = victory and rgb(20, 10, 60) or rgb(40, 5, 20),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = true,
	}, resultGui)
	tween(dim, 0.4, { BackgroundTransparency = 0.25 })

	local holder = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(470, 400),
		BackgroundTransparency = 1,
	}, dim)
	local holderScale = new("UIScale", {}, holder)
	local fitS = UIKit.fit(620, 0.55, 1.1)
	holderScale.Scale = fitS * 0.4
	TweenService:Create(holderScale, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = fitS }):Play()

	-- лучи и свечение за карточкой
	UIKit.rays(holder, victory and rgb(255, 225, 120) or rgb(255, 110, 140), 900, victory and 18 or 8, {
		Position = UDim2.fromScale(0.5, 0.3),
		ImageTransparency = victory and 0.35 or 0.6,
	})
	UIKit.glow(holder, victory and rgb(255, 230, 140) or rgb(255, 90, 120), 700, {
		Position = UDim2.fromScale(0.5, 0.3),
		ImageTransparency = 0.4,
	})

	local card = UIKit.panel(holder, {
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 1, -40),
		ZIndex = 1,
	}, victory and rgb(120, 220, 255) or rgb(255, 130, 150), victory and rgb(70, 80, 235) or rgb(150, 30, 90),
	{ Radius = 26, OutlineThickness = 5, GlossHeight = 50 })
	UIKit.sparkles(card, WHITE, victory and 6 or 2, 8)

	-- большая иконка и заголовок
	local bigIcon = icon(holder, victory and "trophy" or "skull", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(110, 110),
		ZIndex = 4,
	})
	UIKit.wobble(bigIcon, 6, 0.9)
	UIKit.pop(bigIcon, 2.2, 0.6)

	local title = UIKit.title(card, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 58),
		Size = UDim2.new(1, -20, 0, 60),
		TextSize = 60,
		Text = victory and "VICTORY!" or "DEFEAT",
		Colors = victory and { rgb(255, 250, 170), rgb(255, 170, 20) } or { rgb(255, 200, 210), rgb(255, 70, 100) },
		ZIndex = 3,
	})
	TweenService:Create(title, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Rotation = 3 }):Play()

	-- сложность и волны
	local infoRow = new("Frame", {
		Position = UDim2.fromOffset(0, 122),
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundTransparency = 1,
		ZIndex = 3,
	}, card)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, infoRow)
	icon(infoRow, UIKit.DifficultyIcon[dId] or "swords", { Size = UDim2.fromOffset(32, 32), LayoutOrder = 1, ZIndex = 3 })
	text(infoRow, {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		TextSize = 24,
		Font = UIKit.Font.Title,
		Text = string.upper(d.Name),
		TextColor3 = d.Color:Lerp(WHITE, 0.45),
		LayoutOrder = 2,
		ZIndex = 3,
	})
	icon(infoRow, "flag", { Size = UDim2.fromOffset(30, 30), LayoutOrder = 3, ZIndex = 3 })
	text(infoRow, {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		TextSize = 22,
		Text = string.format("%d / %d waves", data.wave or 0, data.total or 0),
		LayoutOrder = 4,
		ZIndex = 3,
	})

	local row = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 164),
		Size = UDim2.new(1, -40, 0, 110),
		BackgroundTransparency = 1,
		ZIndex = 3,
	}, card)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 18),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, row)
	rewardBox(row, 1, "coin", data.cash or 0, rgb(255, 215, 60))
	rewardBox(row, 2, "gem", data.gems or 0, rgb(225, 140, 255))

	text(card, {
		Position = UDim2.fromOffset(0, 278),
		Size = UDim2.new(1, 0, 0, 22),
		TextSize = 18,
		Text = victory and "Rewards added to your account!" or "Keep going - you'll get them next time!",
		ZIndex = 3,
	})

	local ok = UIKit.button(card, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.fromOffset(230, 62),
		Color = "yellow",
		Text = "AWESOME!",
		Font = UIKit.Font.Title,
		TextSize = 30,
		Icon = "check",
		ZIndex = 3,
	})
	UIKit.pulse(new("UIScale", {}, ok.Face), 1.05, 0.6)
	ok.Button.MouseButton1Click:Connect(function()
		resultGui.Enabled = false
		resultGui:ClearAllChildren()
	end)

	if victory then
		confetti(dim)
	end
end

resultEvent.OnClientEvent:Connect(function(data)
	local ok, err = pcall(showResult, data)
	if not ok then warn("[HUD] result screen: " .. tostring(err)) end
end)
