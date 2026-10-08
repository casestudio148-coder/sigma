-- ServerScriptService.MapService (Script) — ТОЛЬКО В МЕСТЕ С МАТЧЕМ
-- Строит карту матча, выбранную порталом в хабе (8 карт: см. ReplicatedStorage.MapConfig).
--   • отряд из хаба → карта из портала (MemoryStore, запасной путь — данные телепорта)
--   • тест в Studio → MapConfig.StudioMap
--   • обычный / VIP-сервер → случайная карта
-- Ставит точки пути P1, P2, ... Pn (их читают Script, CombatService, PlacementRules),
-- точки появления игроков, свет и эффекты карты. Персонажи появляются, когда карта готова.
-- Старая карта (если осталась в Workspace) не мешает: её точки пути убираются в ServerStorage,
-- точки появления выключаются, а новая карта строится далеко от неё (MapConfig.Origin).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local MemoryStoreService = game:GetService("MemoryStoreService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

-- защита: это место-хаб — тут карта матча не нужна
if game:GetService("ServerScriptService"):FindFirstChild("HubBuilder") or workspace:FindFirstChild("Hub") then
	warn("[MapService] это место-хаб — MapService нужен только в месте с матчем!")
	return
end

local MapConfig = require(ReplicatedStorage:WaitForChild("MapConfig"))

workspace:SetAttribute("MapReady", false)
Players.CharacterAutoLoads = false -- персонажи появятся уже на готовой карте

local M = Enum.Material
local WHITE = Color3.new(1, 1, 1)
local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end

---------------------------------------------------------------- набор инструментов карты

local K = {}
local O = MapConfig.Origin or Vector3.zero
local rng = Random.new(1)
local terrain = workspace.Terrain

function K.reset(seed)
	rng = Random.new(seed)
	O = MapConfig.Origin or Vector3.zero
	K.segs, K.zones, K.rects = {}, {}, {}
	K.nb = {}     -- где нельзя ставить башни (вода, лава, дома, база)
	K.wetPts = {} -- точки рек / прудов
	K.into = nil  -- куда класть детали (модель для анимации)
	K.pathW = 9
	local root = Instance.new("Model")
	root.Name = "BattleMap"
	K.root = root
	K.decor = Instance.new("Folder")
	K.decor.Name = "Decor"
	K.decor.Parent = root
	K.solid = Instance.new("Folder")
	K.solid.Name = "Ground"
	K.solid.Parent = root
end

function K.rnd(a, b) return a + rng:NextNumber() * (b - a) end
function K.int(a, b) return rng:NextInteger(a, b) end
function K.pick(list) return list[rng:NextInteger(1, #list)] end
function K.v(x, y, z) return O + Vector3.new(x, y, z) end
function K.at(x, y, z, yaw)
	local cf = CFrame.new(O + Vector3.new(x, y, z))
	if yaw and yaw ~= 0 then cf = cf * CFrame.Angles(0, yaw, 0) end
	return cf
end

-- деталь. По умолчанию — украшение: сквозь него можно пройти и кликнуть (башни ставятся на землю под ним)
function K.part(props, parent)
	K.made = (K.made or 0) + 1
	if K.made % 600 == 0 then task.wait() end -- даём серверу передохнуть при постройке
	local p = Instance.new(props.ClassName or "Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props.Shape then p.Shape = props.Shape end
	for k, v in pairs(props) do
		if k ~= "ClassName" and k ~= "Shape" and k ~= "Solid" and k ~= "Parent" then p[k] = v end
	end
	if not props.Solid then
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
	end
	if K.naming and not props.Name then p.Name = K.naming end
	p.Parent = parent or props.Parent or K.into or (props.Solid and K.solid or K.decor)
	return p
end

local function merge(props, extra)
	for k, v in pairs(extra or {}) do props[k] = v end
	return props
end

function K.box(cf, size, color, mat, extra)
	return K.part(merge({ CFrame = cf, Size = size, Color = color, Material = mat or M.SmoothPlastic }, extra))
end
function K.ball(pos, d, color, mat, extra)
	return K.part(merge({ Shape = Enum.PartType.Ball, CFrame = CFrame.new(pos), Size = Vector3.one * d, Color = color, Material = mat or M.SmoothPlastic }, extra))
end
-- вертикальный цилиндр: pos — центр
function K.cyl(pos, h, d, color, mat, extra)
	return K.part(merge({
		Shape = Enum.PartType.Cylinder, CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2),
		Size = Vector3.new(h, d, d), Color = color, Material = mat or M.SmoothPlastic,
	}, extra))
end
-- цилиндр вдоль оси X у cf
function K.hcyl(cf, len, d, color, mat, extra)
	return K.part(merge({ Shape = Enum.PartType.Cylinder, CFrame = cf, Size = Vector3.new(len, d, d), Color = color, Material = mat or M.SmoothPlastic }, extra))
end
function K.wedge(cf, size, color, mat, extra)
	return K.part(merge({ ClassName = "WedgePart", CFrame = cf, Size = size, Color = color, Material = mat or M.SmoothPlastic }, extra))
end
-- конус из стопки цилиндров (pos — центр основания)
function K.cone(pos, h, d, color, mat, steps, extra)
	steps = steps or 8
	for i = 0, steps - 1 do
		local k = 1 - i / steps
		K.cyl(pos + Vector3.new(0, h / steps * (i + 0.5), 0), h / steps + 0.02, math.max(d * k, 0.3), color, mat, extra)
	end
end
-- кристалл: куб на вершине
function K.gem(pos, s, color, mat, extra)
	return K.box(CFrame.new(pos) * CFrame.Angles(math.rad(45), 0, math.rad(35.26)), Vector3.one * s, color, mat or M.Neon, extra)
end

function K.light(p, color, range, brightness)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range or 14
	l.Brightness = brightness or 1.5
	l.Shadows = false
	l.Parent = p
	return l
end

function K.emitter(p, cfg)
	local e = Instance.new("ParticleEmitter")
	e.Texture = cfg.Texture or "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(cfg.Color or WHITE, cfg.Color2 or cfg.Color or WHITE)
	e.LightEmission = cfg.LightEmission or 1
	e.LightInfluence = cfg.LightInfluence or 0
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

-- невидимая деталь-держатель
function K.anchor(pos, size)
	return K.box(CFrame.new(pos), size or Vector3.one, WHITE, M.SmoothPlastic, { Transparency = 1, CastShadow = false })
end

local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"
K.SMOKE, K.FIRE = SMOKE, FIRE

-- огонёк (факел, костёр, свеча)
function K.flame(pos, scale, color, color2)
	scale = scale or 1
	local a = K.anchor(pos, Vector3.one * 0.5)
	K.emitter(a, {
		Texture = FIRE, Color = color or rgb(255, 170, 60), Color2 = color2 or rgb(255, 80, 30), LightEmission = 0.9,
		Size = NumberSequence.new(1.2 * scale, 0.2 * scale), Transparency = NumberSequence.new(0.2, 1),
		Lifetime = NumberRange.new(0.4, 0.8), Speed = NumberRange.new(2 * scale, 4 * scale), Spread = Vector2.new(12, 12),
		Rate = 22, EmissionDirection = Enum.NormalId.Top,
	})
	K.light(a, color or rgb(255, 170, 80), 14 * scale, 1.6)
	return a
end

---------------------------------------------------------------- террейн

function K.colors(map)
	for name, color in pairs(map) do
		pcall(function() terrain:SetMaterialColor(M[name], color) end)
	end
end
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
-- поправка по высоте для всех заливок карты (меряется один раз)
local function ts()
	if K.tshift == nil then
		local m, n = measureTerrainShift(terrain)
		K.tshift = math.max(0, m)
		print(string.format("[MapService] проба террейна: %.2f (замеров %d)", m, n))
	end
	return K.tshift
end
function K.tBlock(x, y, z, sx, sy, sz, mat)
	terrain:FillBlock(CFrame.new(O + Vector3.new(x, y - ts(), z)), Vector3.new(sx, sy, sz), mat)
end
function K.tBall(x, y, z, r, mat)
	terrain:FillBall(O + Vector3.new(x, y - ts(), z), r, mat)
end
function K.tCyl(x, y, z, h, r, mat)
	-- тонкие «пятна» Roblox раздувает по высоте (сетка 4 studs) и они вылезают над землёй:
	-- делаем их толстыми вниз, верх остаётся там же
	if h < 4 then
		local top = y + h / 2
		h = 8
		y = top - 4
	end
	terrain:FillCylinder(CFrame.new(O + Vector3.new(x, y - ts(), z)), h, r, mat)
end
-- ровная земля: верх на высоте 0 (до невидимых стен по краю, чтобы нигде не провалиться)
function K.ground(mat, size)
	K.tBlock(0, -8, 0, size or 520, 16, size or 520, mat)
end
function K.water(color, transparency)
	pcall(function()
		terrain.WaterColor = color
		terrain.WaterTransparency = transparency or 0.3
		terrain.WaterReflectance = 0.5
		terrain.WaterWaveSize = 0.1
		terrain.WaterWaveSpeed = 8
	end)
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.FilterDescendantsInstances = { terrain }
-- высота земли (террейн) в точке, в координатах карты
function K.groundY(x, z)
	local r = workspace:Raycast(O + Vector3.new(x, 200, z), Vector3.new(0, -400, 0), rayParams)
	return r and (r.Position.Y - O.Y) or 0
end

---------------------------------------------------------------- дорога мобов и свободные места

local function segDist(x, z, s)
	local abx, abz = s[3] - s[1], s[4] - s[2]
	local len2 = abx * abx + abz * abz
	local t = len2 > 0 and math.clamp(((x - s[1]) * abx + (z - s[2]) * abz) / len2, 0, 1) or 0
	local px, pz = s[1] + abx * t, s[2] + abz * t
	return math.sqrt((x - px) ^ 2 + (z - pz) ^ 2)
end

function K.distToPath(x, z)
	local best = math.huge
	for _, s in ipairs(K.segs) do
		best = math.min(best, segDist(x, z, s))
	end
	return best
end

function K.zone(x, z, r) table.insert(K.zones, { x, z, r }) end
function K.rect(x1, z1, x2, z2) table.insert(K.rects, { math.min(x1, x2), math.min(z1, z2), math.max(x1, x2), math.max(z1, z2) }) end

-- место свободно: не на дороге и не в занятых зонах (margin — запас)
function K.free(x, z, margin)
	margin = margin or 2
	if K.distToPath(x, z) < K.pathW / 2 + margin + 1 then return false end
	for _, c in ipairs(K.zones) do
		if (x - c[1]) ^ 2 + (z - c[2]) ^ 2 < (c[3] + margin) ^ 2 then return false end
	end
	for _, r in ipairs(K.rects) do
		if x > r[1] - margin and x < r[3] + margin and z > r[2] - margin and z < r[4] + margin then return false end
	end
	return true
end

-- раскидать предметы: count штук в прямоугольнике (или кольце), не на дороге
-- nb — радиус, где потом нельзя ставить башни (необязательно)
function K.scatter(count, area, margin, fn, nb)
	local placed = 0
	for _ = 1, count * 15 do
		if placed >= count then break end
		local x, z
		if area.rMin then
			local a, r = K.rnd(0, math.pi * 2), K.rnd(area.rMin, area.rMax)
			x, z = (area.cx or 0) + math.cos(a) * r, (area.cz or 0) + math.sin(a) * r
		else
			x, z = K.rnd(area[1], area[3]), K.rnd(area[2], area[4])
		end
		if K.free(x, z, margin) and (not area.test or area.test(x, z)) then
			fn(x, z)
			K.zone(x, z, margin * 0.7)
			if nb then table.insert(K.nb, { "c", x, z, nb }) end
			placed += 1
		end
	end
	return placed
end

-- дорога: points = { {x, z}, ... }. style: color, mat, discColor, edge(x, z, dir, i) — бордюр
function K.path(points, style)
	local W = style.width or 9
	K.pathW = W
	local y = style.y or 0
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		table.insert(K.segs, { a[1], a[2], b[1], b[2] })
	end
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local pa, pb = K.v(a[1], y - 0.2, a[2]), K.v(b[1], y - 0.2, b[2])
		local len = (pb - pa).Magnitude
		K.box(CFrame.lookAt((pa + pb) / 2, pb), Vector3.new(W, 1, len), style.color, style.mat, { Solid = true, Name = "Road" })
	end
	for i, p in ipairs(points) do
		-- круглый поворот (чуть выше, чтобы не мерцал)
		K.cyl(K.v(p[1], y - 0.17, p[2]), 1, W, style.discColor or style.color, style.mat, { Solid = true, Name = "RoadTurn" })
	end
	-- бордюр по краям, не залезая на соседние участки
	if style.edge then
		for i = 1, #points - 1 do
			local a, b = points[i], points[i + 1]
			local dx, dz = b[1] - a[1], b[2] - a[2]
			local len = math.sqrt(dx * dx + dz * dz)
			local ux, uz = dx / len, dz / len
			local step = style.edgeStep or 3.2
			local n = math.floor(len / step)
			for k = 0, n do
				local t = k * len / math.max(n, 1)
				for _, side in ipairs({ -1, 1 }) do
					local x = a[1] + ux * t - uz * side * (W / 2 + 0.6)
					local z = a[2] + uz * t + ux * side * (W / 2 + 0.6)
					if K.distToPath(x, z) > W / 2 + 0.3 then
						K.naming = "Curb"
						style.edge(x, z, Vector3.new(ux, 0, uz), k)
						K.naming = nil
					end
				end
			end
		end
	end
	-- точки пути для мобов
	for i, p in ipairs(points) do
		local m = Instance.new("Part")
		m.Name = "P" .. i
		m.Size = Vector3.new(2, 1, 2)
		m.Transparency = 1
		m.Anchored = true
		m.CanCollide = false
		m.CanQuery = false
		m.CanTouch = false
		m.CFrame = CFrame.new(K.v(p[1], y + 0.8, p[2]))
		m.Parent = workspace
	end
	local total = 0
	for _, s in ipairs(K.segs) do
		total += math.sqrt((s[3] - s[1]) ^ 2 + (s[4] - s[2]) ^ 2)
	end
	K.pathLength = total
	return total
end

-- направление первого / последнего участка дороги (для ворот и базы)
function K.startDir(points)
	local a, b = points[1], points[2]
	return Vector3.new(b[1] - a[1], 0, b[2] - a[2]).Unit
end
function K.endDir(points)
	local a, b = points[#points - 1], points[#points]
	return Vector3.new(b[1] - a[1], 0, b[2] - a[2]).Unit
end
-- поворот вокруг Y так, чтобы -Z детали смотрел по dir
function K.yawOf(dir)
	return math.atan2(-dir.X, -dir.Z)
end

-- мост вдоль участка дороги a→b, от доли t0 до t1: настил, перила, столбики
function K.bridge(a, b, t0, t1, plankColor, railColor, opts)
	opts = opts or {}
	local W = K.pathW
	local dx, dz = b[1] - a[1], b[2] - a[2]
	local len = math.sqrt(dx * dx + dz * dz)
	local ux, uz = dx / len, dz / len
	local p0 = Vector3.new(a[1] + dx * t0, 0, a[2] + dz * t0)
	local p1 = Vector3.new(a[1] + dx * t1, 0, a[2] + dz * t1)
	local span = (p1 - p0).Magnitude
	local n = math.max(2, math.floor(span / 1.6))
	local dir = Vector3.new(ux, 0, uz)
	for i = 0, n - 1 do
		local c = p0 + dir * ((i + 0.5) * span / n)
		K.box(CFrame.lookAt(K.v(c.X, 0.34, c.Z), K.v(c.X, 0.34, c.Z) + dir), Vector3.new(W + 1, 0.12, span / n - 0.12),
			(plankColor):Lerp(rgb(60, 40, 25), (i % 3) * 0.08), opts.mat or M.WoodPlanks, { CastShadow = false, Name = "Plank" })
	end
	local right = Vector3.new(-uz, 0, ux)
	for _, side in ipairs({ -1, 1 }) do
		local off = right * side * (W / 2 + 0.6)
		local mid = (p0 + p1) / 2 + off
		K.box(CFrame.lookAt(K.v(mid.X, 2.3, mid.Z), K.v(mid.X, 2.3, mid.Z) + dir), Vector3.new(0.4, 0.4, span + 1), railColor, opts.railMat or M.Wood)
		local posts = math.max(2, math.floor(span / 4) + 1)
		for k = 0, posts - 1 do
			local q = p0 + dir * (k * span / (posts - 1)) + off
			K.box(CFrame.new(K.v(q.X, 1, q.Z)), Vector3.new(0.6, 2.8, 0.6), railColor, opts.railMat or M.Wood)
		end
	end
end

---------------------------------------------------------------- общие украшения

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

	return T
end

K.trees = makeTrees({
	rnd = K.rnd,
	groundY = function(x, z) return K.groundY(x, z) end,
	make = function(cls, cf, size, color, mat, shape)
		local props = { ClassName = cls, CFrame = cf + O, Size = size, Color = color, Material = mat or M.SmoothPlastic, CastShadow = size.Magnitude > 3 }
		if shape then props.Shape = shape end
		return K.part(props)
	end,
})
function K.oak(x, z, s, leaves, trunk) K.trees.oak(x, z, s, leaves, trunk) end
function K.pine(x, z, s, green, snow) K.trees.pine(x, z, s, green, snow) end
function K.palm(x, z, s) K.trees.palm(x, z, s) end

function K.deadTree(x, z, s, color)
	local gy = K.groundY(x, z)
	color = color or rgb(70, 55, 50)
	local h = K.rnd(8, 12) * s
	K.cyl(K.v(x, gy + h / 2, z), h, 1.4 * s, color, M.Wood)
	for _ = 1, 4 do
		local a = K.rnd(0, math.pi * 2)
		local y = gy + K.rnd(h * 0.45, h * 0.9)
		local len = K.rnd(3, 5) * s
		local cf = CFrame.new(K.v(x, y, z)) * CFrame.Angles(0, a, 0) * CFrame.Angles(math.rad(K.rnd(30, 55)), 0, 0) * CFrame.new(0, len / 2, 0)
		K.box(cf, Vector3.new(0.5 * s, len, 0.5 * s), color, M.Wood)
		local tip = cf * CFrame.new(0, len / 2, 0)
		K.box(tip * CFrame.Angles(math.rad(K.rnd(-40, 40)), 0, math.rad(K.rnd(-40, 40))) * CFrame.new(0, len * 0.3, 0), Vector3.new(0.35 * s, len * 0.6, 0.35 * s), color, M.Wood)
	end
end

function K.bush(x, z, s, colors)
	K.trees.bush(x, z, s, colors)
end

function K.flowers(x, z, r, n, colors)
	for _ = 1, n do
		local a, d = K.rnd(0, math.pi * 2), K.rnd(0, r)
		local px, pz = x + math.cos(a) * d, z + math.sin(a) * d
		if K.distToPath(px, pz) > K.pathW / 2 + 0.5 then
			K.ball(K.v(px, K.groundY(px, pz) + 0.3, pz), K.rnd(0.6, 0.9), K.pick(colors), M.SmoothPlastic, { CastShadow = false })
		end
	end
end

-- камень из террейна (гладкий)
function K.boulder(x, z, s, mat)
	local gy = K.groundY(x, z)
	K.tBall(x, gy - 0.8 * s, z, 2.6 * s, mat or M.Rock)
	if rng:NextNumber() < 0.6 then
		K.tBall(x + K.rnd(-3, 3) * s, gy - 1 * s, z + K.rnd(-3, 3) * s, 1.8 * s, mat or M.Rock)
	end
end

-- камень из деталей (для мультяшных карт)
function K.rock(x, z, s, color, mat)
	local gy = K.groundY(x, z)
	for i = 1, K.int(1, 3) do
		local size = Vector3.new(K.rnd(2.5, 4.5), K.rnd(1.5, 3), K.rnd(2.5, 4)) * s * (i == 1 and 1 or 0.6)
		K.box(K.at(x + K.rnd(-1.5, 1.5) * s * (i - 1), gy + size.Y * 0.3 - O.Y + O.Y, z + K.rnd(-1.5, 1.5) * s * (i - 1)) * CFrame.Angles(K.rnd(-0.3, 0.3), K.rnd(0, 6.28), K.rnd(-0.3, 0.3)),
			size, color:Lerp(rgb(0, 0, 0), K.rnd(0, 0.15)), mat or M.Slate)
	end
end

-- фонарь на столбе
function K.lamp(x, z, color, post)
	local gy = K.groundY(x, z)
	post = post or rgb(50, 45, 55)
	K.box(K.at(x, gy + 0.4, z), Vector3.new(1.3, 0.8, 1.3), post, M.Metal)
	K.box(K.at(x, gy + 3.8, z), Vector3.new(0.45, 7, 0.45), post, M.Metal)
	K.box(K.at(x, gy + 7.4, z), Vector3.new(1.6, 0.3, 1.6), post, M.Metal)
	K.box(K.at(x, gy + 8.3, z), Vector3.new(1.3, 1.6, 1.3), color:Lerp(WHITE, 0.4), M.Glass, { Transparency = 0.35, CastShadow = false })
	local f = K.box(K.at(x, gy + 8.3, z), Vector3.new(0.6, 0.9, 0.6), color, M.Neon, { CastShadow = false })
	K.box(K.at(x, gy + 9.3, z), Vector3.new(1.8, 0.4, 1.8), post, M.Metal)
	K.light(f, color, 18, 1.6)
end

-- забор вдоль ломаной
function K.fence(points, postColor, railColor, opts)
	opts = opts or {}
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local pa, pb = Vector3.new(a[1], 0, a[2]), Vector3.new(b[1], 0, b[2])
		local len = (pb - pa).Magnitude
		local n = math.max(1, math.floor(len / (opts.step or 4)))
		for k = 0, n do
			local p = pa:Lerp(pb, k / n)
			local gy = K.groundY(p.X, p.Z)
			K.box(K.at(p.X, gy + (opts.h or 3) / 2, p.Z), Vector3.new(0.6, opts.h or 3, 0.6), postColor, opts.mat or M.Wood)
			if opts.spikes then
				K.box(K.at(p.X, gy + (opts.h or 3) + 0.3, p.Z) * CFrame.Angles(0, 0, math.rad(45)), Vector3.new(0.5, 0.5, 0.3), postColor, opts.mat or M.Metal)
			end
		end
		local mid = (pa + pb) / 2
		local gy = K.groundY(mid.X, mid.Z)
		for _, h in ipairs(opts.rails or { 0.9, 2.1 }) do
			K.box(CFrame.lookAt(K.v(mid.X, gy + h, mid.Z), K.v(pb.X, gy + h, pb.Z)), Vector3.new(0.3, 0.3, len), railColor, opts.mat or M.Wood)
		end
	end
end

function K.crystals(x, z, s, color, mat)
	local gy = K.groundY(x, z)
	for i = 1, K.int(3, 5) do
		local h = K.rnd(3, 7) * s * (i == 1 and 1.3 or 1)
		local cf = K.at(x + K.rnd(-1.5, 1.5) * s, gy + h * 0.35, z + K.rnd(-1.5, 1.5) * s)
			* CFrame.Angles(K.rnd(-0.45, 0.45), K.rnd(0, 6.28), K.rnd(-0.45, 0.45))
		K.box(cf, Vector3.new(1.2 * s, h, 1.2 * s), color, mat or M.Neon, { Transparency = (mat == M.Glass) and 0.2 or 0 })
	end
end

function K.flag(pos, color, h)
	h = h or 8
	K.box(CFrame.new(pos + Vector3.new(0, h / 2, 0)), Vector3.new(0.35, h, 0.35), rgb(70, 60, 60), M.Metal)
	K.box(CFrame.new(pos + Vector3.new(1.6, h - 1.1, 0)), Vector3.new(3, 2, 0.12), color, M.Fabric)
end

function K.torch(x, z, h)
	local gy = K.groundY(x, z)
	h = h or 4
	K.box(K.at(x, gy + h / 2, z), Vector3.new(0.5, h, 0.5), rgb(90, 60, 40), M.Wood)
	K.box(K.at(x, gy + h + 0.2, z), Vector3.new(0.9, 0.5, 0.9), rgb(60, 55, 60), M.Metal)
	K.flame(K.v(x, gy + h + 0.8, z), 0.8)
end

-- точки появления игроков (4 штуки)
function K.spawns(x, z, yaw)
	for i = 1, 4 do
		local dx = ((i - 1) % 2 - 0.5) * 6
		local dz = (math.floor((i - 1) / 2) - 0.5) * 6
		local sp = Instance.new("SpawnLocation")
		sp.Name = "MapSpawn" .. i
		sp.Anchored = true
		sp.Size = Vector3.new(5, 0.4, 5)
		sp.Transparency = 1
		sp.CanCollide = false
		sp.CanQuery = false
		sp.CanTouch = false
		sp.Neutral = true
		sp.Duration = 0
		sp.CFrame = K.at(x + dx, 0.5, z + dz, yaw)
		local d = sp:FindFirstChildOfClass("Decal")
		if d then d:Destroy() end
		sp.Parent = K.root
	end
	K.zone(x, z, 9)
end

-- падающие / летающие частицы над всей картой
function K.ambient(cfg)
	local a = K.anchor(K.v(0, cfg.y or 25, 0), Vector3.new(cfg.size or 230, cfg.h or 2, cfg.size or 230))
	K.emitter(a, cfg)
	return a
end

-- свет и небо карты
local function effect(className)
	local e = Lighting:FindFirstChildOfClass(className)
	if not e then
		e = Instance.new(className)
		e.Parent = Lighting
	end
	return e
end
function K.lighting(o)
	pcall(function()
		Lighting.ClockTime = o.clock or 14
		Lighting.GeographicLatitude = o.latitude or 35
		Lighting.Brightness = o.brightness or 2.4
		Lighting.Ambient = o.ambient or rgb(80, 75, 95)
		Lighting.OutdoorAmbient = o.outdoor or rgb(140, 135, 155)
		Lighting.ColorShift_Top = o.shift or rgb(255, 240, 220)
		Lighting.ColorShift_Bottom = rgb(0, 0, 0)
		Lighting.EnvironmentDiffuseScale = 0.6
		Lighting.EnvironmentSpecularScale = 0.6
		Lighting.GlobalShadows = true
		Lighting.ShadowSoftness = 0.3
		Lighting.FogEnd = 100000
		Lighting.ExposureCompensation = o.exposure or 0
		local atm = effect("Atmosphere")
		atm.Density = o.density or 0.3
		atm.Offset = o.offset or 0.1
		atm.Color = o.atmColor or rgb(200, 210, 240)
		atm.Decay = o.decay or rgb(230, 200, 220)
		atm.Glare = o.glare or 0.2
		atm.Haze = o.haze or 1
		local bloom = effect("BloomEffect")
		bloom.Enabled = true
		bloom.Intensity = o.bloom or 0.5
		bloom.Size = 24
		bloom.Threshold = o.bloomThreshold or 1.3
		local cc = effect("ColorCorrectionEffect")
		cc.Enabled = true
		cc.Brightness = o.ccBrightness or 0.02
		cc.Contrast = o.contrast or 0.08
		cc.Saturation = o.saturation or 0.15
		cc.TintColor = o.tint or rgb(255, 252, 248)
		local rays = effect("SunRaysEffect")
		rays.Intensity = o.sunrays or 0.05
		rays.Spread = 0.5
		local dof = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
		if dof then dof.Enabled = false end
		local sky = Lighting:FindFirstChildOfClass("Sky")
		if not sky then
			sky = Instance.new("Sky")
			sky.Parent = Lighting
		end
		sky.StarCount = o.stars or 3000
		sky.CelestialBodiesShown = o.celestial ~= false
		-- облака
		local clouds = terrain:FindFirstChildOfClass("Clouds")
		if o.clouds then
			if not clouds then
				clouds = Instance.new("Clouds")
				clouds.Parent = terrain
			end
			clouds.Enabled = true
			clouds.Cover = o.clouds
			clouds.Density = o.cloudDensity or 0.6
			clouds.Color = o.cloudColor or WHITE
		elseif clouds then
			clouds.Enabled = false
		end
	end)
end

-- стандартный замок (база игроков): x, z — центр, yaw — куда смотрят ворота
-- c: wall, trim, roof, flag, mat, roofMat, glow
function K.castle(x, z, yaw, c)
	local base = K.at(x, 0, z, yaw)
	local function at(lx, ly, lz) return base * CFrame.new(lx, ly, lz) end
	local wall, trim, roof = c.wall, c.trim, c.roof
	local mat = c.mat or M.Brick
	-- стены (ворота спереди, по -Z)
	for _, w in ipairs({
		{ -9.5, 0, 0.4, 1, 17 }, { 9.5, 0, 0.4, 1, 17 },
		{ 0, 8.5, 1, 0, 19 },
		{ -6.5, -8.5, 1, 0, 6 }, { 6.5, -8.5, 1, 0, 6 },
		}) do
		local len = w[5]
		local size = w[3] == 1 and Vector3.new(len, 9, 2) or Vector3.new(2, 9, len)
		K.box(at(w[1], 4.5, w[2]), size, wall, mat)
		-- зубцы
		local n = math.floor(len / 2.4)
		for k = 0, n - 1 do
			local off = -len / 2 + (k + 0.5) * len / n
			local p = w[3] == 1 and at(w[1] + off, 9.6, w[2]) or at(w[1], 9.6, w[2] + off)
			if k % 2 == 0 then K.box(p, Vector3.new(1.4, 1.2, 1.4) + (w[3] == 1 and Vector3.new(0, 0, 0.6) or Vector3.new(0.6, 0, 0)), wall, mat) end
		end
	end
	-- арка ворот
	K.box(at(0, 10, -8.5), Vector3.new(7, 2.2, 2.4), trim, c.trimMat or M.Metal)
	-- угловые башни
	for _, p in ipairs({ { -9.5, -8.5 }, { 9.5, -8.5 }, { -9.5, 8.5 }, { 9.5, 8.5 } }) do
		local pos = at(p[1], 0, p[2]).Position
		K.cyl(pos + Vector3.new(0, 6.5, 0), 13, 5.4, wall, mat)
		K.cyl(pos + Vector3.new(0, 13.3, 0), 0.6, 6.2, trim, c.trimMat or M.Metal)
		K.cone(pos + Vector3.new(0, 13.6, 0), 6, 6.4, roof, c.roofMat or M.SmoothPlastic, 7)
		K.flag(pos + Vector3.new(0, 19.4, 0), c.flag, 4)
	end
	-- главная башня (донжон)
	local keep = at(0, 0, 3).Position
	K.box(CFrame.new(keep + Vector3.new(0, 8, 0)) * base.Rotation, Vector3.new(9, 16, 8), wall, mat)
	K.box(CFrame.new(keep + Vector3.new(0, 16.4, 0)) * base.Rotation, Vector3.new(9.8, 0.8, 8.8), trim, c.trimMat or M.Metal)
	K.cone(keep + Vector3.new(0, 16.8, 0), 9, 9.5, roof, c.roofMat or M.SmoothPlastic, 9)
	K.flag(keep + Vector3.new(0, 25.6, 0), c.flag, 5)
	-- окна светятся
	for _, sx in ipairs({ -2.2, 2.2 }) do
		local w = K.box(CFrame.new(keep + Vector3.new(0, 11, 0)) * base.Rotation * CFrame.new(sx, 0, -4.05), Vector3.new(1.4, 2.4, 0.2), c.glow or rgb(255, 210, 120), M.Neon)
		w.CastShadow = false
	end
	K.zone(x, z, 16)
	K.block(x, z, 13)
	return base
end


---------------------------------------------------------------- запретные зоны, край карты, реки, домики

-- сюда нельзя ставить башни (и не ставим украшения)
function K.block(x, z, r)
	K.zone(x, z, r)
	table.insert(K.nb, { "c", x, z, r })
end
function K.blockRect(x1, z1, x2, z2)
	K.rect(x1, z1, x2, z2)
	table.insert(K.nb, { "r", math.min(x1, x2), math.min(z1, z2), math.max(x1, x2), math.max(z1, z2) })
end

-- точки по краю квадратной карты (для гор / скал по краю)
function K.ring(inner, step, fn)
	for side = 1, 4 do
		for s = -210, 210, step do
			local along = s + K.rnd(-step * 0.3, step * 0.3)
			local out = inner + K.rnd(0, 22)
			if side == 1 then fn(along, out)
			elseif side == 2 then fn(along, -out)
			elseif side == 3 then fn(out, along)
			else fn(-out, along) end
		end
	end
end

-- невидимые стены по краю, чтобы не упасть с карты
function K.walls(half)
	half = half or 250
	local h = 120
	for _, w in ipairs({ { 0, half, 2 * half + 6, 2 }, { 0, -half, 2 * half + 6, 2 }, { half, 0, 2, 2 * half + 6 }, { -half, 0, 2, 2 * half + 6 } }) do
		K.part({ Name = "Edge", CFrame = K.at(w[1], h / 2 - 20, w[2]), Size = Vector3.new(w[3], h, w[4]), Transparency = 1, Solid = true, CastShadow = false })
	end
end

-- точки русла: от a до b с шагом step, x = f(z) (вдоль Z) или z = f(x) (вдоль X)
function K.curve(a, b, step, fn, alongX)
	local pts = {}
	for t = a, b, step do
		local c = fn(t)
		table.insert(pts, alongX and { t, c } or { c, t })
	end
	return pts
end

-- река / пруд: вырезает русло вдоль точек и заливает
-- o: r (полуширина), depth, bed (дно), bank (берег), water = false (без воды), level (верх воды)
function K.river(pts, o)
	local r, depth = o.r or 6, o.depth or 5
	if o.bank then
		for _, p in ipairs(pts) do
			K.tCyl(p[1], -1.5, p[2], 3, r + 3, o.bank)
		end
	end
	for _, p in ipairs(pts) do
		K.tCyl(p[1], (14 - depth) / 2, p[2], 14 + depth, r, M.Air)
	end
	for i, p in ipairs(pts) do
		K.tCyl(p[1], -depth - 1, p[2], 2.5, r, o.bed or M.Mud)
		if o.water ~= false then
			local top = o.level or -1
			K.tCyl(p[1], (top - 4) / 2, p[2], top + 4, r - 0.5, M.Water)
		end
		table.insert(K.wetPts, { p[1], p[2], r })
		K.zone(p[1], p[2], r + 1)
		if i % 2 == 1 or i == #pts then
			table.insert(K.nb, { "c", p[1], p[2], r + 1 })
		end
	end
end

-- точка в воде / лаве?
function K.wet(x, z, extra)
	extra = extra or 1
	for _, p in ipairs(K.wetPts) do
		if (x - p[1]) ^ 2 + (z - p[2]) ^ 2 < (p[3] + extra) ^ 2 then return true end
	end
	return false
end

-- точка дороги на участке i при доле t
function K.along(points, i, t)
	local a, b = points[i], points[i + 1]
	return a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t
end
-- доля участка i, где он ближе всего к x (или z)
function K.tAt(points, i, value, byZ)
	local a, b = points[i], points[i + 1]
	if byZ then return (value - a[2]) / (b[2] - a[2]) end
	return (value - a[1]) / (b[1] - a[1])
end

-- модель-группа (для анимации на клиенте). attrs: Rotor, Float, Spin, Speed, Phase
function K.group(name, attrs, parent)
	local m = Instance.new("Model")
	m.Name = name
	for k, v in pairs(attrs or {}) do m:SetAttribute(k, v) end
	pcall(function() m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic end)
	m.Parent = parent or K.into or K.decor
	return m
end
function K.inside(model, fn)
	local prev = K.into
	K.into = model
	fn()
	K.into = prev
end
-- зафиксировать «покой» модели для анимации (после того как она собрана)
function K.rest(model, pivotCF)
	if not pivotCF then
		pivotCF = CFrame.new((model:GetBoundingBox()).Position)
	end
	model.WorldPivot = pivotCF
	model:SetAttribute("Base", pivotCF)
end

-- домик: x, z — центр, yaw — куда смотрит дверь. c: wall, roof, trim, door, w, d, h
function K.house(x, z, yaw, c)
	local W, D, H = c.w or 12, c.d or 10, c.h or 8
	local gy = K.groundY(x, z)
	local base = K.at(x, gy, z, yaw)
	local function at(lx, ly, lz) return base * CFrame.new(lx, ly, lz) end
	K.box(at(0, 0.4, 0), Vector3.new(W + 1, 0.8, D + 1), c.found or rgb(130, 125, 120), M.Cobblestone)
	K.box(at(0, H / 2 + 0.8, 0), Vector3.new(W, H, D), c.wall, c.wallMat or M.Plaster)
	-- крыша двускатная (конёк вдоль X)
	local rh = c.rh or D * 0.55
	K.wedge(at(0, H + 0.8 + rh / 2, -D / 4 - 0.3), Vector3.new(W + 1.6, rh, D / 2 + 0.8), c.roof, c.roofMat or M.ClayRoofTiles)
	K.wedge(at(0, H + 0.8 + rh / 2, D / 4 + 0.3) * CFrame.Angles(0, math.pi, 0), Vector3.new(W + 1.6, rh, D / 2 + 0.8), c.roof, c.roofMat or M.ClayRoofTiles)
	-- уголки и балки
	local trim = c.trim or rgb(110, 75, 45)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			K.box(at(sx * (W / 2 - 0.2), H / 2 + 0.8, sz * (D / 2 - 0.2)), Vector3.new(0.7, H, 0.7), trim, M.Wood)
		end
	end
	K.box(at(0, H + 0.6, -D / 2), Vector3.new(W, 0.6, 0.6), trim, M.Wood)
	K.box(at(0, H + 0.6, D / 2), Vector3.new(W, 0.6, 0.6), trim, M.Wood)
	-- дверь и окна (спереди, -Z)
	K.box(at(0, 3, -D / 2 - 0.1), Vector3.new(2.6, 4.4, 0.3), c.door or rgb(120, 70, 40), M.Wood)
	K.box(at(0, 5.4, -D / 2 - 0.15), Vector3.new(3.2, 0.4, 0.4), trim, M.Wood)
	for _, sx in ipairs({ -1, 1 }) do
		local w = K.box(at(sx * W * 0.3, H * 0.55 + 0.8, -D / 2 - 0.1), Vector3.new(2, 2, 0.25), c.glass or rgb(255, 225, 150), c.glassMat or M.Glass)
		w.CastShadow = false
		K.box(at(sx * W * 0.3, H * 0.55 + 0.8, -D / 2 - 0.2), Vector3.new(2.4, 0.3, 0.3), trim, M.Wood)
		K.box(at(sx * W * 0.3, H * 0.55 + 0.8 - 1.2, -D / 2 - 0.3), Vector3.new(2.6, 0.4, 0.6), c.box or rgb(120, 80, 50), M.Wood)
	end
	-- труба
	if c.chimney ~= false then
		K.box(at(W * 0.28, H + rh * 0.9, D * 0.18), Vector3.new(1.6, rh + 1, 1.6), rgb(150, 110, 95), M.Brick)
	end
	K.block(x, z, math.max(W, D) * 0.62)
	return base
end

function K.barrel(x, z, s, color)
	local gy = K.groundY(x, z)
	s = s or 1
	K.cyl(K.v(x, gy + 1.5 * s, z), 3 * s, 2.2 * s, color or rgb(140, 95, 55), M.Wood)
	for _, h in ipairs({ 0.5, 2.5 }) do
		K.cyl(K.v(x, gy + h * s, z), 0.3 * s, 2.35 * s, rgb(70, 70, 75), M.Metal)
	end
end

function K.crate(x, z, s, yaw, color)
	local gy = K.groundY(x, z)
	s = s or 1
	local cf = K.at(x, gy + 1.25 * s, z, yaw or K.rnd(0, 1.5))
	K.box(cf, Vector3.one * 2.5 * s, color or rgb(170, 125, 75), M.WoodPlanks)
	K.box(cf, Vector3.new(2.6, 0.4, 2.6) * s, rgb(110, 80, 50), M.Wood)
	K.box(cf, Vector3.new(0.4, 2.6, 2.6) * s, rgb(110, 80, 50), M.Wood)
end

-- светящийся огонёк над землёй, который парит (клиент анимирует Float)
function K.wisp(pos, color, size)
	local g = K.group("Wisp", { Float = 1.2, Speed = K.rnd(0.6, 1.2), Phase = K.rnd(0, 6.28) })
	K.inside(g, function()
		local b = K.ball(pos, size or 1.2, color, M.Neon, { CastShadow = false })
		K.light(b, color, 12, 1.2)
	end)
	K.rest(g)
	return g
end


-- бордюр из камешков вдоль дороги (над водой не ставится)
function K.stoneEdge(colors, mat, size)
	return function(x, z, dir, k)
		if K.wet(x, z, 1.5) then return end
		local s = (size or 1) * K.rnd(0.85, 1.15)
		K.box(K.at(x, 0.2, z, K.rnd(0, 3.14)), Vector3.new(1.5 * s, 0.75 * s, 1.2 * s), colors[(k % #colors) + 1], mat or M.Slate, { CastShadow = false })
	end
end

-- для каждого поворота дороги: точка снаружи угла (для фонарей / факелов)
function K.corners(points, dist, fn)
	for i = 2, #points - 1 do
		local a, b, c = points[i - 1], points[i], points[i + 1]
		local d1 = Vector3.new(b[1] - a[1], 0, b[2] - a[2]).Unit
		local d2 = Vector3.new(c[1] - b[1], 0, c[2] - b[2]).Unit
		local out = d1 - d2
		if out.Magnitude > 0.1 then
			out = out.Unit
			local x, z = b[1] + out.X * dist, b[2] + out.Z * dist
			if not K.wet(x, z, 1) then fn(x, z, i) end
		end
	end
end

-- мост на участке i дороги вокруг точки (x, z), half — половина длины
function K.bridgeAt(points, i, x, z, half, plank, rail, opts)
	local a, b = points[i], points[i + 1]
	local dx, dz = b[1] - a[1], b[2] - a[2]
	local len2 = dx * dx + dz * dz
	local t = ((x - a[1]) * dx + (z - a[2]) * dz) / len2
	local dt = half / math.sqrt(len2)
	K.bridge(a, b, math.max(0, t - dt), math.min(1, t + dt), plank, rail, opts)
end

-- направление «смотреть на точку» (для дверей, точек появления)
function K.face(x, z, tx, tz)
	return K.yawOf(Vector3.new(tx - x, 0, tz - z).Unit)
end

---------------------------------------------------------------- карты

local MAPS = {}

---------------------------------------------------------------- 1. SUNNY VALLEY — холмы, река, мельница, замок

MAPS.Valley = function()
	K.reset(1101)
	K.colors({
		Grass = rgb(106, 182, 66), LeafyGrass = rgb(86, 160, 56), Ground = rgb(134, 106, 74), Rock = rgb(136, 132, 126),
		Mud = rgb(104, 84, 62), Sand = rgb(226, 208, 154), Slate = rgb(112, 112, 118), Limestone = rgb(206, 200, 184),
	})
	K.water(rgb(62, 164, 205), 0.35)
	K.ground(M.Grass)

	-- холмы и горы по краю
	K.ring(170, 24, function(x, z)
		K.tBall(x, K.rnd(-12, -5), z, K.rnd(22, 32), K.rnd(0, 1) < 0.5 and M.Grass or M.LeafyGrass)
	end)
	K.ring(212, 34, function(x, z)
		local r = K.rnd(42, 60)
		local y = K.rnd(-24, -14)
		K.tBall(x, y, z, r, M.Rock)
		K.tBall(x, y + r * 0.16, z, r * 0.88, M.LeafyGrass)
	end)

	-- водопад на севере, река через всю долину
	local function riverX(z) return -6 + 7 * math.sin(z / 28) end
	local fx = math.floor(riverX(148) / 4 + 0.5) * 4
	K.tBlock(fx, 10, 172, 48, 36, 32, M.Rock) -- скала: x ±24, y -8..28, z 156..188
	K.tBall(fx - 14, 26, 170, 12, M.LeafyGrass)
	K.tBall(fx + 12, 27, 172, 13, M.Grass)
	K.tBall(fx, 30, 178, 12, M.Grass)
	K.river(K.curve(-190, 146, 4, riverX), { r = 6, depth = 5, bed = M.Mud, bank = M.Sand })
	K.river({ { fx, 149 } }, { r = 10, depth = 6, bed = M.Sand, bank = M.Sand })
	-- падающая вода, пена
	K.box(K.at(fx, 13, 155.4), Vector3.new(10, 28, 0.6), rgb(150, 212, 245), M.Glass, { Transparency = 0.25, CastShadow = false })
	for i = -2, 2 do
		K.box(K.at(fx + i * 1.9, 13, 155), Vector3.new(0.5, 28, 0.2), rgb(235, 248, 255), M.SmoothPlastic, { Transparency = 0.45, CastShadow = false })
	end
	K.emitter(K.anchor(K.v(fx, -0.5, 152), Vector3.new(10, 1, 3)), {
		Texture = K.SMOKE, Color = rgb(240, 250, 255), LightEmission = 0.2, LightInfluence = 1,
		Size = NumberSequence.new(3, 7), Transparency = NumberSequence.new(0.35, 1), Lifetime = NumberRange.new(1.2, 2.2),
		Speed = NumberRange.new(2, 4), Spread = Vector2.new(40, 40), Rate = 22, EmissionDirection = Enum.NormalId.Top,
	})

	-- дорога
	local P = { { -92, -48 }, { -38, -48 }, { -38, 22 }, { 22, 22 }, { 22, -28 }, { 68, -28 }, { 68, 52 } }
	K.path(P, {
		color = rgb(198, 162, 112), mat = M.Ground, discColor = rgb(192, 156, 106),
		edge = K.stoneEdge({ rgb(152, 148, 142), rgb(128, 124, 120), rgb(172, 168, 160) }),
	})
	K.bridgeAt(P, 3, riverX(22), 22, 9, rgb(176, 124, 78), rgb(122, 82, 50))

	-- ворота: шахта в скале
	K.tBlock(-112, 6, -48, 24, 28, 44, M.Rock) -- x -124..-100
	K.tBall(-112, 18, -48, 15, M.Rock)
	K.tBall(-110, 10, -68, 12, M.Rock)
	K.tBall(-110, 10, -28, 12, M.Rock)
	K.tBall(-118, 26, -46, 12, M.Grass)
	K.tBall(-122, 20, -64, 10, M.LeafyGrass)
	K.tBlock(-106, 4.5, -48, 12, 9, 8, M.Air) -- тоннель
	local wood, woodD = rgb(124, 86, 52), rgb(98, 68, 42)
	for _, sz in ipairs({ -1, 1 }) do
		K.box(K.at(-100.6, 4.6, -48 + sz * 4.7), Vector3.new(1.5, 9.2, 1.5), wood, M.Wood)
		local lamp = K.box(K.at(-99.4, 7.2, -48 + sz * 4.7), Vector3.new(0.8, 1.1, 0.8), rgb(255, 205, 120), M.Neon, { CastShadow = false })
		K.light(lamp, rgb(255, 190, 110), 16, 1.5)
		K.box(K.at(-99.4, 7.95, -48 + sz * 4.7), Vector3.new(1.1, 0.3, 1.1), rgb(50, 45, 45), M.Metal)
	end
	K.box(K.at(-100.6, 9.7, -48), Vector3.new(1.7, 1.5, 11.8), woodD, M.Wood)
	K.box(K.at(-111.6, 4.5, -48), Vector3.new(1, 9, 8), rgb(12, 10, 10), M.SmoothPlastic)
	for _, sz in ipairs({ -1.6, 1.6 }) do
		K.box(K.at(-103, 0.42, -48 + sz), Vector3.new(16, 0.25, 0.3), rgb(96, 96, 104), M.Metal, { CastShadow = false })
	end
	for i = 0, 7 do
		K.box(K.at(-110 + i * 2.1, 0.22, -48), Vector3.new(0.7, 0.2, 4.4), woodD, M.Wood, { CastShadow = false })
	end
	-- вагонетка с камнями сбоку
	do
		local cf = K.at(-99, 0, -58, 0.3)
		K.box(cf * CFrame.new(0, 1.6, 0), Vector3.new(3.4, 1.8, 2.4), rgb(110, 100, 95), M.Metal)
		for _, w in ipairs({ { -1.1, -1.25 }, { 1.1, -1.25 }, { -1.1, 1.25 }, { 1.1, 1.25 } }) do
			K.hcyl(cf * CFrame.new(w[1], 0.55, w[2]) * CFrame.Angles(0, math.pi / 2, 0), 0.3, 1.1, rgb(50, 50, 55), M.Metal)
		end
		for i = 1, 4 do
			K.ball((cf * CFrame.new(K.rnd(-1, 1), 2.8, K.rnd(-0.6, 0.6))).Position, K.rnd(0.9, 1.3), rgb(120, 116, 112), M.Slate)
		end
		K.ball((cf * CFrame.new(0.4, 3, 0)).Position, 0.8, rgb(255, 210, 80), M.Neon, { CastShadow = false })
	end
	K.block(-108, -48, 12)
	K.blockRect(-126, -72, -98, -24)

	-- база игроков: замок
	K.castle(68, 61, 0, {
		wall = rgb(228, 220, 206), trim = rgb(214, 178, 82), roof = rgb(58, 114, 206), flag = rgb(236, 72, 72),
		mat = M.Limestone, roofMat = M.SmoothPlastic, trimMat = M.SmoothPlastic, glow = rgb(255, 214, 130),
	})
	K.spawns(47, 43, K.face(47, 43, 0, 0))

	-- мельница
	do
		local x, z = -64, 52
		local base = K.at(x, K.groundY(x, z), z, K.face(x, z, 20, 0))
		for i = 0, 5 do
			K.cyl((base * CFrame.new(0, 1.5 + i * 3, 0)).Position, 3.04, 12 - i * 0.9, (i % 2 == 0) and rgb(230, 222, 204) or rgb(214, 206, 188), M.Limestone)
		end
		K.cone((base * CFrame.new(0, 18, 0)).Position, 8, 10.6, rgb(178, 72, 56), M.SmoothPlastic, 7)
		K.box(base * CFrame.new(0, 2.6, -5.7), Vector3.new(2.8, 5.2, 1), rgb(124, 78, 46), M.Wood)
		K.box(base * CFrame.new(0, 10.5, -4.9), Vector3.new(1.8, 2.2, 0.6), rgb(255, 222, 150), M.Glass, { CastShadow = false })
		local hub = base * CFrame.new(0, 19.5, -6.6)
		local blades = K.group("Windmill", { Rotor = 35 })
		K.inside(blades, function()
			K.hcyl(hub * CFrame.Angles(0, math.pi / 2, 0) * CFrame.new(0, 0, 0), 2.4, 1.8, rgb(90, 62, 40), M.Wood)
			for k = 0, 3 do
				local arm = hub * CFrame.Angles(0, 0, k * math.pi / 2)
				K.box(arm * CFrame.new(0, 7.2, -0.5), Vector3.new(0.7, 14, 0.5), rgb(112, 78, 48), M.Wood)
				K.box(arm * CFrame.new(1.7, 8.2, -0.6), Vector3.new(2.8, 11, 0.15), rgb(246, 240, 226), M.Fabric)
			end
		end)
		K.rest(blades, hub)
		K.block(x, z, 8)
	end

	-- поле с грядками, забор, амбар, сено
	do
		local x1, z1, x2, z2 = -42, 38, -16, 62
		for row = 0, 7 do
			local z = z1 + 2 + row * 3
			K.box(K.at((x1 + x2) / 2, 0.12, z), Vector3.new(x2 - x1 - 2, 0.3, 1.8), rgb(110, 80, 52), M.Ground, { CastShadow = false })
			local kind = row % 3
			for x = x1 + 2, x2 - 2, 2.2 do
				if kind == 0 then
					K.ball(K.v(x, 0.7, z), 1.1, rgb(80, 170, 60), M.Grass, { CastShadow = false })
				elseif kind == 1 then
					K.ball(K.v(x, 0.75, z), 1.4, rgb(240, 140, 40), M.SmoothPlastic)
					K.box(K.at(x, 1.55, z), Vector3.new(0.2, 0.5, 0.2), rgb(80, 120, 50), M.Wood, { CastShadow = false })
				else
					K.box(K.at(x, 1, z, K.rnd(-0.3, 0.3)), Vector3.new(0.3, 2, 0.3), rgb(236, 200, 90), M.Grass, { CastShadow = false })
				end
			end
		end
		K.fence({ { x1 - 2, z1 - 1 }, { x2 + 2, z1 - 1 }, { x2 + 2, z2 + 2 }, { x1 - 2, z2 + 2 }, { x1 - 2, z1 - 1 } }, rgb(140, 100, 62), rgb(160, 118, 74))
		K.rect(x1 - 3, z1 - 2, x2 + 3, z2 + 3)
		-- пугало
		K.box(K.at(-29, 3, 50), Vector3.new(0.4, 6, 0.4), rgb(110, 80, 50), M.Wood)
		K.box(K.at(-29, 4.4, 50), Vector3.new(4.4, 0.35, 0.35), rgb(110, 80, 50), M.Wood)
		K.box(K.at(-29, 4.2, 50), Vector3.new(2, 2.2, 1), rgb(70, 110, 200), M.Fabric)
		K.ball(K.v(-29, 6.3, 50), 1.6, rgb(230, 200, 120), M.Fabric)
		K.cyl(K.v(-29, 7.2, 50), 0.3, 3, rgb(200, 160, 70), M.Fabric)
		K.cyl(K.v(-29, 7.7, 50), 1, 1.5, rgb(200, 160, 70), M.Fabric)
	end
	K.house(26, 58, 0, {
		w = 16, d = 12, h = 9, wall = rgb(186, 52, 46), wallMat = M.WoodPlanks, roof = rgb(92, 78, 74), roofMat = M.Slate,
		trim = rgb(246, 240, 230), door = rgb(150, 42, 36), chimney = false, glass = rgb(255, 232, 160),
	})
	for _, h in ipairs({ { 38, 50, 0.2 }, { 41, 54, 1.4 }, { 37, 45, 0.8 }, { 14, 50, 0.5 } }) do
		K.hcyl(K.at(h[1], 1.3, h[2], h[3]), 3.2, 2.6, rgb(230, 196, 96), M.Grass)
	end

	-- деревенские домики, колодец, пруд с кувшинками
	local cottage = {
		{ -64, -80, rgb(244, 232, 210), rgb(190, 82, 60) }, { -30, -84, rgb(236, 222, 196), rgb(70, 120, 180) },
		{ 40, -64, rgb(246, 236, 214), rgb(196, 96, 60) }, { 104, 10, rgb(240, 228, 206), rgb(110, 150, 80) },
	}
	for _, c in ipairs(cottage) do
		K.house(c[1], c[2], K.face(c[1], c[2], 0, 0), { wall = c[3], roof = c[4], w = 12, d = 10, h = 8 })
		K.flowers(c[1], c[2], 9, 10, { rgb(255, 120, 140), rgb(255, 220, 90), rgb(240, 240, 255) })
	end
	do
		local x, z = -26, -68
		K.cyl(K.v(x, 1, z), 2, 5, rgb(150, 145, 140), M.Cobblestone)
		K.cyl(K.v(x, 1.95, z), 0.2, 4.2, rgb(60, 130, 180), M.Glass, { Transparency = 0.2 })
		for _, sx in ipairs({ -1, 1 }) do
			K.box(K.at(x + sx * 2.3, 3.6, z), Vector3.new(0.4, 5, 0.4), rgb(110, 76, 46), M.Wood)
		end
		K.wedge(K.at(x, 6.6, z - 0.9), Vector3.new(6, 1.4, 1.8), rgb(176, 74, 56), M.SmoothPlastic)
		K.wedge(K.at(x, 6.6, z + 0.9, math.pi), Vector3.new(6, 1.4, 1.8), rgb(176, 74, 56), M.SmoothPlastic)
		K.block(x, z, 4)
	end
	K.river({ { 56, -82 }, { 62, -80 } }, { r = 8, depth = 4, bed = M.Mud, bank = M.Grass })
	for i = 1, 7 do
		local a = i * 0.9
		K.cyl(K.v(59 + math.cos(a) * 5, -0.92, -81 + math.sin(a) * 4), 0.12, K.rnd(1.6, 2.4), rgb(70, 160, 70), M.Grass, { CastShadow = false })
	end
	K.ball(K.v(57, -0.6, -79), 0.7, rgb(255, 170, 200), M.SmoothPlastic, { CastShadow = false })

	-- фонари на поворотах
	K.corners(P, 9.5, function(x, z) K.lamp(x, z, rgb(255, 214, 140)) end)

	-- лес по краю и деревья внутри
	local leaves = { rgb(88, 170, 64), rgb(110, 186, 70), rgb(74, 150, 60), rgb(130, 190, 80) }
	K.scatter(46, { rMin = 105, rMax = 158, cx = 0, cz = 0 }, 6, function(x, z)
		if K.rnd(0, 1) < 0.45 then K.pine(x, z, K.rnd(1, 1.5), rgb(60, 130, 70)) else K.oak(x, z, K.rnd(1, 1.4), leaves) end
	end, 3)
	K.scatter(16, { -100, -100, 100, 100 }, 7, function(x, z) K.oak(x, z, K.rnd(0.8, 1.15), leaves) end, 2.5)
	K.scatter(30, { -140, -140, 140, 140 }, 3, function(x, z) K.bush(x, z, K.rnd(0.7, 1.1), leaves) end)
	K.scatter(44, { -140, -140, 140, 140 }, 1.5, function(x, z)
		K.flowers(x, z, 3, 6, { rgb(255, 110, 130), rgb(255, 225, 80), rgb(250, 250, 255), rgb(190, 130, 255), rgb(255, 160, 60) })
	end)
	K.scatter(12, { -140, -140, 140, 140 }, 4, function(x, z) K.boulder(x, z, K.rnd(0.8, 1.4), M.Rock) end, 2.5)
	K.scatter(10, { -120, -120, 120, 120 }, 2, function(x, z) K.rock(x, z, K.rnd(0.5, 0.8), rgb(150, 146, 140)) end)

	-- бабочки
	K.ambient({
		Color = rgb(255, 240, 140), Color2 = rgb(255, 170, 220), Size = NumberSequence.new(0.35), Rate = 14,
		Lifetime = NumberRange.new(5, 8), Speed = NumberRange.new(0.6, 1.6), y = 4, h = 4, size = 220, LightEmission = 0.4,
	})
	K.lighting({
		clock = 14.2, brightness = 2.5, ambient = rgb(100, 100, 112), outdoor = rgb(150, 150, 162), shift = rgb(255, 244, 224),
		density = 0.28, offset = 0.15, atmColor = rgb(199, 216, 240), decay = rgb(150, 182, 222), glare = 0.25, haze = 1,
		bloom = 0.35, saturation = 0.18, contrast = 0.08, sunrays = 0.08, clouds = 0.55,
	})
	K.walls()
end

---------------------------------------------------------------- 2. DESERT CANYON — пески, скалы, руины, пирамида

MAPS.Canyon = function()
	K.reset(2202)
	K.colors({
		Sand = rgb(234, 198, 138), Sandstone = rgb(206, 126, 80), Rock = rgb(170, 98, 66), Limestone = rgb(238, 208, 158),
		Ground = rgb(198, 152, 102), Salt = rgb(242, 228, 202), Grass = rgb(134, 166, 72), LeafyGrass = rgb(112, 152, 70), Mud = rgb(150, 110, 75),
	})
	K.water(rgb(60, 170, 175), 0.3)
	K.ground(M.Sand)

	-- слоистая скала (столовая гора)
	local function butte(x, z, r, h)
		local mats = { M.Sandstone, M.Sandstone, M.Limestone, M.Rock, M.Sandstone }
		local y, i = -8, 0
		while y < h do
			local rr = r - i * K.rnd(0.2, 0.9)
			K.tCyl(x + K.rnd(-0.8, 0.8), y + 2, z + K.rnd(-0.8, 0.8), 4.2, rr, mats[(i % #mats) + 1])
			y += 4
			i += 1
		end
	end
	K.ring(166, 30, function(x, z) butte(x, z, K.rnd(18, 28), K.rnd(22, 44)) end)
	K.ring(214, 44, function(x, z) butte(x, z, K.rnd(30, 44), K.rnd(30, 56)) end)

	-- дорога
	local P = { { -95, 0 }, { -55, -40 }, { -5, -40 }, { 15, 5 }, { -25, 45 }, { 35, 70 }, { 85, 30 } }
	-- скалы внутри карты
	butte(-78, 74, 15, 30)
	butte(-104, 52, 10, 22)
	butte(24, -88, 14, 26)
	butte(-60, -86, 11, 18)
	butte(112, -40, 12, 24)
	K.block(-78, 74, 17)
	K.block(-104, 52, 12)
	K.block(24, -88, 16)
	K.block(-60, -86, 13)
	K.block(112, -40, 14)

	-- оазис
	K.tCyl(62, -1.5, -22, 3, 17, M.Grass)
	K.tCyl(62, -1.5, -22, 3, 12, M.LeafyGrass)
	K.river({ { 60, -22 }, { 66, -20 } }, { r = 8, depth = 4, bed = M.Sand, bank = M.Sand })

	K.path(P, {
		color = rgb(184, 116, 74), mat = M.Sandstone, discColor = rgb(176, 110, 70),
		edge = K.stoneEdge({ rgb(236, 206, 156), rgb(222, 190, 140), rgb(244, 220, 172) }, M.Sandstone),
	})
	-- барханы (после дороги, чтобы не легли на неё)
	for _ = 1, 40 do
		local x, z = K.rnd(-140, 140), K.rnd(-140, 140)
		if K.free(x, z, 15) then K.tBall(x, -15, z, K.rnd(18, 22), M.Sand) end
	end

	-- ворота: древняя арка в ущелье
	do
		local d = K.startDir(P)
		local right = Vector3.new(-d.Z, 0, d.X)
		local x0, z0 = P[1][1] - d.X * 5, P[1][2] - d.Z * 5
		local g = K.at(x0, 0, z0, K.yawOf(d))
		local stone, dark = rgb(222, 176, 116), rgb(170, 120, 78)
		for _, s in ipairs({ -1, 1 }) do
			K.box(g * CFrame.new(s * 7, 0.6, 0), Vector3.new(4.4, 1.2, 4.4), dark, M.Sandstone)
			K.box(g * CFrame.new(s * 7, 7.2, 0), Vector3.new(3.4, 12, 3.4), stone, M.Sandstone)
			for k = 1, 3 do
				K.box(g * CFrame.new(s * 7, 2 + k * 3, -1.75), Vector3.new(2.6, 0.5, 0.15), rgb(70, 140, 160), M.SmoothPlastic, { CastShadow = false })
			end
			K.box(g * CFrame.new(s * 7, 13.6, 0), Vector3.new(4.2, 1, 4.2), dark, M.Sandstone)
			K.flame((g * CFrame.new(s * 7, 14.9, 0)).Position, 1.2)
			K.box(g * CFrame.new(s * 7, 14.3, 0), Vector3.new(2.4, 0.6, 2.4), rgb(90, 80, 70), M.Metal)
			butte(x0 - d.X * 14 + right.X * s * 17, z0 - d.Z * 14 + right.Z * s * 17, 12, 34)
			butte(x0 - d.X * 30 + right.X * s * 11, z0 - d.Z * 30 + right.Z * s * 11, 14, 38)
		end
		K.box(g * CFrame.new(0, 15.6, 0), Vector3.new(19, 2.6, 4), stone, M.Sandstone)
		K.box(g * CFrame.new(0, 17.4, 0), Vector3.new(15, 1, 3.4), dark, M.Sandstone)
		K.gem((g * CFrame.new(0, 15.6, -2.3)).Position, 1.4, rgb(80, 220, 255))
		K.box(g * CFrame.new(0, 15.6, -2.05), Vector3.new(12, 0.5, 0.2), rgb(255, 200, 70), M.Foil, { CastShadow = false })
		K.block(x0 - d.X * 6, z0 - d.Z * 6, 14)
	end

	-- база: пирамида
	do
		local e = K.endDir(P)
		local cx, cz = P[#P][1] + e.X * 13, P[#P][2] + e.Z * 13
		local b = K.at(cx, 0, cz, K.yawOf(-e))
		for i = 0, 7 do
			local s = 28 - i * 3.3
			K.box(b * CFrame.new(0, 1.4 + i * 2.8, 2), Vector3.new(s, 2.8, s), (i % 2 == 0) and rgb(232, 196, 136) or rgb(220, 182, 122), M.Sandstone)
		end
		K.box(b * CFrame.new(0, 23.6, 2), Vector3.new(4, 2.2, 4), rgb(255, 205, 70), M.Foil)
		local tip = K.box(b * CFrame.new(0, 25.3, 2), Vector3.new(2, 1.4, 2), rgb(255, 220, 110), M.Neon)
		K.light(tip, rgb(255, 210, 120), 30, 2)
		-- вход
		K.box(b * CFrame.new(0, 3.6, -12.2), Vector3.new(7, 7.2, 1.2), rgb(214, 170, 110), M.Sandstone)
		K.box(b * CFrame.new(0, 3, -12.85), Vector3.new(4, 6, 0.2), rgb(25, 18, 14), M.SmoothPlastic)
		K.box(b * CFrame.new(0, 7.6, -12.9), Vector3.new(8, 1, 1.6), rgb(255, 200, 70), M.Foil)
		-- обелиски и факелы
		for _, s in ipairs({ -1, 1 }) do
			local o = b * CFrame.new(s * 9, 0, -16)
			K.box(o * CFrame.new(0, 0.6, 0), Vector3.new(3, 1.2, 3), rgb(190, 146, 96), M.Sandstone)
			K.box(o * CFrame.new(0, 6.2, 0), Vector3.new(1.8, 10, 1.8), rgb(226, 186, 128), M.Sandstone)
			K.box(o * CFrame.new(0, 11.7, 0) * CFrame.Angles(0, math.rad(45), 0), Vector3.new(1.3, 1, 1.3), rgb(255, 205, 70), M.Foil)
			K.torch((b * CFrame.new(s * 5, 0, -15)).X - O.X, (b * CFrame.new(s * 5, 0, -15)).Z - O.Z, 4.5)
		end
		K.zone(cx, cz, 20)
		K.block(cx, cz, 16)
	end
	K.spawns(68, -2, K.face(68, -2, 0, 10))

	-- руины храма
	do
		local x, z = -62, 34
		local g = K.at(x, 0, z, 0.35)
		K.box(g * CFrame.new(0, 0.5, 0), Vector3.new(22, 1, 14), rgb(214, 172, 116), M.Sandstone)
		K.box(g * CFrame.new(0, 1.3, 0), Vector3.new(18, 0.6, 10), rgb(226, 186, 130), M.Sandstone)
		local hs = { 11, 7, 11, 4, 11, 9 }
		for i = 0, 5 do
			local lx, lz = -7.5 + (i % 3) * 7.5, (i < 3) and -3.6 or 3.6
			K.cyl((g * CFrame.new(lx, 1.6 + hs[i + 1] / 2, lz)).Position, hs[i + 1], 1.9, rgb(232, 200, 150), M.Sandstone)
			if hs[i + 1] >= 11 then
				K.box(g * CFrame.new(lx, 1.6 + hs[i + 1] + 0.4, lz), Vector3.new(2.8, 0.8, 2.8), rgb(214, 176, 124), M.Sandstone)
			end
		end
		K.box(g * CFrame.new(0, 13.4, 3.6), Vector3.new(18, 1.4, 2.8), rgb(220, 182, 128), M.Sandstone)
		K.hcyl(g * CFrame.new(4, 2.6, -8) * CFrame.Angles(0, 0.3, 0), 9, 1.9, rgb(226, 192, 140), M.Sandstone)
		for i = 1, 5 do
			K.box(g * CFrame.new(K.rnd(-10, 10), 1.6, K.rnd(-8, 8)) * CFrame.Angles(K.rnd(-0.4, 0.4), K.rnd(0, 3), 0.2), Vector3.new(K.rnd(1.5, 2.5), 1.2, K.rnd(1.5, 2.2)), rgb(210, 168, 112), M.Sandstone)
		end
		K.block(x, z, 12)
	end
	-- одинокие колонны
	for _, c in ipairs({ { -22, -4 }, { -30, 12 }, { 30, -16 }, { -10, 66 }, { 66, 78 }, { -84, -30 } }) do
		local h = K.rnd(4, 10)
		K.cyl(K.v(c[1], h / 2, c[2]), h, 1.8, rgb(230, 198, 148), M.Sandstone)
		K.box(K.at(c[1], 0.4, c[2]), Vector3.new(2.6, 0.8, 2.6), rgb(210, 170, 116), M.Sandstone)
		K.block(c[1], c[2], 1.8)
	end

	-- скелет огромного зверя
	do
		local x, z = 40, -58
		local g = K.at(x, 0, z, 0.6)
		local bone = rgb(244, 238, 222)
		for i = 0, 9 do
			K.box(g * CFrame.new(0, 3.4 + math.sin(i / 3) * 0.6, -9 + i * 2), Vector3.new(0.9, 0.9, 1.6), bone, M.SmoothPlastic)
		end
		for i = 0, 5 do
			for _, s in ipairs({ -1, 1 }) do
				K.box(g * CFrame.new(s * 2, 2, -6 + i * 2.2) * CFrame.Angles(0, 0, s * 0.45), Vector3.new(0.5, 4.6, 0.5), bone, M.SmoothPlastic)
			end
		end
		K.box(g * CFrame.new(0, 2, -12) * CFrame.Angles(0.3, 0, 0), Vector3.new(3, 2.4, 4), bone, M.SmoothPlastic)
		K.box(g * CFrame.new(0, 0.8, -13.4), Vector3.new(2.4, 0.8, 3), bone, M.SmoothPlastic)
		for _, s in ipairs({ -1, 1 }) do
			K.box(g * CFrame.new(s * 1.4, 3.6, -12.4) * CFrame.Angles(0.5, 0, s * 0.5), Vector3.new(0.5, 2.6, 0.5), bone, M.SmoothPlastic)
		end
		K.block(x, z, 9)
	end

	-- лагерь у оазиса: шатры, костёр
	for _, t in ipairs({ { 86, -36, rgb(220, 70, 60) }, { 80, -2, rgb(70, 120, 200) } }) do
		local g = K.at(t[1], 0, t[2], K.face(t[1], t[2], 62, -22))
		K.wedge(g * CFrame.new(0, 2.5, -1.75), Vector3.new(7, 5, 3.5), t[3], M.Fabric)
		K.wedge(g * CFrame.new(0, 2.5, 1.75) * CFrame.Angles(0, math.pi, 0), Vector3.new(7, 5, 3.5), rgb(240, 230, 210), M.Fabric)
		K.box(g * CFrame.new(0, 2.6, 0), Vector3.new(0.3, 5.2, 0.3), rgb(110, 80, 50), M.Wood)
		K.block(t[1], t[2], 5)
	end
	K.flame(K.v(74, 0.8, -16), 1.1)
	for i = 1, 5 do
		local a = i * 1.26
		K.box(K.at(74 + math.cos(a) * 1.3, 0.3, -16 + math.sin(a) * 1.3, a), Vector3.new(1.8, 0.4, 0.5), rgb(90, 60, 40), M.Wood)
	end
	for i = 1, 6 do
		local a = i * 1.05
		K.palm(62 + math.cos(a) * 13, -22 + math.sin(a) * 11, K.rnd(0.9, 1.2))
		K.block(62 + math.cos(a) * 13, -22 + math.sin(a) * 11, 2)
	end
	K.barrel(90, -28, 1)
	K.crate(91, -25, 1)
	K.crate(87, -8, 0.9)

	-- кактусы
	local function cactus(x, z, s)
		local gy = K.groundY(x, z)
		local green = rgb(80, 150, 70):Lerp(rgb(110, 170, 80), K.rnd(0, 1))
		local h = K.rnd(7, 11) * s
		K.cyl(K.v(x, gy + h / 2, z), h, 1.8 * s, green, M.Grass)
		K.ball(K.v(x, gy + h, z), 1.8 * s, green, M.Grass)
		local a = K.rnd(0, 6.28)
		for k = 0, K.int(1, 2) - 1 do
			local aa = a + k * math.pi
			local dx, dz = math.cos(aa), math.sin(aa)
			local y = gy + K.rnd(0.35, 0.6) * h
			local len = 2.2 * s
			K.box(CFrame.lookAt(K.v(x + dx * len / 2, y, z + dz * len / 2), K.v(x + dx * len, y, z + dz * len)), Vector3.new(1.2 * s, 1.2 * s, len), green, M.Grass)
			local ah = K.rnd(2.5, 4) * s
			K.cyl(K.v(x + dx * len, y + ah / 2, z + dz * len), ah, 1.2 * s, green, M.Grass)
			K.ball(K.v(x + dx * len, y + ah, z + dz * len), 1.2 * s, green, M.Grass)
		end
		if K.rnd(0, 1) < 0.4 then
			K.ball(K.v(x, gy + h + 0.9 * s, z), 0.7 * s, rgb(255, 120, 170), M.SmoothPlastic)
		end
	end
	-- скальные останцы между дорогой и краем
	K.scatter(9, { -130, -130, 130, 130 }, 16, function(x, z)
		butte(x, z, K.rnd(5, 8), K.rnd(10, 20))
		K.block(x, z, 8)
	end)
	-- сломанная арка и стены
	for _, w in ipairs({ { -36, -72, 0.4 }, { 92, 4, 1.1 }, { 4, 92, -0.3 } }) do
		local g = K.at(w[1], 0, w[2], w[3])
		local stone = rgb(226, 190, 136)
		K.box(g * CFrame.new(-4, 4, 0), Vector3.new(2.6, 8, 2.6), stone, M.Sandstone)
		K.box(g * CFrame.new(4, 2.6, 0), Vector3.new(2.6, 5.2, 2.6), stone, M.Sandstone)
		K.box(g * CFrame.new(-1.6, 8.6, 0) * CFrame.Angles(0, 0, -0.12), Vector3.new(7, 1.6, 2.8), stone, M.Sandstone)
		K.box(g * CFrame.new(-9, 1.5, 0.4), Vector3.new(7, 3, 1.6), rgb(214, 176, 124), M.Sandstone)
		K.box(g * CFrame.new(9, 1, -0.3) * CFrame.Angles(0, 0.2, 0), Vector3.new(6, 2, 1.6), rgb(214, 176, 124), M.Sandstone)
		for i = 1, 4 do
			K.box(g * CFrame.new(K.rnd(-8, 8), 0.6, K.rnd(-3, 3)) * CFrame.Angles(K.rnd(-0.4, 0.4), K.rnd(0, 3), 0.2), Vector3.new(K.rnd(1.4, 2.4), 1.1, K.rnd(1.2, 2)), stone, M.Sandstone)
		end
		K.block(w[1], w[2], 9)
	end
	-- статуя-голова в песке
	do
		local g = K.at(-104, 0, -40, K.face(-104, -40, 0, 0))
		K.box(g * CFrame.new(0, 3.6, 0), Vector3.new(6, 7.2, 6), rgb(222, 184, 128), M.Sandstone)
		K.box(g * CFrame.new(0, 8, 0.6), Vector3.new(7.4, 2, 7.4), rgb(70, 110, 170), M.Fabric)
		K.box(g * CFrame.new(0, 4.4, -3.1), Vector3.new(1.4, 2.2, 0.8), rgb(206, 168, 112), M.Sandstone)
		for _, sx in ipairs({ -1, 1 }) do
			K.box(g * CFrame.new(sx * 1.5, 5.6, -3.05), Vector3.new(1.2, 0.5, 0.2), rgb(40, 32, 28), M.SmoothPlastic)
			K.box(g * CFrame.new(sx * 3.6, 4.2, 0), Vector3.new(1.2, 3.4, 2.2), rgb(70, 110, 170), M.Fabric)
		end
		K.block(-104, -40, 6)
	end
	K.scatter(46, { -150, -150, 150, 150 }, 4, function(x, z) cactus(x, z, K.rnd(0.8, 1.3)) end, 1.6)
	K.scatter(18, { -140, -140, 140, 140 }, 2, function(x, z)
		local gy = K.groundY(x, z)
		K.ball(K.v(x, gy + 0.7, z), K.rnd(1.6, 2.4), rgb(90, 156, 76), M.Grass)
		K.ball(K.v(x, gy + 1.8, z), 0.6, rgb(255, 210, 90), M.SmoothPlastic)
	end)
	K.scatter(24, { -150, -150, 150, 150 }, 2, function(x, z)
		local gy = K.groundY(x, z)
		for _ = 1, 3 do
			K.box(K.at(x + K.rnd(-0.8, 0.8), gy + 0.8, z + K.rnd(-0.8, 0.8)) * CFrame.Angles(K.rnd(-0.6, 0.6), K.rnd(0, 3), K.rnd(-0.6, 0.6)), Vector3.new(0.25, 2, 0.25), rgb(150, 110, 70), M.Wood, { CastShadow = false })
		end
	end)
	K.scatter(22, { -140, -140, 140, 140 }, 4, function(x, z) K.boulder(x, z, K.rnd(0.8, 1.6), M.Sandstone) end, 2.5)
	K.scatter(18, { -130, -130, 130, 130 }, 2, function(x, z) K.rock(x, z, K.rnd(0.5, 0.9), rgb(196, 140, 92), M.Sandstone) end)
	-- черепа и перекати-поле
	K.scatter(8, { -130, -130, 130, 130 }, 2, function(x, z)
		local gy = K.groundY(x, z)
		local f = K.at(x, gy, z, K.rnd(0, 6.28))
		K.box(f * CFrame.new(0, 0.7, 0), Vector3.new(1.6, 1.3, 2), rgb(244, 238, 222), M.SmoothPlastic)
		for _, sx in ipairs({ -1, 1 }) do
			K.box(f * CFrame.new(sx * 1.4, 1.2, 0.4) * CFrame.Angles(0, 0, sx * 0.6), Vector3.new(0.4, 2, 0.4), rgb(244, 238, 222), M.SmoothPlastic)
		end
	end)
	K.scatter(10, { -140, -140, 140, 140 }, 2, function(x, z)
		local gy = K.groundY(x, z)
		K.ball(K.v(x, gy + 1.1, z), 2.2, rgb(176, 136, 86), M.Fabric, { Transparency = 0.15 })
		K.ball(K.v(x + 0.4, gy + 1.3, z - 0.3), 1.6, rgb(150, 112, 70), M.Fabric)
	end)
	K.corners(P, 9.5, function(x, z) K.torch(x, z, 4.5) end)

	-- пыль по ветру
	K.ambient({
		Texture = K.SMOKE, Color = rgb(240, 210, 160), LightEmission = 0, LightInfluence = 1,
		Size = NumberSequence.new(4, 9), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.82), NumberSequenceKeypoint.new(1, 1) }),
		Rate = 10, Lifetime = NumberRange.new(8, 12), Speed = NumberRange.new(4, 7), Spread = Vector2.new(10, 10),
		EmissionDirection = Enum.NormalId.Right, y = 3, h = 3, size = 260,
	})
	K.lighting({
		clock = 16.6, latitude = 30, brightness = 2.8, ambient = rgb(132, 102, 82), outdoor = rgb(172, 142, 112), shift = rgb(255, 212, 150),
		density = 0.3, offset = 0.1, atmColor = rgb(240, 206, 160), decay = rgb(212, 142, 92), glare = 0.6, haze = 1.6,
		bloom = 0.45, tint = rgb(255, 242, 225), saturation = 0.18, contrast = 0.12, sunrays = 0.12, clouds = 0.2,
	})
	K.walls()
end

---------------------------------------------------------------- 3. FROZEN FORTRESS — снег, лёд, замёрзшие озёра

MAPS.Frozen = function()
	K.reset(3303)
	K.colors({
		Snow = rgb(238, 244, 252), Glacier = rgb(166, 212, 246), Ice = rgb(186, 226, 250), Rock = rgb(118, 126, 142),
		Slate = rgb(108, 116, 132), Ground = rgb(200, 210, 226), Salt = rgb(226, 236, 246),
	})
	K.water(rgb(80, 150, 200), 0.3)
	K.ground(M.Snow)
	K.ring(168, 26, function(x, z)
		local r = K.rnd(24, 34)
		local y = K.rnd(-10, -3)
		K.tBall(x, y, z, r, M.Rock)
		K.tBall(x, y + r * 0.34, z, r * 0.74, M.Snow)
	end)
	K.ring(212, 36, function(x, z)
		local r = K.rnd(44, 62)
		local y = K.rnd(-22, -10)
		K.tBall(x, y, z, r, M.Rock)
		K.tBall(x, y + r * 0.4, z, r * 0.68, M.Snow)
		K.tBall(x, y + r * 0.66, z, r * 0.4, M.Glacier)
	end)

	local P = { { -70, 55 }, { -70, -30 }, { -20, -30 }, { -20, 30 }, { 30, 30 }, { 30, -40 }, { 78, -40 } }

	-- замёрзшие озёра (по льду можно ходить и ставить юнитов)
	local lakes = { { -45, 16, 12 }, { 64, 36, 16 }, { -104, -48, 13 } }
	for _, l in ipairs(lakes) do
		K.tCyl(l[1], -1, l[2], 2.2, l[3], M.Glacier)
		for _ = 1, 5 do
			local a, d = K.rnd(0, 6.28), K.rnd(0, l[3] * 0.7)
			K.box(K.at(l[1] + math.cos(a) * d, 0.05, l[2] + math.sin(a) * d, K.rnd(0, 3)), Vector3.new(K.rnd(2, 5), 0.06, 0.18), rgb(120, 170, 220), M.SmoothPlastic, { CastShadow = false })
		end
		for k = 1, 9 do
			local a = k / 9 * math.pi * 2 + K.rnd(-0.2, 0.2)
			K.tBall(l[1] + math.cos(a) * (l[3] + 1.5), -2.2, l[2] + math.sin(a) * (l[3] + 1.5), K.rnd(3, 4.5), M.Snow)
		end
		K.zone(l[1], l[2], l[3] + 2)
	end

	K.path(P, {
		color = rgb(146, 176, 210), mat = M.Cobblestone, discColor = rgb(138, 168, 204),
		edge = function(x, z, dir, k)
			if k % 3 == 0 then
				K.box(K.at(x, 0.45, z, K.rnd(0, 3)), Vector3.new(K.rnd(1.3, 1.9), K.rnd(0.9, 1.5), K.rnd(1.2, 1.7)), rgb(176, 222, 250), M.Ice, { Transparency = 0.15, CastShadow = false })
			else
				K.ball(K.v(x, 0, z), K.rnd(1.6, 2.2), rgb(246, 250, 255), M.Snow, { CastShadow = false })
			end
		end,
	})

	-- ворота: ледяная пещера
	K.tBall(-70, 4, 90, 24, M.Glacier)
	K.tBall(-90, 0, 80, 15, M.Glacier)
	K.tBall(-50, 0, 80, 15, M.Glacier)
	K.tBlock(-70, 6, 74, 24, 28, 20, M.Glacier) -- лицо пещеры: x -82..-58, z 64..84
	K.tBall(-84, 18, 76, 9, M.Glacier)
	K.tBall(-56, 18, 76, 9, M.Glacier)
	K.tBall(-72, 26, 84, 14, M.Snow)
	K.tBall(-58, 22, 88, 12, M.Snow)
	K.tBall(-86, 20, 88, 11, M.Snow)
	K.tBall(-70, 21, 72, 8, M.Snow)
	K.tBall(-97, 4, 74, 8, M.Rock)
	K.tBall(-43, 4, 74, 8, M.Rock)
	K.tBlock(-70, 4.5, 70, 8, 9, 12, M.Air)
	do
		local ice = rgb(178, 226, 252)
		K.box(K.at(-70, 4.5, 75.6), Vector3.new(8, 9, 1), rgb(20, 44, 80), M.SmoothPlastic)
		local core = K.gem(K.v(-70, 3, 73), 2.2, rgb(110, 220, 255))
		K.light(core, rgb(120, 220, 255), 22, 2.5)
		for _, s in ipairs({ -1, 1 }) do
			K.box(K.at(-70 + s * 5.2, 5, 63.4) * CFrame.Angles(0, 0, s * 0.05), Vector3.new(2.2, 10, 2.2), ice, M.Ice, { Transparency = 0.1 })
			K.crystals(-70 + s * 7.5, 61.5, 1, rgb(140, 220, 255), M.Glass)
		end
		K.box(K.at(-70, 10.4, 63.4), Vector3.new(13, 1.8, 2.6), ice, M.Ice, { Transparency = 0.1 })
		for i = -5, 5 do
			local len = K.rnd(1.5, 3.4)
			for k = 0, 2 do
				K.cyl(K.v(-70 + i * 1.1, 9.4 - len * (k + 0.5) / 3, 62.4), len / 3 + 0.02, 0.7 - k * 0.2, rgb(214, 240, 255), M.Ice, { Transparency = 0.1, CastShadow = false })
			end
		end
		K.blockRect(-94, 61, -46, 94)
	end

	-- база: ледяной замок
	K.castle(87, -40, math.pi / 2, {
		wall = rgb(196, 230, 252), mat = M.Ice, trim = rgb(244, 250, 255), trimMat = M.SmoothPlastic,
		roof = rgb(70, 122, 212), roofMat = M.SmoothPlastic, flag = rgb(90, 204, 255), glow = rgb(150, 232, 255),
	})
	K.spawns(68, -14, K.face(68, -14, 0, 0))

	-- снеговики, иглу, пингвины, ёлка с подарками
	local function snowman(x, z, s, yaw)
		local gy = K.groundY(x, z)
		local snow = rgb(248, 251, 255)
		K.ball(K.v(x, gy + 2 * s, z), 4.4 * s, snow, M.Snow)
		K.ball(K.v(x, gy + 5.2 * s, z), 3.3 * s, snow, M.Snow)
		K.ball(K.v(x, gy + 7.7 * s, z), 2.4 * s, snow, M.Snow)
		local f = K.at(x, gy + 7.7 * s, z, yaw)
		K.hcyl(f * CFrame.new(0, -0.1 * s, -1.5 * s) * CFrame.Angles(0, math.pi / 2, 0), 1.5 * s, 0.42 * s, rgb(255, 130, 30), M.SmoothPlastic)
		for _, sx in ipairs({ -1, 1 }) do
			K.ball((f * CFrame.new(sx * 0.45 * s, 0.35 * s, -1.02 * s)).Position, 0.32 * s, rgb(20, 20, 25), M.SmoothPlastic)
			K.box(f * CFrame.new(sx * 2.3 * s, -2.3 * s, 0) * CFrame.Angles(0, 0, -sx * 0.9), Vector3.new(0.25 * s, 3 * s, 0.25 * s), rgb(100, 70, 45), M.Wood)
		end
		for k = 0, 2 do
			K.ball((f * CFrame.new(0, -1.9 * s - k * 0.75 * s, -1.55 * s + k * 0.05 * s)).Position, 0.36 * s, rgb(20, 20, 25), M.SmoothPlastic)
		end
		K.cyl(K.v(x, gy + 6.6 * s, z), 0.6 * s, 2.5 * s, rgb(220, 50, 60), M.Fabric)
		K.cyl(K.v(x, gy + 8.8 * s, z), 0.3 * s, 2.6 * s, rgb(30, 30, 40), M.SmoothPlastic)
		K.cyl(K.v(x, gy + 9.7 * s, z), 1.6 * s, 1.7 * s, rgb(30, 30, 40), M.SmoothPlastic)
		K.cyl(K.v(x, gy + 9.1 * s, z), 0.35 * s, 1.75 * s, rgb(220, 50, 60), M.SmoothPlastic)
	end
	local function igloo(x, z, yaw)
		local gy = K.groundY(x, z)
		local snow = rgb(242, 248, 255)
		K.ball(K.v(x, gy - 0.5, z), 12, snow, M.Snow)
		for k = 1, 3 do
			local h = k * 1.5 - 0.5
			K.cyl(K.v(x, gy + h, z), 0.22, 2 * math.sqrt(math.max(1, 36 - (h + 0.5) ^ 2)) + 0.12, rgb(208, 224, 242), M.Snow, { CastShadow = false })
		end
		local f = K.at(x, gy, z, yaw)
		K.hcyl(f * CFrame.new(0, 1, -6) * CFrame.Angles(0, math.pi / 2, 0), 4, 5, snow, M.Snow)
		K.box(f * CFrame.new(0, 1.3, -8.02), Vector3.new(2.6, 2.6, 0.2), rgb(30, 50, 80), M.SmoothPlastic)
		local glow = K.box(f * CFrame.new(0, 1.3, -7.9), Vector3.new(1.2, 1.2, 0.1), rgb(255, 200, 120), M.Neon, { Transparency = 0.5, CastShadow = false })
		K.light(glow, rgb(255, 190, 120), 10, 1.2)
		K.block(x, z, 7.5)
	end
	local function penguin(x, z, yaw, s)
		local gy = K.groundY(x, z)
		local f = K.at(x, gy, z, yaw)
		local black, white, orange = rgb(30, 32, 40), rgb(248, 248, 252), rgb(255, 150, 40)
		K.ball((f * CFrame.new(0, 1.3 * s, 0)).Position, 2.4 * s, black, M.SmoothPlastic)
		K.ball((f * CFrame.new(0, 1.15 * s, -0.42 * s)).Position, 1.8 * s, white, M.SmoothPlastic)
		K.ball((f * CFrame.new(0, 2.9 * s, 0)).Position, 1.6 * s, black, M.SmoothPlastic)
		K.box(f * CFrame.new(0, 2.75 * s, -0.85 * s), Vector3.new(0.4, 0.3, 0.7) * s, orange, M.SmoothPlastic)
		for _, sx in ipairs({ -1, 1 }) do
			K.ball((f * CFrame.new(sx * 0.32 * s, 3.1 * s, -0.68 * s)).Position, 0.3 * s, white, M.SmoothPlastic)
			K.box(f * CFrame.new(sx * 0.45 * s, 0.1 * s, -0.4 * s), Vector3.new(0.6, 0.2, 0.9) * s, orange, M.SmoothPlastic)
			K.box(f * CFrame.new(sx * 1.15 * s, 1.5 * s, 0) * CFrame.Angles(0, 0, sx * 0.25), Vector3.new(0.3, 1.6, 1) * s, black, M.SmoothPlastic)
		end
	end
	local function gift(x, z, s, color, ribbon)
		local gy = K.groundY(x, z)
		local cf = K.at(x, gy + s / 2, z, K.rnd(0, 1.5))
		K.box(cf, Vector3.one * s, color, M.SmoothPlastic)
		K.box(cf, Vector3.new(s + 0.08, s + 0.08, s * 0.22), ribbon, M.SmoothPlastic)
		K.box(cf, Vector3.new(s * 0.22, s + 0.08, s + 0.08), ribbon, M.SmoothPlastic)
		K.ball((cf * CFrame.new(0, s / 2 + 0.2, 0)).Position, s * 0.35, ribbon, M.SmoothPlastic)
	end

	for _, s in ipairs({ { -100, 18, 1.1 }, { 4, 70, 1 }, { 46, -70, 1.2 }, { -38, -64, 0.9 }, { -4, 2, 0.8 }, { 102, 20, 1 } }) do
		snowman(s[1], s[2], s[3], K.face(s[1], s[2], 0, 0))
		K.block(s[1], s[2], 2.6 * s[3])
	end
	igloo(-112, -10, K.face(-112, -10, 0, 0))
	igloo(-6, 92, K.face(-6, 92, 0, 0))
	igloo(108, 46, K.face(108, 46, 0, 0))
	for i = 1, 5 do
		local a = i * 1.2
		penguin(64 + math.cos(a) * 8, 36 + math.sin(a) * 7, K.rnd(0, 6.28), i == 3 and 0.7 or 1)
	end
	penguin(-41, 18, 1, 0.9)
	penguin(-48, 13, 4, 0.7)

	-- большая ёлка
	do
		local x, z, s = 92, 76, 2.4
		K.pine(x, z, s, rgb(46, 120, 76), true)
		local gy = K.groundY(x, z)
		local cols = { rgb(255, 70, 80), rgb(255, 210, 60), rgb(80, 180, 255), rgb(200, 100, 255), rgb(90, 230, 120) }
		for i, dd in ipairs({ 9, 7.2, 5.4, 3.6 }) do
			local y = gy + 3.6 * s + i * 2.4 * s - 1.1 * s
			local n = 10 - i * 2
			for k = 1, n do
				local a = k / n * math.pi * 2 + i
				local r = dd * s / 2 - 0.2
				K.ball(K.v(x + math.cos(a) * r, y, z + math.sin(a) * r), 1.1, cols[(k + i) % #cols + 1], M.Neon, { CastShadow = false })
			end
		end
		local star = K.gem(K.v(x, gy + 16.5 * s, z), 2.6, rgb(255, 225, 90))
		K.light(star, rgb(255, 220, 120), 30, 2.5)
		for k = 1, 7 do
			local a = k * 0.9
			gift(x + math.cos(a) * 9, z + math.sin(a) * 9, K.rnd(1.6, 2.6), cols[k % #cols + 1], rgb(250, 250, 255))
		end
		K.block(x, z, 12)
	end

	-- ёлки, кристаллы, сугробы
	K.scatter(44, { rMin = 100, rMax = 160, cx = 0, cz = 0 }, 6, function(x, z) K.pine(x, z, K.rnd(1.1, 1.7), rgb(52, 116, 84), true) end, 3)
	K.scatter(14, { -110, -110, 110, 110 }, 6, function(x, z) K.pine(x, z, K.rnd(0.8, 1.1), rgb(56, 122, 88), true) end, 2.5)
	K.scatter(12, { -140, -140, 140, 140 }, 4, function(x, z)
		K.crystals(x, z, K.rnd(0.9, 1.4), rgb(150, 222, 255), M.Glass)
		if K.rnd(0, 1) < 0.5 then K.crystals(x + 1.5, z + 1, 0.6, rgb(120, 230, 255), M.Neon) end
	end, 2.5)
	K.scatter(10, { -140, -140, 140, 140 }, 4, function(x, z) K.deadTree(x, z, K.rnd(0.8, 1.2), rgb(206, 220, 238)) end, 1.5)
	K.scatter(18, { -150, -150, 150, 150 }, 3, function(x, z) K.tBall(x, -3, z, K.rnd(4, 6.5), M.Snow) end)
	K.scatter(8, { -130, -130, 130, 130 }, 3, function(x, z) K.boulder(x, z, K.rnd(0.8, 1.2), M.Rock) end, 2)
	K.corners(P, 9.5, function(x, z) K.lamp(x, z, rgb(170, 225, 255), rgb(60, 70, 90)) end)

	-- снег идёт
	K.ambient({
		Texture = K.SMOKE, Color = WHITE, Size = NumberSequence.new(0.4), Rate = 90, Lifetime = NumberRange.new(10, 14),
		Speed = NumberRange.new(3, 5), Spread = Vector2.new(20, 20), EmissionDirection = Enum.NormalId.Bottom,
		Acceleration = Vector3.new(0.8, 0, 0.4), Transparency = NumberSequence.new(0.1, 0.5), LightEmission = 0.3, LightInfluence = 1,
		y = 42, h = 2, size = 260,
	})
	K.lighting({
		clock = 12.6, latitude = 55, brightness = 2.4, ambient = rgb(124, 134, 154), outdoor = rgb(168, 182, 206), shift = rgb(226, 238, 255),
		density = 0.35, offset = 0.18, atmColor = rgb(206, 224, 250), decay = rgb(150, 180, 226), glare = 0.15, haze = 1.6,
		bloom = 0.5, bloomThreshold = 1.2, tint = rgb(238, 246, 255), saturation = 0.02, contrast = 0.1, clouds = 0.7, cloudColor = rgb(236, 241, 250),
	})
	K.walls()
end

---------------------------------------------------------------- 4. LAVA VOLCANO — лава, вулкан, обсидиан

MAPS.Volcano = function()
	K.reset(4404)
	K.colors({
		Basalt = rgb(66, 60, 62), Rock = rgb(96, 84, 82), CrackedLava = rgb(236, 96, 34), Slate = rgb(74, 68, 70),
		Ground = rgb(86, 72, 66), Asphalt = rgb(44, 40, 42), Mud = rgb(62, 52, 50),
	})
	K.ground(M.Basalt)
	K.ring(168, 24, function(x, z)
		K.tBall(x, K.rnd(-10, -3), z, K.rnd(22, 32), K.rnd(0, 1) < 0.6 and M.Basalt or M.Rock)
	end)
	K.ring(212, 34, function(x, z)
		K.tBall(x, K.rnd(-24, -12), z, K.rnd(44, 62), M.Rock)
	end)

	-- вулкан
	local vx, vz = -24, 128
	for i = 0, 15 do
		local r = 50 - i * 2.6
		K.tCyl(vx + K.rnd(-1, 1), i * 4 - 2, vz + K.rnd(-1, 1), 4.2, r, (i % 5 == 2) and M.Rock or M.Basalt)
	end
	K.tCyl(vx, 62, vz, 16, 8, M.Air)
	K.tCyl(vx, 54, vz, 2, 8, M.CrackedLava)
	do
		local top = K.cyl(K.v(vx, 55.4, vz), 0.6, 15, rgb(255, 112, 30), M.Neon, { CastShadow = false })
		K.light(top, rgb(255, 120, 50), 40, 3)
		local plume = K.anchor(K.v(vx, 58, vz), Vector3.new(10, 1, 10))
		K.emitter(plume, {
			Texture = K.SMOKE, Color = rgb(74, 62, 62), Color2 = rgb(40, 36, 38), LightEmission = 0, LightInfluence = 1,
			Size = NumberSequence.new(8, 26), Transparency = NumberSequence.new(0.3, 1), Lifetime = NumberRange.new(7, 10),
			Speed = NumberRange.new(6, 10), Spread = Vector2.new(12, 12), Rate = 5, EmissionDirection = Enum.NormalId.Top, Acceleration = Vector3.new(2, 1, 0),
		})
		K.emitter(plume, {
			Texture = K.FIRE, Color = rgb(255, 180, 60), Color2 = rgb(255, 60, 20), Size = NumberSequence.new(5, 1),
			Transparency = NumberSequence.new(0.2, 1), Lifetime = NumberRange.new(0.8, 1.4), Speed = NumberRange.new(6, 12),
			Spread = Vector2.new(20, 20), Rate = 16, EmissionDirection = Enum.NormalId.Top,
		})
		-- лава стекает по склонам
		for _, a0 in ipairs({ -0.55, 0.05, 0.6 }) do
			local prev = nil
			for rho = 10, 50, 2.5 do
				local a = a0 + math.sin(rho / 7 + a0 * 5) * 0.06
				local cur = K.v(vx + math.sin(a) * rho, (50 - rho) / 2.6 * 4 - 1.6, vz - math.cos(a) * rho)
				if prev then
					K.box(CFrame.lookAt((prev + cur) / 2, cur), Vector3.new(2.8 + rho * 0.04, 1.4, (cur - prev).Magnitude + 0.6), rgb(255, 104, 28), M.Neon, { CastShadow = false })
				end
				prev = cur
			end
		end
	end
	K.blockRect(vx - 52, vz - 52, vx + 52, vz + 52)

	-- лавовая река (выходит из-под вулкана)
	local function lavaX(z) return 2 + 5 * math.sin(z / 22) end
	local lava = K.curve(-190, 84, 4, lavaX)
	K.river(lava, { r = 6, depth = 6, bed = M.CrackedLava, water = false })
	for i = 1, #lava - 1 do
		local a, b = lava[i], lava[i + 1]
		local pa, pb = K.v(a[1], -2.4, a[2]), K.v(b[1], -2.4, b[2])
		local seg = K.box(CFrame.lookAt((pa + pb) / 2, pb), Vector3.new(10.6, 0.6, (pb - pa).Magnitude + 1.2), rgb(255, 96, 24), M.Neon, { CastShadow = false })
		if i % 5 == 0 then K.light(seg, rgb(255, 110, 40), 20, 2.2) end
		if i % 6 == 0 then
			K.emitter(seg, {
				Color = rgb(255, 170, 60), Color2 = rgb(255, 60, 20), Size = NumberSequence.new(0.35, 0), Rate = 6,
				Lifetime = NumberRange.new(1.5, 3), Speed = NumberRange.new(2, 5), Spread = Vector2.new(25, 25), EmissionDirection = Enum.NormalId.Top,
			})
		end
	end

	local P = { { -85, -45 }, { -85, 15 }, { -25, 15 }, { -25, -40 }, { 30, -40 }, { 30, 40 }, { 75, 40 } }
	K.path(P, {
		color = rgb(138, 122, 114), mat = M.Cobblestone, discColor = rgb(128, 112, 104),
		edge = function(x, z, dir, k)
			if K.wet(x, z, 1.5) then return end
			if k % 5 == 2 then
				K.box(K.at(x, 0.06, z, K.rnd(0, 3)), Vector3.new(K.rnd(1.6, 2.4), 0.12, 0.35), rgb(255, 110, 30), M.Neon, { CastShadow = false })
			end
			K.box(K.at(x, 0.2, z, K.rnd(0, 3.14)), Vector3.new(1.5, 0.75, 1.2) * K.rnd(0.8, 1.2), (k % 2 == 0) and rgb(52, 46, 48) or rgb(76, 68, 68), M.Basalt, { CastShadow = false })
		end,
	})
	K.bridgeAt(P, 4, lavaX(-40), -40, 9, rgb(120, 112, 110), rgb(60, 54, 56), { mat = M.Slate, railMat = M.Basalt })

	-- ворота: лавовый портал в обсидиановой арке
	do
		local g = K.at(-85, 0, -53.5, K.yawOf(Vector3.new(0, 0, 1)))
		local obs = rgb(30, 24, 34)
		K.box(g * CFrame.new(0, 0.5, 0), Vector3.new(17, 1, 6), rgb(46, 40, 44), M.Basalt)
		for _, s in ipairs({ -1, 1 }) do
			K.box(g * CFrame.new(s * 6, 6.5, 0) * CFrame.Angles(0, 0, s * 0.06), Vector3.new(2.2, 12, 2.6), obs, M.Glass)
			K.box(g * CFrame.new(s * 3.2, 13.6, 0) * CFrame.Angles(0, 0, s * 0.75), Vector3.new(2.2, 7.4, 2.6), obs, M.Glass)
			K.box(g * CFrame.new(s * 8.6, 4, 0.8) * CFrame.Angles(0.2, 0, -s * 0.35), Vector3.new(1.4, 8, 1.4), obs, M.Glass)
			K.box(g * CFrame.new(s * 7.6, 2.4, -1.6) * CFrame.Angles(-0.3, 0, -s * 0.6), Vector3.new(1, 5, 1), obs, M.Glass)
			K.flame((g * CFrame.new(s * 6, 13.2, -1.6)).Position, 0.9)
		end
		local portal = K.box(g * CFrame.new(0, 7, 0), Vector3.new(10, 12, 0.4), rgb(255, 90, 30), M.Neon, { Transparency = 0.2, CastShadow = false })
		K.light(portal, rgb(255, 100, 40), 26, 3)
		K.emitter(portal, {
			Texture = K.FIRE, Color = rgb(255, 160, 60), Color2 = rgb(255, 50, 20), Size = NumberSequence.new(2.5, 0.2), Rate = 30,
			Lifetime = NumberRange.new(0.8, 1.4), Speed = NumberRange.new(1, 3), Transparency = NumberSequence.new(0.2, 1),
		})
		K.crystals(-96, -60, 1.3, obs, M.Glass)
		K.crystals(-74, -61, 1.2, obs, M.Glass)
		K.block(-85, -56, 10)
	end

	-- база: тёмная крепость
	K.castle(84, 40, math.pi / 2, {
		wall = rgb(84, 76, 78), mat = M.Basalt, trim = rgb(232, 150, 52), trimMat = M.Metal,
		roof = rgb(152, 38, 28), roofMat = M.Slate, flag = rgb(255, 122, 30), glow = rgb(255, 150, 60),
	})
	K.spawns(68, 14, K.face(68, 14, 0, 0))

	-- жаровни на поворотах
	K.corners(P, 9.5, function(x, z)
		K.box(K.at(x, 2, z), Vector3.new(1.2, 4, 1.2), rgb(54, 48, 50), M.Basalt)
		K.cyl(K.v(x, 4.4, z), 1, 3, rgb(70, 60, 58), M.Metal)
		K.flame(K.v(x, 5.2, z), 1.3)
	end)

	-- лавовые лужи, трещины, дымящие жерла
	K.scatter(18, { -150, -150, 150, 150 }, 4, function(x, z) K.tCyl(x, -1, z, 2.2, K.rnd(4, 9), M.CrackedLava) end)
	K.scatter(7, { -130, -130, 130, 130 }, 8, function(x, z)
		local r = K.rnd(3, 5)
		K.river({ { x, z } }, { r = r, depth = 3, bed = M.CrackedLava, water = false })
		local pool = K.cyl(K.v(x, -1.3, z), 0.4, r * 2 - 0.6, rgb(255, 100, 26), M.Neon, { CastShadow = false })
		K.light(pool, rgb(255, 110, 40), 16, 2)
		K.emitter(pool, {
			Color = rgb(255, 170, 60), Color2 = rgb(255, 60, 20), Size = NumberSequence.new(0.3, 0), Rate = 5,
			Lifetime = NumberRange.new(1.5, 3), Speed = NumberRange.new(2, 4), Spread = Vector2.new(25, 25), EmissionDirection = Enum.NormalId.Top,
		})
	end)
	K.scatter(8, { -140, -140, 140, 140 }, 4, function(x, z)
		local gy = K.groundY(x, z)
		for k = 1, 6 do
			local a = k / 6 * math.pi * 2
			K.box(K.at(x + math.cos(a) * 1.8, gy + 0.5, z + math.sin(a) * 1.8, a), Vector3.new(1.4, 1.2, 1.2), rgb(60, 54, 56), M.Basalt)
		end
		local v = K.anchor(K.v(x, gy + 0.8, z), Vector3.new(2, 0.5, 2))
		K.emitter(v, {
			Texture = K.SMOKE, Color = rgb(110, 100, 100), Color2 = rgb(60, 55, 55), LightEmission = 0, LightInfluence = 1,
			Size = NumberSequence.new(2, 9), Transparency = NumberSequence.new(0.35, 1), Lifetime = NumberRange.new(3, 5),
			Speed = NumberRange.new(3, 6), Spread = Vector2.new(10, 10), Rate = 6, EmissionDirection = Enum.NormalId.Top,
		})
		local glow = K.box(K.at(x, gy + 0.3, z), Vector3.new(1.6, 0.2, 1.6), rgb(255, 110, 30), M.Neon, { CastShadow = false })
		K.light(glow, rgb(255, 110, 40), 10, 1.5)
	end, 2)
	K.scatter(14, { -150, -150, 150, 150 }, 4, function(x, z) K.crystals(x, z, K.rnd(1, 1.6), rgb(32, 26, 36), M.Glass) end, 2)
	K.scatter(8, { -140, -140, 140, 140 }, 4, function(x, z)
		K.crystals(x, z, K.rnd(0.8, 1.2), rgb(190, 90, 255), M.Neon)
		K.light(K.anchor(K.v(x, 3, z), Vector3.one), rgb(190, 100, 255), 14, 1.5)
	end, 2)
	K.scatter(16, { -150, -150, 150, 150 }, 4, function(x, z) K.deadTree(x, z, K.rnd(0.8, 1.2), rgb(46, 38, 38)) end, 1.5)
	K.scatter(12, { -150, -150, 150, 150 }, 4, function(x, z) K.boulder(x, z, K.rnd(0.8, 1.4), M.Basalt) end, 2.5)
	K.scatter(10, { -130, -130, 130, 130 }, 2, function(x, z) K.rock(x, z, K.rnd(0.5, 0.9), rgb(70, 62, 62), M.Basalt) end)
	K.scatter(5, { -120, -120, 120, 120 }, 3, function(x, z)
		local gy = K.groundY(x, z)
		for k = 1, 3 do
			local p = K.v(x + K.rnd(-1.2, 1.2), gy + 0.7, z + K.rnd(-1.2, 1.2))
			K.ball(p, 1.5, rgb(236, 228, 210), M.SmoothPlastic)
			K.box(CFrame.new(p) * CFrame.new(0, -0.2, -0.6), Vector3.new(0.9, 0.5, 0.4), rgb(236, 228, 210), M.SmoothPlastic)
		end
	end)

	-- искры в воздухе
	K.ambient({
		Color = rgb(255, 160, 60), Color2 = rgb(255, 60, 20), Size = NumberSequence.new(0.3, 0), Rate = 40,
		Lifetime = NumberRange.new(4, 7), Speed = NumberRange.new(1, 3), EmissionDirection = Enum.NormalId.Top,
		Acceleration = Vector3.new(0.5, 1.5, 0), y = 1, h = 2, size = 240,
	})
	K.lighting({
		clock = 17.7, latitude = 20, brightness = 1.8, ambient = rgb(124, 66, 54), outdoor = rgb(154, 88, 72), shift = rgb(255, 150, 100),
		density = 0.36, offset = 0.05, atmColor = rgb(226, 132, 100), decay = rgb(130, 44, 32), glare = 0.4, haze = 1.8,
		bloom = 0.8, bloomThreshold = 1.0, tint = rgb(255, 228, 214), saturation = 0.15, contrast = 0.18, sunrays = 0.1,
		clouds = 0.65, cloudColor = rgb(92, 64, 62), cloudDensity = 0.7,
	})
	K.walls()
end

---------------------------------------------------------------- 5. HAUNTED GRAVEYARD — ночь, туман, могилы, тыквы

MAPS.Graveyard = function()
	K.reset(5505)
	K.colors({
		Grass = rgb(70, 96, 64), LeafyGrass = rgb(58, 84, 58), Mud = rgb(72, 60, 54), Ground = rgb(84, 74, 66),
		Rock = rgb(100, 96, 110), Slate = rgb(94, 92, 104), Cobblestone = rgb(106, 102, 114),
	})
	K.water(rgb(60, 80, 90), 0.2)
	K.ground(M.Grass)
	K.ring(168, 24, function(x, z)
		K.tBall(x, K.rnd(-10, -4), z, K.rnd(22, 30), K.rnd(0, 1) < 0.5 and M.Grass or M.Mud)
	end)
	K.ring(210, 34, function(x, z)
		local r = K.rnd(42, 58)
		local y = K.rnd(-24, -14)
		K.tBall(x, y, z, r, M.Rock)
		K.tBall(x, y + r * 0.15, z, r * 0.88, M.LeafyGrass)
	end)

	local P = { { -85, 35 }, { -40, 35 }, { -40, -30 }, { 10, -30 }, { 10, 30 }, { 55, 30 }, { 55, -45 }, { 85, -45 } }
	K.path(P, {
		color = rgb(114, 108, 122), mat = M.Cobblestone, discColor = rgb(108, 102, 116),
		edge = K.stoneEdge({ rgb(82, 80, 90), rgb(98, 94, 106), rgb(72, 70, 80) }),
	})
	K.scatter(16, { -150, -150, 150, 150 }, 3, function(x, z) K.tCyl(x, -1, z, 2.2, K.rnd(5, 10), M.Mud) end)

	local iron = rgb(40, 38, 48)
	-- ворота: склеп
	do
		local g = K.at(-97, 0, 35, K.yawOf(Vector3.new(1, 0, 0)))
		local stone, dark = rgb(128, 124, 140), rgb(96, 92, 108)
		K.box(g * CFrame.new(0, 0.3, -7.6), Vector3.new(13, 0.6, 2.4), dark, M.Slate)
		K.box(g * CFrame.new(0, 0.6, 0), Vector3.new(15, 1.2, 14), dark, M.Slate)
		K.box(g * CFrame.new(0, 5.9, 0.5), Vector3.new(13, 9.4, 11), stone, M.Slate)
		for _, sx in ipairs({ -5.4, -2.2, 2.2, 5.4 }) do
			K.cyl((g * CFrame.new(sx, 5.7, -6.2)).Position, 9, 1.5, rgb(150, 146, 160), M.Marble)
		end
		K.box(g * CFrame.new(0, 10.8, -0.6), Vector3.new(15, 1, 14.2), dark, M.Slate)
		for _, s in ipairs({ -1, 1 }) do
			K.wedge(g * CFrame.new(s * 3.75, 12.3, -0.6) * CFrame.Angles(0, -s * math.pi / 2, 0), Vector3.new(14.2, 2, 7.5), rgb(84, 80, 96), M.Slate)
		end
		K.box(g * CFrame.new(0, 14.6, -6.8), Vector3.new(0.6, 3, 0.6), stone, M.Marble)
		K.box(g * CFrame.new(0, 15.2, -6.8), Vector3.new(2, 0.6, 0.6), stone, M.Marble)
		-- тёмный вход, свет, туман
		K.box(g * CFrame.new(0, 4.4, -5), Vector3.new(4.4, 7.6, 0.3), rgb(14, 10, 22), M.SmoothPlastic)
		local glow = K.box(g * CFrame.new(0, 4.4, -4.8), Vector3.new(3.4, 6.6, 0.1), rgb(150, 90, 255), M.Neon, { Transparency = 0.75, CastShadow = false })
		K.light(glow, rgb(160, 100, 255), 20, 2.2)
		K.emitter(K.anchor((g * CFrame.new(0, 0.8, -7.5)).Position, Vector3.new(6, 0.5, 2)), {
			Texture = K.SMOKE, Color = rgb(170, 140, 230), LightEmission = 0.3, LightInfluence = 0.5,
			Size = NumberSequence.new(3, 8), Transparency = NumberSequence.new(0.6, 1), Lifetime = NumberRange.new(2, 4),
			Speed = NumberRange.new(1, 2), Spread = Vector2.new(60, 60), Rate = 8, EmissionDirection = Enum.NormalId.Top,
		})
		for _, s in ipairs({ -1, 1 }) do
			local t = g * CFrame.new(s * 7.6, 0, -9)
			K.box(t * CFrame.new(0, 1.6, 0), Vector3.new(1, 3.2, 1), dark, M.Slate)
			K.cyl((t * CFrame.new(0, 3.5, 0)).Position, 0.7, 1.8, iron, M.Metal)
			K.flame((t * CFrame.new(0, 4.1, 0)).Position, 1, rgb(120, 255, 150), rgb(30, 190, 90))
		end
		K.fence({ { -106, 23 }, { -106, 47 } }, iron, iron, { spikes = true, h = 3.4, mat = M.Metal })
		K.blockRect(-108, 25, -88, 45)
	end

	-- база: каменный замок
	K.castle(94, -45, math.pi / 2, {
		wall = rgb(152, 148, 164), mat = M.Cobblestone, trim = rgb(112, 108, 124), trimMat = M.Slate,
		roof = rgb(74, 52, 116), roofMat = M.Slate, flag = rgb(146, 94, 226), glow = rgb(255, 204, 124),
	})
	K.spawns(76, -18, K.face(76, -18, 0, 0))

	local function tomb(x, z, yaw, kind)
		local gy = K.groundY(x, z)
		local f = K.at(x, gy, z, yaw)
		local stone = rgb(156, 152, 166):Lerp(rgb(112, 108, 122), K.rnd(0, 1))
		local tilt = CFrame.Angles(K.rnd(-0.1, 0.1), 0, K.rnd(-0.1, 0.1))
		if kind == 1 then
			K.box(f * tilt * CFrame.new(0, 1.4, 0), Vector3.new(2.6, 2.8, 0.6), stone, M.Slate)
			K.hcyl(f * tilt * CFrame.new(0, 2.8, 0) * CFrame.Angles(0, math.pi / 2, 0), 0.6, 2.6, stone, M.Slate)
		elseif kind == 2 then
			K.box(f * tilt * CFrame.new(0, 1.8, 0), Vector3.new(0.6, 3.6, 0.6), stone, M.Slate)
			K.box(f * tilt * CFrame.new(0, 2.6, 0), Vector3.new(2.2, 0.6, 0.6), stone, M.Slate)
		else
			K.box(f * CFrame.new(0, 0.3, 0), Vector3.new(3, 0.6, 1.4), stone:Lerp(rgb(0, 0, 0), 0.2), M.Slate)
			K.box(f * tilt * CFrame.new(0, 2, 0), Vector3.new(2.4, 3, 0.5), stone, M.Slate)
			K.box(f * tilt * CFrame.new(0, 3.6, 0), Vector3.new(2.8, 0.4, 0.7), stone, M.Slate)
		end
		K.box(f * CFrame.new(0, 0.1, 2.2), Vector3.new(2.2, 0.3, 3.4), rgb(70, 58, 52), M.Mud, { CastShadow = false })
	end
	local function pumpkin(x, z, s, yaw)
		local gy = K.groundY(x, z)
		local f = K.at(x, gy + 1.1 * s, z, yaw)
		local orange, deep = rgb(255, 132, 30), rgb(214, 96, 22)
		K.ball(f.Position, 2.4 * s, orange, M.SmoothPlastic)
		K.ball((f * CFrame.new(0.75 * s, -0.1 * s, 0)).Position, 2 * s, deep, M.SmoothPlastic)
		K.ball((f * CFrame.new(-0.75 * s, -0.1 * s, 0)).Position, 2 * s, deep, M.SmoothPlastic)
		K.cyl((f * CFrame.new(0, 1.25 * s, 0)).Position, 0.7 * s, 0.35 * s, rgb(70, 110, 40), M.Wood)
		local face = rgb(255, 222, 92)
		for _, sx in ipairs({ -1, 1 }) do
			K.box(f * CFrame.new(sx * 0.45 * s, 0.25 * s, -1.05 * s) * CFrame.Angles(0, 0, math.rad(45)), Vector3.new(0.4, 0.4, 0.2) * s, face, M.Neon, { CastShadow = false })
		end
		K.box(f * CFrame.new(0, -0.35 * s, -1.05 * s), Vector3.new(1.1, 0.25, 0.2) * s, face, M.Neon, { CastShadow = false })
		K.light(K.anchor(f.Position + Vector3.new(0, 0.5, 0), Vector3.one * 0.3), rgb(255, 150, 50), 9 * s, 1.4)
	end
	local function plot(x1, z1, x2, z2, yaw)
		for x = x1 + 3, x2 - 3, 5 do
			for z = z1 + 4, z2 - 4, 7 do
				tomb(x + K.rnd(-0.6, 0.6), z + K.rnd(-0.6, 0.6), yaw + K.rnd(-0.1, 0.1), K.int(1, 3))
			end
		end
		K.fence({ { x1, z1 }, { x2, z1 }, { x2, z2 }, { x1, z2 }, { x1, z1 } }, iron, iron, { spikes = true, h = 3, mat = M.Metal, step = 3, rails = { 0.6, 2.4 } })
		K.rect(x1 - 1, z1 - 1, x2 + 1, z2 + 1)
	end
	plot(-30, 46, 2, 70, 0)
	plot(-34, -74, -2, -46, math.pi)
	plot(72, 0, 104, 28, math.pi / 2)
	plot(-118, -40, -94, -14, -math.pi / 2)

	-- одинокие могилы и тыквы на поле
	K.scatter(34, { -130, -130, 130, 130 }, 3, function(x, z) tomb(x, z, K.face(x, z, 0, 0) + K.rnd(-0.4, 0.4), K.int(1, 3)) end, 1.6)
	K.scatter(22, { -130, -130, 130, 130 }, 3, function(x, z) pumpkin(x, z, K.rnd(0.8, 1.5), K.face(x, z, 0, 0)) end, 1.5)
	-- кусты, свечи, сломанные заборчики
	K.scatter(30, { -150, -150, 150, 150 }, 2.5, function(x, z) K.bush(x, z, K.rnd(0.6, 1), { rgb(52, 66, 58), rgb(64, 54, 74), rgb(44, 58, 50) }) end)
	K.scatter(16, { -120, -120, 120, 120 }, 2, function(x, z)
		local gy = K.groundY(x, z)
		for k = 1, K.int(2, 3) do
			local cx, cz = x + K.rnd(-0.8, 0.8), z + K.rnd(-0.8, 0.8)
			local h = K.rnd(0.6, 1.4)
			K.cyl(K.v(cx, gy + h / 2, cz), h, 0.4, rgb(240, 232, 214), M.SmoothPlastic, { CastShadow = false })
			K.ball(K.v(cx, gy + h + 0.2, cz), 0.3, rgb(255, 210, 120), M.Neon, { CastShadow = false })
		end
		K.light(K.anchor(K.v(x, gy + 1.5, z), Vector3.one * 0.3), rgb(255, 190, 110), 8, 1)
	end)
	K.scatter(8, { -140, -140, 140, 140 }, 3, function(x, z)
		local a = K.rnd(0, 3)
		local x2, z2 = x + math.cos(a) * 8, z + math.sin(a) * 8
		if K.free(x2, z2, 1) then K.fence({ { x, z }, { x2, z2 } }, iron, iron, { spikes = true, h = 2.6, mat = M.Metal, step = 3, rails = { 0.5, 2 } }) end
	end)
	-- гробы
	for _, c in ipairs({ { -76, 52, 0.4 }, { -84, 14, -0.3 }, { 34, 54, 1.2 } }) do
		local f = K.at(c[1], 0.5, c[2], c[3])
		K.box(f, Vector3.new(2.4, 1, 6), rgb(84, 56, 40), M.Wood)
		K.box(f * CFrame.new(0.3, 0.75, 0.4) * CFrame.Angles(0, 0.25, 0.1), Vector3.new(2.5, 0.3, 6.1), rgb(100, 68, 48), M.Wood)
		K.box(f * CFrame.new(0.3, 0.92, 0.4) * CFrame.Angles(0, 0.25, 0.1), Vector3.new(0.4, 0.06, 2.6), rgb(200, 180, 120), M.Foil)
		K.block(c[1], c[2], 3.5)
	end
	-- мёртвые деревья, фонари, огоньки-призраки
	K.scatter(46, { -155, -155, 155, 155 }, 5, function(x, z) K.deadTree(x, z, K.rnd(0.9, 1.6), rgb(58, 48, 50)) end, 1.5)
	K.scatter(8, { -140, -140, 140, 140 }, 4, function(x, z) K.boulder(x, z, K.rnd(0.8, 1.2), M.Rock) end, 2)
	K.corners(P, 9.5, function(x, z) K.lamp(x, z, rgb(196, 150, 255), rgb(34, 32, 42)) end)
	K.scatter(12, { -120, -120, 120, 120 }, 2, function(x, z)
		K.wisp(K.v(x, K.groundY(x, z) + K.rnd(3, 6), z), K.rnd(0, 1) < 0.5 and rgb(120, 255, 200) or rgb(170, 150, 255), K.rnd(0.9, 1.3))
	end)
	-- большая луна над склепом
	local moon = K.ball(K.v(-430, 140, 40), 90, rgb(255, 248, 222), M.Neon, { CastShadow = false })
	moon.Transparency = 0.1

	-- туман у земли
	K.ambient({
		Texture = K.SMOKE, Color = rgb(170, 160, 210), LightEmission = 0.15, LightInfluence = 0.6,
		Size = NumberSequence.new(12, 20), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.8), NumberSequenceKeypoint.new(1, 1) }),
		Rate = 14, Lifetime = NumberRange.new(10, 14), Speed = NumberRange.new(0.5, 1.5), Spread = Vector2.new(180, 10),
		y = 2, h = 2, size = 250,
	})
	K.lighting({
		clock = 0, brightness = 2, ambient = rgb(86, 76, 120), outdoor = rgb(130, 120, 176), shift = rgb(180, 170, 255), exposure = 0.4,
		density = 0.45, offset = 0.25, atmColor = rgb(120, 104, 170), decay = rgb(70, 52, 110), glare = 0, haze = 2.2,
		bloom = 0.9, bloomThreshold = 0.95, tint = rgb(225, 214, 255), saturation = -0.05, contrast = 0.15,
		stars = 3000, clouds = 0.35, cloudColor = rgb(80, 70, 102),
	})
	K.walls()
end

---------------------------------------------------------------- 6. PIRATE COVE — остров, пальмы, корабль, сокровища

MAPS.Pirate = function()
	K.reset(6606)
	K.colors({
		Sand = rgb(242, 224, 170), Grass = rgb(112, 192, 82), LeafyGrass = rgb(92, 172, 70), Rock = rgb(142, 132, 122),
		Ground = rgb(172, 142, 100), Mud = rgb(120, 100, 80), Slate = rgb(110, 110, 115),
	})
	K.water(rgb(38, 178, 192), 0.35)
	-- море и остров
	K.tBlock(0, -15, 0, 1400, 8, 1400, M.Sand)   -- дно на -11: пловца AntiCheat не примет за «летуна»
	K.tBlock(0, -6, 0, 1400, 10, 1400, M.Water)
	local isl = { { -50, 5, 52 }, { -5, 5, 52 }, { 40, 5, 52 }, { 75, 8, 50 }, { 90, 44, 30 } }
	for _, c in ipairs(isl) do K.tCyl(c[1], -14, c[2], 8, c[3] + 14, M.Sand) end
	for _, c in ipairs(isl) do K.tCyl(c[1], -11, c[2], 14, c[3] + 7, M.Sand) end
	for _, c in ipairs(isl) do K.tCyl(c[1], -9, c[2], 18, c[3], M.Sand) end
	for _, c in ipairs(isl) do K.tCyl(c[1], -1.5, c[2], 3, c[3] - 14, M.Grass) end
	-- маленькие острова
	local islets = { { -150, 96, 13 }, { 146, -108, 10 }, { 40, 146, 12 }, { -124, -132, 9 } }
	for _, c in ipairs(islets) do
		K.tCyl(c[1], -11, c[2], 14, c[3] + 6, M.Sand)
		K.tCyl(c[1], -9, c[2], 18, c[3], M.Sand)
	end
	-- скалы в воде
	for _, r in ipairs({ { -92, 54, 6 }, { -24, -64, 7 }, { 104, -40, 6 }, { 126, 70, 8 }, { -60, 64, 5 } }) do
		K.tBall(r[1], -3, r[2], r[3], M.Rock)
		K.tBall(r[1] + r[3] * 0.6, -4, r[2] + 1, r[3] * 0.7, M.Rock)
	end
	local function land(x, z) return K.groundY(x, z) > -0.5 end

	local P = { { -100, -10 }, { -55, -10 }, { -55, 40 }, { 0, 40 }, { 0, -30 }, { 55, -30 }, { 55, 35 }, { 85, 35 } }
	K.path(P, {
		color = rgb(182, 134, 86), mat = M.WoodPlanks, discColor = rgb(170, 124, 78),
		edge = function(x, z, dir, k)
			if k % 2 == 0 then
				K.box(K.at(x, 0.8, z), Vector3.new(0.6, 1.8, 0.6), rgb(120, 84, 52), M.Wood)
				K.cyl(K.v(x, 1.75, z), 0.2, 0.75, rgb(214, 190, 140), M.Fabric, { CastShadow = false })
			end
		end,
	})

	-- ворота: пиратский корабль у причала
	do
		-- причал (по нему можно ходить)
		K.part({ Name = "Dock", CFrame = K.at(-106, -0.2, -10), Size = Vector3.new(14, 1, 12), Color = rgb(150, 108, 70), Material = M.WoodPlanks, Solid = true })
		for i = 0, 5 do
			K.box(K.at(-106, 0.36, -15 + i * 2), Vector3.new(14, 0.12, 1.8), rgb(176, 128, 82):Lerp(rgb(130, 92, 58), (i % 2) * 0.4), M.WoodPlanks, { CastShadow = false })
		end
		for _, p in ipairs({ { -112.6, -15.6 }, { -112.6, -4.4 }, { -99.4, -15.6 }, { -99.4, -4.4 }, { -106, -15.6 }, { -106, -4.4 } }) do
			K.cyl(K.v(p[1], -2.5, p[2]), 7, 1, rgb(110, 76, 48), M.Wood)
		end
		local ship = K.group("Ship", { Float = 0.35, Speed = 0.7 })
		K.inside(ship, function()
			local s = K.at(-127, -1, -10)
			local hullC, deckC, trimC = rgb(112, 72, 42), rgb(178, 130, 84), rgb(70, 46, 30)
			K.box(s * CFrame.new(0, 1.5, 0), Vector3.new(12, 7, 30), hullC, M.WoodPlanks)
			K.box(s * CFrame.new(0, -2.4, 0), Vector3.new(8, 2, 28), rgb(84, 54, 32), M.WoodPlanks)
			K.wedge(s * CFrame.new(3, 1.5, -19) * CFrame.Angles(0, 0, -math.pi / 2), Vector3.new(7, 6, 8), hullC, M.WoodPlanks)
			K.wedge(s * CFrame.new(-3, 1.5, -19) * CFrame.Angles(0, 0, math.pi / 2), Vector3.new(7, 6, 8), hullC, M.WoodPlanks)
			K.box(s * CFrame.new(0, 5.2, 0), Vector3.new(11.4, 0.4, 30), deckC, M.WoodPlanks)
			K.box(s * CFrame.new(0, 4.2, 0), Vector3.new(12.2, 0.5, 30.2), rgb(226, 192, 92), M.SmoothPlastic)
			for _, sx in ipairs({ -1, 1 }) do
				K.box(s * CFrame.new(sx * 5.8, 6.1, 0), Vector3.new(0.4, 1.4, 30), trimC, M.Wood)
				for k = -1, 1 do
					K.box(s * CFrame.new(sx * 6.05, 2.4, k * 8), Vector3.new(0.2, 1.6, 1.8), rgb(30, 22, 18), M.SmoothPlastic)
					K.hcyl(s * CFrame.new(sx * 6.6, 2.4, k * 8), 1.6, 0.9, rgb(40, 40, 44), M.Metal)
				end
			end
			-- корма
			K.box(s * CFrame.new(0, 7.4, 11.5), Vector3.new(12, 4, 7), hullC, M.WoodPlanks)
			K.box(s * CFrame.new(0, 9.6, 11.5), Vector3.new(12.4, 0.4, 7.4), deckC, M.WoodPlanks)
			for _, sx in ipairs({ -3.5, 0, 3.5 }) do
				K.box(s * CFrame.new(sx, 7.6, 15.05), Vector3.new(1.6, 1.6, 0.2), rgb(255, 210, 120), M.Neon, { CastShadow = false })
			end
			local lantern = K.box(s * CFrame.new(0, 11, 14.6), Vector3.new(0.8, 1.2, 0.8), rgb(255, 200, 110), M.Neon)
			K.light(lantern, rgb(255, 190, 110), 16, 1.5)
			-- мачты и паруса
			for _, m in ipairs({ { -6, 24 }, { 5, 20 } }) do
				local z, h = m[1], m[2]
				K.cyl((s * CFrame.new(0, 5.4 + h / 2, z)).Position, h, 1, rgb(96, 64, 40), M.Wood)
				for k, y in ipairs({ 0.42, 0.78 }) do
					local yy = 5.4 + h * y
					local w = (k == 1) and 13 or 10
					K.hcyl(s * CFrame.new(0, yy + 3.7, z), w, 0.5, rgb(96, 64, 40), M.Wood)
					K.box(s * CFrame.new(0, yy, z - 0.6), Vector3.new(w - 1.5, 7, 0.25), rgb(246, 240, 226), M.Fabric)
				end
			end
			K.cyl((s * CFrame.new(0, 28.2, -6)).Position, 1, 3, rgb(96, 64, 40), M.Wood)
			K.box(s * CFrame.new(1.7, 31, -6), Vector3.new(3.2, 2, 0.15), rgb(22, 22, 26), M.Fabric)
			K.ball((s * CFrame.new(1.7, 31.2, -6.12)).Position, 0.9, WHITE, M.SmoothPlastic)
			K.box(s * CFrame.new(1.7, 30.4, -6.12) * CFrame.Angles(0, 0, 0.6), Vector3.new(1.6, 0.25, 0.1), WHITE, M.SmoothPlastic)
			K.box(s * CFrame.new(1.7, 30.4, -6.12) * CFrame.Angles(0, 0, -0.6), Vector3.new(1.6, 0.25, 0.1), WHITE, M.SmoothPlastic)
			local b0, b1 = (s * CFrame.new(0, 5.6, -21)).Position, (s * CFrame.new(0, 9.2, -30)).Position
			K.hcyl(CFrame.lookAt((b0 + b1) / 2, b1) * CFrame.Angles(0, math.pi / 2, 0), (b1 - b0).Magnitude, 0.6, rgb(96, 64, 40), M.Wood)
		end)
		K.rest(ship)
		-- трап с корабля на причал
		local a, b = K.v(-121, 4.6, -10), K.v(-112.5, 0.5, -10)
		K.box(CFrame.lookAt((a + b) / 2, b), Vector3.new(3, 0.3, (b - a).Magnitude), rgb(150, 106, 66), M.WoodPlanks)
		K.barrel(-110, -14.5, 0.9)
		K.barrel(-111.5, -12.5, 0.8)
		K.crate(-102, -14.8, 0.9)
		K.blockRect(-140, -32, -99, 12)
	end

	-- база: форт и маяк
	K.castle(94, 35, math.pi / 2, {
		wall = rgb(222, 198, 150), mat = M.Sandstone, trim = rgb(124, 84, 52), trimMat = M.Wood,
		roof = rgb(196, 62, 50), roofMat = M.ClayRoofTiles, flag = rgb(60, 124, 222), glow = rgb(255, 214, 140),
	})
	do
		local x, z = 104, 64
		local gy = K.groundY(x, z)
		K.cyl(K.v(x, gy + 1, z), 2, 10, rgb(150, 140, 130), M.Cobblestone)
		for i = 0, 7 do
			K.cyl(K.v(x, gy + 3.7 + i * 3.4, z), 3.42, 7.4 - i * 0.3, (i % 2 == 0) and rgb(242, 242, 242) or rgb(222, 52, 52), M.SmoothPlastic)
		end
		local top = gy + 2 + 8 * 3.4
		K.cyl(K.v(x, top + 0.3, z), 0.6, 8, rgb(60, 60, 66), M.Metal)
		K.cyl(K.v(x, top + 2.2, z), 3.4, 4.6, rgb(200, 240, 255), M.Glass, { Transparency = 0.4 })
		local lamp = K.ball(K.v(x, top + 2.2, z), 2.4, rgb(255, 240, 160), M.Neon)
		K.light(lamp, rgb(255, 235, 170), 40, 2)
		K.cone(K.v(x, top + 3.9, z), 2.6, 5.4, rgb(202, 46, 46), M.SmoothPlastic, 5)
		local beam = K.group("LighthouseBeam", { Spin = 40 })
		K.inside(beam, function()
			for _, s in ipairs({ -1, 1 }) do
				K.box(K.at(x + s * 9, top + 2.2, z), Vector3.new(14, 1.2, 1.2), rgb(255, 245, 190), M.Neon, { Transparency = 0.65, CastShadow = false })
			end
		end)
		K.rest(beam, K.at(x, top + 2.2, z))
		K.block(x, z, 6)
	end
	K.spawns(72, 8, K.face(72, 8, 0, 0))

	-- сундук с сокровищами
	local function chest(x, z, yaw, s)
		local gy = K.groundY(x, z)
		local f = K.at(x, gy, z, yaw)
		local wood, gold = rgb(130, 82, 46), rgb(255, 206, 60)
		K.box(f * CFrame.new(0, 1 * s, 0), Vector3.new(4, 2, 2.6) * s, wood, M.WoodPlanks)
		K.box(f * CFrame.new(0, 1 * s, 0), Vector3.new(4.1, 0.3, 2.7) * s, gold, M.Foil)
		K.box(f * CFrame.new(0, 2.1 * s, 1.5 * s) * CFrame.Angles(math.rad(-50), 0, 0) * CFrame.new(0, 0, -1.3 * s), Vector3.new(4, 0.5, 2.6) * s, wood, M.WoodPlanks)
		for i = 1, 7 do
			K.ball((f * CFrame.new(K.rnd(-1.5, 1.5) * s, 2.1 * s, K.rnd(-0.9, 0.9) * s)).Position, K.rnd(0.6, 0.9) * s, gold, M.Foil, { CastShadow = false })
		end
		local gem = K.gem((f * CFrame.new(0.6 * s, 2.5 * s, 0)).Position, 0.7 * s, rgb(255, 60, 120))
		K.light(gem, rgb(255, 210, 90), 10, 1.5)
		for i = 1, 6 do
			K.cyl((f * CFrame.new(K.rnd(-3, 3) * s, 0.08, K.rnd(-2.5, 2.5) * s)).Position, 0.15, 0.8 * s, gold, M.Foil, { CastShadow = false })
		end
		K.block(x, z, 3.2 * s)
	end
	chest(-28, 14, 0.4, 1)
	for _, a in ipairs({ math.rad(45), math.rad(-45) }) do
		K.box(K.at(-28, 0.05, 20, a), Vector3.new(5, 0.1, 1), rgb(210, 40, 40), M.SmoothPlastic, { CastShadow = false })
	end
	chest(76, 60, 2.2, 1.1)
	chest(-150, 96, 0.8, 0.9)

	-- пушки у форта
	local function cannon(x, z, yaw)
		local gy = K.groundY(x, z)
		local f = K.at(x, gy, z, yaw)
		K.box(f * CFrame.new(0, 0.9, 0), Vector3.new(2.2, 1, 3.6), rgb(110, 74, 46), M.Wood)
		for _, w in ipairs({ { -1.2, -1 }, { 1.2, -1 }, { -1.2, 1.2 }, { 1.2, 1.2 } }) do
			K.hcyl(f * CFrame.new(w[1], 0.8, w[2]), 0.4, 1.6, rgb(80, 54, 34), M.Wood)
		end
		K.hcyl(f * CFrame.new(0, 1.9, -0.6) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.Angles(0, 0, math.rad(-12)), 4.6, 1.2, rgb(40, 40, 46), M.Metal)
		for i = 0, 2 do
			K.ball((f * CFrame.new(1.8 + i * 0.5, 0.45, 1.6 - (i % 2) * 0.5)).Position, 0.9, rgb(30, 30, 34), M.Metal)
		end
		K.block(x, z, 2.5)
	end
	cannon(106, 8, K.face(106, 8, 160, -20))
	cannon(114, 22, K.face(114, 22, 170, 10))
	cannon(82, 66, K.face(82, 66, 60, 140))

	-- хижины, лодки, замок из песка, обломки корабля
	local function hut(x, z)
		local gy = K.groundY(x, z)
		for _, p in ipairs({ { -3, -3 }, { 3, -3 }, { -3, 3 }, { 3, 3 } }) do
			K.cyl(K.v(x + p[1], gy + 3, z + p[2]), 6, 0.6, rgb(196, 168, 100), M.Wood)
		end
		K.box(K.at(x, gy + 0.4, z), Vector3.new(7.4, 0.5, 7.4), rgb(160, 120, 76), M.WoodPlanks)
		K.cone(K.v(x, gy + 5.6, z), 5, 11, rgb(214, 182, 96), M.Grass, 6)
		K.block(x, z, 5.5)
	end
	hut(-72, 46)
	hut(28, 50)
	local function rowboat(x, z, yaw)
		local g = K.group("Boat", { Float = 0.25, Speed = 1.1, Phase = K.rnd(0, 6) })
		K.inside(g, function()
			local f = K.at(x, -0.9, z, yaw)
			K.box(f * CFrame.new(0, 0.3, 0), Vector3.new(3.2, 1.2, 6), rgb(150, 100, 60), M.WoodPlanks)
			K.wedge(f * CFrame.new(0.8, 0.3, -4) * CFrame.Angles(0, 0, -math.pi / 2), Vector3.new(1.2, 1.6, 2), rgb(150, 100, 60), M.WoodPlanks)
			K.wedge(f * CFrame.new(-0.8, 0.3, -4) * CFrame.Angles(0, 0, math.pi / 2), Vector3.new(1.2, 1.6, 2), rgb(150, 100, 60), M.WoodPlanks)
			K.box(f * CFrame.new(0, 0.95, 0), Vector3.new(2.6, 0.1, 5.4), rgb(110, 74, 44), M.Wood)
			K.box(f * CFrame.new(0, 1.1, 0.5), Vector3.new(3, 0.25, 0.8), rgb(176, 128, 82), M.Wood)
			for _, sx in ipairs({ -1, 1 }) do
				K.box(f * CFrame.new(sx * 2.4, 0.9, 0.5) * CFrame.Angles(0, sx * 0.5, sx * 0.25), Vector3.new(3.4, 0.2, 0.3), rgb(176, 128, 82), M.Wood)
			end
		end)
		K.rest(g)
	end
	rowboat(-38, 58, 0.6)
	rowboat(20, -52, 2)
	do -- замок из песка
		local x, z = -72, -38
		local sand = rgb(232, 210, 150)
		K.box(K.at(x, 0.8, z), Vector3.new(4, 1.6, 4), sand, M.Sand)
		for _, p in ipairs({ { -2, -2 }, { 2, -2 }, { -2, 2 }, { 2, 2 } }) do
			K.cyl(K.v(x + p[1], 1.4, z + p[2]), 2.8, 1.6, sand, M.Sand)
			K.cone(K.v(x + p[1], 2.8, z + p[2]), 1.2, 1.7, sand, M.Sand, 3)
		end
		K.cyl(K.v(x, 2.6, z), 2, 2, sand, M.Sand)
		K.box(K.at(x + 0.3, 4.4, z), Vector3.new(0.1, 1.6, 0.1), rgb(110, 80, 50), M.Wood)
		K.box(K.at(x + 0.8, 4.8, z), Vector3.new(0.9, 0.6, 0.05), rgb(220, 50, 50), M.Fabric)
		K.block(x, z, 3.5)
	end
	do -- обломки корабля в море
		local f = K.at(-40, -3, -104, 0.7) * CFrame.Angles(0.25, 0, 0.35)
		K.box(f * CFrame.new(0, 1.5, 0), Vector3.new(10, 6, 20), rgb(90, 62, 40), M.WoodPlanks)
		K.box(f * CFrame.new(0, 4.7, 0), Vector3.new(9.4, 0.4, 18), rgb(130, 94, 60), M.WoodPlanks)
		K.cyl((f * CFrame.new(0, 10, -2)).Position, 12, 0.9, rgb(80, 56, 36), M.Wood)
		K.box(f * CFrame.new(0, 12, -2.6) * CFrame.Angles(0, 0, 0.2), Vector3.new(6, 5, 0.2), rgb(214, 206, 186), M.Fabric)
	end

	-- пальмы, бочки, ящики, факелы
	K.scatter(30, { -100, -60, 112, 76, test = land }, 4, function(x, z) K.palm(x, z, K.rnd(0.9, 1.3)) end, 2)
	for _, c in ipairs(islets) do
		K.palm(c[1] + 3, c[2] - 2, 1.1)
		K.palm(c[1] - 4, c[2] + 3, 0.9)
	end
	K.scatter(14, { -100, -60, 112, 76, test = land }, 3, function(x, z)
		if K.rnd(0, 1) < 0.5 then K.barrel(x, z, K.rnd(0.8, 1)) else K.crate(x, z, K.rnd(0.8, 1.1)) end
	end, 1.5)
	K.scatter(14, { -100, -60, 112, 76, test = land }, 2, function(x, z)
		K.bush(x, z, K.rnd(0.6, 0.9), { rgb(70, 160, 70), rgb(90, 180, 80), rgb(60, 140, 60) })
	end)
	K.scatter(16, { -100, -60, 112, 76, test = land }, 2, function(x, z)
		K.ball(K.v(x, 0.15, z), K.rnd(0.5, 0.8), K.pick({ rgb(255, 200, 210), rgb(250, 240, 220), rgb(255, 170, 120) }), M.SmoothPlastic, { CastShadow = false })
	end)
	K.corners(P, 9.5, function(x, z)
		if not land(x, z) then return end
		K.cyl(K.v(x, 2.5, z), 5, 0.7, rgb(196, 168, 100), M.Wood)
		K.cyl(K.v(x, 5.2, z), 0.8, 1.3, rgb(120, 84, 52), M.Wood)
		K.flame(K.v(x, 5.9, z), 0.9)
	end)

	K.lighting({
		clock = 13.2, latitude = 15, brightness = 3, ambient = rgb(122, 126, 136), outdoor = rgb(166, 170, 180), shift = rgb(255, 248, 236),
		density = 0.24, offset = 0.1, atmColor = rgb(200, 230, 255), decay = rgb(140, 196, 236), glare = 0.3, haze = 0.8,
		bloom = 0.35, tint = rgb(248, 255, 255), saturation = 0.28, contrast = 0.08, sunrays = 0.12, clouds = 0.42,
	})
	K.walls()
end

---------------------------------------------------------------- 7. CANDY LAND — сладости, торты, шоколадная река

MAPS.Candy = function()
	K.reset(7707)
	K.colors({
		Grass = rgb(250, 168, 204), LeafyGrass = rgb(150, 226, 186), Sand = rgb(255, 232, 180), Salt = rgb(252, 250, 255),
		Mud = rgb(112, 64, 38), Ground = rgb(162, 102, 62), Rock = rgb(214, 182, 255), Limestone = rgb(255, 222, 152), Snow = rgb(255, 255, 255),
	})
	K.water(rgb(112, 62, 34), 0.05)
	K.ground(M.Grass)
	K.ring(168, 24, function(x, z)
		local r = K.rnd(22, 30)
		local y = K.rnd(-10, -4)
		K.tBall(x, y, z, r, K.pick({ M.Grass, M.LeafyGrass, M.Rock }))
		K.tBall(x, y + r * 0.5, z, r * 0.6, M.Snow)
	end)
	K.ring(212, 34, function(x, z)
		local r = K.rnd(40, 56)
		local y = K.rnd(-24, -14)
		K.tBall(x, y, z, r, K.pick({ M.Rock, M.LeafyGrass, M.Limestone }))
		K.tBall(x, y + r * 0.45, z, r * 0.62, M.Snow)
	end)
	-- мятные полянки
	for _ = 1, 14 do
		local x, z = K.rnd(-150, 150), K.rnd(-150, 150)
		K.tCyl(x, -1, z, 2.2, K.rnd(8, 16), M.LeafyGrass)
	end

	-- шоколадная река
	local function chocZ(x) return 2 + 4 * math.sin(x / 20 + 0.5) end
	K.river(K.curve(-190, 190, 4, chocZ, true), { r = 6, depth = 5, bed = M.Mud, bank = M.Sand })

	local P = { { -85, 45 }, { -45, 45 }, { -45, -20 }, { 5, -20 }, { 5, 40 }, { 45, 40 }, { 45, -45 }, { 80, -45 } }
	K.path(P, {
		color = rgb(255, 246, 238), mat = M.SmoothPlastic, discColor = rgb(255, 238, 230),
		edge = function(x, z, dir, k)
			if K.wet(x, z, 1.5) then return end
			local cols = { rgb(255, 84, 124), rgb(120, 200, 255), rgb(255, 220, 80), rgb(150, 230, 140), rgb(200, 140, 255) }
			K.ball(K.v(x, 0.45, z), 1.5, cols[(k % #cols) + 1], M.SmoothPlastic, { CastShadow = false })
		end,
	})
	-- красные полоски на дороге, как на леденце
	for i = 1, #P - 1 do
		local a, b = P[i], P[i + 1]
		local pa, pb = Vector3.new(a[1], 0, a[2]), Vector3.new(b[1], 0, b[2])
		local len = (pb - pa).Magnitude
		local dir = (pb - pa).Unit
		for d = 3, len - 3, 4 do
			local c = pa + dir * d
			if not K.wet(c.X, c.Z, 2) then
				K.box(CFrame.lookAt(K.v(c.X, 0.31, c.Z), K.v(c.X, 0.31, c.Z) + dir) * CFrame.Angles(0, math.rad(20), 0), Vector3.new(K.pathW - 0.6, 0.06, 1.3), rgb(240, 64, 96), M.SmoothPlastic, { CastShadow = false, Name = "Stripe" })
			end
		end
	end
	-- печенье-мосты
	for _, i in ipairs({ 2, 4, 6 }) do
		local x = P[i][1]
		K.bridgeAt(P, i, x, chocZ(x), 9, rgb(214, 160, 92), rgb(255, 120, 170), { mat = M.SmoothPlastic, railMat = M.SmoothPlastic })
	end

	local SPRINKLES = { rgb(255, 80, 120), rgb(120, 200, 255), rgb(255, 230, 90), rgb(140, 230, 140), rgb(200, 140, 255), WHITE }
	local function cane(pos, h, yaw, s)
		s = s or 1
		local n = math.max(2, math.floor(h / (0.9 * s)))
		for i = 0, n - 1 do
			K.cyl(pos + Vector3.new(0, (i + 0.5) * 0.9 * s, 0), 0.92 * s, 1 * s, (i % 2 == 0) and rgb(240, 40, 60) or WHITE, M.SmoothPlastic)
		end
		local f = CFrame.new(pos + Vector3.new(0, n * 0.9 * s, 0)) * CFrame.Angles(0, yaw or 0, 0)
		for k = 0, 6 do
			local a = k / 6 * math.pi
			K.ball((f * CFrame.new(-(1 - math.cos(a)) * 1.2 * s, math.sin(a) * 1.2 * s, 0)).Position, 1.05 * s, (k % 2 == 0) and WHITE or rgb(240, 40, 60), M.SmoothPlastic)
		end
		K.cyl((f * CFrame.new(-2.4 * s, -0.5 * s, 0)).Position, 1 * s, 1 * s, rgb(240, 40, 60), M.SmoothPlastic)
	end
	local LOLLY = { { rgb(255, 80, 140), WHITE }, { rgb(110, 196, 255), WHITE }, { rgb(255, 226, 90), rgb(255, 120, 160) }, { rgb(140, 230, 170), WHITE }, { rgb(190, 130, 255), rgb(255, 210, 240) } }
	local function lollipop(x, z, s, yaw)
		local gy = K.groundY(x, z)
		local h = 7 * s
		K.cyl(K.v(x, gy + h / 2, z), h, 0.5 * s, WHITE, M.SmoothPlastic)
		local f = K.at(x, gy + h + 2.2 * s, z, yaw)
		local c = K.pick(LOLLY)
		for k = 0, 4 do
			K.hcyl(f * CFrame.Angles(0, math.pi / 2, 0), 0.6 * s + k * 0.06, (5 - k) * 0.9 * s, c[(k % 2) + 1], M.SmoothPlastic)
		end
	end
	local function cupcake(x, z, s)
		local gy = K.groundY(x, z)
		K.cyl(K.v(x, gy + 1.5 * s, z), 3 * s, 5 * s, K.pick({ rgb(120, 200, 255), rgb(255, 150, 190), rgb(255, 220, 110) }), M.SmoothPlastic)
		for k = 0, 9 do
			local a = k / 10 * math.pi * 2
			K.box(K.at(x + math.cos(a) * 2.45 * s, gy + 1.5 * s, z + math.sin(a) * 2.45 * s, -a), Vector3.new(0.3, 3, 0.3) * s, WHITE, M.SmoothPlastic)
		end
		local cream = K.pick({ rgb(255, 240, 248), rgb(255, 180, 210), rgb(176, 116, 78), rgb(200, 240, 220) })
		K.cyl(K.v(x, gy + 3.3 * s, z), 0.8 * s, 5.4 * s, cream, M.SmoothPlastic)
		K.ball(K.v(x, gy + 4.2 * s, z), 4.4 * s, cream, M.SmoothPlastic)
		K.ball(K.v(x, gy + 5.8 * s, z), 2.6 * s, cream, M.SmoothPlastic)
		K.ball(K.v(x, gy + 7.4 * s, z), 1.3 * s, rgb(230, 30, 50), M.SmoothPlastic)
		for _ = 1, 10 do
			local a, r = K.rnd(0, 6.28), K.rnd(0.4, 1.9) * s
			local y = gy + 4.2 * s + math.sqrt(math.max(0, (2.2 * s) ^ 2 - r * r))
			K.box(K.at(x + math.cos(a) * r, y, z + math.sin(a) * r, K.rnd(0, 3)), Vector3.new(0.6, 0.18, 0.18) * s, K.pick(SPRINKLES), M.SmoothPlastic, { CastShadow = false })
		end
	end
	local function icecream(x, z, s)
		local gy = K.groundY(x, z)
		for i = 0, 5 do
			K.cyl(K.v(x, gy + (i + 0.5) * 1.2 * s, z), 1.22 * s, (0.8 + i * 0.75) * s, (i % 2 == 0) and rgb(222, 166, 96) or rgb(200, 140, 74), M.SmoothPlastic)
		end
		local top = gy + 7.2 * s
		K.ball(K.v(x, top + 1.3 * s, z), 5 * s, K.pick({ rgb(255, 190, 214), rgb(255, 248, 230), rgb(176, 116, 78) }), M.SmoothPlastic)
		K.ball(K.v(x + 0.3 * s, top + 4.4 * s, z), 4 * s, K.pick({ rgb(160, 230, 200), rgb(255, 214, 120), rgb(200, 170, 255) }), M.SmoothPlastic)
		K.ball(K.v(x + 0.3 * s, top + 6.7 * s, z), 1.2 * s, rgb(230, 30, 50), M.SmoothPlastic)
	end
	local function donut(x, z, s, yaw)
		local gy = K.groundY(x, z)
		local f = K.at(x, gy + 3.3 * s, z, yaw)
		local glaze = K.pick({ rgb(255, 150, 200), rgb(120, 76, 48), rgb(255, 255, 255), rgb(150, 210, 255) })
		for k = 0, 11 do
			local a = k / 12 * math.pi * 2
			local p = f * CFrame.new(math.cos(a) * 2.2 * s, math.sin(a) * 2.2 * s, 0)
			K.ball(p.Position, 2.3 * s, rgb(224, 168, 98), M.SmoothPlastic)
			K.ball((p * CFrame.new(0, 0, -0.4 * s)).Position, 1.9 * s, glaze, M.SmoothPlastic)
			if k % 2 == 0 then
				K.box(p * CFrame.new(0, 0, -1.3 * s) * CFrame.Angles(0, 0, a * 3), Vector3.new(0.6, 0.18, 0.18) * s, K.pick(SPRINKLES), M.SmoothPlastic, { CastShadow = false })
			end
		end
	end
	local function cotton(x, z, s)
		local gy = K.groundY(x, z)
		local h = K.rnd(6, 9) * s
		K.cyl(K.v(x, gy + h / 2, z), h, 0.7 * s, rgb(250, 245, 240), M.SmoothPlastic)
		local c = K.pick({ rgb(255, 170, 214), rgb(170, 210, 255), rgb(214, 180, 255) })
		local top = K.v(x, gy + h + 2 * s, z)
		K.ball(top, 7 * s, c, M.Fabric)
		for k = 1, 4 do
			local a = k * 1.57 + K.rnd(-0.3, 0.3)
			K.ball(top + Vector3.new(math.cos(a) * 2.6 * s, K.rnd(-1.2, 0.8) * s, math.sin(a) * 2.6 * s), K.rnd(4, 5) * s, c:Lerp(WHITE, 0.15), M.Fabric)
		end
	end
	local function gumdrop(x, z, d)
		local gy = K.groundY(x, z)
		K.ball(K.v(x, gy - d * 0.12, z), d, K.pick(SPRINKLES), M.SmoothPlastic, { Reflectance = 0.15 })
	end

	-- ворота: пряничный домик
	do
		local g = K.at(-99, 0, 45, K.yawOf(Vector3.new(1, 0, 0)))
		local cookie, icing, dark = rgb(186, 114, 60), WHITE, rgb(132, 74, 38)
		local W, D, H, rh = 16, 13, 10, 7
		K.box(g * CFrame.new(0, H / 2, 0), Vector3.new(W, H, D), cookie, M.SmoothPlastic)
		for _, s in ipairs({ -1, 1 }) do
			K.wedge(g * CFrame.new(0, H + rh / 2, s * (D / 4 + 0.4)) * CFrame.Angles(0, s == 1 and math.pi or 0, 0), Vector3.new(W + 2, rh, D / 2 + 1.4), dark, M.SmoothPlastic)
			K.box(g * CFrame.new(0, H + 0.1, s * (D / 2 + 1.1)), Vector3.new(W + 2.4, 0.7, 0.7), icing, M.SmoothPlastic)
			for k = 0, 9 do
				K.ball((g * CFrame.new(-W / 2 + 0.3 + k * (W - 0.6) / 9, H - 0.4, s * (D / 2 + 1.1))).Position, 0.8, icing, M.SmoothPlastic)
			end
			for k = 0, 4 do
				local p = g * CFrame.new(-W / 2 + 2 + k * (W - 4) / 4, H + rh * 0.5, s * (D / 4 + 0.6))
				K.ball(p.Position + Vector3.new(0, 0.4, 0), 1.6, SPRINKLES[(k + (s > 0 and 2 or 0)) % #SPRINKLES + 1], M.SmoothPlastic)
			end
		end
		K.box(g * CFrame.new(0, H + rh + 0.1, 0), Vector3.new(W + 2.4, 0.8, 1), icing, M.SmoothPlastic)
		-- двери и окна
		K.box(g * CFrame.new(0, 3.6, -D / 2 - 0.1), Vector3.new(5, 7.2, 0.3), rgb(70, 40, 22), M.SmoothPlastic)
		K.box(g * CFrame.new(0, 7.4, -D / 2 - 0.2), Vector3.new(6, 0.6, 0.5), icing, M.SmoothPlastic)
		for _, sx in ipairs({ -5, 5 }) do
			local w = K.box(g * CFrame.new(sx, 6, -D / 2 - 0.1), Vector3.new(2.6, 2.6, 0.2), sx < 0 and rgb(255, 150, 200) or rgb(150, 220, 255), M.Neon, { Transparency = 0.2, CastShadow = false })
			K.box(g * CFrame.new(sx, 6, -D / 2 - 0.2), Vector3.new(3.2, 0.4, 0.3), icing, M.SmoothPlastic)
			K.box(g * CFrame.new(sx, 6, -D / 2 - 0.2), Vector3.new(0.4, 3.2, 0.3), icing, M.SmoothPlastic)
			K.light(w, rgb(255, 210, 230), 10, 1)
			cane((g * CFrame.new(sx * 0.66, 0, -D / 2 - 1.2)).Position, 8, K.yawOf(Vector3.new(1, 0, 0)) + (sx < 0 and math.pi or 0), 0.9)
		end
		K.blockRect(-110, 33, -88, 57)
	end

	-- база: сахарный замок
	K.castle(89, -45, math.pi / 2, {
		wall = rgb(255, 198, 224), mat = M.SmoothPlastic, trim = rgb(255, 240, 160), trimMat = M.SmoothPlastic,
		roof = rgb(150, 216, 255), roofMat = M.SmoothPlastic, flag = rgb(255, 92, 160), glow = rgb(255, 245, 210),
	})
	lollipop(78, -60, 1.3, K.yawOf(Vector3.new(-1, 0, 0)))
	lollipop(78, -30, 1.3, K.yawOf(Vector3.new(-1, 0, 0)))
	K.spawns(65, -20, K.face(65, -20, 0, 0))

	-- радуга на севере
	do
		local cols = { rgb(255, 90, 90), rgb(255, 170, 70), rgb(255, 236, 90), rgb(110, 220, 120), rgb(90, 170, 255), rgb(170, 110, 255) }
		local c0 = K.v(0, -4, 122)
		for bIdx, col in ipairs(cols) do
			local R = 74 - (bIdx - 1) * 2.4
			local n = 36
			for k = 0, n - 1 do
				local a0, a1 = k / n * math.pi, (k + 1) / n * math.pi
				local p0 = c0 + Vector3.new(math.cos(a0) * R, math.sin(a0) * R, 0)
				local p1 = c0 + Vector3.new(math.cos(a1) * R, math.sin(a1) * R, 0)
				K.box(CFrame.lookAt((p0 + p1) / 2, p1), Vector3.new(1.2, 2.5, (p1 - p0).Magnitude + 0.25), col, M.SmoothPlastic, { Transparency = 0.15, CastShadow = false })
			end
		end
		for _, sx in ipairs({ -1, 1 }) do
			for k = 1, 6 do
				K.ball(K.v(sx * 68 + K.rnd(-8, 8), K.rnd(1, 5), 122 + K.rnd(-5, 5)), K.rnd(7, 11), WHITE, M.Fabric)
			end
			K.block(sx * 68, 122, 12)
		end
	end

	-- сладости вокруг
	K.scatter(14, { -150, -150, 150, 150 }, 4, function(x, z) lollipop(x, z, K.rnd(0.9, 1.5), K.face(x, z, 0, 0)) end, 2)
	K.scatter(14, { -150, -150, 150, 150 }, 3, function(x, z) cane(K.v(x, K.groundY(x, z), z), K.rnd(6, 10), K.rnd(0, 6.28), K.rnd(0.9, 1.2)) end, 1.5)
	K.scatter(26, { -150, -150, 150, 150 }, 2.5, function(x, z) gumdrop(x, z, K.rnd(2.4, 4.4)) end, 1.6)
	K.scatter(7, { -140, -140, 140, 140 }, 5, function(x, z) cupcake(x, z, K.rnd(1, 1.5)) end, 3.5)
	K.scatter(5, { -140, -140, 140, 140 }, 5, function(x, z) icecream(x, z, K.rnd(1, 1.4)) end, 3)
	K.scatter(4, { -140, -140, 140, 140 }, 5, function(x, z) donut(x, z, K.rnd(1, 1.3), K.face(x, z, 0, 0)) end, 3.5)
	K.scatter(18, { rMin = 95, rMax = 160, cx = 0, cz = 0 }, 6, function(x, z) cotton(x, z, K.rnd(1, 1.6)) end, 3)
	K.scatter(8, { -110, -110, 110, 110 }, 6, function(x, z) cotton(x, z, K.rnd(0.8, 1.1)) end, 2.5)
	K.scatter(4, { -140, -140, 140, 140 }, 5, function(x, z)
		local f = K.at(x, 0.6, z, K.rnd(0, 3)) * CFrame.Angles(0, 0, 0.12)
		K.box(f, Vector3.new(7, 1, 11), rgb(112, 64, 36), M.SmoothPlastic)
		for i = -1, 1 do K.box(f * CFrame.new(i * 2.2, 0.55, 0), Vector3.new(0.3, 0.2, 10.4), rgb(140, 84, 50), M.SmoothPlastic) end
		for i = -2, 2 do K.box(f * CFrame.new(0, 0.55, i * 2.1), Vector3.new(6.4, 0.2, 0.3), rgb(140, 84, 50), M.SmoothPlastic) end
	end, 5)
	K.scatter(60, { -150, -150, 150, 150 }, 1, function(x, z)
		K.box(K.at(x, 0.08, z, K.rnd(0, 3)), Vector3.new(1, 0.16, 0.3), K.pick(SPRINKLES), M.SmoothPlastic, { CastShadow = false })
	end)
	K.corners(P, 9.5, function(x, z) K.lamp(x, z, rgb(255, 170, 214), rgb(255, 250, 252)) end)

	K.ambient({
		Color = rgb(255, 200, 230), Color2 = rgb(200, 230, 255), Size = NumberSequence.new(0.4, 0), Rate = 20,
		Lifetime = NumberRange.new(3, 5), Speed = NumberRange.new(0.5, 1), y = 6, h = 8, size = 230,
	})
	K.lighting({
		clock = 14.5, brightness = 2.4, ambient = rgb(128, 112, 130), outdoor = rgb(170, 152, 172), shift = rgb(255, 236, 246),
		density = 0.28, offset = 0.12, atmColor = rgb(255, 222, 240), decay = rgb(255, 172, 216), glare = 0.2, haze = 1.2,
		bloom = 0.5, tint = rgb(255, 246, 250), saturation = 0.32, contrast = 0.06, clouds = 0.5,
	})
	K.walls()
end

---------------------------------------------------------------- 8. SPACE STATION — астероид, неон, звёзды

MAPS.Space = function()
	K.reset(8808)
	K.colors({
		Slate = rgb(96, 92, 114), Basalt = rgb(64, 60, 80), Rock = rgb(124, 118, 142), CrackedLava = rgb(126, 74, 210),
		Ground = rgb(104, 100, 122), Asphalt = rgb(54, 52, 64), Salt = rgb(184, 178, 206), Glacier = rgb(120, 222, 255),
	})
	K.ground(M.Slate)
	K.ring(168, 24, function(x, z)
		K.tBall(x, K.rnd(-10, -3), z, K.rnd(20, 30), K.rnd(0, 1) < 0.5 and M.Rock or M.Basalt)
	end)
	K.ring(212, 34, function(x, z)
		K.tBall(x, K.rnd(-26, -14), z, K.rnd(40, 58), M.Basalt)
	end)

	local cyan, purple = rgb(80, 230, 255), rgb(190, 110, 255)
	local metal, white = rgb(150, 156, 174), rgb(234, 238, 246)
	local P = { { -90, -45 }, { -35, -45 }, { -35, 20 }, { 20, 20 }, { 20, -25 }, { 65, -25 }, { 65, 40 } }
	K.path(P, {
		color = rgb(150, 156, 174), mat = M.DiamondPlate, discColor = rgb(132, 138, 156),
		edge = function(x, z, dir, k)
			local c = (k % 2 == 0) and cyan or purple
			local p = K.box(K.at(x, 0.3, z, K.yawOf(dir)), Vector3.new(0.7, 0.35, 1.4), c, M.Neon, { CastShadow = false })
			if k % 8 == 0 then K.light(p, c, 12, 1.2) end
		end,
	})
	-- кратеры
	K.scatter(16, { -150, -150, 150, 150 }, 16, function(x, z)
		local r = K.rnd(6, 12)
		K.tBall(x, r * 0.55, z, r, M.Air)
		for k = 1, 9 do
			local a = k / 9 * math.pi * 2 + K.rnd(-0.2, 0.2)
			K.tBall(x + math.cos(a) * r * 0.92, -r * 0.12, z + math.sin(a) * r * 0.92, r * 0.32, M.Rock)
		end
		if r > 9 then K.tCyl(x, -r * 0.45 - 1, z, 2, r * 0.5, M.CrackedLava) end
	end, 6)

	-- ворота: портал пришельцев
	do
		local g = K.at(-99, 0, -45, K.yawOf(Vector3.new(1, 0, 0)))
		local dark = rgb(70, 72, 88)
		K.cyl((g * CFrame.new(0, 0.6, 0)).Position, 1.2, 16, dark, M.DiamondPlate)
		K.cyl((g * CFrame.new(0, 1.3, 0)).Position, 0.3, 16.6, purple, M.Neon, { CastShadow = false })
		for _, s in ipairs({ -1, 1 }) do
			K.box(g * CFrame.new(s * 8, 5, 0), Vector3.new(1.6, 10, 2.4), metal, M.Metal)
			K.box(g * CFrame.new(s * 7.4, 8.4, 0), Vector3.new(1.4, 1, 1.6), metal, M.Metal)
			local tip = K.box(g * CFrame.new(s * 8, 10.6, 0), Vector3.new(1, 1.2, 1), cyan, M.Neon)
			K.light(tip, cyan, 12, 1.5)
		end
		local center = g * CFrame.new(0, 8.4, 0)
		local ring = K.group("PortalRing", { Rotor = 30 })
		K.inside(ring, function()
			for k = 0, 19 do
				local a = k / 20 * math.pi * 2
				K.box(center * CFrame.Angles(0, 0, a) * CFrame.new(0, 6.4, 0), Vector3.new(2.2, 1.4, 1.4), (k % 2 == 0) and purple or rgb(90, 60, 160), M.Neon, { CastShadow = false })
			end
		end)
		K.rest(ring, center)
		local disc = K.hcyl(center * CFrame.Angles(0, math.pi / 2, 0), 0.3, 12, rgb(150, 80, 255), M.Neon, { Transparency = 0.35, CastShadow = false })
		K.light(disc, rgb(170, 100, 255), 28, 3)
		K.emitter(disc, {
			Color = rgb(210, 160, 255), Color2 = cyan, Size = NumberSequence.new(0.6, 0), Rate = 40,
			Lifetime = NumberRange.new(1, 2), Speed = NumberRange.new(2, 5),
		})
		K.block(-100, -45, 10)
	end

	-- база: станция с энергоядром
	do
		local cx, cz = 65, 54
		local b = K.at(cx, 0, cz, 0)
		K.cyl(K.v(cx, 0.6, cz), 1.2, 30, rgb(90, 94, 110), M.DiamondPlate)
		K.cyl(K.v(cx, 1.25, cz), 0.2, 30.6, cyan, M.Neon, { CastShadow = false })
		K.cyl(K.v(cx, 9, cz), 16, 10, white, M.SmoothPlastic)
		for _, y in ipairs({ 4, 8, 12, 16 }) do
			K.cyl(K.v(cx, y, cz), 0.5, 10.4, cyan, M.Neon, { CastShadow = false })
		end
		K.cyl(K.v(cx, 17.4, cz), 1.4, 13, metal, M.Metal)
		K.ball(K.v(cx, 18, cz), 12, rgb(170, 230, 255), M.Glass, { Transparency = 0.45 })
		local core = K.group("Core", { Float = 0.6, Spin = 60, Speed = 1.2 })
		K.inside(core, function()
			local c = K.gem(K.v(cx, 20, cz), 3.4, cyan)
			K.light(c, cyan, 40, 3)
		end)
		K.rest(core, K.at(cx, 20, cz))
		K.box(b * CFrame.new(0, 3.5, -5), Vector3.new(4.6, 7, 1.2), metal, M.Metal)
		K.box(b * CFrame.new(0, 3.2, -5.65), Vector3.new(3.2, 5.8, 0.2), rgb(30, 40, 60), M.SmoothPlastic)
		K.box(b * CFrame.new(0, 6.5, -5.7), Vector3.new(4, 0.4, 0.2), cyan, M.Neon, { CastShadow = false })
		for k = 0, 3 do
			local a = k * math.pi / 2 + math.pi / 4
			local px, pz = cx + math.cos(a) * 12, cz + math.sin(a) * 12
			K.cyl(K.v(px, 6.6, pz), 12, 2.2, white, M.SmoothPlastic)
			K.cyl(K.v(px, 12.8, pz), 0.8, 3, metal, M.Metal)
			local tip = K.ball(K.v(px, 14, pz), 2, cyan, M.Neon, { CastShadow = false })
			K.light(tip, cyan, 14, 1.5)
		end
		K.cyl(K.v(cx + 3, 27, cz + 2), 8, 0.4, metal, M.Metal)
		K.ball(K.v(cx + 3, 31.2, cz + 2), 0.9, rgb(255, 60, 60), M.Neon, { CastShadow = false })
		K.zone(cx, cz, 17)
		K.block(cx, cz, 15)
	end
	K.spawns(44, 44, K.face(44, 44, 0, 0))

	local function dome(x, z, d)
		local gy = K.groundY(x, z)
		K.cyl(K.v(x, gy + 0.5, z), 1, d + 1.4, rgb(110, 114, 130), M.DiamondPlate)
		K.ball(K.v(x, gy + 0.6, z), d, rgb(170, 225, 255), M.Glass, { Transparency = 0.5 })
		K.cyl(K.v(x, gy + 1.2, z), 0.3, d + 0.25, cyan, M.Neon, { CastShadow = false })
		for _ = 1, 3 do
			K.ball(K.v(x + K.rnd(-d / 5, d / 5), gy + 1.5, z + K.rnd(-d / 5, d / 5)), K.rnd(1.5, 2.6), rgb(90, 220, 120), M.Grass)
		end
		K.light(K.anchor(K.v(x, gy + 3, z), Vector3.one), rgb(170, 230, 255), d, 1.2)
		K.block(x, z, d / 2 + 1)
	end
	local function radar(x, z, yaw)
		local gy = K.groundY(x, z)
		K.box(K.at(x, gy + 0.5, z), Vector3.new(4, 1, 4), rgb(90, 94, 110), M.DiamondPlate)
		K.cyl(K.v(x, gy + 4, z), 6, 0.8, metal, M.Metal)
		local f = K.at(x, gy + 7.6, z, yaw) * CFrame.Angles(math.rad(35), 0, 0)
		K.hcyl(f * CFrame.Angles(0, math.pi / 2, 0), 0.5, 8, rgb(222, 226, 238), M.SmoothPlastic)
		K.hcyl(f * CFrame.Angles(0, math.pi / 2, 0) * CFrame.new(-0.35, 0, 0), 0.3, 6.6, rgb(190, 196, 210), M.SmoothPlastic)
		K.box(f * CFrame.new(0, 0, -2), Vector3.new(0.3, 0.3, 4), metal, M.Metal)
		K.ball((f * CFrame.new(0, 0, -4.1)).Position, 0.8, rgb(255, 80, 80), M.Neon, { CastShadow = false })
		K.block(x, z, 4)
	end
	local function rocket(x, z, s)
		local gy = K.groundY(x, z)
		local red = rgb(226, 60, 60)
		K.cyl(K.v(x, gy + 0.6, z), 1.2, 14 * s, rgb(90, 94, 110), M.DiamondPlate)
		K.cyl(K.v(x, gy + 1.2 + 9 * s, z), 18 * s, 5 * s, white, M.SmoothPlastic)
		K.cyl(K.v(x, gy + 1.2 + 4 * s, z), 1.2 * s, 5.1 * s, red, M.SmoothPlastic)
		K.cyl(K.v(x, gy + 1.2 + 14 * s, z), 0.8 * s, 5.1 * s, red, M.SmoothPlastic)
		K.cone(K.v(x, gy + 1.2 + 18 * s, z), 6 * s, 5 * s, red, M.SmoothPlastic, 6)
		K.hcyl(K.at(x, gy + 1.2 + 12 * s, z) * CFrame.new(0, 0, -2.45 * s) * CFrame.Angles(0, math.pi / 2, 0), 0.3, 1.8 * s, cyan, M.Neon)
		for k = 0, 2 do
			local a = k / 3 * math.pi * 2
			local dir = Vector3.new(math.cos(a), 0, math.sin(a))
			K.wedge(K.at(x + dir.X * 4 * s, gy + 1.2 + 2.5 * s, z + dir.Z * 4 * s, K.yawOf(dir)), Vector3.new(0.5, 5, 3) * s, red, M.SmoothPlastic)
		end
		local tower = rgb(200, 90, 60)
		K.box(K.at(x + 7 * s, gy + 1.2 + 11 * s, z), Vector3.new(1.4, 22, 1.4) * s, tower, M.Metal)
		for k = 1, 5 do
			K.box(K.at(x + 5 * s, gy + 1.2 + k * 4 * s, z), Vector3.new(3.4, 0.4, 0.4) * s, tower, M.Metal)
		end
		local glow = K.anchor(K.v(x, gy + 1.6, z), Vector3.new(3, 0.5, 3))
		K.emitter(glow, {
			Texture = K.SMOKE, Color = rgb(200, 200, 220), LightEmission = 0, LightInfluence = 1,
			Size = NumberSequence.new(3, 8), Transparency = NumberSequence.new(0.5, 1), Lifetime = NumberRange.new(2, 3),
			Speed = NumberRange.new(1, 3), Spread = Vector2.new(80, 80), Rate = 4,
		})
		K.block(x, z, 8 * s)
	end
	local function solar(x, z, yaw)
		local gy = K.groundY(x, z)
		local f = K.at(x, gy, z, yaw)
		for i = -1, 1 do
			K.box(f * CFrame.new(i * 5, 1.5, 0), Vector3.new(0.4, 3, 0.4), metal, M.Metal)
			local panel = f * CFrame.new(i * 5, 3.2, 0) * CFrame.Angles(math.rad(-30), 0, 0)
			K.box(panel, Vector3.new(4.6, 0.2, 3.4), rgb(40, 60, 150), M.Glass)
			K.box(panel * CFrame.new(0, 0.12, 0), Vector3.new(4.7, 0.05, 0.15), metal, M.Metal)
			K.box(panel * CFrame.new(0, 0.12, 0), Vector3.new(0.15, 0.05, 3.5), metal, M.Metal)
		end
		K.block(x, z, 8)
	end
	local function mushroom(x, z, s)
		local gy = K.groundY(x, z)
		local c = K.rnd(0, 1) < 0.5 and cyan or purple
		K.cyl(K.v(x, gy + 1.5 * s, z), 3 * s, 0.8 * s, rgb(220, 220, 240), M.SmoothPlastic)
		local cap = K.ball(K.v(x, gy + 3 * s, z), 3.2 * s, c, M.Neon, { CastShadow = false })
		K.cyl(K.v(x, gy + 2.9 * s, z), 0.4 * s, 3.1 * s, rgb(40, 40, 60), M.SmoothPlastic)
		K.light(cap, c, 10, 1.2)
	end
	local function container(x, z, yaw)
		local f = K.at(x, K.groundY(x, z) + 1.6, z, yaw)
		local col = K.pick({ rgb(220, 120, 50), rgb(70, 130, 210), rgb(200, 200, 210) })
		K.box(f, Vector3.new(4, 3.2, 7), col, M.Metal)
		for i = -2, 2 do K.box(f * CFrame.new(0, 0, i * 1.4), Vector3.new(4.1, 3.3, 0.25), col:Lerp(rgb(0, 0, 0), 0.25), M.Metal) end
		K.box(f * CFrame.new(0, 1.7, 0), Vector3.new(0.6, 0.12, 6.6), cyan, M.Neon, { CastShadow = false })
		K.block(x, z, 4.5)
	end

	dome(-70, 22, 16)
	dome(-6, -6, 12)
	dome(100, -10, 18)
	dome(-20, 64, 14)
	dome(36, -70, 14)
	radar(-60, -82, K.face(-60, -82, 0, 0))
	radar(40, 60, K.face(40, 60, 0, 0))
	radar(-110, 0, K.face(-110, 0, 0, 0))
	rocket(-86, 74, 1.2)
	rocket(108, -76, 1)
	solar(-12, -84, 0)
	solar(96, 24, math.pi / 2)
	solar(-110, 40, math.pi / 2)
	container(0, 46, 0.2)
	container(-58, -14, 1.6)
	container(88, -40, 0.4)
	K.scatter(12, { -150, -150, 150, 150 }, 4, function(x, z)
		K.crystals(x, z, K.rnd(0.9, 1.5), K.rnd(0, 1) < 0.5 and purple or cyan, M.Neon)
		K.light(K.anchor(K.v(x, 3, z), Vector3.one), purple, 14, 1.2)
	end, 2)
	K.scatter(14, { -140, -140, 140, 140 }, 3, function(x, z) mushroom(x, z, K.rnd(0.8, 1.4)) end, 1.8)
	K.scatter(10, { -150, -150, 150, 150 }, 4, function(x, z) K.boulder(x, z, K.rnd(0.8, 1.5), M.Rock) end, 2.5)
	K.scatter(12, { -140, -140, 140, 140 }, 2, function(x, z) K.rock(x, z, K.rnd(0.5, 0.9), rgb(110, 104, 128), M.Slate) end)
	K.corners(P, 9.5, function(x, z) K.lamp(x, z, cyan, rgb(70, 74, 90)) end)

	-- летающие астероиды по краю
	for k = 1, 10 do
		local a = k / 10 * math.pi * 2 + K.rnd(-0.2, 0.2)
		local r = K.rnd(120, 150)
		local pos = K.v(math.cos(a) * r, K.rnd(24, 40), math.sin(a) * r)
		local g = K.group("Asteroid", { Float = K.rnd(1.5, 3), Speed = K.rnd(0.3, 0.6), Phase = K.rnd(0, 6), Spin = K.rnd(-10, 10) })
		K.inside(g, function()
			for _ = 1, 3 do
				K.box(CFrame.new(pos + Vector3.new(K.rnd(-2, 2), K.rnd(-1.5, 1.5), K.rnd(-2, 2))) * CFrame.Angles(K.rnd(0, 3), K.rnd(0, 3), K.rnd(0, 3)), Vector3.new(K.rnd(3, 6), K.rnd(3, 5), K.rnd(3, 6)), rgb(116, 110, 132), M.Slate)
			end
		end)
		K.rest(g, CFrame.new(pos))
	end
	-- планеты в небе
	K.ball(K.v(-300, 150, -380), 140, rgb(240, 172, 112), M.SmoothPlastic, { CastShadow = false })
	K.ball(K.v(-292, 176, -372), 104, rgb(250, 196, 140), M.SmoothPlastic, { CastShadow = false })
	K.hcyl(CFrame.new(K.v(-300, 150, -380)) * CFrame.Angles(0.35, 0.3, 0.25) * CFrame.Angles(0, 0, math.pi / 2), 0.6, 290, rgb(220, 200, 170), M.SmoothPlastic, { Transparency = 0.35, CastShadow = false })
	K.ball(K.v(330, 110, 300), 60, rgb(200, 200, 212), M.Slate, { CastShadow = false })
	for _ = 1, 6 do
		local d = Vector3.new(K.rnd(-1, 1), K.rnd(-1, 1), K.rnd(-1, 1)).Unit
		K.ball(K.v(330, 110, 300) + d * 27, K.rnd(8, 14), rgb(160, 160, 172), M.Slate, { CastShadow = false })
	end
	K.ball(K.v(380, 210, -220), 34, rgb(90, 160, 255), M.SmoothPlastic, { CastShadow = false })

	K.ambient({
		Color = rgb(150, 220, 255), Color2 = rgb(200, 150, 255), Size = NumberSequence.new(0.25, 0), Rate = 16,
		Lifetime = NumberRange.new(4, 7), Speed = NumberRange.new(0.2, 0.6), y = 8, h = 14, size = 230,
	})
	K.lighting({
		clock = 0, brightness = 1.2, ambient = rgb(100, 90, 140), outdoor = rgb(130, 120, 176), shift = rgb(180, 170, 255), exposure = 0.3,
		density = 0.2, offset = 0, atmColor = rgb(110, 90, 190), decay = rgb(60, 40, 140), glare = 0, haze = 0.6,
		bloom = 1, bloomThreshold = 0.9, tint = rgb(232, 226, 255), saturation = 0.25, contrast = 0.12,
		stars = 5000, celestial = false,
	})
	K.walls()
end

---------------------------------------------------------------- выбор карты и постройка

local oldSpawns = {}

-- старая карта: точки пути P1, P2, ... — в ServerStorage, точки появления выключаем
local function retireOldMap()
	local old = ServerStorage:FindFirstChild("OldMapPath") or Instance.new("Folder")
	old.Name = "OldMapPath"
	for i = 1, 200 do
		local p = workspace:FindFirstChild("P" .. i)
		if p then p.Parent = old end
	end
	old.Parent = ServerStorage
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("SpawnLocation") and d.Enabled then
			d.Enabled = false
			table.insert(oldSpawns, d)
		end
	end
end

-- если новая карта не построилась — возвращаем старую как было
local function restoreOldMap()
	local old = ServerStorage:FindFirstChild("OldMapPath")
	if old then
		for _, p in ipairs(old:GetChildren()) do
			if not workspace:FindFirstChild(p.Name) then p.Parent = workspace end
		end
	end
	for _, s in ipairs(oldSpawns) do
		if s.Parent then s.Enabled = true end
	end
end

local function validId(id)
	return typeof(id) == "string" and MapConfig.get(id) ~= nil
end

local function teleportMap()
	for _, p in ipairs(Players:GetPlayers()) do
		local ok, join = pcall(function() return p:GetJoinData() end)
		local td = ok and type(join) == "table" and join.TeleportData or nil
		if type(td) == "table" and validId(td.map) then
			return td.map
		end
	end
	return nil
end

-- какую карту строить: портал хаба → MemoryStore / данные телепорта; Studio → MapConfig.StudioMap; иначе случайная
local function chooseMap()
	local isReserved = game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
	if isReserved then
		for _ = 1, 3 do
			local ok, value = pcall(function()
				return MemoryStoreService:GetSortedMap("HubMatches"):GetAsync(game.PrivateServerId)
			end)
			if ok then
				local id = type(value) == "table" and value.map or value
				if validId(id) then return id, "hub" end
				break
			end
			task.wait(1)
		end
		local t0 = os.clock()
		while os.clock() - t0 < 15 do
			local id = teleportMap()
			if id then return id, "teleport" end
			task.wait(0.25)
		end
		return MapConfig.Default, "default"
	end
	if RunService:IsStudio() and validId(MapConfig.StudioMap) then
		return MapConfig.StudioMap, "studio"
	end
	return MapConfig.Order[math.random(1, #MapConfig.Order)], "random"
end

-- убрать недостроенную карту
local function cleanup()
	if K.root then K.root:Destroy() end
	for i = 1, 200 do
		local p = workspace:FindFirstChild("P" .. i)
		if p then p:Destroy() end
	end
	pcall(function()
		terrain:FillBlock(CFrame.new(O + Vector3.new(0, 30, 0)), Vector3.new(1000, 140, 1000), M.Air)
	end)
end

local function build(id)
	local fn = MAPS[id]
	if not fn then return false, "нет такой карты" end
	local t0 = os.clock()
	local ok, err = pcall(fn)
	if not ok then return false, err end
	K.root.Parent = workspace
	print(string.format("[MapService] карта %s построена за %.2f с", id, os.clock() - t0))
	return true
end

-- где нельзя ставить юнитов и где путь (читает PlacementRules у игроков и на сервере)
local function publishNoBuild()
	local list = {}
	for _, z in ipairs(K.nb or {}) do
		if z[1] == "c" then
			table.insert(list, string.format("c,%.1f,%.1f,%.1f", z[2] + O.X, z[3] + O.Z, z[4]))
		else
			table.insert(list, string.format("r,%.1f,%.1f,%.1f,%.1f", z[2] + O.X, z[3] + O.Z, z[4] + O.X, z[5] + O.Z))
		end
	end
	local v = ReplicatedStorage:FindFirstChild("NoBuildZones")
	if not v then
		v = Instance.new("StringValue")
		v.Name = "NoBuildZones"
		v.Parent = ReplicatedStorage
	end
	v.Value = table.concat(list, ";")
	-- путь строкой: у игрока точки P1..Pn могут быть не подгружены (StreamingEnabled)
	local path = {}
	for i = 1, 200 do
		local pt = workspace:FindFirstChild("P" .. i)
		if not pt then break end
		table.insert(path, string.format("%.2f,%.2f", pt.Position.X, pt.Position.Z))
	end
	local pv = ReplicatedStorage:FindFirstChild("MapPath")
	if not pv then
		pv = Instance.new("StringValue")
		pv.Name = "MapPath"
		pv.Parent = ReplicatedStorage
	end
	pv.Value = table.concat(path, ";")
end

local function spawnEveryone()
	Players.CharacterAutoLoads = true
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			pcall(function() p:LoadCharacter() end)
		end)
	end
end

local function start()
	pcall(function() workspace.Terrain.Decoration = false end) -- без высокой травы
	retireOldMap()
	local id, why = chooseMap()
	local ok, err = build(id)
	if not ok then
		warn("[MapService] карта " .. tostring(id) .. " не построилась: " .. tostring(err))
		cleanup()
		if id ~= MapConfig.Default then
			id = MapConfig.Default
			ok, err = build(id)
			if not ok then
				warn("[MapService] запасная карта тоже не построилась: " .. tostring(err))
				cleanup()
			end
		end
	end
	if not ok then
		restoreOldMap()
		workspace:SetAttribute("MapReady", true)
		spawnEveryone()
		return
	end
	publishNoBuild()
	workspace:SetAttribute("MapId", id)
	workspace:SetAttribute("MapName", MapConfig[id].Name)
	workspace:SetAttribute("MapSource", why)
	workspace:SetAttribute("MapReady", true)
	spawnEveryone()
end

start()
