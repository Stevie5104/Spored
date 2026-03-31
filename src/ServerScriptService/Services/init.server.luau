--!strict
-- Services init: bootstraps all server services.

local CurrencyService = require(script.Parent.CurrencyService)
local CombatService = require(script.Parent.CombatService)
local PlayerBuildService = require(script.Parent.PlayerBuildService)
local EnemyService = require(script.Parent.EnemyService)

-- LootService is required by EnemyService; no direct Init needed.

CurrencyService.Init()
CombatService.Init()
PlayerBuildService.Init()
EnemyService.Init()

print("[Services] All server services initialized.")
