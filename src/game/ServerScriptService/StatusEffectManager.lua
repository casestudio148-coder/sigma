-- ServerScriptService.StatusEffectManager (ModuleScript)
-- Универсальный менеджер статус-эффектов для мобов и башен:
--   стан, заморозка, замедление, ускорение, горение и яд (урон со временем),
--   броня, уязвимость, бафы башен (скорость атаки, урон), отключение башни, неуязвимость.
--
-- Почему не лагает и не течёт память:
--   • ОДИН цикл на весь сервер (20 раз в секунду) вместо отдельного потока на каждый эффект;
--   • эффекты — это записи в таблице, а не task.delay: нечего «забыть отменить»;
--   • модель удалили → её запись удаляется сама (Destroying), соединение отключается;
--   • клиенту уходит ОДИН атрибут "Status" (битовая маска) и только когда набор эффектов изменился.
--
-- API:
--   SEM.Apply(target, "Slow", { Magnitude = 0.4, Duration = 2, Source = tower })
--   SEM.Apply(target, "Burn", { Magnitude = 6, Duration = 3, Source = tower, MaxStacks = 3 })  -- 6 урона/с за стак
--   SEM.Remove(target, "Slow" [, key])    SEM.Cleanse(target)    SEM.Clear(target)
--   SEM.Has(target, "Stun")               SEM.Value(target, "Burn")  -- сила / стаки
--   SEM.Multiplier(target, "MoveSpeed" | "DamageTaken" | "AttackSpeed" | "Damage")
--   SEM.RefreshSpeed(mob)                 -- пересчитать WalkSpeed после смены атрибута BaseSpeed
--
-- Параметры Apply:
--   Duration  — секунды (math.huge = пока не снимут вручную)
--   Magnitude — сила: для Modifier доля (0.4 = 40%), для DoT урон в секунду за 1 стак
--   Source    — кто наложил (башня): ей засчитывается убийство от DoT
--   Key       — «источник» для модификаторов (по умолчанию Source). Один ключ = одна запись.
--   Stacks / MaxStacks — для горения

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StatusData = require(ReplicatedStorage:WaitForChild("StatusData"))

local Defs = StatusData.Effects

local SEM = {}

SEM.Config = {
	TickRate = 0.05,    -- как часто обновляются эффекты (сек)
	MinDuration = 0.05, -- после всех ослаблений эффект короче этого не вешается
	DR = {
		BossOnly = true,                -- убывающая эффективность контроля только для боссов
		Window = 4,                     -- окно в секундах (отсчёт от первого контроля)
		Factors = { 1, 0.6, 0.35, 0.2 }, -- 1-й контроль 100%, 2-й 60%, 3-й 35%, дальше 20%
	},
}

-- подключаются из CombatService
SEM.Hooks = {
	Damage = nil, -- function(target, amount, damageType, source, effectId)
	GetInfo = function(_target)
		return nil -- { boss = bool, tags = { [tag] = true } }
	end,
}

SEM._now = os.clock -- можно подменить в тестах

local records = {} -- [target] = запись
local active = {}  -- массив записей для быстрого обхода

local statEffects = {} -- [stat] = { id, ... }
for id, def in pairs(Defs) do
	if def.Stat then
		statEffects[def.Stat] = statEffects[def.Stat] or {}
		table.insert(statEffects[def.Stat], id)
	end
end

---------------------------------------------------------------- записи

local function drActive(rec, t)
	return rec.dr ~= nil and t < rec.dr.resetAt
end

local function release(rec)
	if rec.dead then return end
	rec.dead = true
	rec.effects = {}
	rec.dr = nil
	if rec.conn then
		rec.conn:Disconnect()
		rec.conn = nil
	end
	if records[rec.target] == rec then
		records[rec.target] = nil
	end
	-- из массива active запись уберёт Step
end

local function getRecord(target, create)
	local rec = records[target]
	if rec or not create then
		return rec
	end
	rec = {
		target = target,
		effects = {},
		mask = target:GetAttribute("Status") or 0,
		humanoid = target:FindFirstChildOfClass("Humanoid"),
		dead = false,
	}
	rec.conn = target.Destroying:Connect(function()
		SEM.Clear(target, true)
	end)
	records[target] = rec
	table.insert(active, rec)
	return rec
end

local function strongest(e, def)
	local best = 0
	for _, s in pairs(e.sources) do
		if s.mag > best then best = s.mag end
	end
	if def.Cap and best > def.Cap then best = def.Cap end
	return best
end

---------------------------------------------------------------- множители

function SEM.Multiplier(target, stat)
	local rec = records[target]
	if not rec then return 1 end
	local fx = rec.effects
	if stat == "MoveSpeed" then
		for id in pairs(fx) do
			if Defs[id].StopsMovement then return 0 end
		end
	elseif stat == "DamageTaken" and fx.Invulnerable then
		return 0
	end
	local m = 1
	local ids = statEffects[stat]
	if ids then
		for _, id in ipairs(ids) do
			local e = fx[id]
			if e and e.value > 0 then
				if Defs[id].Sign < 0 then
					m *= 1 - e.value
				else
					m *= 1 + e.value
				end
			end
		end
	end
	return m
end

-- скорость меняем только мобам: у них есть атрибут BaseSpeed (у башен его нет)
function SEM.RefreshSpeed(target)
	local base = target:GetAttribute("BaseSpeed")
	if type(base) ~= "number" then return end
	local rec = records[target]
	local hum = (rec and rec.humanoid) or target:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	local speed = base * SEM.Multiplier(target, "MoveSpeed")
	if math.abs(hum.WalkSpeed - speed) > 0.01 then
		hum.WalkSpeed = speed
	end
end

-- записать маску для клиента, обновить скорость, освободить пустую запись
local function sync(rec)
	if rec.dead then return end
	local mask = 0
	for id in pairs(rec.effects) do
		mask = bit32.bor(mask, Defs[id].Bit)
	end
	local target = rec.target
	if mask ~= rec.mask then
		rec.mask = mask
		target:SetAttribute("Status", if mask ~= 0 then mask else nil)
	end
	SEM.RefreshSpeed(target)
	if next(rec.effects) == nil and not drActive(rec, SEM._now()) then
		release(rec)
	end
end

---------------------------------------------------------------- наложить / снять

function SEM.Apply(target, id, params)
	local def = Defs[id]
	if not def then
		warn("[StatusEffects] неизвестный эффект: " .. tostring(id))
		return false
	end
	if not target or not target.Parent then return false end
	params = params or {}

	local info = SEM.Hooks.GetInfo(target)
	if info and def.ImmuneTag and info.tags and info.tags[def.ImmuneTag] then
		return false
	end
	local isBoss = info ~= nil and info.boss == true

	local existing = records[target]
	if existing and existing.dead then existing = nil end

	-- мёртвым мобам эффекты не вешаем
	local hum = (existing and existing.humanoid) or target:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health <= 0 and target:GetAttribute("BaseSpeed") then
		return false
	end

	local t = SEM._now()
	local duration = params.Duration or 1
	local magnitude = params.Magnitude or 0

	if isBoss then
		if def.BossDuration and duration ~= math.huge then duration *= def.BossDuration end
		if def.BossMagnitude then magnitude *= def.BossMagnitude end
	end

	local rec = existing
	local dr
	if def.DR and duration ~= math.huge and (isBoss or not SEM.Config.DR.BossOnly) then
		dr = rec and rec.dr
		if not dr or t >= dr.resetAt then
			dr = { count = 0, resetAt = t + SEM.Config.DR.Window }
		end
		local factors = SEM.Config.DR.Factors
		duration *= factors[math.min(dr.count + 1, #factors)]
	end

	local e = rec and rec.effects[id]
	if duration < SEM.Config.MinDuration
		or ((def.Kind == "Modifier" or def.Kind == "DoT") and magnitude <= 0 and not e) then
		return false
	end

	rec = rec or getRecord(target, true)
	if dr then
		-- в DR засчитывается только контроль, который реально наложился
		dr.count += 1
		rec.dr = dr
	end
	local fx = rec.effects
	e = fx[id]
	local expires = t + duration

	if def.Kind == "CC" then
		if e then
			if expires > e.expires then e.expires = expires end
		else
			fx[id] = { expires = expires, value = 1 }
		end

	elseif def.Kind == "Modifier" then
		if not e then
			e = { sources = {}, value = 0 }
			fx[id] = e
		end
		local key = params.Key or params.Source or "_"
		local s = e.sources[key]
		if s then
			s.mag = magnitude
			if expires > s.expires then s.expires = expires end
		else
			e.sources[key] = { mag = magnitude, expires = expires }
		end
		e.value = strongest(e, def)

	elseif def.Kind == "DoT" then
		local cap = def.MaxStacks or 1
		local maxStacks = math.min(params.MaxStacks or cap, cap)
		if not e then
			e = { stacks = 0, dps = 0, expires = 0, nextTick = t + def.Tick, value = 0 }
			fx[id] = e
		end
		-- источник с меньшим лимитом стаков не срезает уже набранные (Метеор 5 → Бомбер 3 = остаётся 5)
		e.stacks = math.max(e.stacks, math.min(maxStacks, e.stacks + (params.Stacks or 1)))
		e.value = e.stacks
		if magnitude > e.dps then e.dps = magnitude end
		if expires > e.expires then e.expires = expires end
		e.source = params.Source or e.source
		e.damageType = params.DamageType or e.damageType or def.DamageType or "True"
	end

	sync(rec)
	return true
end

function SEM.Remove(target, id, key)
	local rec = records[target]
	if not rec then return end
	local e = rec.effects[id]
	if not e then return end
	if key ~= nil and e.sources then
		e.sources[key] = nil
		if next(e.sources) == nil then
			rec.effects[id] = nil
		else
			e.value = strongest(e, Defs[id])
		end
	else
		rec.effects[id] = nil
	end
	sync(rec)
end

-- снять все дебафы (замедление, стан, горение, яд, уязвимость...)
function SEM.Cleanse(target)
	local rec = records[target]
	if not rec then return end
	for id in pairs(rec.effects) do
		if Defs[id].Debuff then
			rec.effects[id] = nil
		end
	end
	sync(rec)
end

-- снять всё (destroying = модель удаляется, атрибуты не трогаем)
function SEM.Clear(target, destroying)
	local rec = records[target]
	if not rec then return end
	rec.effects = {}
	if not destroying and target.Parent then
		if rec.mask ~= 0 then
			rec.mask = 0
			target:SetAttribute("Status", nil)
		end
		SEM.RefreshSpeed(target)
	end
	release(rec)
end

---------------------------------------------------------------- запросы

function SEM.Has(target, id)
	local rec = records[target]
	return rec ~= nil and rec.effects[id] ~= nil
end

function SEM.Value(target, id)
	local rec = records[target]
	local e = rec and rec.effects[id]
	return e and e.value or 0
end

function SEM.IsStunned(target)
	local rec = records[target]
	if not rec then return false end
	for id in pairs(rec.effects) do
		if Defs[id].StopsMovement then return true end
	end
	return false
end

-- для отладки утечек: сколько целей сейчас с эффектами
function SEM.Stats()
	local n = 0
	for _ in pairs(records) do n += 1 end
	return n, #active
end

---------------------------------------------------------------- общий цикл

local scratch = {}

local function stepRecord(rec, t, Damage)
	local n = 0
	for id in pairs(rec.effects) do
		n += 1
		scratch[n] = id
	end

	local changed = false
	for k = 1, n do
		local id = scratch[k]
		scratch[k] = nil
		local e = (not rec.dead) and rec.effects[id] or nil
		if e then
			local def = Defs[id]
			if def.Kind == "Modifier" then
				local any = false
				for key, s in pairs(e.sources) do
					if t >= s.expires then
						e.sources[key] = nil
					else
						any = true
					end
				end
				if not any then
					rec.effects[id] = nil
					changed = true
				else
					local v = strongest(e, def)
					if v ~= e.value then
						e.value = v
						changed = true
					end
				end
			else
				if def.Kind == "DoT" and Damage then
					while not rec.dead and e.nextTick <= t and e.nextTick <= e.expires do
						Damage(rec.target, e.dps * e.stacks * def.Tick, e.damageType, e.source, id)
						e.nextTick += def.Tick
					end
				end
				if not rec.dead and t >= e.expires then
					rec.effects[id] = nil
					changed = true
				end
			end
		end
	end

	if rec.dead then return end
	if changed then
		sync(rec)
	elseif next(rec.effects) == nil and not drActive(rec, t) then
		release(rec)
	end
end

function SEM.Step(t)
	local Damage = SEM.Hooks.Damage
	local i = #active
	while i > 0 do
		local rec = active[i]
		if not rec.dead and not rec.target.Parent then
			release(rec) -- модель убрали из игры
		end
		if rec.dead then
			local last = #active
			active[i] = active[last]
			active[last] = nil
		else
			stepRecord(rec, t, Damage)
		end
		i -= 1
	end
end

local started = false
function SEM.Start()
	if started then return end
	started = true
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < SEM.Config.TickRate then return end
		acc = 0
		local ok, err = pcall(SEM.Step, SEM._now())
		if not ok then
			warn("[StatusEffects] " .. tostring(err))
		end
	end)
end

return SEM
