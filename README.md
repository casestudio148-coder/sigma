# sigma

Roblox Tower Defense: два места — хаб (лобби) и игра (матч). Код синхронизируется через [Rojo](https://rojo.space).

```
rojo serve hub.project.json    # место-хаб
rojo serve game.project.json   # место с матчем
```

- `src/shared` — общий код обоих мест (конфиги, PlayerData, MetaService, CaseService, UI меню и кейсов…)
- `src/hub` — только хаб (HubBuilder, HubService, HubClient)
- `src/game` — только матч (башни, мобы, боссы, карты, HUD…)

Скрипты `Animate` внутри моделей `ReplicatedStorage.Towers` / `ReplicatedStorage.Mobs` лежат в `src/*/Models`,
но в проекты Rojo не подключены (Rojo пересоздал бы модели) — их правят в Studio вручную.
Все сервисы в проектах помечены `$ignoreUnknownInstances`, поэтому модели, ремоуты и прочее из Studio не удаляются.
