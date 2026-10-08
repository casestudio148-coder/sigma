-- ReplicatedStorage.VFXKit (ModuleScript) — только для клиента
-- Помощники для визуальных эффектов с защитой от лагов:
--   • ПУЛ деталей: детали эффектов не создаются каждый раз заново, а переиспользуются;
--   • ЛИМИТ: если эффектов на экране слишком много, второстепенные пропускаются;
--   • АДАПТИВНОЕ КАЧЕСТВО: при низком FPS частиц и вспышек становится меньше;
--   • всё возвращается в пул по таймеру сам, незавершённые твины отменяются.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local VFX = {}

VFX.MaxLive = 450  -- максимум деталей эффектов одновременно
VFX.PoolSize = 250 -- сколько свободных деталей держать про запас
VFX.UP = Vector3.new(0, 1, 0)
VFX.TEX = {
	Sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	Fire = "rbxasset://textures/particles/fire_main.dds",
	Smoke = "rbxasset://textures/particles/smoke_main.dds",
}

function VFX.rgb(r, g, b) return Color3.fromRGB(r, g, b) end
function VFX.ns(a, b) return NumberSequence.new(a, b) end
function VFX.nr(a, b) return NumberRange.new(a, b) end

local WHITE = Color3.new(1, 1, 1)
local UP = VFX.UP

local folder = Instance.new("Folder")
folder.Name = "CombatFX"
folder.Parent = workspace
VFX.Folder = folder

---------------------------------------------------------------- адаптивное качество

VFX.Quality = 1 -- 1 = полное, 0.6 = среднее, 0.35 = экономное
do
	local frames, elapsed = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		frames += 1
		elapsed += dt
		if elapsed >= 1 then
			local fps = frames / elapsed
			VFX.Quality = (fps >= 50 and 1) or (fps >= 35 and 0.6) or 0.35
			-- настройка «Full effects» выключена → всегда экономный режим
			local lp = Players.LocalPlayer
			if lp and lp:GetAttribute("Set_Effects") == false then
				VFX.Quality = 0.35
			end
			frames, elapsed = 0, 0
		end
	end)
end

-- сколько частиц выпускать с учётом качества
function VFX.count(n)
	return math.max(1, math.floor(n * VFX.Quality + 0.5))
end

function VFX.lowQuality()
	return VFX.Quality < 0.5
end

---------------------------------------------------------------- пул деталей

local pool = {}
local inUse = {}
local generation = {}
local partTweens = {}
local live = 0

function VFX.live()
	return live
end

-- можно ли создать ещё cost деталей
function VFX.canSpawn(cost)
	return live + (cost or 1) <= VFX.MaxLive
end

function VFX.tween(obj, t, goal, style, dir, delayTime)
	local tw = TweenService:Create(obj,
		TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out, 0, false, delayTime or 0), goal)
	tw:Play()
	if inUse[obj] then
		local listT = partTweens[obj]
		if not listT then
			listT = {}
			partTweens[obj] = listT
		end
		table.insert(listT, tw)
	end
	return tw
end

function VFX.part(props)
	local p = table.remove(pool)
	if not p then
		p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
	end
	p.Shape = props.Shape or Enum.PartType.Block
	p.Material = props.Material or Enum.Material.Neon
	p.Color = props.Color or WHITE
	p.Transparency = props.Transparency or 0
	p.Size = props.Size or Vector3.one
	p.CFrame = props.CFrame or CFrame.new(props.Position or Vector3.zero)
	p.Parent = folder
	inUse[p] = true
	generation[p] = (generation[p] or 0) + 1
	live += 1
	return p
end

-- вернуть деталь в пул (сразу или через delayTime секунд)
function VFX.release(p, delayTime)
	if not p then return end
	if delayTime and delayTime > 0 then
		local gen = generation[p]
		task.delay(delayTime, function()
			if generation[p] == gen then
				VFX.release(p)
			end
		end)
		return
	end
	if not inUse[p] then return end
	inUse[p] = nil
	live -= 1
	local listT = partTweens[p]
	if listT then
		for _, tw in ipairs(listT) do tw:Cancel() end
		partTweens[p] = nil
	end
	if #pool < VFX.PoolSize then
		p:ClearAllChildren()
		p.Parent = nil
		table.insert(pool, p)
	else
		generation[p] = nil
		p:Destroy()
	end
end

function VFX.fadeOut(p, t, goal)
	goal = goal or {}
	goal.Transparency = 1
	VFX.tween(p, t, goal)
	VFX.release(p, t + 0.05)
end

---------------------------------------------------------------- частицы

function VFX.emitter(parent, cfg)
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = cfg.Texture or VFX.TEX.Sparkle
	local c1 = cfg.Color or WHITE
	pe.Color = ColorSequence.new(c1, cfg.Color2 or c1)
	pe.LightEmission = cfg.LightEmission or 1
	pe.LightInfluence = 0
	pe.Size = cfg.Size or VFX.ns(0.6, 0)
	pe.Transparency = cfg.Transparency or VFX.ns(0, 1)
	pe.Lifetime = cfg.Lifetime or VFX.nr(0.3, 0.6)
	pe.Speed = cfg.Speed or VFX.nr(8, 16)
	pe.SpreadAngle = cfg.Spread or Vector2.new(180, 180)
	pe.Acceleration = cfg.Acceleration or Vector3.zero
	pe.Drag = cfg.Drag or 0
	pe.Rotation = VFX.nr(0, 360)
	pe.RotSpeed = cfg.RotSpeed or VFX.nr(-120, 120)
	pe.Rate = (cfg.Rate or 0) * VFX.Quality
	pe.Enabled = (cfg.Rate or 0) > 0
	if cfg.EmissionDirection then pe.EmissionDirection = cfg.EmissionDirection end
	pe.Parent = parent
	return pe
end

-- разовый выброс частиц в точке
function VFX.emit(pos, count, cfg)
	if not VFX.canSpawn(1) then return end
	local a = VFX.part({ Transparency = 1, Size = Vector3.one * 0.2, Position = pos })
	VFX.emitter(a, cfg):Emit(VFX.count(count))
	VFX.release(a, ((cfg.Lifetime and cfg.Lifetime.Max) or 0.6) + 0.15)
end

---------------------------------------------------------------- простые формы

function VFX.burst(pos, radius, color, t, startTransparency)
	if not VFX.canSpawn(1) then return end
	local s = VFX.part({ Shape = Enum.PartType.Ball, Color = color, Transparency = startTransparency or 0.2, Size = Vector3.one * 0.5, Position = pos })
	VFX.fadeOut(s, t or 0.3, { Size = Vector3.one * radius * 2 })
end

-- плоское расширяющееся кольцо на земле
function VFX.ring(pos, radius, color, t, width)
	if not VFX.canSpawn(1) then return end
	t = t or 0.4
	local a = VFX.part({ Transparency = 1, Size = Vector3.one * 0.2, CFrame = CFrame.new(pos) * CFrame.Angles(-math.pi / 2, 0, 0) })
	local c = Instance.new("CylinderHandleAdornment")
	c.Adornee = a
	c.Color3 = color
	c.Height = 0.12
	c.Radius = 0.5
	c.InnerRadius = 0.2
	c.Transparency = 0.05
	c.Parent = a
	local w = width or 0.6
	TweenService:Create(c, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Radius = radius, InnerRadius = math.max(radius - w, 0), Transparency = 1 }):Play()
	VFX.release(a, t + 0.05)
end

-- плоский диск на земле (зона способности). Вернёт деталь; убрать — VFX.fadeOut / VFX.release
function VFX.disc(pos, radius, color, transparency)
	return VFX.part({
		Shape = Enum.PartType.Cylinder,
		Color = color,
		Transparency = transparency or 0.6,
		Size = Vector3.new(0.15, radius * 2, radius * 2),
		CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2),
	})
end

function VFX.flash(pos, color, brightness, range, t)
	if VFX.lowQuality() or not VFX.canSpawn(1) then return end
	t = t or 0.3
	local a = VFX.part({ Transparency = 1, Size = Vector3.one * 0.2, Position = pos })
	local l = Instance.new("PointLight")
	l.Color = color
	l.Brightness = brightness or 3
	l.Range = range or 12
	l.Parent = a
	TweenService:Create(l, TweenInfo.new(t), { Brightness = 0 }):Play()
	VFX.release(a, t + 0.05)
end

-- зигзаг молнии между двумя точками
function VFX.bolt(a, b, color, width, life)
	local dist = (b - a).Magnitude
	if dist < 0.2 then return end
	local segs = math.clamp(math.floor(dist / 3), 3, 12)
	if not VFX.canSpawn(segs) then return end
	local prev = a
	for i = 1, segs do
		local point = a:Lerp(b, i / segs)
		if i < segs then
			point += Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 2.4
		end
		local len = (point - prev).Magnitude
		if len > 0.05 then
			local seg = VFX.part({ Size = Vector3.new(width, width, len), Color = color, CFrame = CFrame.lookAt(prev, point) * CFrame.new(0, 0, -len / 2) })
			VFX.fadeOut(seg, life or 0.2)
		end
		prev = point
	end
end

-- светящийся луч (прямой)
function VFX.beam(a, b, color, width, life)
	local len = (b - a).Magnitude
	if len < 0.1 or not VFX.canSpawn(1) then return end
	local p = VFX.part({ Size = Vector3.new(width, width, len), Color = color, CFrame = CFrame.lookAt(a, b) * CFrame.new(0, 0, -len / 2) })
	VFX.fadeOut(p, life or 0.3, { Size = Vector3.new(width * 0.2, width * 0.2, len) })
end

-- летящий снаряд со шлейфом, onHit(позиция) в момент попадания
function VFX.projectile(from, to, cfg, onHit)
	local dist = (to - from).Magnitude
	if dist < 0.1 or not VFX.canSpawn(1) then
		if onHit then onHit(to) end
		return
	end
	local t = cfg.Time or math.clamp(dist / (cfg.Speed or 100), 0.05, 1.5)
	local dir = (to - from).Unit
	local p = VFX.part({
		Shape = cfg.Shape,
		Size = cfg.Size or Vector3.one * 0.6,
		Color = cfg.Color or WHITE,
		Material = cfg.Material,
		CFrame = CFrame.lookAt(from, to),
	})
	if cfg.TrailColor then
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
		trail.Color = ColorSequence.new(cfg.TrailColor)
		trail.Transparency = VFX.ns(0.1, 1)
		trail.WidthScale = VFX.ns(1, 0)
		trail.Lifetime = cfg.TrailLife or 0.2
		trail.LightEmission = 1
		trail.FaceCamera = true
		trail.Parent = p
	end
	if cfg.Emitter then VFX.emitter(p, cfg.Emitter) end
	VFX.tween(p, t, { CFrame = CFrame.lookAt(to, to + dir) }, cfg.Easing or Enum.EasingStyle.Linear)
	task.delay(t, function()
		p.Transparency = 1
		for _, d in ipairs(p:GetChildren()) do
			if d:IsA("ParticleEmitter") then d.Enabled = false end
		end
		VFX.release(p, math.max(cfg.TrailLife or 0.2, 0.5))
		if onHit then onHit(to) end
	end)
end

-- надпись, всплывающая над точкой
function VFX.popText(pos, text, color, size, life)
	if not VFX.canSpawn(1) then return end
	life = life or 1
	local a = VFX.part({ Transparency = 1, Size = Vector3.one * 0.2, Position = pos })
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(260, 50)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 200
	bb.Parent = a
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(1, 1)
	l.Font = Enum.Font.FredokaOne
	l.TextSize = size or 24
	l.TextColor3 = color
	l.TextStrokeTransparency = 0
	l.TextStrokeColor3 = Color3.fromRGB(30, 22, 40)
	l.Text = text
	l.Parent = bb
	local sc = Instance.new("UIScale")
	sc.Scale = 0.3
	sc.Parent = l
	TweenService:Create(sc, TweenInfo.new(0.22, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	VFX.tween(a, life, { Position = pos + UP * 2.5 })
	TweenService:Create(l, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, life * 0.55),
		{ TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	VFX.release(a, life)
end

---------------------------------------------------------------- тряска камеры

local shakePower = 0
function VFX.shake(pos, power)
	local lp = Players.LocalPlayer
	if lp and lp:GetAttribute("Set_Shake") == false then return end
	local cam = workspace.CurrentCamera
	if not cam then return end
	local d = (cam.CFrame.Position - pos).Magnitude
	if d < 100 then
		shakePower = math.max(shakePower, power * (1 - d / 100))
	end
end
RunService:BindToRenderStep("CombatFXShake", Enum.RenderPriority.Camera.Value + 2, function(dt)
	if shakePower > 0.01 then
		local cam = workspace.CurrentCamera
		local s = shakePower * 0.04
		cam.CFrame *= CFrame.Angles((math.random() - 0.5) * s, (math.random() - 0.5) * s, 0)
		shakePower *= math.exp(-dt * 10)
	end
end)

---------------------------------------------------------------- геометрия

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

-- точка на земле под позицией
function VFX.ground(pos)
	local ignore = { folder }
	for _, name in ipairs({ "Mobs", "Towers", "ClientFX" }) do
		local f = workspace:FindFirstChild(name)
		if f then table.insert(ignore, f) end
	end
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Character then table.insert(ignore, plr.Character) end
	end
	rayParams.FilterDescendantsInstances = ignore
	local r = workspace:Raycast(pos + UP * 3, Vector3.new(0, -40, 0), rayParams)
	return r and (r.Position + UP * 0.1) or (pos - UP * 2.8)
end

function VFX.flatDir(a, b)
	local d = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	if d.Magnitude < 0.01 then return Vector3.new(0, 0, -1) end
	return d.Unit
end

return VFX
