--!strict
-- Services init: bootstraps all server services.

local CurrencyService  = require(script.Parent.CurrencyService)
local CombatService    = require(script.Parent.CombatService)
local PlayerBuildService = require(script.Parent.PlayerBuildService)
local LootService      = require(script.Parent.LootService)
local EnemyService     = require(script.Parent.EnemyService)
local DataService      = require(script.Parent.DataService)
local OrganismService  = require(script.Parent.OrganismService)

-- Initialization order matters:
-- 1. OrganismService: must run first to disable CharacterAutoLoads before any
--    player connects and to spawn organisms for already-connected players.
-- 2. CurrencyService: must be ready before LootService can award coins.
-- 3. LootService: must be ready before EnemyService death handlers fire.
-- 4. CombatService: wires the PartAttack remote.
-- 5. PlayerBuildService: wires build remotes and BuildChanged event.
-- 6. EnemyService: spawns enemies and starts AI loop.
-- 7. DataService: connects DataStore save/load AFTER all state services are ready.

OrganismService.Init()
CurrencyService.Init()
LootService.Init()
CombatService.Init()
PlayerBuildService.Init()
EnemyService.Init()
DataService.Init()

print("[Services] All server services initialized.")
