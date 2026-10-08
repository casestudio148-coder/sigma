-- StarterPlayer.StarterPlayerScripts.BossUI (LocalScript)
-- Полоска здоровья босса (с отметками фаз), большие надписи «БОСС ПОЯВИЛСЯ / ЯРОСТЬ / ПОБЕЖДЁН» с картинками,
-- вспышка экрана и аура на боссе по цвету фазы. Данные — атрибуты BossId / BossPhase с сервера.
-- Всё, что создаётся для босса, лежит в его Janitor и удаляется вместе с ним.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local BossData = require(ReplicatedStorage:WaitForChild("BossData"))
local Janitor = require(ReplicatedStorage:WaitForChild("Janitor"))
local VFX = require(ReplicatedStorage:WaitForChild("VFXKit"))
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))
local mobsFolder = workspace:WaitForChild("Mobs")

local rgb, ns, nr, UP, TEX = VFX.rgb, VFX.ns, VFX.nr, VFX.UP, VFX.TEX
local new, corner, stroke, text, icon = UIKit.new, UIKit.corner, UIKit.stroke, UIKit.text, UIKit.icon
local WHITE = Color3.new(1, 1, 1)

---------------------------------------------------------------- интерфейс

local gui = new("ScreenGui", { Name = "BossUI", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 6, Enabled = true }, player:WaitForChild("PlayerGui"))

local bar = UIKit.panel(gui, {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 126),
	Size = UDim2.fromOffset(470, 72),
	Visible = false,
}, rgb(150, 60, 120), rgb(55, 15, 60), { Radius = 20, GlossHeight = 20 })
local barScale = new("UIScale", {}, bar)

local crownIcon = icon(bar, "crown", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0, 6, 0, 6),
	Size = UDim2.fromOffset(54, 54),
	Rotation = -18,
	ZIndex = 3,
})
UIKit.wobble(crownIcon, 8, 1)

local nameLabel = text(bar, {
	Position = UDim2.fromOffset(38, 6), Size = UDim2.new(0.6, 0, 0, 28),
	Font = UIKit.Font.Title, TextSize = 24, TextXAlignment = Enum.TextXAlignment.Left, Text = "",
})
local phaseLabel = text(bar, {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 8), Size = UDim2.new(0.4, 0, 0, 24),
	TextSize = 18, TextXAlignment = Enum.TextXAlignment.Right, Text = "",
})

local hp = UIKit.bar(bar, { Position = UDim2.fromOffset(14, 38), Size = UDim2.new(1, -28, 0, 22) })
local hpTrack, fill, hpText = hp.Track, hp.Fill, hp.Label

-- отметки фаз
local markers = {}
for i = 1, 4 do
	markers[i] = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.new(0, 4, 1, 0),
		BackgroundColor3 = WHITE, BackgroundTransparency = 0.1, BorderSizePixel = 0, ZIndex = 2, Visible = false,
	}, hpTrack)
end

-- большая надпись с картинками по бокам
local announceRow = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.34), Size = UDim2.new(0.95, 0, 0, 90),
	BackgroundTransparency = 1, Visible = false, ZIndex = 10,
}, gui)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	Padding = UDim.new(0, 12),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, announceRow)
local announceIconL = icon(announceRow, "crown", { Size = UDim2.fromOffset(80, 80), LayoutOrder = 1, ZIndex = 10 })
local announce = UIKit.title(announceRow, {
	AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0),
	TextSize = 58, Text = "", ZIndex = 10, LayoutOrder = 2,
})
local announceGrad = announce:FindFirstChildOfClass("UIGradient")
local announceIconR = icon(announceRow, "crown", { Size = UDim2.fromOffset(80, 80), LayoutOrder = 3, ZIndex = 10 })
local announceScale = new("UIScale", {}, announceRow)

local vignette = new("Frame", {
	Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(255, 40, 40), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 1,
}, gui)

local announceToken = 0
local function showAnnounce(msg, color, flash, iconName)
	announceToken += 1
	local token = announceToken
	color = color or WHITE
	announce.Text = msg
	announceGrad.Color = ColorSequence.new(color:Lerp(WHITE, 0.6), color)
	UIKit.setIcon(announceIconL, iconName)
	UIKit.setIcon(announceIconR, iconName)
	announceIconL.Visible = iconName ~= nil and UIKit.IconsReady
	announceIconR.Visible = announceIconL.Visible
	announceRow.Visible = true
	announceScale.Scale = 0.3
	TweenService:Create(announceScale, TweenInfo.new(0.5, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	UIKit.pop(announceIconL, 2, 0.5)
	UIKit.pop(announceIconR, 2, 0.5)
	if flash then
		vignette.BackgroundColor3 = color
		vignette.BackgroundTransparency = 0.55
		TweenService:Create(vignette, TweenInfo.new(0.8), { BackgroundTransparency = 1 }):Play()
	end
	task.delay(2.2, function()
		if token ~= announceToken then return end
		TweenService:Create(announceScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 }):Play()
		task.delay(0.32, function()
			if token == announceToken then announceRow.Visible = false end
		end)
	end)
end

---------------------------------------------------------------- боссы

local states = {} -- [mob] = состояние
local order = {}  -- порядок появления
local current = nil

local function phaseDef(st)
	return st.def.Phases[st.phase] or st.def.Phases[1]
end

local function render()
	if not current then
		bar.Visible = false
		return
	end
	bar.Visible = true
	local hum = current.hum
	local ratio = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
	local ph = phaseDef(current)
	local color = ph.Color or current.def.Color or rgb(255, 80, 80)

	nameLabel.Text = current.def.DisplayName
	phaseLabel.Text = ph.Name
	phaseLabel.TextColor3 = color
	hp.setColors(color:Lerp(WHITE, 0.35), color)
	hp.set(ratio, 0.25)
	hpText.Text = math.floor(ratio * 100 + 0.5) .. "%"

	-- отметки порогов фаз (кроме первой)
	local phases = current.def.Phases
	for i, m in ipairs(markers) do
		local p = phases[i + 1]
		m.Visible = p ~= nil
		if p then
			m.Position = UDim2.fromScale(p.At, 0)
			m.BackgroundColor3 = (i + 1 <= current.phase) and rgb(120, 120, 140) or WHITE
		end
	end
end

local function pickCurrent()
	current = nil
	for _, st in ipairs(order) do
		if st.hum.Health > 0 then
			current = st
			break
		end
	end
	render()
end

-- аура и подсветка босса по цвету фазы
local function applyAura(st)
	if st.aura then
		st.aura:Destroy()
		st.aura = nil
	end
	local root = st.mob:FindFirstChild("HumanoidRootPart") or st.mob.PrimaryPart
	if not root then return end
	local ph = phaseDef(st)
	local color = ph.Color or st.def.Color or rgb(255, 80, 80)
	local j = Janitor.new()
	st.aura = j

	local att = Instance.new("Attachment")
	att.Parent = root
	j:Add(att)
	VFX.emitter(att, {
		Texture = (st.phase >= 2) and TEX.Fire or TEX.Sparkle,
		Color = color:Lerp(WHITE, 0.3), Color2 = color,
		Rate = 6 + st.phase * 8, Speed = nr(2, 5), Lifetime = nr(0.5, 0.9),
		Size = ns(1 + st.phase * 0.4, 0), Acceleration = UP * 6, Spread = Vector2.new(60, 60),
	})

	local hl = Instance.new("Highlight")
	hl.FillColor = color
	hl.OutlineColor = color
	hl.FillTransparency = 0.85 - st.phase * 0.1
	hl.OutlineTransparency = 0.1
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.Adornee = st.mob
	hl.Parent = st.mob
	j:Add(hl)
end

local function untrack(mob)
	local st = states[mob]
	if not st then return end
	states[mob] = nil
	local idx = table.find(order, st)
	if idx then table.remove(order, idx) end
	if st.aura then st.aura:Destroy() end
	st.janitor:Destroy()
	if current == st then pickCurrent() end
end

local function track(mob)
	if states[mob] then return end
	local def = BossData[mob:GetAttribute("BossId") or ""]
	if not def then return end
	local hum = mob:FindFirstChildOfClass("Humanoid") or mob:WaitForChild("Humanoid", 3)
	if not hum or not mob.Parent or states[mob] then return end

	local st = { mob = mob, hum = hum, def = def, phase = mob:GetAttribute("BossPhase") or 1, janitor = Janitor.new() }
	states[mob] = st
	table.insert(order, st)

	st.janitor:Connect(hum.HealthChanged, function()
		if current == st then render() end
	end)
	st.janitor:Connect(mob:GetAttributeChangedSignal("BossPhase"), function()
		local ph = mob:GetAttribute("BossPhase") or 1
		if ph > st.phase then
			st.phase = ph
			local pd = phaseDef(st)
			showAnnounce(pd.Announce or (string.upper(def.DisplayName) .. ": " .. string.upper(pd.Name)),
				pd.Color or def.Color, true, "warning")
			barScale.Scale = 1.12
			TweenService:Create(barScale, TweenInfo.new(0.4, Enum.EasingStyle.Back), { Scale = 1 }):Play()
			local root = mob.PrimaryPart
			if root then
				VFX.burst(root.Position, 8, pd.Color or WHITE, 0.5, 0.2)
				VFX.ring(VFX.ground(root.Position), 14, pd.Color or WHITE, 0.6, 1.6)
				VFX.shake(root.Position, 1.5)
			end
			applyAura(st)
		end
		if current == st then render() end
	end)
	st.janitor:Connect(hum.Died, function()
		showAnnounce(string.upper(def.DisplayName) .. " DEFEATED!", rgb(255, 215, 80), false, "trophy")
		if current == st then pickCurrent() end
	end)
	st.janitor:Connect(mob.AncestryChanged, function(_, parent)
		if parent == nil then untrack(mob) end
	end)

	applyAura(st)
	showAnnounce(string.upper(def.DisplayName) .. " APPEARS!", def.Color, true, "demon")
	if not current then
		current = st
	end
	render()
end

local function onMob(mob)
	if mob:GetAttribute("BossId") then
		task.spawn(track, mob)
	else
		-- сервер ставит BossId сразу после появления моба. Соединение умрёт вместе с мобом.
		local conn
		conn = mob:GetAttributeChangedSignal("BossId"):Connect(function()
			conn:Disconnect()
			task.spawn(track, mob)
		end)
	end
end

mobsFolder.ChildAdded:Connect(onMob)
for _, m in ipairs(mobsFolder:GetChildren()) do
	onMob(m)
end

-- полоска только во время матча
local function refreshPhase()
	gui.Enabled = workspace:GetAttribute("Phase") == "Playing"
end
workspace:GetAttributeChangedSignal("Phase"):Connect(refreshPhase)
refreshPhase()
