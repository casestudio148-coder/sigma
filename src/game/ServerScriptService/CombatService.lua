-- ServerScriptService.CombatService (ModuleScript)
-- Общее боевое ядро сервера. Им пользуются TowerManeger, AbilityService и BossController.
--   • Реестр живых мобов: Humanoid, корень, теги и позиция кэшируются ОДИН раз,
--     а не ищутся заново каждой башней каждый кадр.
--   • Единый расчёт урона: сопротивления → броня/уязвимость → щит → неуязвимость → кто убил.
--   • Поиск целей (First / Last / Strongest / Closest), области, «самая плотная толпа», цепь.
--   • Подключает StatusEffectManager (урон от горения/яда, иммунитеты, «босс или нет»).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local MobData = require(ReplicatedStorage:WaitForChild("MobData"))
local Janitor = require(ReplicatedStorage:WaitForChild("Janitor"))
local SEM = require(ServerScriptService:WaitForChild("StatusEffectManager"))

local Combat = {}

local function getFolder(name)
	local f = workspace:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = workspace
	end
	return f
end

local mobsFolder = getFolder("Mobs")
local towersFolder = getFolder("Towers")
Combat.MobsFolder = mobsFolder
Combat.TowersFolder = towersFolder

---------------------------------------------------------------- путь P1 -> P2 -> ... -> Pn

local PTS, CUM -- точки пути (без высоты) и пройденная длина до каждой

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function initPath()
	local pts = {}
	local i = 1
	while true do
		local p = workspace:FindFirstChild("P" .. i)
		if not p then break end
		table.insert(pts, flat(p.Position))
		i += 1
	end
	if #pts < 2 then return false end
	local cum = { 0 }
	for k = 2, #pts do
		cum[k] = cum[k - 1] + (pts[k] - pts[k - 1]).Magnitude
	end
	PTS, CUM = pts, cum
	return true
end

-- карту перестроили (MapService) — путь читаем заново
workspace:GetAttributeChangedSignal("MapReady"):Connect(function()
	PTS, CUM = nil, nil
end)

local function project(pos, a, b)
	local ab = b - a
	local lenSq = ab:Dot(ab)
	local t = lenSq > 0 and math.clamp((pos - a):Dot(ab) / lenSq, 0, 1) or 0
	return t, (pos - (a + ab * t)).Magnitude
end

-- сколько моб прошёл по пути (для режимов First / Last)
function Combat.GetProgress(position)
	if not PTS and not initPath() then return 0 end
	local pos = flat(position)
	local best, bestD = 0, math.huge
	for k = 1, #PTS - 1 do
		local t, d = project(pos, PTS[k], PTS[k + 1])
		if d < bestD then
			bestD = d
			best = CUM[k] + t * (CUM[k + 1] - CUM[k])
		end
	end
	return best
end

function Combat.FlatDistance(a, b)
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

---------------------------------------------------------------- реестр мобов

local infoByName = {}
local function infoFor(name)
	local info = infoByName[name]
	if not info then
		local cfg = MobData[name]
		local tags = {}
		if cfg and cfg.Tags then
			for _, tag in ipairs(cfg.Tags) do tags[tag] = true end
		end
		info = { config = cfg, tags = tags, boss = tags.Boss == true }
		infoByName[name] = info
	end
	return info
end

local entries = {} -- [mob] = запись
local list = {}    -- массив записей (быстрый обход)
local aliveCount = 0

local function unregister(mob)
	local e = entries[mob]
	if not e then return end
	entries[mob] = nil
	e.alive = false
	e.removed = true -- из массива list уберёт UpdateMobCache
	e.janitor:Destroy()
end

local function register(mob)
	if entries[mob] or not mob:IsA("Model") then return end
	local hum = mob:FindFirstChildOfClass("Humanoid")
	local root = mob:FindFirstChild("HumanoidRootPart") or mob.PrimaryPart or mob:FindFirstChild("Torso")
	if not hum or not root then return end

	local info = infoFor(mob.Name)
	local e = {
		mob = mob,
		humanoid = hum,
		root = root,
		config = info.config,
		tags = info.tags,
		boss = info.boss,
		pos = root.Position,
		progress = 0,
		alive = hum.Health > 0,
		removed = false,
		janitor = Janitor.new(),
	}
	e.progress = Combat.GetProgress(e.pos)
	entries[mob] = e
	table.insert(list, e)

	e.janitor:Connect(hum.Died, function()
		e.alive = false
		SEM.Clear(mob) -- мёртвому эффекты не нужны
	end)
end

mobsFolder.ChildAdded:Connect(register)
mobsFolder.ChildRemoved:Connect(unregister)
for _, m in ipairs(mobsFolder:GetChildren()) do
	register(m)
end

-- обновить позиции и прогресс всех мобов (раз за тик TowerManeger, а не на каждую башню)
function Combat.UpdateMobCache()
	local n = #list
	local i = 1
	local alive = 0
	while i <= n do
		local e = list[i]
		if e.removed then
			list[i] = list[n]
			list[n] = nil
			n -= 1
		else
			if e.alive then
				if e.humanoid.Health <= 0 or not e.root.Parent then
					e.alive = false
				else
					local p = e.root.Position
					e.pos = p
					e.progress = Combat.GetProgress(p)
					alive += 1
				end
			end
			i += 1
		end
	end
	aliveCount = alive
end

function Combat.AliveCount()
	return aliveCount
end

function Combat.GetEntry(mob)
	return entries[mob]
end

function Combat.HasTag(mob, tag)
	local e = entries[mob]
	local tags = e and e.tags or infoFor(mob.Name).tags
	return tags[tag] == true
end

function Combat.IsBoss(mob)
	return Combat.HasTag(mob, "Boss")
end

---------------------------------------------------------------- урон

local function creditKill(source)
	if source and typeof(source) == "Instance" and source.Parent then
		source:SetAttribute("Kills", (source:GetAttribute("Kills") or 0) + 1)
	end
end

-- damageType: "Physical" | "Magic" | "True" (True игнорирует сопротивления, но не броню/неуязвимость)
-- возвращает: убит ли моб, сколько урона нанесено
function Combat.Damage(mob, amount, damageType, source)
	if not mob or not amount or amount <= 0 then return false, 0 end
	local e = entries[mob]
	local hum = (e and e.humanoid) or mob:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return false, 0 end

	local taken = SEM.Multiplier(mob, "DamageTaken")
	if taken <= 0 then return false, 0 end -- неуязвим (смена фазы босса)
	amount *= taken

	if damageType == "Physical" or damageType == "Magic" then
		local cfg = (e and e.config) or infoFor(mob.Name).config
		local sp = cfg and cfg.Special
		if sp then
			if damageType == "Physical" and sp.PhysicalDamageReduction then
				amount *= 1 - sp.PhysicalDamageReduction
			elseif damageType == "Magic" and sp.MagicDamageReduction then
				amount *= 1 - sp.MagicDamageReduction
			end
		end
	end

	local shield = mob:GetAttribute("Shield")
	if shield and shield > 0 then
		local absorbed = math.min(shield, amount)
		mob:SetAttribute("Shield", shield - absorbed)
		amount -= absorbed
		if amount <= 0 then return false, absorbed end
	end

	hum:TakeDamage(amount)
	if hum.Health <= 0 then
		if e then e.alive = false end
		creditKill(source)
		return true, amount
	end
	return false, amount
end

-- мгновенное убийство (казнь). Не срабатывает на неуязвимого.
function Combat.Execute(mob, source)
	local e = entries[mob]
	local hum = (e and e.humanoid) or mob:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 or SEM.Has(mob, "Invulnerable") then return false end
	hum.Health = 0
	if e then e.alive = false end
	creditKill(source)
	return true
end

---------------------------------------------------------------- поиск

-- все живые мобы (fn получает запись: e.mob, e.pos, e.humanoid, e.tags, e.boss ...)
function Combat.ForEachMob(fn)
	for _, e in ipairs(list) do
		if e.alive and not e.removed then
			fn(e)
		end
	end
end

-- все живые мобы в радиусе по горизонтали. opts.visibleOnly = невидимых видит только opts.detector
function Combat.ForEachMobInRadius(center, radius, fn, opts)
	local r2 = radius * radius
	local visibleOnly = opts and opts.visibleOnly
	local detector = opts and opts.detector
	for _, e in ipairs(list) do
		if e.alive and not e.removed and not (visibleOnly and e.tags.Stealth and not detector) then
			local dx, dz = e.pos.X - center.X, e.pos.Z - center.Z
			if dx * dx + dz * dz <= r2 then
				fn(e)
			end
		end
	end
end

-- лучшие count целей в радиусе. opts: { melee = bool, detector = bool }
function Combat.GetTargets(center, range, mode, count, opts)
	local best, scores = {}, {}
	if count < 1 then return best end
	local r2 = range * range
	local melee = opts and opts.melee
	local detector = opts and opts.detector
	local k = 0
	for _, e in ipairs(list) do
		if e.alive and not e.removed then
			local tags = e.tags
			if not (melee and tags.Flying) and not (tags.Stealth and not detector) then
				local dx, dz = e.pos.X - center.X, e.pos.Z - center.Z
				local d2 = dx * dx + dz * dz
				if d2 <= r2 then
					local score
					if mode == "Last" then
						score = -e.progress
					elseif mode == "Strongest" then
						score = e.humanoid.Health
					elseif mode == "Closest" then
						score = -d2
					else -- First
						score = e.progress
					end
					local slot
					if k < count then
						k += 1
						slot = k
					elseif score > scores[k] then
						slot = k
					end
					if slot then
						best[slot] = e
						scores[slot] = score
						while slot > 1 and scores[slot] > scores[slot - 1] do
							best[slot], best[slot - 1] = best[slot - 1], best[slot]
							scores[slot], scores[slot - 1] = scores[slot - 1], scores[slot]
							slot -= 1
						end
					end
				end
			end
		end
	end
	return best
end

-- случайный видимый моб в радиусе
function Combat.RandomInRange(center, range, opts)
	local pool = {}
	Combat.ForEachMobInRadius(center, range, function(e)
		table.insert(pool, e)
	end, { visibleOnly = true, detector = opts and opts.detector })
	if #pool == 0 then return nil end
	return pool[math.random(#pool)]
end

-- центр самой плотной толпы в радиусе башни: позиция, сколько мобов рядом, запись моба
function Combat.BestCluster(center, range, radius, opts)
	local cand = {}
	Combat.ForEachMobInRadius(center, range, function(e)
		table.insert(cand, e)
	end, { visibleOnly = true, detector = opts and opts.detector })
	if #cand == 0 then return nil, 0, nil end

	local rr = radius * radius
	local bestE, bestN = nil, -1
	for _, a in ipairs(cand) do
		local n = 0
		for _, b in ipairs(cand) do
			local dx, dz = a.pos.X - b.pos.X, a.pos.Z - b.pos.Z
			if dx * dx + dz * dz <= rr then n += 1 end
		end
		if n > bestN or (n == bestN and a.progress > bestE.progress) then
			bestE, bestN = a, n
		end
	end
	return bestE.pos, bestN, bestE
end

-- цепная молния от startEntry. onHit(entry, damage) — свой обработчик удара (иначе обычный урон)
function Combat.Chain(startEntry, jumps, jumpRange, damage, falloff, damageType, source, hitSet, onHit)
	hitSet = hitSet or {}
	hitSet[startEntry.mob] = true
	local points = {}
	local last = startEntry.pos
	local dmg = damage
	local r2 = jumpRange * jumpRange
	for _ = 1, jumps do
		local nextE, bestD = nil, r2
		for _, e in ipairs(list) do
			if e.alive and not e.removed and not hitSet[e.mob] then
				local d = e.pos - last
				local d2 = d.X * d.X + d.Y * d.Y + d.Z * d.Z
				if d2 < bestD then
					bestD = d2
					nextE = e
				end
			end
		end
		if not nextE then break end
		dmg *= falloff
		table.insert(points, nextE.pos)
		if onHit then
			onHit(nextE, dmg)
		else
			Combat.Damage(nextE.mob, dmg, damageType, source)
		end
		hitSet[nextE.mob] = true
		last = nextE.pos
	end
	return points
end

---------------------------------------------------------------- башни

local towerPos = {}
towersFolder.ChildRemoved:Connect(function(t)
	towerPos[t] = nil
end)

-- центр башни (кэшируется, когда башня окончательно встала — Ready)
function Combat.GetTowerPos(tower)
	local p = towerPos[tower]
	if p then return p end
	local cf = tower:GetBoundingBox()
	p = cf.Position
	if tower:GetAttribute("Ready") then
		towerPos[tower] = p
	end
	return p
end

---------------------------------------------------------------- подключение статус-эффектов

SEM.Hooks.GetInfo = function(target)
	local e = entries[target]
	if e then return e end -- у записи есть поля boss и tags
	if target.Parent == mobsFolder then
		return infoFor(target.Name)
	end
	return nil -- башни: без иммунитетов и ослаблений
end

SEM.Hooks.Damage = function(target, amount, damageType, source)
	Combat.Damage(target, amount, damageType, source)
end

SEM.Start()

return Combat
