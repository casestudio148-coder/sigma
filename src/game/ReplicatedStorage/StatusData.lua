-- ReplicatedStorage.StatusData (ModuleScript) — общая таблица статус-эффектов (сервер + клиент)
--
--   Bit           — бит в атрибуте "Status" у модели. Клиент рисует эффекты по ОДНОМУ числу.
--   Kind          — "CC"       контроль на время (стан, заморозка, отключение башни...)
--                   "Modifier" множитель стата; от разных источников берётся СИЛЬНЕЙШИЙ (не суммируется)
--                   "DoT"      урон со временем (горение копит стаки, яд обновляется)
--   Stat / Sign   — какой стат меняет модификатор: Sign = -1 уменьшает, +1 увеличивает
--   Cap           — предел силы (0.8 = максимум 80%)
--   StopsMovement — пока эффект висит, моб стоит
--   Debuff        — снимается «очищением» (босс при смене фазы)
--   ImmuneTag     — тег моба из MobData, дающий иммунитет к эффекту
--   BossDuration / BossMagnitude — множитель для боссов (0.25 = стан на 75% короче)
--   DR            — убывающая эффективность при частом контроле (против вечного стана)
--   ShowIcon      — показывать значок над головой

local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end

local StatusData = {}

StatusData.Effects = {
	Stun = {
		Bit = 1, Kind = "CC", StopsMovement = true, Debuff = true, DR = true,
		ImmuneTag = "ImmuneToStun", BossDuration = 0.25,
		Icon = "💫", Color = rgb(255, 230, 120), ShowIcon = true,
	},
	Freeze = {
		Bit = 2, Kind = "CC", StopsMovement = true, Debuff = true, DR = true,
		ImmuneTag = "ImmuneToStun", BossDuration = 0.25,
		Icon = "🧊", Color = rgb(150, 225, 255), ShowIcon = true,
	},
	Slow = {
		Bit = 4, Kind = "Modifier", Stat = "MoveSpeed", Sign = -1, Cap = 0.8, Debuff = true,
		ImmuneTag = "ImmuneToSlow", BossMagnitude = 0.5,
		Icon = "🐌", Color = rgb(90, 170, 255), ShowIcon = true,
	},
	Haste = {
		Bit = 8, Kind = "Modifier", Stat = "MoveSpeed", Sign = 1, Cap = 1,
		Icon = "💨", Color = rgb(255, 150, 60), ShowIcon = true,
	},
	Burn = {
		Bit = 16, Kind = "DoT", Tick = 0.5, MaxStacks = 5, DamageType = "True", Debuff = true,
		ImmuneTag = "ImmuneToBurn",
		Icon = "🔥", Color = rgb(255, 120, 40), ShowIcon = true,
	},
	Poison = {
		Bit = 32, Kind = "DoT", Tick = 1, MaxStacks = 1, DamageType = "True", Debuff = true,
		ImmuneTag = "ImmuneToPoison",
		Icon = "☠️", Color = rgb(120, 240, 80), ShowIcon = true,
	},
	Armor = {
		Bit = 64, Kind = "Modifier", Stat = "DamageTaken", Sign = -1, Cap = 0.9,
		Icon = "🛡️", Color = rgb(200, 210, 230), ShowIcon = false,
	},
	Vulnerable = {
		Bit = 128, Kind = "Modifier", Stat = "DamageTaken", Sign = 1, Cap = 2, Debuff = true,
		Icon = "💔", Color = rgb(255, 70, 110), ShowIcon = true,
	},
	AttackHaste = {
		Bit = 256, Kind = "Modifier", Stat = "AttackSpeed", Sign = 1, Cap = 2,
		Icon = "⚡", Color = rgb(255, 230, 90), ShowIcon = false,
	},
	Empower = {
		Bit = 512, Kind = "Modifier", Stat = "Damage", Sign = 1, Cap = 2,
		Icon = "⚔️", Color = rgb(255, 170, 60), ShowIcon = false,
	},
	Disabled = {
		Bit = 1024, Kind = "CC", Debuff = true,
		Icon = "⛓️", Color = rgb(150, 60, 230), ShowIcon = true,
	},
	Invulnerable = {
		Bit = 2048, Kind = "CC",
		Icon = "✨", Color = rgb(255, 235, 150), ShowIcon = true,
	},
	Transform = {
		Bit = 4096, Kind = "CC", StopsMovement = true,
		Icon = "", Color = rgb(255, 80, 80), ShowIcon = false,
	},
}

-- порядок значков над головой
StatusData.Order = {
	"Freeze", "Stun", "Disabled", "Invulnerable", "Burn", "Poison", "Slow", "Vulnerable",
	"Haste", "Armor", "AttackHaste", "Empower", "Transform",
}

for id, def in pairs(StatusData.Effects) do
	def.Id = id
end

-- маска -> список эффектов в порядке Order
function StatusData.Decode(mask)
	local out = {}
	if not mask or mask == 0 then return out end
	for _, id in ipairs(StatusData.Order) do
		local def = StatusData.Effects[id]
		if def and bit32.band(mask, def.Bit) ~= 0 then
			table.insert(out, def)
		end
	end
	return out
end

return StatusData
