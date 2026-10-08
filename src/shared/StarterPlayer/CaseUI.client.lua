-- StarterPlayer.StarterPlayerScripts. (LocalScript)
-- Кейсы с юнитами:
--   • окно SHOP (кнопка Shop в боковом меню):
--       сундуки (лучи, шансы, гарантия, кэшбэк), ниже гемы за Robux и Cash за гемы (таблицы в MetaConfig)
--   • открытие на весь экран — РУЛЕТКА как в CS:
--       1. сундук падает и раскрывается, из него вылетает лента юнитов
--       2. лента летит и тормозит, щелчок на каждом юните, в конце всё темнеет
--       3. остановка под стрелкой, доводка до центра
--       4. праздник по редкости: вспышки, фейерверки, дождь монет, буквы по одной
--          Legendary — с неба падает комета, удар, столб света, золотая аура
--          Mythic — полная темнота, по экрану ползут трещины, стекло разлетается, радужная аура с молниями
--       5. юнит в 3D крутится в лучах; карточка NEW! или DUPLICATE + кэшбэк
--   SKIP — только с геймпассом Instant Open (MetaConfig.SkipPass), без него кнопка предлагает купить.
--   Всё решает сервер (CaseService), здесь только показ.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local MarketplaceService = game:GetService("MarketplaceService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))
local TowerData = require(ReplicatedStorage:WaitForChild("TowerData"))
local RarityData = require(ReplicatedStorage:WaitForChild("RarityData"))
local CaseConfig = require(ReplicatedStorage:WaitForChild("CaseConfig"))
local PlacementRules = require(ReplicatedStorage:WaitForChild("PlacementRules"))
local openRemote = ReplicatedStorage:WaitForChild("OpenCase")
-- 3D-модели юнитов (папка ReplicatedStorage.Towers). Нет папки — рулетка работает без 3D-моделей.
local NO_TEMPLATES = Instance.new("Folder")
local function templatesFolder()
	return ReplicatedStorage:FindFirstChild("Towers") or NO_TEMPLATES
end
task.delay(15, function()
	if not ReplicatedStorage:FindFirstChild("Towers") then
		warn("[Cases] нет папки ReplicatedStorage.Towers — скопируй её из игры, чтобы в кейсах были 3D-юниты")
	end
end)

local new, corner, stroke, tween = UIKit.new, UIKit.corner, UIKit.stroke, UIKit.tween
local text, icon, rgb = UIKit.text, UIKit.icon, UIKit.rgb
local WHITE, BLACK = Color3.new(1, 1, 1), Color3.new(0, 0, 0)
local INK = UIKit.C.Ink
local RANK = UIKit.Rank
local CUR_ICON = UIKit.CurrencyIcon
local CUR_NAME = { Cash = "Cash", Gems = "Gems", Cases = "Chests" }

---------------------------------------------------------------- помощники

local function rarityColor(rarity)
	return (RarityData[rarity] or RarityData.Common).Color
end

local function pctText(p)
	if p >= 10 then
		return tostring(math.floor(p + 0.5))
	end
	return (string.format("%.1f", p):gsub("%.0$", ""))
end

local function wallet(name)
	local data = player:FindFirstChild("Data")
	local v = data and data:FindFirstChild(name)
	return v and v.Value or 0
end

-- чем заплатим прямо сейчас (как на сервере: сначала сундучок-жетон, потом валюта)
local function payment(def)
	if def.TokenCurrency and wallet(def.TokenCurrency) >= (def.TokenPrice or 1) then
		return def.TokenCurrency, def.TokenPrice or 1
	end
	return def.Currency, def.Price
end

local function canAfford(def)
	local currency, cost = payment(def)
	return wallet(currency) >= cost
end

-- иконка и текст цены: «OPEN 500» или «FREE x3» за сундучки
local function priceInfo(def)
	local currency, cost = payment(def)
	if currency == def.TokenCurrency then
		return CUR_ICON[currency], "FREE  x" .. wallet(currency)
	end
	return CUR_ICON[currency], UIKit.commas(cost)
end

---------------------------------------------------------------- состояние

local scene = nil  -- текущее открытие
local busy = false -- ждём ответ сервера или идёт анимация
local requestOpen  -- объявлена ниже

-- геймпасс Instant Open: атрибут SkipPass ставит сервер (MetaService); настройки — MetaConfig.SkipPass
local skipPassCfg = { Id = 0, Robux = 40 }
local instantOpen = false -- владелец пасса может включить «сразу результат» в магазине
local function hasPass() return player:GetAttribute("SkipPass") == true end
local function effectsOn() return player:GetAttribute("Set_Effects") ~= false end
local function shakeOn() return player:GetAttribute("Set_Shake") ~= false end

---------------------------------------------------------------- окно SHOP

local shopGui = new("ScreenGui", {
	Name = "CaseShopGui",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 12,
}, playerGui)

local win = UIKit.window(shopGui, {
	Title = "Shop",
	Icon = "shop",
	Width = 820,
	Height = 520,
	Theme = { rgb(255, 160, 220), rgb(200, 55, 170) },
	Ribbon = "yellow",
})
local root = win.Root

local function toast(msg, iconName)
	UIKit.toast(shopGui, msg, { Color = rgb(255, 170, 170), Icon = iconName, Y = 70 })
end

-- всё окно листается вниз: СУНДУКИ → ГЕМЫ → CASH
local scroll = new("ScrollingFrame", {
	Name = "Scroll",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 10,
	ScrollBarImageColor3 = rgb(255, 220, 90),
	ScrollingDirection = Enum.ScrollingDirection.Y,
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	CanvasSize = UDim2.new(),
}, win.Content)
new("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }, scroll)
new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 16), PaddingRight = UDim.new(0, 12) }, scroll)

local instantBtn
do
	local h = new("Frame", { Size = UDim2.new(1, -20, 0, 46), BackgroundTransparency = 1, LayoutOrder = 1 }, scroll)
	local group = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, h)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, group)
	icon(group, "chest", { Size = UDim2.fromOffset(42, 42), LayoutOrder = 1 })
	UIKit.title(group, { Text = "CHESTS", AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), TextSize = 34, LayoutOrder = 2 })

	-- переключатель «сразу результат» (виден только с геймпассом Instant Open)
	instantBtn = UIKit.button(h, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(190, 42),
		Color = "grey",
		Icon = "skip",
		IconSize = 26,
		Text = "INSTANT: OFF",
		Font = UIKit.Font.Title,
		TextSize = 17,
		Visible = false,
	})
	local function refreshInstant()
		instantBtn.Button.Visible = hasPass()
		instantBtn.setText(instantOpen and "INSTANT: ON" or "INSTANT: OFF")
		instantBtn.setColor(instantOpen and "green" or "grey")
	end
	instantBtn.Button.MouseButton1Click:Connect(function()
		instantOpen = not instantOpen
		refreshInstant()
		UIKit.pop(instantBtn.Face, 1.15, 0.25)
	end)
	player:GetAttributeChangedSignal("SkipPass"):Connect(refreshInstant)
	refreshInstant()
end

-- сундуки — те же карточки, что были в Summon
local list = new("Frame", { Size = UDim2.new(1, -8, 0, 410), BackgroundTransparency = 1, LayoutOrder = 2 }, scroll)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	Padding = UDim.new(0, 20),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, list)

local cards = {}
local floaters = {} -- сундуки, которые плавно парят

for i, caseId in ipairs(CaseConfig.Order) do
	local def = CaseConfig.Cases[caseId]
	if def then
		local theme = def.Theme or { rgb(255, 215, 110), rgb(235, 110, 30) }
		local accent = def.Accent or WHITE
		local card = UIKit.panel(list, {
			Name = caseId,
			Size = UDim2.new(0.5, -10, 1, 0),
			LayoutOrder = i,
		}, theme[1], theme[2], { Radius = 22, GlossHeight = 40 })
		UIKit.sparkles(card, WHITE, 3, 8)

		-- сундук в лучах
		local stage = new("Frame", { Size = UDim2.new(1, 0, 0, 160), BackgroundTransparency = 1, ClipsDescendants = false }, card)
		UIKit.rays(stage, accent, 330, 22, { ImageTransparency = 0.35 })
		UIKit.glow(stage, accent, 230, { ImageTransparency = 0.2 })
		local chest = UIKit.art(stage, def.Art or "chestHero", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.52),
			Size = UDim2.fromOffset(170, 170),
			ZIndex = 3,
		})
		UIKit.wobble(chest, 4, 1.4)
		table.insert(floaters, { img = chest, seed = i * 1.7 })

		UIKit.title(card, {
			Text = string.upper(def.Name),
			Position = UDim2.fromOffset(0, 156),
			Size = UDim2.new(1, 0, 0, 36),
			TextSize = 32,
			ZIndex = 3,
		})

		-- шансы цветными полосками
		local odds = UIKit.well(card, {
			Position = UDim2.fromOffset(14, 196),
			Size = UDim2.new(1, -28, 0, 84),
			BackgroundTransparency = 0.5,
		})
		new("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }, odds)
		new("UIPadding", { PaddingTop = UDim.new(0, 3) }, odds)
		for k, e in ipairs(def.Rates) do
			local c = rarityColor(e.Rarity)
			local row = new("Frame", {
				Size = UDim2.new(1, -8, 0, 24),
				BackgroundColor3 = WHITE,
				BorderSizePixel = 0,
				LayoutOrder = k,
			}, odds)
			corner(row, 12)
			new("UIGradient", { Color = ColorSequence.new(c:Lerp(WHITE, 0.15), c:Lerp(BLACK, 0.3)) }, row)
			stroke(row, INK, 2)
			if (RANK[e.Rarity] or 1) >= 4 then
				icon(row, "star", { Position = UDim2.fromOffset(4, 1), Size = UDim2.fromOffset(22, 22), ZIndex = 2 })
			end
			text(row, {
				Text = string.upper(e.Rarity),
				Position = UDim2.fromOffset(30, 0),
				Size = UDim2.new(0.6, 0, 1, 0),
				Font = UIKit.Font.Title,
				TextSize = 16,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 2,
			})
			text(row, {
				Text = pctText(CaseConfig.Chance(def, e.Rarity)) .. "%",
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -10, 0, 0),
				Size = UDim2.new(0.4, 0, 1, 0),
				Font = UIKit.Font.Title,
				TextSize = 17,
				TextXAlignment = Enum.TextXAlignment.Right,
				ZIndex = 2,
			})
		end

		-- гарантия и кэшбэк
		local pityRow = new("Frame", { Position = UDim2.fromOffset(0, 284), Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1 }, card)
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, pityRow)
		icon(pityRow, "sparkle", { Size = UDim2.fromOffset(22, 22), LayoutOrder = 1 })
		local pity = text(pityRow, { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), RichText = true, TextSize = 15, LayoutOrder = 2, Text = "" })

		local maxBack = 0
		for _, share in pairs(def.Cashback or {}) do
			maxBack = math.max(maxBack, share)
		end
		local backRow = new("Frame", { Position = UDim2.fromOffset(0, 306), Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1 }, card)
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, backRow)
		icon(backRow, CUR_ICON[def.Currency], { Size = UDim2.fromOffset(22, 22), LayoutOrder = 1 })
		text(backRow, {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.new(0, 0, 1, 0),
			TextSize = 15,
			TextColor3 = rgb(255, 250, 215),
			LayoutOrder = 2,
			Text = string.format("Duplicate? Get up to %d%% back!", math.floor(maxBack * 100 + 0.5)),
		})

		local btn = UIKit.button(card, {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -12),
			Size = UDim2.new(1, -36, 0, 64),
			Color = def.Button or "green",
			Icon = CUR_ICON[def.Currency],
			IconSize = 40,
			Text = "OPEN",
			Font = UIKit.Font.Title,
			TextSize = 28,
			Radius = 20,
			Depth = 6,
		})
		local btnPulse = UIKit.pulse(new("UIScale", {}, btn.Face), 1.04, 0.7)
		btn.Button.MouseButton1Click:Connect(function()
			if not canAfford(def) then
				UIKit.shake(btn.Button)
				toast("Not enough " .. (CUR_NAME[def.Currency] or def.Currency) .. "!", CUR_ICON[def.Currency])
				return
			end
			requestOpen(caseId)
		end)

		cards[caseId] = { button = btn, pulse = btnPulse, pity = pity }
	end
end

local function refreshShop()
	for caseId, c in pairs(cards) do
		local def = CaseConfig.Cases[caseId]
		local iconName, priceText = priceInfo(def)
		c.button.setIcon(iconName)
		c.button.setText("OPEN  " .. priceText)
		if canAfford(def) then
			c.button.setColor(def.Button or "green")
			c.pulse:Play()
		else
			c.button.setColor("grey")
			c.pulse:Cancel()
		end
		local parts = {}
		for _, e in ipairs(def.Rates) do
			local need = def.Pity and def.Pity[e.Rarity]
			if need then
				local got = player:GetAttribute("Pity_" .. caseId .. "_" .. e.Rarity) or 0
				table.insert(parts, string.format('<font color="#%s">%s</font> in %d',
					rarityColor(e.Rarity):Lerp(WHITE, 0.35):ToHex(), e.Rarity, math.max(1, need - got)))
			end
		end
		c.pity.Text = #parts > 0 and ("For sure: " .. table.concat(parts, ", ")) or ""
	end
end

local shopOpen = false

local function hideLobbyWindows()
	local lw = playerGui:FindFirstChild("LobbyWindows")
	if lw then
		for _, w in ipairs(lw:GetChildren()) do
			if w:IsA("GuiObject") then
				w.Visible = false
			end
		end
	end
end

local function openShop()
	hideLobbyWindows()
	shopOpen = true
	refreshShop()
	scroll.CanvasPosition = Vector2.zero
	win.show()
end

local function closeShop()
	shopOpen = false
	win.hide()
end

win.Close.Button.MouseButton1Click:Connect(closeShop)

-- сундуки в окне плавно парят
RunService.RenderStepped:Connect(function()
	if not root.Visible then return end
	local t = os.clock()
	for _, f in ipairs(floaters) do
		f.img.Position = UDim2.new(0.5, 0, 0.52, math.sin(t * 2 + f.seed) * 6)
	end
end)

---------------------------------------------------------------- гемы за Robux и Cash за гемы (ниже сундуков)

local PILES = { -- кучка кристаллов: { x, y, размер } — чем больше набор, тем больше кучка
	{ { 0, 0, 96 } },
	{ { -26, 6, 78 }, { 26, -2, 82 } },
	{ { 0, -14, 76 }, { -36, 12, 70 }, { 36, 12, 70 } },
	{ { -20, -18, 66 }, { 22, -16, 68 }, { -40, 16, 64 }, { 40, 16, 64 } },
	{ { -24, -18, 64 }, { 24, -18, 64 }, { -48, 16, 60 }, { 48, 16, 60 }, { 0, 20, 66 } },
	{ { 0, -40, 62 }, { -26, -12, 62 }, { 26, -12, 62 }, { -52, 18, 60 }, { 52, 18, 60 }, { 0, 22, 66 } },
}

local bobbers = {} -- кучки гемов и монеты плавно покачиваются

local function sectionHeader(iconName, label, order)
	local h = new("Frame", { Size = UDim2.new(1, -20, 0, 46), BackgroundTransparency = 1, LayoutOrder = order }, scroll)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, h)
	icon(h, iconName, { Size = UDim2.fromOffset(42, 42), LayoutOrder = 1 })
	UIKit.title(h, { Text = label, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), TextSize = 34, LayoutOrder = 2 })
	return h
end

local function tagRibbon(card, label)
	local tag = new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 10, 0, -10),
		Size = UDim2.fromOffset(math.max(74, #label * 11 + 20), 30),
		BackgroundColor3 = rgb(255, 60, 90),
		BorderSizePixel = 0,
		Rotation = 8,
		ZIndex = 8,
	}, card)
	corner(tag, 10)
	stroke(tag, WHITE, 3)
	text(tag, { Text = label, Size = UDim2.fromScale(1, 1), Font = UIKit.Font.Title, TextSize = 17, ZIndex = 9 })
end

local function shopGrid(order, rows)
	local g = new("Frame", { Size = UDim2.new(1, -8, 0, rows * 244 - 14), BackgroundTransparency = 1, LayoutOrder = order }, scroll)
	new("UIGridLayout", {
		CellSize = UDim2.fromOffset(236, 230),
		CellPadding = UDim2.fromOffset(16, 14),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, g)
	return g
end

task.spawn(function()
	local cfgObj = ReplicatedStorage:WaitForChild("MetaConfig", 30)
	local okCfg, MetaConfig = false, nil
	if cfgObj then
		okCfg, MetaConfig = pcall(require, cfgObj)
	end
	if not okCfg or typeof(MetaConfig) ~= "table" or not MetaConfig.GemPacks then
		warn("[Shop] нет MetaConfig (или он старый) — в магазине только сундуки")
		return
	end
	local robuxImage = MetaConfig.RobuxIcon or ""

	-- настройки геймпасса Instant Open (их же читает кнопка SKIP при открытии)
	if typeof(MetaConfig.SkipPass) == "table" then
		skipPassCfg = {
			Id = tonumber(MetaConfig.SkipPass.Id) or 0,
			Robux = MetaConfig.SkipPass.Robux or 40,
			RobuxIcon = robuxImage,
		}
	else
		skipPassCfg.RobuxIcon = robuxImage
	end

	-- ГЕЙМПАСС INSTANT OPEN
	sectionHeader("skip", "PASSES", 3)
	do
		local row = new("Frame", { Size = UDim2.new(1, -8, 0, 150), BackgroundTransparency = 1, LayoutOrder = 4 }, scroll)
		local card = UIKit.panel(row, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.new(0, 3 * 236 + 2 * 16, 1, 0),
			Name = "InstantOpen",
		}, rgb(130, 240, 255), rgb(40, 110, 230), { Radius = 18, OutlineThickness = 4, GlossHeight = 26 })
		UIKit.sparkles(card, WHITE, 3, 6)
		local art = new("Frame", { Position = UDim2.fromOffset(10, 0), Size = UDim2.fromOffset(150, 150), BackgroundTransparency = 1 }, card)
		UIKit.rays(art, rgb(220, 250, 255), 230, 16, { ImageTransparency = 0.45 })
		UIKit.glow(art, rgb(150, 240, 255), 170, { ImageTransparency = 0.2 })
		local img = icon(art, "skip", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(104, 104),
			ZIndex = 3,
		})
		table.insert(bobbers, { obj = img, y = 0.5, seed = 7 })
		UIKit.title(card, {
			Position = UDim2.fromOffset(170, 18),
			Size = UDim2.new(1, -400, 0, 40),
			TextSize = 34,
			Text = "INSTANT OPEN",
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 4,
		})
		text(card, {
			Position = UDim2.fromOffset(170, 62),
			Size = UDim2.new(1, -400, 0, 64),
			TextSize = 18,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Text = "Skip chest animations and see your new unit right away! Works forever.",
			ZIndex = 4,
		})
		local buy = UIKit.button(card, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -18, 0.5, 0),
			Size = UDim2.fromOffset(200, 64),
			Color = "green",
			Text = tostring(skipPassCfg.Robux),
			Font = UIKit.Font.Title,
			TextSize = 28,
			ZIndex = 5,
		})
		local function refreshPassCard()
			if hasPass() then
				buy.setIcon("check")
				buy.Icon.Size = UDim2.fromOffset(36, 36)
				buy.setText("OWNED")
				buy.setColor("grey")
			else
				buy.Icon.Image = robuxImage
				buy.Icon.ImageRectOffset = Vector2.zero
				buy.Icon.ImageRectSize = Vector2.zero
				buy.Icon.Size = UDim2.fromOffset(32, 32)
				buy.Icon.Visible = robuxImage ~= ""
				buy.setText(tostring(skipPassCfg.Robux))
				buy.setColor("green")
			end
		end
		refreshPassCard()
		player:GetAttributeChangedSignal("SkipPass"):Connect(refreshPassCard)
		-- настоящая цена пасса из Roblox (если пасс уже создан)
		if skipPassCfg.Id ~= 0 then
			task.spawn(function()
				local ok, info = pcall(function()
					return MarketplaceService:GetProductInfo(skipPassCfg.Id, Enum.InfoType.GamePass)
				end)
				if ok and info and info.PriceInRobux then
					skipPassCfg.Robux = info.PriceInRobux
					refreshPassCard()
				end
			end)
		end
		buy.Button.MouseButton1Click:Connect(function()
			if hasPass() then
				UIKit.pop(img, 1.4, 0.3)
				return
			end
			if skipPassCfg.Id == 0 then
				UIKit.shake(buy.Button)
				if RunService:IsStudio() then
					toast("Put the SkipPass Id in MetaConfig", "warning")
				else
					toast("Coming soon!", "lock")
				end
				return
			end
			MarketplaceService:PromptGamePassPurchase(player, skipPassCfg.Id)
		end)
	end

	-- ГЕМЫ ЗА ROBUX
	sectionHeader("gem", "GEMS", 5)
	local gemGrid = shopGrid(6, math.ceil(#MetaConfig.GemPacks / 3))
	for i, pack in ipairs(MetaConfig.GemPacks) do
		local size = math.clamp(pack.Size or i, 1, #PILES)
		local big = size >= 4
		local card = UIKit.panel(gemGrid, { Name = pack.Id, LayoutOrder = i },
		big and rgb(220, 160, 255) or rgb(150, 215, 255),
		big and rgb(115, 40, 220) or rgb(60, 95, 225),
		{ Radius = 18, OutlineThickness = 4, GlossHeight = 26 })
		if big then UIKit.sparkles(card, WHITE, 2 + size * 0.5, 6) end

		local stage = new("Frame", { Position = UDim2.fromOffset(0, 6), Size = UDim2.new(1, 0, 0, 130), BackgroundTransparency = 1 }, card)
		UIKit.rays(stage, rgb(245, 215, 255), 200 + size * 14, 12 + size * 2, { ImageTransparency = big and 0.35 or 0.55 })
		UIKit.glow(stage, rgb(235, 160, 255), 130 + size * 16, { ImageTransparency = big and 0.1 or 0.3 })
		local pile = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.55),
			Size = UDim2.fromOffset(1, 1),
			BackgroundTransparency = 1,
		}, stage)
		for k, g in ipairs(PILES[size]) do
			icon(pile, "gem", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(g[1], g[2]),
				Size = UDim2.fromOffset(g[3], g[3]),
				Rotation = (k % 2 == 0) and 8 or -8,
				ZIndex = 3 + k,
			})
		end
		table.insert(bobbers, { obj = pile, y = 0.55, seed = i * 1.3 })

		UIKit.title(card, {
			Text = pack.Title,
			Position = UDim2.fromOffset(0, 136),
			Size = UDim2.new(1, 0, 0, 30),
			TextSize = 26,
			ZIndex = 4,
		})
		if pack.Tag then tagRibbon(card, pack.Tag) end

		local btn = UIKit.button(card, {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -10),
			Size = UDim2.new(1, -26, 0, 52),
			Color = "green",
			Text = tostring(pack.Robux or "?"),
			Font = UIKit.Font.Title,
			TextSize = 26,
			ZIndex = 5,
		})
		-- значок Robux (своя картинка из MetaConfig.RobuxIcon)
		btn.Icon.Image = robuxImage
		btn.Icon.ImageRectOffset = Vector2.zero
		btn.Icon.ImageRectSize = Vector2.zero
		btn.Icon.Size = UDim2.fromOffset(30, 30)
		btn.Icon.Visible = robuxImage ~= ""

		-- настоящая цена из Roblox (если товар уже создан)
		if pack.ProductId and pack.ProductId ~= 0 then
			task.spawn(function()
				local ok, info = pcall(function()
					return MarketplaceService:GetProductInfo(pack.ProductId, Enum.InfoType.Product)
				end)
				if ok and info and info.PriceInRobux then
					btn.setText(tostring(info.PriceInRobux))
				end
			end)
		end

		btn.Button.MouseButton1Click:Connect(function()
			if not pack.ProductId or pack.ProductId == 0 then
				UIKit.shake(btn.Button)
				if RunService:IsStudio() then
					toast("Put ProductId for " .. pack.Id .. " in MetaConfig", "warning")
				else
					toast("Coming soon!", "lock")
				end
				return
			end
			MarketplaceService:PromptProductPurchase(player, pack.ProductId)
		end)
	end

	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, bought)
		if userId ~= player.UserId or not bought then return end
		for _, pack in ipairs(MetaConfig.GemPacks) do
			if pack.ProductId == productId then
				UIKit.toast(shopGui, "Thank you! +" .. UIKit.commas(pack.Gems) .. " Gems", { Color = rgb(150, 255, 150), Icon = "gem", Y = 70 })
				UIKit.pop(win.Panel, 1.04, 0.3)
			end
		end
	end)

	-- CASH ЗА ГЕМЫ (покупка идёт через сервер меню)
	local metaRemote = ReplicatedStorage:WaitForChild("Meta", 30)
	if #MetaConfig.Shop > 0 then
		sectionHeader("coin", "CASH", 7)
		local cashGrid = shopGrid(8, math.ceil(#MetaConfig.Shop / 3))
		for i, item in ipairs(MetaConfig.Shop) do
			local card = UIKit.panel(cashGrid, { Name = item.Id, LayoutOrder = i }, rgb(255, 235, 140), rgb(235, 140, 30),
			{ Radius = 18, OutlineThickness = 4, GlossHeight = 26 })
			local stage = new("Frame", { Position = UDim2.fromOffset(0, 6), Size = UDim2.new(1, 0, 0, 130), BackgroundTransparency = 1 }, card)
			UIKit.rays(stage, rgb(255, 250, 200), 230, 14, { ImageTransparency = 0.5 })
			UIKit.glow(stage, rgb(255, 230, 120), 170, { ImageTransparency = 0.25 })
			local img = icon(stage, item.Icon, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.55),
				Size = UDim2.fromOffset(96, 96),
				ZIndex = 3,
			})
			table.insert(bobbers, { obj = img, y = 0.55, seed = 10 + i })
			UIKit.title(card, {
				Text = item.Title,
				Position = UDim2.fromOffset(0, 136),
				Size = UDim2.new(1, 0, 0, 30),
				TextSize = 26,
				ZIndex = 4,
			})
			if item.Tag then tagRibbon(card, item.Tag) end
			local cur, amount = next(item.Cost)
			local btn = UIKit.button(card, {
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -10),
				Size = UDim2.new(1, -26, 0, 52),
				Color = "purple",
				Icon = CUR_ICON[cur],
				IconSize = 32,
				Text = UIKit.commas(amount),
				Font = UIKit.Font.Title,
				TextSize = 26,
				ZIndex = 5,
			})
			btn.Button.MouseButton1Click:Connect(function()
				if wallet(cur) < amount then
					UIKit.shake(btn.Button)
					toast("Not enough " .. (CUR_NAME[cur] or cur) .. "!", CUR_ICON[cur])
					return
				end
				if not metaRemote then
					toast("Shop is loading, try again", "warning")
					return
				end
				local ok, res = pcall(function()
					return metaRemote:InvokeServer("buy", item.Id)
				end)
				if ok and typeof(res) == "table" and res.ok then
					UIKit.pop(img, 1.6, 0.4)
					UIKit.toast(shopGui, res.msg or "Bought!", { Color = rgb(150, 255, 150), Icon = item.Icon, Y = 70 })
				else
					UIKit.shake(btn.Button)
					toast((ok and typeof(res) == "table" and res.msg) or "Try again in a moment", "warning")
				end
			end)
		end
	end
end)

RunService.RenderStepped:Connect(function()
	if not root.Visible then return end
	local t = os.clock()
	for _, b in ipairs(bobbers) do
		b.obj.Position = UDim2.new(0.5, 0, b.y, math.sin(t * 2.2 + b.seed) * 5)
	end
end)

---------------------------------------------------------------- экран открытия: РУЛЕТКА КАК В CS
-- 1. сундук падает и раскрывается
-- 2. лента юнитов летит и тормозит (щелчок на каждом юните), стрелка в центре
-- 3. остановка → лента доезжает до центра выигрыша
-- 4. праздник по редкости: вспышки, фейерверки, дождь монет, буквы по одной, радуга у Mythic
-- Лента честная: юниты на ней выпадают по настоящим шансам сундука. Что выпало — решил сервер заранее.
-- SKIP — геймпасс «Instant Open» (MetaConfig.SkipPass). Без него кнопка предлагает купить.

local SoundService = game:GetService("SoundService")

-- ЗВУКИ. Свои звуки: Toolbox → Audio → найди звук → правый клик → Copy Asset ID →
-- вставь сюда: Id = "rbxassetid://123456". Пустая строка "" — без звука.
local SOUNDS = {
	Tick = { Id = "rbxasset://sounds/action_jump_land.mp3", Volume = 0.35, Speed = 3.4 },  -- щелчок, юнит прошёл стрелку
	Start = { Id = "rbxasset://sounds/action_jump.mp3", Volume = 0.7, Speed = 0.7 },       -- лента сорвалась с места
	Stop = { Id = "rbxasset://sounds/action_jump_land.mp3", Volume = 1, Speed = 0.8 },     -- лента остановилась / удар сердца
	Boom = { Id = "rbxasset://sounds/action_jump_land.mp3", Volume = 1, Speed = 0.45 },    -- взрыв выигрыша
	Crack = { Id = "rbxasset://sounds/action_jump_land.mp3", Volume = 1, Speed = 2.1 },   -- треск (Mythic)
	Comet = { Id = "rbxasset://sounds/action_jump.mp3", Volume = 1, Speed = 0.35 },       -- гул падающей кометы (Legendary)
	Shatter = { Id = "", Volume = 1, Speed = 1 },    -- звон разбитого стекла (Mythic) — вставь свой звук
	Win = { Id = "", Volume = 0.8, Speed = 1 },      -- фанфары (Common / Rare / Epic) — вставь свой звук
	BigWin = { Id = "", Volume = 1, Speed = 1 },     -- большие фанфары (Legendary / Mythic) — вставь свой звук
}

local CARD_W, CARD_H, GAP = 150, 178, 12
local STEP = CARD_W + GAP
local STRIP_W = 1010           -- ширина окна ленты (видно ~6 юнитов)
local WIN_INDEX = 46           -- на какой по счёту карточке остановится лента
local LAST_INDEX = WIN_INDEX + 6
local START_POS = 3 * STEP
local SPIN_TIME = 6            -- секунд прокрутки
local POOL = 12                -- карточек в памяти (видимые переиспользуются)

local overlay = new("ScreenGui", {
	Name = "CaseOpenGui",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 60,
	Enabled = false,
}, playerGui)

---------------------------------------------------------------- звуки

local soundBank = {}
local function sound(name, speedMul)
	if player:GetAttribute("Set_Music") == false then return end
	local cfg = SOUNDS[name]
	if not cfg or not cfg.Id or cfg.Id == "" then return end
	local bank = soundBank[name]
	if not bank then
		bank = { i = 0, list = {} }
		for _ = 1, (name == "Tick" and 6 or 2) do
			local snd = Instance.new("Sound")
			snd.Name = "Case" .. name
			snd.SoundId = cfg.Id
			snd.Volume = cfg.Volume or 0.6
			snd.Parent = SoundService
			table.insert(bank.list, snd)
		end
		soundBank[name] = bank
	end
	bank.i = bank.i % #bank.list + 1
	local snd = bank.list[bank.i]
	snd.PlaybackSpeed = (cfg.Speed or 1) * (speedMul or 1)
	snd.TimePosition = 0
	snd:Play()
end

---------------------------------------------------------------- фон и сцена

local bg = new("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = WHITE,
	BorderSizePixel = 0,
	Active = true,
}, overlay)
local DEFAULT_BG = ColorSequence.new(rgb(70, 30, 160), rgb(15, 5, 45))
local bgGrad = new("UIGradient", { Rotation = 90, Color = DEFAULT_BG }, bg)
UIKit.sparkles(bg, rgb(230, 220, 255), 3, 3)

-- затемнение по краям (растёт, когда лента почти остановилась)
local dark = new("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = BLACK,
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ZIndex = 2,
}, bg)
new("UIGradient", {
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, 0.75),
		NumberSequenceKeypoint.new(0.5, 1),
		NumberSequenceKeypoint.new(0.7, 0.75),
		NumberSequenceKeypoint.new(1, 0),
	}),
}, dark)

-- всё, что трясётся при взрывах, лежит в shakeRoot
local shakeRoot = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 3 }, bg)

local stage = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.4),
	Size = UDim2.fromOffset(600, 600),
	BackgroundTransparency = 1,
	ZIndex = 3,
}, shakeRoot)
local stageScale = new("UIScale", {}, stage)

local rays = UIKit.rays(stage, WHITE, 760, 20, { ImageTransparency = 1, ZIndex = 3 })
local rays2 = UIKit.rays(stage, WHITE, 560, -32, { ImageTransparency = 1, ZIndex = 3 })
local glow = UIKit.glow(stage, WHITE, 380, { ImageTransparency = 1, ZIndex = 4 })
local shadow = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 130),
	Size = UDim2.fromOffset(220, 40),
	BackgroundColor3 = BLACK,
	BackgroundTransparency = 0.6,
	BorderSizePixel = 0,
	ZIndex = 4,
}, stage)
corner(shadow, 20)
local chest = UIKit.art(stage, "chestHero", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(280, 280),
	ZIndex = 6,
})
local burst = UIKit.art(stage, "burst", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(100, 100),
	ImageTransparency = 1,
	ZIndex = 5,
})
local ring = UIKit.art(stage, "ring", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(100, 100),
	ImageTransparency = 1,
	ZIndex = 7,
})

-- юнит в 3D (финал)
local unitView = new("ViewportFrame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.52),
	Size = UDim2.fromOffset(380, 380),
	BackgroundTransparency = 1,
	Ambient = rgb(210, 205, 225),
	LightColor = WHITE,
	LightDirection = Vector3.new(-0.4, -1, -0.6),
	Visible = false,
	ZIndex = 8,
}, stage)
local unitScale = new("UIScale", {}, unitView)

-- убрать модель из вьюпорта финала (UIScale остаётся — им юнит «выпрыгивает»)
local function clearUnitView()
	for _, c in ipairs(unitView:GetChildren()) do
		if not c:IsA("UIScale") then
			c:Destroy()
		end
	end
end

local rarityTitle = UIKit.title(stage, {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0, 70),
	Size = UDim2.fromOffset(600, 80),
	TextSize = 66,
	Text = "",
	Visible = false,
	ZIndex = 10,
})
local rarityGrad = rarityTitle:FindFirstChildOfClass("UIGradient")

-- буквы редкости по одной (Legendary / Mythic)
local letterRow = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0, 70),
	Size = UDim2.fromOffset(900, 100),
	BackgroundTransparency = 1,
	Visible = false,
	ZIndex = 10,
}, stage)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	Padding = UDim.new(0, 2),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, letterRow)


---------------------------------------------------------------- лента (рулетка)

local roulRoot = new("Frame", {
	Name = "Roulette",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.46),
	Size = UDim2.fromOffset(STRIP_W + 36, CARD_H + 52),
	BackgroundTransparency = 1,
	Visible = false,
	ZIndex = 4,
}, shakeRoot)
local roulScale = new("UIScale", {}, roulRoot)

local roulGlow = UIKit.glow(roulRoot, WHITE, UDim2.fromOffset(STRIP_W * 1.3, 560), { ImageTransparency = 0.6, ZIndex = 4 })
local roulRays = UIKit.rays(roulRoot, WHITE, 1150, 6, { ImageTransparency = 0.88, ZIndex = 4 })
UIKit.panel(roulRoot, { Size = UDim2.fromScale(1, 1), ZIndex = 5 }, rgb(110, 80, 210), rgb(38, 20, 92),
{ Radius = 24, OutlineThickness = 5, GlossHeight = 18 })

local caseTitle = UIKit.title(roulRoot, {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 0, -8),
	Size = UDim2.new(1, 0, 0, 56),
	TextSize = 50,
	Text = "",
	ZIndex = 6,
})

-- шансы под лентой (честно показываем, что может выпасть)
local oddsRow = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 1, 10),
	Size = UDim2.new(1, 0, 0, 30),
	BackgroundTransparency = 1,
	ZIndex = 6,
}, roulRoot)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	Padding = UDim.new(0, 10),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, oddsRow)

local clip = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(STRIP_W, CARD_H + 16),
	BackgroundColor3 = rgb(12, 6, 30),
	BorderSizePixel = 0,
	ClipsDescendants = true,
	ZIndex = 6,
}, roulRoot)
corner(clip, 12)
stroke(clip, rgb(255, 215, 90), 2, 0.35)

local cardsLayer = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 7 }, clip)

-- полосы скорости
local speedLines = {}
for i = 1, 7 do
	local l = new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(math.random(), (i - 0.5) / 7),
		Size = UDim2.fromOffset(math.random(120, 320), math.random(2, 3)),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 12,
	}, clip)
	speedLines[i] = { frame = l, x = math.random() * STRIP_W, speedMul = 1.3 + math.random() }
end

-- края ленты уходят в темноту
for side = 0, 1 do
	local edge = new("Frame", {
		AnchorPoint = Vector2.new(side, 0),
		Position = UDim2.fromScale(side, 0),
		Size = UDim2.new(0, 180, 1, 0),
		BackgroundColor3 = rgb(12, 6, 30),
		BorderSizePixel = 0,
		ZIndex = 13,
	}, clip)
	new("UIGradient", {
		Transparency = side == 0 and NumberSequence.new(0, 1) or NumberSequence.new(1, 0),
	}, edge)
end

-- стрелка в центре: золотая линия и два ромба
local marker = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(6, CARD_H + 40),
	BackgroundColor3 = rgb(255, 215, 70),
	BorderSizePixel = 0,
	ZIndex = 15,
}, roulRoot)
stroke(marker, INK, 2)
local markerScale = new("UIScale", {}, marker)
local markerGlow = UIKit.glow(roulRoot, rgb(255, 220, 90), UDim2.fromOffset(110, CARD_H + 150), { ImageTransparency = 0.5, ZIndex = 14 })
for _, top in ipairs({ true, false }) do
	local d = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = top and UDim2.new(0.5, 0, 0, 0) or UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.fromOffset(26, 26),
		Rotation = 45,
		BackgroundColor3 = rgb(255, 225, 90),
		BorderSizePixel = 0,
		ZIndex = 16,
	}, marker)
	corner(d, 4)
	stroke(d, INK, 3)
end

local function roulFit()
	local cam = workspace.CurrentCamera
	if not cam then return 1 end
	local vs = cam.ViewportSize
	return math.clamp(math.min(vs.X * 0.94 / (STRIP_W + 36), vs.Y * 0.45 / (CARD_H + 52)), 0.35, 1.15)
end

---------------------------------------------------------------- карточки ленты (3D-юниты, переиспользуются)

-- юниты по редкостям — как на сервере
local unitPools = {}
for name, cfg in pairs(TowerData) do
	local r = cfg.Rarity or "Common"
	unitPools[r] = unitPools[r] or {}
	table.insert(unitPools[r], name)
end
for _, names in pairs(unitPools) do
	table.sort(names)
end

-- случайный юнит по настоящим шансам сундука
local function randomItem(def)
	local total = 0
	for _, e in ipairs(def.Rates) do
		total += e.Weight
	end
	local x = math.random() * total
	local rarity = def.Rates[#def.Rates].Rarity
	for _, e in ipairs(def.Rates) do
		x -= e.Weight
		if x <= 0 then
			rarity = e.Rarity
			break
		end
	end
	local pool = unitPools[rarity]
	if not pool or #pool == 0 then
		for _, e in ipairs(def.Rates) do
			if unitPools[e.Rarity] and #unitPools[e.Rarity] > 0 then
				rarity, pool = e.Rarity, unitPools[e.Rarity]
				break
			end
		end
	end
	if not pool or #pool == 0 then return nil end
	return { unit = pool[math.random(#pool)], rarity = rarity }
end

-- камера для каждого юнита: считается один раз по видимым деталям шаблона
local unitCams = {}
local function camFor(name)
	local cf = unitCams[name]
	if cf ~= nil then return cf end
	unitCams[name] = false
	local template = templatesFolder():FindFirstChild(name)
	if not template then return false end
	local minV, maxV = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, p in ipairs(template:GetDescendants()) do
		if p:IsA("BasePart") and p.Transparency < 0.95 then
			local half = p.Size / 2
			for _, sx in ipairs({ -1, 1 }) do
				for _, sy in ipairs({ -1, 1 }) do
					for _, sz in ipairs({ -1, 1 }) do
						local c = (p.CFrame * CFrame.new(half.X * sx, half.Y * sy, half.Z * sz)).Position
						minV = minV:Min(c)
						maxV = maxV:Max(c)
					end
				end
			end
		end
	end
	if minV.X == math.huge then
		local ok, bcf, size = pcall(function() return template:GetBoundingBox() end)
		if not ok then return false end
		minV, maxV = bcf.Position - size / 2, bcf.Position + size / 2
	end
	local center = (minV + maxV) / 2
	local extent = maxV - minV
	local radius = math.max(extent.X, extent.Y, extent.Z) / 2
	local dist = radius / math.tan(math.rad(20)) * 1.12 + 0.5
	local pivot = template:GetPivot()
	local dir = (pivot.LookVector + pivot.RightVector * 0.45 + Vector3.new(0, 0.25, 0)).Unit
	cf = CFrame.lookAt(center + dir * dist, center)
	unitCams[name] = cf
	return cf
end

local function cloneUnit(name)
	local template = templatesFolder():FindFirstChild(name)
	if not template then return nil end
	local ok, model = pcall(function()
		local m = template:Clone()
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("LuaSourceContainer") then d:Destroy() end
		end
		PlacementRules.prepareRig(m)
		return m
	end)
	return ok and model or nil
end

-- запас готовых копий моделей: [юнит] = { модели, которые сейчас никто не показывает }
local freeModels = {}
local function takeModel(name)
	local list = freeModels[name]
	if list and #list > 0 then
		return table.remove(list)
	end
	return cloneUnit(name)
end
local function giveBackModel(name, model)
	if not model then return end
	model.Parent = nil
	freeModels[name] = freeModels[name] or {}
	table.insert(freeModels[name], model)
end
-- заранее скопировать по 2 модели каждого юнита ленты (по одной за кадр — без подвисаний)
local function warmModels(items)
	local need = {}
	for _, item in pairs(items) do
		need[item.unit] = true
	end
	for name in pairs(need) do
		freeModels[name] = freeModels[name] or {}
		while #freeModels[name] < 2 do
			local m = cloneUnit(name)
			if not m then break end
			table.insert(freeModels[name], m)
			RunService.Heartbeat:Wait()
		end
	end
end

local slots = {}
local function makeSlot()
	local f = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(CARD_W, CARD_H),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 7,
	}, cardsLayer)
	corner(f, 14)
	local grad = new("UIGradient", { Rotation = 90 }, f)
	local st = stroke(f, WHITE, 3)
	local sc = new("UIScale", {}, f)
	local gl = UIKit.glow(f, WHITE, UDim2.new(1.3, 0, 1, 0), { Position = UDim2.fromScale(0.5, 0.45), ImageTransparency = 0.4, ZIndex = 7 })
	local vp = new("ViewportFrame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.new(1, -10, 0, 124),
		BackgroundTransparency = 1,
		Ambient = rgb(200, 200, 215),
		LightColor = WHITE,
		LightDirection = Vector3.new(-0.4, -1, -0.6),
		ZIndex = 8,
	}, f)
	local world = Instance.new("WorldModel")
	world.Parent = vp
	local cam = Instance.new("Camera")
	cam.FieldOfView = 40
	cam.Parent = vp
	vp.CurrentCamera = cam
	local nameL = text(f, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -15),
		Size = UDim2.new(1, -10, 0, 24),
		Font = UIKit.Font.Title,
		TextSize = 18,
		TextScaled = true,
		Text = "",
		ZIndex = 9,
	})
	new("UITextSizeConstraint", { MaxTextSize = 18 }, nameL)
	local bar = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -5),
		Size = UDim2.new(1, -14, 0, 8),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = 9,
	}, f)
	corner(bar, 4)
	local star = icon(f, "star", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -5, 0, 5),
		Size = UDim2.fromOffset(26, 26),
		Visible = false,
		ZIndex = 9,
	})
	local dim = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = BLACK,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 10,
	}, f)
	corner(dim, 14)
	return {
		frame = f, grad = grad, stroke = st, scale = sc, glow = gl, vp = vp, world = world, cam = cam,
		name = nameL, bar = bar, star = star, dim = dim, model = nil, current = nil, idx = nil, rainbow = false,
	}
end
for i = 1, POOL do
	slots[i] = makeSlot()
end

local function paintSlot(slot, item)
	local c = rarityColor(item.rarity)
	local rank = RANK[item.rarity] or 1
	slot.grad.Color = ColorSequence.new(rgb(46, 36, 92):Lerp(c, 0.12), c:Lerp(rgb(14, 8, 34), 0.4))
	slot.stroke.Color = c:Lerp(WHITE, 0.15)
	slot.glow.ImageColor3 = c
	slot.glow.ImageTransparency = rank >= 4 and 0.2 or 0.45
	slot.bar.BackgroundColor3 = c
	slot.name.Text = string.upper(item.unit)
	slot.star.Visible = rank >= 4 and UIKit.IconsReady
	slot.rainbow = item.rarity == "Mythic"
	slot.dim.BackgroundTransparency = 1
	slot.scale.Scale = 1

	if slot.current ~= item.unit then
		if slot.current then
			giveBackModel(slot.current, slot.model)
		end
		local m = takeModel(item.unit)
		if m then m.Parent = slot.world end
		slot.model = m
		local cf = camFor(item.unit)
		if cf then slot.cam.CFrame = cf end
		slot.current = item.unit
	end
end

-- расставить видимые карточки: pos — какая точка ленты под стрелкой (в пикселях)
local function layoutStrip(s, pos)
	local half = STRIP_W / 2 + STEP
	local first = math.max(0, math.floor((pos - half) / STEP))
	local last = math.min(LAST_INDEX, math.ceil((pos + half) / STEP))
	local used = {}
	for idx = first, last do
		local item = s.items[idx]
		if item then
			local slot = slots[idx % POOL + 1]
			if slot.idx ~= idx then
				slot.idx = idx
				paintSlot(slot, item)
			end
			slot.frame.Position = UDim2.new(0.5, idx * STEP - pos, 0.5, 0)
			slot.frame.Visible = true
			used[slot] = true
		end
	end
	for _, slot in ipairs(slots) do
		if not used[slot] then
			slot.frame.Visible = false
		end
	end
end

local function slotAt(idx)
	local slot = slots[idx % POOL + 1]
	return slot.idx == idx and slot or nil
end

-- шансы под лентой
local function fillOdds(def)
	for _, c in ipairs(oddsRow:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	for i, e in ipairs(def.Rates) do
		local c = rarityColor(e.Rarity)
		local pill = new("Frame", {
			Size = UDim2.fromOffset(0, 28),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = c:Lerp(rgb(20, 12, 45), 0.35),
			BorderSizePixel = 0,
			LayoutOrder = i,
			ZIndex = 6,
		}, oddsRow)
		corner(pill, 14)
		stroke(pill, c:Lerp(WHITE, 0.3), 2)
		new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, pill)
		text(pill, {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.new(0, 0, 1, 0),
			Font = UIKit.Font.Title,
			TextSize = 16,
			Text = string.upper(e.Rarity) .. "  " .. pctText(CaseConfig.Chance(def, e.Rarity)) .. "%",
			ZIndex = 7,
		})
	end
end

---------------------------------------------------------------- кнопка SKIP (геймпасс)

local skipHolder = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -26),
	Size = UDim2.fromOffset(250, 66),
	BackgroundTransparency = 1,
	Visible = false,
	ZIndex = 22,
}, bg)
local skipScale = new("UIScale", {}, skipHolder)
local skipBtn = UIKit.button(skipHolder, {
	Size = UDim2.fromScale(1, 1),
	Color = "purple",
	Icon = "skip",
	IconSize = 38,
	Text = "SKIP",
	Font = UIKit.Font.Title,
	TextSize = 28,
	ZIndex = 22,
})
local skipPrice = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(1, -18, 0, 2),
	Size = UDim2.fromOffset(0, 34),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundColor3 = rgb(255, 205, 50),
	BorderSizePixel = 0,
	Rotation = 8,
	ZIndex = 24,
}, skipBtn.Button)
corner(skipPrice, 17)
stroke(skipPrice, INK, 3)
new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 10) }, skipPrice)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	Padding = UDim.new(0, 4),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, skipPrice)
local skipRobux = new("ImageLabel", {
	Size = UDim2.fromOffset(24, 24),
	BackgroundTransparency = 1,
	ScaleType = Enum.ScaleType.Fit,
	LayoutOrder = 1,
	ZIndex = 25,
}, skipPrice)
local skipPriceText = text(skipPrice, {
	AutomaticSize = Enum.AutomaticSize.X,
	Size = UDim2.new(0, 0, 1, 0),
	Font = UIKit.Font.Title,
	TextSize = 20,
	Text = "40",
	LayoutOrder = 2,
	ZIndex = 25,
})

local function otoast(msg, iconName, color)
	UIKit.toast(overlay, msg, { Color = color or rgb(255, 230, 150), Icon = iconName, Y = 60 })
end

local function refreshSkip()
	if hasPass() then
		skipBtn.setColor("green")
		skipBtn.setText("SKIP")
		skipPrice.Visible = false
	else
		skipBtn.setColor("purple")
		skipBtn.setText("SKIP")
		skipPrice.Visible = true
		skipRobux.Image = skipPassCfg.RobuxIcon or ""
		skipRobux.Visible = skipRobux.Image ~= ""
		skipPriceText.Text = tostring(skipPassCfg.Robux or 40)
	end
end

skipBtn.Button.MouseButton1Click:Connect(function()
	local s = scene
	if not s or s.skip or not s.canSkip then return end
	if hasPass() then
		s.skip = true
		return
	end
	local id = skipPassCfg.Id or 0
	if id == 0 then
		UIKit.shake(skipBtn.Button)
		if RunService:IsStudio() then
			otoast("Put the SkipPass Id in MetaConfig", "warning")
		else
			otoast("Coming soon!", "lock")
		end
		return
	end
	MarketplaceService:PromptGamePassPurchase(player, id)
end)

-- купил прямо во время прокрутки — сразу пропускаем
player:GetAttributeChangedSignal("SkipPass"):Connect(function()
	refreshSkip()
	local s = scene
	if hasPass() and s and s.canSkip and not s.skip then
		otoast("Instant Open unlocked!", "skip", rgb(150, 255, 150))
		s.skip = true
	end
end)

---------------------------------------------------------------- карточка результата

local card = UIKit.panel(bg, {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -16),
	Size = UDim2.fromOffset(560, 236),
	Visible = false,
	ZIndex = 18,
}, rgb(120, 205, 255), rgb(55, 70, 220), { Radius = 24, GlossHeight = 30 })
local cardScale = new("UIScale", {}, card)
local cardStroke = card:FindFirstChildOfClass("UIStroke")

local resName = UIKit.title(card, { Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 0, 44), TextSize = 42, Text = "", ZIndex = 19 })
local resNameGrad = resName:FindFirstChildOfClass("UIGradient")

local newBadge = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(1, -40, 0, 14),
	Size = UDim2.fromOffset(110, 110),
	BackgroundTransparency = 1,
	Rotation = 12,
	Visible = false,
	ZIndex = 20,
}, card)
UIKit.art(newBadge, "burst", { Size = UDim2.fromScale(1, 1), ImageColor3 = rgb(255, 225, 60), ZIndex = 20 })
text(newBadge, { Size = UDim2.fromScale(1, 1), Text = "NEW!", Font = UIKit.Font.Title, TextSize = 30, ZIndex = 21 })
UIKit.wobble(newBadge, 14, 0.5)

local dupPill = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 56),
	Size = UDim2.fromOffset(250, 32),
	BackgroundColor3 = rgb(35, 22, 80),
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 19,
}, card)
corner(dupPill, 16)
stroke(dupPill, WHITE, 3)
local dupText = text(dupPill, { Size = UDim2.fromScale(1, 1), Font = UIKit.Font.Title, TextSize = 19, ZIndex = 20 })

local cashRow = new("Frame", {
	Position = UDim2.fromOffset(0, 92),
	Size = UDim2.new(1, 0, 0, 40),
	BackgroundTransparency = 1,
	Visible = false,
	ZIndex = 19,
}, card)
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, cashRow)
local cashIcon = icon(cashRow, "coin", { Size = UDim2.fromOffset(40, 40), LayoutOrder = 1, ZIndex = 20 })
local cashText = UIKit.title(cashRow, {
	AutomaticSize = Enum.AutomaticSize.X,
	Size = UDim2.new(0, 0, 1, 0),
	TextSize = 30,
	Text = "+0",
	Colors = { rgb(200, 255, 170), rgb(60, 220, 90) },
	LayoutOrder = 2,
	ZIndex = 20,
})

local infoRow = new("Frame", {
	Position = UDim2.fromOffset(16, 60),
	Size = UDim2.new(1, -32, 0, 44),
	BackgroundTransparency = 1,
	ZIndex = 19,
}, card)
local infoIcon = icon(infoRow, "lightning", { Position = UDim2.fromOffset(0, 6), Size = UDim2.fromOffset(32, 32), ZIndex = 20 })
local infoLine = text(infoRow, {
	Position = UDim2.fromOffset(38, 0),
	Size = UDim2.new(1, -38, 1, 0),
	TextSize = 15,
	TextWrapped = true,
	RichText = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = rgb(240, 245, 255),
	ZIndex = 20,
})

local again = UIKit.button(card, {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 16, 1, -14),
	Size = UDim2.new(0.5, -22, 0, 60),
	Color = "purple",
	Text = "AGAIN",
	Font = UIKit.Font.Title,
	TextSize = 22,
	IconSize = 34,
	ZIndex = 19,
})
local okBtn = UIKit.button(card, {
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -16, 1, -14),
	Size = UDim2.new(0.5, -22, 0, 60),
	Color = "yellow",
	Icon = "check",
	IconSize = 34,
	Text = "AWESOME!",
	Font = UIKit.Font.Title,
	TextSize = 24,
	ZIndex = 19,
})
UIKit.pulse(new("UIScale", {}, okBtn.Face), 1.05, 0.55)

local flash = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 30 }, overlay)
local fade = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = BLACK, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 31 }, overlay)

local cashValue = Instance.new("NumberValue")
cashValue.Changed:Connect(function(v)
	cashText.Text = "+" .. UIKit.commas(v + 0.5)
end)

---------------------------------------------------------------- эффекты

-- искры из точки (parent — любой кадр, pos — UDim2 внутри него)
local function burstAt(parent, pos, color, count, radius, z)
	for i = 1, count do
		local a = (i / count) * math.pi * 2 + math.random() * 0.4
		local size = math.random(18, 34)
		local sp = UIKit.art(parent, "sparkle", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = pos,
			Size = UDim2.fromOffset(size, size),
			ImageColor3 = color,
			ZIndex = z or 9,
		})
		local r = radius * (0.6 + math.random() * 0.5)
		local t = 0.5 + math.random() * 0.4
		TweenService:Create(sp, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = pos + UDim2.fromOffset(math.cos(a) * r, math.sin(a) * r),
			ImageTransparency = 1,
			Rotation = math.random(-180, 180),
		}):Play()
		Debris:AddItem(sp, t + 0.05)
	end
end

local function sparkBurst(color, count, radius)
	burstAt(stage, UDim2.fromScale(0.5, 0.5), color, count, radius, 9)
end

-- вспышка на весь экран
local function flashScreen(color, from, time)
	flash.BackgroundColor3 = color
	flash.BackgroundTransparency = from or 0
	tween(flash, time or 0.6, { BackgroundTransparency = 1 })
end

-- тряска всего экрана: strength пикселей, затухает за time
local shakeAmp = Instance.new("NumberValue")
local function screenShake(strength, time)
	if not shakeOn() then return end
	shakeAmp.Value = math.max(shakeAmp.Value, strength)
	TweenService:Create(shakeAmp, TweenInfo.new(time or 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = 0 }):Play()
end

-- 3D-модель юнита во вьюпорте финала (крутится вокруг своего центра)
local function buildUnit(name)
	clearUnitView()
	local template = templatesFolder():FindFirstChild(name)
	if not template then return nil end
	local ok, result = pcall(function()
		local model = template:Clone()
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("LuaSourceContainer") then d:Destroy() end
		end
		PlacementRules.prepareRig(model)
		local world = Instance.new("WorldModel")
		world.Parent = unitView
		model.Parent = world
		RunService.Heartbeat:Wait()

		local cf, size = model:GetBoundingBox()
		local center = cf.Position
		local radius = math.max(size.X, size.Y, size.Z) / 2
		local cam = Instance.new("Camera")
		cam.FieldOfView = 40
		cam.Parent = unitView
		unitView.CurrentCamera = cam
		local dist = radius / math.tan(math.rad(20)) * 1.05 + 0.5
		local look = (model:GetPivot().LookVector * Vector3.new(1, 0, 1))
		if look.Magnitude < 0.01 then look = Vector3.new(0, 0, -1) end
		look = look.Unit
		cam.CFrame = CFrame.lookAt(center + look * dist + Vector3.new(0, radius * 0.25, 0), center)
		return { model = model, center = CFrame.new(center), offset = CFrame.new(center):Inverse() * model:GetPivot() }
	end)
	if not ok then
		warn("[Cases] модель " .. name .. ": " .. tostring(result))
		return nil
	end
	return result
end

---------------------------------------------------------------- слои для особых выпадений

-- Mythic: чёрный экран и трещины лежат поверх всей сцены (под вспышкой)
local void = new("Frame", {
	Name = "Void",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = BLACK,
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 28,
}, overlay)
local crackLayer = new("Frame", {
	Name = "Cracks",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Visible = false,
	ZIndex = 29,
}, overlay)
-- Legendary: звёзды на небе (за сценой) и комета (над сценой)
local skyLayer = new("Frame", { Name = "Sky", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 2 }, bg)
local cometLayer = new("Frame", { Name = "CometFx", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 24 }, bg)
-- аура вокруг юнита: сзади модели и спереди
local auraBack = new("Frame", { Name = "AuraBack", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 7 }, stage)
local auraFront = new("Frame", { Name = "AuraFront", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 9 }, stage)

-- эффекты выпадения: функции в таблицах (в Luau не больше 200 local в одном месте)
local FX = {} -- красивые эффекты (ниже)
local CR = {} -- трещины Mythic
FX.back = new("Frame", { Name = "FxBack", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 2 }, bg)
FX.front = new("Frame", { Name = "FxFront", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 22 }, bg)

---------------------------------------------------------------- трещины (рисуются линиями, растут волнами)

CR.cracks = {} -- линии, которые есть на экране

-- ломаная линия между двумя точками (как настоящая трещина): середины отрезков сдвигаются в стороны
function CR.jagged(x1, y1, x2, y2, rough, maxIter)
	local pts = { { x1, y1 }, { x2, y2 } }
	local dist = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
	local iter = math.clamp(math.floor(math.log(math.max(dist, 1) / 18, 2) + 0.5), 1, maxIter or 4)
	local disp = dist * (rough or 0.15)
	for _ = 1, iter do
		local out = { pts[1] }
		for i = 1, #pts - 1 do
			local a, b = pts[i], pts[i + 1]
			local dx, dy = b[1] - a[1], b[2] - a[2]
			local len = math.sqrt(dx * dx + dy * dy)
			local mx, my = (a[1] + b[1]) / 2, (a[2] + b[2]) / 2
			if len > 0 then
				local off = (math.random() - 0.5) * disp
				mx -= dy / len * off
				my += dx / len * off
			end
			table.insert(out, { mx, my })
			table.insert(out, b)
		end
		pts = out
		disp *= 0.55
	end
	return pts
end

-- одна трещина: белая сердцевина + цветное свечение, к концу тоньше.
-- waitFor = { line, at } — начнёт расти, когда другая трещина дойдёт до этой точки
function CR.addCrack(pts, thickness, color, speed, waitFor)
	local line = { segs = {}, total = 0, shown = 0, target = 1, speed = speed or 1200, waitFor = waitFor, color = color }
	local n = #pts - 1
	for i = 1, n do
		local a, b = pts[i], pts[i + 1]
		local dx, dy = b[1] - a[1], b[2] - a[2]
		local len = math.sqrt(dx * dx + dy * dy)
		if len > 0.5 then
			local th = math.max(1, thickness * (1 - 0.65 * (i - 1) / math.max(1, n)))
			local f = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(a[1], a[2]),
				Size = UDim2.fromOffset(0, th),
				Rotation = math.deg(math.atan2(dy, dx)),
				BackgroundColor3 = WHITE,
				BorderSizePixel = 0,
				Visible = false,
				ZIndex = 29,
			}, crackLayer)
			new("UIStroke", {
				Color = color,
				Thickness = math.max(1.5, th * 1.3),
				Transparency = 0.45,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}, f)
			table.insert(line.segs, { f = f, x = a[1], y = a[2], dx = dx / len, dy = dy / len, len = len, th = th, start = line.total })
			line.total += len
		end
	end
	line.endX, line.endY = pts[#pts][1], pts[#pts][2]
	table.insert(CR.cracks, line)
	return line
end

-- точка на трещине на расстоянии d от начала (и направление в ней)
function CR.pointAt(line, d)
	for _, sg in ipairs(line.segs) do
		if d <= sg.start + sg.len then
			local k = math.max(0, d - sg.start)
			return sg.x + sg.dx * k, sg.y + sg.dy * k, math.atan2(sg.dy, sg.dx)
		end
	end
	local last = line.segs[#line.segs]
	return line.endX, line.endY, last and math.atan2(last.dy, last.dx) or 0
end

-- рост трещин (каждый кадр)
function CR.growCracks(dt)
	for _, line in ipairs(CR.cracks) do
		local goal = line.total * line.target
		local ready = not line.waitFor or line.waitFor.line.shown >= line.waitFor.at
		if line.shown < goal and ready then
			line.shown = math.min(goal, line.shown + line.speed * dt)
			for _, sg in ipairs(line.segs) do
				local vis = line.shown - sg.start
				if vis <= 0 then break end
				if not sg.full then
					local l = math.min(vis, sg.len)
					sg.f.Visible = true
					sg.f.Size = UDim2.fromOffset(l, sg.th)
					sg.f.Position = UDim2.fromOffset(sg.x + sg.dx * l / 2, sg.y + sg.dy * l / 2)
					sg.full = l >= sg.len
				end
			end
			if line.tip then
				local x, y = CR.pointAt(line, line.shown)
				line.tip.Position = UDim2.fromOffset(x, y)
				line.tip.Visible = true
			end
		elseif line.tip and line.tip.Visible then
			line.tip.Visible = false
		end
	end
end

function CR.setTargets(lines, value)
	for _, line in ipairs(lines) do
		line.target = value
	end
end

function CR.clearCracks()
	table.clear(CR.cracks)
	crackLayer:ClearAllChildren()
end

-- паутина трещин из точки удара: лучи, ветки и кольца
function CR.crackWeb(cx, cy, radius, rays, hue0, full, ringIter)
	local web = { radials = {}, cx = cx, cy = cy }
	local a0 = math.random() * math.pi * 2
	for i = 1, rays do
		local a = a0 + (i - 1) / rays * math.pi * 2 + (math.random() - 0.5) * (math.pi * 2 / rays) * 0.55
		local len = radius * (0.55 + math.random() * 0.45)
		local col = Color3.fromHSV((hue0 + i / rays) % 1, 0.08, 1) -- белый свет с еле заметным оттенком
		local line = CR.addCrack(CR.jagged(cx, cy, cx + math.cos(a) * len, cy + math.sin(a) * len, 0.13, 4), 3.6, col, 1500)
		-- светящаяся «искра» на конце растущей трещины
		line.tip = UIKit.art(crackLayer, "glow", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(cx, cy),
			Size = UDim2.fromOffset(44, 44),
			ImageColor3 = col:Lerp(WHITE, 0.5),
			ImageTransparency = 0.05,
			Visible = false,
			ZIndex = 29,
		})
		web.radials[i] = line
	end
	-- мелкое крошево в самой точке удара
	for _ = 1, 7 do
		local a = math.random() * math.pi * 2
		local l = 10 + math.random() * 26
		CR.addCrack(CR.jagged(cx, cy, cx + math.cos(a) * l, cy + math.sin(a) * l, 0.3, 2), 1.4, WHITE, 300, { line = web.radials[1], at = 2 })
	end
	if not full then return web end
	-- ветки от лучей
	for _, line in ipairs(web.radials) do
		for _ = 1, math.random(1, 2) do
			local d = line.total * (0.25 + math.random() * 0.5)
			local px, py, pa = CR.pointAt(line, d)
			local side = math.random() < 0.5 and -1 or 1
			local ba = pa + side * math.rad(22 + math.random() * 35)
			local bl = (line.total - d) * (0.3 + math.random() * 0.4)
			CR.addCrack(CR.jagged(px, py, px + math.cos(ba) * bl, py + math.sin(ba) * bl, 0.2, ringIter or 3), 2, line.color, 1000, { line = line, at = d })
		end
	end
	-- кольца паутины между соседними лучами
	for _, frac in ipairs({ 0.15, 0.32, 0.55 }) do
		for i = 1, rays do
			local L1, L2 = web.radials[i], web.radials[i % rays + 1]
			local r1 = radius * frac * (0.9 + math.random() * 0.2)
			local r2 = radius * frac * (0.9 + math.random() * 0.2)
			if r1 < L1.total and r2 < L2.total and math.random() < 0.8 then
				local x1, y1 = CR.pointAt(L1, r1)
				local x2, y2 = CR.pointAt(L2, r2)
				CR.addCrack(CR.jagged(x1, y1, x2, y2, 0.22, ringIter or 3), 1.6, L1.color:Lerp(L2.color, 0.5), 800, { line = L1, at = r1 })
			end
		end
	end
	return web
end

-- стеклянная крошка сыплется с трещин
function CR.glassDust(count)
	if #CR.cracks == 0 then return end
	if not effectsOn() then count = math.floor(count / 3) end
	for _ = 1, count do
		local line = CR.cracks[math.random(#CR.cracks)]
		if line.shown > 0 then
			local x, y = CR.pointAt(line, math.random() * line.shown)
			local p = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(x, y),
				Size = UDim2.fromOffset(math.random(2, 4), math.random(2, 5)),
				BackgroundColor3 = WHITE,
				BackgroundTransparency = 0.1,
				BorderSizePixel = 0,
				Rotation = math.random(0, 90),
				ZIndex = 29,
			}, crackLayer)
			local t = 0.8 + math.random() * 0.8
			TweenService:Create(p, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = UDim2.fromOffset(x + math.random(-20, 20), y + math.random(80, 220)),
				BackgroundTransparency = 1,
				Rotation = math.random(-180, 180),
			}):Play()
			Debris:AddItem(p, t + 0.1)
		end
	end
end

-- стекло разлетается: чёрные осколки с яркими краями летят на зрителя
function CR.shatter(cx, cy)
	local W, H = crackLayer.AbsoluteSize.X, crackLayer.AbsoluteSize.Y
	local cols = effectsOn() and 9 or 6
	local rows = math.max(3, math.floor(cols * H / math.max(W, 1) + 0.5))
	local cw, ch = W / cols, H / rows
	for r = 0, rows - 1 do
		for c = 0, cols - 1 do
			local x = (c + 0.5) * cw + (math.random() - 0.5) * cw * 0.35
			local y = (r + 0.5) * ch + (math.random() - 0.5) * ch * 0.35
			local sh = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(x, y),
				Size = UDim2.fromOffset(cw * 1.45, ch * 1.45),
				Rotation = math.random(-28, 28),
				BackgroundColor3 = WHITE,
				BorderSizePixel = 0,
				ZIndex = 29,
			}, crackLayer)
			new("UIGradient", { Rotation = math.random(0, 360), Color = ColorSequence.new(rgb(46, 34, 80), rgb(4, 2, 12)) }, sh)
			local st = stroke(sh, rgb(235, 242, 255), 2.5, 0.05)
			local sc = new("UIScale", {}, sh)
			local dx, dy = x - cx, y - cy
			local d = math.max(1, math.sqrt(dx * dx + dy * dy))
			local push = 250 + math.random() * 550
			local t = 0.7 + math.random() * 0.5
			TweenService:Create(sh, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = UDim2.fromOffset(x + dx / d * push, y + dy / d * push + math.random(60, 220)),
				Rotation = sh.Rotation + math.random(-220, 220),
				BackgroundTransparency = 1,
			}):Play()
			TweenService:Create(st, TweenInfo.new(t * 0.8), { Transparency = 1 }):Play()
			TweenService:Create(sc, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1.4 + math.random() * 0.7 }):Play()
			Debris:AddItem(sh, t + 0.1)
		end
	end
	-- мелкие сверкающие осколки
	for _ = 1, (effectsOn() and 50 or 15) do
		local a = math.random() * math.pi * 2
		local sp = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(cx, cy),
			Size = UDim2.fromOffset(math.random(3, 6), math.random(10, 26)),
			Rotation = math.deg(a) + 90,
			BackgroundColor3 = Color3.fromHSV(math.random(), 0.12, 1),
			BorderSizePixel = 0,
			ZIndex = 29,
		}, crackLayer)
		local dist = 300 + math.random() * 700
		local t = 0.4 + math.random() * 0.4
		TweenService:Create(sp, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(cx + math.cos(a) * dist, cy + math.sin(a) * dist),
			BackgroundTransparency = 1,
		}):Play()
		Debris:AddItem(sp, t + 0.1)
	end
end

-- молния ауры вокруг юнита (координаты сцены 600x600, центр юнита 300, 312)
function CR.auraArc(color)
	local a1 = math.random() * math.pi * 2
	local a2 = a1 + (math.random() - 0.5) * 1.6
	local r1, r2 = 120 + math.random() * 90, 120 + math.random() * 90
	local x1, y1 = 300 + math.cos(a1) * r1, 312 + math.sin(a1) * r1 * 0.8
	local x2, y2 = 300 + math.cos(a2) * r2, 312 + math.sin(a2) * r2 * 0.8
	local pts = CR.jagged(x1, y1, x2, y2, 0.45, 3)
	local parent = math.sin(a1) > 0 and auraFront or auraBack
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local dx, dy = b[1] - a[1], b[2] - a[2]
		local len = math.sqrt(dx * dx + dy * dy)
		if len > 0.5 then
			local f = new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset((a[1] + b[1]) / 2, (a[2] + b[2]) / 2),
				Size = UDim2.fromOffset(len + 1, 2),
				Rotation = math.deg(math.atan2(dy, dx)),
				BackgroundColor3 = WHITE,
				BorderSizePixel = 0,
				ZIndex = parent.ZIndex,
			}, parent)
			local st = stroke(f, color, 2, 0.15)
			tween(f, 0.18, { BackgroundTransparency = 1 })
			tween(st, 0.18, { Transparency = 1 })
			Debris:AddItem(f, 0.2)
		end
	end
end

---------------------------------------------------------------- общий цикл кадра

-- ждать sec секунд, пока сцена жива (пропуск ожидание не обрывает — сокращает сам код)
local function hold(sec)
	local s = scene
	local started = os.clock()
	while s and scene == s and os.clock() - started < sec do
		RunService.RenderStepped:Wait()
	end
end

-- ждать, но выйти сразу, если нажали SKIP
local function pause(sec)
	local s = scene
	local started = os.clock()
	while s and scene == s and not s.skip and os.clock() - started < sec do
		RunService.RenderStepped:Wait()
	end
end

RunService.RenderStepped:Connect(function(dt)
	local s = scene
	if not s then return end
	local t = os.clock()

	-- тряска
	local amp = shakeAmp.Value
	if amp > 0.2 then
		shakeRoot.Position = UDim2.fromOffset((math.random() - 0.5) * 2 * amp, (math.random() - 0.5) * 2 * amp)
	else
		shakeRoot.Position = UDim2.new()
	end

	-- сундук падает
	chest.Position = UDim2.new(0.5, 0, 0.5, s.chestY)

	-- юнит крутится
	if s.unit then
		local a = (t - s.unitBorn) * 1.1
		s.unit.model:PivotTo(s.unit.center * CFrame.Angles(0, a, 0) * s.unit.offset)
	end

	-- радуга для Mythic
	local rainbow = Color3.fromHSV((t * 0.35) % 1, 0.65, 1)
	if s.rainbow then
		rays.ImageColor3 = rainbow
		rays2.ImageColor3 = rainbow:Lerp(WHITE, 0.4)
		bgGrad.Color = ColorSequence.new(Color3.fromHSV((t * 0.2) % 1, 0.6, 0.32), rgb(4, 2, 12))
	end
	-- трещины растут, свет в точке удара переливается
	if #CR.cracks > 0 then
		CR.growCracks(dt)
	end

	-- аура: искры кружат вокруг юнита (впереди и сзади), свечение пульсирует
	local au = s.aura
	if au then
		for i, o in ipairs(au.orbs) do
			local a = t * o.speed + o.phase
			local front = math.sin(a) > 0
			if front ~= o.front then
				o.front = front
				o.img.Parent = front and auraFront or auraBack
				o.img.ZIndex = front and 9 or 7
			end
			o.img.Position = UDim2.new(0.5, math.cos(a) * o.r, 0.52, math.sin(a) * o.r * 0.38)
			local size = 22 + math.sin(t * 6 + i) * 8
			o.img.Size = UDim2.fromOffset(size, size)
			if au.mythic then
				o.img.ImageColor3 = Color3.fromHSV((t * 0.4 + i / #au.orbs) % 1, 0.6, 1)
			end
		end
		local pulse = math.sin(t * 4)
		glow.Size = UDim2.fromOffset(560 + pulse * 70, 560 + pulse * 70)
		if au.mythic then
			glow.ImageColor3 = rainbow:Lerp(WHITE, 0.35)
		end
		if au.pedestal then
			local p = 0.5 + 0.5 * math.sin(t * 3)
			au.pedestal.glow.ImageTransparency = 0.15 + 0.2 * p
			au.pedestal.ring.ImageTransparency = 0.25 + 0.35 * p
			if au.mythic then
				au.pedestal.ring.ImageColor3 = rainbow
			end
		end
	end
	-- карточка-победитель дрожит, пока заряжается
	if s.hero and (s.heroAmp or 0) > 0 then
		s.hero.card.Rotation = math.sin(t * 55) * s.heroAmp * 0.6
		s.hero.holder.Position = UDim2.new(0.5, math.sin(t * 61) * s.heroAmp, 0.4, math.cos(t * 47) * s.heroAmp * 0.6)
	end
	-- буквы MYTHIC переливаются радугой
	if s.rainbowLetters then
		for i, g in ipairs(s.rainbowLetters) do
			local h = (t * 0.5 + i * 0.07) % 1
			g.Color = ColorSequence.new(Color3.fromHSV(h, 0.55, 1), Color3.fromHSV((h + 0.12) % 1, 0.85, 1))
		end
	end

	-- карточки Mythic на ленте переливаются
	if roulRoot.Visible then
		for _, slot in ipairs(slots) do
			if slot.rainbow and slot.frame.Visible then
				slot.stroke.Color = rainbow
				slot.bar.BackgroundColor3 = rainbow
				slot.glow.ImageColor3 = rainbow
			end
		end
		-- полосы скорости
		local speed = s.speed or 0
		local k = math.clamp((speed - 600) / 2200, 0, 1)
		for _, l in ipairs(speedLines) do
			l.x -= speed * dt * l.speedMul
			if l.x < -400 then
				l.x = STRIP_W + math.random(0, 300)
				l.frame.Size = UDim2.fromOffset(math.random(120, 320), math.random(2, 3))
			end
			l.frame.Position = UDim2.new(0, l.x, l.frame.Position.Y.Scale, 0)
			l.frame.BackgroundTransparency = 1 - 0.55 * k
		end
	end
end)

---------------------------------------------------------------- шаги сцены

local function resetStage(def)
	stageScale.Scale = UIKit.fit(760, 0.55, 1)
	roulScale.Scale = roulFit()
	UIKit.setArt(chest, def.Art or "chestHero")
	chest.Size = UDim2.fromOffset(280, 280)
	chest.ImageTransparency = 0
	chest.Rotation = 0
	chest.Visible = true
	shadow.Visible = true
	shadow.BackgroundTransparency = 0.6
	rays.ImageTransparency, rays2.ImageTransparency, glow.ImageTransparency = 1, 1, 1
	rays.ImageColor3, rays2.ImageColor3, glow.ImageColor3 = WHITE, WHITE, WHITE
	UIKit.spin(rays, 20)
	UIKit.spin(rays2, -32)
	UIKit.spin(roulRays, 6)
	glow.Size = UDim2.fromOffset(380, 380)
	burst.ImageTransparency, ring.ImageTransparency = 1, 1
	unitView.Visible = false
	clearUnitView()
	rarityTitle.Visible = false
	letterRow.Visible = false
	for _, c in ipairs(letterRow:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	CR.clearCracks()
	void.Visible = false
	crackLayer.Visible = false
	skyLayer:ClearAllChildren()
	cometLayer:ClearAllChildren()
	auraBack:ClearAllChildren()
	auraFront:ClearAllChildren()
	FX.back:ClearAllChildren()
	FX.front:ClearAllChildren()
	card.Visible = false
	roulRoot.Visible = false
	roulRoot.Position = UDim2.fromScale(0.5, 0.46)
	roulGlow.ImageColor3 = WHITE
	roulGlow.ImageTransparency = 0.6
	markerGlow.ImageTransparency = 0.5
	dark.BackgroundTransparency = 1
	bgGrad.Color = DEFAULT_BG
	shakeAmp.Value = 0
	skipHolder.Visible = false
	for _, slot in ipairs(slots) do
		slot.idx = nil
		slot.frame.Visible = false
		slot.dim.BackgroundTransparency = 1
		slot.scale.Scale = 1
	end
	for _, l in ipairs(speedLines) do
		l.frame.BackgroundTransparency = 1
	end
end

-- свет вокруг сцены: level 0..1
local function setGlow(color, level)
	glow.ImageColor3 = color
	tween(glow, 0.2, { ImageTransparency = 0.45 - 0.35 * level, Size = UDim2.fromOffset(300 + 260 * level, 300 + 260 * level) })
	rays.ImageColor3 = color
	tween(rays, 0.2, { ImageTransparency = 0.75 - 0.45 * level })
	UIKit.spin(rays, 20 + 60 * level)
end

local function showResult(s)
	local def, result = s.def, s.result
	local color = rarityColor(result.rarity)
	local cfg = TowerData[result.unit] or {}

	resName.Text = string.upper(result.unit)
	resNameGrad.Color = ColorSequence.new(color:Lerp(WHITE, 0.65), color:Lerp(WHITE, 0.1))
	cardStroke.Color = INK

	newBadge.Visible = result.new == true
	dupPill.Visible = not result.new
	cashRow.Visible = false
	if result.new then
		UIKit.pop(newBadge, 2.2, 0.5)
		infoRow.Position = UDim2.fromOffset(16, 60)
	else
		dupText.Text = "DUPLICATE  x" .. tostring(result.copies or 2)
		if (result.cashback or 0) > 0 then
			UIKit.setIcon(cashIcon, CUR_ICON[result.cashbackCurrency] or "coin")
			cashValue.Value = 0
			cashText.Text = "+0"
			cashRow.Visible = true
			TweenService:Create(cashValue, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0.35),
				{ Value = result.cashback }):Play()
			UIKit.pop(cashIcon, 2, 0.6)
		end
		infoRow.Position = UDim2.fromOffset(16, cashRow.Visible and 128 or 94)
	end
	infoLine.Text = string.format('<font color="#FFE066">%s:</font> %s', cfg.Ability or "?", cfg.Description or "")
	infoIcon.Visible = UIKit.IconsReady
	infoRow.Visible = not cashRow.Visible

	local iconName, priceText = priceInfo(def)
	again.setIcon(iconName)
	again.setText("AGAIN  " .. priceText)
	again.setColor(canAfford(def) and "purple" or "grey")

	card.Visible = true
	cardScale.Scale = UIKit.fit(760, 0.55, 1) * 0.4
	TweenService:Create(cardScale, TweenInfo.new(0.4, Enum.EasingStyle.Back), { Scale = UIKit.fit(760, 0.55, 1) }):Play()
end

-- ЛЕНТА: разгон и торможение. Возвращается, когда лента стоит под выигрышем (или нажали SKIP)
local function spin(s)
	local land = WIN_INDEX * STEP + (math.random() * 2 - 1) * CARD_W * 0.42
	local dist = land - START_POS
	local t0 = os.clock()
	local lastIdx = math.floor(START_POS / STEP + 0.5)
	local lastTick = 0
	sound("Start")
	while scene == s and not s.skip do
		local u = math.min(1, (os.clock() - t0) / SPIN_TIME)
		local pos = START_POS + dist * (1 - (1 - u) ^ 3)
		s.speed = 3 * dist * (1 - u) ^ 2 / SPIN_TIME
		layoutStrip(s, pos)

		-- щелчок: под стрелку въехал новый юнит
		local idx = math.floor(pos / STEP + 0.5)
		if idx ~= lastIdx then
			lastIdx = idx
			local now = os.clock()
			if now - lastTick > 0.03 then
				lastTick = now
				sound("Tick", 0.96 + math.random() * 0.08)
			end
			markerScale.Scale = 1.35
			tween(markerScale, 0.12, { Scale = 1 })
			local item = s.items[idx]
			if item then
				local c = rarityColor(item.rarity)
				roulGlow.ImageColor3 = c
				markerGlow.ImageColor3 = c:Lerp(rgb(255, 220, 90), 0.4)
			end
		end

		-- напряжение в конце: темнеет, стрелка горит ярче
		local tension = math.clamp(1 - s.speed / 450, 0, 1)
		dark.BackgroundTransparency = 1 - 0.55 * tension
		roulGlow.ImageTransparency = 0.6 - 0.3 * tension
		markerGlow.ImageTransparency = 0.5 - 0.35 * tension

		if u >= 1 then break end
		RunService.RenderStepped:Wait()
	end
	s.speed = 0
	s.canSkip = false
	skipHolder.Visible = false
	if scene ~= s then return end

	if s.skip then
		layoutStrip(s, WIN_INDEX * STEP)
		return
	end

	-- остановка и доводка до центра карточки
	sound("Stop")
	markerScale.Scale = 1.5
	tween(markerScale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	pause(0.18)
	local v = Instance.new("NumberValue")
	v.Value = land
	v.Changed:Connect(function(p)
		if scene == s then layoutStrip(s, p) end
	end)
	TweenService:Create(v, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { Value = WIN_INDEX * STEP }):Play()
	pause(0.47)
	layoutStrip(s, WIN_INDEX * STEP)
end

-- победная карточка на ленте: остальные гаснут, она растёт и светится
local function highlightWinner(s)
	for _, slot in ipairs(slots) do
		if slot.frame.Visible and slot.idx ~= WIN_INDEX then
			tween(slot.dim, 0.3, { BackgroundTransparency = 0.45 })
		end
	end
	local w = slotAt(WIN_INDEX)
	if w then
		TweenService:Create(w.scale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1.12 }):Play()
		w.glow.ImageTransparency = 0
		local c = rarityColor(s.result.rarity)
		burstAt(roulRoot, UDim2.fromScale(0.5, 0.5), c:Lerp(WHITE, 0.4), 14, 150, 17)
	end
end

-- буквы редкости по одной: «L E G E N D A R Y»
local function slamLetters(s, word, color, delayPer)
	for _, c in ipairs(letterRow:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	letterRow.Visible = true
	rarityTitle.Visible = false
	local letters = {}
	for i = 1, #word do
		local ch = string.sub(word, i, i)
		local l = UIKit.title(letterRow, {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.new(0, 0, 1, 0),
			TextSize = 84,
			Text = ch,
			Colors = { color:Lerp(WHITE, 0.75), color },
			TextTransparency = 1,
			LayoutOrder = i,
			ZIndex = 10,
		})
		local st = l:FindFirstChildOfClass("UIStroke")
		if st then st.Transparency = 1 end
		letters[i] = l
	end
	if s.result.rarity == "Mythic" then
		s.rainbowLetters = {}
		for i, l in ipairs(letters) do
			s.rainbowLetters[i] = l:FindFirstChildOfClass("UIGradient")
		end
	end
	for i, l in ipairs(letters) do
		if scene ~= s then return end
		l.TextTransparency = 0
		local st = l:FindFirstChildOfClass("UIStroke")
		if st then st.Transparency = 0 end
		UIKit.pop(l, 2.6, 0.3)
		screenShake(6 + i, 0.18)
		if i % 2 == 1 then sound("Tick", 0.6 + i * 0.05) end
		hold(delayPer)
	end
	-- буквы прыгают волной
	for i, l in ipairs(letters) do
		task.delay(i * 0.05, function()
			if l.Parent then UIKit.pop(l, 1.35, 0.35) end
		end)
	end
end

---------------------------------------------------------------- КРАСИВЫЕ ЭФФЕКТЫ ВЫПАДЕНИЯ (вместо монет и конфетти)

FX.CENTER = UDim2.fromScale(0.5, 0.42) -- где на экране появляется юнит

FX.EDGE_FADE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.5, 0),
	NumberSequenceKeypoint.new(1, 1),
})

-- цвет частиц: у Mythic — нежная радуга, у остальных — цвет редкости с бликами
function FX.fxColor(rank, base)
	if rank >= 5 then
		return Color3.fromHSV(math.random(), 0.4, 1)
	end
	return base:Lerp(WHITE, math.random() * 0.55)
end

-- кинематографичный блик-полоса через экран
function FX.lensStreak(color, width, thickness, rotation, life)
	life = life or 0.8
	local holder = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = FX.CENTER,
		Size = UDim2.fromOffset(width, thickness),
		Rotation = rotation or 0,
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = 22,
	}, FX.front)
	new("UIGradient", { Transparency = FX.EDGE_FADE }, holder)
	local core = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.75, 0, 0.3, 0),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = 22,
	}, holder)
	new("UIGradient", { Transparency = FX.EDGE_FADE }, core)
	local sc = new("UIScale", { Scale = 0.15 }, holder)
	tween(sc, 0.2, { Scale = 1 })
	local info = TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.15)
	TweenService:Create(holder, info, { BackgroundTransparency = 1, Size = UDim2.fromOffset(width * 1.25, math.max(1, thickness * 0.3)) }):Play()
	TweenService:Create(core, info, { BackgroundTransparency = 1 }):Play()
	Debris:AddItem(holder, life + 0.25)
end

-- звёздная вспышка: искра, мягкое свечение и крест из лучей
function FX.starFlare(pos, color, size)
	local h = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = pos,
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		Rotation = math.random(0, 45),
		ZIndex = 22,
	}, FX.front)
	local sc = new("UIScale", { Scale = 0 }, h)
	UIKit.glow(h, color, UDim2.fromScale(1.7, 1.7), { ImageTransparency = 0.35, ZIndex = 22 })
	UIKit.art(h, "sparkle", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		ImageColor3 = color:Lerp(WHITE, 0.6),
		ZIndex = 22,
	})
	for _, rot in ipairs({ 0, 90 }) do
		local ln = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(2.8, 0, 0, 2),
			Rotation = rot,
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			ZIndex = 22,
		}, h)
		new("UIGradient", { Transparency = FX.EDGE_FADE }, ln)
	end
	TweenService:Create(sc, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	TweenService:Create(h, TweenInfo.new(0.9), { Rotation = h.Rotation + 90 }):Play()
	task.delay(0.45, function()
		if h.Parent then tween(sc, 0.4, { Scale = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In) end
	end)
	Debris:AddItem(h, 1)
end

-- ударная волна от юнита
function FX.shockRing(color, delay, maxSize)
	task.delay(delay or 0, function()
		local r = UIKit.art(FX.front, "ring", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = FX.CENTER,
			Size = UDim2.fromOffset(80, 80),
			ImageColor3 = color,
			ZIndex = 22,
		})
		tween(r, 0.75, { Size = UDim2.fromOffset(maxSize or 1000, maxSize or 1000), ImageTransparency = 1 })
		Debris:AddItem(r, 0.8)
	end)
end

-- мягкий огонёк, плывёт вверх и гаснет (боке)
function FX.bokeh(color, front)
	local layer = front and FX.front or FX.back
	local size = math.random(18, front and 46 or 110)
	local x, y = math.random(), 0.15 + math.random() * 0.8
	local orb = UIKit.glow(layer, color, size, { Position = UDim2.fromScale(x, y), ImageTransparency = 1, ZIndex = layer.ZIndex })
	local life = 2.8 + math.random() * 2.2
	local peak = front and (0.35 + math.random() * 0.3) or (0.45 + math.random() * 0.35)
	TweenService:Create(orb, TweenInfo.new(life, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
		Position = UDim2.fromScale(x + (math.random() - 0.5) * 0.06, y - 0.08 - math.random() * 0.1),
	}):Play()
	tween(orb, life * 0.4, { ImageTransparency = peak }, Enum.EasingStyle.Sine)
	task.delay(life * 0.55, function()
		if orb.Parent then tween(orb, life * 0.45, { ImageTransparency = 1 }, Enum.EasingStyle.Sine) end
	end)
	Debris:AddItem(orb, life + 0.1)
end

-- мерцающие блёстки падают сверху
function FX.glitter(color)
	local x = math.random()
	local size = math.random(6, 15)
	local g = UIKit.art(FX.front, "sparkle", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(x, 0, 0, -20),
		Size = UDim2.fromOffset(size, size),
		ImageColor3 = color,
		Rotation = math.random(0, 90),
		ZIndex = 22,
	})
	local life = 2.4 + math.random() * 1.8
	TweenService:Create(g, TweenInfo.new(life, Enum.EasingStyle.Linear), {
		Position = UDim2.new(x + (math.random() - 0.5) * 0.12, 0, 1.05, 0),
		Rotation = g.Rotation + math.random(-360, 360),
	}):Play()
	TweenService:Create(g, TweenInfo.new(0.25 + math.random() * 0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { ImageTransparency = 0.7 }):Play()
	Debris:AddItem(g, life + 0.1)
end

-- лепестки света медленно кружатся вниз (Mythic)
function FX.petal()
	local x = math.random()
	local w = math.random(10, 18)
	local p = UIKit.glow(FX.front, Color3.fromHSV(math.random(), 0.22, 1), UDim2.fromOffset(w, w * 2.6), {
		Position = UDim2.new(x, 0, 0, -40),
		Rotation = math.random(-40, 40),
		ImageTransparency = 0.12,
		ZIndex = 22,
	})
	local life = 3.5 + math.random() * 2
	TweenService:Create(p, TweenInfo.new(life, Enum.EasingStyle.Linear), {
		Position = UDim2.new(x + (math.random() - 0.5) * 0.25, 0, 1.08, 0),
	}):Play()
	TweenService:Create(p, TweenInfo.new(0.8 + math.random() * 0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Rotation = p.Rotation + 60 }):Play()
	Debris:AddItem(p, life + 0.1)
end

-- золотые угольки поднимаются из воронки (Legendary)
function FX.ember()
	local x = 0.5 + (math.random() - 0.5) * 0.5
	local size = math.random(5, 12)
	local e = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(x, 0.92),
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = rgb(255, 180 + math.random(0, 60), 70),
		BorderSizePixel = 0,
		ZIndex = 22,
	}, FX.front)
	corner(e, size)
	local life = 1.8 + math.random() * 1.4
	TweenService:Create(e, TweenInfo.new(life, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		Position = UDim2.fromScale(x + (math.random() - 0.5) * 0.12, 0.25 + math.random() * 0.3),
		Size = UDim2.fromOffset(2, 2),
		BackgroundTransparency = 1,
	}):Play()
	Debris:AddItem(e, life + 0.1)
end

-- частицы слетаются к центру (зарядка перед вспышкой)
function FX.converge(color, count, time)
	local W, H = bg.AbsoluteSize.X, bg.AbsoluteSize.Y
	local cx, cy = W * 0.5, H * 0.42
	if not effectsOn() then count = math.floor(count / 2) end
	for _ = 1, count do
		local a = math.random() * math.pi * 2
		local r = 260 + math.random() * 320
		local size = math.random(12, 26)
		local p = UIKit.art(FX.front, "sparkle", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(cx + math.cos(a) * r, cy + math.sin(a) * r),
			Size = UDim2.fromOffset(size, size),
			ImageColor3 = color:Lerp(WHITE, math.random() * 0.4),
			ImageTransparency = 1,
			ZIndex = 22,
		})
		local delay = math.random() * time * 0.5
		TweenService:Create(p, TweenInfo.new(time - delay, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, delay), {
			Position = UDim2.fromOffset(cx, cy),
			ImageTransparency = 0,
			Size = UDim2.fromOffset(size * 0.4, size * 0.4),
		}):Play()
		Debris:AddItem(p, time + 0.05)
	end
end

-- белое свечение при каждом треске (Mythic)
function FX.crackBloom(cx, cy, size)
	local b = UIKit.art(crackLayer, "glow", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(cx, cy),
		Size = UDim2.fromOffset(size * 0.3, size * 0.3),
		ImageTransparency = 0,
		ZIndex = 29,
	})
	tween(b, 0.5, { Size = UDim2.fromOffset(size, size), ImageTransparency = 1 })
	Debris:AddItem(b, 0.55)
	flashScreen(WHITE, 0.82, 0.3)
end

-- божественный столб света сверху на юнита (Mythic)
function FX.divinePillar()
	local beam = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0.6, 0),
		Size = UDim2.fromOffset(0, 1500),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = 7,
	}, auraBack)
	new("UIGradient", { Transparency = FX.EDGE_FADE }, beam)
	local core = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.25, 1),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = 7,
	}, beam)
	new("UIGradient", { Transparency = FX.EDGE_FADE }, core)
	tween(beam, 0.25, { Size = UDim2.fromOffset(280, 1500) })
	task.delay(0.6, function()
		if beam.Parent then
			tween(beam, 1.6, { Size = UDim2.fromOffset(120, 1500), BackgroundTransparency = 0.75 }, Enum.EasingStyle.Sine)
			tween(core, 1.6, { BackgroundTransparency = 0.6 }, Enum.EasingStyle.Sine)
		end
	end)
	return beam
end

-- подсветка «пьедестала» под юнитом
function FX.pedestal(color)
	local glowE = UIKit.glow(auraBack, color, UDim2.fromOffset(440, 110), {
		Position = UDim2.fromScale(0.5, 0.84),
		ImageTransparency = 0.2,
		ZIndex = 7,
	})
	local ringE = UIKit.art(auraBack, "ring", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.84),
		Size = UDim2.fromOffset(380, 92),
		ImageColor3 = color:Lerp(WHITE, 0.4),
		ImageTransparency = 0.35,
		ZIndex = 7,
	})
	return { glow = glowE, ring = ringE }
end

-- карточка-победитель вылетает из ленты к центру экрана
function FX.heroCard(s)
	local item = s.items[WIN_INDEX]
	local c = rarityColor(item.rarity)
	local holder = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = roulRoot.Position,
		Size = UDim2.fromOffset(CARD_W, CARD_H),
		BackgroundTransparency = 1,
		ZIndex = 20,
	}, shakeRoot)
	local sc = new("UIScale", { Scale = roulFit() * 1.12 }, holder)
	local hRays = UIKit.rays(holder, c:Lerp(WHITE, 0.35), 460, 45, { ImageTransparency = 1, ZIndex = 20 })
	local hGlow = UIKit.glow(holder, c, 300, { ImageTransparency = 0.45, ZIndex = 20 })
	local card = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = 21,
	}, holder)
	corner(card, 14)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(rgb(46, 36, 92):Lerp(c, 0.12), c:Lerp(rgb(14, 8, 34), 0.4)) }, card)
	stroke(card, c:Lerp(WHITE, 0.3), 4)
	local vp = new("ViewportFrame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.new(1, -10, 0, 124),
		BackgroundTransparency = 1,
		Ambient = rgb(200, 200, 215),
		LightColor = WHITE,
		LightDirection = Vector3.new(-0.4, -1, -0.6),
		ZIndex = 22,
	}, card)
	local world = Instance.new("WorldModel")
	world.Parent = vp
	local cam = Instance.new("Camera")
	cam.FieldOfView = 40
	cam.Parent = vp
	vp.CurrentCamera = cam
	local cf = camFor(item.unit)
	if cf then cam.CFrame = cf end
	local model = cloneUnit(item.unit)
	if model then model.Parent = world end
	local nameL = text(card, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -15),
		Size = UDim2.new(1, -10, 0, 24),
		Font = UIKit.Font.Title,
		TextSize = 18,
		TextScaled = true,
		Text = string.upper(item.unit),
		ZIndex = 23,
	})
	new("UITextSizeConstraint", { MaxTextSize = 18 }, nameL)
	local bar = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -5),
		Size = UDim2.new(1, -14, 0, 8),
		BackgroundColor3 = c,
		BorderSizePixel = 0,
		ZIndex = 23,
	}, card)
	corner(bar, 4)
	return { holder = holder, scale = sc, rays = hRays, glow = hGlow, card = card, color = c }
end

-- фон эффектов, пока виден выигрыш: боке, блёстки, лепестки, угольки, искры вокруг, волны, молнии
-- числа — раз в сколько секунд появляется частица (0 — нет)
FX.AMBIENT = {
	[1] = { bokeh = 0.35, glitter = 0, petals = 0, embers = 0, rise = 0, orbs = 0, ring = 0, arc = 0 },
	[2] = { bokeh = 0.22, glitter = 0.22, petals = 0, embers = 0, rise = 0, orbs = 0, ring = 1.4, arc = 0 },
	[3] = { bokeh = 0.16, glitter = 0.12, petals = 0, embers = 0, rise = 0.14, orbs = 4, ring = 1, arc = 0.55 },
	[4] = { bokeh = 0.12, glitter = 0.09, petals = 0, embers = 0.06, rise = 0.09, orbs = 6, ring = 0.8, arc = 0 },
	[5] = { bokeh = 0.08, glitter = 0.06, petals = 0.12, embers = 0, rise = 0.05, orbs = 10, ring = 0.55, arc = 0.16 },
}

function FX.startAmbient(s, rank, color)
	local cfg = FX.AMBIENT[rank] or FX.AMBIENT[1]
	local mythic = rank >= 5
	local aura = { mythic = mythic, orbs = {}, color = color }
	s.aura = aura
	for i = 1, cfg.orbs do
		local o = UIKit.art(auraFront, "sparkle", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(26, 26),
			ImageColor3 = mythic and WHITE or color:Lerp(WHITE, 0.4),
			ZIndex = 9,
		})
		table.insert(aura.orbs, { img = o, phase = i / cfg.orbs * math.pi * 2, speed = 1.3 + math.random() * 0.9, r = 165 + math.random() * 70, front = true })
	end
	aura.pedestal = FX.pedestal(mythic and WHITE or color)

	task.spawn(function()
		local timers = {}
		for k in pairs(cfg) do timers[k] = math.random() * 0.2 end
		local slow = effectsOn() and 1 or 2.5
		local function due(key, dt)
			local every = cfg[key]
			if every <= 0 then return false end
			timers[key] += dt
			if timers[key] >= every * slow then
				timers[key] = 0
				return true
			end
			return false
		end
		while scene == s and s.aura == aura do
			local dt = RunService.RenderStepped:Wait()
			if scene ~= s or s.aura ~= aura then break end
			if due("bokeh", dt) then
				FX.bokeh(FX.fxColor(rank, color), math.random() < 0.3)
			end
			if due("glitter", dt) then
				FX.glitter(FX.fxColor(rank, color))
			end
			if due("petals", dt) then
				FX.petal()
			end
			if due("embers", dt) then
				FX.ember()
			end
			if due("ring", dt) then
				local r = UIKit.art(auraBack, "ring", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.52),
					Size = UDim2.fromOffset(140, 140),
					ImageColor3 = FX.fxColor(rank, color),
					ImageTransparency = 0.2,
					ZIndex = 7,
				})
				tween(r, 0.9, { Size = UDim2.fromOffset(720, 720), ImageTransparency = 1 })
				Debris:AddItem(r, 0.95)
			end
			if effectsOn() and due("arc", dt) then
				CR.auraArc(mythic and Color3.fromHSV(math.random(), 0.6, 1) or color:Lerp(WHITE, 0.3))
			end
			if due("rise", dt) then
				local size = math.random(14, 30)
				local x = 300 + math.random(-170, 170)
				local sp = UIKit.art(auraFront, "sparkle", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromOffset(x, 470),
					Size = UDim2.fromOffset(size, size),
					ImageColor3 = FX.fxColor(rank, color),
					ZIndex = 9,
				})
				local life = 0.9 + math.random() * 0.6
				TweenService:Create(sp, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Position = UDim2.fromOffset(x + math.random(-40, 40), 120 + math.random(-40, 40)),
					ImageTransparency = 1,
					Rotation = math.random(-180, 180),
				}):Play()
				Debris:AddItem(sp, life + 0.05)
			end
		end
	end)
end

---------------------------------------------------------------- MYTHIC: темнота → трещины → стекло разлетается

local function mythicIntro(s, quick)
	local W, H = crackLayer.AbsoluteSize.X, crackLayer.AbsoluteSize.Y
	local cx, cy = W * 0.5, H * 0.43
	local R = math.max(W, H) * 0.62
	local full = effectsOn()

	-- 1. ПОЛНАЯ ТЕМНОТА И ТИШИНА
	void.BackgroundTransparency = 0
	void.Visible = true
	crackLayer.Visible = true
	roulRoot.Visible = false
	chest.Visible = false
	shadow.Visible = false
	-- под темнотой уже горит белый свет — он пробьётся сквозь трещины
	setGlow(WHITE, 1)
	rays.ImageTransparency = 0.1
	rays2.ImageTransparency = 0.4
	rays2.ImageColor3 = WHITE

	-- трещины строятся заранее, пока экран чёрный (их ещё не видно)
	local hue0 = math.random()
	local web = CR.crackWeb(cx, cy, R, full and 9 or 6, hue0, full)
	CR.setTargets(web.radials, 0)
	-- ещё два удара сбоку (готовятся тоже в темноте, чтобы потом не было подвисаний)
	local extra = {}
	if full and not quick then
		extra[1] = CR.crackWeb(W * (0.16 + math.random() * 0.1), H * (0.22 + math.random() * 0.15), R * 0.42, 5, hue0 + 0.33, true, 2)
		extra[2] = CR.crackWeb(W * (0.74 + math.random() * 0.1), H * (0.62 + math.random() * 0.15), R * 0.42, 5, hue0 + 0.66, true, 2)
		CR.setTargets(extra[1].radials, 0)
		CR.setTargets(extra[2].radials, 0)
	end
	local coreGlow = UIKit.art(crackLayer, "glow", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(cx, cy),
		Size = UDim2.fromOffset(30, 30),
		ImageTransparency = 0.05,
		Visible = false,
		ZIndex = 29,
	})
	local coreRays = UIKit.rays(crackLayer, WHITE, 420, 35, {
		Position = UDim2.fromOffset(cx, cy),
		ImageTransparency = 1,
		ZIndex = 29,
	})
	s.crackGlow = coreGlow
	s.crackRays = coreRays
	hold(quick and 0.15 or 1.1)
	if scene ~= s then return end

	if quick then
		-- с пропуском: трещины появляются сразу
		for _, line in ipairs(CR.cracks) do
			line.target = 1
			line.speed = 100000
		end
		coreGlow.Visible = true
		coreGlow.Size = UDim2.fromOffset(240, 240)
		sound("Crack")
		FX.crackBloom(cx, cy, 800)
		screenShake(12, 0.25)
		hold(0.35)
	else
		-- 2. первая трещина
		coreGlow.Visible = true
		tween(coreGlow, 0.3, { Size = UDim2.fromOffset(130, 130) })
		CR.setTargets(web.radials, 0.2)
		sound("Crack", 1.1)
		FX.crackBloom(cx, cy, 380)
		screenShake(6, 0.2)
		CR.glassDust(6)
		hold(0.75)
		if scene ~= s then return end

		-- 3. трещины расползаются
		CR.setTargets(web.radials, 0.5)
		sound("Crack", 0.95)
		FX.crackBloom(cx, cy, 620)
		sound("Tick", 0.5)
		screenShake(11, 0.3)
		CR.glassDust(12)
		tween(coreGlow, 0.4, { Size = UDim2.fromOffset(260, 260) })
		tween(coreRays, 0.6, { ImageTransparency = 0.65 })
		hold(0.65)
		if scene ~= s then return end

		-- 4. до краёв экрана + новые удары
		CR.setTargets(web.radials, 1)
		sound("Crack", 0.85)
		FX.crackBloom(cx, cy, 900)
		screenShake(16, 0.4)
		CR.glassDust(18)
		if extra[1] then
			CR.setTargets(extra[1].radials, 1)
			FX.crackBloom(extra[1].cx, extra[1].cy, 460)
			task.delay(0.28, function()
				if scene ~= s or not extra[2] then return end
				CR.setTargets(extra[2].radials, 1)
				sound("Crack", 1.2)
				FX.crackBloom(extra[2].cx, extra[2].cy, 460)
				screenShake(14, 0.3)
			end)
		end
		tween(coreRays, 0.8, { ImageTransparency = 0.35, Size = UDim2.fromOffset(700, 700) })
		hold(0.95)
		if scene ~= s then return end

		-- 5. свет рвётся наружу: экран мерцает, всё трясётся сильнее
		for i = 1, 3 do
			void.BackgroundTransparency = 0.25 + i * 0.1
			tween(void, 0.18, { BackgroundTransparency = 0 })
			sound("Stop", 0.45 + i * 0.15)
			FX.crackBloom(cx, cy, 700 + i * 220)
			screenShake(10 + i * 7, 0.3)
			coreGlow.Size = UDim2.fromOffset(260 + i * 90, 260 + i * 90)
			CR.glassDust(8)
			hold(0.26)
		end
		screenShake(24, 0.5)
		tween(coreGlow, 0.35, { Size = UDim2.fromOffset(900, 900), ImageTransparency = 0 })
		hold(0.35)
	end
	if scene ~= s then return end

	-- 6. РАЗБИТИЕ
	flashScreen(WHITE, 0, quick and 0.4 or 0.7)
	s.crackGlow = nil
	s.crackRays = nil
	CR.clearCracks()
	void.Visible = false
	CR.shatter(cx, cy)
	if SOUNDS.Shatter.Id ~= "" then
		sound("Shatter")
	else
		sound("Crack", 1.5)
	end
	sound("Boom", 0.6)
	screenShake(45, 0.9)
end

---------------------------------------------------------------- LEGENDARY: падает комета

local function cometImpact(tx, ty)
	local pos = UDim2.fromOffset(tx, ty)
	local H = bg.AbsoluteSize.Y
	local fx = effectsOn()
	flashScreen(rgb(255, 235, 190), 0, 0.6)
	sound("Boom", 0.5)
	sound("Stop", 0.4)
	screenShake(42, 0.9)

	-- ударные волны
	for i = 1, 3 do
		task.delay((i - 1) * 0.08, function()
			local r = UIKit.art(cometLayer, "ring", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = pos,
				Size = UDim2.fromOffset(60, 60),
				ImageColor3 = i == 1 and WHITE or rgb(255, 190, 80),
				ZIndex = 24,
			})
			tween(r, 0.7 + i * 0.1, { Size = UDim2.fromOffset(900 + i * 300, 900 + i * 300), ImageTransparency = 1 })
			Debris:AddItem(r, 1.2)
		end)
	end
	local b = UIKit.art(cometLayer, "burst", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = pos,
		Size = UDim2.fromOffset(120, 120),
		ImageColor3 = rgb(255, 215, 130),
		ZIndex = 24,
	})
	tween(b, 0.6, { Size = UDim2.fromOffset(1100, 1100), ImageTransparency = 1 })
	Debris:AddItem(b, 0.65)

	-- облако пыли
	for _ = 1, (fx and 12 or 5) do
		local a = math.random() * math.pi * 2
		local d = UIKit.glow(cometLayer, rgb(150, 100, 70), 160, { Position = pos, ImageTransparency = 0.25, ZIndex = 23 })
		local dist = 120 + math.random() * 240
		local life = 1 + math.random() * 0.6
		TweenService:Create(d, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(tx + math.cos(a) * dist, ty + math.sin(a) * dist * 0.5),
			Size = UDim2.fromOffset(360, 360),
			ImageTransparency = 1,
		}):Play()
		Debris:AddItem(d, life + 0.1)
	end

	-- раскалённые обломки летят вверх и падают
	for _ = 1, (fx and 18 or 8) do
		local a = -math.pi * (0.08 + math.random() * 0.84)
		local rock = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = pos,
			Size = UDim2.fromOffset(math.random(8, 22), math.random(8, 20)),
			Rotation = math.random(0, 90),
			BackgroundColor3 = rgb(70, 45, 30),
			BorderSizePixel = 0,
			ZIndex = 24,
		}, cometLayer)
		corner(rock, 3)
		stroke(rock, rgb(255, 140, 40), 2, 0.1)
		local dist = 200 + math.random() * 380
		local px, py = tx + math.cos(a) * dist, ty + math.sin(a) * dist
		local up = 0.35 + math.random() * 0.2
		TweenService:Create(rock, TweenInfo.new(up, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(px, py),
			Rotation = rock.Rotation + math.random(-200, 200),
		}):Play()
		task.delay(up, function()
			if rock.Parent then
				TweenService:Create(rock, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					Position = UDim2.fromOffset(px + math.random(-40, 40), py + 420),
					Rotation = rock.Rotation + math.random(-200, 200),
					BackgroundTransparency = 1,
				}):Play()
			end
		end)
		Debris:AddItem(rock, up + 0.7)
	end
	burstAt(cometLayer, pos, rgb(255, 170, 60), fx and 26 or 10, 420, 24)

	-- светящаяся воронка
	local crater = UIKit.glow(cometLayer, rgb(255, 120, 30), UDim2.fromOffset(340, 170), {
		Position = UDim2.fromOffset(tx, ty + 50),
		ImageTransparency = 0.05,
		ZIndex = 23,
	})
	tween(crater, 2.2, { ImageTransparency = 1, Size = UDim2.fromOffset(460, 200) })
	Debris:AddItem(crater, 2.3)

	-- столб света из воронки
	local pillar = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromOffset(tx, ty + 60),
		Size = UDim2.fromOffset(10, H * 1.4),
		BackgroundColor3 = rgb(255, 230, 150),
		BorderSizePixel = 0,
		ZIndex = 23,
	}, cometLayer)
	new("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, pillar)
	tween(pillar, 0.18, { Size = UDim2.fromOffset(200, H * 1.4) })
	task.delay(0.25, function()
		if pillar.Parent then
			tween(pillar, 0.9, { Size = UDim2.fromOffset(40, H * 1.4), BackgroundTransparency = 1 })
		end
	end)
	Debris:AddItem(pillar, 1.3)
end

local function legendaryIntro(s, quick)
	local W, H = bg.AbsoluteSize.X, bg.AbsoluteSize.Y
	local tx, ty = W * 0.5, H * 0.43
	local sx, sy = W * 1.08, -H * 0.12
	local fx = effectsOn()

	-- лента уезжает
	tween(roulScale, 0.2, { Scale = roulFit() * 0.2 })
	hold(0.2)
	roulRoot.Visible = false
	chest.Visible = false
	shadow.Visible = false

	-- 1. ночное небо со звёздами
	bgGrad.Color = ColorSequence.new(rgb(10, 12, 38), rgb(2, 2, 10))
	tween(dark, 0.3, { BackgroundTransparency = 0.3 })
	for _ = 1, (fx and 45 or 15) do
		local size = math.random(6, 16)
		local star = UIKit.art(skyLayer, "sparkle", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(math.random(), math.random() * 0.8),
			Size = UDim2.fromOffset(size, size),
			ImageColor3 = rgb(220, 230, 255),
			ImageTransparency = 1,
			ZIndex = 2,
		})
		TweenService:Create(star, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, math.random() * 0.4),
			{ ImageTransparency = 0.15 + math.random() * 0.5 }):Play()
	end
	if not quick then
		sound("Stop", 0.35)
		screenShake(4, 0.6)
		hold(0.6)
		if scene ~= s then return end
	end

	-- 2. КОМЕТА
	local head = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(sx, sy),
		Size = UDim2.fromOffset(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 24,
	}, cometLayer)
	local headScale = new("UIScale", {}, head)
	UIKit.glow(head, rgb(255, 120, 30), 320, { ImageTransparency = 0.3, ZIndex = 24 })
	UIKit.glow(head, rgb(255, 200, 80), 160, { ImageTransparency = 0.05, ZIndex = 24 })
	UIKit.glow(head, WHITE, 80, { ImageTransparency = 0, ZIndex = 24 })
	local flare = UIKit.art(head, "sparkle", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(170, 170),
		ImageColor3 = rgb(255, 245, 210),
		ZIndex = 24,
	})
	UIKit.spin(flare, 200)
	-- небо освещается кометой
	local skyGlow = UIKit.glow(skyLayer, rgb(255, 140, 50), 900, { Position = UDim2.fromOffset(sx, sy), ImageTransparency = 1, ZIndex = 2 })

	sound("Comet")
	local dur = quick and 0.5 or 1.4
	local dirX, dirY = tx - sx, ty - sy
	local dl = math.max(1, math.sqrt(dirX * dirX + dirY * dirY))
	dirX, dirY = dirX / dl, dirY / dl
	local t0 = os.clock()
	while scene == s do
		local u = math.min(1, (os.clock() - t0) / dur)
		local e = u * u
		local x, y = sx + (tx - sx) * e, sy + (ty - sy) * e
		local k = 0.3 + 1.1 * e
		head.Position = UDim2.fromOffset(x, y)
		headScale.Scale = k
		-- огненный хвост
		for _ = 1, (fx and 2 or 1) do
			local p = UIKit.glow(cometLayer, rgb(255, 215, 130), UDim2.fromOffset(120 * k, 120 * k), {
				Position = UDim2.fromOffset(x + (math.random() - 0.5) * 14 * k, y + (math.random() - 0.5) * 14 * k),
				ImageTransparency = 0.15,
				ZIndex = 23,
			})
			local life = 0.35 + math.random() * 0.25
			TweenService:Create(p, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = UDim2.fromOffset(40 * k, 40 * k),
				ImageTransparency = 1,
				ImageColor3 = rgb(200, 50, 20),
			}):Play()
			Debris:AddItem(p, life + 0.05)
		end
		-- искры отлетают назад
		if math.random() < 0.7 then
			local size = math.random(10, 22) * k
			local sp = UIKit.art(cometLayer, "sparkle", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(x, y),
				Size = UDim2.fromOffset(size, size),
				ImageColor3 = rgb(255, 220, 140),
				ZIndex = 23,
			})
			local back = 60 + math.random() * 140
			local side = (math.random() - 0.5) * 120
			TweenService:Create(sp, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = UDim2.fromOffset(x - dirX * back - dirY * side, y - dirY * back + dirX * side),
				ImageTransparency = 1,
			}):Play()
			Debris:AddItem(sp, 0.5)
		end
		skyGlow.Position = UDim2.fromOffset(x, y)
		skyGlow.ImageTransparency = 1 - 0.55 * e
		screenShake(1 + 8 * e, 0.15)
		if u >= 1 then break end
		RunService.RenderStepped:Wait()
	end
	head:Destroy()
	if scene ~= s then return end

	-- 3. УДАР
	cometImpact(tx, ty)
	tween(skyGlow, 0.8, { ImageTransparency = 1 })
	tween(dark, 0.6, { BackgroundTransparency = 1 })
end


-- ПРАЗДНИК по редкости
local function celebrate(s)
	local LETTER_DELAY = { 0.035, 0.045, 0.055, 0.07, 0.11 }
	local FLARES = { 0, 3, 5, 7, 12 }
	local result = s.result
	local color = rarityColor(result.rarity)
	local rank = RANK[result.rarity] or 1
	local quick = s.skip or s.quick
	local fxOn = effectsOn()

	-- 1. победная карточка на ленте
	if roulRoot.Visible then
		highlightWinner(s)
		hold(quick and 0.25 or (rank >= 4 and 0.6 or 0.4))
	end
	if scene ~= s then return end

	-- 2. Mythic — темнота и трещины, Legendary — комета, остальные — карточка вылетает к игроку и заряжается
	if rank >= 5 then
		mythicIntro(s, quick)
	elseif rank == 4 then
		legendaryIntro(s, quick)
	elseif roulRoot.Visible and not quick then
		local hero = FX.heroCard(s)
		s.hero = hero
		s.heroAmp = 0
		tween(roulScale, 0.2, { Scale = roulFit() * 0.85 })
		task.delay(0.15, function()
			if scene == s then roulRoot.Visible = false end
		end)
		TweenService:Create(hero.holder, TweenInfo.new(0.45, Enum.EasingStyle.Back), { Position = UDim2.fromScale(0.5, 0.4) }):Play()
		TweenService:Create(hero.scale, TweenInfo.new(0.45, Enum.EasingStyle.Back), { Scale = UIKit.fit(760, 0.55, 1) * 1.75 }):Play()
		tween(hero.rays, 0.4, { ImageTransparency = 0.4 })
		sound("Start", 1.3)
		hold(0.5)
		if rank >= 2 then
			-- зарядка: частицы слетаются, карточка дрожит и разгорается
			local ct = rank == 2 and 0.55 or 0.85
			FX.converge(color, rank == 2 and 16 or 30, ct)
			tween(hero.glow, ct, { Size = UDim2.fromOffset(560, 560), ImageTransparency = 0.1 })
			tween(hero.rays, ct, { ImageTransparency = 0.1 })
			UIKit.spin(hero.rays, 120)
			local steps = math.max(1, math.floor(ct / 0.07))
			for i = 1, steps do
				if scene ~= s then return end
				s.heroAmp = 2 + 8 * i / steps
				if i % 2 == 0 then sound("Tick", 0.8 + i * 0.07) end
				if rank >= 3 and fxOn and i % 3 == 0 then CR.auraArc(color:Lerp(WHITE, 0.3)) end
				hold(0.07)
			end
		else
			hold(0.1)
		end
		s.heroAmp = 0
	end
	if scene ~= s then return end

	-- 3. РАСКРЫТИЕ: вспышка, волны, блики, лучи
	if s.hero then
		s.hero.holder:Destroy()
		s.hero = nil
	end
	roulRoot.Visible = false
	tween(dark, 0.4, { BackgroundTransparency = 1 })
	chest.Visible = false
	shadow.Visible = false
	sound("Boom")
	sound(rank >= 4 and "BigWin" or "Win")
	setGlow(rank >= 5 and WHITE or color, 1)
	if rank >= 5 then
		s.rainbow = true -- тёмный переливающийся фон
	else
		bgGrad.Color = ColorSequence.new(color:Lerp(rgb(30, 12, 80), 0.55), rgb(8, 3, 26))
	end
	if rank < 4 then
		flashScreen(color:Lerp(WHITE, 0.6), rank >= 3 and 0 or 0.2, 0.6) -- у Legendary / Mythic вспышка уже была
	end
	-- звёзды кометы гаснут
	for _, star in ipairs(skyLayer:GetChildren()) do
		if star:IsA("ImageLabel") then
			tween(star, 1.2, { ImageTransparency = 1 })
		end
	end
	burst.ImageColor3 = color:Lerp(WHITE, 0.3)
	burst.Size = UDim2.fromOffset(120, 120)
	burst.ImageTransparency = 0
	tween(burst, 0.7, { Size = UDim2.fromOffset(900, 900), ImageTransparency = 1 })
	ring.ImageColor3 = color:Lerp(WHITE, 0.5)
	ring.Size = UDim2.fromOffset(120, 120)
	ring.ImageTransparency = 0
	tween(ring, 0.6, { Size = UDim2.fromOffset(1000, 1000), ImageTransparency = 1 })
	rays.ImageTransparency = 0.1
	rays2.ImageTransparency = 0.45
	rays2.ImageColor3 = (rank >= 5 and WHITE or color):Lerp(WHITE, 0.5)
	UIKit.spin(rays, 30 + rank * 8)
	for i = 1, math.min(rank, 4) do
		FX.shockRing(rank >= 5 and Color3.fromHSV((i * 0.27) % 1, 0.45, 1) or color:Lerp(WHITE, 0.4), (i - 1) * 0.09, 800 + i * 220)
	end
	if rank >= 2 then
		FX.lensStreak(color:Lerp(WHITE, 0.5), 1300 + rank * 150, 6 + rank * 2, 0, 0.7 + rank * 0.1)
	end
	if rank >= 4 then
		FX.lensStreak(rank >= 5 and WHITE or color:Lerp(WHITE, 0.4), 900, 8, 90, 0.8)
	end
	if rank >= 5 then
		FX.lensStreak(Color3.fromHSV(math.random(), 0.5, 1), 1800, 4, 0, 1.1)
		FX.divinePillar()
	end
	sparkBurst((rank >= 5 and WHITE or color):Lerp(WHITE, 0.4), (fxOn and 20 or 8) + rank * 6, 420)
	screenShake(6 + rank * 5, 0.5)
	-- звёздные вспышки вокруг
	local flares = FLARES[rank] or 0
	if not fxOn then flares = math.floor(flares / 2) end
	if flares > 0 then
		task.spawn(function()
			for _ = 1, flares do
				if scene ~= s then return end
				local a = math.random() * math.pi * 2
				local r = 0.12 + math.random() * 0.22
				FX.starFlare(UDim2.fromScale(0.5 + math.cos(a) * r, 0.42 + math.sin(a) * r * 1.2), FX.fxColor(rank, color), math.random(50, 110))
				task.wait(rank >= 5 and 0.12 or 0.18)
			end
		end)
	end

	-- 4. юнит появляется в лучах, вокруг — живые эффекты
	local waited = 0
	while not s.ready and waited < 2 do
		waited += task.wait()
	end
	if s.prepared and scene == s then
		s.unit = s.prepared
		s.unitBorn = os.clock()
		unitView.Visible = true
		unitScale.Scale = 0
		TweenService:Create(unitScale, TweenInfo.new(0.55, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end
	if scene == s then
		FX.startAmbient(s, rank, color)
	end

	-- 5. название редкости — буквы падают по одной
	local word = string.upper(result.rarity) .. "!"
	if quick then
		rarityTitle.Text = word
		rarityGrad.Color = ColorSequence.new(color:Lerp(WHITE, 0.7), color)
		rarityTitle.Visible = true
		UIKit.pop(rarityTitle, 2.4, 0.5)
	else
		slamLetters(s, word, rank >= 5 and WHITE or color, LETTER_DELAY[rank] or 0.05)
	end
	hold(quick and 0.3 or (rank >= 4 and 0.6 or 0.4))
	if scene == s then
		showResult(s)
	end
end

local function playOpening(caseId, def, result)
	overlay.Enabled = true
	fade.BackgroundTransparency = 0

	local s = {
		caseId = caseId, def = def, result = result,
		skip = false, canSkip = false, chestY = 0, speed = 0,
		quick = instantOpen and hasPass(),
	}
	scene = s
	resetStage(def)
	tween(fade, 0.3, { BackgroundTransparency = 1 })

	-- 3D-юнит для финала готовится заранее
	task.spawn(function()
		s.prepared = buildUnit(result.unit)
		s.ready = true
	end)

	-- лента: случайные юниты по шансам сундука, на WIN_INDEX — выигрыш
	s.items = {}
	for i = 0, LAST_INDEX do
		s.items[i] = randomItem(def) or { unit = result.unit, rarity = result.rarity }
	end
	s.items[WIN_INDEX] = { unit = result.unit, rarity = result.rarity }

	if s.quick then
		-- Instant Open включён: сразу праздник
		chest.Visible = false
		shadow.Visible = false
		celebrate(s)
		return
	end

	-- кнопка SKIP видна всё время прокрутки
	refreshSkip()
	s.canSkip = true
	skipHolder.Visible = true
	skipScale.Scale = 0.3
	TweenService:Create(skipScale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()

	-- 1. сундук прилетает сверху и подпрыгивает
	local drop = Instance.new("NumberValue")
	drop.Value = -520
	drop.Changed:Connect(function(v) s.chestY = v end)
	s.chestY = -520
	TweenService:Create(drop, TweenInfo.new(0.7, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), { Value = 0 }):Play()
	shadow.Size = UDim2.fromOffset(60, 12)
	tween(shadow, 0.7, { Size = UDim2.fromOffset(220, 40) }, Enum.EasingStyle.Bounce)

	-- пока сундук падает — готовим модели и первые карточки ленты (понемногу за кадр, без подвисаний)
	caseTitle.Text = string.upper(def.Name or "")
	fillOdds(def)
	task.spawn(warmModels, s.items)
	local half = STRIP_W / 2 + STEP
	local n = 0
	for idx = math.max(0, math.floor((START_POS - half) / STEP)), math.ceil((START_POS + half) / STEP) do
		local item = s.items[idx]
		if item then
			local slot = slots[idx % POOL + 1]
			slot.idx = idx
			paintSlot(slot, item)
			n += 1
			if n % 2 == 0 then RunService.Heartbeat:Wait() end
		end
	end
	pause(0.6 - math.min(0.4, n * 0.016))

	if not s.skip and scene == s then
		-- 2. сундук раскрывается — из него вылетает лента
		sparkBurst(WHITE, 10, 180)
		local accent = def.Accent or WHITE
		setGlow(accent, 0.6)
		tween(chest, 0.22, { Size = UDim2.fromOffset(420, 420), ImageTransparency = 1 })
		tween(shadow, 0.22, { BackgroundTransparency = 1 })
		burst.ImageColor3 = accent
		burst.Size = UDim2.fromOffset(100, 100)
		burst.ImageTransparency = 0
		tween(burst, 0.5, { Size = UDim2.fromOffset(700, 700), ImageTransparency = 1 })
		flashScreen(accent:Lerp(WHITE, 0.6), 0.4, 0.4)
		screenShake(10, 0.3)
		hold(0.12)
		tween(glow, 0.3, { ImageTransparency = 1 })
		tween(rays, 0.3, { ImageTransparency = 1 })
	end
	chest.Visible = false
	shadow.Visible = false

	-- лента выезжает (раскрывается вширь)
	layoutStrip(s, START_POS)
	roulRoot.Visible = true
	roulScale.Scale = roulFit() * 0.2
	TweenService:Create(roulScale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = roulFit() }):Play()
	pause(0.25)

	-- 3. крутим
	spin(s)
	s.canSkip = false
	skipHolder.Visible = false
	if scene ~= s then return end
	if s.skip then
		roulScale.Scale = roulFit()
		sound("Stop")
	end

	-- 4. праздник
	celebrate(s)
end

local function cleanupScene()
	local s = scene
	if not s then return end
	scene = nil
	s.rainbow = false
	s.canSkip = false
	clearUnitView()
	card.Visible = false
	skipHolder.Visible = false
	roulRoot.Visible = false
	letterRow.Visible = false
	s.aura = nil
	if s.hero then
		s.hero.holder:Destroy()
		s.hero = nil
	end
	CR.clearCracks()
	void.Visible = false
	crackLayer.Visible = false
	skyLayer:ClearAllChildren()
	cometLayer:ClearAllChildren()
	auraBack:ClearAllChildren()
	auraFront:ClearAllChildren()
	FX.back:ClearAllChildren()
	FX.front:ClearAllChildren()
	dark.BackgroundTransparency = 1
	shakeAmp.Value = 0
	shakeRoot.Position = UDim2.new()
	UIKit.sparkles(bg, rgb(230, 220, 255), 3, 3)
end

local function finishScene(againId)
	local s = scene
	if not s or s.closing then return end
	s.closing = true
	tween(fade, 0.25, { BackgroundTransparency = 0 })
	task.wait(0.25)
	cleanupScene()
	busy = false
	if againId and requestOpen(againId) then
		return -- новое открытие начнётся с чёрного экрана
	end
	overlay.Enabled = false
	fade.BackgroundTransparency = 1
	if not scene then
		openShop()
	end
end

requestOpen = function(caseId)
	if busy or scene then return false end
	local def = CaseConfig.Cases[caseId]
	if not def then return false end
	if not canAfford(def) then
		toast("Not enough " .. (CUR_NAME[def.Currency] or def.Currency) .. "!", CUR_ICON[def.Currency])
		return false
	end
	busy = true
	local ok, result = pcall(function()
		return openRemote:InvokeServer(caseId)
	end)
	if not ok or typeof(result) ~= "table" or not result.ok then
		busy = false
		toast((ok and typeof(result) == "table" and result.reason) or "Something went wrong, try again", "warning")
		return false
	end
	closeShop()
	task.spawn(function()
		local fine, err = pcall(playOpening, caseId, def, result)
		if not fine then
			-- сломалась анимация — юнит уже выдан сервером; просто возвращаем игрока
			warn("[Cases] анимация открытия: " .. tostring(err))
			cleanupScene()
			busy = false
			fade.BackgroundTransparency = 1
			overlay.Enabled = false
			openShop()
		end
	end)
	return true
end

okBtn.Button.MouseButton1Click:Connect(function()
	finishScene(nil)
end)
again.Button.MouseButton1Click:Connect(function()
	local s = scene
	if not s then return end
	if not canAfford(s.def) then
		UIKit.shake(again.Button)
		return
	end
	finishScene(s.caseId)
end)

---------------------------------------------------------------- объявление на весь сервер: кто-то выбил Legendary / Mythic

task.spawn(function()
	local announceRemote = ReplicatedStorage:WaitForChild("CaseAnnounce", 30)
	if not announceRemote then return end
	local annGui = new("ScreenGui", {
		Name = "CaseAnnounceGui",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 65,
	}, playerGui)
	local queue = {}
	local showing = false

	local function showNext()
		if showing or #queue == 0 then return end
		if scene then
			-- игрок сам сейчас открывает сундук — покажем после
			task.delay(1, showNext)
			return
		end
		showing = true
		local info = table.remove(queue, 1)
		local color = rarityColor(info.rarity)
		local mythic = info.rarity == "Mythic"
		local banner = UIKit.panel(annGui, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, -120),
			Size = UDim2.fromOffset(620, 74),
			ZIndex = 2,
		}, color:Lerp(WHITE, 0.25), color:Lerp(rgb(20, 10, 45), 0.45), { Radius = 22, GlossHeight = 22 })
		local sc = new("UIScale", { Scale = UIKit.fit(760, 0.6, 1) }, banner)
		UIKit.sparkles(banner, WHITE, mythic and 8 or 4, 6)
		icon(banner, mythic and "crown" or "star", { Position = UDim2.fromOffset(10, 9), Size = UDim2.fromOffset(56, 56), ZIndex = 4 })
		text(banner, {
			Position = UDim2.fromOffset(74, 0),
			Size = UDim2.new(1, -84, 1, 0),
			RichText = true,
			TextWrapped = true,
			TextSize = 22,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = string.format('%s got <font color="#%s">%s</font> %s!',
				tostring(info.name), color:Lerp(WHITE, 0.55):ToHex(), string.upper(info.rarity), tostring(info.unit)),
			ZIndex = 4,
		})
		local rainbowConn
		if mythic then
			local st = banner:FindFirstChildOfClass("UIStroke")
			rainbowConn = RunService.RenderStepped:Connect(function()
				if st then st.Color = Color3.fromHSV((os.clock() * 0.5) % 1, 0.7, 1) end
			end)
		end
		tween(banner, 0.45, { Position = UDim2.new(0.5, 0, 0, 70) }, Enum.EasingStyle.Back)
		task.delay(4.5, function()
			tween(banner, 0.35, { Position = UDim2.new(0.5, 0, 0, -140) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			task.wait(0.4)
			if rainbowConn then rainbowConn:Disconnect() end
			banner:Destroy()
			sc:Destroy()
			showing = false
			showNext()
		end)
	end

	announceRemote.OnClientEvent:Connect(function(info)
		if typeof(info) ~= "table" or info.userId == player.UserId then return end
		table.insert(queue, info)
		if #queue > 4 then table.remove(queue, 1) end
		showNext()
	end)
end)

---------------------------------------------------------------- хаб: E у прилавка магазина
-- HubClient шлёт сюда id раздела меню (шина MenuBus в PlayerScripts)

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
		if id ~= "Shop" then return end
		task.defer(function()
			if busy or scene or shopOpen or not shopGui.Enabled then return end
			openShop()
		end)
	end)
end)

---------------------------------------------------------------- кнопка Shop в боковом меню

task.spawn(function()
	local lobby = playerGui:WaitForChild("LobbyMenu", 60)
	if not lobby then
		warn("[Cases] нет LobbyMenu — окно кейсов не к чему привязать")
		return
	end
	local function findTile()
		local b = lobby:FindFirstChild("Shop", true)
		return (b and b:IsA("GuiButton")) and b or nil
	end
	local btn = findTile()
	while not btn do
		lobby.DescendantAdded:Wait()
		btn = findTile()
	end
	btn.MouseButton1Click:Connect(function()
		task.defer(function()
			if busy or scene then return end
			if shopOpen then
				closeShop()
			else
				openShop()
			end
		end)
	end)
	-- открыли другое окно меню (Units, Rewards...) — кейсы закрываются
	local lw = playerGui:WaitForChild("LobbyWindows", 10)
	if lw then
		local function watch(w)
			if not w:IsA("GuiObject") then return end
			w:GetPropertyChangedSignal("Visible"):Connect(function()
				if w.Visible and shopOpen then
					closeShop()
				end
			end)
		end
		for _, w in ipairs(lw:GetChildren()) do
			watch(w)
		end
		lw.ChildAdded:Connect(watch)
	end
end)

-- пока идёт выбор команды, окно скрыто (как и боковое меню)
local function refreshPhase()
	local phase = workspace:GetAttribute("Phase")
	local selecting = phase == nil or phase == "Selection"
	shopGui.Enabled = not selecting
	if selecting then
		closeShop()
	end
end
workspace:GetAttributeChangedSignal("Phase"):Connect(refreshPhase)
refreshPhase()

-- цены, сундучки и гарантия обновляются сами
task.spawn(function()
	local data = player:WaitForChild("Data", 600)
	if not data then return end
	for _, name in ipairs({ "Cash", "Gems", "Cases" }) do
		local v = data:WaitForChild(name, 10)
		if v then
			v.Changed:Connect(refreshShop)
		end
	end
	refreshShop()
end)
player.AttributeChanged:Connect(function(attr)
	if string.sub(attr, 1, 5) == "Pity_" then
		refreshShop()
	end
end)
refreshShop()
