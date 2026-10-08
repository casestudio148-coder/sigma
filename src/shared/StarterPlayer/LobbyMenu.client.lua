-- StarterPlayer.StarterPlayerScripts.LobbyMenu (LocalScript)
-- Яркое боковое меню: валюты, 10 больших кнопок с картинками, окна.
--   Units    — коллекция юнитов: свои с числом копий, чужие под замком
--   Summon   — кейсы (окно открывает CaseUI)
--   Rewards  — награды за время игры (таймеры, кнопка CLAIM)
--   Daily    — награда каждый день, серия 7 дней
--   Shop     — сундуки и Cash за гемы, гемы за Robux
--   Quests   — 3 задания на день
--   Clans    — создать / вступить / выйти, список участников
--   Codes    — промокоды
--   Settings — эффекты, тряска камеры, искры, звук
--   Trades   — заблокирован (появится позже)
-- Сервер для Daily / Shop / Quests / Clans / Codes / Settings — MetaService, таблицы — MetaConfig.
-- Всё строится кодом, вручную в StarterGui ничего создавать не нужно.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))
local TowerData = require(ReplicatedStorage:WaitForChild("TowerData"))
local RarityData = require(ReplicatedStorage:WaitForChild("RarityData"))
local Config = require(ReplicatedStorage:WaitForChild("PlaytimeConfig"))
local claimEvent = ReplicatedStorage:WaitForChild("ClaimPlaytimeReward")
local grantedEvent = ReplicatedStorage:WaitForChild("PlaytimeRewardGranted")

local new, corner, stroke, tween = UIKit.new, UIKit.corner, UIKit.stroke, UIKit.tween
local text, icon, rgb, C = UIKit.text, UIKit.icon, UIKit.rgb, UIKit.C
local WHITE = Color3.new(1, 1, 1)

---------------------------------------------------------------- главный экран

local gui = new("ScreenGui", {
	Name = "LobbyMenu",
	ResetOnSpawn = false,
	IgnoreGuiInset = false,
	DisplayOrder = 8,
}, playerGui)

local function toast(msg, color, iconName)
	UIKit.toast(gui, msg, { Color = color, Icon = iconName, Y = 150 })
end

---------------------------------------------------------------- меню слева

local MENU_W, MENU_H = 204, 548

local menu = new("Frame", {
	Name = "Menu",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 14, 0.5, 14),
	Size = UDim2.fromOffset(MENU_W, MENU_H),
	BackgroundTransparency = 1,
}, gui)
local menuScale = UIKit.fitScale(new("UIScale", {}, menu), 800, 0.55, 1)

-- валюты: три пилюли с картинками
local strip = new("Frame", { Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1 }, menu)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	Padding = UDim.new(0, 5),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, strip)

local currencyLabels = {}
local currencyIcons = {}
local function currencyPill(key, order, color)
	local pill = new("Frame", {
		Size = UDim2.new(1 / 3, -4, 0, 34),
		Position = UDim2.fromOffset(0, 6),
		BackgroundColor3 = rgb(32, 20, 72),
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		LayoutOrder = order,
	}, strip)
	corner(pill, 17)
	stroke(pill, color, 3)
	currencyIcons[key] = icon(pill, UIKit.CurrencyIcon[key], {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, -8, 0.5, 0),
		Size = UDim2.fromOffset(38, 38),
		ZIndex = 2,
	})
	currencyLabels[key] = text(pill, {
		Position = UDim2.fromOffset(28, 0),
		Size = UDim2.new(1, -32, 1, 0),
		Text = "0",
		Font = UIKit.Font.Title,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = color:Lerp(WHITE, 0.45),
	})
end
currencyPill("Cash", 1, rgb(255, 200, 40))
currencyPill("Gems", 2, rgb(215, 120, 255))
currencyPill("Cases", 3, rgb(255, 150, 60))

task.spawn(function()
	local data = player:WaitForChild("Data")
	for key, lbl in pairs(currencyLabels) do
		local v = data:WaitForChild(key)
		local last = v.Value
		local function upd()
			lbl.Text = UIKit.short(v.Value)
			if v.Value > last then
				UIKit.pop(currencyIcons[key], 1.6, 0.4)
			end
			last = v.Value
		end
		v:GetPropertyChangedSignal("Value"):Connect(upd)
		upd()
	end
end)

-- сетка больших кнопок
local grid = new("Frame", {
	Position = UDim2.fromOffset(0, 54),
	Size = UDim2.new(1, 0, 1, -54),
	BackgroundTransparency = 1,
}, menu)
new("UIGridLayout", {
	CellSize = UDim2.fromOffset(96, 90),
	CellPadding = UDim2.fromOffset(12, 8),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, grid)

local BUTTONS = {
	{ id = "Inventory", text = "Units", icon = "backpack", color = "orange" },
	{ id = "Summon", text = "Summon", icon = "summon", color = "grey", locked = true },
	{ id = "Playtime", text = "Rewards", icon = "gift", color = "yellow", wobble = true },
	{ id = "Daily", text = "Daily", icon = "calendar", color = "blue" },
	{ id = "Shop", text = "Shop", icon = "shop", color = "pink", wobble = true },
	{ id = "Quests", text = "Quests", icon = "scroll", color = "orange" },
	{ id = "Trades", text = "Trades", icon = "trade", color = "grey", locked = true },
	{ id = "Clans", text = "Clans", icon = "shield", color = "green" },
	{ id = "Codes", text = "Codes", icon = "ticket", color = "cyan" },
	{ id = "Settings", text = "Settings", icon = "gear", color = "night" },
}

local tiles = {}
local handlers = {}
local openWin = nil -- открытое сейчас окно меню

local function makeTile(def, order)
	local api = UIKit.button(grid, {
		Name = def.id,
		Color = def.color,
		LayoutOrder = order,
		Radius = 18,
		Depth = 6,
		Shine = not def.locked,
	})
	local face = api.Face
	local img = icon(face, def.icon, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 2),
		Size = UDim2.fromOffset(56, 56),
		ImageTransparency = def.locked and 0.4 or 0,
		ZIndex = 2,
	})
	if def.wobble then
		UIKit.wobble(img, 6, 1.1)
	end
	local name = text(face, {
		Text = def.text,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -3),
		Size = UDim2.new(1, 4, 0, 22),
		TextSize = 17,
		ZIndex = 3,
		TextColor3 = def.locked and rgb(225, 225, 235) or WHITE,
	})
	if def.locked then
		icon(face, "lock", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 8, 0, -8),
			Size = UDim2.fromOffset(32, 32),
			ZIndex = 4,
		})
	end

	api.Button.MouseButton1Click:Connect(function()
		if def.locked then
			UIKit.shake(api.Button)
			toast(def.text .. " coming soon!", rgb(230, 230, 240), "lock")
			return
		end
		local h = handlers[def.id]
		if h then
			h()
			if openWin then openWin.busId = def.id end
		end
	end)

	tiles[def.id] = { button = api.Button, face = face, icon = img, name = name }
	return tiles[def.id]
end

for i, def in ipairs(BUTTONS) do
	makeTile(def, i)
end

-- кнопка свернуть / развернуть меню
local collapsed = false
local toggleApi = UIKit.button(menu, {
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(1, 8, 0.5, 20),
	Size = UDim2.fromOffset(40, 66),
	Color = "night",
	Icon = "arrowLeft",
	IconSize = 30,
	Radius = 12,
	Depth = 4,
	Shine = false,
})
toggleApi.Button.MouseButton1Click:Connect(function()
	collapsed = not collapsed
	toggleApi.setIcon(collapsed and "arrowRight" or "arrowLeft")
	local x = collapsed and -(MENU_W * menuScale.Scale) + 4 or 14
	tween(menu, 0.3, { Position = UDim2.new(0, x, 0.5, 14) }, Enum.EasingStyle.Back)
end)

---------------------------------------------------------------- окна

local winGui = new("ScreenGui", {
	Name = "LobbyWindows",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 12,
}, playerGui)

-- темы окон: верх / низ плашки
local THEMES = {
	blue = { rgb(110, 200, 255), rgb(55, 95, 235) },
	green = { rgb(130, 235, 140), rgb(30, 150, 90) },
	purple = { rgb(200, 150, 255), rgb(105, 50, 220) },
	orange = { rgb(255, 205, 110), rgb(235, 105, 40) },
	pink = { rgb(255, 170, 225), rgb(220, 60, 150) },
}

local function makeWindow(o)
	local w = UIKit.window(winGui, {
		Title = o.title,
		Icon = o.icon,
		Width = o.w,
		Height = o.h,
		Theme = THEMES[o.theme or "blue"],
		Ribbon = o.ribbon or "yellow",
	})
	local win = { root = w.Root, content = w.Content, ui = w }

	function win.open()
		if openWin and openWin ~= win then openWin.close() end
		openWin = win
		w.show()
		if win.onOpen then win.onOpen() end
	end

	function win.close()
		w.hide()
		if openWin == win then openWin = nil end
	end

	function win.toggle()
		if w.Root.Visible then win.close() else win.open() end
	end

	w.Close.Button.MouseButton1Click:Connect(win.close)
	return win
end

---------------------------------------------------------------- INVENTORY

local invWin = makeWindow({ title = "My Units", icon = "backpack", w = 700, h = 500, theme = "blue", ribbon = "orange" })

local invCount = text(invWin.content, {
	Size = UDim2.new(1, 0, 0, 26),
	TextSize = 20,
	TextXAlignment = Enum.TextXAlignment.Left,
})

local invWell = UIKit.well(invWin.content, {
	Position = UDim2.fromOffset(0, 32),
	Size = UDim2.new(1, 0, 1, -122),
})
local invScroll = new("ScrollingFrame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 8,
	ScrollBarImageColor3 = rgb(255, 220, 90),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	CanvasSize = UDim2.new(),
}, invWell)
new("UIGridLayout", {
	CellSize = UDim2.fromOffset(118, 150),
	CellPadding = UDim2.fromOffset(12, 12),
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder,
}, invScroll)
new("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10) }, invScroll)

-- нижняя плашка с характеристиками выбранного юнита
local invInfo = UIKit.well(invWin.content, {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.fromScale(0, 1),
	Size = UDim2.new(1, 0, 0, 82),
	BackgroundTransparency = 0.3,
})
local infoName = text(invInfo, {
	Position = UDim2.fromOffset(14, 6),
	Size = UDim2.new(0.42, 0, 0, 30),
	TextSize = 24,
	Font = UIKit.Font.Title,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "Tap a unit!",
})
local chips = new("Frame", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -10, 0, 6),
	Size = UDim2.new(0.58, 0, 0, 30),
	BackgroundTransparency = 1,
	Visible = false,
}, invInfo)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Right,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	Padding = UDim.new(0, 10),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, chips)
local chipLabels = {}
for i, iconName in ipairs({ "swords", "range", "stopwatch", "coin" }) do
	local chip = new("Frame", { Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, LayoutOrder = i }, chips)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }, chip)
	icon(chip, iconName, { Size = UDim2.fromOffset(28, 28), LayoutOrder = 1 })
	chipLabels[i] = text(chip, { Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, TextSize = 19, LayoutOrder = 2, Text = "" })
end
local abilityIcon = icon(invInfo, "lightning", {
	Position = UDim2.fromOffset(10, 42),
	Size = UDim2.fromOffset(30, 30),
	Visible = false,
})
local infoText = text(invInfo, {
	Position = UDim2.fromOffset(44, 40),
	Size = UDim2.new(1, -54, 0, 36),
	TextSize = 15,
	TextWrapped = true,
	RichText = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = rgb(225, 232, 255),
	Text = "See damage, range and the special power of every unit",
})

local unitNames = UIKit.sortedTowerNames(TowerData)
invCount.Text = "Units: " .. #unitNames

-- свои юниты: папка Data.Units (сколько копий у игрока)
local function unitsFolder()
	local data = player:FindFirstChild("Data")
	return data and data:FindFirstChild("Units")
end
local function copies(name)
	local f = unitsFolder()
	local v = f and f:FindFirstChild(name)
	return v and v.Value or 0
end
local invCards = {}
local function refreshInventory()
	local owned = 0
	for i, name in ipairs(unitNames) do
		local c = invCards[name]
		local n = copies(name)
		if n > 0 then owned += 1 end
		if c then
			c.lock.Visible = n == 0
			c.copies.Visible = n > 1
			c.copies.Text = "x" .. n
			c.card.LayoutOrder = n > 0 and i or (100 + i)
		end
	end
	invCount.Text = string.format("Collected: %d / %d", owned, #unitNames)
end

-- карточки строятся только при первом открытии окна
local inventoryBuilt = false
local function buildInventory()
	if inventoryBuilt then return end
	inventoryBuilt = true

	for i, name in ipairs(unitNames) do
		local cfg = TowerData[name]
		local rar = RarityData[cfg.Rarity] or RarityData.Common

		local card = new("TextButton", {
			Name = name,
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			LayoutOrder = i,
		}, invScroll)
		local back = UIKit.rarityBack(card, rar.Color)
		local sc = new("UIScale", {}, card)

		local holder = new("Frame", {
			Position = UDim2.fromOffset(4, 6),
			Size = UDim2.new(1, -8, 0, 86),
			BackgroundTransparency = 1,
			ZIndex = 2,
		}, back)
		UIKit.makeIcon(holder, name)

		text(back, { Text = name, Position = UDim2.fromOffset(2, 94), Size = UDim2.new(1, -4, 0, 24), TextSize = 17, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 2 })
		text(back, { Text = string.upper(cfg.Rarity or "Common"), Position = UDim2.fromOffset(0, 118), Size = UDim2.new(1, 0, 0, 20), TextSize = 15, Font = UIKit.Font.Title, TextColor3 = rar.Color:Lerp(WHITE, 0.35), ZIndex = 2 })
		if (UIKit.Rank[cfg.Rarity] or 1) >= 4 then
			UIKit.sparkles(back, rar.Color:Lerp(WHITE, 0.5), 2, 5)
		end

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
			Position = UDim2.fromScale(0.5, 0.4),
			Size = UDim2.fromOffset(52, 52),
			ZIndex = 8,
		})
		local copiesLabel = text(back, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -6, 0, 4),
			Size = UDim2.fromOffset(44, 22),
			Font = UIKit.Font.Title,
			TextSize = 18,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = rgb(255, 230, 120),
			ZIndex = 6,
			Visible = false,
		})
		invCards[name] = { card = card, lock = lock, copies = copiesLabel }

		card.MouseEnter:Connect(function() tween(sc, 0.12, { Scale = 1.05 }) end)
		card.MouseLeave:Connect(function() tween(sc, 0.12, { Scale = 1 }) end)
		card.MouseButton1Click:Connect(function()
			UIKit.pop(card, 0.9, 0.25)
			infoName.Text = name
			infoName.TextColor3 = rar.Color:Lerp(WHITE, 0.4)
			chips.Visible = true
			chipLabels[1].Text = tostring(cfg.Damage or 0)
			chipLabels[2].Text = tostring(cfg.Range or 0)
			chipLabels[3].Text = string.format("%.1fs", cfg.Cooldown or 0)
			chipLabels[4].Text = tostring(cfg.Price or 0)
			abilityIcon.Visible = UIKit.IconsReady
			infoText.Text = string.format('<font color="#FFE066">%s:</font> %s', cfg.Ability or "-", cfg.Description or "")
			if copies(name) == 0 then
				infoText.Text ..= '  <font color="#FF9AA8">Get it in the Shop!</font>'
			end
		end)
	end
	refreshInventory()
	local f = unitsFolder()
	if f then
		f.ChildAdded:Connect(function(v)
			refreshInventory()
			v.Changed:Connect(refreshInventory)
		end)
		for _, v in ipairs(f:GetChildren()) do
			v.Changed:Connect(refreshInventory)
		end
	end
end

invWin.onOpen = function()
	buildInventory()
	refreshInventory()
end
handlers.Inventory = invWin.toggle

---------------------------------------------------------------- PLAYTIME REWARDS

local ptWin = makeWindow({ title = "Rewards", icon = "gift", w = 500, h = 500, theme = "purple", ribbon = "yellow" })

local sessionRow = new("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1 }, ptWin.content)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	Padding = UDim.new(0, 6),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, sessionRow)
icon(sessionRow, "stopwatch", { Size = UDim2.fromOffset(30, 30), LayoutOrder = 1 })
local sessionLabel = text(sessionRow, {
	Size = UDim2.new(0, 0, 1, 0),
	AutomaticSize = Enum.AutomaticSize.X,
	TextSize = 22,
	Text = "Playing: 00:00",
	LayoutOrder = 2,
})

local ptGrid = new("Frame", {
	Position = UDim2.fromOffset(0, 38),
	Size = UDim2.new(1, 0, 1, -66),
	BackgroundTransparency = 1,
}, ptWin.content)
new("UIGridLayout", {
	CellSize = UDim2.new(1 / 3, -10, 1 / 3, -10),
	CellPadding = UDim2.fromOffset(14, 14),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, ptGrid)

text(ptWin.content, {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.fromScale(0, 1),
	Size = UDim2.new(1, 0, 0, 20),
	TextSize = 15,
	TextColor3 = rgb(240, 230, 255),
	Text = "Stay in the game to unlock rewards! Timer resets when you leave.",
})

local TYPE_COLORS = { Cash = rgb(255, 225, 90), Gems = rgb(230, 160, 255), Cases = rgb(255, 170, 80) }
local cells = {}

for i, r in ipairs(Config.Rewards) do
	local cell = new("Frame", {
		BackgroundColor3 = rgb(40, 22, 95),
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		LayoutOrder = i,
	}, ptGrid)
	corner(cell, 16)
	local cellStroke = stroke(cell, rgb(150, 120, 230), 3)
	local cellScale = new("UIScale", {}, cell)
	local glow = UIKit.glow(cell, TYPE_COLORS[r.Type] or WHITE, UDim2.fromScale(1.1, 1.1), { Visible = false, ImageTransparency = 0.3 })

	local img = icon(cell, UIKit.CurrencyIcon[r.Type] or "gift", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.04, 0),
		Size = UDim2.fromScale(0.5, 0.42),
		ZIndex = 2,
	})
	new("UIAspectRatioConstraint", {}, img)

	local amount = text(cell, {
		Text = "x" .. r.Amount,
		Position = UDim2.fromScale(0, 0.46),
		Size = UDim2.new(1, 0, 0.2, 0),
		Font = UIKit.Font.Title,
		TextSize = 24,
		TextColor3 = TYPE_COLORS[r.Type] or WHITE,
		ZIndex = 2,
	})

	local timer = text(cell, {
		Text = "",
		Position = UDim2.fromScale(0, 0.7),
		Size = UDim2.new(1, 0, 0.22, 0),
		TextSize = 19,
		TextColor3 = rgb(225, 225, 245),
		ZIndex = 2,
	})

	local claim = UIKit.button(cell, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -6),
		Size = UDim2.new(0.86, 0, 0, 36),
		Color = "green",
		Text = "CLAIM!",
		Font = UIKit.Font.Title,
		TextSize = 19,
		Radius = 12,
		Depth = 4,
		ZIndex = 3,
		Visible = false,
	})
	local claimScale = new("UIScale", {}, claim.Face)

	local check = icon(cell, "check", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromScale(0.6, 0.6),
		ZIndex = 3,
		Visible = false,
	})
	new("UIAspectRatioConstraint", {}, check)

	claim.Button.MouseButton1Click:Connect(function()
		claimEvent:FireServer(i)
	end)

	cells[i] = {
		frame = cell, stroke = cellStroke, scale = cellScale, amount = amount, glow = glow,
		timer = timer, claim = claim.Button, claimScale = claimScale, check = check,
		img = img, state = nil, pulse = nil, wobble = nil,
	}
end

local function setCellState(c, state)
	if c.state == state then return end
	c.state = state

	if c.pulse then
		c.pulse:Cancel()
		c.pulse = nil
		c.claimScale.Scale = 1
	end
	if c.wobble then
		c.wobble:Cancel()
		c.wobble = nil
		c.img.Rotation = 0
	end
	UIKit.stopSparkles(c.frame)

	c.claim.Visible = state == "ready"
	c.timer.Visible = state == "locked"
	c.check.Visible = state == "claimed" and UIKit.IconsReady
	c.amount.Visible = state ~= "claimed"
	c.img.Visible = state ~= "claimed"
	c.glow.Visible = state == "ready"

	if state == "ready" then
		c.stroke.Color = rgb(255, 225, 80)
		c.stroke.Thickness = 4
		c.frame.BackgroundTransparency = 0.05
		c.pulse = UIKit.pulse(c.claimScale, 1.08, 0.5)
		c.wobble = UIKit.wobble(c.img, 8, 0.6)
		UIKit.sparkles(c.frame, rgb(255, 240, 160), 4, 6)
	elseif state == "claimed" then
		c.stroke.Color = rgb(120, 230, 140)
		c.stroke.Thickness = 3
		c.frame.BackgroundTransparency = 0.45
	else
		c.stroke.Color = rgb(150, 120, 230)
		c.stroke.Thickness = 3
		c.frame.BackgroundTransparency = 0.15
	end
end

local function getElapsed()
	local start = player:GetAttribute("SessionStart")
	if not start then return 0 end
	return math.max(0, workspace:GetServerTimeNow() - start)
end

local function getClaimed()
	local set = {}
	for _, v in ipairs(string.split(player:GetAttribute("PlaytimeClaimed") or "", ",")) do
		local n = tonumber(v)
		if n then set[n] = true end
	end
	return set
end

-- таймер и красный значок на кнопке Rewards
local ptTile = tiles.Playtime
local tileTimer = text(ptTile.face, {
	Text = "",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, -16),
	Size = UDim2.fromOffset(84, 20),
	TextSize = 16,
	ZIndex = 5,
})
local dot = new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(1, -4, 0, 4),
	Size = UDim2.fromOffset(28, 28),
	BackgroundColor3 = rgb(255, 50, 80),
	Font = UIKit.Font.Title,
	Text = "!",
	TextSize = 20,
	TextColor3 = WHITE,
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 6,
}, ptTile.face)
corner(dot, 14)
stroke(dot, WHITE, 3)
UIKit.pulse(new("UIScale", {}, dot), 1.2, 0.45)

local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < 0.2 then return end
	acc = 0

	local elapsed = getElapsed()
	local claimed = getClaimed()
	local ready, nextLeft = 0, nil

	for i, c in ipairs(cells) do
		local need = Config.getTime(i)
		if claimed[i] then
			setCellState(c, "claimed")
		elseif elapsed >= need then
			setCellState(c, "ready")
			ready += 1
		else
			setCellState(c, "locked")
			local left = need - elapsed
			c.timer.Text = Config.format(left)
			nextLeft = nextLeft and math.min(nextLeft, left) or left
		end
	end

	sessionLabel.Text = "Playing: " .. Config.format(elapsed)

	if ready > 0 then
		tileTimer.Text = "READY!"
		tileTimer.TextColor3 = rgb(150, 255, 150)
		dot.Visible = true
	elseif nextLeft then
		tileTimer.Text = Config.format(nextLeft)
		tileTimer.TextColor3 = WHITE
		dot.Visible = false
	else
		tileTimer.Text = ""
		dot.Visible = false
	end
end)

local TYPE_NAMES = { Cash = "Cash", Gems = "Gems", Cases = "Cases" }

grantedEvent.OnClientEvent:Connect(function(index)
	local r = Config.Rewards[index]
	local c = cells[index]
	if not r or not c then return end
	c.scale.Scale = 1.2
	tween(c.scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	toast("+" .. r.Amount .. " " .. (TYPE_NAMES[r.Type] or "") .. "!", TYPE_COLORS[r.Type], UIKit.CurrencyIcon[r.Type])
end)

handlers.Playtime = ptWin.toggle

-- по кнопке Shop закрываем открытое окно меню (магазин с сундуками откроет CaseUI)
handlers.Shop = function()
	if openWin then openWin.close() end
end

---------------------------------------------------------------- не мешаем экрану выбора юнитов

local function refreshPhase()
	local phase = workspace:GetAttribute("Phase")
	local selecting = phase == nil or phase == "Selection"
	gui.Enabled = not selecting
	winGui.Enabled = not selecting
	if selecting and openWin then
		openWin.close()
	end
end

workspace:GetAttributeChangedSignal("Phase"):Connect(refreshPhase)
refreshPhase()

---------------------------------------------------------------- DAILY / SHOP / QUESTS / CLANS / CODES / SETTINGS
-- пока грузится — кнопка отвечает «Loading...», а не молчит
local META_IDS = { "Daily", "Quests", "Clans", "Codes", "Settings" }
for _, id in ipairs(META_IDS) do
	handlers[id] = function()
		toast("Loading... try again in a second", rgb(230, 230, 240), "stopwatch")
	end
end

-- строится в отдельном потоке: если сервер меню не найден, остальное меню всё равно работает
task.spawn(function()
	---------------------------------------------------------------- ОБЩЕЕ ДЛЯ DAILY / SHOP / QUESTS / CLANS / CODES / SETTINGS


	-- проверка, что серверная часть меню на месте (ждём не дольше 15 сек, меню не зависает)
	local function fail(why)
		warn("[LobbyMenu] " .. why)
		for _, id in ipairs(META_IDS) do
			handlers[id] = function()
				toast(why, rgb(255, 160, 170), "warning")
			end
		end
	end

	local cfgObj = ReplicatedStorage:WaitForChild("MetaConfig", 15)
	if not cfgObj or not cfgObj:IsA("ModuleScript") then
		fail("MetaConfig not found: it must be a ModuleScript in ReplicatedStorage")
		return
	end
	local okCfg, MetaConfig = pcall(require, cfgObj)
	if not okCfg or typeof(MetaConfig) ~= "table" then
		warn("[LobbyMenu] MetaConfig error: " .. tostring(MetaConfig))
		fail("MetaConfig is broken: paste its code again")
		return
	end
	local metaRemote = ReplicatedStorage:WaitForChild("Meta", 15)
	local metaPush = ReplicatedStorage:WaitForChild("MetaPush", 15)
	if not metaRemote or not metaPush then
		fail("MetaService not running: it must be a Script in ServerScriptService")
		return
	end

	-- каждый раздел строится отдельно: ошибка в одном не ломает остальные
	local function section(id, build)
		local ok, err = pcall(build)
		if not ok then
			warn("[LobbyMenu] " .. id .. " error: " .. tostring(err))
			handlers[id] = function()
				toast(id .. " error: look in Output", rgb(255, 160, 170), "warning")
			end
		end
	end

	local metaState = nil
	local metaListeners = {}
	local function setMetaState(st)
		if typeof(st) ~= "table" then return end
		metaState = st
		for _, f in ipairs(metaListeners) do
			task.spawn(f, st)
		end
	end
	local function onMeta(f)
		table.insert(metaListeners, f)
		if metaState then task.spawn(f, metaState) end
	end
	metaPush.OnClientEvent:Connect(setMetaState)

	-- первая (главная) валюта награды → картинка и текст «+200»
	local CUR_ORDER = { "Gems", "Cases", "Cash" }
	local function rewardMain(bundle)
		for _, k in ipairs(CUR_ORDER) do
			if bundle and bundle[k] then return k, bundle[k] end
		end
		return "Cash", 0
	end
	local function rewardText(bundle)
		local parts = {}
		for _, k in ipairs(CUR_ORDER) do
			if bundle and bundle[k] then
				table.insert(parts, "+" .. UIKit.short(bundle[k]))
			end
		end
		return table.concat(parts, "  ")
	end

	local GOOD, BAD = rgb(150, 255, 150), rgb(255, 160, 170)

	-- запрос на сервер: показывает сообщение сервера и обновляет состояние
	local function call(action, ...)
		local args = table.pack(...)
		local ok, res = pcall(function()
			return metaRemote:InvokeServer(action, table.unpack(args, 1, args.n))
		end)
		if not ok or typeof(res) ~= "table" then
			toast("Try again in a moment", BAD, "warning")
			return nil
		end
		setMetaState(res.state)
		if res.msg then
			local cur = res.reward and (rewardMain(res.reward))
			toast(res.msg, res.ok and GOOD or BAD, res.ok and (cur and UIKit.CurrencyIcon[cur] or "check") or "warning")
		end
		return res
	end

	local function timeLeft(at)
		local left = math.max(0, math.floor(at - workspace:GetServerTimeNow()))
		return string.format("%02d:%02d:%02d", math.floor(left / 3600), math.floor(left % 3600 / 60), left % 60)
	end

	-- поле ввода в мультяшном стиле
	local function inputBox(parent, props)
		local holder = new("Frame", {
			Position = props.Position,
			Size = props.Size,
			BackgroundColor3 = rgb(255, 255, 255),
			BorderSizePixel = 0,
		}, parent)
		corner(holder, 14)
		stroke(holder, C.Ink, 3)
		local box = new("TextBox", {
			Size = UDim2.new(1, -20, 1, 0),
			Position = UDim2.fromOffset(10, 0),
			BackgroundTransparency = 1,
			Font = UIKit.Font.Title,
			TextSize = 22,
			TextColor3 = rgb(50, 30, 90),
			PlaceholderText = props.Placeholder or "",
			PlaceholderColor3 = rgb(160, 150, 190),
			Text = "",
			ClearTextOnFocus = false,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, holder)
		return box
	end

	---------------------------------------------------------------- DAILY

	section("Daily", function()
		local win = makeWindow({ title = "Daily", icon = "calendar", w = 720, h = 360, theme = "blue", ribbon = "yellow" })
		text(win.content, {
			Size = UDim2.new(1, 0, 0, 24),
			TextSize = 18,
			Text = "Come back every day! Miss a day and the streak starts again.",
		})
		local row = new("Frame", { Position = UDim2.fromOffset(0, 32), Size = UDim2.new(1, 0, 0, 170), BackgroundTransparency = 1 }, win.content)
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, row)

		local cells = {}
		for i, reward in ipairs(MetaConfig.Daily) do
			local big = i == #MetaConfig.Daily
			local cell = new("Frame", {
				Size = UDim2.fromOffset(big and 108 or 84, 164),
				BackgroundColor3 = big and rgb(120, 50, 200) or rgb(35, 25, 95),
				BackgroundTransparency = 0.1,
				BorderSizePixel = 0,
				LayoutOrder = i,
			}, row)
			corner(cell, 16)
			local st = stroke(cell, rgb(150, 140, 240), 3)
			text(cell, { Text = "DAY " .. i, Position = UDim2.fromOffset(0, 6), Size = UDim2.new(1, 0, 0, 24), Font = UIKit.Font.Title, TextSize = 19 })
			local cur, amount = rewardMain(reward)
			local img = icon(cell, UIKit.CurrencyIcon[cur], {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 34),
				Size = UDim2.fromOffset(big and 72 or 60, big and 72 or 60),
				ZIndex = 2,
			})
			text(cell, {
				Text = rewardText(reward),
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -10),
				Size = UDim2.new(1, -4, 0, 40),
				TextWrapped = true,
				Font = UIKit.Font.Title,
				TextSize = 18,
				TextColor3 = rgb(255, 230, 120),
				ZIndex = 2,
			})
			local done = icon(cell, "check", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.45),
				Size = UDim2.fromOffset(56, 56),
				ZIndex = 4,
				Visible = false,
			})
			cells[i] = { frame = cell, stroke = st, img = img, done = done, wob = nil }
		end

		local claim = UIKit.button(win.content, {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -4),
			Size = UDim2.fromOffset(300, 64),
			Color = "green",
			Icon = "gift",
			IconSize = 40,
			Text = "CLAIM!",
			Font = UIKit.Font.Title,
			TextSize = 26,
		})
		local claimPulse = UIKit.pulse(new("UIScale", {}, claim.Face), 1.06, 0.55)

		local function render(st)
			local d = st.daily
			local doneCount = d.claimedToday and d.streak or (d.nextIndex - 1)
			for i, c in ipairs(cells) do
				local isDone = i <= doneCount
				local isNext = (not d.claimedToday) and i == d.nextIndex
				c.done.Visible = isDone and UIKit.IconsReady
				c.img.ImageTransparency = isDone and 0.6 or 0
				c.stroke.Color = isNext and rgb(255, 225, 80) or rgb(150, 140, 240)
				c.stroke.Thickness = isNext and 5 or 3
				if isNext and not c.wob then
					c.wob = UIKit.wobble(c.img, 8, 0.6)
					UIKit.sparkles(c.frame, rgb(255, 240, 160), 4, 6)
				elseif not isNext and c.wob then
					c.wob:Cancel()
					c.wob = nil
					c.img.Rotation = 0
					UIKit.stopSparkles(c.frame)
				end
			end
			if d.claimedToday then
				claim.setColor("grey")
				claim.setIcon("stopwatch")
				claimPulse:Cancel()
			else
				claim.setColor("green")
				claim.setIcon("gift")
				claim.setText("CLAIM DAY " .. d.nextIndex .. "!")
				claimPulse:Play()
			end
		end
		onMeta(render)

		-- таймер до следующей награды и красный значок на кнопке
		local tile = tiles.Daily
		local dot = new("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -4, 0, 4),
			Size = UDim2.fromOffset(28, 28),
			BackgroundColor3 = rgb(255, 50, 80),
			Font = UIKit.Font.Title,
			Text = "!",
			TextSize = 20,
			TextColor3 = WHITE,
			BorderSizePixel = 0,
			Visible = false,
			ZIndex = 6,
		}, tile.face)
		corner(dot, 14)
		stroke(dot, WHITE, 3)
		UIKit.pulse(new("UIScale", {}, dot), 1.2, 0.45)
		local acc = 0
		RunService.Heartbeat:Connect(function(dt)
			acc += dt
			if acc < 0.5 or not metaState then return end
			acc = 0
			local d = metaState.daily
			dot.Visible = not d.claimedToday
			if d.claimedToday then
				claim.setText("NEXT IN " .. timeLeft(metaState.nextDayAt))
			end
		end)

		claim.Button.MouseButton1Click:Connect(function()
			if metaState and metaState.daily.claimedToday then
				UIKit.shake(claim.Button)
				return
			end
			local res = call("daily")
			if res and res.ok then
				UIKit.pop(claim.Button, 1.2, 0.3)
			end
		end)
		handlers.Daily = win.toggle
	end)


	---------------------------------------------------------------- QUESTS

	section("Quests", function()
		local win = makeWindow({ title = "Quests", icon = "scroll", w = 680, h = 500, theme = "orange", ribbon = "yellow" })

		-- вкладки DAILY / WEEKLY
		local tabsBar = new("Frame", { Size = UDim2.new(1, 0, 0, 52), BackgroundTransparency = 1 }, win.content)
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 14),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, tabsBar)

		local function tabDot(parent)
			local d = new("TextLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(1, -6, 0, 6),
				Size = UDim2.fromOffset(28, 28),
				BackgroundColor3 = rgb(255, 50, 80),
				Font = UIKit.Font.Title,
				Text = "!",
				TextSize = 18,
				TextColor3 = WHITE,
				BorderSizePixel = 0,
				Visible = false,
				ZIndex = 6,
			}, parent)
			corner(d, 14)
			stroke(d, WHITE, 3)
			return d
		end

		local tabs = {}
		for i, t in ipairs({ { id = "daily", text = "DAILY", icon = "calendar" }, { id = "weekly", text = "WEEKLY", icon = "crown" } }) do
			local b = UIKit.button(tabsBar, {
				Size = UDim2.fromOffset(210, 50),
				Color = "grey",
				Icon = t.icon,
				IconSize = 32,
				Text = t.text,
				Font = UIKit.Font.Title,
				TextSize = 22,
				LayoutOrder = i,
			})
			tabs[t.id] = { btn = b, dot = tabDot(b.Face) }
		end

		local listWell = UIKit.well(win.content, { Position = UDim2.fromOffset(0, 60), Size = UDim2.new(1, 0, 1, -94) })
		local list = new("ScrollingFrame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 8,
			ScrollBarImageColor3 = rgb(255, 220, 90),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = UDim2.new(),
		}, listWell)
		new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }, list)
		new("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10) }, list)

		local footer = text(win.content, {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, 28),
			TextSize = 19,
			Text = "",
		})

		local rows = {}
		local function makeRow(i)
			local row = new("Frame", {
				Size = UDim2.new(1, -24, 0, 90),
				BackgroundColor3 = rgb(90, 40, 20),
				BackgroundTransparency = 0.35,
				BorderSizePixel = 0,
				LayoutOrder = i,
			}, list)
			corner(row, 18)
			local st = stroke(row, rgb(255, 210, 140), 3)
			local img = icon(row, "skull", { Position = UDim2.fromOffset(10, 12), Size = UDim2.fromOffset(66, 66) })
			local title = text(row, {
				Position = UDim2.fromOffset(88, 8),
				Size = UDim2.new(1, -290, 0, 30),
				TextSize = 21,
				TextScaled = false,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
			})
			local bar = UIKit.bar(row, { Position = UDim2.fromOffset(88, 48), Size = UDim2.new(1, -290, 0, 26) },
			rgb(255, 240, 110), rgb(255, 160, 20))
			local rewardRow = new("Frame", {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -144, 0, 22),
				Size = UDim2.fromOffset(60, 44),
				BackgroundTransparency = 1,
			}, row)
			local rIcon = icon(rewardRow, "coin", { Size = UDim2.fromOffset(40, 40), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -8) })
			local rText = text(rewardRow, { Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 0, 20), Font = UIKit.Font.Title, TextSize = 16, TextColor3 = rgb(255, 230, 120) })
			local btn = UIKit.button(row, {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -12, 0.5, 0),
				Size = UDim2.fromOffset(120, 54),
				Color = "grey",
				Text = "...",
				Font = UIKit.Font.Title,
				TextSize = 20,
			})
			local r = { frame = row, stroke = st, img = img, title = title, bar = bar, rIcon = rIcon, rText = rText, btn = btn, id = nil }
			btn.Button.MouseButton1Click:Connect(function()
				if not r.id or not r.ready then
					UIKit.shake(btn.Button)
					return
				end
				call("quest", r.id)
			end)
			rows[i] = r
			return r
		end

		local current = "daily"

		local function readyCount(qs)
			local n = 0
			for _, q in ipairs(qs or {}) do
				if not q.claimed and q.progress >= q.goal then n += 1 end
			end
			return n
		end

		-- плитка Quests в меню: красный значок, если есть что забрать
		local tileDot = tabDot(tiles.Quests.face)
		UIKit.pulse(new("UIScale", {}, tileDot), 1.2, 0.45)

		local function render(st)
			local qs = (current == "weekly" and st.weekly or st.quests) or {}
			for id, t in pairs(tabs) do
				t.btn.setColor(id == current and (id == "weekly" and "purple" or "yellow") or "grey")
				t.dot.Visible = readyCount(id == "weekly" and st.weekly or st.quests) > 0
			end
			tileDot.Visible = readyCount(st.quests) + readyCount(st.weekly) > 0

			for i = 1, math.max(#qs, #rows) do
				local q = qs[i]
				local r = rows[i] or (q and makeRow(i))
				if r then
					r.frame.Visible = q ~= nil
					local def = q and MetaConfig.findQuest(q.id)
					if def then
						r.id = q.id
						UIKit.setIcon(r.img, def.Icon)
						r.title.Text = def.Text
						r.bar.set(q.progress / q.goal)
						r.bar.Label.Text = UIKit.short(q.progress) .. " / " .. UIKit.short(q.goal)
						local cur, amount = rewardMain(def.Reward)
						UIKit.setIcon(r.rIcon, UIKit.CurrencyIcon[cur])
						r.rText.Text = "+" .. UIKit.short(amount)
						local wasReady = r.ready
						r.ready = not q.claimed and q.progress >= q.goal
						if q.claimed then
							r.btn.setColor("grey")
							r.btn.setIcon("check")
							r.btn.setText("DONE")
							r.stroke.Color = rgb(140, 255, 150)
							r.frame.LayoutOrder = 100 + i -- сделанные — вниз списка
						elseif r.ready then
							r.btn.setColor("green")
							r.btn.setIcon(nil)
							r.btn.setText("CLAIM!")
							r.stroke.Color = rgb(255, 230, 80)
							r.frame.LayoutOrder = i - 100 -- готовые — наверх
							if not wasReady then UIKit.pop(r.btn.Button, 1.2, 0.3) end
						else
							r.btn.setColor("grey")
							r.btn.setIcon(nil)
							r.btn.setText("GO!")
							r.stroke.Color = rgb(255, 210, 140)
							r.frame.LayoutOrder = i
						end
					else
						r.frame.Visible = false
						r.id = nil
					end
				end
			end
		end
		onMeta(render)

		local function switch(id)
			if current == id then return end
			current = id
			for _, r in ipairs(rows) do r.ready = nil end
			list.CanvasPosition = Vector2.zero
			if metaState then render(metaState) end
		end
		tabs.daily.btn.Button.MouseButton1Click:Connect(function() switch("daily") end)
		tabs.weekly.btn.Button.MouseButton1Click:Connect(function() switch("weekly") end)

		local function longLeft(at)
			local left = math.max(0, math.floor(at - workspace:GetServerTimeNow()))
			if left >= 86400 then
				return string.format("%dd %dh", math.floor(left / 86400), math.floor(left % 86400 / 3600))
			end
			return timeLeft(at)
		end

		local acc = 0
		RunService.Heartbeat:Connect(function(dt)
			acc += dt
			if acc < 0.5 or not metaState then return end
			acc = 0
			if current == "weekly" then
				footer.Text = "New weekly quests in " .. longLeft(metaState.nextWeekAt or 0)
			else
				footer.Text = "New quests in " .. timeLeft(metaState.nextDayAt)
			end
		end)
		handlers.Quests = win.toggle
	end)

	---------------------------------------------------------------- CLANS

	section("Clans", function()
		local win = makeWindow({ title = "Clans", icon = "shield", w = 560, h = 440, theme = "green", ribbon = "yellow" })

		-- без клана: создать или вступить
		local joinView = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, win.content)
		local bigIcon = icon(joinView, "shield", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.fromOffset(100, 100) })
		UIKit.wobble(bigIcon, 5, 1.3)
		text(joinView, {
			Position = UDim2.fromOffset(0, 104),
			Size = UDim2.new(1, 0, 0, 50),
			TextWrapped = true,
			TextSize = 19,
			Text = "Play together with friends! Type a clan name to join it, or make your own.",
		})
		local nameBox = inputBox(joinView, { Position = UDim2.fromOffset(40, 160), Size = UDim2.new(1, -80, 0, 54), Placeholder = "Clan name..." })
		text(joinView, {
			Position = UDim2.fromOffset(0, 216),
			Size = UDim2.new(1, 0, 0, 20),
			TextSize = 15,
			TextColor3 = rgb(225, 255, 225),
			Text = string.format("%d-%d letters or numbers", MetaConfig.Clan.MinName, MetaConfig.Clan.MaxName),
		})
		local joinBtn = UIKit.button(joinView, {
			Position = UDim2.new(0, 20, 0, 246),
			Size = UDim2.new(0.5, -30, 0, 62),
			Color = "blue",
			Icon = "hand",
			IconSize = 36,
			Text = "JOIN",
			Font = UIKit.Font.Title,
			TextSize = 24,
		})
		local createBtn = UIKit.button(joinView, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -20, 0, 246),
			Size = UDim2.new(0.5, -30, 0, 62),
			Color = "yellow",
			Icon = "coin",
			IconSize = 34,
			Text = "CREATE " .. UIKit.short(MetaConfig.Clan.CreateCost.Cash or 0),
			Font = UIKit.Font.Title,
			TextSize = 21,
		})

		-- в клане: участники
		local clanView = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, win.content)
		local clanTitle = UIKit.title(clanView, { Size = UDim2.new(1, 0, 0, 42), TextSize = 38, Text = "" })
		local clanSub = text(clanView, { Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 0, 24), TextSize = 18, Text = "" })
		local listWell = UIKit.well(clanView, { Position = UDim2.fromOffset(0, 76), Size = UDim2.new(1, 0, 1, -150) })
		local members = new("ScrollingFrame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 8,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = UDim2.new(),
		}, listWell)
		new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, members)
		new("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, members)
		local leaveBtn = UIKit.button(clanView, {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -4),
			Size = UDim2.fromOffset(220, 58),
			Color = "red",
			Icon = "close",
			IconSize = 32,
			Text = "LEAVE",
			Font = UIKit.Font.Title,
			TextSize = 24,
		})

		local function showClan(info)
			joinView.Visible = info == nil
			clanView.Visible = info ~= nil
			if not info then return end
			clanTitle.Text = string.upper(info.name)
			clanSub.Text = string.format("Leader: %s   Members: %d / %d", info.owner or "-", #info.members, info.max or 20)
			for _, c in ipairs(members:GetChildren()) do
				if c:IsA("GuiObject") then c:Destroy() end
			end
			for i, name in ipairs(info.members) do
				local row = new("Frame", { Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = rgb(30, 80, 50), BackgroundTransparency = 0.2, BorderSizePixel = 0, LayoutOrder = i }, members)
				corner(row, 12)
				icon(row, name == info.owner and "crown" or "shield", { Position = UDim2.fromOffset(6, 4), Size = UDim2.fromOffset(32, 32) })
				text(row, { Text = name, Position = UDim2.fromOffset(46, 0), Size = UDim2.new(1, -52, 1, 0), TextSize = 20, TextXAlignment = Enum.TextXAlignment.Left })
			end
		end

		local function act(action, arg)
			if action ~= "clanLeave" and (typeof(arg) ~= "string" or not string.find(arg, "%S")) then
				toast("Type a clan name first!", BAD, "warning")
				UIKit.pop(nameBox.Parent, 1.06, 0.2)
				return
			end
			local res = call(action, arg)
			if res and res.ok then
				showClan(res.clan)
			end
		end
		joinBtn.Button.MouseButton1Click:Connect(function() act("clanJoin", nameBox.Text) end)
		createBtn.Button.MouseButton1Click:Connect(function() act("clanCreate", nameBox.Text) end)
		leaveBtn.Button.MouseButton1Click:Connect(function() act("clanLeave") end)

		win.onOpen = function()
			task.spawn(function()
				local ok, res = pcall(function() return metaRemote:InvokeServer("clanInfo") end)
				if ok and typeof(res) == "table" then
					showClan(res.clan)
				end
			end)
		end
		handlers.Clans = win.toggle
	end)

	---------------------------------------------------------------- CODES

	section("Codes", function()
		local win = makeWindow({ title = "Codes", icon = "ticket", w = 480, h = 300, theme = "blue", ribbon = "pink" })
		text(win.content, {
			Size = UDim2.new(1, 0, 0, 50),
			TextWrapped = true,
			TextSize = 19,
			Text = "Got a secret code? Type it here and get free rewards!",
		})
		local box = inputBox(win.content, { Position = UDim2.fromOffset(20, 60), Size = UDim2.new(1, -40, 0, 56), Placeholder = "Enter code..." })
		local redeem = UIKit.button(win.content, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 134),
			Size = UDim2.fromOffset(240, 62),
			Color = "green",
			Icon = "ticket",
			IconSize = 36,
			Text = "REDEEM",
			Font = UIKit.Font.Title,
			TextSize = 26,
		})
		redeem.Button.MouseButton1Click:Connect(function()
			if box.Text == "" then
				UIKit.shake(redeem.Button)
				return
			end
			local res = call("redeem", box.Text)
			if res and res.ok then
				box.Text = ""
				UIKit.pop(redeem.Button, 1.2, 0.3)
			else
				UIKit.shake(redeem.Button)
			end
		end)
		handlers.Codes = win.toggle
	end)

	---------------------------------------------------------------- SETTINGS

	section("Settings", function()
		local win = makeWindow({ title = "Settings", icon = "gear", w = 520, h = 400, theme = "purple", ribbon = "yellow" })
		local list = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, win.content)
		new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, list)

		local values = {}
		for _, s in ipairs(MetaConfig.Settings) do
			values[s.Id] = s.Default
		end

		-- звук: глушим все звуки в игре, сохраняя их громкость
		local SoundService = game:GetService("SoundService")
		local savedVolume = setmetatable({}, { __mode = "k" })
		local function setSound(on)
			local function apply(snd)
				if not snd:IsA("Sound") then return end
				if on then
					if savedVolume[snd] then snd.Volume = savedVolume[snd] end
				else
					if savedVolume[snd] == nil then savedVolume[snd] = snd.Volume end
					snd.Volume = 0
				end
			end
			for _, root in ipairs({ workspace, SoundService, playerGui }) do
				for _, d in ipairs(root:GetDescendants()) do apply(d) end
			end
		end
		local soundOn = true
		for _, root in ipairs({ workspace, SoundService }) do
			root.DescendantAdded:Connect(function(d)
				if not soundOn and d:IsA("Sound") then
					savedVolume[d] = d.Volume
					d.Volume = 0
				end
			end)
		end

		-- настройки читают UIKit / VFXKit / TowerVFX через атрибуты игрока
		local function applyAll()
			for id, v in pairs(values) do
				player:SetAttribute("Set_" .. id, v)
			end
			if values.Music ~= soundOn then
				soundOn = values.Music ~= false
				setSound(soundOn)
			end
		end

		local toggles = {}
		for i, s in ipairs(MetaConfig.Settings) do
			local row = new("Frame", {
				Size = UDim2.new(1, 0, 0, 72),
				BackgroundColor3 = rgb(50, 25, 110),
				BackgroundTransparency = 0.25,
				BorderSizePixel = 0,
				LayoutOrder = i,
			}, list)
			corner(row, 16)
			icon(row, s.Icon, { Position = UDim2.fromOffset(10, 8), Size = UDim2.fromOffset(56, 56) })
			text(row, { Text = s.Text, Position = UDim2.fromOffset(78, 8), Size = UDim2.new(1, -230, 0, 30), TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left })
			text(row, { Text = s.Hint, Position = UDim2.fromOffset(78, 38), Size = UDim2.new(1, -230, 0, 22), TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = rgb(215, 205, 255) })
			local btn = UIKit.button(row, {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -12, 0.5, 0),
				Size = UDim2.fromOffset(120, 54),
				Color = "green",
				Text = "ON",
				Font = UIKit.Font.Title,
				TextSize = 24,
				Shine = false,
			})
			toggles[s.Id] = btn
			btn.Button.MouseButton1Click:Connect(function()
				values[s.Id] = not values[s.Id]
				btn.setColor(values[s.Id] and "green" or "grey")
				btn.setText(values[s.Id] and "ON" or "OFF")
				applyAll()
				task.spawn(call, "settings", values)
			end)
		end

		local loaded = false
		onMeta(function(st)
			if loaded or typeof(st.settings) ~= "table" then return end
			loaded = true
			for id, v in pairs(st.settings) do
				if values[id] ~= nil and typeof(v) == "boolean" then
					values[id] = v
				end
			end
			for id, btn in pairs(toggles) do
				btn.setColor(values[id] and "green" or "grey")
				btn.setText(values[id] and "ON" or "OFF")
			end
			applyAll()
		end)
		applyAll()
		handlers.Settings = win.toggle
	end)

	-- первое состояние (если сервер ещё не прислал сам)
	task.spawn(function()
		local waited = 0
		while not metaState and waited < 30 do
			local ok, res = pcall(function() return metaRemote:InvokeServer("state") end)
			if ok and typeof(res) == "table" and res.state then
				setMetaState(res.state)
				break
			end
			waited += task.wait(2)
		end
	end)
end)

---------------------------------------------------------------- хаб: E у предмета в мире открывает раздел меню
-- HubClient шлёт сюда id раздела (Inventory, Daily, Quests, Clans, Codes, Shop) через шину MenuBus

task.spawn(function()
	local holder = player:WaitForChild("PlayerScripts", 30)
	if not holder then return end
	local bus = holder:FindFirstChild("MenuBus")
	if not bus then
		bus = Instance.new("BindableEvent")
		bus.Name = "MenuBus"
		bus.Parent = holder
	end
	bus.Event:Connect(function(id)
		if typeof(id) ~= "string" or not gui.Enabled then return end
		if openWin and openWin.busId == id then return end -- это окно уже открыто
		local h = handlers[id]
		if h then
			h()
			if openWin then openWin.busId = id end
		end
	end)
end)

---------------------------------------------------------------- тег клана в чате: «[MOGG] Ivan: привет»
pcall(function()
	local TextChatService = game:GetService("TextChatService")
	if TextChatService.ChatVersion ~= Enum.ChatVersion.TextChatService then return end
	if TextChatService:GetAttribute("ClanTagsHooked") then return end
	TextChatService:SetAttribute("ClanTagsHooked", true)
	TextChatService.OnIncomingMessage = function(message)
		local props = Instance.new("TextChatMessageProperties")
		local src = message.TextSource
		local who = src and Players:GetPlayerByUserId(src.UserId)
		local clan = who and who:GetAttribute("Clan")
		if typeof(clan) == "string" and clan ~= "" then
			clan = clan:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
			props.PrefixText = '<font color="#FFD25A">[' .. clan .. ']</font> ' .. (message.PrefixText or "")
		end
		return props
	end
end)
