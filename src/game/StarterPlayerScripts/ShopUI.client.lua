-- StarterPlayer.StarterPlayerScripts.ShopUI (LocalScript)
-- Хотбар из 6 выбранных юнитов + постановка башен (мышь, тач, клавиши 1-6).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()

local TowerData = require(ReplicatedStorage:WaitForChild("TowerData"))
local RarityData = require(ReplicatedStorage:WaitForChild("RarityData"))
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))
local PlacementRules = require(ReplicatedStorage:WaitForChild("PlacementRules"))
local PlaceTowerEvent = ReplicatedStorage:WaitForChild("PlaceTower")
local replicatedTowers = ReplicatedStorage:WaitForChild("Towers")
local towersFolder = workspace:WaitForChild("Towers")
local playerGui = player:WaitForChild("PlayerGui")

local new, corner, stroke, tween = UIKit.new, UIKit.corner, UIKit.stroke, UIKit.tween
local text, icon, rgb = UIKit.text, UIKit.icon, UIKit.rgb

-- ждём конца фазы выбора и свой набор юнитов
while workspace:GetAttribute("Phase") ~= "Playing" do task.wait(0.2) end
while not player:GetAttribute("Loadout") do task.wait(0.2) end

local loadout = {}
for _, name in ipairs(string.split(player:GetAttribute("Loadout"), ",")) do
	if TowerData[name] and replicatedTowers:FindFirstChild(name) then
		table.insert(loadout, name)
	end
end

local coins
do
	local stats = player:WaitForChild("leaderstats")
	coins = stats:WaitForChild("Coins")
end

local WHITE = Color3.new(1, 1, 1)
local INK = UIKit.C.Ink
local GREEN_TOP, GREEN_BOT = rgb(160, 255, 120), rgb(25, 185, 70)
local RED_TOP, RED_BOT = rgb(255, 150, 140), rgb(225, 40, 60)
local RED = rgb(255, 110, 120)
local selectedTowerName, ghostModel = nil, nil
local ghostValid = nil -- последний цвет призрака (true = можно ставить)
local slots = {}

---------------------------------------------------------------- интерфейс

local gui = new("ScreenGui", { Name = "ShopScreenGui", ResetOnSpawn = false, DisplayOrder = 3 }, playerGui)

local bar = new("Frame", {
	Name = "Hotbar",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -14),
	Size = UDim2.new(0.62, 0, 0, 124),
	BackgroundTransparency = 1,
}, gui)
new("UISizeConstraint", { MinSize = Vector2.new(440, 124), MaxSize = Vector2.new(740, 124) }, bar)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Bottom,
	Padding = UDim.new(0, 12),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, bar)

local cancel = UIKit.button(gui, {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -150),
	Size = UDim2.fromOffset(200, 50),
	Color = "red",
	Icon = "close",
	IconSize = 34,
	Text = "CANCEL",
	Font = UIKit.Font.Title,
	TextSize = 24,
	Radius = 25,
	Visible = false,
})
local cancelBtn = cancel.Button

local function countPlaced(name)
	local n = 0
	for _, t in ipairs(towersFolder:GetChildren()) do
		if t.Name == name and t:GetAttribute("OwnerId") == player.UserId then
			n += 1
		end
	end
	return n
end

local function refreshSlots()
	local balance = coins.Value
	for _, s in ipairs(slots) do
		local cfg = s.cfg
		local placed = countPlaced(s.name)
		local atLimit = cfg.Limit ~= nil and placed >= cfg.Limit
		local affordable = balance >= cfg.Price
		s.ok = affordable and not atLimit

		s.limit.Text = cfg.Limit and (placed .. "/" .. cfg.Limit) or ""
		s.limit.TextColor3 = atLimit and RED or rgb(235, 240, 255)
		s.priceGrad.Color = affordable and ColorSequence.new(GREEN_TOP, GREEN_BOT) or ColorSequence.new(RED_TOP, RED_BOT)

		local picked = selectedTowerName == s.name
		s.stroke.Thickness = picked and 5 or 3
		s.stroke.Color = picked and WHITE or INK
		s.rays.Visible = picked
		tween(s.scale, 0.15, { Scale = picked and 1.12 or 1 }, Enum.EasingStyle.Back)
		-- недоступный слот слегка затемняется
		tween(s.shade, 0.15, { BackgroundTransparency = s.ok and 1 or 0.45 })
	end
end

local function clearGhost()
	if ghostModel then
		ghostModel:Destroy()
		ghostModel = nil
	end
	ghostValid = nil
	selectedTowerName = nil
	-- флаг для TowerInfoUI: клик, которым ставили башню, не должен открывать панель башни
	task.delay(0.15, function()
		if not ghostModel then player:SetAttribute("Placing", false) end
	end)
	cancelBtn.Visible = false
	refreshSlots()
end

local function setPlacementMode(towerName)
	clearGhost()
	local template = replicatedTowers:FindFirstChild(towerName)
	if not template then return end

	selectedTowerName = towerName
	ghostModel = template:Clone()
	player:SetAttribute("Placing", true)

	for _, d in ipairs(ghostModel:GetDescendants()) do
		if d:IsA("BasePart") then
			if d.Transparency < 1 then d.Transparency = 0.4 end
			d.CanQuery = false
			d.Material = Enum.Material.Neon
			d.Color = Color3.fromRGB(0, 170, 255)
		elseif d:IsA("Script") or d:IsA("LocalScript") or d:IsA("Decal") or d:IsA("SurfaceAppearance") then
			d:Destroy()
		end
	end
	PlacementRules.prepareRig(ghostModel)

	ghostModel.Parent = workspace
	cancelBtn.Visible = true
	UIKit.pop(cancelBtn, 0.5, 0.3)
	refreshSlots()
end

local function choose(index)
	local s = slots[index]
	if not s then return end
	if selectedTowerName == s.name then
		clearGhost()
	elseif s.ok then
		setPlacementMode(s.name)
	else
		UIKit.shake(s.frame)
	end
end

for i, name in ipairs(loadout) do
	local cfg = TowerData[name]
	local rar = RarityData[cfg.Rarity] or RarityData.Common

	local frame = new("TextButton", {
		Name = name,
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.new(1 / 6, -10, 1, 0),
		LayoutOrder = i,
	}, bar)
	local scale = new("UIScale", {}, frame)

	-- лучи за выбранным слотом
	local rays = UIKit.rays(frame, rar.Color:Lerp(WHITE, 0.4), 200, 40, {
		Position = UDim2.fromScale(0.5, 0.4),
		ImageTransparency = 0.3,
		Visible = false,
	})

	local back = UIKit.rarityBack(frame, rar.Color)
	local st = back:FindFirstChildOfClass("UIStroke")

	local holder = new("Frame", {
		Position = UDim2.fromOffset(2, 4),
		Size = UDim2.new(1, -4, 0, 66),
		BackgroundTransparency = 1,
		ZIndex = 2,
	}, back)
	UIKit.makeIcon(holder, name)

	text(back, {
		Text = name,
		Position = UDim2.fromOffset(3, 68),
		Size = UDim2.new(1, -6, 0, 20),
		TextSize = 16,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 3,
	})

	local pricePill = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -6),
		Size = UDim2.new(0.86, 0, 0, 26),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = 3,
	}, back)
	corner(pricePill, 13)
	local priceGrad = new("UIGradient", { Rotation = 90, Color = ColorSequence.new(GREEN_TOP, GREEN_BOT) }, pricePill)
	stroke(pricePill, INK, 2.5)
	icon(pricePill, "coin", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, -8, 0.5, 0),
		Size = UDim2.fromOffset(30, 30),
		ZIndex = 4,
	})
	local price = text(pricePill, {
		Text = tostring(cfg.Price),
		Position = UDim2.fromOffset(16, 0),
		Size = UDim2.new(1, -18, 1, 0),
		Font = UIKit.Font.Title,
		TextSize = 17,
		ZIndex = 4,
	})

	local shade = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = rgb(20, 15, 40),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 5,
	}, back)
	corner(shade, 16)

	local key = new("Frame", {
		Position = UDim2.fromOffset(-8, -8),
		Size = UDim2.fromOffset(26, 26),
		BackgroundColor3 = rgb(255, 220, 70),
		BorderSizePixel = 0,
		ZIndex = 6,
	}, back)
	corner(key, 13)
	stroke(key, INK, 2.5)
	text(key, { Text = tostring(i), Size = UDim2.fromScale(1, 1), Font = UIKit.Font.Title, TextSize = 16, ZIndex = 6 })

	local limit = text(back, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -7, 0, 4),
		Size = UDim2.fromOffset(40, 18),
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 6,
	})

	frame.MouseEnter:Connect(function()
		if selectedTowerName ~= name then tween(scale, 0.12, { Scale = 1.06 }) end
	end)
	frame.MouseLeave:Connect(function()
		if selectedTowerName ~= name then tween(scale, 0.12, { Scale = 1 }) end
	end)
	frame.MouseButton1Click:Connect(function()
		choose(i)
	end)

	slots[i] = {
		name = name, cfg = cfg, frame = frame, stroke = st, scale = scale, shade = shade,
		price = price, priceGrad = priceGrad, rays = rays, limit = limit, ok = true,
	}
end

cancelBtn.MouseButton1Click:Connect(clearGhost)

coins:GetPropertyChangedSignal("Value"):Connect(refreshSlots)
towersFolder.ChildAdded:Connect(refreshSlots)
towersFolder.ChildRemoved:Connect(refreshSlots)
refreshSlots()

---------------------------------------------------------------- призрак башни и ввод

-- синий призрак = можно ставить, красный = нельзя (дорожка или впритык к башне)
local function paintGhost(valid)
	if not ghostModel or ghostValid == valid then return end
	ghostValid = valid
	local color = valid and Color3.fromRGB(0, 170, 255) or Color3.fromRGB(255, 60, 60)
	for _, part in ipairs(ghostModel:GetDescendants()) do
		if part:IsA("BasePart") then part.Color = color end
	end
end

RunService.RenderStepped:Connect(function()
	if ghostModel and mouse.Hit then
		mouse.TargetFilter = ghostModel
		local modelSize = ghostModel:GetExtentsSize()
		ghostModel:PivotTo(CFrame.new(mouse.Hit.Position + Vector3.new(0, modelSize.Y / 2, 0)))
		paintGhost(PlacementRules.check(mouse.Hit.Position, towersFolder) == true)
	end
end)

local keyMap = {
	[Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4, [Enum.KeyCode.Five] = 5, [Enum.KeyCode.Six] = 6,
}

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	local t = input.UserInputType

	if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
		local name = selectedTowerName
		if not name then return end
		if t == Enum.UserInputType.Touch then
			RunService.RenderStepped:Wait() -- даём Mouse.Hit обновиться по месту касания
		end
		if selectedTowerName == name and mouse.Hit then
			if PlacementRules.check(mouse.Hit.Position, towersFolder) then
				PlaceTowerEvent:FireServer(name, mouse.Hit.Position)
				clearGhost()
			elseif ghostModel then
				UIKit.shake(bar) -- нельзя ставить сюда
			end
		end
	elseif t == Enum.UserInputType.MouseButton2 then
		clearGhost()
	elseif t == Enum.UserInputType.Keyboard then
		local idx = keyMap[input.KeyCode]
		if idx then choose(idx) end
	end
end)
