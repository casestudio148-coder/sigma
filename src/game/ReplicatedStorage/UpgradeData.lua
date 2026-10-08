-- ReplicatedStorage.UpgradeData (ModuleScript) — ЗАМЕНИТЕ старый код целиком
-- Общий для сервера и клиента расчёт тиров. Сами числа — в TowerData (поле Tiers).
--
--   UpgradeData.get(TowerData, name, tier)      → характеристики башни на тире 0..4 (кеш, только чтение)
--   UpgradeData.getCost(config, nextTier)        → цена перехода на тир nextTier (math.huge, если нельзя)
--   UpgradeData.maxFor(config)                   → сколько тиров у башни (не больше MaxLevel)
--   UpgradeData.describe(TowerData, name, tier)  → короткий текст «что даст тир» для панели
--   UpgradeData.validate(TowerData)              → проверка таблицы, ошибки пишет в Output
--
-- Тир башни хранится в атрибуте Level: 0 — только поставлена, 4 — максимум. Меняет его только сервер.

local UpgradeData = {
	MaxLevel = 4,
}

-- поля тира, которые не являются характеристиками
local META = { Cost = true, SpecialEffect = true, Name = true }
local REQUIRED = { "Cost", "Damage", "Range", "AttackCooldown" }

local function isNumber(v)
	return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

function UpgradeData.maxFor(config)
	local tiers = type(config) == "table" and config.Tiers
	if type(tiers) ~= "table" then return 0 end
	return math.min(#tiers, UpgradeData.MaxLevel)
end

-- любое значение → целый тир в пределах 0..max (NaN, строки, дроби — всё приводится)
local function toTier(value, max)
	local n = tonumber(value)
	if not n or n ~= n then return 0 end
	return math.clamp(math.floor(n), 0, max)
end

function UpgradeData.getCost(config, nextTier)
	if not isNumber(nextTier) or nextTier ~= math.floor(nextTier) then return math.huge end
	if nextTier < 1 or nextTier > UpgradeData.maxFor(config) then return math.huge end
	local cost = config.Tiers[nextTier].Cost
	if not isNumber(cost) or cost < 0 then return math.huge end
	return math.floor(cost)
end

---------------------------------------------------------------- расчёт характеристик

local function build(config, tier)
	local s = table.clone(config)
	s.Tiers = nil
	for i = 1, tier do
		local t = config.Tiers[i]
		for k, v in pairs(t) do
			if not META[k] then
				s[k] = v
			end
		end
		local sp = t.SpecialEffect
		if type(sp) == "table" then
			if type(sp.Stats) == "table" then
				for k, v in pairs(sp.Stats) do
					s[k] = v
				end
			end
			s.Special = sp.Name
			s.SpecialDescription = sp.Description
		end
	end
	s.AttackCooldown = s.AttackCooldown or s.Cooldown or 1
	s.Cooldown = s.AttackCooldown -- старое имя поля
	s.Level = tier
	return table.freeze(s) -- общий кеш: случайно изменить характеристики нельзя
end

local cache = {}

function UpgradeData.get(TowerData, name, tier)
	local config = TowerData[name]
	if type(config) ~= "table" then return nil end
	tier = toTier(tier, UpgradeData.maxFor(config))
	local byName = cache[name]
	if not byName then
		byName = {}
		cache[name] = byName
	end
	local s = byName[tier]
	if not s then
		s = build(config, tier)
		byName[tier] = s
	end
	return s
end

---------------------------------------------------------------- текст для панели

local function num(x)
	if x == math.floor(x) then return tostring(x) end
	return (string.format("%.2f", x):gsub("0+$", ""))
end
local function pct(x)
	return math.floor(x * 100 + 0.5) .. "%"
end

-- как показывать изменения способностей (в этом порядке)
local EXTRA = {
	{ "Detector", function(_, new) return new and "sees hidden" or nil end },
	{ "MultiShot", function(old, new)
		local d = new - (old or 0)
		return d > 0 and ("+" .. d .. (d > 1 and " targets" or " target")) or nil
	end },
	{ "Pierce", function(_, new) return "pierce " .. new end },
	{ "Splash", function(old, new) return old and "bigger blast" or ("splash " .. num(new)) end },
	{ "SlowPercent", function(_, new) return "slow " .. pct(new) end },
	{ "FreezeChance", function(_, new) return "freeze " .. pct(new) end },
	{ "PoisonDamage", function(_, new) return "poison " .. num(new) .. "/s" end },
	{ "BurnDPS", function(_, new) return "burn " .. num(new) .. "/s" end },
	{ "CritChance", function(_, new) return "crit " .. pct(new) end },
	{ "Stun", function(_, new) return "stun " .. num(new) .. "s" end },
	{ "ExecuteHealthPercent", function(_, new) return "execute <" .. pct(new) end },
	{ "PercentMaxHpDamage", function(_, new) return pct(new) .. " max HP" end },
	{ "BuffAuraPercent", function(_, new) return "aura +" .. pct(new) .. " dmg" end },
	{ "HasteAuraPercent", function(_, new) return "aura +" .. pct(new) .. " speed" end },
	{ "AuraRange", function(_, new) return "aura range " .. num(new) end },
	{ "ChainTargets", function(_, new) return "chain " .. new end },
	{ "ChainRange", function(_, new) return "chain range " .. num(new) end },
	{ "SoulBonusCap", function(_, new) return "soul cap +" .. num(new) end },
}

function UpgradeData.describe(TowerData, name, tier)
	local config = TowerData[name]
	if type(tier) ~= "number" or tier < 1 or tier > UpgradeData.maxFor(config) then return "" end
	local sp = config.Tiers[tier].SpecialEffect
	if type(sp) == "table" then
		return string.format("Tier %d ★ %s: %s", tier, sp.Name or "Special", sp.Description or "")
	end
	local a = UpgradeData.get(TowerData, name, tier - 1)
	local b = UpgradeData.get(TowerData, name, tier)
	local parts = {}
	if (b.Damage or 0) > (a.Damage or 0) then table.insert(parts, "+" .. num(b.Damage - a.Damage) .. " damage") end
	if (b.Range or 0) > (a.Range or 0) then table.insert(parts, "+" .. num(b.Range - a.Range) .. " range") end
	if b.AttackCooldown < a.AttackCooldown then
		table.insert(parts, "+" .. pct(a.AttackCooldown / b.AttackCooldown - 1) .. " speed")
	end
	for _, e in ipairs(EXTRA) do
		local k = e[1]
		if b[k] ~= nil and b[k] ~= a[k] then
			local text = e[2](a[k], b[k])
			if text then table.insert(parts, text) end
		end
	end
	return string.format("Tier %d: %s", tier, table.concat(parts, ", "))
end

---------------------------------------------------------------- проверка таблицы

function UpgradeData.validate(TowerData)
	local problems = {}
	for name, cfg in pairs(TowerData) do
		if type(cfg) == "table" then
			local tiers = cfg.Tiers
			if type(tiers) ~= "table" or #tiers ~= UpgradeData.MaxLevel then
				table.insert(problems, string.format("%s: в Tiers должно быть ровно %d тира", name, UpgradeData.MaxLevel))
			else
				for i = 1, #tiers do
					for _, field in ipairs(REQUIRED) do
						local v = tiers[i][field]
						if field == "AttackCooldown" then
							if not isNumber(v) or v <= 0 then
								table.insert(problems, string.format("%s: тир %d — AttackCooldown должно быть числом больше 0", name, i))
							end
						elseif not isNumber(v) or v < 0 then
							table.insert(problems, string.format("%s: тир %d — %s должно быть числом от 0", name, i, field))
						end
					end
				end
				if type(tiers[#tiers].SpecialEffect) ~= "table" then
					table.insert(problems, name .. ": у 4-го тира нет SpecialEffect")
				end
			end
		end
	end
	for _, p in ipairs(problems) do
		warn("[Upgrades] " .. p)
	end
	return #problems == 0, problems
end

return UpgradeData
