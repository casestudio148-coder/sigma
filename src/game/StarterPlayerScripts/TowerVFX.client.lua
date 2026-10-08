-- StarterPlayer.StarterPlayerScripts.TowerVFX (LocalScript)
-- Все эффекты башен рисуются здесь, на клиенте:
--   • тематичный удар для каждого юнита (событие TowerFX от сервера)
--   • эффект появления при постановке башни (у Некроманта — призыв, у Паладина — луч света)
--   • статусы мобов: замедление, заморозка, оглушение, яд
--   • «пуф» и «+монеты» при смерти моба

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local TowerData = require(ReplicatedStorage:WaitForChild("TowerData"))
local UpgradeData = require(ReplicatedStorage:WaitForChild("UpgradeData"))
local RarityData = require(ReplicatedStorage:WaitForChild("RarityData"))
local MobData = require(ReplicatedStorage:WaitForChild("MobData"))
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))
local fxEvent = ReplicatedStorage:WaitForChild("TowerFX")
local towersFolder = workspace:WaitForChild("Towers")
local mobsFolder = workspace:WaitForChild("Mobs")

local fxFolder = Instance.new("Folder")
fxFolder.Name = "ClientFX"
fxFolder.Parent = workspace

local MAX_FX_PARTS = 450 -- защита от лагов: при перегрузе новые эффекты пропускаются
local fxCount = 0         -- сколько деталей эффектов сейчас в мире (без GetChildren на каждый удар)
fxFolder.ChildAdded:Connect(function() fxCount += 1 end)
fxFolder.ChildRemoved:Connect(function() fxCount -= 1 end)
local UP = Vector3.new(0, 1, 0)

local TEX = {
	Sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	Fire = "rbxasset://textures/particles/fire_main.dds",
	Smoke = "rbxasset://textures/particles/smoke_main.dds",
}

local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end
local function ns(a, b) return NumberSequence.new(a, b) end
local function nr(a, b) return NumberRange.new(a, b) end

local C = {
	White = rgb(255, 255, 255), Gold = rgb(255, 210, 80), Holy = rgb(255, 235, 150),
	Arcane = rgb(190, 90, 255), Pink = rgb(255, 120, 220),
	Ice = rgb(150, 225, 255), IceDeep = rgb(70, 160, 255),
	Toxic = rgb(120, 240, 80),
	Fire = rgb(255, 140, 40), Ember = rgb(255, 220, 90), Smoke = rgb(70, 70, 75),
	Necro = rgb(150, 70, 230), Soul = rgb(120, 255, 170), Bone = rgb(235, 230, 205),
	Steel = rgb(190, 195, 205), Bolt = rgb(120, 230, 255),
	Void = rgb(130, 40, 220), Blood = rgb(255, 40, 70), Shadow = rgb(90, 40, 140),
}

---------------------------------------------------------------- базовые помощники

local function tween(obj, t, goal, style, dir)
	local tw = TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goal)
	tw:Play()
	return tw
end

local function part(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Size = Vector3.new(1, 1, 1)
	if props.Shape then p.Shape = props.Shape end
	for k, v in pairs(props) do
		if k ~= "Shape" then p[k] = v end
	end
	p.Parent = fxFolder
	return p
end

local function fadeOut(p, t, goal)
	goal = goal or {}
	goal.Transparency = 1
	tween(p, t, goal)
	Debris:AddItem(p, t + 0.05)
end

local function makeEmitter(parent, cfg)
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = cfg.Texture or TEX.Sparkle
	local c1 = cfg.Color or C.White
	pe.Color = ColorSequence.new(c1, cfg.Color2 or c1)
	pe.LightEmission = cfg.LightEmission or 1
	pe.LightInfluence = 0
	pe.Size = cfg.Size or ns(0.6, 0)
	pe.Transparency = cfg.Transparency or ns(0, 1)
	pe.Lifetime = cfg.Lifetime or nr(0.3, 0.6)
	pe.Speed = cfg.Speed or nr(8, 16)
	pe.SpreadAngle = cfg.Spread or Vector2.new(180, 180)
	pe.Acceleration = cfg.Acceleration or Vector3.zero
	pe.Drag = cfg.Drag or 0
	pe.Rotation = nr(0, 360)
	pe.RotSpeed = cfg.RotSpeed or nr(-120, 120)
	pe.Rate = cfg.Rate or 0
	pe.Enabled = (cfg.Rate or 0) > 0
	pe.Parent = parent
	return pe
end

local function emit(pos, count, cfg)
	local a = part({ Transparency = 1, Size = Vector3.one * 0.2, Position = pos })
	makeEmitter(a, cfg):Emit(count)
	Debris:AddItem(a, ((cfg.Lifetime and cfg.Lifetime.Max) or 0.6) + 0.1)
end

local function burst(pos, radius, color, t, startTransparency)
	local s = part({ Shape = Enum.PartType.Ball, Color = color, Transparency = startTransparency or 0.2, Size = Vector3.one * 0.5, Position = pos })
	fadeOut(s, t or 0.3, { Size = Vector3.one * radius * 2 })
end

-- плоское расширяющееся кольцо на земле
local function ring(pos, radius, color, t, width)
	t = t or 0.4
	local a = part({ Transparency = 1, Size = Vector3.one * 0.2, CFrame = CFrame.new(pos) * CFrame.Angles(-math.pi / 2, 0, 0) })
	local c = Instance.new("CylinderHandleAdornment")
	c.Adornee = a
	c.Color3 = color
	c.Height = 0.12
	c.Radius = 0.5
	c.InnerRadius = 0.2
	c.Transparency = 0.05
	c.Parent = a
	local w = width or 0.6
	tween(c, t, { Radius = radius, InnerRadius = math.max(radius - w, 0), Transparency = 1 })
	Debris:AddItem(a, t + 0.05)
end

local function flash(pos, color, brightness, range, t)
	t = t or 0.3
	local a = part({ Transparency = 1, Size = Vector3.one * 0.2, Position = pos })
	local l = Instance.new("PointLight")
	l.Color = color
	l.Brightness = brightness or 3
	l.Range = range or 12
	l.Parent = a
	tween(l, t, { Brightness = 0 })
	Debris:AddItem(a, t + 0.05)
end

-- надпись над точкой в мультяшном стиле; iconName — картинка слева (например "coin")
local function popText(pos, text, color, size, iconName)
	local a = part({ Transparency = 1, Size = Vector3.one * 0.2, Position = pos })
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(260, 56)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 220
	bb.Parent = a
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.fromScale(1, 1)
	row.Parent = bb
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row
	local img
	if iconName and UIKit.IconsReady then
		img = UIKit.icon(row, iconName, { Size = UDim2.fromOffset((size or 24) + 12, (size or 24) + 12), LayoutOrder = 1 })
	end
	local l = UIKit.text(row, {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		Font = UIKit.Font.Title,
		TextSize = size or 24,
		TextColor3 = color,
		Text = text,
		LayoutOrder = 2,
	})
	local st = l:FindFirstChildOfClass("UIStroke")
	local sc = Instance.new("UIScale")
	sc.Scale = 0.3
	sc.Parent = row
	tween(sc, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)
	tween(a, 0.9, { Position = pos + UP * 2.5 })
	local fade = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.5)
	TweenService:Create(l, fade, { TextTransparency = 1 }):Play()
	if st then TweenService:Create(st, fade, { Transparency = 1 }):Play() end
	if img then TweenService:Create(img, fade, { ImageTransparency = 1 }):Play() end
	Debris:AddItem(a, 1)
end

-- лёгкая тряска камеры от сильных ударов рядом
local shakePower = 0
local function shake(pos, power)
	if player:GetAttribute("Set_Shake") == false then return end
	local cam = workspace.CurrentCamera
	if not cam then return end
	local d = (cam.CFrame.Position - pos).Magnitude
	if d < 90 then
		shakePower = math.max(shakePower, power * (1 - d / 90))
	end
end
RunService:BindToRenderStep("TowerFXShake", Enum.RenderPriority.Camera.Value + 1, function(dt)
	if shakePower > 0.01 then
		local cam = workspace.CurrentCamera
		local s = shakePower * 0.04
		cam.CFrame = cam.CFrame * CFrame.Angles((math.random() - 0.5) * s, (math.random() - 0.5) * s, 0)
		shakePower *= math.exp(-dt * 10)
	end
end)

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local function ground(pos)
	local ignore = { mobsFolder, fxFolder, towersFolder }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(ignore, p.Character) end
	end
	rayParams.FilterDescendantsInstances = ignore
	local r = workspace:Raycast(pos + UP * 2, Vector3.new(0, -30, 0), rayParams)
	return r and (r.Position + UP * 0.1) or (pos - UP * 2.8)
end

local function flatDir(a, b)
	local d = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	if d.Magnitude < 0.01 then return Vector3.new(0, 0, -1) end
	return d.Unit
end

---------------------------------------------------------------- снаряды, молнии, взмахи

local function stopChildren(p)
	for _, d in ipairs(p:GetChildren()) do
		if d:IsA("ParticleEmitter") or d:IsA("PointLight") or d:IsA("Trail") then
			d.Enabled = false
		end
	end
end

local function projectile(from, to, cfg, onHit)
	local dist = (to - from).Magnitude
	if dist < 0.1 then
		if onHit then onHit(to) end
		return
	end
	local t = math.clamp(dist / (cfg.Speed or 100), 0.05, 0.6)
	local dir = (to - from).Unit

	local p = part({
		Shape = cfg.Shape,
		Size = cfg.Size or Vector3.one * 0.6,
		Color = cfg.Color or C.White,
		Material = cfg.Material or Enum.Material.Neon,
		Transparency = cfg.Transparency or 0,
		CFrame = CFrame.lookAt(from, to),
	})

	if cfg.Trail ~= false then
		local w = cfg.TrailWidth or 0.25
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, w, 0)
		a0.Parent = p
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -w, 0)
		a1.Parent = p
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Color = ColorSequence.new(cfg.TrailColor or cfg.Color or C.White)
		trail.Transparency = ns(0.1, 1)
		trail.WidthScale = ns(1, 0)
		trail.Lifetime = cfg.TrailLife or 0.18
		trail.LightEmission = 1
		trail.FaceCamera = true
		trail.Parent = p
	end
	if cfg.Light then
		local l = Instance.new("PointLight")
		l.Color = cfg.Color or C.White
		l.Range = 8
		l.Brightness = 2
		l.Parent = p
	end
	if cfg.Emitter then makeEmitter(p, cfg.Emitter) end

	tween(p, t, { CFrame = CFrame.lookAt(to, to + dir) }, Enum.EasingStyle.Linear)
	task.delay(t, function()
		p.Transparency = 1
		for _, d in ipairs(p:GetChildren()) do
			if d:IsA("ParticleEmitter") or d:IsA("PointLight") then d.Enabled = false end
		end
		Debris:AddItem(p, math.max(cfg.TrailLife or 0.18, 0.5))
		if onHit then onHit(to) end
	end)
end

-- снаряд по дуге (бомбы, черепа, души)
local function lob(from, to, height, time, cfg, onHit)
	local p = part({
		Shape = cfg.Shape,
		Size = cfg.Size or Vector3.one * 0.8,
		Color = cfg.Color or C.White,
		Material = cfg.Material or Enum.Material.Neon,
		Position = from,
	})
	if cfg.Light then
		local l = Instance.new("PointLight")
		l.Color = cfg.Color or C.White
		l.Range = 8
		l.Brightness = 2
		l.Parent = p
	end
	if cfg.Emitter then makeEmitter(p, cfg.Emitter) end

	local start = os.clock()
	local conn
	conn = RunService.Heartbeat:Connect(function()
		local a = math.min((os.clock() - start) / time, 1)
		local pos = from:Lerp(to, a) + UP * (4 * height * a * (1 - a))
		p.CFrame = CFrame.new(pos) * CFrame.Angles(a * 9, a * 6, 0)
		if a >= 1 then
			conn:Disconnect()
			p.Transparency = 1
			stopChildren(p)
			Debris:AddItem(p, 0.6)
			if onHit then onHit(to) end
		end
	end)
end

local function bolt(a, b, color, width, life)
	local dist = (b - a).Magnitude
	if dist < 0.2 then return end
	local segs = math.clamp(math.floor(dist / 3), 3, 12)
	local prev = a
	for i = 1, segs do
		local point = a:Lerp(b, i / segs)
		if i < segs then
			point += Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 2.4
		end
		local len = (point - prev).Magnitude
		if len > 0.05 then
			local seg = part({ Size = Vector3.new(width, width, len), Color = color, CFrame = CFrame.lookAt(prev, point) * CFrame.new(0, 0, -len / 2) })
			fadeOut(seg, life)
		end
		prev = point
	end
end

-- светящийся полумесяц-взмах (меч, коса, кинжалы). tilt поворачивает плоскость удара
local function slash(center, dir, radius, color, arcDeg, tilt, life, width, segments)
	segments = segments or 10
	local base = CFrame.lookAt(center, center + dir) * CFrame.Angles(0, 0, tilt or 0)
	local segLen = radius * math.rad(arcDeg) / segments * 1.3
	for i = 0, segments - 1 do
		local f = i / (segments - 1)
		local ang = math.rad(arcDeg * (f - 0.5))
		local w = (width or 0.8) * math.sin(math.pi * f) + 0.06
		task.delay(f * 0.07, function()
			local p = part({ Size = Vector3.new(segLen, 0.08, w), Color = color, CFrame = base * CFrame.Angles(0, -ang, 0) * CFrame.new(0, 0, -radius) })
			fadeOut(p, life or 0.2, { Size = Vector3.new(segLen, 0.04, w * 0.3) })
		end)
	end
end

local function critFX(pos)
	burst(pos, 2.2, C.Gold, 0.25, 0.3)
	emit(pos, 14, { Color = C.Gold, Color2 = C.White, Speed = nr(12, 22), Lifetime = nr(0.2, 0.4), Size = ns(0.5, 0) })
	popText(pos + UP * 2.5, "CRIT!", C.Gold, 26, "explosion")
end

local function iceSpikes(g, count, radius)
	for i = 1, count do
		local ang = i / count * math.pi * 2 + math.random() * 0.5
		local r = radius * (0.5 + math.random() * 0.6)
		local base = g + Vector3.new(math.cos(ang) * r, 0, math.sin(ang) * r)
		local h = 1.4 + math.random() * 1.4
		local rot = CFrame.Angles(math.rad(math.random(-20, 20)), math.rad(45), math.rad(math.random(-20, 20)))
		local spike = part({ Material = Enum.Material.Glass, Color = C.Ice, Transparency = 0.2, Size = Vector3.new(0.5, 0.1, 0.5), CFrame = CFrame.new(base) * rot })
		tween(spike, 0.12, { Size = Vector3.new(0.5, h, 0.5), CFrame = CFrame.new(base) * rot * CFrame.new(0, h / 2, 0) }, Enum.EasingStyle.Back)
		task.delay(0.45 + math.random() * 0.15, function()
			if spike.Parent then fadeOut(spike, 0.2, { Size = Vector3.new(0.1, h * 0.3, 0.1) }) end
		end)
	end
end

-- костяные руки, вылезающие из земли
local function boneHands(g, count, radius)
	for i = 1, count do
		local ang = i / count * math.pi * 2 + math.random()
		local base = g + Vector3.new(math.cos(ang) * radius, 0, math.sin(ang) * radius)
		local hand = CFrame.lookAt(base, Vector3.new(g.X, base.Y, g.Z)) * CFrame.Angles(math.rad(25), 0, 0)
		for f = -1, 1 do
			local start = hand * CFrame.new(f * 0.3, -1.4, 0) * CFrame.Angles(0, 0, math.rad(f * 12))
			local finger = part({ Material = Enum.Material.SmoothPlastic, Color = C.Bone, Size = Vector3.new(0.22, 1.8, 0.22), CFrame = start })
			local risen = start * CFrame.new(0, 2.2, 0)
			tween(finger, 0.18, { CFrame = risen }, Enum.EasingStyle.Back)
			task.delay(0.55, function()
				if finger.Parent then fadeOut(finger, 0.25, { CFrame = start }) end
			end)
		end
	end
end

local function holyPillar(g, width, height)
	local cf = CFrame.new(g + UP * height / 2) * CFrame.Angles(0, 0, math.pi / 2)
	local outer = part({ Shape = Enum.PartType.Cylinder, Color = C.Holy, Transparency = 0.25, Size = Vector3.new(height, width, width), CFrame = cf })
	fadeOut(outer, 0.5, { Size = Vector3.new(height, 0.1, 0.1) })
	local core = part({ Shape = Enum.PartType.Cylinder, Color = C.White, Transparency = 0.05, Size = Vector3.new(height, width * 0.4, width * 0.4), CFrame = cf })
	fadeOut(core, 0.35, { Size = Vector3.new(height, 0.05, 0.05) })
end

local function debrisChunks(pos, count, color)
	for _ = 1, count do
		local p = part({ Material = Enum.Material.Slate, Color = color, Size = Vector3.one * (0.3 + math.random() * 0.4), Position = pos, Anchored = false })
		p.AssemblyLinearVelocity = Vector3.new(math.random(-20, 20), math.random(18, 32), math.random(-20, 20))
		p.AssemblyAngularVelocity = Vector3.new(math.random(-10, 10), math.random(-10, 10), math.random(-10, 10))
		Debris:AddItem(p, 0.8)
	end
end

local function explosion(p, r)
	local g = ground(p)
	local core = part({ Shape = Enum.PartType.Ball, Color = C.Ember, Size = Vector3.one, Position = p, Transparency = 0 })
	fadeOut(core, 0.25, { Size = Vector3.one * r * 1.2 })
	local fire = part({ Shape = Enum.PartType.Ball, Color = C.Fire, Size = Vector3.one * 1.5, Position = p, Transparency = 0.15 })
	fadeOut(fire, 0.4, { Size = Vector3.one * r * 2 })
	ring(g, r * 1.5, C.Ember, 0.45, 1.2)
	emit(p, 20, { Texture = TEX.Fire, Color = C.Ember, Color2 = C.Fire, Speed = nr(8, 18), Lifetime = nr(0.3, 0.6), Size = ns(2.5, 0.5), Drag = 3 })
	emit(p, 14, {
		Texture = TEX.Smoke, Color = C.Smoke, Color2 = rgb(40, 40, 40), LightEmission = 0,
		Speed = nr(3, 8), Lifetime = nr(0.9, 1.6), Size = ns(2, 5),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }),
		Acceleration = UP * 4, Drag = 1.5,
	})
	debrisChunks(p, 7, rgb(60, 50, 45))
	flash(p, C.Fire, 6, r * 3.5, 0.45)
	shake(p, 1)
end

---------------------------------------------------------------- поворот и выпад башни к цели

local basePivots = setmetatable({}, { __mode = "k" })
local tokens = setmetatable({}, { __mode = "k" })
local auraPulse = setmetatable({}, { __mode = "k" })

-- «Домашняя» позиция башни запоминается ОДИН раз, когда сервер закончил её ставить (атрибут Ready).
-- Раньше она бралась в момент атаки — посреди выпада, и модель застревала в позе удара.
local function trackTower(tower)
	local function capture()
		if tower.Parent and tower:GetAttribute("Ready") and not basePivots[tower] then
			basePivots[tower] = tower:GetPivot()
		end
	end
	tower:GetAttributeChangedSignal("Ready"):Connect(capture)
	capture()
end

local function animateTower(tower, targetPos, lunge)
	if not tower or not tower.Parent or not targetPos then return end
	local base = basePivots[tower]
	if not base then return end -- башня ещё не встала: не трогаем модель
	local pos = base.Position
	local dir = flatDir(pos, targetPos)
	local facing = CFrame.lookAt(pos, pos + dir)

	local token = (tokens[tower] or 0) + 1
	tokens[tower] = token

	local cv = Instance.new("CFrameValue")
	cv.Value = tower:GetPivot()
	cv.Changed:Connect(function(v)
		if tokens[tower] == token and tower.Parent then
			tower:PivotTo(v)
		end
	end)

	if lunge and lunge > 0 then
		tween(cv, 0.08, { Value = facing + dir * lunge })
		task.delay(0.1, function()
			if tokens[tower] == token then tween(cv, 0.18, { Value = facing }) end
		end)
	else
		tween(cv, 0.12, { Value = facing })
	end
	-- страховка: в конце анимации башня точно возвращается домой
	task.delay(0.4, function()
		if tokens[tower] == token and tower.Parent then
			tower:PivotTo(facing)
		end
		cv:Destroy()
	end)
end

---------------------------------------------------------------- УДАРЫ ЮНИТОВ

local FX = {}

-- Scout: двойной быстрый взмах клинком
FX.Scout = function(fx)
	local hit = fx.hits[1]
	animateTower(fx.tower, hit, 1.4)
	local dir = flatDir(fx.origin, hit)
	local col = fx.crit and C.Gold or rgb(225, 240, 255)
	slash(hit - dir * 2, dir, 2.4, col, 130, math.rad(20), 0.18, 0.7)
	task.delay(0.08, function()
		slash(hit - dir * 2, dir, 2.4, col, 130, math.rad(-20), 0.18, 0.7)
	end)
	emit(hit, 8, { Color = col, Speed = nr(10, 18), Lifetime = nr(0.12, 0.28), Size = ns(0.35, 0) })
	if fx.crit then critFX(hit) end
end

-- Archer: залп стрел со следом, щепки при попадании
FX.Archer = function(fx)
	animateTower(fx.tower, fx.hits[1], 0)
	for i, hit in ipairs(fx.hits) do
		task.delay((i - 1) * 0.06, function()
			projectile(fx.origin, hit, {
				Size = Vector3.new(0.12, 0.12, 1.8), Color = rgb(150, 100, 50), Material = Enum.Material.Wood,
				Speed = 140, TrailColor = rgb(255, 250, 220), TrailWidth = 0.08, TrailLife = 0.12,
			}, function(p)
				emit(p, 6, { Color = rgb(170, 120, 70), LightEmission = 0, Speed = nr(6, 12), Lifetime = nr(0.2, 0.35), Size = ns(0.25, 0), Acceleration = Vector3.new(0, -40, 0) })
				burst(p, 1.1, rgb(255, 245, 210), 0.15, 0.4)
				if fx.splash then
					-- 4-й тир: взрывные стрелы
					burst(p, fx.splash * 0.8, C.Fire, 0.25, 0.3)
					ring(ground(p), fx.splash, rgb(255, 170, 60), 0.3, 0.6)
				end
			end)
		end)
	end
end

-- Spearman: золотой выпад копья насквозь через линию врагов
FX.Spearman = function(fx)
	local hit = fx.hits[1]
	animateTower(fx.tower, hit, 2)
	local dir = flatDir(fx.origin, hit)
	local from = Vector3.new(fx.origin.X, hit.Y, fx.origin.Z) + dir
	local endPos = fx.pierceEnd or (hit + dir * 4)
	local to = Vector3.new(endPos.X, hit.Y, endPos.Z)
	local len = (to - from).Magnitude

	if len > 0.5 then
		local spear = part({ Size = Vector3.new(0.35, 0.35, 0.1), Color = C.Gold, CFrame = CFrame.lookAt(from, to) })
		tween(spear, 0.08, { Size = Vector3.new(0.35, 0.35, len), CFrame = CFrame.lookAt(from, to) * CFrame.new(0, 0, -len / 2) })
		task.delay(0.1, function() fadeOut(spear, 0.18, { Size = Vector3.new(0.05, 0.05, len) }) end)

		local tip = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.9, Color = C.White, Position = from })
		tween(tip, 0.08, { Position = to })
		task.delay(0.1, function() fadeOut(tip, 0.15) end)
	end

	local list = { hit }
	for _, p in ipairs(fx.pierceHits or {}) do table.insert(list, p) end
	for _, p in ipairs(list) do
		emit(p, 8, { Color = C.Gold, Color2 = C.White, Speed = nr(10, 18), Lifetime = nr(0.15, 0.3), Size = ns(0.35, 0) })
		burst(p, 1.2, C.White, 0.15, 0.35)
	end
	ring(ground(hit), 3.5, C.Gold, 0.3, 0.5)
end

-- Mage: арканный шар, фиолетовый магический взрыв
FX.Mage = function(fx, cfg)
	animateTower(fx.tower, fx.hits[1], 0)
	burst(fx.origin + UP, 1.5, C.Arcane, 0.2, 0.3)
	projectile(fx.origin + UP * 0.5, fx.hits[1], {
		Shape = Enum.PartType.Ball, Size = Vector3.one * 1.1, Color = C.Arcane, Speed = 75, Light = true,
		TrailColor = C.Pink, TrailWidth = 0.4, TrailLife = 0.25,
		Emitter = { Color = C.Pink, Color2 = C.Arcane, Rate = 40, Speed = nr(1, 3), Lifetime = nr(0.2, 0.4), Size = ns(0.4, 0) },
	}, function(p)
		local r = cfg.Splash or 6
		burst(p, r, C.Arcane, 0.3, 0.35)
		burst(p, r * 0.5, C.Pink, 0.2, 0.1)
		ring(ground(p), r * 1.1, C.Pink, 0.4, 0.7)
		emit(p, 26, { Color = C.Pink, Color2 = C.Arcane, Speed = nr(10, 22), Lifetime = nr(0.3, 0.6), Size = ns(0.6, 0), Drag = 4 })
		flash(p, C.Arcane, 4, r * 2.5, 0.35)
	end)
end

-- IceMage: ледяной осколок, морозное кольцо и ледяные шипы из земли
FX.IceMage = function(fx)
	local hit = fx.hits[1]
	animateTower(fx.tower, hit, 0)
	projectile(fx.origin + UP * 0.5, hit, {
		Size = Vector3.new(0.45, 0.45, 1.6), Color = C.Ice, Material = Enum.Material.Glass, Transparency = 0.15,
		Speed = 85, TrailColor = C.Ice, TrailWidth = 0.3, Light = true,
		Emitter = { Color = C.White, Color2 = C.Ice, Rate = 30, Speed = nr(0.5, 2), Lifetime = nr(0.3, 0.5), Size = ns(0.3, 0) },
	}, function(p)
		local g = ground(p)
		ring(g, 4.5, C.Ice, 0.45, 0.9)
		burst(p, 2.6, C.Ice, 0.25, 0.3)
		iceSpikes(g, 6, 2.2)
		emit(p, 18, { Color = C.White, Color2 = C.Ice, Speed = nr(6, 14), Lifetime = nr(0.4, 0.8), Size = ns(0.4, 0), Acceleration = Vector3.new(0, -12, 0), Drag = 2 })
		flash(p, C.IceDeep, 3, 10, 0.3)
	end)
end

-- DartSpitter: ядовитый дротик, зелёные брызги и лужа яда
FX.DartSpitter = function(fx)
	local hit = fx.hits[1]
	animateTower(fx.tower, hit, 0)
	projectile(fx.origin, hit, {
		Size = Vector3.new(0.12, 0.12, 0.9), Color = C.Toxic, Speed = 150,
		TrailColor = C.Toxic, TrailWidth = 0.1, TrailLife = 0.15,
	}, function(p)
		local g = ground(p)
		local puddle = part({ Shape = Enum.PartType.Cylinder, Color = rgb(80, 200, 60), Transparency = 0.35, Size = Vector3.new(0.05, 0.5, 0.5), CFrame = CFrame.new(g) * CFrame.Angles(0, 0, math.pi / 2) })
		tween(puddle, 0.15, { Size = Vector3.new(0.05, 3.2, 3.2) })
		task.delay(0.6, function()
			if puddle.Parent then fadeOut(puddle, 0.6) end
		end)
		emit(p, 10, { Color = C.Toxic, Color2 = rgb(200, 255, 120), Speed = nr(4, 9), Lifetime = nr(0.3, 0.6), Size = ns(0.45, 0), Acceleration = Vector3.new(0, -20, 0) })
		burst(p, 1.3, C.Toxic, 0.18, 0.35)
	end)
end

-- BomberTower: бомба с горящим фитилём по дуге, взрыв с огнём, дымом и обломками
FX.BomberTower = function(fx, cfg)
	local hit = fx.hits[1]
	animateTower(fx.tower, hit, 0)
	local t = math.clamp((hit - fx.origin).Magnitude / 60, 0.25, 0.45)
	lob(fx.origin + UP, hit, 6, t, {
		Shape = Enum.PartType.Ball, Size = Vector3.one * 1.4, Color = rgb(35, 35, 40), Material = Enum.Material.SmoothPlastic,
		Emitter = { Texture = TEX.Fire, Color = C.Ember, Color2 = C.Fire, Rate = 60, Speed = nr(1, 3), Lifetime = nr(0.15, 0.3), Size = ns(0.7, 0) },
	}, function(p)
		explosion(p, cfg.Splash or 9)
	end)
end

-- Necromancer: магический круг, призрачные черепа, костяные руки из земли
FX.Necromancer = function(fx)
	animateTower(fx.tower, fx.hits[1], 0)
	ring(ground(fx.origin), 4, C.Necro, 0.5, 0.6)
	emit(fx.origin, 12, { Texture = TEX.Fire, Color = C.Soul, Color2 = C.Necro, Speed = nr(2, 5), Lifetime = nr(0.4, 0.8), Size = ns(1, 0), Acceleration = UP * 8, Spread = Vector2.new(40, 40) })

	for i, hit in ipairs(fx.hits) do
		task.delay((i - 1) * 0.08, function()
			lob(fx.origin + UP, hit, 3, 0.35, {
				Shape = Enum.PartType.Ball, Size = Vector3.one * 0.9, Color = C.Soul, Light = true,
				Emitter = { Texture = TEX.Smoke, Color = C.Necro, Color2 = rgb(40, 10, 60), LightEmission = 0.4, Rate = 45, Speed = nr(0.5, 1.5), Lifetime = nr(0.3, 0.5), Size = ns(0.9, 0.2) },
			}, function(p)
				local g = ground(p)
				boneHands(g, 3, 1.4)
				ring(g, 3, C.Necro, 0.5, 0.6)
				emit(p, 14, { Texture = TEX.Fire, Color = C.Soul, Color2 = C.Necro, Speed = nr(3, 7), Lifetime = nr(0.5, 0.9), Size = ns(0.8, 0), Acceleration = UP * 10 })
				flash(p, C.Soul, 3, 10, 0.4)
			end)
		end)
	end
end

-- Assassin: рывок из тени, крестовой разрез кинжалами, казнь
FX.Assassin = function(fx)
	local hit = fx.hits[1]
	animateTower(fx.tower, hit, 2.5)
	emit(fx.origin, 10, { Texture = TEX.Smoke, Color = C.Shadow, Color2 = rgb(20, 10, 30), LightEmission = 0, Speed = nr(2, 5), Lifetime = nr(0.4, 0.7), Size = ns(1.5, 2.5) })
	local dir = flatDir(fx.origin, hit)
	local col = fx.crit and C.Blood or rgb(200, 140, 255)
	slash(hit - dir * 1.8, dir, 2.2, col, 120, math.rad(55), 0.2, 0.7)
	task.delay(0.06, function()
		slash(hit - dir * 1.8, dir, 2.2, col, 120, math.rad(-55), 0.2, 0.7)
	end)
	emit(hit, 10, { Texture = TEX.Smoke, Color = C.Shadow, LightEmission = 0.2, Speed = nr(3, 6), Lifetime = nr(0.3, 0.5), Size = ns(1, 2) })
	if fx.crit then critFX(hit) end
	for _, p in ipairs(fx.executes or {}) do
		burst(p, 3, C.Blood, 0.3, 0.2)
		popText(p + UP * 3, "EXECUTE!", C.Blood, 28, "scythe")
	end
end

-- CrossbowTower: скорострел — лёгкие быстрые болты (до 10 в секунду, поэтому эффект маленький)
local xbowAnim = {}
FX.CrossbowTower = function(fx)
	local hit = fx.hits[1]
	local now = os.clock()
	if fx.tower and now - (xbowAnim[fx.tower] or 0) > 0.3 then
		xbowAnim[fx.tower] = now
		animateTower(fx.tower, hit, 0)
	end
	local endPos = fx.pierceEnd or hit
	projectile(fx.origin, endPos, {
		Size = Vector3.new(0.14, 0.14, 1.4), Color = C.Steel, Material = Enum.Material.Metal,
		Speed = 260, TrailColor = rgb(170, 230, 255), TrailWidth = 0.08, TrailLife = 0.12,
	})
	emit(hit, 3, { Color = rgb(255, 220, 150), Color2 = C.Bolt, Speed = nr(12, 22), Lifetime = nr(0.1, 0.2), Size = ns(0.22, 0), Acceleration = Vector3.new(0, -50, 0) })
	for _, p in ipairs(fx.pierceHits or {}) do
		emit(p, 2, { Color = C.White, Color2 = C.Bolt, Speed = nr(10, 18), Lifetime = nr(0.1, 0.2), Size = ns(0.2, 0) })
	end
	if fx.crit then
		critFX(hit)
	end
end

-- Paladin: столб священного света с неба + пульс ауры вокруг паладина
FX.Paladin = function(fx, cfg)
	local hit = fx.hits[1]
	animateTower(fx.tower, hit, 1.2)
	local g = ground(hit)
	holyPillar(g, 2.6, 26)
	ring(g, 4.5, C.Gold, 0.45, 0.8)
	emit(hit, 18, { Color = C.Holy, Color2 = C.White, Speed = nr(4, 10), Lifetime = nr(0.5, 0.9), Size = ns(0.5, 0), Acceleration = UP * 10 })
	flash(hit, C.Holy, 5, 14, 0.45)

	if fx.tower then
		local last = auraPulse[fx.tower]
		if not last or os.clock() - last > 3 then
			auraPulse[fx.tower] = os.clock()
			ring(ground(fx.origin), cfg.AuraRange or 25, C.Gold, 0.9, 1.2)
		end
	end
end

-- LightningMage: ветвистая молния с цепью по врагам
FX.LightningMage = function(fx)
	local hit = fx.hits[1]
	animateTower(fx.tower, hit, 0)
	local start = fx.origin + UP * 1.5
	burst(start, 1.4, C.Bolt, 0.2, 0.3)

	local points = { hit }
	for _, p in ipairs(fx.chain or {}) do table.insert(points, p) end
	for i = 1, #points do
		local a = (i == 1) and start or points[i - 1]
		local b = points[i]
		task.delay((i - 1) * 0.05, function()
			bolt(a, b, C.Bolt, 0.32, 0.2)
			bolt(a, b, C.White, 0.1, 0.15)
			burst(b, 1.6, C.Bolt, 0.18, 0.3)
			emit(b, 8, { Color = C.White, Color2 = C.Bolt, Speed = nr(10, 20), Lifetime = nr(0.1, 0.25), Size = ns(0.3, 0) })
			flash(b, C.Bolt, 4, 12, 0.2)
		end)
	end
end

-- VoidLord: сфера пустоты, чёрная дыра схлопывается и взрывается
FX.VoidLord = function(fx, cfg)
	local hit = fx.hits[1]
	animateTower(fx.tower, hit, 0)
	projectile(fx.origin + UP, hit, {
		Shape = Enum.PartType.Ball, Size = Vector3.one * 1.6, Color = C.Void, Speed = 60, Light = true,
		TrailColor = C.Shadow, TrailWidth = 0.6, TrailLife = 0.3,
		Emitter = { Texture = TEX.Smoke, Color = C.Void, Color2 = rgb(20, 0, 40), LightEmission = 0.3, Rate = 50, Speed = nr(0.5, 2), Lifetime = nr(0.3, 0.5), Size = ns(1.2, 0) },
	}, function(p)
		local r = cfg.Splash or 10
		local hole = part({ Shape = Enum.PartType.Ball, Material = Enum.Material.SmoothPlastic, Color = rgb(10, 0, 20), Transparency = 0.05, Size = Vector3.one * 0.5, Position = p })
		tween(hole, 0.15, { Size = Vector3.one * r * 0.9 }, Enum.EasingStyle.Back)
		task.delay(0.18, function() fadeOut(hole, 0.25, { Size = Vector3.one * 0.2 }) end)

		local shell = part({ Shape = Enum.PartType.Ball, Color = C.Void, Transparency = 0.4, Size = Vector3.one * r * 2.2, Position = p })
		fadeOut(shell, 0.35, { Size = Vector3.one * 0.5 })

		for _ = 1, 10 do
			local d = Vector3.new(math.random() - 0.5, math.random() * 0.6, math.random() - 0.5)
			if d.Magnitude < 0.05 then d = UP end
			local s = part({ Shape = Enum.PartType.Ball, Color = rgb(200, 120, 255), Size = Vector3.one * 0.4, Position = p + d.Unit * r })
			fadeOut(s, 0.3, { Position = p, Size = Vector3.one * 0.1 })
		end

		task.delay(0.35, function()
			ring(ground(p), r * 1.3, C.Void, 0.45, 1.5)
			burst(p, r * 0.6, rgb(200, 120, 255), 0.25, 0.3)
			flash(p, C.Void, 6, r * 3, 0.4)
			shake(p, 0.7)
		end)
	end)
	for _, p in ipairs(fx.executes or {}) do
		popText(p + UP * 3, "VOID!", C.Void, 24, "blackhole")
	end
end

-- SoulReaper: кровавый взмах косы, души убитых летят к жнецу
FX.SoulReaper = function(fx, cfg)
	local hit = fx.hits[1]
	animateTower(fx.tower, hit, 1.5)
	local o = Vector3.new(fx.origin.X, hit.Y, fx.origin.Z)
	local dir = flatDir(o, hit)
	local dist = math.max((Vector3.new(hit.X, 0, hit.Z) - Vector3.new(o.X, 0, o.Z)).Magnitude, 3)
	slash(o, dir, dist, C.Blood, 150, 0, 0.3, 1.8, 16)
	task.delay(0.05, function()
		slash(o, dir, dist * 0.85, rgb(90, 0, 25), 140, 0, 0.3, 0.9, 14)
	end)

	local r = cfg.Splash or 6
	burst(hit, r, C.Blood, 0.3, 0.45)
	ring(ground(hit), r * 1.2, C.Blood, 0.4, 0.8)
	emit(hit, 16, { Texture = TEX.Fire, Color = C.Blood, Color2 = rgb(60, 0, 20), Speed = nr(6, 14), Lifetime = nr(0.3, 0.6), Size = ns(1, 0) })
	flash(hit, C.Blood, 4, 14, 0.35)

	for _, k in ipairs(fx.kills or {}) do
		lob(k, fx.origin + UP * 2, 6, 0.55, {
			Shape = Enum.PartType.Ball, Size = Vector3.one * 0.7, Color = C.Blood, Light = true,
			Emitter = { Color = C.Blood, Color2 = C.Pink, Rate = 40, Speed = nr(0.5, 1), Lifetime = nr(0.3, 0.5), Size = ns(0.5, 0) },
		}, function(p)
			burst(p, 2, C.Blood, 0.25, 0.3)
			emit(p, 8, { Color = C.Blood, Speed = nr(4, 8), Lifetime = nr(0.2, 0.4), Size = ns(0.4, 0) })
		end)
	end
end

-- запасной вариант для новых юнитов без своего эффекта
FX.Default = function(fx)
	local hit = fx.hits[1]
	animateTower(fx.tower, hit, 0)
	projectile(fx.origin, hit, { Shape = Enum.PartType.Ball, Size = Vector3.one * 0.6, Color = C.White, Speed = 100 }, function(p)
		burst(p, 1.5, C.White, 0.2, 0.3)
	end)
end

fxEvent.OnClientEvent:Connect(function(fx)
	if typeof(fx) ~= "table" or typeof(fx.hits) ~= "table" or #fx.hits == 0 then return end
	if fxCount > MAX_FX_PARTS then return end
	local fn = FX[fx.name] or FX.Default
	local cfg = table.clone(TowerData[fx.name] or {})
	if fx.splash then cfg.Splash = fx.splash end -- радиус с учётом улучшений
	local ok, err = pcall(fn, fx, cfg)
	if not ok then
		warn("[TowerVFX] " .. tostring(fx.name) .. ": " .. tostring(err))
	end
end)

---------------------------------------------------------------- ПОЯВЛЕНИЕ БАШНИ

local RANK = { Common = 1, Rare = 2, Epic = 3, Legendary = 4, Mythic = 5 }

-- призыв Некроманта: тёмный портал, столбы душ, руки мертвецов
local function necroSummon(g)
	ring(g, 7, C.Necro, 0.8, 1.2)
	local disc = part({ Shape = Enum.PartType.Cylinder, Color = rgb(40, 10, 60), Transparency = 0.3, Size = Vector3.new(0.05, 1, 1), CFrame = CFrame.new(g) * CFrame.Angles(0, 0, math.pi / 2) })
	tween(disc, 0.3, { Size = Vector3.new(0.05, 12, 12) })
	task.delay(1, function()
		if disc.Parent then fadeOut(disc, 0.6) end
	end)

	for i = 1, 8 do
		local ang = i / 8 * math.pi * 2
		local pos = g + Vector3.new(math.cos(ang) * 5, 0, math.sin(ang) * 5)
		task.delay(i * 0.05, function()
			local pillar = part({ Color = C.Soul, Transparency = 0.2, Size = Vector3.new(0.5, 0.1, 0.5), CFrame = CFrame.new(pos) })
			tween(pillar, 0.25, { Size = Vector3.new(0.5, 6, 0.5), CFrame = CFrame.new(pos + UP * 3) })
			task.delay(0.35, function()
				if pillar.Parent then
					fadeOut(pillar, 0.3, { Size = Vector3.new(0.05, 8, 0.05), CFrame = CFrame.new(pos + UP * 4) })
				end
			end)
			emit(pos, 6, { Texture = TEX.Fire, Color = C.Soul, Color2 = C.Necro, Speed = nr(3, 6), Lifetime = nr(0.5, 0.9), Size = ns(1, 0), Acceleration = UP * 8, Spread = Vector2.new(25, 25) })
		end)
	end

	boneHands(g, 5, 3.5)
	emit(g + UP, 20, { Texture = TEX.Smoke, Color = C.Necro, Color2 = rgb(20, 0, 30), LightEmission = 0.2, Speed = nr(3, 8), Lifetime = nr(0.8, 1.4), Size = ns(2, 4) })
	flash(g + UP * 3, C.Necro, 6, 20, 1)
	popText(g + UP * 6, "ARISE!", C.Soul, 26, "skull")
	shake(g, 0.6)
end

-- ЗВУКИ ПОЯВЛЕНИЯ. Свои звуки: Toolbox → Audio → правый клик → Copy Asset ID → вставь как "rbxassetid://123".
local PLACE_SOUNDS = {
	Whoosh = { Id = "rbxasset://sounds/action_jump.mp3", Volume = 0.5, Speed = 1.4 },   -- юнит летит вниз
	Land = { Id = "rbxasset://sounds/action_jump_land.mp3", Volume = 0.9, Speed = 0.7 }, -- приземление
	Boom = { Id = "rbxasset://sounds/action_jump_land.mp3", Volume = 1, Speed = 0.42 },  -- тяжёлый удар (Legendary / Mythic)
	Magic = { Id = "", Volume = 0.8, Speed = 1 },                                        -- волшебный звон (Epic+) — вставь свой
}

local function sound3D(name, pos, speedMul)
	if player:GetAttribute("Set_Music") == false then return end
	local cfg = PLACE_SOUNDS[name]
	if not cfg or cfg.Id == "" then return end
	local a = part({ Transparency = 1, Size = Vector3.one * 0.2, Position = pos })
	local snd = Instance.new("Sound")
	snd.SoundId = cfg.Id
	snd.Volume = cfg.Volume
	snd.PlaybackSpeed = cfg.Speed * (speedMul or 1)
	snd.RollOffMaxDistance = 150
	snd.Parent = a
	snd:Play()
	Debris:AddItem(a, 3)
end

-- сужающийся круг-прицел на земле: «сюда сейчас приземлится»
local function targetRing(g, color, t)
	local a = part({ Transparency = 1, Size = Vector3.one * 0.2, CFrame = CFrame.new(g) * CFrame.Angles(-math.pi / 2, 0, 0) })
	local c = Instance.new("CylinderHandleAdornment")
	c.Adornee = a
	c.Color3 = color
	c.Height = 0.1
	c.Radius = 7
	c.InnerRadius = 6.3
	c.Transparency = 0.6
	c.Parent = a
	tween(c, t, { Radius = 2.2, InnerRadius = 1.7, Transparency = 0.05 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	Debris:AddItem(a, t + 0.05)
end

-- светящийся след падения с неба
local function fallStreak(g, top, color, t)
	local h = math.max(top - g.Y, 1)
	local streak = part({ Color = color, Transparency = 0.35, Size = Vector3.new(0.5, h, 0.5), CFrame = CFrame.new(g + UP * h / 2) })
	fadeOut(streak, t, { Size = Vector3.new(0.05, h, 0.05) })
	local core = part({ Color = C.White, Transparency = 0.1, Size = Vector3.new(0.18, h, 0.18), CFrame = CFrame.new(g + UP * h / 2) })
	fadeOut(core, t * 0.8, { Size = Vector3.new(0.02, h, 0.02) })
end

-- облако пыли по земле
local function dustRing(g, amount, color)
	emit(g + UP * 0.4, amount, {
		Texture = TEX.Smoke, Color = color or rgb(215, 205, 185), Color2 = rgb(160, 150, 135), LightEmission = 0,
		Speed = nr(9, 16), Lifetime = nr(0.5, 0.9), Size = ns(1.2, 3.4), Drag = 5,
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) }),
		Spread = Vector2.new(88, 180), Acceleration = Vector3.new(0, -3, 0),
	})
end

-- светящийся диск под юнитом
local function groundGlow(g, color, radius, t)
	local disc = part({ Shape = Enum.PartType.Cylinder, Color = color, Transparency = 0.25, Size = Vector3.new(0.06, 1, 1), CFrame = CFrame.new(g) * CFrame.Angles(0, 0, math.pi / 2) })
	tween(disc, 0.18, { Size = Vector3.new(0.06, radius * 2, radius * 2) })
	task.delay(0.2, function()
		if disc.Parent then fadeOut(disc, t or 0.6) end
	end)
end

-- светящиеся руны кружат вокруг юнита и улетают вверх (Epic+)
local function runeCircle(g, color, count, radius, time, rainbow)
	local runes = {}
	for i = 1, count do
		local r = part({ Color = color, Transparency = 0.15, Size = Vector3.new(0.6, 0.6, 0.6) })
		table.insert(runes, { p = r, a = i / count * math.pi * 2 })
	end
	local t0 = os.clock()
	local conn
	conn = RunService.Heartbeat:Connect(function()
		local t = os.clock() - t0
		if t > time then
			conn:Disconnect()
			for _, r in ipairs(runes) do
				if r.p.Parent then
					fadeOut(r.p, 0.35, { CFrame = r.p.CFrame + UP * 6, Size = Vector3.one * 0.1 })
				end
			end
			return
		end
		local k = t / time
		for i, r in ipairs(runes) do
			if r.p.Parent then
				local a = r.a + t * 5
				local rad = radius * (1 - 0.25 * k)
				r.p.CFrame = CFrame.new(g + Vector3.new(math.cos(a) * rad, 0.6 + k * 2.5, math.sin(a) * rad)) * CFrame.Angles(t * 4, t * 3, 0)
				if rainbow then
					r.p.Color = Color3.fromHSV((t * 0.8 + i / count) % 1, 0.7, 1)
				end
			end
		end
	end)
end

-- столб света с неба
local function skyBeam(g, color, width, height, t)
	local cf = CFrame.new(g + UP * height / 2) * CFrame.Angles(0, 0, math.pi / 2)
	local outer = part({ Shape = Enum.PartType.Cylinder, Color = color, Transparency = 0.3, Size = Vector3.new(height, 0.2, 0.2), CFrame = cf })
	tween(outer, 0.15, { Size = Vector3.new(height, width, width) })
	task.delay(0.2, function()
		if outer.Parent then fadeOut(outer, t, { Size = Vector3.new(height, 0.1, 0.1) }) end
	end)
	local core = part({ Shape = Enum.PartType.Cylinder, Color = C.White, Transparency = 0.05, Size = Vector3.new(height, 0.1, 0.1), CFrame = cf })
	tween(core, 0.15, { Size = Vector3.new(height, width * 0.35, width * 0.35) })
	task.delay(0.2, function()
		if core.Parent then fadeOut(core, t * 0.8, { Size = Vector3.new(height, 0.05, 0.05) }) end
	end)
end

-- юнит падает сверху и пружинит при приземлении (только на экране, сервер его не двигает)
local function dropIn(tower, base, height, time, onLand)
	local token = (tokens[tower] or 0) + 1
	tokens[tower] = token
	local cv = Instance.new("CFrameValue")
	cv.Value = base + UP * height
	tower:PivotTo(cv.Value)
	cv.Changed:Connect(function(v)
		if tokens[tower] == token and tower.Parent then
			tower:PivotTo(v)
		end
	end)
	tween(cv, time, { Value = base }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.delay(time, function()
		if tokens[tower] ~= token or not tower.Parent then
			cv:Destroy()
			return
		end
		onLand()
		-- пружинка
		tween(cv, 0.09, { Value = base + UP * 0.9 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		task.delay(0.09, function()
			if tokens[tower] == token then
				tween(cv, 0.12, { Value = base }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			end
			task.delay(0.15, function()
				if tokens[tower] == token and tower.Parent then
					tower:PivotTo(base)
				end
				cv:Destroy()
			end)
		end)
	end)
end

local RARITY_TEXT = { [3] = "EPIC!", [4] = "LEGENDARY!", [5] = "MYTHIC!" }

local function placeFX(tower)
	local base = basePivots[tower] or tower:GetPivot()
	local cf, size = tower:GetBoundingBox()
	local g = Vector3.new(cf.Position.X, cf.Position.Y - size.Y / 2 + 0.1, cf.Position.Z)
	local cfg = TowerData[tower.Name] or {}
	local rar = RarityData[cfg.Rarity or "Common"] or RarityData.Common
	local color = rar.Color
	local rank = RANK[cfg.Rarity] or 1
	local full = player:GetAttribute("Set_Effects") ~= false
	local mine = tower:GetAttribute("OwnerId") == player.UserId
	local height = 9 + rank * 2
	local fall = 0.24 + rank * 0.02

	-- 1. прицел на земле и след с неба
	targetRing(g, color, fall)
	fallStreak(g, g.Y + height + size.Y, color, fall + 0.15)
	sound3D("Whoosh", g)
	if rank >= 4 then
		-- у Legendary / Mythic перед ударом сверху бьёт столб света
		skyBeam(g, rank >= 5 and C.White or color, 3.2, 60, 0.7)
	end

	-- 2. приземление
	dropIn(tower, base, height, fall, function()
		sound3D("Land", g)
		ring(g, 4 + rank, color, 0.45, 0.9)
		task.delay(0.07, function() ring(g, 6 + rank * 1.5, C.White, 0.5, 0.45) end)
		groundGlow(g, color, 3 + rank * 0.6, 0.5)
		dustRing(g, full and (14 + rank * 4) or 8)
		emit(g + UP * 0.5, (full and 14 or 6) + rank * 5, {
			Color = color, Color2 = C.White, Speed = nr(5, 11 + rank * 2), Lifetime = nr(0.5, 1),
			Size = ns(0.6, 0), Acceleration = UP * 6, Spread = Vector2.new(60, 60),
		})
		flash(g + UP * 2, color, 3 + rank, 10 + rank * 3, 0.5)
		if rank >= 2 then
			debrisChunks(g + UP * 0.5, full and (3 + rank) or 2, rgb(95, 85, 75))
		end
		shake(g, 0.15 + rank * 0.1)

		-- 3. блеск по редкости
		if rank >= 2 then
			emit(g + UP, 10 + rank * 4, { Color = color, Color2 = C.White, Speed = nr(2, 5), Lifetime = nr(0.8, 1.4), Size = ns(0.5, 0), Acceleration = UP * 4, Spread = Vector2.new(30, 30) })
		end
		if rank >= 3 then
			local h = 10 + rank * 4
			local beam = part({ Shape = Enum.PartType.Cylinder, Color = color, Transparency = 0.3, Size = Vector3.new(h, 2, 2), CFrame = CFrame.new(g + UP * h / 2) * CFrame.Angles(0, 0, math.pi / 2) })
			fadeOut(beam, 0.6, { Size = Vector3.new(h, 0.1, 0.1) })
			if full then
				runeCircle(g, color:Lerp(C.White, 0.3), rank >= 5 and 10 or (rank == 4 and 8 or 6), 4.5, 1.1, rank >= 5)
			end
			sound3D("Magic", g)
			popText(g + UP * (size.Y + 3), RARITY_TEXT[rank] or "", color, 22 + rank * 2, rank >= 4 and "crown" or "star")
		end
		if rank >= 4 then
			sound3D("Boom", g)
			task.delay(0.12, function() ring(g, 11, color, 0.6, 1.4) end)
			emit(g + UP * 0.5, full and 26 or 10, { Texture = TEX.Fire, Color = C.Ember, Color2 = color, Speed = nr(6, 14), Lifetime = nr(0.4, 0.8), Size = ns(1.4, 0.2), Acceleration = UP * 8, Drag = 2 })
			shake(g, 0.6)
		end
		if rank >= 5 then
			-- радужные волны одна за другой
			for i = 1, 5 do
				task.delay(0.08 * i, function()
					ring(g, 6 + i * 3, Color3.fromHSV(i / 5, 0.65, 1), 0.6, 1)
				end)
			end
			flash(g + UP * 3, C.White, 9, 30, 0.8)
			emit(g + UP * 2, full and 40 or 14, { Color = C.White, Color2 = color, Speed = nr(10, 22), Lifetime = nr(0.6, 1.2), Size = ns(0.8, 0), Drag = 2 })
			shake(g, 0.9)
		end

		-- 4. своему игроку — сколько стоило
		if mine and cfg.Price then
			task.delay(0.25, function()
				popText(g + UP * (size.Y + (rank >= 3 and 5.5 or 3)), "-" .. tostring(cfg.Price), C.Gold, 20, "coin")
			end)
		end

		-- особые юниты
		if tower.Name == "Necromancer" then
			necroSummon(g)
		elseif tower.Name == "Paladin" then
			holyPillar(g, 5, 40)
		end
	end)
	-- модель НЕ масштабируем: Model:ScaleTo на клиенте ломал риги (огромные головы, оторванные руки)
end

-- эффект — только когда сервер поставил юнита (атрибут Ready), и только для новых, не для тех, что уже стояли
local function onTowerAdded(tower)
	trackTower(tower)
	local function go()
		if tower.Parent and not tower:GetAttribute("FxPlaced") then
			tower:SetAttribute("FxPlaced", true) -- только у себя на экране, чтобы не повторять
			local ok, err = pcall(placeFX, tower)
			if not ok then warn("[TowerVFX] появление: " .. tostring(err)) end
		end
	end
	if tower:GetAttribute("Ready") then
		task.defer(go)
	else
		local conn
		conn = tower:GetAttributeChangedSignal("Ready"):Connect(function()
			if tower:GetAttribute("Ready") then
				conn:Disconnect()
				task.defer(go)
			end
		end)
	end
end

towersFolder.ChildAdded:Connect(onTowerAdded)

for _, tower in ipairs(towersFolder:GetChildren()) do
	trackTower(tower)
end

---------------------------------------------------------------- СМЕРТЬ МОБА
-- Статусы (заморозка, замедление, горение, яд, стан, броня) рисует CombatVFX по атрибуту Status.
-- Здесь только «пуф» и награда. Соединение висит на Humanoid и удаляется вместе с мобом.

local function watchMob(mob)
	local humanoid = mob:WaitForChild("Humanoid", 3)
	local root = mob:WaitForChild("HumanoidRootPart", 3) or mob.PrimaryPart
	if not humanoid or not root then return end
	humanoid.Died:Once(function()
		if not root.Parent then return end
		local pos = root.Position
		emit(pos, 12, { Texture = TEX.Smoke, Color = C.White, Color2 = rgb(200, 200, 210), LightEmission = 0.3, Speed = nr(3, 7), Lifetime = nr(0.4, 0.7), Size = ns(1.2, 2.2) })
		local info = MobData[mob.Name]
		local reward = mob:GetAttribute("Reward") or (info and info.RewardGold) or 0
		if reward > 0 then
			popText(pos + UP * 2.5, "+" .. reward, C.Gold, 22, "coin")
		end
	end)
end

mobsFolder.ChildAdded:Connect(function(mob)
	task.spawn(watchMob, mob)
end)
for _, mob in ipairs(mobsFolder:GetChildren()) do
	task.spawn(watchMob, mob)
end

---------------------------------------------------------------- УЛУЧШЕНИЕ БАШНИ
-- Отключение башни боссом рисует CombatVFX по статусу Disabled.

local function towerGround(tower)
	local cf, size = tower:GetBoundingBox()
	return Vector3.new(cf.Position.X, cf.Position.Y - size.Y / 2 + 0.1, cf.Position.Z), cf.Position, size
end

local function levelUpFX(tower, level)
	if level <= 0 then return end
	local g, center, size = towerGround(tower)
	local max = level >= UpgradeData.MaxLevel
	local color = max and C.Pink or C.Gold
	ring(g, 5, color, 0.5, 0.9)
	task.delay(0.1, function() ring(g, 7, C.White, 0.5, 0.5) end)
	holyPillar(g, 2.2, size.Y + 10)
	emit(g + UP, 24, { Color = color, Color2 = C.White, Speed = nr(5, 12), Lifetime = nr(0.5, 1), Size = ns(0.6, 0), Acceleration = UP * 10, Spread = Vector2.new(50, 50) })
	flash(center, color, 5, 16, 0.5)
	local text = "LEVEL " .. level .. "!"
	if max then
		-- на 4-м тире показываем название особого усиления
		local stats = UpgradeData.get(TowerData, tower.Name, level)
		text = string.upper(stats and stats.Special or "MAX LEVEL") .. "!"
	end
	popText(center + UP * (size.Y / 2 + 2), text, color, max and 28 or 24, max and "crown" or "upgrade")
	if max then shake(g, 0.4) end
end

local function watchTower(tower)
	tower:GetAttributeChangedSignal("Level"):Connect(function()
		pcall(levelUpFX, tower, tower:GetAttribute("Level") or 0)
	end)
end

towersFolder.ChildAdded:Connect(watchTower)
for _, tower in ipairs(towersFolder:GetChildren()) do
	watchTower(tower)
end
