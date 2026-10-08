-- ReplicatedStorage.PlaceConfig (ModuleScript) — ОДИН И ТОТ ЖЕ в обоих местах: в хабе и в игре.
-- ID мест взять так: Studio → View → Asset Manager → Places →
--   правый клик по месту → Copy ID to clipboard → вставить число ниже.

local PlaceConfig = {
	HubPlaceId = 74615684419171,  -- место-ХАБ (лобби с порталами)
	GamePlaceId = 99998687762663, -- место с КАРТОЙ МАТЧА

	MaxParty = 4,    -- сколько игроков помещается в один портал
	QueueTime = 15,  -- секунд ожидания, пока собирается отряд
	FullTime = 5,    -- отряд собрался полностью → старт через столько секунд
	ReturnDelay = 30, -- после конца матча через столько секунд всех вернёт в хаб

	-- игрок зашёл в место с картой напрямую (с сайта, а не через портал) → отправить его в хаб
	RedirectToHub = true,
}

return PlaceConfig
