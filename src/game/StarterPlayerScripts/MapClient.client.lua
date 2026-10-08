-- StarterPlayer.StarterPlayerScripts.MapClient (LocalScript) — ТОЛЬКО В МЕСТЕ С МАТЧЕМ
-- Оживляет карту матча (мельница, корабль, маяк, портал, огоньки, астероиды)
-- и показывает название карты, когда начинается бой.
-- Двигает детали только у себя на экране — сервер и другие игроки не нагружаются.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local MapConfig = require(ReplicatedStorage:WaitForChild("MapConfig"))

local UIKit = nil
do
	local mod = ReplicatedStorage:WaitForChild("UIKit", 10)
	if mod then
		local ok, result = pcall(require, mod)
		if ok then UIKit = result end
	end
end

local WHITE = Color3.new(1, 1, 1)

---------------------------------------------------------------- анимации карты

-- у модели атрибуты: Base (CFrame покоя), Rotor (°/с вокруг своей оси Z),
-- Float (высота покачивания), Spin (°/с вокруг вертикали), Speed, Phase
local tracked = {}

local function track(obj)
	if not obj:IsA("Model") then return end
	local base = obj:GetAttribute("Base")
	if typeof(base) ~= "CFrame" then return end
	local rotor, float, spin = obj:GetAttribute("Rotor"), obj:GetAttribute("Float"), obj:GetAttribute("Spin")
	if not (rotor or float or spin) then return end
	tracked[obj] = {
		base = base,
		rotor = math.rad(rotor or 0),
		float = float or 0,
		spin = math.rad(spin or 0),
		speed = obj:GetAttribute("Speed") or 1,
		phase = obj:GetAttribute("Phase") or 0,
	}
end

local function hook(map)
	for _, d in ipairs(map:GetDescendants()) do track(d) end
	map.DescendantAdded:Connect(track)
	map.DescendantRemoving:Connect(function(d) tracked[d] = nil end)
end

local current = workspace:FindFirstChild("BattleMap")
if current then hook(current) end
workspace.ChildAdded:Connect(function(c)
	if c.Name == "BattleMap" then hook(c) end
end)

local TAU = math.pi * 2
RunService.RenderStepped:Connect(function()
	local t = workspace:GetServerTimeNow() - 1.7e9 -- общее время: у всех игроков движется одинаково
	for obj, a in pairs(tracked) do
		if obj.Parent then
			local cf = a.base
			if a.float ~= 0 or a.spin ~= 0 then
				local y = math.sin((t * a.speed + a.phase) % TAU) * a.float
				cf = CFrame.new(a.base.Position + Vector3.new(0, y, 0)) * CFrame.Angles(0, (t * a.spin) % TAU, 0) * a.base.Rotation
			end
			if a.rotor ~= 0 then
				cf = cf * CFrame.Angles(0, 0, (t * a.rotor) % TAU)
			end
			obj:PivotTo(cf)
		else
			tracked[obj] = nil
		end
	end
end)

---------------------------------------------------------------- название карты в начале боя

local shown = false
local function showTitle()
	if shown then return end
	local cfg = MapConfig.get(workspace:GetAttribute("MapId"))
	if not cfg then return end
	shown = true

	local gui = Instance.new("ScreenGui")
	gui.Name = "MapTitle"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 15

	local group = Instance.new("CanvasGroup")
	group.AnchorPoint = Vector2.new(0.5, 0)
	group.Position = UDim2.new(0.5, 0, 0, 84)
	group.Size = UDim2.fromOffset(760, 130)
	group.BackgroundTransparency = 1
	group.GroupTransparency = 1
	group.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = group
	if UIKit then UIKit.fitScale(scale, 820, 0.5, 1) end

	local function label(text, y, h, size, font, color)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromOffset(0, y)
		l.Size = UDim2.new(1, 0, 0, h)
		l.Font = font
		l.TextSize = size
		l.Text = text
		l.TextColor3 = color
		l.Parent = group
		local s = Instance.new("UIStroke")
		s.Color = Color3.fromRGB(36, 19, 58)
		s.Thickness = size >= 40 and 4.5 or 2.5
		s.Parent = l
		return l
	end
	label(string.upper(cfg.Name), 0, 76, 66, Enum.Font.LuckiestGuy, cfg.Color:Lerp(WHITE, 0.45))
	label("MAP LEVEL: " .. MapConfig.tier(workspace:GetAttribute("MapId")).Name .. "   •   " .. (cfg.Tagline or ""), 78, 36, 28, Enum.Font.FredokaOne, WHITE)
	gui.Parent = playerGui

	TweenService:Create(group, TweenInfo.new(0.6), { GroupTransparency = 0 }):Play()
	task.delay(4.2, function()
		local tw = TweenService:Create(group, TweenInfo.new(0.9), { GroupTransparency = 1 })
		tw:Play()
		tw.Completed:Wait()
		gui:Destroy()
	end)
end

local function onPhase()
	if workspace:GetAttribute("Phase") == "Playing" then
		task.delay(0.6, showTitle)
	end
end
workspace:GetAttributeChangedSignal("Phase"):Connect(onPhase)
workspace:GetAttributeChangedSignal("MapId"):Connect(onPhase)
onPhase()
