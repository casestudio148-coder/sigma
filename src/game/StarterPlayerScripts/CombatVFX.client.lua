-- StarterPlayer.StarterPlayerScripts.CombatVFX (LocalScript)
-- Клиентские эффекты новой боевой системы:
--   • статусы на мобах и башнях по атрибуту Status (огонь, яд, лёд, стан, бафы, отключение...);
--   • эффекты активных способностей башен и навыков боссов (событие AbilityFX).
-- Всё, что создаётся для моба/башни, лежит в его Janitor и удаляется вместе с ним.
-- Лимиты: подсветок (Highlight) не больше 24 (у Roblox предел 31), постоянных излучателей не больше 90.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local VFX = require(ReplicatedStorage:WaitForChild("VFXKit"))
local Janitor = require(ReplicatedStorage:WaitForChild("Janitor"))
local StatusData = require(ReplicatedStorage:WaitForChild("StatusData"))
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))
local fxEvent = ReplicatedStorage:WaitForChild("AbilityFX")
local mobsFolder = workspace:WaitForChild("Mobs")
local towersFolder = workspace:WaitForChild("Towers")

local rgb, ns, nr, UP, TEX = VFX.rgb, VFX.ns, VFX.nr, VFX.UP, VFX.TEX

---------------------------------------------------------------- СТАТУСЫ

local MAX_HIGHLIGHTS = 24
local MAX_EMITTERS = 90
local highlights, emitters = 0, 0

-- как выглядит каждый статус (Emitter — постоянные частицы, Highlight — подсветка модели)
local LOOK = {
	Burn = { Emitter = { Texture = TEX.Fire, Color = rgb(255, 210, 90), Color2 = rgb(255, 80, 20), Rate = 14,
		Speed = nr(2, 5), Lifetime = nr(0.35, 0.6), Size = ns(1.3, 0.2), Acceleration = UP * 8, Spread = Vector2.new(25, 25) } },
	Poison = { Emitter = { Color = rgb(120, 240, 80), Color2 = rgb(200, 255, 120), Rate = 7,
		Speed = nr(1, 3), Lifetime = nr(0.6, 1), Size = ns(0.45, 0), Acceleration = UP * 3, Spread = Vector2.new(30, 30) } },
	Slow = { Emitter = { Color = rgb(255, 255, 255), Color2 = rgb(150, 225, 255), Rate = 8,
		Speed = nr(0.5, 2), Lifetime = nr(0.6, 1), Size = ns(0.3, 0), Acceleration = Vector3.new(0, -4, 0) } },
	Freeze = {
		Highlight = { Color = rgb(170, 230, 255), Fill = 0.2 },
		Emitter = { Color = rgb(220, 245, 255), Rate = 6, Speed = nr(0.2, 1), Lifetime = nr(0.5, 0.9), Size = ns(0.5, 0) },
	},
	Haste = { Emitter = { Texture = TEX.Smoke, Color = rgb(255, 180, 90), LightEmission = 0.4, Rate = 10,
		Speed = nr(4, 7), Lifetime = nr(0.2, 0.35), Size = ns(0.6, 0), Spread = Vector2.new(10, 10) } },
	Vulnerable = {
		Highlight = { Color = rgb(255, 60, 100), Fill = 0.75 },
		Emitter = { Color = rgb(255, 70, 110), Rate = 5, Speed = nr(1, 3), Lifetime = nr(0.4, 0.7), Size = ns(0.4, 0) },
	},
	AttackHaste = { Emitter = { Color = rgb(255, 235, 100), Rate = 3, Speed = nr(1, 3), Lifetime = nr(0.4, 0.7),
		Size = ns(0.35, 0), Acceleration = UP * 6 } },
	Empower = { Emitter = { Color = rgb(255, 160, 60), Rate = 2, Speed = nr(1, 2), Lifetime = nr(0.4, 0.7),
		Size = ns(0.4, 0), Acceleration = UP * 5 } },
	Disabled = {
		Highlight = { Color = rgb(100, 25, 160), Fill = 0.35 },
		Emitter = { Texture = TEX.Smoke, Color = rgb(130, 40, 220), Color2 = rgb(20, 0, 30), LightEmission = 0.3, Rate = 6,
			Speed = nr(1, 3), Lifetime = nr(0.6, 1), Size = ns(1.2, 2) },
	},
	Invulnerable = { Highlight = { Color = rgb(255, 235, 150), Fill = 0.5 } },
	Transform = { Highlight = { Color = rgb(255, 60, 60), Fill = 0.35 } },
}

local watchers = {}

local function addLook(w, id)
	local look = LOOK[id]
	if not look or not w.root then return end
	local j = Janitor.new()
	w.looks[id] = j

	if look.Emitter and emitters < MAX_EMITTERS * VFX.Quality then
		local att = Instance.new("Attachment")
		att.Parent = w.root
		VFX.emitter(att, look.Emitter)
		emitters += 1
		j:Add(att)
		j:Add(function() emitters -= 1 end)
	end

	if look.Highlight and highlights < MAX_HIGHLIGHTS then
		local hl = Instance.new("Highlight")
		hl.FillColor = look.Highlight.Color
		hl.OutlineColor = look.Highlight.Color
		hl.FillTransparency = look.Highlight.Fill
		hl.OutlineTransparency = 0.2
		hl.DepthMode = Enum.HighlightDepthMode.Occluded
		hl.Adornee = w.model
		hl.Parent = w.model
		highlights += 1
		j:Add(hl)
		j:Add(function() highlights -= 1 end)
	end
end

local function removeLook(w, id)
	local j = w.looks[id]
	if j then
		w.looks[id] = nil
		j:Destroy()
	end
end

-- значки статусов над головой. Один BillboardGui на модель; каждый значок создаётся один раз,
-- дальше только показывается/прячется (стан мигает много раз в секунду — пересоздавать GUI дорого)
local ICON = 30
local function buildIcons(w, mask)
	if not w.root then return end
	local shown, order = 0, {}
	for _, def in ipairs(StatusData.Decode(mask)) do
		if def.ShowIcon and def.Icon ~= "" then
			shown += 1
			order[def.Id] = shown
			if shown >= 4 then break end
		end
	end
	if shown == 0 and not w.icons then return end

	if not w.icons then
		local bb = Instance.new("BillboardGui")
		bb.Name = "StatusIcons"
		bb.StudsOffsetWorldSpace = Vector3.new(0, w.height, 0)
		bb.LightInfluence = 0
		bb.MaxDistance = 140
		bb.Adornee = w.root
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = bb
		bb.Parent = w.root
		w.icons = bb
		w.iconLabels = {}
	end

	-- спрятать то, что закончилось
	for id, l in pairs(w.iconLabels) do
		if not order[id] and l.Visible then
			l.Visible = false
			if id == "Stun" and w.iconTween then w.iconTween:Pause() end
		end
	end
	-- показать то, что появилось
	for id, n in pairs(order) do
		local l = w.iconLabels[id]
		local appeared = false
		if not l then
			-- картинка статуса из атласа UIKit (вместо смайлика)
			l = UIKit.icon(w.icons, UIKit.StatusIcon[id] or "sparkle", { Size = UDim2.fromOffset(ICON, ICON) })
			w.iconLabels[id] = l
			if id == "Stun" then
				w.iconTween = TweenService:Create(l, TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Rotation = 20 })
			end
			appeared = true
		elseif not l.Visible then
			l.Visible = true
			appeared = true
		end
		l.LayoutOrder = n
		if appeared and id == "Stun" and w.iconTween then w.iconTween:Play() end
	end
	w.icons.Size = UDim2.fromOffset(ICON * math.max(shown, 1), ICON)
	w.icons.Enabled = shown > 0
end

local function update(w)
	if not w.model.Parent then return end
	local mask = w.model:GetAttribute("Status") or 0
	if mask == w.mask then return end
	local old = w.mask
	w.mask = mask
	for id, def in pairs(StatusData.Effects) do
		local had = bit32.band(old, def.Bit) ~= 0
		local has = bit32.band(mask, def.Bit) ~= 0
		if has and not had then
			addLook(w, id)
		elseif had and not has then
			removeLook(w, id)
		end
	end
	buildIcons(w, mask)
end

local function watch(model)
	if watchers[model] or not model:IsA("Model") then return end
	local w = { model = model, mask = 0, looks = {}, height = 3.5, janitor = Janitor.new() }
	watchers[model] = w

	w.janitor:Add(function()
		for _, j in pairs(w.looks) do j:Destroy() end
		w.looks = {}
		if w.iconTween then
			w.iconTween:Cancel()
			w.iconTween = nil
		end
		if w.icons then
			w.icons:Destroy()
			w.icons = nil
			w.iconLabels = nil
		end
		if watchers[model] == w then watchers[model] = nil end
	end)
	w.janitor:Connect(model.AncestryChanged, function(_, parent)
		if parent == nil then w.janitor:Destroy() end
	end)

	task.spawn(function()
		local root = model:FindFirstChild("HumanoidRootPart") or model:WaitForChild("HumanoidRootPart", 3) or model.PrimaryPart
		if not root or watchers[model] ~= w or not model.Parent then return end
		w.root = root
		local ok, size = pcall(function() return model:GetExtentsSize() end)
		w.height = (ok and size.Y / 2 or 2.5) + 1.3
		w.janitor:Connect(model:GetAttributeChangedSignal("Status"), function()
			update(w)
		end)
		update(w)
	end)
end

for _, folder in ipairs({ mobsFolder, towersFolder }) do
	folder.ChildAdded:Connect(watch)
	for _, m in ipairs(folder:GetChildren()) do
		watch(m)
	end
end

---------------------------------------------------------------- СПОСОБНОСТИ И НАВЫКИ БОССОВ

local function towerTop(p)
	local tower = p.tower
	if tower and tower.Parent then
		local cf, size = tower:GetBoundingBox()
		return cf.Position + UP * (size.Y / 2 + 1.5)
	end
	return (p.origin or p.center or Vector3.zero) + UP * 3
end

local function smoke(pos, color, count)
	VFX.emit(pos, count or 12, {
		Texture = TEX.Smoke, Color = color or rgb(70, 70, 75), Color2 = rgb(40, 40, 40), LightEmission = 0,
		Speed = nr(3, 8), Lifetime = nr(0.8, 1.4), Size = ns(2, 4.5),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) }),
		Acceleration = UP * 3, Drag = 1.5,
	})
end

local function explosion(pos, radius, color)
	local g = VFX.ground(pos)
	VFX.burst(pos, radius * 0.6, rgb(255, 240, 150), 0.25, 0)
	VFX.burst(pos, radius, color or rgb(255, 140, 40), 0.4, 0.15)
	VFX.ring(g, radius * 1.4, rgb(255, 220, 90), 0.45, 1.2)
	VFX.emit(pos, 18, { Texture = TEX.Fire, Color = rgb(255, 220, 90), Color2 = rgb(255, 90, 20),
		Speed = nr(8, 18), Lifetime = nr(0.3, 0.6), Size = ns(2.5, 0.5), Drag = 3 })
	smoke(pos)
	VFX.flash(pos, rgb(255, 140, 40), 6, radius * 3.5, 0.45)
	VFX.shake(pos, 0.8)
end

-- зона, которая держится duration секунд и плавно исчезает
local function zone(center, radius, color, transparency, duration, emitterCfg)
	if not VFX.canSpawn(1) then return end -- лимит деталей: при перегрузе зону пропускаем
	local g = VFX.ground(center)
	local d = VFX.disc(g, 0.5, color, transparency) -- появляется маленьким и раскрывается
	VFX.tween(d, 0.25, { Size = Vector3.new(0.15, radius * 2, radius * 2) })
	if emitterCfg then
		-- диск — повёрнутый цилиндр: «вверх» для него — локальная ось +X (Right)
		emitterCfg.EmissionDirection = emitterCfg.EmissionDirection or Enum.NormalId.Right
		VFX.emitter(d, emitterCfg)
	end
	task.delay(duration, function()
		for _, c in ipairs(d:GetChildren()) do
			if c:IsA("ParticleEmitter") then c.Enabled = false end
		end
		VFX.fadeOut(d, 0.6)
	end)
	return d, g
end

local FX = {}

-- 🏹 Arrow Rain
FX.ArrowRain = function(p)
	VFX.ring(VFX.ground(p.center), p.radius, rgb(255, 230, 160), 0.6, 0.6)
end
FX.ArrowVolley = function(p)
	local g = VFX.ground(p.center)
	for _ = 1, VFX.count(12) do
		local landing = g + Vector3.new((math.random() - 0.5) * 1.6 * p.radius, 0.3, (math.random() - 0.5) * 1.6 * p.radius)
		local start = landing + Vector3.new(-5, 28, -5)
		task.delay(math.random() * 0.2, function()
			VFX.projectile(start, landing, {
				Size = Vector3.new(0.14, 0.14, 2), Color = rgb(150, 100, 50), Material = Enum.Material.Wood,
				Speed = 95, TrailColor = rgb(255, 250, 220), TrailWidth = 0.08, TrailLife = 0.12,
			}, function(pos)
				VFX.emit(pos, 3, { Color = rgb(170, 130, 80), LightEmission = 0, Speed = nr(4, 8), Lifetime = nr(0.2, 0.35),
					Size = ns(0.25, 0), Acceleration = Vector3.new(0, -40, 0) })
			end)
		end)
	end
end

-- ☄️ Meteor
FX.Meteor = function(p)
	local g = VFX.ground(p.center)
	VFX.ring(g, p.radius, rgb(255, 120, 40), p.fall, 0.5)
	VFX.projectile(g + Vector3.new(-25, 70, -25), g, {
		Shape = Enum.PartType.Ball, Size = Vector3.one * 4, Color = rgb(255, 120, 40), Time = p.fall,
		Easing = Enum.EasingStyle.Quad, TrailColor = rgb(255, 200, 80), TrailWidth = 1.6, TrailLife = 0.35,
		Emitter = { Texture = TEX.Fire, Color = rgb(255, 220, 90), Color2 = rgb(255, 60, 20), Rate = 80,
			Speed = nr(1, 3), Lifetime = nr(0.3, 0.6), Size = ns(3, 0.5) },
	}, function()
		explosion(g + UP, p.radius, rgb(255, 110, 30))
		VFX.shake(g, 1.4)
		zone(g, p.radius * 0.8, rgb(255, 90, 20), 0.75, 3, { Texture = TEX.Fire, Color = rgb(255, 200, 80),
			Color2 = rgb(255, 60, 20), Rate = 30, Speed = nr(1, 3), Lifetime = nr(0.4, 0.8), Size = ns(1.6, 0.2), Acceleration = UP * 6 })
	end)
end

-- 🌨️ Blizzard
FX.Blizzard = function(p)
	local g = VFX.ground(p.center)
	VFX.ring(g, p.radius, rgb(200, 240, 255), 0.5, 1.2)
	task.delay(0.1, function() VFX.ring(g, p.radius * 1.1, rgb(120, 200, 255), 0.6, 0.6) end)
	VFX.burst(g + UP, p.radius * 0.7, rgb(170, 230, 255), 0.4, 0.3)
	zone(g, p.radius, rgb(170, 230, 255), 0.55, p.duration or 2.5)
	-- снегопад над зоной
	if VFX.canSpawn(1) then
		local cloud = VFX.part({ Transparency = 1, Size = Vector3.new(p.radius * 2, 0.2, p.radius * 2), Position = g + UP * 16 })
		VFX.emitter(cloud, { Color = rgb(255, 255, 255), Color2 = rgb(190, 230, 255), Rate = 90, Speed = nr(10, 16),
			Lifetime = nr(0.9, 1.2), Size = ns(0.5, 0.2), Spread = Vector2.new(8, 8), EmissionDirection = Enum.NormalId.Bottom })
		VFX.release(cloud, (p.duration or 2.5) + 1.2)
	end
	-- ледяные шипы по кругу
	for i = 1, VFX.count(10) do
		local ang = i / 10 * math.pi * 2 + math.random() * 0.4
		local r = p.radius * (0.4 + math.random() * 0.55)
		local base = g + Vector3.new(math.cos(ang) * r, 0, math.sin(ang) * r)
		local h = 2 + math.random() * 2.5
		local rot = CFrame.Angles(math.rad(math.random(-20, 20)), math.rad(45), math.rad(math.random(-20, 20)))
		if VFX.canSpawn(1) then
			local spike = VFX.part({ Material = Enum.Material.Glass, Color = rgb(170, 230, 255), Transparency = 0.2,
				Size = Vector3.new(0.7, 0.1, 0.7), CFrame = CFrame.new(base) * rot })
			VFX.tween(spike, 0.15, { Size = Vector3.new(0.7, h, 0.7), CFrame = CFrame.new(base) * rot * CFrame.new(0, h / 2, 0) }, Enum.EasingStyle.Back)
			task.delay((p.duration or 2.5) - 0.2, function()
				VFX.fadeOut(spike, 0.3, { Size = Vector3.new(0.1, h * 0.3, 0.1) })
			end)
		end
	end
	VFX.shake(g, 0.5)
end

-- ☁️ Toxic Cloud
FX.ToxicCloud = function(p)
	local g = VFX.ground(p.center)
	VFX.ring(g, p.radius, rgb(140, 255, 90), 0.5, 0.8)
	zone(g, p.radius, rgb(90, 200, 60), 0.7, p.duration or 6, {
		Texture = TEX.Smoke, Color = rgb(120, 230, 70), Color2 = rgb(60, 140, 40), LightEmission = 0.2, Rate = 22,
		Speed = nr(1, 3), Lifetime = nr(1.2, 2), Size = ns(4, 6.5),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) }),
		Acceleration = UP * 1.5, Spread = Vector2.new(60, 60),
	})
end

-- 💣 Carpet Bomb
FX.CarpetBomb = function(p)
	for i, pt in ipairs(p.points or {}) do
		local g = VFX.ground(pt)
		local arrive = p.fall + (i - 1) * p.step
		VFX.ring(g, p.radius, rgb(255, 80, 60), arrive, 0.4)
		task.delay(math.max(arrive - 0.45, 0), function()
			VFX.projectile(g + Vector3.new(0, 30, 0), g, {
				Shape = Enum.PartType.Ball, Size = Vector3.one * 1.6, Color = rgb(35, 35, 40), Material = Enum.Material.SmoothPlastic,
				Time = 0.45, Easing = Enum.EasingStyle.Quad,
				Emitter = { Texture = TEX.Fire, Color = rgb(255, 220, 90), Color2 = rgb(255, 120, 30), Rate = 50,
					Speed = nr(1, 3), Lifetime = nr(0.15, 0.3), Size = ns(0.8, 0) },
			}, function()
				explosion(g + UP, p.radius, rgb(255, 120, 30))
			end)
		end)
	end
end

-- 🎯 Mark for Death
FX.MarkForDeath = function(p)
	local target = p.target
	VFX.beam(p.origin, target, rgb(200, 140, 255), 0.25, 0.25)
	VFX.burst(target, 3, rgb(255, 40, 70), 0.3, 0.2)
	local g = VFX.ground(target)
	VFX.ring(g, 4, rgb(255, 50, 80), 0.6, 0.5)
	task.delay(0.15, function() VFX.ring(g, 6, rgb(255, 120, 140), 0.6, 0.3) end)
	VFX.popText(target + UP * 4, "MARKED!", rgb(255, 80, 110), 26, 1.3)
end

-- 🦠 Plague
FX.Plague = function(p)
	for i, pt in ipairs(p.points or {}) do
		task.delay(i * 0.05, function()
			VFX.bolt(p.origin, pt, rgb(140, 255, 120), 0.18, 0.3)
			VFX.burst(pt, 2.2, rgb(110, 220, 80), 0.3, 0.3)
			VFX.emit(pt, 8, { Color = rgb(150, 255, 100), Speed = nr(2, 5), Lifetime = nr(0.5, 0.9), Size = ns(0.5, 0), Acceleration = UP * 4 })
			VFX.popText(pt + UP * 3, "SICK!", rgb(150, 255, 120), 22, 0.9)
		end)
	end
end

-- 🔱 Ballista
FX.Ballista = function(p)
	VFX.beam(p.origin, p.endPos, rgb(255, 255, 255), 0.5, 0.35)
	VFX.beam(p.origin, p.endPos, rgb(120, 190, 255), 1.6, 0.5)
	VFX.projectile(p.origin, p.endPos, { Size = Vector3.new(0.5, 0.5, 4), Color = rgb(200, 205, 215), Material = Enum.Material.Metal,
		Speed = 240, TrailColor = rgb(200, 230, 255), TrailWidth = 0.3, TrailLife = 0.3 })
	for _, h in ipairs(p.hits or {}) do
		VFX.emit(h, 8, { Color = rgb(255, 210, 130), Color2 = rgb(255, 120, 40), Speed = nr(14, 26), Lifetime = nr(0.15, 0.35),
			Size = ns(0.35, 0), Acceleration = Vector3.new(0, -50, 0) })
		VFX.burst(h, 1.6, rgb(255, 255, 255), 0.15, 0.3)
	end
	VFX.shake(p.origin, 0.6)
end

-- 📯 Rally
FX.Rally = function(p)
	local g = VFX.ground(p.center)
	VFX.ring(g, p.radius, rgb(255, 215, 90), 0.8, 1.4)
	task.delay(0.15, function() VFX.ring(g, p.radius * 0.6, rgb(255, 245, 190), 0.6, 0.8) end)
	VFX.flash(p.center, rgb(255, 230, 140), 5, 30, 0.6)
	for i, tp in ipairs(p.towers or {}) do
		task.delay(i * 0.04, function()
			local tg = VFX.ground(tp)
			if VFX.canSpawn(1) then
				local h = 14
				local pillar = VFX.part({ Shape = Enum.PartType.Cylinder, Color = rgb(255, 230, 140), Transparency = 0.3,
					Size = Vector3.new(h, 1.8, 1.8), CFrame = CFrame.new(tg + UP * h / 2) * CFrame.Angles(0, 0, math.pi / 2) })
				VFX.fadeOut(pillar, 0.6, { Size = Vector3.new(h, 0.1, 0.1) })
			end
			VFX.emit(tg + UP * 2, 10, { Color = rgb(255, 235, 140), Speed = nr(3, 7), Lifetime = nr(0.5, 0.9), Size = ns(0.5, 0), Acceleration = UP * 8 })
		end)
	end
end

-- 🌩️ Thunderstorm: зарядка на башне, удары — отдельными событиями ThunderStrike
FX.Thunderstorm = function(p)
	VFX.burst(p.origin + UP, 3, rgb(120, 230, 255), 0.35, 0.3)
	VFX.flash(p.origin, rgb(120, 230, 255), 6, 20, 0.5)
end
FX.ThunderStrike = function(p)
	local pts = p.points or {}
	if #pts == 0 then return end
	local first = pts[1]
	local sky = first + Vector3.new(math.random(-6, 6), 45, math.random(-6, 6))
	VFX.bolt(sky, first, rgb(140, 235, 255), 0.6, 0.25)
	VFX.bolt(sky, first, rgb(255, 255, 255), 0.22, 0.2)
	VFX.burst(first, 3, rgb(140, 235, 255), 0.25, 0.2)
	VFX.ring(VFX.ground(first), 5, rgb(140, 235, 255), 0.35, 0.6)
	VFX.flash(first, rgb(140, 235, 255), 7, 22, 0.25)
	VFX.shake(first, 0.6)
	for i = 2, #pts do
		task.delay((i - 1) * 0.05, function()
			VFX.bolt(pts[i - 1], pts[i], rgb(140, 235, 255), 0.3, 0.2)
			VFX.burst(pts[i], 1.6, rgb(140, 235, 255), 0.18, 0.3)
		end)
	end
end

-- 🕳️ Black Hole
FX.BlackHole = function(p)
	local center = p.center + UP * 1.5
	local duration = p.duration or 3
	if not VFX.canSpawn(2) then return end
	local core = VFX.part({ Shape = Enum.PartType.Ball, Material = Enum.Material.SmoothPlastic, Color = rgb(8, 0, 16),
		Size = Vector3.one * 0.5, Position = center })
	VFX.tween(core, 0.3, { Size = Vector3.one * 5 }, Enum.EasingStyle.Back)
	local shell = VFX.part({ Shape = Enum.PartType.Ball, Color = rgb(130, 40, 220), Transparency = 0.75,
		Size = Vector3.one * p.radius * 2, Position = center })
	-- частицы затягиваются внутрь (отрицательная скорость)
	VFX.emitter(shell, { Color = rgb(200, 120, 255), Color2 = rgb(90, 20, 160), Rate = 60, Speed = nr(-14, -8),
		Lifetime = nr(0.5, 0.8), Size = ns(0.6, 0.1) })
	VFX.tween(shell, duration, { Size = Vector3.one * 3, Transparency = 0.9 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local g = VFX.ground(p.center)
	for k = 0, math.floor(duration / 0.6) do
		task.delay(k * 0.6, function() VFX.ring(g, p.radius, rgb(150, 60, 230), 0.6, 0.6) end)
	end
	VFX.release(core, duration + 0.1)
	VFX.release(shell, duration + 0.1)
end
FX.BlackHoleCollapse = function(p)
	local center = p.center + UP * 1.5
	VFX.burst(center, p.radius * 0.8, rgb(200, 120, 255), 0.3, 0.2)
	VFX.ring(VFX.ground(p.center), p.radius * 1.4, rgb(150, 60, 230), 0.5, 1.6)
	VFX.emit(center, 24, { Color = rgb(220, 150, 255), Color2 = rgb(110, 30, 200), Speed = nr(14, 26), Lifetime = nr(0.3, 0.6), Size = ns(0.7, 0) })
	VFX.flash(center, rgb(150, 60, 230), 7, p.radius * 3, 0.45)
	VFX.shake(center, 1.1)
end

-- 💀 Reap
FX.Reap = function(p)
	local g = VFX.ground(p.center)
	VFX.ring(g, p.radius, rgb(255, 40, 70), 0.45, 2.2)
	task.delay(0.08, function() VFX.ring(g, p.radius * 0.85, rgb(110, 0, 25), 0.45, 1.2) end)
	for _, h in ipairs(p.hits or {}) do
		VFX.burst(h, 1.8, rgb(255, 40, 70), 0.25, 0.3)
	end
	for i, k in ipairs(p.kills or {}) do
		VFX.burst(k, 2.6, rgb(255, 40, 70), 0.3, 0.1)
		VFX.popText(k + UP * 3, "REAPED", rgb(255, 60, 90), 22, 0.9)
		task.delay(0.1 + i * 0.03, function()
			VFX.projectile(k, towerTop(p), { Shape = Enum.PartType.Ball, Size = Vector3.one * 0.7, Color = rgb(255, 50, 80),
				Speed = 45, TrailColor = rgb(255, 120, 150), TrailWidth = 0.3, TrailLife = 0.3 })
		end)
	end
	VFX.shake(p.center, 0.7)
end

-- 👹 навыки боссов
FX.BossSummon = function(p)
	local g = VFX.ground(p.center)
	if VFX.canSpawn(1) then
		local d = VFX.disc(g, 1, rgb(40, 0, 60), 0.3)
		VFX.tween(d, 0.3, { Size = Vector3.new(0.15, 12, 12) })
		VFX.fadeOut(d, 1.1)
	end
	VFX.ring(g, 7, rgb(170, 40, 230), 0.6, 1)
	smoke(g + UP, rgb(130, 40, 220), 16)
end

FX.BossDisable = function(p)
	local g = VFX.ground(p.center)
	VFX.ring(g, 45, rgb(150, 60, 230), 0.8, 2)
	VFX.flash(p.center, rgb(150, 60, 230), 6, 30, 0.5)
	for _, tp in ipairs(p.towers or {}) do
		VFX.bolt(p.center + UP * 3, tp + UP * 2, rgb(170, 70, 255), 0.35, 0.4)
		VFX.popText(tp + UP * 5, "DISABLED!", rgb(190, 110, 255), 22, 1.2)
	end
	VFX.shake(p.center, 0.9)
end

FX.BossWarCry = function(p)
	local g = VFX.ground(p.center)
	VFX.ring(g, p.radius, rgb(255, 70, 50), 0.6, 1.5)
	task.delay(0.12, function() VFX.ring(g, p.radius * 0.7, rgb(255, 160, 80), 0.5, 0.8) end)
	VFX.popText(p.center + UP * 7, "WAR CRY!", rgb(255, 90, 60), 28, 1.2)
	VFX.shake(p.center, 0.8)
end

FX.BossRegenerate = function(p)
	VFX.ring(VFX.ground(p.center), 8, rgb(120, 255, 120), 0.6, 1)
	VFX.emit(p.center, 16, { Color = rgb(150, 255, 150), Speed = nr(3, 7), Lifetime = nr(0.6, 1), Size = ns(0.6, 0), Acceleration = UP * 8 })
	VFX.popText(p.center + UP * 7, "+HP", rgb(130, 255, 130), 26, 1)
end

fxEvent.OnClientEvent:Connect(function(p)
	if typeof(p) ~= "table" or typeof(p.id) ~= "string" then return end
	-- надпись над башней при касте способности игрока
	if p.name and p.tower then
		VFX.popText(towerTop(p), string.upper(p.name) .. "!", rgb(255, 230, 120), 24, 1.2)
	end
	local fn = FX[p.id]
	if fn then
		local ok, err = pcall(fn, p)
		if not ok then warn("[CombatVFX] " .. p.id .. ": " .. tostring(err)) end
	end
end)
