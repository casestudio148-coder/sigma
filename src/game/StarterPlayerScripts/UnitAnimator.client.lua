-- StarterPlayer.StarterPlayerScripts.UnitAnimator (LocalScript)
-- Плавные анимации юнитов кодом (без загрузки анимаций в Roblox):
--   • покой: дыхание, лёгкое покачивание корпуса, взгляд по сторонам, руки чуть двигаются
--   • атака: у каждого юнита свой удар (замах мечом, натяжение лука, выпад копьём, заклинание,
--     удар молотом, два кинжала, взмах косой, выстрел с отдачей)
--   • появление и улучшение: радостный взмах руками
-- Работает с любыми ригами R15 и R6 (через суставы Motor6D). Башни-здания без суставов просто пропускаются.
-- Всё только на клиенте — сервер и другие игроки не нагружаются.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local towersFolder = workspace:WaitForChild("Towers")
local fxEvent = ReplicatedStorage:WaitForChild("TowerFX")

local MAX_DISTANCE = 160 -- дальше камеры не анимируем (экономия)
local rad = math.rad

---------------------------------------------------------------- стиль атаки каждого юнита

local STYLE = {
	Scout = "slash", Archer = "bow", Spearman = "thrust",
	Mage = "cast", IceMage = "cast", DartSpitter = "blow", BomberTower = "heavy",
	Assassin = "dual", Necromancer = "cast", CrossbowTower = "shoot", Paladin = "heavy",
	LightningMage = "cast", VoidLord = "cast", SoulReaper = "reap",
}
local FLOATY = { Mage = true, IceMage = true, Necromancer = true, LightningMage = true, VoidLord = true, SoulReaper = true }

-- позы: сустав → { вперёд/назад, поворот, вбок } в градусах (в осях родительской детали).
-- RS/LS — плечи, RE/LE — локти, W — корпус, N — шея, RH/LH — бёдра.
-- Плечо: +X поднимает руку вперёд; правая рука +Z — в сторону, левая −Z — в сторону.
-- Корпус: −X — наклон вперёд. Шея: +X — голова назад.
local ATTACKS = {
	slash = {
		{ 0.00, {} },
		{ 0.10, { RS = { 150, 0, 20 }, RE = { 30, 0, 0 }, W = { 4, 25, 0 }, N = { -5, -10, 0 }, LS = { 20, 0, -15 } } },
		{ 0.20, { RS = { 45, 0, -20 }, RE = { 10, 0, 0 }, W = { -12, -28, 0 }, N = { 0, 12, 0 }, LS = { -10, 0, -25 } } },
		{ 0.50, {} },
	},
	bow = {
		{ 0.00, {} },
		{ 0.12, { LS = { 90, 0, 0 }, RS = { 90, 0, -25 }, RE = { 0, 0, -70 }, W = { 0, -22, 0 }, N = { 0, 15, 0 } } },
		{ 0.22, { LS = { 92, 0, 0 }, RS = { 92, 0, -30 }, RE = { 0, 0, -85 }, W = { 0, -24, 0 }, N = { 0, 16, 0 } } },
		{ 0.27, { LS = { 88, 0, 0 }, RS = { 75, 0, 35 }, RE = { 0, 0, 0 }, W = { 3, -16, 0 }, N = { 2, 12, 0 } } },
		{ 0.60, {} },
	},
	thrust = {
		{ 0.00, {} },
		{ 0.09, { RS = { 55, 0, 10 }, RE = { 60, 0, 0 }, W = { 6, 22, 0 }, LS = { 30, 0, -10 } } },
		{ 0.17, { RS = { 98, 0, 0 }, RE = { 0, 0, 0 }, W = { -16, -14, 0 }, N = { -6, 0, 0 }, LS = { 10, 0, -20 }, RH = { -15, 0, 0 }, LH = { 20, 0, 0 } } },
		{ 0.50, {} },
	},
	cast = {
		{ 0.00, {} },
		{ 0.16, { RS = { 165, 0, 12 }, LS = { 165, 0, -12 }, N = { 16, 0, 0 }, W = { 9, 0, 0 } } },
		{ 0.28, { RS = { 88, 0, -5 }, LS = { 88, 0, 5 }, N = { -6, 0, 0 }, W = { -13, 0, 0 } } },
		{ 0.62, {} },
	},
	heavy = {
		{ 0.00, {} },
		{ 0.20, { RS = { 172, 0, 5 }, LS = { 172, 0, -5 }, RE = { 20, 0, 0 }, LE = { 20, 0, 0 }, W = { 14, 0, 0 }, N = { 12, 0, 0 } } },
		{ 0.32, { RS = { 55, 0, -8 }, LS = { 55, 0, 8 }, W = { -28, 0, 0 }, N = { -12, 0, 0 }, RH = { 15, 0, 0 }, LH = { 15, 0, 0 } } },
		{ 0.72, {} },
	},
	dual = {
		{ 0.00, {} },
		{ 0.07, { RS = { 125, 0, 35 }, LS = { 40, 0, -10 }, W = { 0, 22, 0 } } },
		{ 0.14, { RS = { 40, 0, -20 }, LS = { 125, 0, -35 }, W = { -6, -22, 0 } } },
		{ 0.22, { RS = { 115, 0, 15 }, LS = { 35, 0, -5 }, W = { -10, 12, 0 } } },
		{ 0.48, {} },
	},
	reap = {
		{ 0.00, {} },
		{ 0.17, { RS = { 100, 0, 60 }, LS = { 100, 0, -20 }, W = { 4, 50, 0 }, N = { 0, -15, 0 } } },
		{ 0.31, { RS = { 90, 0, -40 }, LS = { 90, 0, 35 }, W = { -12, -60, 0 }, N = { 0, 20, 0 } } },
		{ 0.70, {} },
	},
	blow = {
		{ 0.00, {} },
		{ 0.06, { RS = { 85, 0, -15 }, LS = { 85, 0, 15 }, N = { -10, 0, 0 }, W = { -4, 0, 0 } } },
		{ 0.13, { RS = { 80, 0, -12 }, LS = { 80, 0, 12 }, N = { 12, 0, 0 }, W = { 10, 0, 0 } } },
		{ 0.42, {} },
	},
	shoot = {
		{ 0.00, {} },
		{ 0.05, { RS = { 88, 0, -10 }, LS = { 88, 0, 10 }, W = { -5, 0, 0 } } },
		{ 0.11, { RS = { 98, 0, -10 }, LS = { 98, 0, 10 }, W = { 12, 0, 0 }, N = { 8, 0, 0 } } },
		{ 0.42, {} },
	},
}

-- радость при появлении и улучшении
local CHEER = {
	{ 0.00, {} },
	{ 0.16, { RS = { 0, 0, 150 }, LS = { 0, 0, -150 }, RE = { 30, 0, 0 }, LE = { 30, 0, 0 }, N = { 14, 0, 0 }, W = { 6, 0, 0 } } },
	{ 0.30, { RS = { 0, 0, 130 }, LS = { 0, 0, -130 }, N = { 10, 0, 0 }, W = { 2, 0, 0 } } },
	{ 0.44, { RS = { 0, 0, 155 }, LS = { 0, 0, -155 }, N = { 16, 0, 0 }, W = { 6, 0, 0 } } },
	{ 0.85, {} },
}

---------------------------------------------------------------- суставы

-- имя сустава (R15 и R6) → короткий ключ
local JOINT_KEY = {
	RightShoulder = "RS", LeftShoulder = "LS", RightElbow = "RE", LeftElbow = "LE",
	Waist = "W", RootJoint = "W6", Neck = "N", RightHip = "RH", LeftHip = "LH",
}

local units = {} -- [model] = { joints = { key = { motor, c0 } }, style, phase, anims = {} }

local function collect(model)
	local joints = {}
	local count = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") then
			local key = JOINT_KEY[string.gsub(d.Name, " ", "")]
			if key == "W6" then
				-- у R6 корпус двигаем через RootJoint, только если Waist нет
				key = "W"
				if joints.W then key = nil end
			end
			if key and not joints[key] then
				joints[key] = { motor = d, c0 = d.C0 }
				count += 1
			end
		end
	end
	return joints, count
end

local function track(model)
	if units[model] or not model:IsA("Model") then return end
	local joints, count = collect(model)
	if count == 0 then return end -- здание без суставов
	units[model] = {
		joints = joints,
		style = STYLE[model.Name] or "slash",
		floaty = FLOATY[model.Name] == true,
		phase = math.random() * 10,
		anims = {},
	}
end

local function untrack(model)
	local u = units[model]
	if not u then return end
	for _, j in pairs(u.joints) do
		if j.motor.Parent then j.motor.Transform = CFrame.identity end
	end
	units[model] = nil
end

local function play(model, frames)
	local u = units[model]
	if not u then return end
	-- новый удар заменяет незаконченный такой же — поза не «копится»
	u.anims = { { frames = frames, start = os.clock() } }
end

local function cheer(model)
	local u = units[model]
	if not u then return end
	table.insert(u.anims, { frames = CHEER, start = os.clock() })
end

---------------------------------------------------------------- сборка позы

local function ease(a)
	-- плавный разгон и торможение
	return a * a * (3 - 2 * a)
end

-- добавить к pose значения анимации в момент t
local function sample(pose, frames, t)
	local last = frames[#frames]
	if t >= last[1] then return true end
	for i = 1, #frames - 1 do
		local f0, f1 = frames[i], frames[i + 1]
		if t >= f0[1] and t < f1[1] then
			local a = ease((t - f0[1]) / (f1[1] - f0[1]))
			for key, v1 in pairs(f1[2]) do
				local v0 = f0[2][key] or { 0, 0, 0 }
				local p = pose[key]
				p[1] += v0[1] + (v1[1] - v0[1]) * a
				p[2] += v0[2] + (v1[2] - v0[2]) * a
				p[3] += v0[3] + (v1[3] - v0[3]) * a
			end
			for key, v0 in pairs(f0[2]) do
				if not f1[2][key] then
					local p = pose[key]
					p[1] += v0[1] * (1 - a)
					p[2] += v0[2] * (1 - a)
					p[3] += v0[3] * (1 - a)
				end
			end
			return false
		end
	end
	return false
end

local KEYS = { "RS", "LS", "RE", "LE", "W", "N", "RH", "LH" }

local function idle(pose, u, t)
	local p = t + u.phase
	local breath = math.sin(p * 1.8)
	pose.W[1] += 2 * breath
	pose.W[2] += 4 * math.sin(p * 0.55)
	pose.N[1] += 3 * math.sin(p * 1.8 + 0.6)
	pose.N[2] += 10 * math.sin(p * 0.4) -- оглядывается
	local arm = u.floaty and 10 or 5
	pose.RS[1] += arm * math.sin(p * 1.8 + 1)
	pose.LS[1] += arm * math.sin(p * 1.8 + 1.3)
	pose.RS[3] += 6 + 3 * breath
	pose.LS[3] -= 6 + 3 * breath
	if u.floaty then
		-- маги «колдуют» в покое: руки чуть разведены и плавают
		pose.RS[1] += 15
		pose.LS[1] += 15
		pose.RE[1] += 25 + 10 * math.sin(p * 1.3)
		pose.LE[1] += 25 + 10 * math.sin(p * 1.3 + 1)
	end
end

local function apply(u, t)
	local pose = {}
	for _, k in ipairs(KEYS) do
		pose[k] = { 0, 0, 0 }
	end
	idle(pose, u, t)
	local now = os.clock()
	for i = #u.anims, 1, -1 do
		local a = u.anims[i]
		if sample(pose, a.frames, now - a.start) then
			table.remove(u.anims, i)
		end
	end
	for key, j in pairs(u.joints) do
		local p = pose[key]
		if p and j.motor.Parent then
			-- поворот в осях родительской детали вокруг точки сустава
			local r = CFrame.Angles(rad(p[1]), rad(p[2]), rad(p[3]))
			local c0 = j.c0
			j.motor.Transform = c0:Inverse() * (CFrame.new(c0.Position) * r * c0.Rotation)
		end
	end
end

RunService.Stepped:Connect(function()
	local cam = workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position
	local t = os.clock()
	for model, u in pairs(units) do
		if not model.Parent then
			units[model] = nil
		else
			local pivot = model:GetPivot().Position
			if not camPos or (pivot - camPos).Magnitude < MAX_DISTANCE then
				apply(u, t)
			end
		end
	end
end)

---------------------------------------------------------------- события

local function onTower(model)
	-- ждём, пока сервер поставит башню (суставы на местах)
	task.spawn(function()
		local waited = 0
		while model.Parent and not model:GetAttribute("Ready") and waited < 3 do
			waited += task.wait(0.1)
		end
		if not model.Parent then return end
		track(model)
		cheer(model)
		model:GetAttributeChangedSignal("Level"):Connect(function()
			cheer(model)
		end)
	end)
end

towersFolder.ChildAdded:Connect(onTower)
towersFolder.ChildRemoved:Connect(untrack)
for _, m in ipairs(towersFolder:GetChildren()) do
	onTower(m)
end

fxEvent.OnClientEvent:Connect(function(fx)
	if typeof(fx) ~= "table" or typeof(fx.tower) ~= "Instance" then return end
	local u = units[fx.tower]
	if not u then return end
	play(fx.tower, ATTACKS[u.style] or ATTACKS.slash)
end)
