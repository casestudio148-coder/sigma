-- StarterPlayer.StarterPlayerScripts.TowerInfoUI (LocalScript)
-- Панель своей башни (тап / клик по башне):
--   уровень (5 звёзд), урон / радиус / скорость с превью улучшения,
--   кнопка UPGRADE (клавиша E), способность (клавиша Q), режим цели, продажа, круг радиуса.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local TowerData = require(ReplicatedStorage:WaitForChild("TowerData"))
local RarityData = require(ReplicatedStorage:WaitForChild("RarityData"))
local UpgradeData = require(ReplicatedStorage:WaitForChild("UpgradeData"))
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))
local setTargetEvent = ReplicatedStorage:WaitForChild("SetTargetMode")
local sellEvent = ReplicatedStorage:WaitForChild("SellTower")
local upgradeEvent = ReplicatedStorage:WaitForChild("UpgradeTower")
local AbilityData = require(ReplicatedStorage:WaitForChild("AbilityData"))
local useAbilityEvent = ReplicatedStorage:FindFirstChild("UseAbility") -- создаёт AbilityService; ниже дождёмся без блокировки
local towersFolder = workspace:WaitForChild("Towers")

local new, corner, stroke, tween = UIKit.new, UIKit.corner, UIKit.stroke, UIKit.tween
local text, icon, rgb = UIKit.text, UIKit.icon, UIKit.rgb

local SELL_PERCENT = 0.6
local MODES = { "First", "Strongest", "Last", "Closest" }
local MODE_TEXT = { First = "First", Strongest = "Strong", Last = "Last", Closest = "Close" }
local MODE_ICON = { First = "first", Strongest = "strong", Last = "snail", Closest = "pin" }

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local INK = UIKit.C.Ink
local INFO = rgb(225, 228, 255)

local selectedTower = nil
local highlight, rangeAnchor = nil, nil
local connections = {}

local function num(n)
	if n >= 100 then return tostring(math.floor(n + 0.5)) end
	local s = string.format("%.1f", n)
	s = string.gsub(s, "%.0$", "")
	return s
end

-- убираем символы-звёздочки из текстов данных (картинки рисуем сами)
local function clean(s)
	s = string.gsub(tostring(s or ""), "★", "")
	s = string.gsub(s, "^%s+", "")
	return s
end

---------------------------------------------------------------- панель

local gui = new("ScreenGui", { Name = "TowerInfoGui", ResetOnSpawn = false, DisplayOrder = 6 }, player:WaitForChild("PlayerGui"))

local PANEL_W, PANEL_H = 286, 520

local panel = UIKit.panel(gui, {
	Name = "Panel",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -16, 0.5, -16),
	Size = UDim2.fromOffset(PANEL_W, PANEL_H),
	Visible = false,
}, rgb(110, 90, 230), rgb(40, 25, 110), { Radius = 24, OutlineThickness = 5, GlossHeight = 10, Gloss = false })
local panelScale = new("UIScale", {}, panel)

local function fit()
	return UIKit.fit(700, 0.55, 1)
end

-- шапка цвета редкости
local header = new("Frame", {
	Position = UDim2.fromOffset(6, 6),
	Size = UDim2.new(1, -12, 0, 66),
	BackgroundColor3 = WHITE,
	BorderSizePixel = 0,
}, panel)
corner(header, 19)
local headerGrad = new("UIGradient", { Rotation = 90 }, header)
stroke(header, INK, 3)
UIKit.shine(header, 19, 4)

local title = text(header, {
	Position = UDim2.fromOffset(14, 5),
	Size = UDim2.new(1, -70, 0, 34),
	Font = UIKit.Font.Title,
	TextSize = 28,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	ZIndex = 2,
})
local rarityLabel = text(header, {
	Position = UDim2.fromOffset(14, 38),
	Size = UDim2.new(1, -70, 0, 20),
	TextSize = 15,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	ZIndex = 2,
})

local close = UIKit.closeButton(panel, { Position = UDim2.new(1, -4, 0, 4), Size = UDim2.fromOffset(44, 46), TextSize = 24 })
local closeBtn = close.Button

-- звёзды уровня
local starsRow = new("Frame", {
	Position = UDim2.fromOffset(0, 76),
	Size = UDim2.new(1, 0, 0, 38),
	BackgroundTransparency = 1,
}, panel)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	Padding = UDim.new(0, 4),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, starsRow)
local stars = {}
for i = 1, UpgradeData.MaxLevel do
	stars[i] = icon(starsRow, "starEmpty", { Size = UDim2.fromOffset(36, 36), LayoutOrder = i })
end

-- характеристики
local statsBox = UIKit.well(panel, {
	Position = UDim2.fromOffset(12, 118),
	Size = UDim2.new(1, -24, 0, 128),
})

local statRows = {}
local function statRow(i, iconName, name)
	local y = 6 + (i - 1) * 30
	icon(statsBox, iconName, { Position = UDim2.fromOffset(8, y), Size = UDim2.fromOffset(28, 28) })
	text(statsBox, {
		Text = name,
		Position = UDim2.fromOffset(42, y),
		Size = UDim2.fromOffset(90, 28),
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = rgb(210, 210, 255),
	})
	statRows[i] = text(statsBox, {
		RichText = true,
		Position = UDim2.new(0, 120, 0, y),
		Size = UDim2.new(1, -130, 0, 28),
		Font = UIKit.Font.Title,
		TextSize = 19,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
end
statRow(1, "swords", "Damage")
statRow(2, "range", "Range")
statRow(3, "stopwatch", "Speed")
statRow(4, "skull", "Kills")

-- описание следующего уровня
local nextLabel = text(panel, {
	Position = UDim2.fromOffset(12, 250),
	Size = UDim2.new(1, -24, 0, 34),
	TextSize = 14,
	TextWrapped = true,
	TextColor3 = INFO,
})

-- кнопка улучшения: [стрелка] UPGRADE [монета] цена
local upgrade = UIKit.button(panel, {
	Position = UDim2.fromOffset(12, 288),
	Size = UDim2.new(1, -24, 0, 58),
	Color = "green",
	Icon = "upgrade",
	IconSize = 38,
	Text = "UPGRADE",
	Font = UIKit.Font.Title,
	TextSize = 24,
})
local upgradeBtn = upgrade.Button
local upgradeCoin = icon(upgrade.Content, "coin", { Size = UDim2.fromOffset(28, 28), LayoutOrder = 3 })
local upgradePrice = text(upgrade.Content, {
	Size = UDim2.new(0, 0, 1, 0),
	AutomaticSize = Enum.AutomaticSize.X,
	Font = UIKit.Font.Title,
	TextSize = 22,
	LayoutOrder = 4,
})
local upgradeScale = new("UIScale", {}, upgrade.Face)
local upgradePulse = TweenService:Create(upgradeScale,
	TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.05 })

-- активная способность (клавиша Q)
local ability = UIKit.button(panel, {
	Position = UDim2.fromOffset(12, 352),
	Size = UDim2.new(1, -24, 0, 58),
	Color = "purple",
})
local abilityBtn = ability.Button
ability.Content.Visible = false
local abilityCd = new("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = BLACK,
	BackgroundTransparency = 0.45,
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 2,
}, ability.Face)
corner(abilityCd, 14)
local abilityIcon = icon(ability.Face, nil, {
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 4, 0.5, 0),
	Size = UDim2.fromOffset(44, 44),
	ZIndex = 3,
})
local abilityName = text(ability.Face, {
	Position = UDim2.fromOffset(52, 4),
	Size = UDim2.new(1, -124, 0, 24),
	TextSize = 18,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	ZIndex = 3,
})
local abilityInfo = text(ability.Face, {
	Position = UDim2.fromOffset(52, 27),
	Size = UDim2.new(1, -124, 0, 18),
	TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	TextColor3 = rgb(235, 225, 255),
	ZIndex = 3,
})
local abilityLock = icon(ability.Face, "lock", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -46, 0.5, 0),
	Size = UDim2.fromOffset(26, 26),
	ZIndex = 3,
	Visible = false,
})
local abilityState = text(ability.Face, {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -8, 0.5, 0),
	Size = UDim2.fromOffset(66, 30),
	Font = UIKit.Font.Title,
	TextSize = 18,
	TextXAlignment = Enum.TextXAlignment.Right,
	ZIndex = 3,
})
local abilityScale = new("UIScale", {}, ability.Face)
local abilityPulse = TweenService:Create(abilityScale,
	TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.04 })
local abilityPulsing = false
local abilityFlashUntil = 0

-- строка «что даст следующий тир»; пока висит сообщение об отказе сервера — не перетираем его
local upgradeFlashUntil = 0
local function setNextText(s)
	if os.clock() > upgradeFlashUntil then
		nextLabel.Text = s
		nextLabel.TextColor3 = INFO
	end
end

-- режимы цели
text(panel, {
	Text = "TARGET",
	Position = UDim2.fromOffset(16, 414),
	Size = UDim2.fromOffset(120, 20),
	Font = UIKit.Font.Title,
	TextSize = 17,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = rgb(255, 230, 120),
})
local modeButtons = {}
for i, mode in ipairs(MODES) do
	local col = (i - 1) % 2
	local row = math.floor((i - 1) / 2)
	local b = UIKit.button(panel, {
		Position = UDim2.new(col * 0.5, col == 0 and 12 or 4, 0, 436 + row * 40),
		Size = UDim2.new(0.5, -16, 0, 38),
		Color = "night",
		Icon = MODE_ICON[mode],
		IconSize = 28,
		Text = MODE_TEXT[mode],
		TextSize = 17,
		Radius = 12,
		Depth = 4,
		Shine = false,
	})
	modeButtons[mode] = b
	b.Button.MouseButton1Click:Connect(function()
		if selectedTower then
			setTargetEvent:FireServer(selectedTower, mode)
		end
	end)
end

-- продажа (под панелью, чтобы не нажать случайно)
local sell = UIKit.button(panel, {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 1, 10),
	Size = UDim2.new(1, -50, 0, 50),
	Color = "red",
	Icon = "sell",
	IconSize = 34,
	Text = "SELL",
	Font = UIKit.Font.Title,
	TextSize = 22,
})
local sellBtn = sell.Button

---------------------------------------------------------------- круг радиуса

local function getBottomY(model)
	local lowest = math.huge
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part.Transparency < 1 then
			local cf, size = part.CFrame, part.Size
			local halfY = 0.5 * (
				math.abs(cf.RightVector.Y) * size.X
					+ math.abs(cf.UpVector.Y) * size.Y
					+ math.abs(cf.LookVector.Y) * size.Z
			)
			lowest = math.min(lowest, cf.Position.Y - halfY)
		end
	end
	return lowest
end

local function setRange(tower, range)
	if rangeAnchor then
		rangeAnchor:Destroy()
		rangeAnchor = nil
	end
	local cf = tower:GetBoundingBox()
	local bottomY = getBottomY(tower)
	if bottomY == math.huge then bottomY = cf.Position.Y end

	local anchor = Instance.new("Part")
	anchor.Name = "RangeAnchor"
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CFrame = CFrame.new(cf.Position.X, bottomY + 0.15, cf.Position.Z) * CFrame.Angles(-math.pi / 2, 0, 0)
	anchor.Parent = workspace

	local fill = Instance.new("CylinderHandleAdornment")
	fill.Adornee = anchor
	fill.Radius = range
	fill.InnerRadius = 0
	fill.Height = 0.05
	fill.Color3 = rgb(110, 190, 255)
	fill.Transparency = 0.85
	fill.Parent = anchor

	local edge = Instance.new("CylinderHandleAdornment")
	edge.Adornee = anchor
	edge.Radius = range
	edge.InnerRadius = math.max(range - 0.5, 0)
	edge.Height = 0.08
	edge.Color3 = rgb(170, 225, 255)
	edge.Transparency = 0.15
	edge.Parent = anchor

	rangeAnchor = anchor
end

---------------------------------------------------------------- логика

local function getCoins()
	local stats = player:FindFirstChild("leaderstats")
	local c = stats and stats:FindFirstChild("Coins")
	return c and c.Value or 0
end

local function getLevel(tower)
	return tower:GetAttribute("Level") or 0
end

local function statText(cur, nextVal)
	if nextVal and math.abs(nextVal - cur) > 0.001 then
		return string.format('%s <font color="#8CFF6E">&gt; %s</font>', num(cur), num(nextVal))
	end
	return num(cur)
end

local lastLevel = nil

local function setAbilityPulse(on)
	if on and not abilityPulsing then
		abilityPulse:Play()
	elseif not on and abilityPulsing then
		abilityPulse:Cancel()
		abilityScale.Scale = 1
	end
	abilityPulsing = on
end

-- состояние кнопки способности: нет / закрыта / перезарядка / готова
local function refreshAbility()
	local tower = selectedTower
	if not tower then return end
	local def = AbilityData.Get(tower.Name)

	if not def then
		UIKit.setIcon(abilityIcon, "sparkle")
		abilityName.Text = "Passive only"
		abilityInfo.Text = "This unit has no active power"
		abilityState.Text = ""
		abilityLock.Visible = false
		abilityCd.Visible = false
		ability.setColor("grey")
		setAbilityPulse(false)
		return
	end

	UIKit.setIcon(abilityIcon, UIKit.AbilityIcon[def.Id] or "lightning")
	abilityName.Text = def.Name
	if os.clock() > abilityFlashUntil then
		abilityInfo.Text = def.Description
		abilityInfo.TextColor3 = rgb(235, 225, 255)
	end

	if getLevel(tower) < (def.UnlockLevel or 0) then
		abilityState.Text = "Lv." .. def.UnlockLevel
		abilityLock.Visible = UIKit.IconsReady
		abilityCd.Visible = false
		ability.setColor("grey")
		setAbilityPulse(false)
		return
	end
	abilityLock.Visible = false

	local left = (tower:GetAttribute("AbilityReadyAt") or 0) - workspace:GetServerTimeNow()
	if left > 0 then
		abilityState.Text = math.ceil(left) .. "s"
		abilityCd.Visible = true
		abilityCd.Size = UDim2.fromScale(math.clamp(left / def.Cooldown, 0, 1), 1)
		ability.setColor("purple")
		setAbilityPulse(false)
	else
		abilityState.Text = "GO! [Q]"
		abilityCd.Visible = false
		ability.setColor("pink")
		setAbilityPulse(true)
	end
end

local function refresh()
	local tower = selectedTower
	if not tower then return end
	local base = TowerData[tower.Name]
	if not base then return end

	local level = getLevel(tower)
	local cur = UpgradeData.get(TowerData, tower.Name, level)
	local maxed = level >= UpgradeData.MaxLevel
	local nxt = not maxed and UpgradeData.get(TowerData, tower.Name, level + 1) or nil

	-- звёзды
	for i, s in ipairs(stars) do
		UIKit.setIcon(s, i <= level and "star" or "starEmpty")
	end
	if lastLevel and level > lastLevel then
		for i = lastLevel + 1, level do
			if stars[i] then
				UIKit.pop(stars[i], 2, 0.45)
			end
		end
		setRange(tower, cur.Range or 20)
	end
	lastLevel = level

	-- характеристики
	statRows[1].Text = statText(cur.Damage or 0, nxt and nxt.Damage)
	statRows[2].Text = statText(cur.Range or 0, nxt and nxt.Range)
	statRows[3].Text = statText(1 / (cur.Cooldown or 1), nxt and 1 / (nxt.Cooldown or 1)) .. "/s"
	statRows[4].Text = tostring(tower:GetAttribute("Kills") or 0)

	-- улучшение
	if maxed then
		setNextText(cur.Special and string.format("%s: %s", cur.Special, cur.SpecialDescription or "")
			or "Fully upgraded!")
		upgrade.setText("MAX LEVEL")
		upgrade.setIcon("crown")
		upgradeCoin.Visible = false
		upgradePrice.Visible = false
		upgrade.setColor("yellow")
		upgradePulse:Cancel()
		upgradeScale.Scale = 1
	else
		local cost = UpgradeData.getCost(base, level + 1)
		local canAfford = getCoins() >= cost
		setNextText(clean(UpgradeData.describe(TowerData, tower.Name, level + 1)))
		upgrade.setText("UPGRADE")
		upgrade.setIcon("upgrade")
		upgradeCoin.Visible = UIKit.IconsReady
		upgradePrice.Visible = true
		upgradePrice.Text = tostring(cost)
		upgradePrice.TextColor3 = canAfford and WHITE or rgb(255, 160, 160)
		if canAfford then
			upgrade.setColor("green")
			upgradePulse:Play()
		else
			upgrade.setColor("grey")
			upgradePulse:Cancel()
			upgradeScale.Scale = 1
		end
	end

	-- режим цели
	local mode = tower:GetAttribute("TargetMode") or base.TargetMode or "First"
	for m, b in pairs(modeButtons) do
		b.setColor(m == mode and "cyan" or "night")
	end

	-- продажа
	local invested = tower:GetAttribute("Invested") or base.Price
	sell.setText("SELL  " .. math.floor(invested * SELL_PERCENT))

	refreshAbility()
end

local function deselect()
	for _, c in ipairs(connections) do
		c:Disconnect()
	end
	connections = {}
	if highlight then highlight:Destroy() highlight = nil end
	if rangeAnchor then rangeAnchor:Destroy() rangeAnchor = nil end
	upgradePulse:Cancel()
	setAbilityPulse(false)
	selectedTower = nil
	lastLevel = nil
	panel.Visible = false
end

local function selectTower(tower)
	if selectedTower == tower then return end
	deselect()
	if tower:GetAttribute("OwnerId") ~= player.UserId then return end
	local base = TowerData[tower.Name]
	if not base then return end

	selectedTower = tower
	lastLevel = getLevel(tower)

	local rar = RarityData[base.Rarity or "Common"] or RarityData.Common
	title.Text = tower.Name
	rarityLabel.Text = string.upper(base.Rarity or "Common") .. "  -  " .. (base.Ability or "")
	headerGrad.Color = ColorSequence.new(rar.Color:Lerp(WHITE, 0.35), rar.Color:Lerp(BLACK, 0.2))

	panel.Visible = true
	panelScale.Scale = fit() * 0.6
	TweenService:Create(panelScale, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = fit() }):Play()

	highlight = Instance.new("Highlight")
	highlight.Adornee = tower
	highlight.FillColor = rar.Color
	highlight.FillTransparency = 0.8
	highlight.OutlineColor = rar.Color:Lerp(WHITE, 0.3)
	highlight.Parent = tower

	setRange(tower, UpgradeData.get(TowerData, tower.Name, lastLevel).Range or 20)

	for _, attr in ipairs({ "Level", "TargetMode", "Invested", "Kills", "AbilityReadyAt" }) do
		table.insert(connections, tower:GetAttributeChangedSignal(attr):Connect(refresh))
	end
	table.insert(connections, tower.AncestryChanged:Connect(function()
		if not tower:IsDescendantOf(towersFolder) and selectedTower == tower then
			deselect()
		end
	end))
	task.spawn(function()
		local stats = player:WaitForChild("leaderstats", 5)
		local coins = stats and stats:WaitForChild("Coins", 5)
		if coins and selectedTower == tower then
			table.insert(connections, coins:GetPropertyChangedSignal("Value"):Connect(refresh))
		end
	end)

	refresh()
end

local function tryUpgrade()
	local tower = selectedTower
	if not tower then return end
	local base = TowerData[tower.Name]
	local level = getLevel(tower)
	if level >= UpgradeData.MaxLevel then return end
	if getCoins() < UpgradeData.getCost(base, level + 1) then
		UIKit.shake(upgradeBtn)
		return
	end
	upgradeEvent:FireServer(tower)
end

local function tryAbility()
	local tower = selectedTower
	if not tower then return end
	local def = AbilityData.Get(tower.Name)
	if not def or getLevel(tower) < (def.UnlockLevel or 0)
		or (tower:GetAttribute("AbilityReadyAt") or 0) > workspace:GetServerTimeNow() then
		UIKit.shake(abilityBtn)
		return
	end
	if not useAbilityEvent then
		UIKit.shake(abilityBtn)
		return
	end
	useAbilityEvent:FireServer(tower)
end

-- ответ сервера: способность сработала или почему нет
local function onAbilityReply(kind, info)
	if kind == "fail" then
		abilityInfo.Text = tostring(info or "Can't use now")
		abilityInfo.TextColor3 = rgb(255, 150, 150)
		abilityFlashUntil = os.clock() + 1.5
		UIKit.shake(abilityBtn)
	elseif kind == "ok" then
		setAbilityPulse(false)
		abilityScale.Scale = 1.15
		TweenService:Create(abilityScale, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end
end
-- ответ сервера на улучшение: при отказе показываем причину (например, не хватило монет)
upgradeEvent.OnClientEvent:Connect(function(kind, info)
	if kind ~= "fail" then return end
	upgradeFlashUntil = os.clock() + 1.5
	nextLabel.Text = tostring(info or "Can't upgrade")
	nextLabel.TextColor3 = rgb(255, 150, 150)
	UIKit.shake(upgradeBtn)
	task.delay(1.6, function()
		if selectedTower then refresh() end
	end)
end)

task.spawn(function()
	useAbilityEvent = useAbilityEvent or ReplicatedStorage:WaitForChild("UseAbility")
	useAbilityEvent.OnClientEvent:Connect(onAbilityReply)
end)

-- таймер перезарядки на кнопке
local abilityAcc = 0
RunService.Heartbeat:Connect(function(dt)
	if not panel.Visible then return end
	abilityAcc += dt
	if abilityAcc < 0.1 then return end
	abilityAcc = 0
	refreshAbility()
end)

closeBtn.MouseButton1Click:Connect(deselect)
upgradeBtn.MouseButton1Click:Connect(tryUpgrade)
abilityBtn.MouseButton1Click:Connect(tryAbility)
sellBtn.MouseButton1Click:Connect(function()
	if selectedTower then
		sellEvent:FireServer(selectedTower)
		deselect()
	end
end)

---------------------------------------------------------------- выбор башни кликом / тапом

local function findTower(part)
	local current = part
	while current and current.Parent do
		if current.Parent == towersFolder then
			return current
		end
		current = current.Parent
	end
	return nil
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if input.KeyCode == Enum.KeyCode.E then
		tryUpgrade()
		return
	end
	if input.KeyCode == Enum.KeyCode.Q then
		tryAbility()
		return
	end

	local t = input.UserInputType
	if t ~= Enum.UserInputType.MouseButton1 and t ~= Enum.UserInputType.Touch then return end
	if player:GetAttribute("Placing") then return end

	local cam = workspace.CurrentCamera
	if not cam then return end
	local ray = cam:ScreenPointToRay(input.Position.X, input.Position.Y)
	rayParams.FilterDescendantsInstances = { towersFolder }
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 1000, rayParams)
	local tower = hit and findTower(hit.Instance)

	if tower then
		selectTower(tower)
	else
		deselect()
	end
end)
