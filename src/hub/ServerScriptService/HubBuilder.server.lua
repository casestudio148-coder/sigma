-- ServerScriptService.HubBuilder (Script) — ТОЛЬКО В МЕСТЕ-ХАБЕ
-- При запуске сервера строит красивый хаб-лобби:
--   остров на воде (пляжи, скалы, холмы), площадь с фонтаном и парящим кристаллом,
--   8 порталов карт (список в ReplicatedStorage.MapConfig) вдоль дорожки-полукруга, с табло и кругом-очередью,
--   магазин сундуков, храм юнитов со статуями, доска квестов, подарок дня, почтовый ящик кодов,
--   знамя кланов, пирс с лодкой, мельница, деревья, цветы, фонари,
--   летающие острова с водопадом, радуга, облака, светлячки и красивый свет.
-- Если в Workspace уже есть модель "Hub" (ты сохранил её вручную), заново строить не будет.
-- Порталы и кнопки работают через HubService (сервер) и HubClient (игрок).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local MapConfig = require(ReplicatedStorage:WaitForChild("MapConfig"))
local TowerData = require(ReplicatedStorage:WaitForChild("TowerData"))
local PlacementRules = require(ReplicatedStorage:WaitForChild("PlacementRules"))
local PlaceConfig = require(ReplicatedStorage:WaitForChild("PlaceConfig"))

local MUSIC_ID = "" -- фоновая музыка хаба: "rbxassetid://..." (Toolbox → Audio → правый клик → Copy Asset ID)
local MUSIC_VOLUME = 0.3

if workspace:FindFirstChild("Hub") then
	workspace:SetAttribute("HubReady", true)
	return
end
-- защита: это место с картой матча (там есть точки дорожки P1 / P2) — хаб тут не нужен
if workspace:FindFirstChild("P1") and workspace:FindFirstChild("P2") then
	warn("[HubBuilder] это место с картой матча — хаб здесь не строю. HubBuilder нужен только в месте-хабе!")
	return
end

local rng = Random.new(2026)
local function rnd(a, b) return a + rng:NextNumber() * (b - a) end
local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end
local UP = Vector3.new(0, 1, 0)
local M = Enum.Material
local WHITE = Color3.new(1, 1, 1)

local hub = Instance.new("Model")
hub.Name = "Hub"
local function folder(name)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = hub
	return f
end
local F = {
	Plaza = folder("Plaza"),
	Portals = folder("Portals"),
	Places = folder("Places"),
	Nature = folder("Nature"),
	Lights = folder("Lights"),
	Sky = folder("Sky"),
	Effects = folder("Effects"),
	Spawns = folder("Spawns"),
}

---------------------------------------------------------------- помощники

local function part(props, parent)
	local p = Instance.new(props.ClassName or "Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props.Shape then p.Shape = props.Shape end
	for k, v in pairs(props) do
		if k ~= "ClassName" and k ~= "Shape" then p[k] = v end
	end
	p.Parent = parent
	return p
end

local function box(cf, size, color, mat, parent, extra)
	local props = { CFrame = cf, Size = size, Color = color, Material = mat or M.SmoothPlastic }
	for k, v in pairs(extra or {}) do props[k] = v end
	return part(props, parent)
end

local function ball(pos, d, color, mat, parent, extra)
	local props = { Shape = Enum.PartType.Ball, CFrame = CFrame.new(pos), Size = Vector3.one * d, Color = color, Material = mat or M.SmoothPlastic }
	for k, v in pairs(extra or {}) do props[k] = v end
	return part(props, parent)
end

-- вертикальный цилиндр: pos — центр, height — высота, d — диаметр
local function vcyl(pos, height, d, color, mat, parent, extra)
	local props = {
		Shape = Enum.PartType.Cylinder,
		CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2),
		Size = Vector3.new(height, d, d),
		Color = color,
		Material = mat or M.SmoothPlastic,
	}
	for k, v in pairs(extra or {}) do props[k] = v end
	return part(props, parent)
end

-- кольцо из отрезков (бордюр, чаша фонтана, стенка): size.X — вдоль кольца, size.Z — толщина
local function ringOf(center, radius, count, size, color, mat, parent, skip, extra)
	for i = 1, count do
		local a = (i - 0.5) / count * math.pi * 2
		if not (skip and skip(a)) then
			local pos = center + Vector3.new(math.cos(a) * radius, 0, math.sin(a) * radius)
			box(CFrame.lookAt(pos, Vector3.new(center.X, pos.Y, center.Z)), size, color, mat, parent, extra)
		end
	end
end

local function light(p, color, range, brightness)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness or 1.5
	l.Shadows = false
	l.Parent = p
	return l
end

local function emitter(p, cfg)
	local e = Instance.new("ParticleEmitter")
	e.Texture = cfg.Texture or "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(cfg.Color or WHITE, cfg.Color2 or cfg.Color or WHITE)
	e.LightEmission = cfg.LightEmission or 1
	e.LightInfluence = 0
	e.Size = cfg.Size or NumberSequence.new(0.4, 0)
	e.Transparency = cfg.Transparency or NumberSequence.new(0, 1)
	e.Lifetime = cfg.Lifetime or NumberRange.new(1, 2)
	e.Speed = cfg.Speed or NumberRange.new(1, 3)
	e.SpreadAngle = cfg.Spread or Vector2.new(180, 180)
	e.Acceleration = cfg.Acceleration or Vector3.zero
	e.Rate = cfg.Rate or 5
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = cfg.RotSpeed or NumberRange.new(-40, 40)
	e.Drag = cfg.Drag or 0
	if cfg.EmissionDirection then e.EmissionDirection = cfg.EmissionDirection end
	e.Parent = p
	return e
end

-- невидимая деталь-держатель (для частиц, табло)
local function anchor(pos, size, parent)
	return box(CFrame.new(pos), size or Vector3.one, WHITE, M.SmoothPlastic, parent, {
		Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false,
	})
end

local function addLines(holder, lines)
	local labels = {}
	for i, line in ipairs(lines) do
		local l = Instance.new("TextLabel")
		l.Name = line.name or ("Line" .. i)
		l.BackgroundTransparency = 1
		l.Size = UDim2.fromScale(0.94, line.h or 0.3)
		l.Font = line.font or Enum.Font.LuckiestGuy
		l.TextScaled = true
		l.Text = line.text
		l.TextColor3 = line.color or WHITE
		l.LayoutOrder = i
		l.Parent = holder
		local st = Instance.new("UIStroke")
		st.Color = rgb(30, 20, 45)
		st.Thickness = line.stroke or 3
		st.Parent = l
		labels[l.Name] = l
	end
	return labels
end

local function listLayout(holder, padding)
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(padding or 0.02, 0)
	list.Parent = holder
end

local function iconLabel(holder, name, size)
	local img = Instance.new("ImageLabel")
	img.Name = "Icon"
	img.BackgroundTransparency = 1
	img.Size = UDim2.fromScale(size, size)
	img.SizeConstraint = Enum.SizeConstraint.RelativeYY
	img.ScaleType = Enum.ScaleType.Fit
	img.LayoutOrder = 0
	img:SetAttribute("IconName", name) -- картинку из атласа UIKit подставит HubClient
	img.Parent = holder
	return img
end

-- надпись на грани детали. opts.icon — картинка из атласа UIKit
local function sign(p, face, lines, opts)
	opts = opts or {}
	local gui = Instance.new("SurfaceGui")
	gui.Name = opts.name or "Sign"
	gui.Face = face or Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = opts.PPS or 40
	gui.LightInfluence = 0
	gui.Brightness = 1.6
	gui.Parent = p
	local holder = Instance.new("Frame")
	holder.Size = UDim2.fromScale(1, 1)
	holder.BackgroundTransparency = 1
	holder.Parent = gui
	listLayout(holder)
	if opts.icon then iconLabel(holder, opts.icon, opts.iconSize or 0.36) end
	return gui, addLines(holder, lines)
end

-- табло, которое всегда смотрит на игрока (размер в стадах)
local function billboard(p, w, h, lines, opts)
	opts = opts or {}
	local gui = Instance.new("BillboardGui")
	gui.Name = opts.name or "Billboard"
	gui.Size = UDim2.fromScale(w, h)
	gui.LightInfluence = 0
	gui.MaxDistance = opts.maxDistance or 160
	gui.Parent = p
	local holder = Instance.new("Frame")
	holder.Name = "Panel"
	holder.Size = UDim2.fromScale(1, 1)
	holder.BackgroundColor3 = opts.bg or rgb(25, 18, 50)
	holder.BackgroundTransparency = opts.bgTransparency or 0.3
	holder.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.25, 0)
	corner.Parent = holder
	if opts.border then
		local st = Instance.new("UIStroke")
		st.Color = opts.border
		st.Thickness = 3
		st.Parent = holder
	end
	listLayout(holder, 0)
	return gui, addLines(holder, lines)
end

local function prompt(p, action, object, menuId)
	local pr = Instance.new("ProximityPrompt")
	pr.Name = "HubPrompt"
	pr.ActionText = action
	pr.ObjectText = object or ""
	pr.HoldDuration = 0
	pr.MaxActivationDistance = 13
	pr.RequiresLineOfSight = false
	pr:SetAttribute("MenuId", menuId)
	pr.Parent = p
	return pr
end

-- откуда HubClient анимирует объект (модель приходит к игроку целиком)
local function animBase(obj)
	if obj:IsA("Model") then
		pcall(function() obj.ModelStreamingMode = Enum.ModelStreamingMode.Atomic end)
		obj:SetAttribute("HubBase", obj:GetPivot())
	else
		obj:SetAttribute("HubBase", obj.CFrame)
	end
end

-- парит и крутится вокруг вертикали (анимацию делает HubClient — так плавнее)
local function floaty(obj, amp, spin, speed)
	animBase(obj)
	obj:SetAttribute("HubFloat", amp or 1)
	obj:SetAttribute("HubSpin", spin or 0)
	obj:SetAttribute("HubSpeed", speed or 1)
	obj:SetAttribute("HubPhase", rng:NextNumber() * 6)
end

-- алмаз (кристалл): куб, поставленный на вершину
local function diamond(pos, s, color, mat, parent, extra)
	return box(CFrame.new(pos) * CFrame.Angles(math.rad(45), 0, math.rad(35.26)), Vector3.one * s, color, mat or M.Glass, parent, extra)
end

---------------------------------------------------------------- зоны (чтобы деревья не выросли на дорожках)

local zones, segs = {}, {}
local function addZone(x, z, r) table.insert(zones, { x, z, r }) end
local function addSeg(ax, az, bx, bz, r) table.insert(segs, { ax, az, bx, bz, r }) end
local function free(x, z, margin)
	for _, c in ipairs(zones) do
		if (x - c[1]) ^ 2 + (z - c[2]) ^ 2 < (c[3] + margin) ^ 2 then return false end
	end
	for _, s in ipairs(segs) do
		local abx, abz = s[3] - s[1], s[4] - s[2]
		local len2 = abx * abx + abz * abz
		local t = len2 > 0 and math.clamp(((x - s[1]) * abx + (z - s[2]) * abz) / len2, 0, 1) or 0
		local px, pz = s[1] + abx * t, s[2] + abz * t
		if (x - px) ^ 2 + (z - pz) ^ 2 < (s[5] + margin) ^ 2 then return false end
	end
	return true
end

---------------------------------------------------------------- раскладка

local function dirAt(deg) -- 0° — север (к порталам), по часовой
	local a = math.rad(deg)
	return Vector3.new(math.sin(a), 0, -math.cos(a))
end

local PLAZA_R = 42
local PORTAL_R = 108  -- порталы стоят полукругом
local AVENUE_R = 86   -- дорожка-полукруг перед порталами
local ROAD_ANGLES = { -36, 0, 36 } -- дорожки от площади к полукругу
local PORTAL_ANGLES = {} -- [карта] = угол
for i, id in ipairs(MapConfig.Order) do
	PORTAL_ANGLES[id] = (i - (#MapConfig.Order + 1) / 2) * 18.4
end
local PLACES = {
	Shop = { angle = 90, r = 86 },
	Units = { angle = -90, r = 86 },
	Daily = { angle = 135, r = 74 },
	Quests = { angle = -135, r = 74 },
	Clans = { angle = 160, r = 76 },
	Codes = { angle = -160, r = 76 },
}
local DOCK_ANGLE = 180
local MILL = { angle = -112, r = 118 }

addZone(0, 0, PLAZA_R + 2)
for _, a in pairs(PORTAL_ANGLES) do
	local p = dirAt(a) * PORTAL_R
	addZone(p.X, p.Z, 18)
end
for _, a in ipairs(ROAD_ANGLES) do
	local s, e = dirAt(a) * (PLAZA_R - 2), dirAt(a) * AVENUE_R
	addSeg(s.X, s.Z, e.X, e.Z, 6)
end
for a = -72, 66, 6 do
	local p1, p2 = dirAt(a) * AVENUE_R, dirAt(a + 6) * AVENUE_R
	addSeg(p1.X, p1.Z, p2.X, p2.Z, 6)
end
for id, info in pairs(PLACES) do
	local p = dirAt(info.angle) * info.r
	addZone(p.X, p.Z, (id == "Shop" or id == "Units") and 20 or 11)
	local s = dirAt(info.angle) * (PLAZA_R - 2)
	addSeg(s.X, s.Z, p.X, p.Z, 6)
end
do
	local m = dirAt(MILL.angle) * MILL.r
	addZone(m.X, m.Z, 12)
	local a, b = dirAt(DOCK_ANGLE) * 128, dirAt(DOCK_ANGLE) * 180
	addSeg(a.X, a.Z, b.X, b.Z, 8)
end

---------------------------------------------------------------- ЗЕМЛЯ: остров на воде (Terrain)

local terrain = workspace.Terrain
pcall(function() terrain.Decoration = false end) -- без высокой травы
-- Roblox может нарисовать верх террейна выше, чем просили (сетка 4 studs).
-- Пробная заливка далеко в стороне: меряем, насколько выше, и опускаем на столько все заливки.
-- Террейн попадает под лучи не сразу — ждём (до 4 с на каждую пробу).
local function measureTerrainShift(t)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { t }
	local shift, hits = 0, 0
	local ok, err = pcall(function()
		for i = 1, 4 do
			local probe = Vector3.new(-6000 + i * 300, 0, -6000)
			t:FillBlock(CFrame.new(probe + Vector3.new(0, -8 - shift, 0)), Vector3.new(48, 16, 48), Enum.Material.Rock)
			local hit
			local t0 = os.clock()
			repeat
				hit = workspace:Raycast(probe + Vector3.new(0, 60, 0), Vector3.new(0, -120, 0), params)
				if not hit then task.wait(0.05) end
			until hit or os.clock() - t0 > 4
			t:FillBlock(CFrame.new(probe + Vector3.new(0, -10, 0)), Vector3.new(96, 72, 96), Enum.Material.Air)
			if not hit then break end
			hits += 1
			local e = hit.Position.Y - probe.Y
			if math.abs(e) < 0.3 then break end
			shift += e
		end
	end)
	if not ok then warn("[terrain] проба не удалась: " .. tostring(err)) return 0, 0 end
	return math.clamp(shift, -4, 4), hits
end
local TSHIFT, probeHits = measureTerrainShift(terrain)
TSHIFT = math.max(0, TSHIFT)
print(string.format("[HubBuilder] проба террейна: %.2f (замеров %d)", TSHIFT, probeHits))
local DOWN = Vector3.new(0, TSHIFT, 0)
local function tFillBlock(cf, size, mat) terrain:FillBlock(cf - DOWN, size, mat) end
local function tFillBall(pos, r, mat) terrain:FillBall(pos - DOWN, r, mat) end
local function tFillCylinder(cf, h, r, mat) terrain:FillCylinder(cf - DOWN, h, r, mat) end
pcall(function()
	terrain:SetMaterialColor(M.Grass, rgb(104, 190, 74))
	terrain:SetMaterialColor(M.LeafyGrass, rgb(86, 170, 66))
	terrain:SetMaterialColor(M.Rock, rgb(132, 124, 142))
	terrain:SetMaterialColor(M.Sand, rgb(242, 224, 172))
	terrain:SetMaterialColor(M.Ground, rgb(130, 100, 70))
	terrain.WaterColor = rgb(40, 170, 220)
	terrain.WaterTransparency = 0.35
	terrain.WaterReflectance = 0.6
	terrain.WaterWaveSize = 0.12
	terrain.WaterWaveSpeed = 8
end)

local ISLAND_R = 150 -- край травы
-- море
tFillBlock(CFrame.new(0, -26, 0), Vector3.new(1600, 8, 1600), M.Sand)
tFillBlock(CFrame.new(0, -14, 0), Vector3.new(1600, 16, 1600), M.Water)

-- пляжи: в этих местах берег песчаный и пологий (на юге — пирс)
local BEACHES = { DOCK_ANGLE, 62, -62 }
local function nearBeach(a, width)
	local deg = math.deg(a) + 90
	for _, b in ipairs(BEACHES) do
		if math.abs(((deg - b) + 180) % 360 - 180) < (width or 26) then return true end
	end
	return false
end

-- каменное основание с неровным берегом (вода на высоте -6)
tFillCylinder(CFrame.new(0, -13, 0), 22, ISLAND_R - 4, M.Rock)
local EDGE = {}
for i = 1, 40 do
	local a = (i - 0.5) / 40 * math.pi * 2 + rnd(-0.04, 0.04)
	local r = ISLAND_R - 8 + rnd(-5, 7)
	local rr = rnd(14, 22)
	local beach = nearBeach(a, 18)
	table.insert(EDGE, { a = a, r = r, rr = rr, beach = beach })
	if beach then
		-- песчаная отмель чуть выше воды
		tFillCylinder(CFrame.new(math.cos(a) * (r + 4), -14, math.sin(a) * (r + 4)), 20, rr, M.Sand)
	else
		tFillCylinder(CFrame.new(math.cos(a) * r, -13, math.sin(a) * r), 22, rr, M.Rock)
	end
end
-- трава сверху (камень виден только по краю, как скалы)
tFillCylinder(CFrame.new(0, -4, 0), 8, ISLAND_R - 8, M.Grass)
for _, e in ipairs(EDGE) do
	if not e.beach then
		tFillCylinder(CFrame.new(math.cos(e.a) * (e.r - 4), -4, math.sin(e.a) * (e.r - 4)), 8, e.rr - 3, M.Grass)
	end
end
-- проверка: на какой высоте получилась трава (для отладки)
do
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Include
	rp.FilterDescendantsInstances = { terrain }
	local hit
	local t0 = os.clock()
	repeat
		hit = workspace:Raycast(Vector3.new(60, 60, 20), Vector3.new(0, -120, 0), rp)
		if not hit then task.wait(0.05) end
	until hit or os.clock() - t0 > 4
	print(string.format("[HubBuilder] трава на высоте %s (должно быть около 0)", hit and string.format("%.2f", hit.Position.Y) or "?"))
end
-- вся трава острова не выше 0: срезаем лишнее сверху (иначе закроет порталы, домики, дорожки)
tFillCylinder(CFrame.new(0, 30, 0), 61, ISLAND_R + 24, M.Air)
-- Roblox всё равно может положить траву чуть выше или ниже 0 (сетка 4 studs).
-- Меряем, где она на самом деле (LIFT), и потом ставим ВСЕ постройки на эту высоту.
local LIFT = 0
do
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Include
	rp.FilterDescendantsInstances = { terrain }
	local function sample()
		local ys = {}
		for i = 0, 11 do
			local a = (i + 0.5) / 12 * math.pi * 2
			for _, rr in ipairs({ 20, 50, 80, 105 }) do
				local hit = workspace:Raycast(Vector3.new(math.cos(a) * rr, 80, math.sin(a) * rr), Vector3.new(0, -160, 0), rp)
				if hit and hit.Position.Y > -5 then table.insert(ys, hit.Position.Y) end
			end
		end
		return ys
	end
	task.wait(0.1)
	local ys = sample()
	local t0 = os.clock()
	while #ys < 20 and os.clock() - t0 < 5 do
		task.wait(0.1)
		ys = sample()
	end
	if #ys >= 10 then
		table.sort(ys)
		LIFT = ys[math.ceil(#ys / 2)]
		if math.abs(LIFT) < 0.05 or math.abs(LIFT) > 6 then LIFT = 0 end
	end
	print(string.format("[HubBuilder] трава после выравнивания: %.2f (замеров %d) — постройки ставлю на эту высоту", LIFT, #ys))
	-- все следующие заливки (холмы, песок, камни) тоже относительно этой высоты
	DOWN = Vector3.new(0, TSHIFT - LIFT, 0)
end
-- пологий спуск от травы к песку
for _, deg in ipairs(BEACHES) do
	for k = -1, 1 do
		local c = dirAt(deg + k * 8) * (ISLAND_R - 5)
		tFillBall(Vector3.new(c.X, -30, c.Z), 28, M.Sand)
	end
end

-- скалы у воды (не на пляжах)
for _ = 1, 18 do
	local a = rnd(0, math.pi * 2)
	if not nearBeach(a) then
		local r = ISLAND_R + rnd(2, 10)
		local pos = Vector3.new(math.cos(a) * r, rnd(-7, -4), math.sin(a) * r)
		tFillBall(pos, rnd(6, 10), M.Rock)
		tFillBall(pos + Vector3.new(rnd(-6, 6), -2, rnd(-6, 6)), rnd(4, 7), M.Rock)
	end
end
-- пологие зелёные холмы
local hills = 0
for _ = 1, 200 do
	if hills >= 10 then break end
	local a = rnd(0, math.pi * 2)
	local r = rnd(102, 128)
	local x, z = math.cos(a) * r, math.sin(a) * r
	if free(x, z, 16) and not nearBeach(a) then
		local rr = rnd(24, 32)
		local h = rnd(5, 9)
		tFillBall(Vector3.new(x, h - rr, z), rr, M.Grass)
		addZone(x, z, 6)
		hills += 1
	end
end
-- маленькие скалистые островки в море
for _ = 1, 9 do
	local a = rnd(0, math.pi * 2)
	local r = rnd(210, 320)
	local pos = Vector3.new(math.cos(a) * r, -10, math.sin(a) * r)
	tFillBall(pos, rnd(8, 14), M.Rock)
	tFillBall(pos + Vector3.new(0, 4, 0), rnd(5, 8), M.Grass)
end

-- высота земли (с холмами); ждём, пока новый террейн начнёт ловить лучи
do
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Include
	rp.FilterDescendantsInstances = { terrain }
	local t0 = os.clock()
	while not workspace:Raycast(Vector3.new(0, 60, 0), Vector3.new(0, -120, 0), rp) and os.clock() - t0 < 4 do
		task.wait(0.05)
	end
	task.wait(0.3)
end
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.FilterDescendantsInstances = { terrain }
local function groundY(x, z)
	local r = workspace:Raycast(Vector3.new(x, 120, z), Vector3.new(0, -260, 0), rayParams)
	return r and (r.Position.Y - LIFT) or 0
end

---------------------------------------------------------------- ПЛОЩАДЬ И ФОНТАН

local MARBLE = rgb(242, 236, 226)
local STONE = rgb(214, 205, 190)
local SLATE = rgb(165, 155, 142)
local GOLD = rgb(255, 204, 80)
local WOOD = rgb(150, 100, 62)
local DARKWOOD = rgb(98, 64, 42)
local IRON = rgb(55, 50, 60)

-- пол площади
vcyl(Vector3.new(0, -3.8, 0), 8, PLAZA_R * 2, STONE, M.Pavement, F.Plaza)
vcyl(Vector3.new(0, -3.85, 0), 8, PLAZA_R * 2 + 3, rgb(160, 150, 138), M.Slate, F.Plaza)
-- узор: кольца-вставки
for _, rr in ipairs({ { 17, 2, rgb(120, 170, 255) }, { 31, 1.4, GOLD } }) do
	ringOf(Vector3.new(0, 0.22, 0), rr[1], 48, Vector3.new(rr[1] * 2 * math.pi / 48 + 0.3, 0.1, rr[2]), rr[3], M.SmoothPlastic, F.Plaza)
end
-- лучи-узор от фонтана
for i = 1, 8 do
	local a = (i - 0.5) / 8 * math.pi * 2
	local d = Vector3.new(math.cos(a), 0, math.sin(a))
	box(CFrame.lookAt(d * 24 + Vector3.new(0, 0.21, 0), d * 30 + Vector3.new(0, 0.21, 0)), Vector3.new(1.2, 0.1, 13), rgb(255, 225, 140), M.SmoothPlastic, F.Plaza)
end

-- низкая стенка вокруг площади с проходами к порталам и домикам
local pathAngles = {}
for _, a in ipairs(ROAD_ANGLES) do table.insert(pathAngles, a) end
for _, info in pairs(PLACES) do table.insert(pathAngles, info.angle) end
local function nearPath(a)
	local deg = (math.deg(a) + 90) % 360 -- угол в «компасе» (0 — север)
	for _, pa in ipairs(pathAngles) do
		local d = math.abs(((deg - (pa % 360)) + 180) % 360 - 180)
		if d < 9 then return true end
	end
	return false
end
ringOf(Vector3.new(0, 1.2, 0), PLAZA_R + 0.6, 40, Vector3.new(6.8, 2.4, 1.8), MARBLE, M.Marble, F.Plaza, nearPath)
ringOf(Vector3.new(0, 2.5, 0), PLAZA_R + 0.6, 40, Vector3.new(7, 0.3, 2.2), GOLD, M.Metal, F.Plaza, nearPath)
-- столбики с шарами у проходов
for _, pa in ipairs(pathAngles) do
	for _, side in ipairs({ -1, 1 }) do
		local p = dirAt(pa + side * 9.5) * (PLAZA_R + 0.6)
		box(CFrame.new(p + Vector3.new(0, 1.8, 0)), Vector3.new(2.4, 3.6, 2.4), MARBLE, M.Marble, F.Plaza)
		ball(p + Vector3.new(0, 4.2, 0), 1.6, GOLD, M.Metal, F.Plaza)
	end
end

-- фонтан: чаша, вода, постамент
local FC = Vector3.new(0, 0, 0)
ringOf(FC + Vector3.new(0, 1.5, 0), 12.4, 24, Vector3.new(3.6, 3, 1.8), MARBLE, M.Marble, F.Plaza)
ringOf(FC + Vector3.new(0, 3.1, 0), 12.4, 24, Vector3.new(3.8, 0.4, 2.3), GOLD, M.Metal, F.Plaza)
vcyl(FC + Vector3.new(0, 0.6, 0), 0.8, 24, rgb(70, 110, 160), M.Slate, F.Plaza)
local water = vcyl(FC + Vector3.new(0, 1.6, 0), 1.6, 23.6, rgb(80, 200, 255), M.Glass, F.Plaza, { Transparency = 0.25, Reflectance = 0.15, CanCollide = false })
water.Name = "FountainWater"
vcyl(FC + Vector3.new(0, 2.5, 0), 3.4, 7, MARBLE, M.Marble, F.Plaza)
vcyl(FC + Vector3.new(0, 4.6, 0), 0.8, 7.6, GOLD, M.Metal, F.Plaza)
vcyl(FC + Vector3.new(0, 6.2, 0), 2.6, 4.6, MARBLE, M.Marble, F.Plaza)
vcyl(FC + Vector3.new(0, 7.7, 0), 0.6, 5.4, GOLD, M.Metal, F.Plaza)
-- струи воды
local spray = anchor(FC + Vector3.new(0, 8.2, 0), Vector3.new(1, 0.2, 1), F.Effects)
emitter(spray, {
	Color = rgb(220, 245, 255), Color2 = rgb(120, 210, 255), LightEmission = 0.4,
	Size = NumberSequence.new(0.55, 0.25), Transparency = NumberSequence.new(0.1, 0.9),
	Lifetime = NumberRange.new(1.1, 1.5), Speed = NumberRange.new(13, 17), Spread = Vector2.new(22, 22),
	Acceleration = Vector3.new(0, -26, 0), Rate = 70, EmissionDirection = Enum.NormalId.Top,
})
local mist = anchor(FC + Vector3.new(0, 2.4, 0), Vector3.new(20, 0.5, 20), F.Effects)
emitter(mist, {
	Texture = "rbxasset://textures/particles/smoke_main.dds", Color = rgb(230, 245, 255), LightEmission = 0.2,
	Size = NumberSequence.new(2, 4), Transparency = NumberSequence.new(0.8, 1), Lifetime = NumberRange.new(1.5, 2.5),
	Speed = NumberRange.new(0.5, 1.2), Rate = 6,
})

-- парящий кристалл над фонтаном
local crystal = Instance.new("Model")
crystal.Name = "Crystal"
crystal.Parent = F.Plaza
local cPos = FC + Vector3.new(0, 16, 0)
local shell = diamond(cPos, 5.6, rgb(150, 225, 255), M.Glass, crystal, { Transparency = 0.45, CanCollide = false })
local core = diamond(cPos, 3.4, rgb(120, 230, 255), M.Neon, crystal, { CanCollide = false })
crystal.PrimaryPart = shell
light(core, rgb(140, 220, 255), 36, 2.6)
emitter(core, { Color = rgb(190, 240, 255), Size = NumberSequence.new(0.5, 0), Lifetime = NumberRange.new(1, 1.6), Speed = NumberRange.new(2, 4), Rate = 14 })
floaty(crystal, 1.2, 28, 0.9)
-- светящееся кольцо под кристаллом
local halo = vcyl(cPos - Vector3.new(0, 5.5, 0), 0.25, 9, rgb(150, 230, 255), M.Neon, F.Plaza, { Transparency = 0.35, CanCollide = false, CastShadow = false })
floaty(halo, 0.6, 0, 0.9)
-- осколки кружат вокруг кристалла
local SHARD_COLORS = { rgb(120, 230, 255), rgb(255, 150, 220), rgb(255, 220, 100), rgb(170, 140, 255), rgb(140, 255, 190), rgb(255, 170, 120) }
for i = 1, 6 do
	local s = diamond(cPos, 1.3, SHARD_COLORS[i], M.Neon, F.Plaza, { CanCollide = false, CastShadow = false })
	s.Name = "OrbitShard"
	s:SetAttribute("OrbitCenter", cPos)
	s:SetAttribute("OrbitRadius", 7.5)
	s:SetAttribute("OrbitSpeed", 0.7)
	s:SetAttribute("OrbitPhase", (i - 1) / 6 * math.pi * 2)
	s:SetAttribute("OrbitBob", 1.4)
	s.CFrame = CFrame.new(cPos + Vector3.new(math.cos((i - 1) / 6 * math.pi * 2) * 7.5, 0, math.sin((i - 1) / 6 * math.pi * 2) * 7.5))
end

-- скамейки и клумбы на площади
local function bench(pos, faceTo)
	local cf = CFrame.lookAt(pos, Vector3.new(faceTo.X, pos.Y, faceTo.Z))
	box(cf * CFrame.new(0, 1.6, 0), Vector3.new(7, 0.5, 2.2), WOOD, M.WoodPlanks, F.Plaza)
	box(cf * CFrame.new(0, 2.9, 1), Vector3.new(7, 2, 0.4), WOOD, M.WoodPlanks, F.Plaza)
	for _, sx in ipairs({ -3, 3 }) do
		box(cf * CFrame.new(sx, 0.8, 0), Vector3.new(0.5, 1.6, 2), rgb(70, 70, 80), M.Metal, F.Plaza)
	end
end
local FLOWER_COLORS = { rgb(255, 90, 110), rgb(255, 210, 70), rgb(255, 255, 255), rgb(190, 110, 255), rgb(255, 150, 210), rgb(110, 190, 255) }
local function flowers(center, radius, count, parent, y)
	for _ = 1, count do
		local a, r = rnd(0, math.pi * 2), rnd(0, radius)
		local pos = center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		local gy = y or groundY(pos.X, pos.Z)
		ball(Vector3.new(pos.X, gy + 0.35, pos.Z), rnd(0.6, 1), FLOWER_COLORS[rng:NextInteger(1, #FLOWER_COLORS)], M.SmoothPlastic, parent, { CanCollide = false, CastShadow = false })
	end
end
local function planter(pos)
	local cf = CFrame.lookAt(pos, Vector3.new(0, pos.Y, 0))
	box(cf * CFrame.new(0, 0.9, 0), Vector3.new(6, 1.8, 3), DARKWOOD, M.WoodPlanks, F.Plaza)
	box(cf * CFrame.new(0, 1.85, 0), Vector3.new(5.4, 0.2, 2.4), rgb(80, 150, 60), M.Grass, F.Plaza)
	for i = 1, 9 do
		ball((cf * CFrame.new(rnd(-2.4, 2.4), 2.3, rnd(-1, 1))).Position, rnd(0.8, 1.2), FLOWER_COLORS[(i % #FLOWER_COLORS) + 1], M.SmoothPlastic, F.Plaza, { CanCollide = false, CastShadow = false })
	end
end

-- точки появления: за фонтаном, лицом к порталам
for i, x in ipairs({ -7.5, -2.5, 2.5, 7.5 }) do
	local pos = Vector3.new(x, 0.5, 24)
	local sp = part({
		ClassName = "SpawnLocation",
		CFrame = CFrame.lookAt(pos, pos + Vector3.new(0, 0, -10)),
		Size = Vector3.new(4, 0.2, 4),
		Transparency = 1,
		CanCollide = false,
		Neutral = true,
		Duration = 0,
		Name = "HubSpawn" .. i,
	}, F.Spawns)
	local decal = sp:FindFirstChildOfClass("Decal")
	if decal then decal:Destroy() end
end

---------------------------------------------------------------- ДОРОЖКИ (плитка с бордюром) и фонари

local PATH_COLOR = rgb(200, 188, 168)
-- все дорожки заранее: бордюр не ставим поперёк соседней дорожки
local ROADS = {}
local function distSeg(p, a, b)
	local ab = b - a
	local t = math.clamp((p - a):Dot(ab) / ab:Dot(ab), 0, 1)
	local q = a + ab * t
	return Vector3.new(p.X - q.X, 0, p.Z - q.Z).Magnitude
end
local function addRoad(a, b) table.insert(ROADS, { a, b }) end
for _, a in ipairs(ROAD_ANGLES) do addRoad(dirAt(a) * (PLAZA_R - 2), dirAt(a) * AVENUE_R) end
for a = -72, 66, 6 do addRoad(dirAt(a) * AVENUE_R, dirAt(a + 6) * AVENUE_R) end

local function segPath(a, b)
	local d = (b - a).Unit
	local len = (b - a).Magnitude
	local mid = (a + b) / 2
	box(CFrame.lookAt(mid + Vector3.new(0, -2.6, 0), b + Vector3.new(0, -2.6, 0)), Vector3.new(10, 6, len), PATH_COLOR, M.Cobblestone, F.Plaza)
	local right = d:Cross(UP)
	local n = math.max(1, math.floor(len / 3.4))
	for i = 0, n do
		local p = a + d * (i * len / n)
		for _, side in ipairs({ -1, 1 }) do
			local pos = p + right * side * 5.3
			local blocked = false
			for _, r in ipairs(ROADS) do
				if not (r[1] == a and r[2] == b) and distSeg(pos, r[1], r[2]) < 5.6 then
					blocked = true
					break
				end
			end
			if not blocked then
				pos += Vector3.new(0, 0.25, 0)
				box(CFrame.lookAt(pos, pos + d) * CFrame.Angles(0, rnd(-0.25, 0.25), 0), Vector3.new(rnd(1.2, 1.6), rnd(0.6, 0.9), rnd(2.6, 3.2)), rgb(150, 145, 140), M.Slate, F.Plaza)
			end
		end
	end
	return a, b, right
end
local function path(fromDist, deg, toDist)
	local d = dirAt(deg)
	return segPath(d * fromDist, d * toDist)
end

local LAMP_WARM = rgb(255, 200, 120)
local function lantern(pos, baseY)
	local gy = baseY or groundY(pos.X, pos.Z)
	local base = Vector3.new(pos.X, gy, pos.Z)
	box(CFrame.new(base + Vector3.new(0, 0.4, 0)), Vector3.new(1.4, 0.8, 1.4), IRON, M.Metal, F.Lights)
	box(CFrame.new(base + Vector3.new(0, 4, 0)), Vector3.new(0.5, 7.4, 0.5), IRON, M.Metal, F.Lights)
	box(CFrame.new(base + Vector3.new(0, 7.8, 0)), Vector3.new(1.8, 0.3, 1.8), IRON, M.Metal, F.Lights)
	box(CFrame.new(base + Vector3.new(0, 8.8, 0)), Vector3.new(1.4, 1.8, 1.4), rgb(255, 230, 180), M.Glass, F.Lights, { Transparency = 0.35, CastShadow = false })
	local flame = box(CFrame.new(base + Vector3.new(0, 8.8, 0)), Vector3.new(0.6, 0.9, 0.6), LAMP_WARM, M.Neon, F.Lights, { CanCollide = false, CastShadow = false })
	box(CFrame.new(base + Vector3.new(0, 9.9, 0)), Vector3.new(2, 0.4, 2), IRON, M.Metal, F.Lights)
	light(flame, LAMP_WARM, 16, 1.4)
end

-- дорожки к порталам: три от площади и полукруг перед порталами
for _, a in ipairs(ROAD_ANGLES) do
	local from, to, right = path(PLAZA_R - 2, a, AVENUE_R)
	local mid = (from + to) / 2
	lantern(mid + right * 7.5)
	lantern(mid - right * 7.5)
end
for a = -72, 66, 6 do
	local p1, p2 = dirAt(a) * AVENUE_R, dirAt(a + 6) * AVENUE_R
	segPath(p1, p2)
	vcyl(p2 + Vector3.new(0, -2.62, 0), 6, 10, PATH_COLOR, M.Cobblestone, F.Plaza) -- стык без щели
end
-- фонари между порталами
for i = 1, #MapConfig.Order - 1 do
	local a = (i - #MapConfig.Order / 2) * 18.4
	lantern(dirAt(a) * (AVENUE_R + 8))
end
for id, info in pairs(PLACES) do
	local stop = (id == "Shop") and info.r - 8 or (id == "Units") and info.r - 13 or info.r - 3
	local from, to, right = path(PLAZA_R - 2, info.angle, stop)
	lantern((from + to) / 2 + right * 7.5)
end

---------------------------------------------------------------- ДЕРЕВЬЯ (нужны и порталам)

local GREENS = { rgb(86, 172, 70), rgb(104, 188, 80), rgb(74, 152, 66), rgb(122, 198, 92), rgb(96, 180, 110) }
local BLOSSOM = { rgb(255, 172, 210), rgb(255, 200, 228), rgb(250, 150, 200) }

-- Низкополигональные деревья (общий код для хаба и карт).
-- B.make(class, cf, size, color, mat, shape) — создать деталь; B.rnd(a, b); B.groundY(x, z)
local function makeTrees(B)
	local T = {}
	local rnd = B.rnd
	local M = Enum.Material
	local TAU = math.pi * 2
	local DARK = Color3.new(0, 0, 0)
	local function pick(list) return list[math.clamp(math.floor(rnd(1, #list + 1)), 1, #list)] end
	local LIGHT = Color3.new(1, 1, 1)

	local function cyl(pos, h, d, color, mat)
		return B.make("Part", CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2), Vector3.new(h, d, d), color, mat, Enum.PartType.Cylinder)
	end
	-- наклонный цилиндр от точки a до точки b
	local function stick(a, b, d, color, mat)
		local len = (b - a).Magnitude
		local cf = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0)
		return B.make("Part", cf, Vector3.new(len, d, d), color, mat, Enum.PartType.Cylinder)
	end
	local function cube(pos, s, color, mat)
		local cf = CFrame.new(pos) * CFrame.Angles(rnd(0, TAU), rnd(0, TAU), rnd(0, TAU))
		return B.make("Part", cf, Vector3.new(s, s * rnd(0.82, 1), s), color, mat or M.SmoothPlastic)
	end

	-- треугольник из двух клиньев (грань конуса)
	local TH = 0.2
	local function tri(a, b, c, color, mat)
		local ab, ac, bc = b - a, c - a, c - b
		local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
		if abd > acd and abd > bcd then
			c, a = a, c
		elseif acd > bcd and acd > abd then
			a, b = b, a
		end
		ab, ac, bc = b - a, c - a, c - b
		local right = ac:Cross(ab).Unit
		local up = bc:Cross(right).Unit
		local back = bc.Unit
		local height = math.abs(ab:Dot(up))
		local d1, d2 = math.abs(ab:Dot(back)), math.abs(ac:Dot(back))
		if d1 > 0.05 then
			B.make("WedgePart", CFrame.fromMatrix((a + b) / 2, right, up, back), Vector3.new(TH, height, d1), color, mat)
		end
		if d2 > 0.05 then
			B.make("WedgePart", CFrame.fromMatrix((a + c) / 2, -right, up, -back), Vector3.new(TH, height, d2), color, mat)
		end
	end

	-- конус-пирамида с n гранями: base — центр основания, r — радиус, h — высота
	local function cone(base, r, h, color, mat, n, rot, noDisc)
		local apex = base + Vector3.new(0, h, 0)
		for i = 0, n - 1 do
			local a1, a2 = rot + i / n * TAU, rot + (i + 1) / n * TAU
			local p1 = base + Vector3.new(math.cos(a1) * r, 0, math.sin(a1) * r)
			local p2 = base + Vector3.new(math.cos(a2) * r, 0, math.sin(a2) * r)
			-- чуть темнее грани с одной стороны — объём
			local shade = 0.06 * math.cos((a1 + a2) / 2 - 0.8)
			tri(apex, p1, p2, shade > 0 and color:Lerp(LIGHT, shade) or color:Lerp(DARK, -shade), mat)
		end
		-- дно, чтобы снизу не было видно пустоты
		if noDisc then return end
		cyl(base + Vector3.new(0, 0.12, 0), 0.24, 2 * r * math.cos(math.pi / n) - 0.1, color:Lerp(DARK, 0.25), mat)
	end

	-- низкополигональный «шар» кроны: шестигранная призма + крышки-пирамиды сверху и снизу
	local SQ3 = math.sqrt(3)
	local function blob(c, r, hMid, hTop, hBot, color, rot, noBottom)
		for k = 0, 2 do
			B.make("Part", CFrame.new(c) * CFrame.Angles(0, -rot - k * math.pi / 3, 0), Vector3.new(r, hMid, r * SQ3), color, M.SmoothPlastic)
		end
		cone(c + Vector3.new(0, hMid / 2 - 0.02, 0), r, hTop, color:Lerp(LIGHT, 0.06), M.SmoothPlastic, 6, rot, true)
		if not noBottom then
			cone(c - Vector3.new(0, hMid / 2 - 0.02, 0), r, -hBot, color:Lerp(DARK, 0.12), M.SmoothPlastic, 6, rot, true)
		end
	end

	-- лиственное дерево: ствол, две ветки, крона из 3 граненых шаров
	function T.oak(x, z, s, leaves, trunkColor)
		local gy = B.groundY(x, z)
		trunkColor = trunkColor or Color3.fromRGB(122, 84, 56)
		local h = rnd(5.5, 7) * s
		cyl(Vector3.new(x, gy + 0.5 * s, z), 1 * s, 2.4 * s, trunkColor:Lerp(DARK, 0.12), M.Wood)
		cyl(Vector3.new(x, gy + h / 2, z), h, 1.6 * s, trunkColor, M.Wood)
		local a0 = rnd(0, TAU)
		local top = Vector3.new(x, gy + h + 3.4 * s, z)
		local col = pick(leaves)
		blob(top, 5 * s, 4.2 * s, 4.6 * s, 3 * s, col, rnd(0, TAU))
		for k = 0, 1 do
			local a = a0 + k * math.pi + rnd(-0.5, 0.5)
			local off = Vector3.new(math.cos(a) * 4.4 * s, rnd(-1.4, -0.2) * s, math.sin(a) * 4.4 * s)
			stick(Vector3.new(x, gy + h * 0.55, z), top + off * 0.8 - Vector3.new(0, 1.6 * s, 0), 0.75 * s, trunkColor, M.Wood)
			blob(top + off, rnd(3, 3.5) * s, 2.6 * s, 2.8 * s, 2 * s, pick(leaves):Lerp(DARK, 0.05), rnd(0, TAU), true)
		end
	end

	-- ель: 3 яруса-конуса со сдвигом граней, по желанию снежная шапка
	function T.pine(x, z, s, green, snow)
		local gy = B.groundY(x, z)
		green = green or Color3.fromRGB(58, 132, 76)
		cyl(Vector3.new(x, gy + 1.8 * s, z), 3.6 * s, 1.3 * s, Color3.fromRGB(104, 72, 48), M.Wood)
		local tiers = { { 5.0, 5.4 }, { 3.9, 4.8 }, { 2.8, 4.4 } }
		local y = gy + 2.4 * s
		local rot = rnd(0, TAU)
		for i, t in ipairs(tiers) do
			local r, h = t[1] * s, t[2] * s
			local col = green:Lerp(LIGHT, (i - 1) * 0.06)
			cone(Vector3.new(x, y, z), r, h, col, M.SmoothPlastic, 6, rot + i * math.pi / 6)
			if snow and i == #tiers then
				local k = 0.45
				cone(Vector3.new(x, y + h * (1 - k) + 0.05, z), r * k + 0.12, h * k, Color3.fromRGB(246, 250, 255), M.Snow, 6, rot + i * math.pi / 6)
			end
			y += h * 0.52
		end
	end

	-- сакура: как дуб, но розовая крона
	function T.cherry(x, z, s)
		T.oak(x, z, s, { Color3.fromRGB(255, 176, 212), Color3.fromRGB(252, 160, 202), Color3.fromRGB(255, 196, 224) }, Color3.fromRGB(96, 64, 56))
	end

	-- куст: приплюснутый граненый шар
	function T.bush(x, z, s, colors)
		local gy = B.groundY(x, z)
		local r = rnd(1.8, 2.4) * s
		blob(Vector3.new(x, gy + 0.9 * s, z), r, 1.6 * s, 1.5 * s, 0, pick(colors), rnd(0, TAU), true)
	end

	-- пальма: изогнутый ствол и листья из двух частей (свисают)
	function T.palm(x, z, s)
		local gy = B.groundY(x, z)
		local lx, lz = rnd(-0.25, 0.25), rnd(-0.25, 0.25)
		local base = Vector3.new(x, gy, z)
		local top = base
		for i = 0, 5 do
			local p = base + Vector3.new(lx * i * i * 0.35 * s, (i + 0.5) * 1.8 * s, lz * i * i * 0.35 * s)
			cyl(p, 1.9 * s, (1.5 - i * 0.08) * s, (i % 2 == 0) and Color3.fromRGB(150, 110, 70) or Color3.fromRGB(130, 95, 60), M.Wood)
			top = p
		end
		top += Vector3.new(0, 1.1 * s, 0)
		for k = 0, 6 do
			local a = k / 7 * TAU + rnd(-0.2, 0.2)
			local col = Color3.fromRGB(78, 168, 72):Lerp(Color3.fromRGB(56, 136, 60), rnd(0, 1))
			local cf = CFrame.new(top) * CFrame.Angles(0, a, 0) * CFrame.Angles(math.rad(10), 0, 0)
			local c1 = cf * CFrame.new(0, 0, -2.2 * s)
			B.make("Part", c1, Vector3.new(2 * s, 0.3 * s, 4.6 * s), col, M.SmoothPlastic)
			local c2 = cf * CFrame.new(0, 0, -4.4 * s) * CFrame.Angles(math.rad(-35), 0, 0) * CFrame.new(0, 0, -1.8 * s)
			B.make("Part", c2, Vector3.new(1.5 * s, 0.26 * s, 3.8 * s), col:Lerp(DARK, 0.08), M.SmoothPlastic)
		end
		for k = 1, 3 do
			B.make("Part", CFrame.new(top + Vector3.new(math.cos(k * 2) * 0.9, -0.8, math.sin(k * 2) * 0.9)), Vector3.one * 1.1 * s, Color3.fromRGB(120, 85, 40), M.SmoothPlastic, Enum.PartType.Ball)
		end
	end

	T.cone = cone
	return T
end

local TREE_PARENT = nil -- куда класть детали деревьев (по умолчанию F.Nature)
local TREES = makeTrees({
	rnd = rnd,
	groundY = function(x, z) return groundY(x, z) end,
	make = function(cls, cf, size, color, mat, shape)
		local props = { ClassName = cls, CFrame = cf, Size = size, Color = color, Material = mat or M.SmoothPlastic, CastShadow = size.Magnitude > 3 }
		if shape then props.Shape = shape end
		return part(props, TREE_PARENT or F.Nature)
	end,
})
local function treeOak(x, z, s) TREES.oak(x, z, s, GREENS) end
local function treeCherry(x, z, s) TREES.cherry(x, z, s) end
local function treePine(x, z, s) TREES.pine(x, z, s) end
local function bush(x, z, s) TREES.bush(x, z, s, GREENS) end

local function chest(pos, facing, kind)
	local m = Instance.new("Model")
	m.Name = kind .. "Chest"
	local mythic = kind == "Mythic"
	local body = mythic and rgb(95, 45, 160) or rgb(150, 95, 50)
	local trim = mythic and rgb(255, 120, 230) or GOLD
	local mat = mythic and M.SmoothPlastic or M.WoodPlanks
	local cf = CFrame.lookAt(pos, pos + facing)
	local base = box(cf, Vector3.new(4.2, 2.6, 3), body, mat, m)
	-- крышка: полуцилиндр вдоль ширины сундука
	box(cf * CFrame.new(0, 1.3, 0), Vector3.new(4.2, 3, 3), body, mat, m, { Shape = Enum.PartType.Cylinder })
	for _, sx in ipairs({ -1.5, 1.5 }) do
		box(cf * CFrame.new(sx, 0, 0), Vector3.new(0.45, 2.7, 3.1), trim, mythic and M.Neon or M.Metal, m)
	end
	box(cf * CFrame.new(0, 1.3, 0), Vector3.new(4.3, 0.35, 3.1), trim, mythic and M.Neon or M.Metal, m)
	local lock = diamond((cf * CFrame.new(0, 1.1, -1.6)).Position, 0.9, mythic and rgb(120, 240, 255) or rgb(255, 80, 120), M.Neon, m)
	light(lock, mythic and rgb(220, 130, 255) or rgb(255, 210, 120), 12, 1.6)
	m.PrimaryPart = base
	return m
end

---------------------------------------------------------------- ТЕМЫ ПОРТАЛОВ (материалы арки и украшения вокруг)

-- точка на земле в системе портала: x — вбок, z — назад (за арку), -z — к площади
local function gpos(cf, x, z)
	local p = (cf * CFrame.new(x, 0, z)).Position
	return Vector3.new(p.X, groundY(p.X, p.Z), p.Z)
end
local function face(cf) return CFrame.lookAt(Vector3.zero, cf.LookVector) end -- поворот «лицом к площади»

local function cactus(m, pos, h)
	local G = rgb(84, 160, 80)
	vcyl(pos + Vector3.new(0, h / 2, 0), h, 1.8, G, M.SmoothPlastic, m)
	ball(pos + Vector3.new(0, h, 0), 1.8, G, M.SmoothPlastic, m)
	for _, sx in ipairs({ -1, 1 }) do
		local y = h * rnd(0.4, 0.6)
		local arm = pos + Vector3.new(sx * 1.6, y, 0)
		box(CFrame.new(pos + Vector3.new(sx * 0.9, y, 0)), Vector3.new(1.8, 1.1, 1.1), G, M.SmoothPlastic, m)
		vcyl(arm + Vector3.new(0, 1.2, 0), 2.6, 1.2, G, M.SmoothPlastic, m)
		ball(arm + Vector3.new(0, 2.5, 0), 1.2, G, M.SmoothPlastic, m)
	end
end

local function barrel(m, pos)
	vcyl(pos + Vector3.new(0, 1.5, 0), 3, 2.6, rgb(130, 86, 50), M.WoodPlanks, m)
	for _, y in ipairs({ 0.6, 2.4 }) do
		vcyl(pos + Vector3.new(0, y, 0), 0.3, 2.75, rgb(70, 66, 70), M.Metal, m)
	end
end

local function tombstone(m, pos, cf)
	local rot = face(cf) * CFrame.Angles(math.rad(rnd(-8, 8)), math.rad(rnd(-15, 15)), math.rad(rnd(-6, 6)))
	local base = CFrame.new(pos) * rot
	local c = rgb(128, 124, 140):Lerp(rgb(90, 88, 100), rnd(0, 1))
	box(base * CFrame.new(0, 1.3, 0), Vector3.new(2.4, 2.6, 0.7), c, M.Slate, m)
	box(base * CFrame.new(0, 2.6, 0) * CFrame.Angles(0, math.pi / 2, 0), Vector3.new(0.7, 2.4, 2.4), c, M.Slate, m, { Shape = Enum.PartType.Cylinder })
	box(base * CFrame.new(0, 1.9, -0.37), Vector3.new(1.2, 0.25, 0.05), rgb(60, 56, 70), M.Slate, m)
	box(base * CFrame.new(0, 1.9, -0.37), Vector3.new(0.25, 1.1, 0.05), rgb(60, 56, 70), M.Slate, m)
end

local function pumpkin(m, pos)
	local o = rgb(255, 140, 40)
	for k = -1, 1 do
		ball(pos + Vector3.new(k * 0.55, 1, 0), 2.1, o:Lerp(rgb(220, 100, 20), math.abs(k) * 0.4), M.SmoothPlastic, m)
	end
	vcyl(pos + Vector3.new(0, 2.25, 0), 0.6, 0.4, rgb(90, 120, 50), M.Wood, m)
	local glow = ball(pos + Vector3.new(0, 1, 0), 1.2, rgb(255, 200, 80), M.Neon, m, { CanCollide = false, Transparency = 0.6 })
	light(glow, rgb(255, 170, 60), 10, 1.2)
end

local function lollipop(m, pos, cf, c1, c2, h)
	vcyl(pos + Vector3.new(0, h / 2, 0), h, 0.5, WHITE, M.SmoothPlastic, m)
	local disc = CFrame.new(pos + Vector3.new(0, h + 1.6, 0)) * face(cf) * CFrame.Angles(0, math.pi / 2, 0)
	box(disc, Vector3.new(0.6, 4.2, 4.2), c1, M.SmoothPlastic, m, { Shape = Enum.PartType.Cylinder })
	box(disc * CFrame.new(-0.05, 0, 0), Vector3.new(0.6, 2.9, 2.9), c2, M.SmoothPlastic, m, { Shape = Enum.PartType.Cylinder })
	box(disc * CFrame.new(-0.1, 0, 0), Vector3.new(0.6, 1.5, 1.5), c1, M.SmoothPlastic, m, { Shape = Enum.PartType.Cylinder })
end

local function candyCane(m, pos, cf)
	for k = 0, 7 do
		vcyl(pos + Vector3.new(0, 0.4 + k * 0.8, 0), 0.8, 1, k % 2 == 0 and rgb(240, 50, 70) or WHITE, M.SmoothPlastic, m)
	end
	local top = pos + Vector3.new(0, 6.8, 0)
	local side = cf.RightVector
	for k = 1, 5 do
		local a = k / 5 * math.pi
		local p = top + side * (1 - math.cos(a)) * 0.9 + Vector3.new(0, math.sin(a) * 0.9, 0)
		ball(p, 1, k % 2 == 0 and rgb(240, 50, 70) or WHITE, M.SmoothPlastic, m)
	end
end

local function planet(m, pos, c, d, ringC)
	local b = ball(pos, d, c, M.SmoothPlastic, m, { CanCollide = false })
	floaty(b, 0.6, 20, 0.8)
	if ringC then
		local r = box(CFrame.new(pos) * CFrame.Angles(0.4, 0, 0.3) * CFrame.Angles(0, 0, math.pi / 2), Vector3.new(0.15, d * 1.8, d * 1.8), ringC, M.Neon, m, { Shape = Enum.PartType.Cylinder, CanCollide = false, Transparency = 0.4 })
		floaty(r, 0.6, 20, 0.8)
	end
end

local function rocket(m, pos)
	vcyl(pos + Vector3.new(0, 5.5, 0), 9, 3, rgb(240, 240, 250), M.SmoothPlastic, m)
	TREES.cone(pos + Vector3.new(0, 10, 0), 1.6, 3.4, rgb(240, 70, 80), M.SmoothPlastic, 8, 0)
	ball(pos + Vector3.new(0, 7.5, 0) + Vector3.new(0, 0, 0), 1.6, rgb(90, 200, 255), M.Neon, m)
	for k = 0, 3 do
		local a = k * math.pi / 2
		box(CFrame.new(pos + Vector3.new(math.cos(a) * 1.8, 1.8, math.sin(a) * 1.8)) * CFrame.Angles(0, -a, 0), Vector3.new(1.6, 3.4, 0.3), rgb(240, 70, 80), M.SmoothPlastic, m)
	end
	local flame = box(CFrame.new(pos + Vector3.new(0, 0.5, 0)), Vector3.new(1.6, 1, 1.6), rgb(255, 170, 60), M.Neon, m, { CanCollide = false })
	light(flame, rgb(255, 150, 60), 12, 1.5)
end

local PORTAL_THEMES = {
	Default = { base = SLATE, baseMat = M.Slate, plat = MARBLE, platMat = M.Marble, col = MARBLE, colMat = M.Marble, trim = GOLD, trimMat = M.Metal },

	Valley = {
		base = rgb(120, 112, 96), baseMat = M.Cobblestone, plat = rgb(222, 212, 186), platMat = M.Limestone,
		col = rgb(178, 170, 150), colMat = M.Cobblestone, trim = rgb(96, 172, 70), trimMat = M.LeafyGrass,
		decor = function(m, cf, archC)
			TREES.oak(gpos(cf, -12, 16).X, gpos(cf, -12, 16).Z, 0.7, GREENS)
			TREES.oak(gpos(cf, 12, 17).X, gpos(cf, 12, 17).Z, 0.65, GREENS)
			for _, sx in ipairs({ -1, 1 }) do
				-- плющ по колоннам
				for k = 0, 6 do
					local p = archC * CFrame.new(sx * (9 + (k % 2 == 0 and 1.6 or -1.6)), 3 + k * 2.3, -1.6)
					ball(p.Position, rnd(1.1, 1.6), GREENS[(k % #GREENS) + 1], M.LeafyGrass, m, { CanCollide = false })
				end
				TREES.bush(gpos(cf, sx * 15, 3).X, gpos(cf, sx * 15, 3).Z, 0.9, GREENS)
				flowers(gpos(cf, sx * 13.5, 9), 2.6, 9, m)
				-- грибок
				local g = gpos(cf, sx * 15.5, 10)
				vcyl(g + Vector3.new(0, 0.9, 0), 1.8, 0.8, rgb(245, 235, 215), M.SmoothPlastic, m)
				ball(g + Vector3.new(0, 2, 0), 2.4, rgb(230, 60, 60), M.SmoothPlastic, m)
			end
		end,
	},

	Canyon = {
		base = rgb(176, 124, 72), baseMat = M.Sandstone, plat = rgb(234, 204, 146), platMat = M.Sandstone,
		col = rgb(226, 182, 116), colMat = M.Sandstone, trim = rgb(196, 112, 56), trimMat = M.Sandstone,
		decor = function(m, cf)
			cactus(m, gpos(cf, -14, 12), 6)
			cactus(m, gpos(cf, 14.5, 13), 5)
			cactus(m, gpos(cf, -16, -2), 4)
			local pyr = gpos(cf, 0, 19)
			TREES.cone(pyr, 7, 8, rgb(226, 190, 120), M.Sandstone, 4, math.rad(45) + math.atan2(cf.LookVector.X, cf.LookVector.Z))
			for _, sx in ipairs({ -1, 1 }) do
				local pot = gpos(cf, sx * 12.5, 4)
				ball(pot + Vector3.new(0, 1.1, 0), 2.2, rgb(196, 112, 56), M.Sandstone, m)
				vcyl(pot + Vector3.new(0, 2.3, 0), 0.8, 1.1, rgb(176, 96, 46), M.Sandstone, m)
			end
			for _ = 1, 4 do
				local r = gpos(cf, rnd(-15, 15), rnd(11, 21))
				box(CFrame.new(r + Vector3.new(0, 0.6, 0)) * CFrame.Angles(rnd(0, 1), rnd(0, 6), rnd(0, 1)), Vector3.new(rnd(1.5, 2.6), rnd(1.2, 2), rnd(1.5, 2.6)), rgb(200, 150, 96), M.Sandstone, m)
			end
		end,
	},

	Frozen = {
		base = rgb(150, 192, 224), baseMat = M.Ice, plat = rgb(238, 246, 255), platMat = M.Snow,
		col = rgb(176, 220, 252), colMat = M.Ice, trim = rgb(250, 252, 255), trimMat = M.Snow,
		decor = function(m, cf, archC)
			TREES.pine(gpos(cf, -12, 16).X, gpos(cf, -12, 16).Z, 0.75, rgb(52, 116, 84), true)
			TREES.pine(gpos(cf, 12.5, 17).X, gpos(cf, 12.5, 17).Z, 0.85, rgb(52, 116, 84), true)
			TREES.pine(gpos(cf, 0, 22).X, gpos(cf, 0, 22).Z, 0.7, rgb(56, 122, 88), true)
			-- сосульки под аркой
			for _, x in ipairs({ -5.5, -3, -1, 1, 3, 5.5 }) do
				local y = 18.8 + math.sqrt(math.max(0, 7.55 * 7.55 - x * x)) - 0.2
				local p = (archC * CFrame.new(x, y, -1.4)).Position
				TREES.cone(p, 0.45, -rnd(1.6, 2.8), rgb(200, 235, 255), M.Ice, 4, rnd(0, 1))
			end
			-- снег на верхушках колонн
			for _, sx in ipairs({ -9, 9 }) do
				box(archC * CFrame.new(sx, 19, 0), Vector3.new(4.4, 0.5, 4.4), rgb(250, 252, 255), M.Snow, m)
			end
			-- снеговик
			local s = gpos(cf, 14.5, 4)
			ball(s + Vector3.new(0, 1.4, 0), 2.8, WHITE, M.Snow, m)
			ball(s + Vector3.new(0, 3.4, 0), 2.1, WHITE, M.Snow, m)
			ball(s + Vector3.new(0, 4.9, 0), 1.5, WHITE, M.Snow, m)
			box(CFrame.lookAt(s + Vector3.new(0, 4.9, 0), s + Vector3.new(0, 4.9, 0) + cf.LookVector) * CFrame.new(0, 0, -0.9), Vector3.new(0.3, 0.3, 0.9), rgb(255, 140, 40), M.SmoothPlastic, m)
			-- ледяные кристаллы
			for _ = 1, 3 do
				local c = gpos(cf, rnd(-16, -12), rnd(-2, 8))
				diamond(c + Vector3.new(0, 1.4, 0), rnd(1.6, 2.4), rgb(170, 225, 255), M.Ice, m)
			end
		end,
	},

	Volcano = {
		base = rgb(44, 38, 42), baseMat = M.Basalt, plat = rgb(72, 60, 62), platMat = M.Basalt,
		col = rgb(54, 46, 52), colMat = M.Basalt, trim = rgb(255, 120, 40), trimMat = M.Neon,
		decor = function(m, cf, archC)
			for _, p in ipairs({ { -13, 12, 6 }, { 13.5, 13, 7.5 }, { -15.5, 2, 4.5 }, { 15.5, 3, 5 }, { 0, 20, 9 } }) do
				TREES.cone(gpos(cf, p[1], p[2]), p[3] * 0.32, p[3], rgb(40, 34, 38), M.Basalt, 5, rnd(0, 6))
			end
			for _, sx in ipairs({ -1, 1 }) do
				local pool = gpos(cf, sx * 10.5, 18)
				local lava = vcyl(pool + Vector3.new(0, 0.1, 0), 0.4, 5.5, rgb(255, 110, 30), M.Neon, m, { CanCollide = false })
				light(lava, rgb(255, 120, 40), 18, 2)
				emitter(lava, { Color = rgb(255, 160, 60), Color2 = rgb(255, 60, 20), Size = NumberSequence.new(0.6, 0), Lifetime = NumberRange.new(0.8, 1.4), Speed = NumberRange.new(2, 5), Rate = 12, EmissionDirection = Enum.NormalId.Right })
				-- огонь на колоннах
				local top = anchor((archC * CFrame.new(sx * 9, 19.4, 0)).Position, Vector3.new(2, 0.4, 2), m)
				emitter(top, { Color = rgb(255, 190, 80), Color2 = rgb(255, 70, 20), Size = NumberSequence.new(1.4, 0), Lifetime = NumberRange.new(0.6, 1.1), Speed = NumberRange.new(4, 7), Rate = 26, LightEmission = 1, EmissionDirection = Enum.NormalId.Top })
				light(top, rgb(255, 130, 50), 16, 1.8)
				-- светящиеся трещины на колоннах
				for k = 0, 3 do
					box(archC * CFrame.new(sx * 9 + rnd(-0.8, 0.8), 5 + k * 3.4, -1.75) * CFrame.Angles(0, 0, rnd(-0.6, 0.6)), Vector3.new(0.25, 2.2, 0.1), rgb(255, 120, 40), M.Neon, m, { CanCollide = false })
				end
			end
		end,
	},

	Graveyard = {
		base = rgb(70, 66, 80), baseMat = M.Slate, plat = rgb(102, 98, 114), platMat = M.Slate,
		col = rgb(112, 106, 124), colMat = M.Cobblestone, trim = rgb(160, 120, 230), trimMat = M.Neon,
		decor = function(m, cf, archC)
			for _, p in ipairs({ { -13, 12 }, { -9, 17 }, { 9, 16 }, { 14, 11 }, { -15, 4 }, { 15.5, 5 } }) do
				tombstone(m, gpos(cf, p[1], p[2]), cf)
			end
			pumpkin(m, gpos(cf, -12.5, -3))
			pumpkin(m, gpos(cf, 13, -2))
			pumpkin(m, gpos(cf, 3, 19))
			-- сухое дерево
			local t = gpos(cf, 0, 21)
			vcyl(t + Vector3.new(0, 4, 0), 8, 1.2, rgb(60, 50, 52), M.Wood, m)
			for k = 0, 3 do
				local a = k * math.pi / 2 + 0.4
				local from = t + Vector3.new(0, 5 + k * 0.6, 0)
				local to = from + Vector3.new(math.cos(a) * 3, 2.4, math.sin(a) * 3)
				box(CFrame.lookAt((from + to) / 2, to), Vector3.new(0.45, 0.45, (to - from).Magnitude), rgb(60, 50, 52), M.Wood, m)
			end
			-- свечи у колонн
			for _, sx in ipairs({ -11.5, 11.5 }) do
				local c = (archC * CFrame.new(sx, 0, -2)).Position
				c = Vector3.new(c.X, groundY(c.X, c.Z), c.Z)
				vcyl(c + Vector3.new(0, 0.8, 0), 1.6, 0.6, rgb(240, 236, 220), M.SmoothPlastic, m)
				local f = ball(c + Vector3.new(0, 1.9, 0), 0.5, rgb(255, 200, 90), M.Neon, m, { CanCollide = false })
				light(f, rgb(255, 190, 90), 10, 1.4)
			end
			-- фиолетовый туман
			local fog = anchor(gpos(cf, 0, 12) + Vector3.new(0, 0.6, 0), Vector3.new(26, 0.4, 14), m)
			emitter(fog, { Texture = "rbxasset://textures/particles/smoke_main.dds", Color = rgb(170, 140, 220), Size = NumberSequence.new(3, 6), Transparency = NumberSequence.new(0.75, 1), Lifetime = NumberRange.new(3, 5), Speed = NumberRange.new(0.3, 0.8), Rate = 5 })
		end,
	},

	Pirate = {
		base = rgb(110, 74, 46), baseMat = M.WoodPlanks, plat = rgb(152, 106, 66), platMat = M.WoodPlanks,
		col = rgb(124, 84, 52), colMat = M.Wood, trim = rgb(214, 176, 92), trimMat = M.Metal,
		decor = function(m, cf)
			barrel(m, gpos(cf, -13, 3))
			barrel(m, gpos(cf, -15, 6))
			barrel(m, gpos(cf, 13.5, 4))
			local ch = chest(gpos(cf, 12.5, 9) + Vector3.new(0, 1.3, 0), cf.LookVector, "Gold")
			ch.Parent = m
			TREES.palm(gpos(cf, -12, 17).X, gpos(cf, -12, 17).Z, 0.8)
			TREES.palm(gpos(cf, 12, 18).X, gpos(cf, 12, 18).Z, 0.75)
			-- якорь
			local a = CFrame.new(gpos(cf, 0, 18)) * face(cf) * CFrame.Angles(0, 0, math.rad(12))
			local IRN = rgb(70, 72, 82)
			box(a * CFrame.new(0, 4, 0), Vector3.new(0.9, 8, 0.9), IRN, M.Metal, m)
			box(a * CFrame.new(0, 6.6, 0), Vector3.new(4.2, 0.7, 0.7), IRN, M.Metal, m)
			box(a * CFrame.new(0, 8.6, 0) * CFrame.Angles(0, math.pi / 2, 0), Vector3.new(0.4, 1.8, 1.8), IRN, M.Metal, m, { Shape = Enum.PartType.Cylinder })
			for _, sx in ipairs({ -1, 1 }) do
				box(a * CFrame.new(sx * 1.4, 0.9, 0) * CFrame.Angles(0, 0, sx * math.rad(55)), Vector3.new(0.8, 3.4, 0.8), IRN, M.Metal, m)
				box(a * CFrame.new(sx * 2.6, 2, 0) * CFrame.Angles(0, 0, sx * math.rad(-20)), Vector3.new(0.9, 1.4, 0.9), IRN, M.Metal, m)
			end
			-- монеты
			for _ = 1, 8 do
				local c = gpos(cf, rnd(10, 15), rnd(6, 12))
				box(CFrame.new(c + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, rnd(0, 6), math.pi / 2), Vector3.new(0.25, 1, 1), GOLD, M.Metal, m, { Shape = Enum.PartType.Cylinder, CanCollide = false })
			end
		end,
	},

	Candy = {
		base = rgb(255, 190, 220), baseMat = M.SmoothPlastic, plat = rgb(255, 242, 248), platMat = M.SmoothPlastic,
		col = rgb(255, 255, 255), col2 = rgb(255, 96, 156), colMat = M.SmoothPlastic, stripes = true,
		trim = rgb(130, 232, 200), trimMat = M.SmoothPlastic,
		decor = function(m, cf)
			lollipop(m, gpos(cf, -14, 9), cf, rgb(255, 90, 150), rgb(255, 230, 90), 6)
			lollipop(m, gpos(cf, 14, 10), cf, rgb(110, 200, 255), WHITE, 7)
			lollipop(m, gpos(cf, -6, 19), cf, rgb(170, 110, 255), rgb(255, 160, 210), 8)
			lollipop(m, gpos(cf, 7, 20), cf, rgb(120, 230, 150), rgb(255, 250, 200), 6.5)
			candyCane(m, gpos(cf, -13, -1), cf)
			candyCane(m, gpos(cf, 13, 0), cf)
			-- кекс
			local k = gpos(cf, 0, 22)
			vcyl(k + Vector3.new(0, 1.6, 0), 3.2, 5, rgb(255, 160, 200), M.SmoothPlastic, m)
			ball(k + Vector3.new(0, 3.6, 0), 5.2, rgb(255, 245, 250), M.SmoothPlastic, m)
			ball(k + Vector3.new(0, 5.9, 0), 1.4, rgb(230, 30, 60), M.SmoothPlastic, m)
			-- мармеладки
			local GUM = { rgb(255, 90, 120), rgb(120, 220, 140), rgb(255, 220, 90), rgb(150, 130, 255), rgb(110, 200, 255) }
			for i = 1, 10 do
				local g = gpos(cf, rnd(-16, 16), rnd(11, 24))
				ball(g + Vector3.new(0, 0.6, 0), rnd(1, 1.6), GUM[(i % #GUM) + 1], M.SmoothPlastic, m)
			end
		end,
	},

	Space = {
		base = rgb(40, 42, 60), baseMat = M.DiamondPlate, plat = rgb(72, 76, 104), platMat = M.Metal,
		col = rgb(62, 66, 90), colMat = M.Metal, trim = rgb(90, 230, 255), trimMat = M.Neon,
		decor = function(m, cf, archC)
			rocket(m, gpos(cf, -13.5, 14))
			-- антенна-тарелка
			local d = gpos(cf, 13.5, 14)
			vcyl(d + Vector3.new(0, 2, 0), 4, 0.8, rgb(180, 185, 200), M.Metal, m)
			local dishCF = CFrame.new(d + Vector3.new(0, 4.6, 0)) * face(cf) * CFrame.Angles(math.rad(35), 0, 0) * CFrame.Angles(0, math.pi / 2, 0)
			box(dishCF, Vector3.new(0.5, 5, 5), rgb(220, 224, 236), M.SmoothPlastic, m, { Shape = Enum.PartType.Cylinder })
			local tip = ball((dishCF * CFrame.new(-1.8, 0, 0)).Position, 0.7, rgb(90, 230, 255), M.Neon, m)
			light(tip, rgb(90, 230, 255), 10, 1.4)
			-- планеты над аркой
			planet(m, (archC * CFrame.new(-14, 24, 2)).Position, rgb(255, 150, 90), 3.4, rgb(255, 220, 160))
			planet(m, (archC * CFrame.new(14, 27, 2)).Position, rgb(120, 140, 255), 2.6, nil)
			planet(m, (archC * CFrame.new(8, 33, 4)).Position, rgb(150, 255, 200), 1.6, nil)
			-- неоновые антенны на колоннах
			for _, sx in ipairs({ -9, 9 }) do
				box(archC * CFrame.new(sx, 21, 0), Vector3.new(0.3, 4, 0.3), rgb(180, 185, 200), M.Metal, m)
				local b = ball((archC * CFrame.new(sx, 23.2, 0)).Position, 0.9, rgb(255, 90, 200), M.Neon, m)
				light(b, rgb(255, 90, 200), 8, 1.2)
			end
			-- звёзды
			for _ = 1, 6 do
				local s = diamond((archC * CFrame.new(rnd(-16, 16), rnd(6, 26), rnd(6, 14))).Position, rnd(0.6, 1.1), rgb(255, 255, 210), M.Neon, m, { CanCollide = false })
				floaty(s, 0.4, 40, rnd(0.8, 1.4))
			end
		end,
	},
}

---------------------------------------------------------------- ПОРТАЛЫ КАРТ

local function buildPortal(id, deg)
	local d = MapConfig[id]
	local color = d.Color
	local light2 = color:Lerp(WHITE, 0.45)
	local center = dirAt(deg) * PORTAL_R
	local cf = CFrame.lookAt(center, Vector3.zero) -- -Z смотрит на площадь
	local m = Instance.new("Model")
	m.Name = id
	m.Parent = F.Portals
	local th = PORTAL_THEMES[id] or PORTAL_THEMES.Default

	-- платформа со ступенькой
	vcyl(center + Vector3.new(0, -0.2, 0), 2, 30, th.base, th.baseMat, m)
	vcyl(center + Vector3.new(0, 0.5, 0), 1.2, 27, th.plat, th.platMat, m)
	vcyl(center + Vector3.new(0, 0.62, 0), 0.9, 27.8, th.trim, th.trimMat, m)

	-- круг-очередь: встань сюда
	local padPos = (cf * CFrame.new(0, 0, -3)).Position + Vector3.new(0, 1.2, 0)
	local pad = vcyl(padPos, 0.3, 15, color, M.Neon, m, { Transparency = 0.3, CanCollide = false, CastShadow = false })
	pad.Name = "Pad"
	pad:SetAttribute("Map", id)
	pad:SetAttribute("Radius", 7.5)
	vcyl(padPos + Vector3.new(0, -0.05, 0), 0.3, 16.4, light2, M.Neon, m, { Transparency = 0.55, CanCollide = false, CastShadow = false })
	emitter(pad, {
		Color = light2, Color2 = color, Size = NumberSequence.new(0.5, 0), Lifetime = NumberRange.new(1.4, 2.2),
		Speed = NumberRange.new(2, 4.5), Spread = Vector2.new(8, 8), Rate = 16, EmissionDirection = Enum.NormalId.Right,
	})

	-- арка: две колонны и полукруг
	local archC = cf * CFrame.new(0, 0, 7.5)
	for _, sx in ipairs({ -9, 9 }) do
		local col = archC * CFrame.new(sx, 0, 0)
		box(col * CFrame.new(0, 1.8, 0), Vector3.new(4.6, 2.4, 4.6), th.base, th.baseMat, m)
		if th.stripes then
			for k = 0, 6 do
				box(col * CFrame.new(0, 3.8 + k * 2.2, 0) * CFrame.Angles(0, k * 0.5, 0), Vector3.new(3.4, 2.2, 3.4), k % 2 == 0 and th.col or th.col2, th.colMat, m)
			end
		else
			box(col * CFrame.new(0, 10.5, 0), Vector3.new(3.4, 15.5, 3.4), th.col, th.colMat, m)
		end
		box(col * CFrame.new(0, 18.4, 0), Vector3.new(4.2, 0.8, 4.2), th.trim, th.trimMat, m)
	end
	local th2 = th
	local SEG = 11
	for k = 0, SEG - 1 do
		local th = math.pi * (k + 0.5) / SEG
		local pos = archC * CFrame.new(math.cos(th) * 9, 18.8 + math.sin(th) * 9, 0)
		box(pos * CFrame.Angles(0, 0, th - math.pi / 2), Vector3.new(3.6, 2.9, 3.4), (th2.stripes and k % 2 == 1) and th2.col2 or th2.col, th2.colMat, m)
		if k % 2 == 0 then
			box(pos * CFrame.Angles(0, 0, th - math.pi / 2) * CFrame.new(0, 1.5, 0), Vector3.new(3.7, 0.35, 3.6), th2.trim, th2.trimMat, m)
		end
	end

	-- окно портала по форме арки: прямоугольник + полукруг из полосок (края спрятаны в камне)
	local BOTTOM, SPRING, R, W = 1.2, 18.8, 7.5, 14.8
	local function door(z, mat, c, transp, name)
		local h = SPRING - BOTTOM
		local main = box(archC * CFrame.new(0, BOTTOM + h / 2, z), Vector3.new(W, h, 0.5), c, mat, m, { CanCollide = false, CastShadow = false, Transparency = transp })
		main.Name = name
		local N = 7
		for k = 0, N - 1 do
			local y0 = k * R / N
			local w = 2 * math.sqrt(R * R - y0 * y0)
			local s = box(archC * CFrame.new(0, SPRING + y0 + R / N / 2, z), Vector3.new(w, R / N + 0.02, 0.5), c, mat, m, { CanCollide = false, CastShadow = false, Transparency = transp })
			s.Name = name .. "Top"
		end
		return main
	end
	local disc = door(0, M.ForceField, color, 0, "Portal")
	door(0.6, M.Neon, light2, 0.5, "PortalGlow")
	emitter(disc, {
		Color = light2, Color2 = color, Size = NumberSequence.new(0.7, 0), Lifetime = NumberRange.new(1, 1.8),
		Speed = NumberRange.new(0.5, 2), Rate = 30, RotSpeed = NumberRange.new(-200, 200),
	})
	light(disc, color, 30, 2.5)

	-- табличка на верху арки: название, волны, награда
	local boardCF = archC * CFrame.new(0, 32.6, -0.4) * CFrame.Angles(math.rad(-10), 0, 0)
	local board = box(boardCF, Vector3.new(15, 6.2, 0.8), rgb(40, 28, 70), M.SmoothPlastic, m)
	board.Name = "Board"
	box(boardCF * CFrame.new(0, 0, 0.3), Vector3.new(15.9, 7.1, 0.5), th.trim, th.trimMat, m)
	box(archC * CFrame.new(0, 29.2, 1), Vector3.new(3, 2.4, 1.6), th.col, th.colMat, m)
	sign(board, Enum.NormalId.Front, {
		{ name = "Title", text = string.upper(d.Name), color = light2, h = 0.28, stroke = 4 },
		{ name = "Tagline", text = d.Tagline, color = WHITE, h = 0.14, font = Enum.Font.FredokaOne },
		{ name = "Tier", text = "MAP LEVEL: " .. MapConfig.tier(id).Name, color = MapConfig.tier(id).Color, h = 0.16, stroke = 2.5 },
		{ name = "Party", text = "UP TO " .. PlaceConfig.MaxParty .. " PLAYERS", color = rgb(255, 225, 120), h = 0.14, font = Enum.Font.FredokaOne },
	}, { name = "BoardGui", icon = d.Icon, iconSize = 0.2, PPS = 45 })
	-- самоцвет над табличкой
	local gem = diamond((archC * CFrame.new(0, 38.2, 0)).Position, 2.6, color, M.Neon, m, { CanCollide = false })
	light(gem, color, 26, 2.2)
	floaty(gem, 0.5, 60, 1.4)

	-- табло над кругом: сколько игроков и таймер (меняет HubService)
	local status = anchor(padPos + Vector3.new(0, 8.5, 0), Vector3.new(1, 1, 1), m)
	status.Name = "Status"
	billboard(status, 11, 4.4, {
		{ name = "Count", text = "0 / " .. PlaceConfig.MaxParty, color = rgb(255, 230, 120), h = 0.52 },
		{ name = "Timer", text = "STAND HERE TO PLAY", color = WHITE, h = 0.32, font = Enum.Font.FredokaOne },
	}, { name = "StatusGui", border = light2, maxDistance = 140 })

	-- флажки по бокам
	for _, sx in ipairs({ -12.4, 12.4 }) do
		local pole = cf * CFrame.new(sx, 0, 2)
		box(pole * CFrame.new(0, 7, 0), Vector3.new(0.6, 14, 0.6), IRON, M.Metal, m)
		ball((pole * CFrame.new(0, 14.2, 0)).Position, 1.1, GOLD, M.Metal, m)
		box(pole * CFrame.new(sx > 0 and 1.8 or -1.8, 11.6, 0), Vector3.new(3, 4.4, 0.2), color, M.Fabric, m)
	end

	-- украшения по теме карты
	if th.decor then
		TREE_PARENT = m
		local ok, err = pcall(th.decor, m, cf, archC, color)
		TREE_PARENT = nil
		if not ok then warn("[HubBuilder] украшения портала " .. id .. ": " .. tostring(err)) end
	end
	return m
end

for id, deg in pairs(PORTAL_ANGLES) do
	buildPortal(id, deg)
end

---------------------------------------------------------------- МАГАЗИН (прилавок с сундуками)


local function buildShop(info)
	local d = dirAt(info.angle)
	local center = d * info.r
	local cf = CFrame.lookAt(center, Vector3.zero)
	local m = Instance.new("Model")
	m.Name = "Shop"
	m.Parent = F.Places
	-- деревянный настил
	box(cf * CFrame.new(0, 0.5, 0), Vector3.new(28, 1, 18), rgb(170, 120, 75), M.WoodPlanks, m)
	-- прилавок
	local counter = box(cf * CFrame.new(0, 2.6, -4.5), Vector3.new(20, 3.4, 3), rgb(160, 105, 64), M.WoodPlanks, m)
	box(cf * CFrame.new(0, 4.45, -4.5), Vector3.new(20.6, 0.4, 3.6), GOLD, M.Metal, m)
	box(cf * CFrame.new(0, 2.6, -6.05), Vector3.new(18, 1, 0.2), rgb(255, 110, 170), M.SmoothPlastic, m)
	-- столбы
	for _, p in ipairs({ { -12, -7 }, { 12, -7 }, { -12, 7 }, { 12, 7 } }) do
		box(cf * CFrame.new(p[1], 7.5, p[2]), Vector3.new(1.4, 14, 1.4), DARKWOOD, M.Wood, m)
	end
	-- полосатый тент (две стороны)
	local STRIPES = { rgb(255, 105, 170), rgb(255, 245, 235) }
	for side = -1, 1, 2 do
		for i = 0, 9 do
			local x = -12.6 + i * 2.8 + 1.4
			box(cf * CFrame.new(x, 16.2, side * 4.4) * CFrame.Angles(side * math.rad(-24), 0, 0), Vector3.new(2.8, 0.45, 10), STRIPES[(i % 2) + 1], M.Fabric, m)
		end
	end
	-- фестончики по краю тента
	for i = 0, 13 do
		local x = -13 + i * 2
		ball((cf * CFrame.new(x, 13.8, -9.2)).Position, 1.6, STRIPES[(i % 2) + 1], M.Fabric, m, { CanCollide = false })
	end
	-- сундуки парят над прилавком
	for i, kind in ipairs({ "Hero", "Mythic" }) do
		local pos = (cf * CFrame.new(i == 1 and -4.5 or 4.5, 7.6, -4.5)).Position
		local c = chest(pos, cf.LookVector, kind)
		c.Parent = m
		floaty(c, 0.6, 20, 1 + i * 0.2)
		local glowP = anchor(pos, Vector3.new(3, 3, 3), m)
		emitter(glowP, {
			Color = kind == "Mythic" and rgb(230, 150, 255) or rgb(255, 225, 140), Size = NumberSequence.new(0.6, 0),
			Lifetime = NumberRange.new(0.8, 1.4), Speed = NumberRange.new(1.5, 3), Rate = 12,
		})
	end
	-- горка самоцветов
	for _ = 1, 7 do
		diamond((cf * CFrame.new(rnd(-8.5, 8.5), 4.95, rnd(-5.2, -3.8))).Position, rnd(0.6, 1), Color3.fromHSV(rnd(0.75, 0.95), 0.6, 1), M.Neon, m, { CanCollide = false })
	end
	-- вывеска
	local signPart = box(cf * CFrame.new(0, 20.4, -7.6), Vector3.new(12, 4.2, 0.7), rgb(255, 120, 180), M.SmoothPlastic, m)
	box(cf * CFrame.new(0, 20.4, -7.4), Vector3.new(12.8, 5, 0.5), GOLD, M.Metal, m)
	sign(signPart, Enum.NormalId.Front, { { text = "SHOP", color = WHITE, h = 0.62, stroke = 5 } }, { icon = "shop", iconSize = 0.7, PPS = 45 })
	for _, sx in ipairs({ -4, 4 }) do
		box(cf * CFrame.new(sx, 17.6, -7.5), Vector3.new(0.4, 1.6, 0.4), IRON, M.Metal, m)
	end
	prompt(counter, "Open Shop", "Chests & Gems", "Shop")
	light(signPart, rgb(255, 170, 210), 18, 1.4)
end

---------------------------------------------------------------- ХРАМ ЮНИТОВ (со статуями)

local function statue(name, pos, facing, scale, plateDist)
	local templates = ReplicatedStorage:FindFirstChild("Towers")
	local template = templates and templates:FindFirstChild(name)
	if not template then return end
	local ok = pcall(function()
		local model = template:Clone()
		for _, s in ipairs(model:GetDescendants()) do
			if s:IsA("LuaSourceContainer") then s:Destroy() end
		end
		PlacementRules.prepareRig(model)
		if scale and scale ~= 1 then
			pcall(function() model:ScaleTo(scale) end)
		end
		model:PivotTo(CFrame.lookAt(pos, pos + facing))
		local bcf, size = model:GetBoundingBox()
		model:PivotTo(model:GetPivot() + Vector3.new(0, pos.Y - (bcf.Position.Y - size.Y / 2), 0))
		model.Name = "Statue_" .. name
		model.Parent = F.Places
	end)
	if ok and plateDist then
		local cfg = TowerData[name] or {}
		local at = pos - Vector3.new(0, 1.6, 0) + facing * plateDist
		local p = box(CFrame.lookAt(at, at + facing), Vector3.new(4.6, 1.2, 0.3), rgb(40, 30, 60), M.SmoothPlastic, F.Places)
		sign(p, Enum.NormalId.Front, {
			{ text = string.upper(name), color = WHITE, h = 0.55 },
			{ text = string.upper(cfg.Rarity or ""), color = rgb(255, 210, 120), h = 0.35, font = Enum.Font.FredokaOne },
		}, { PPS = 60 })
	end
end

local RARITY_RANK = { Common = 1, Rare = 2, Epic = 3, Legendary = 4, Mythic = 5 }
local function bestUnits()
	local list = {}
	for name, cfg in pairs(TowerData) do
		table.insert(list, { name = name, rank = RARITY_RANK[cfg.Rarity] or 0, price = cfg.Price or 0 })
	end
	table.sort(list, function(a, b)
		if a.rank ~= b.rank then return a.rank > b.rank end
		if a.price ~= b.price then return a.price > b.price end
		return a.name < b.name
	end)
	return list
end

local function buildTemple(info)
	local d = dirAt(info.angle)
	local center = d * info.r
	local cf = CFrame.lookAt(center, Vector3.zero)
	local m = Instance.new("Model")
	m.Name = "UnitsTemple"
	m.Parent = F.Places
	vcyl(center + Vector3.new(0, 0.2, 0), 1.6, 32, SLATE, M.Slate, m)
	vcyl(center + Vector3.new(0, 0.9, 0), 1.2, 29, MARBLE, M.Marble, m)
	vcyl(center + Vector3.new(0, 1.02, 0), 0.6, 29.8, GOLD, M.Metal, m)
	-- колонны по кругу (спереди проход)
	for i = 1, 10 do
		local a = (i - 0.5) / 10 * math.pi * 2
		local world = (cf * CFrame.new(math.cos(a) * 12, 0, math.sin(a) * 12)).Position
		local frontness = (cf:VectorToObjectSpace(world - center)).Z
		if frontness > -9 then
			vcyl(world + Vector3.new(0, 8.5, 0), 14.5, 2.2, MARBLE, M.Marble, m)
			vcyl(world + Vector3.new(0, 1.9, 0), 1, 3, GOLD, M.Metal, m)
			vcyl(world + Vector3.new(0, 15.9, 0), 1, 3, GOLD, M.Metal, m)
		end
	end
	-- крыша: барабан, купол и шпиль (нижняя половина купола спрятана в барабане)
	vcyl(center + Vector3.new(0, 18.8, 0), 6, 28.4, MARBLE, M.Marble, m)
	vcyl(center + Vector3.new(0, 16.4, 0), 0.6, 29, GOLD, M.Metal, m)
	vcyl(center + Vector3.new(0, 21.9, 0), 0.5, 29, GOLD, M.Metal, m)
	ball(center + Vector3.new(0, 27, 0), 22, rgb(105, 150, 245), M.SmoothPlastic, m)
	vcyl(center + Vector3.new(0, 38.6, 0), 3.2, 1, GOLD, M.Metal, m)
	local top = diamond(center + Vector3.new(0, 41.5, 0), 2.2, rgb(150, 220, 255), M.Neon, m, { CanCollide = false })
	light(top, rgb(150, 210, 255), 22, 1.8)
	floaty(top, 0.4, 70, 1.3)
	-- постамент со статуей самого редкого юнита
	local units = bestUnits()
	vcyl(center + Vector3.new(0, 2.6, 0), 2.6, 7, MARBLE, M.Marble, m)
	vcyl(center + Vector3.new(0, 3.95, 0), 0.4, 7.6, GOLD, M.Metal, m)
	local ringGlow = vcyl(center + Vector3.new(0, 1.55, 0), 0.2, 10, rgb(255, 120, 200), M.Neon, m, { Transparency = 0.3, CanCollide = false })
	emitter(ringGlow, { Color = rgb(255, 180, 230), Size = NumberSequence.new(0.5, 0), Lifetime = NumberRange.new(1.5, 2.5), Speed = NumberRange.new(1, 3), Rate = 10, EmissionDirection = Enum.NormalId.Right, Spread = Vector2.new(10, 10) })
	local spot = anchor(center + Vector3.new(0, 12, 0), Vector3.one, m)
	light(spot, rgb(255, 230, 200), 18, 1.6)
	if units[1] then
		statue(units[1].name, center + Vector3.new(0, 4.15, 0), cf.LookVector, 1.9, 3.75)
	end
	-- две статуи у входа
	for i, sx in ipairs({ -8.5, 8.5 }) do
		local u = units[i + 1]
		local p = (cf * CFrame.new(sx, 0, -17)).Position
		vcyl(p + Vector3.new(0, 1.5, 0), 3, 5.4, MARBLE, M.Marble, m)
		vcyl(p + Vector3.new(0, 3.1, 0), 0.3, 5.8, GOLD, M.Metal, m)
		if u then statue(u.name, p + Vector3.new(0, 3.25, 0), cf.LookVector, 1.35, 2.95) end
	end
	-- вывеска и кнопка
	local signPart = box(cf * CFrame.new(0, 19, -14.4), Vector3.new(12, 3.8, 0.6), rgb(90, 120, 230), M.SmoothPlastic, m)
	box(cf * CFrame.new(0, 19, -14.2), Vector3.new(12.8, 4.6, 0.4), GOLD, M.Metal, m)
	sign(signPart, Enum.NormalId.Front, { { text = "MY UNITS", color = WHITE, h = 0.6, stroke = 5 } }, { icon = "backpack", iconSize = 0.7, PPS = 45 })
	local btn = vcyl(center + Vector3.new(0, 1.6, 0) + cf.LookVector * 8.5, 0.3, 6, rgb(110, 160, 255), M.Neon, m, { Transparency = 0.35, CanCollide = false })
	prompt(btn, "My Units", "See your collection", "Inventory")
end

---------------------------------------------------------------- ДОСКА КВЕСТОВ, ПОДАРОК ДНЯ, КОДЫ, КЛАНЫ

local function buildQuestBoard(info)
	local center = dirAt(info.angle) * info.r
	local gy = groundY(center.X, center.Z)
	local cf = CFrame.lookAt(center + Vector3.new(0, gy, 0), Vector3.new(0, gy, 0))
	local m = Instance.new("Model")
	m.Name = "QuestBoard"
	m.Parent = F.Places
	for _, sx in ipairs({ -5.5, 5.5 }) do
		box(cf * CFrame.new(sx, 5.5, 0), Vector3.new(1, 11, 1), DARKWOOD, M.Wood, m)
	end
	local board = box(cf * CFrame.new(0, 6.6, 0), Vector3.new(10, 7, 0.6), rgb(176, 124, 76), M.WoodPlanks, m)
	-- крыша-козырёк
	for side = -1, 1, 2 do
		box(cf * CFrame.new(0, 11.4, side * 1.1) * CFrame.Angles(side * math.rad(-30), 0, 0), Vector3.new(12.4, 0.4, 2.8), rgb(200, 70, 70), M.WoodPlanks, m)
	end
	-- записки
	local NOTE = { rgb(255, 250, 230), rgb(255, 235, 150), rgb(200, 235, 255), rgb(255, 210, 230) }
	for i = 1, 6 do
		local x = -3.3 + ((i - 1) % 3) * 3.3 + rnd(-0.3, 0.3)
		local y = 4.4 + math.floor((i - 1) / 3) * 2.7
		box(cf * CFrame.new(x, y, -0.35) * CFrame.Angles(0, 0, rnd(-0.15, 0.15)), Vector3.new(2.4, 2.2, 0.1), NOTE[(i % #NOTE) + 1], M.SmoothPlastic, m)
		ball((cf * CFrame.new(x, y + 0.9, -0.42)).Position, 0.35, rgb(230, 60, 60), M.SmoothPlastic, m)
	end
	local top = box(cf * CFrame.new(0, 9.7, -0.4), Vector3.new(8, 1.5, 0.3), rgb(90, 60, 40), M.Wood, m)
	sign(top, Enum.NormalId.Front, { { text = "QUESTS", color = rgb(255, 230, 140), h = 0.8, stroke = 4 } }, { PPS = 50 })
	prompt(board, "Quests", "Daily & weekly", "Quests")
	flowers(center + cf.LookVector * 3, 5, 10, m)
end

local function buildDailyGift(info)
	local center = dirAt(info.angle) * info.r
	local gy = groundY(center.X, center.Z)
	local m = Instance.new("Model")
	m.Name = "DailyGift"
	m.Parent = F.Places
	vcyl(center + Vector3.new(0, gy + 0.6, 0), 1.2, 12, MARBLE, M.Marble, m)
	local ringGlow = vcyl(center + Vector3.new(0, gy + 1.3, 0), 0.2, 11, rgb(255, 120, 160), M.Neon, m, { Transparency = 0.3, CanCollide = false })
	emitter(ringGlow, { Color = rgb(255, 200, 220), Size = NumberSequence.new(0.5, 0), Lifetime = NumberRange.new(1.2, 2), Speed = NumberRange.new(2, 4), Rate = 10, EmissionDirection = Enum.NormalId.Right, Spread = Vector2.new(15, 15) })
	local gift = Instance.new("Model")
	gift.Name = "Gift"
	gift.Parent = m
	local pos = center + Vector3.new(0, gy + 5.6, 0)
	local cube = box(CFrame.new(pos), Vector3.new(6.4, 6.4, 6.4), rgb(255, 80, 120), M.SmoothPlastic, gift)
	box(CFrame.new(pos), Vector3.new(6.6, 6.6, 1.4), GOLD, M.Metal, gift)
	box(CFrame.new(pos), Vector3.new(1.4, 6.6, 6.6), GOLD, M.Metal, gift)
	box(CFrame.new(pos + Vector3.new(0, 3.35, 0)), Vector3.new(7, 0.6, 7), rgb(255, 110, 150), M.SmoothPlastic, gift)
	for _, rot in ipairs({ -0.6, 0.6 }) do
		box(CFrame.new(pos + Vector3.new(0, 4.4, 0)) * CFrame.Angles(0, 0, rot), Vector3.new(3.4, 1.8, 1.2), GOLD, M.Metal, gift)
	end
	ball(pos + Vector3.new(0, 4.3, 0), 1.4, GOLD, M.Metal, gift)
	gift.PrimaryPart = cube
	floaty(gift, 0.7, 25, 1.1)
	light(cube, rgb(255, 170, 200), 18, 1.6)
	local to0 = -center.Unit
	local sp = center + to0 * 7 + Vector3.new(0, gy + 1.9, 0)
	local signPart = box(CFrame.lookAt(sp, sp + to0) * CFrame.Angles(math.rad(20), 0, 0), Vector3.new(6, 1.6, 0.4), rgb(255, 120, 160), M.SmoothPlastic, m)
	sign(signPart, Enum.NormalId.Front, { { text = "DAILY GIFT", color = WHITE, h = 0.8, stroke = 3 } }, { PPS = 50 })
	prompt(cube, "Daily Reward", "Come back every day!", "Daily")
end

local function buildMailbox(info)
	local center = dirAt(info.angle) * info.r
	local gy = groundY(center.X, center.Z)
	local cf = CFrame.lookAt(center + Vector3.new(0, gy, 0), Vector3.new(0, gy, 0))
	local S = 1.6 -- большой мультяшный ящик
	local function at(x, y, z) return cf * CFrame.new(x * S, y * S, z * S) end
	local function sz(x, y, z) return Vector3.new(x * S, y * S, z * S) end
	local m = Instance.new("Model")
	m.Name = "CodesMailbox"
	m.Parent = F.Places
	box(cf * CFrame.new(0, 0.3, 0), Vector3.new(4.4 * S, 0.6, 4.4 * S), SLATE, M.Slate, m)
	box(at(0, 2.5, 0), sz(0.8, 5, 0.8), DARKWOOD, M.Wood, m)
	local mbox = box(at(0, 5.6, 0), sz(2.6, 2.4, 4), rgb(70, 130, 255), M.SmoothPlastic, m)
	-- круглая крыша ящика: цилиндр вдоль глубины
	box(at(0, 6.8, 0) * CFrame.Angles(0, math.pi / 2, 0), sz(4, 2.6, 2.6), rgb(70, 130, 255), M.SmoothPlastic, m, { Shape = Enum.PartType.Cylinder })
	-- флажок
	box(at(1.45, 6.4, 0.9), sz(0.2, 2.6, 0.3), IRON, M.Metal, m)
	box(at(1.45, 7.6, 0.4), sz(0.2, 0.9, 1.1), rgb(255, 70, 80), M.SmoothPlastic, m)
	-- письмо торчит из щели
	local letter = box(at(0, 6.2, -2.2) * CFrame.Angles(0.25, 0, 0), sz(1.8, 1.2, 0.1), rgb(255, 250, 235), M.SmoothPlastic, m)
	floaty(letter, 0.25, 0, 2)
	local signPart = box(at(0, 3.3, -0.5), sz(3.4, 1.3, 0.15), rgb(40, 60, 140), M.SmoothPlastic, m)
	sign(signPart, Enum.NormalId.Front, { { text = "CODES", color = rgb(255, 235, 140), h = 0.85, stroke = 3 } }, { PPS = 50 })
	prompt(mbox, "Enter Code", "Free rewards!", "Codes")
	flowers(center + cf.LookVector * 3, 5, 10, m)
end

local function buildClanBanner(info)
	local center = dirAt(info.angle) * info.r
	local gy = groundY(center.X, center.Z)
	local cf = CFrame.lookAt(center + Vector3.new(0, gy, 0), Vector3.new(0, gy, 0))
	local m = Instance.new("Model")
	m.Name = "ClanBanner"
	m.Parent = F.Places
	box(cf * CFrame.new(0, 0.6, 0), Vector3.new(7, 1.2, 4), SLATE, M.Slate, m)
	box(cf * CFrame.new(0, 9, 0.2), Vector3.new(0.7, 17, 0.7), IRON, M.Metal, m)
	box(cf * CFrame.new(0, 16.6, 0.2), Vector3.new(7.6, 0.5, 0.5), GOLD, M.Metal, m)
	for _, sx in ipairs({ -3.8, 3.8 }) do
		ball((cf * CFrame.new(sx, 16.6, 0.2)).Position, 0.9, GOLD, M.Metal, m)
	end
	-- полотнище висит на перекладине перед столбом
	local flag = box(cf * CFrame.new(0, 12.4, -0.35), Vector3.new(6.6, 8, 0.2), rgb(70, 190, 110), M.Fabric, m)
	box(cf * CFrame.new(0, 8.4, -0.35) * CFrame.Angles(0, 0, math.rad(45)), Vector3.new(2.4, 2.4, 0.2), rgb(70, 190, 110), M.Fabric, m)
	box(cf * CFrame.new(0, 16.25, -0.35), Vector3.new(6.8, 0.4, 0.3), GOLD, M.Metal, m)
	sign(flag, Enum.NormalId.Front, { { text = "CLANS", color = WHITE, h = 0.24, stroke = 3 } }, { icon = "shield", iconSize = 0.5, PPS = 40 })
	prompt(flag, "Clans", "Play with friends", "Clans")
	flowers(center + cf.LookVector * 3, 4, 8, m)
end

buildShop(PLACES.Shop)
buildTemple(PLACES.Units)
buildQuestBoard(PLACES.Quests)
buildDailyGift(PLACES.Daily)
buildMailbox(PLACES.Codes)
buildClanBanner(PLACES.Clans)

---------------------------------------------------------------- ПИРС С ЛОДКОЙ (юг) И МЕЛЬНИЦА

local function buildDock()
	local d = dirAt(DOCK_ANGLE)
	local m = Instance.new("Model")
	m.Name = "Dock"
	m.Parent = F.Places
	local deckY = -3.2 -- верх настила: вода на -6, песчаная отмель на -4
	local startR = ISLAND_R + 6
	local endR = ISLAND_R + 38
	local from, to = d * startR, d * endR
	local len = endR - startR
	-- локальная ось -Z смотрит в море; z = -len/2 — дальний край
	local cf = CFrame.lookAt(Vector3.new(0, deckY, 0) + (from + to) / 2, Vector3.new(0, deckY, 0) + to)
	local planks = math.floor(len / 1.6)
	for i = 0, planks - 1 do
		local z = -len / 2 + (i + 0.5) * len / planks
		box(cf * CFrame.new(0, -0.3 + rnd(-0.04, 0.04), z), Vector3.new(7 + rnd(-0.3, 0.3), 0.5, 1.45), WOOD:Lerp(DARKWOOD, rnd(0, 0.5)), M.WoodPlanks, m)
	end
	-- сваи, столбики и перила
	local posts = 7
	for i = 0, posts - 1 do
		local z = -len / 2 + 1 + i * (len - 8) / (posts - 1)
		for _, sx in ipairs({ -3.6, 3.6 }) do
			box(cf * CFrame.new(sx, -4.6, z), Vector3.new(0.9, 9, 0.9), DARKWOOD, M.Wood, m)
			box(cf * CFrame.new(sx, 1.2, z), Vector3.new(0.5, 2.4, 0.5), DARKWOOD, M.Wood, m)
		end
	end
	for _, sx in ipairs({ -3.6, 3.6 }) do
		box(cf * CFrame.new(sx, 2.3, -3.5), Vector3.new(0.35, 0.35, len - 7), WOOD, M.Wood, m)
	end
	-- фонарь на дальнем краю
	lantern((cf * CFrame.new(2.4, 0, -len / 2 + 1.5)).Position, deckY - 0.1)
	-- лодка покачивается у края
	local boat = Instance.new("Model")
	boat.Name = "Boat"
	boat.Parent = m
	local bcf = cf * CFrame.new(-8.5, -3.2, -len / 2 + 9)
	local hull = box(bcf, Vector3.new(4.6, 1.6, 12), rgb(170, 90, 60), M.WoodPlanks, boat)
	box(bcf * CFrame.new(0, 0.9, 0), Vector3.new(4.9, 0.3, 12.3), rgb(240, 240, 240), M.SmoothPlastic, boat)
	box(bcf * CFrame.new(0, 0, -6.4) * CFrame.Angles(0, math.rad(45), 0), Vector3.new(3.25, 1.6, 3.25), rgb(170, 90, 60), M.WoodPlanks, boat)
	box(bcf * CFrame.new(0, 0.6, 1), Vector3.new(4, 0.3, 1.2), WOOD, M.Wood, boat)
	box(bcf * CFrame.new(0, 5.2, -1), Vector3.new(0.45, 9.6, 0.45), DARKWOOD, M.Wood, boat)
	box(bcf * CFrame.new(0, 5.6, 1.4), Vector3.new(0.15, 7.2, 4.4), rgb(255, 250, 240), M.Fabric, boat)
	box(bcf * CFrame.new(0, 10.4, -0.4), Vector3.new(0.1, 1, 1.4), rgb(255, 80, 100), M.Fabric, boat)
	boat.PrimaryPart = hull
	floaty(boat, 0.3, 0, 0.7)
end

local function buildWindmill()
	local center = dirAt(MILL.angle) * MILL.r
	local gy = groundY(center.X, center.Z)
	local base = center + Vector3.new(0, gy, 0)
	local m = Instance.new("Model")
	m.Name = "Windmill"
	m.Parent = F.Places
	local face = CFrame.lookAt(base, Vector3.new(0, gy, 0))
	-- башня сужается кверху
	for i = 0, 5 do
		vcyl(base + Vector3.new(0, 1.5 + i * 3, 0), 3.05, 11 - i * 0.9, i % 2 == 0 and rgb(245, 235, 220) or rgb(235, 222, 205), M.SmoothPlastic, m)
	end
	vcyl(base + Vector3.new(0, 18.4, 0), 0.6, 7.6, DARKWOOD, M.Wood, m)
	-- крыша-конус
	for i = 0, 7 do
		vcyl(base + Vector3.new(0, 19 + i * 0.85, 0), 0.9, 8.4 - i * 1.05, rgb(200, 70, 70), M.SmoothPlastic, m)
	end
	-- дверь и окно
	box(face * CFrame.new(0, 2.6, -5.2), Vector3.new(2.6, 4.4, 0.6), DARKWOOD, M.Wood, m)
	box(face * CFrame.new(0, 10, -4.3), Vector3.new(1.8, 1.8, 0.4), rgb(120, 190, 255), M.Glass, m)
	-- лопасти вращаются (HubClient крутит модель вокруг её оси)
	local hubPos = (face * CFrame.new(0, 16.5, -4.6)).Position
	local blades = Instance.new("Model")
	blades.Name = "Blades"
	blades.Parent = m
	local hubPart = box(CFrame.lookAt(hubPos, hubPos + face.LookVector), Vector3.new(1.6, 1.6, 1.2), DARKWOOD, M.Wood, blades)
	blades.PrimaryPart = hubPart
	for k = 0, 3 do
		local rot = hubPart.CFrame * CFrame.Angles(0, 0, k * math.pi / 2)
		box(rot * CFrame.new(0, 6, -0.2), Vector3.new(0.5, 11, 0.3), DARKWOOD, M.Wood, blades)
		box(rot * CFrame.new(1.3, 6.8, -0.3), Vector3.new(2.4, 8.6, 0.1), rgb(250, 245, 235), M.Fabric, blades)
	end
	animBase(blades)
	blades:SetAttribute("HubRotor", 35) -- градусов в секунду
	flowers(base + face.LookVector * 7, 6, 14, m)
end

buildDock()
buildWindmill()

---------------------------------------------------------------- ПРИРОДА: деревья, кусты, камни, цветы


-- камни — из террейна, гладкие
local function rock(x, z, s)
	local gy = groundY(x, z)
	tFillBall(Vector3.new(x, gy - 0.6 * s, z), 2.6 * s, M.Rock)
	if rng:NextNumber() < 0.6 then
		tFillBall(Vector3.new(x + rnd(-3, 3) * s, gy - 0.8 * s, z + rnd(-3, 3) * s), 1.7 * s, M.Rock)
	end
end

local function scatter(count, rMin, rMax, margin, fn)
	local placed = 0
	for _ = 1, count * 12 do
		if placed >= count then break end
		local a, r = rnd(0, math.pi * 2), rnd(rMin, rMax)
		local x, z = math.cos(a) * r, math.sin(a) * r
		if free(x, z, margin) then
			fn(x, z)
			addZone(x, z, margin * 0.7)
			placed += 1
		end
	end
end

scatter(14, 104, 134, 4, function(x, z) rock(x, z, rnd(0.9, 1.6)) end)
scatter(32, 96, 138, 7, function(x, z)
	local k = rng:NextNumber()
	local s = rnd(0.9, 1.25)
	if k < 0.45 then treeOak(x, z, s) elseif k < 0.75 then treePine(x, z, s) else treeCherry(x, z, s) end
end)
scatter(14, 52, 96, 6, function(x, z)
	if rng:NextNumber() < 0.55 then treeCherry(x, z, rnd(0.75, 0.95)) else treeOak(x, z, rnd(0.7, 0.9)) end
end)
scatter(40, 50, 140, 3, function(x, z) bush(x, z, rnd(0.8, 1.2)) end)
scatter(34, 50, 138, 2, function(x, z) flowers(Vector3.new(x, 0, z), 3.5, 9, F.Nature) end)

---------------------------------------------------------------- НЕБО: летающие острова, водопад, кристаллы, радуга, облака

local function floatingIsland(c, withFall)
	tFillCylinder(CFrame.new(c), 5, 17, M.Grass)
	tFillBall(c - Vector3.new(0, 6, 0), 15, M.Rock)
	tFillBall(c - Vector3.new(0, 14, 0), 10, M.Rock)
	tFillBall(c - Vector3.new(0, 20, 0), 6, M.Rock)
	treeOak(c.X - 3, c.Z - 7, 0.9)
	treeCherry(c.X - 7, c.Z + 5, 0.7)
	if withFall then
		-- ручей по траве и водопад с края
		local top = c.Y + 2.6
		box(CFrame.new(c.X + 10, top, c.Z), Vector3.new(14, 0.3, 3.4), rgb(110, 205, 255), M.Glass, F.Sky, { Transparency = 0.25, CanCollide = false, CastShadow = false })
		local x = c.X + 17.3
		local h = top + 6
		local fall = box(CFrame.new(x, top - h / 2, c.Z), Vector3.new(0.8, h, 3.6), rgb(140, 220, 255), M.Glass, F.Sky, { Transparency = 0.3, CanCollide = false, CastShadow = false })
		emitter(fall, { Color = rgb(230, 250, 255), LightEmission = 0.3, Size = NumberSequence.new(0.6, 1.4), Transparency = NumberSequence.new(0.4, 1), Lifetime = NumberRange.new(0.8, 1.4), Speed = NumberRange.new(4, 8), Rate = 30, Acceleration = Vector3.new(0, -20, 0) })
		local splash = anchor(Vector3.new(x, -5.5, c.Z), Vector3.new(6, 1, 6), F.Effects)
		emitter(splash, { Texture = "rbxasset://textures/particles/smoke_main.dds", Color = rgb(240, 250, 255), LightEmission = 0.2, Size = NumberSequence.new(3, 7), Transparency = NumberSequence.new(0.5, 1), Lifetime = NumberRange.new(1.5, 2.5), Speed = NumberRange.new(2, 5), Rate = 10 })
	end
end

-- большие парящие кристаллы вокруг острова
for i = 1, 8 do
	local a = (i - 0.5) / 8 * math.pi * 2
	local pos = Vector3.new(math.cos(a) * 146, rnd(28, 40), math.sin(a) * 146)
	local c = diamond(pos, rnd(3.5, 5.5), Color3.fromHSV((i / 8 + 0.55) % 1, 0.45, 1), M.Neon, F.Sky, { CanCollide = false, Transparency = 0.1 })
	floaty(c, 2, 25, 0.6)
	if i % 2 == 0 then light(c, c.Color, 30, 1.2) end
end

-- радуга за порталами (лучи Beam: гладкая дуга без стыков)
local RAINBOW = { rgb(255, 80, 90), rgb(255, 160, 60), rgb(255, 230, 80), rgb(90, 220, 110), rgb(80, 170, 255), rgb(170, 110, 255) }
local rainbowCenter = anchor(Vector3.new(0, -6, -300), Vector3.one, F.Sky)
rainbowCenter.Name = "Rainbow"
for i, col in ipairs(RAINBOW) do
	local radius = 190 - (i - 1) * 5.2
	local a0 = Instance.new("Attachment")
	a0.CFrame = CFrame.new(-radius, 0, 0) * CFrame.Angles(0, 0, math.pi / 2) -- ось X смотрит вверх
	a0.Parent = rainbowCenter
	local a1 = Instance.new("Attachment")
	a1.CFrame = CFrame.new(radius, 0, 0) * CFrame.Angles(0, 0, -math.pi / 2) -- ось X смотрит вниз
	a1.Parent = rainbowCenter
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.CurveSize0 = radius * 4 / 3
	beam.CurveSize1 = radius * 4 / 3
	beam.Width0 = 5.6
	beam.Width1 = 5.6
	beam.Segments = 80
	beam.FaceCamera = true
	beam.Color = ColorSequence.new(col)
	beam.Transparency = NumberSequence.new(0.4)
	beam.LightEmission = 0.2
	beam.LightInfluence = 0
	beam.Parent = rainbowCenter
end

-- пушистые облака
for i = 1, 12 do
	local a = (i - 0.5) / 12 * math.pi * 2 + rnd(-0.2, 0.2)
	local r = rnd(170, 330)
	local c = Vector3.new(math.cos(a) * r, rnd(85, 125), math.sin(a) * r)
	local cloud = Instance.new("Model")
	cloud.Name = "Cloud"
	cloud.Parent = F.Sky
	for _ = 1, rng:NextInteger(5, 8) do
		ball(c + Vector3.new(rnd(-16, 16), rnd(-2, 5), rnd(-7, 7)), rnd(12, 22), WHITE, M.SmoothPlastic, cloud, { CanCollide = false, CastShadow = false, CanQuery = false })
	end
	animBase(cloud)
	cloud:SetAttribute("HubDrift", rnd(0.6, 1.4)) -- облака медленно плывут
end

---------------------------------------------------------------- СВЕТЛЯЧКИ И ИСКРЫ

for i = 1, 10 do
	local a = (i - 0.5) / 10 * math.pi * 2
	local r = rnd(60, 130)
	local pos = Vector3.new(math.cos(a) * r, 4, math.sin(a) * r)
	local p = anchor(pos, Vector3.new(34, 6, 34), F.Effects)
	emitter(p, {
		Color = rgb(255, 245, 140), Color2 = rgb(190, 255, 140), Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.2, 0.35), NumberSequenceKeypoint.new(0.8, 0.35), NumberSequenceKeypoint.new(1, 0),
		}),
		Transparency = NumberSequence.new(0, 0.2), Lifetime = NumberRange.new(4, 7), Speed = NumberRange.new(0.3, 1),
		Rate = 3, RotSpeed = NumberRange.new(0, 0),
	})
end
local sparkleAir = anchor(Vector3.new(0, 20, 0), Vector3.new(110, 24, 110), F.Effects)
emitter(sparkleAir, {
	Color = WHITE, Color2 = rgb(180, 220, 255), Size = NumberSequence.new(0.25, 0),
	Lifetime = NumberRange.new(2, 3.5), Speed = NumberRange.new(0.2, 0.6), Rate = 10,
})

---------------------------------------------------------------- СВЕТ И АТМОСФЕРА

local function effect(className)
	local e = Lighting:FindFirstChildOfClass(className)
	if not e then
		e = Instance.new(className)
		e.Parent = Lighting
	end
	return e
end

pcall(function()
	Lighting.ClockTime = 14.8
	Lighting.GeographicLatitude = 35
	Lighting.Brightness = 2.4
	Lighting.Ambient = rgb(80, 70, 100)
	Lighting.OutdoorAmbient = rgb(150, 140, 170)
	Lighting.ColorShift_Top = rgb(255, 238, 215)
	Lighting.EnvironmentDiffuseScale = 0.7
	Lighting.EnvironmentSpecularScale = 0.7
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.35

	local atm = effect("Atmosphere")
	atm.Density = 0.27
	atm.Offset = 0.12
	atm.Color = rgb(205, 215, 255)
	atm.Decay = rgb(255, 196, 225)
	atm.Glare = 0.25
	atm.Haze = 1.1

	local bloom = effect("BloomEffect")
	bloom.Intensity = 0.55
	bloom.Size = 26
	bloom.Threshold = 1.25

	local cc = effect("ColorCorrectionEffect")
	cc.Brightness = 0.02
	cc.Contrast = 0.08
	cc.Saturation = 0.18
	cc.TintColor = rgb(255, 250, 245)

	local rays = effect("SunRaysEffect")
	rays.Intensity = 0.05
	rays.Spread = 0.5

	local dof = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
	if dof then dof.Enabled = false end
end)

---------------------------------------------------------------- МУЗЫКА

if MUSIC_ID ~= "" then
	local music = Instance.new("Sound")
	music.Name = "HubMusic"
	music.SoundId = MUSIC_ID
	music.Looped = true
	music.Volume = MUSIC_VOLUME
	music.Parent = workspace
	music:Play()
end


---------------------------------------------------------------- невидимая стена в море (дальше не уплыть)
do
	local WALL_R, N = 205, 64
	for i = 1, N do
		local a = (i - 0.5) / N * math.pi * 2
		local pos = Vector3.new(math.cos(a) * WALL_R, 20, math.sin(a) * WALL_R)
		part({
			Name = "SeaWall",
			CFrame = CFrame.lookAt(pos, Vector3.new(0, 20, 0)),
			Size = Vector3.new(WALL_R * 2 * math.pi / N + 2, 120, 2),
			Transparency = 1,
			CanCollide = true,
			CastShadow = false,
			CanQuery = false,
		}, F.Effects)
	end
end

---------------------------------------------------------------- готово

-- старые точки появления и плита из шаблона больше не нужны
for _, d in ipairs(workspace:GetChildren()) do
	if d:IsA("SpawnLocation") then
		d.Enabled = false
	elseif d:IsA("BasePart") and d.Name == "Baseplate" and d.Size.X >= 500 then
		d:Destroy()
	end
end

-- поднимаем/опускаем все постройки на реальную высоту травы
if LIFT ~= 0 then
	local up = Vector3.new(0, LIFT, 0)
	hub:PivotTo(hub:GetPivot() + up)
	for _, d in ipairs(hub:GetDescendants()) do
		local b = d:GetAttribute("HubBase")
		if typeof(b) == "CFrame" then d:SetAttribute("HubBase", b + up) end
		local c = d:GetAttribute("OrbitCenter")
		if typeof(c) == "Vector3" then d:SetAttribute("OrbitCenter", c + up) end
	end
end

hub.Parent = workspace
workspace:SetAttribute("HubReady", true)
print("[HubBuilder] хаб построен")
