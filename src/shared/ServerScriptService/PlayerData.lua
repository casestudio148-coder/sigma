-- ServerScriptService.PlayerData (ModuleScript)
-- Сохранение игрока в DataStore: Cash, Gems, Cases, юниты (сколько копий) и счётчики гарантии кейсов.
-- При входе создаёт папку player.Data:
--   Data.Cash / Data.Gems / Data.Cases — IntValue (их уже читают меню, награды за время и итоги матча)
--   Data.Units.<Юнит>                  — IntValue = сколько копий юнита у игрока
-- PlayerData.Meta(player) — таблица для MetaService (ежедневки, коды, квесты, клан, настройки), тоже сохраняется.
-- Остальные скрипты просто меняют эти значения — всё сохранится само (автосейв, выход, закрытие сервера).
-- Не загрузилось на живом сервере → кик, чтобы прогресс сессии не пропал.
-- В Studio без доступа к API всё работает, но не сохраняется (будет предупреждение в Output).
-- Для теста в Studio у игрока сразу есть деньги на кейсы (STUDIO_TEST_MONEY ниже).
-- Модуль запускается при первом require (это делает CaseService).

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local TowerData = require(ReplicatedStorage:WaitForChild("TowerData"))
local CaseConfig = require(ReplicatedStorage:WaitForChild("CaseConfig"))

local PlayerData = {}

local STORE_NAME = "PlayerData_v1"
local AUTOSAVE_EVERY = 60
local CURRENCIES = { "Cash", "Gems", "Cases" }

-- ТЕСТ В STUDIO: столько валюты у каждого игрока, чтобы сразу крутить кейсы.
-- Пока включено, в Studio DataStore не трогается (прогресс не сохраняется, ошибок доступа в Output нет).
-- На живых серверах не работает никогда.
-- Выключить: STUDIO_TEST_MONEY = nil
local STUDIO_TEST_MONEY = { Cash = 100000, Gems = 10000 }

-- РЕЖИМ РАЗРАБОТЧИКА: в Studio у тебя сразу ВСЕ юниты из TowerData (для тестов).
-- Выключить: DEV_ALL_UNITS = false
local DEV_ALL_UNITS = true
-- Хочешь все юниты и в настоящей игре (не в Studio)? Впиши сюда свой UserId, например { 123456789 }.
-- Внимание: там юниты сохранятся у тебя навсегда.
local DEV_USER_IDS = {}

local store = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		warn("[PlayerData] DataStore недоступен: " .. tostring(result))
	end
end

local sessions = {} -- [player] = { currency, units, unitsFolder, unknown, pity, canSave }

local function keyFor(player)
	return "u_" .. player.UserId
end

local function retry(what, fn)
	for attempt = 1, 3 do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		local msg = tostring(result)
		-- Studio без доступа к API: повторять бесполезно, подсказка будет одной строкой
		if string.find(msg, "not allowed") or string.find(msg, "not enabled") or string.find(msg, "publish") then
			return false, nil
		end
		warn(string.format("[PlayerData] %s, попытка %d: %s", what, attempt, msg))
		if attempt < 3 then
			task.wait(attempt * 2)
		end
	end
	return false, nil
end

local function intValue(name, value, parent)
	local v = Instance.new("IntValue")
	v.Name = name
	v.Value = value
	v.Parent = parent
	return v
end

-- счётчики гарантии → атрибуты игрока (окно кейсов показывает «Epic in 12»)
local function publishPity(player, s, caseId)
	local def = CaseConfig.Cases[caseId]
	if not def or not def.Pity then return end
	local p = s.pity[caseId] or {}
	for rarity in pairs(def.Pity) do
		player:SetAttribute("Pity_" .. caseId .. "_" .. rarity, p[rarity] or 0)
	end
end

local function loadPlayer(player)
	if sessions[player] then return end
	local studio = RunService:IsStudio()
	local testMoney = studio and STUDIO_TEST_MONEY or nil
	local saved, canSave = nil, false
	if store and not testMoney then -- в тестовом режиме DataStore не трогаем вообще
		local ok, result = retry("загрузка " .. player.Name, function()
			return store:GetAsync(keyFor(player))
		end)
		if ok then
			saved, canSave = result, true
		end
	end
	if not player.Parent or sessions[player] then return end -- вышел, пока грузили

	if not canSave and not studio then
		player:Kick("Couldn't load your data. Please rejoin!")
		return
	end
	if testMoney then
		print(string.format("[PlayerData] Studio, тестовый режим: %s Cash, %s Gems, прогресс не сохраняется",
			tostring(testMoney.Cash or 0), tostring(testMoney.Gems or 0)))
	elseif not canSave then
		warn("[PlayerData] Studio: нет доступа к DataStore, прогресс не сохраняется. Включить: Game Settings → Security → Enable Studio Access to API Services")
	end

	saved = type(saved) == "table" and saved or {}
	local s = {
		currency = {},
		units = {},
		unknown = {},
		pity = type(saved.Pity) == "table" and saved.Pity or {},
		meta = type(saved.Meta) == "table" and saved.Meta or {},
		canSave = canSave,
	}

	local folder = Instance.new("Folder")
	folder.Name = "Data"
	for _, name in ipairs(CURRENCIES) do
		s.currency[name] = intValue(name, math.max(0, math.floor(tonumber(saved[name]) or 0)), folder)
	end
	for name, amount in pairs(testMoney or {}) do
		local v = s.currency[name]
		if v and v.Value < amount then
			v.Value = amount
		end
	end
	s.unitsFolder = Instance.new("Folder")
	s.unitsFolder.Name = "Units"
	s.unitsFolder.Parent = folder

	local units = type(saved.Units) == "table" and saved.Units or {}
	for _, name in ipairs(CaseConfig.StarterUnits) do
		units[name] = units[name] or 1
	end
	if (studio and DEV_ALL_UNITS) or table.find(DEV_USER_IDS, player.UserId) then
		for name in pairs(TowerData) do
			units[name] = units[name] or 1
		end
		print("[PlayerData] Режим разработчика: у " .. player.Name .. " все юниты")
	end
	for name, count in pairs(units) do
		count = math.max(1, math.floor(tonumber(count) or 1))
		if TowerData[name] then
			s.units[name] = intValue(name, count, s.unitsFolder)
		else
			s.unknown[name] = count -- юнита убрали из игры: не показываем, но и не теряем
		end
	end

	sessions[player] = s
	s.lastJson = PlayerData._json(s) -- что сейчас лежит в DataStore (лишний раз не перезаписываем)
	folder.Parent = player -- папка появляется уже заполненной
	for caseId in pairs(CaseConfig.Cases) do
		publishPity(player, s, caseId)
	end
end

local function snapshot(s)
	local data = { Version = 1, Pity = s.pity, Meta = s.meta, Units = {} }
	for name, v in pairs(s.currency) do
		data[name] = v.Value
	end
	for name, v in pairs(s.units) do
		data.Units[name] = v.Value
	end
	for name, count in pairs(s.unknown) do
		data.Units[name] = count
	end
	return data
end

function PlayerData._json(s)
	local ok, json = pcall(function()
		return HttpService:JSONEncode(snapshot(s))
	end)
	return ok and json or nil
end

-- сохранить сейчас. Записи идут по очереди, а данные снимаются, когда подошла очередь,
-- поэтому последняя запись всегда самая свежая (автосейв, выход и телепорт не перетирают друг друга).
-- Если с прошлого сохранения ничего не поменялось — запись пропускается.
function PlayerData.Save(player)
	local s = sessions[player]
	if not s or not s.canSave or not store then return false end
	-- ждём своей очереди, и только потом снимаем данные: последняя запись всегда самая свежая
	while s.saving do
		task.wait(0.1)
	end
	s.saving = true
	local okJson, json = pcall(function()
		return HttpService:JSONEncode(snapshot(s))
	end)
	if okJson and json == s.lastJson then
		s.saving = false
		return true
	end
	-- пишем неизменяемую копию (живые таблицы могут поменяться, пока идёт запись)
	local data = okJson and HttpService:JSONDecode(json) or snapshot(s)
	local ok = retry("сохранение " .. player.Name, function()
		store:UpdateAsync(keyFor(player), function()
			return data
		end)
	end)
	s.saving = false
	if ok and okJson then
		s.lastJson = json
	end
	return ok
end

-- можно ли телепортировать игрока: прогресс сохранён (или сохранять нечего)
function PlayerData.SaveBeforeTeleport(player)
	local s = sessions[player]
	if not s or s.closing or not s.canSave or not store then
		return true
	end
	return PlayerData.Save(player)
end

local function finish(player)
	local s = sessions[player]
	if not s or s.closing then return end
	s.closing = true
	PlayerData.Save(player)
	sessions[player] = nil
end

---------------------------------------------------------------- API для других серверных скриптов

-- сессия игрока или nil, пока данные грузятся
function PlayerData.Get(player)
	local s = sessions[player]
	return (s and not s.closing) and s or nil
end

-- IntValue валюты: "Cash" / "Gems" / "Cases"
function PlayerData.Wallet(player, currency)
	local s = sessions[player]
	return s and s.currency[currency] or nil
end

function PlayerData.Owns(player, unit)
	local s = sessions[player]
	return s ~= nil and s.units[unit] ~= nil
end

-- +1 копия юнита. Вернёт: сколько копий стало, новый ли это юнит
function PlayerData.AddUnit(player, unit)
	local s = sessions[player]
	if not s or not TowerData[unit] then return 0, false end
	local v = s.units[unit]
	if v then
		v.Value += 1
		return v.Value, false
	end
	s.units[unit] = intValue(unit, 1, s.unitsFolder)
	return 1, true
end

-- таблица MetaService (меняйте поля прямо в ней — сохранится при автосейве / выходе)
function PlayerData.Meta(player)
	local s = sessions[player]
	return s and s.meta or nil
end

-- выдать валюту (Cash / Gems / Cases)
function PlayerData.Give(player, currency, amount)
	local v = PlayerData.Wallet(player, currency)
	if v and amount and amount > 0 then
		v.Value += math.floor(amount)
		return true
	end
	return false
end

function PlayerData.GetPity(player, caseId)
	local s = sessions[player]
	return table.clone((s and s.pity[caseId]) or {})
end

function PlayerData.SetPity(player, caseId, pity)
	local s = sessions[player]
	if not s then return end
	s.pity[caseId] = pity
	publishPity(player, s, caseId)
end

---------------------------------------------------------------- запуск

Players.PlayerAdded:Connect(loadPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(loadPlayer, player)
end
Players.PlayerRemoving:Connect(finish)

task.spawn(function()
	while true do
		task.wait(AUTOSAVE_EVERY)
		for player, s in pairs(sessions) do
			if not s.closing then
				task.spawn(PlayerData.Save, player)
			end
		end
	end
end)

game:BindToClose(function()
	for player in pairs(sessions) do
		task.spawn(finish, player)
	end
	local started = os.clock()
	while next(sessions) and os.clock() - started < 25 do
		task.wait(0.2)
	end
end)

return PlayerData
