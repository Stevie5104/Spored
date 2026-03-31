--!strict
-- Services init: bootstraps all server services.

local CharacterService   = require(script.Parent.CharacterService)
local CurrencyService    = require(script.Parent.CurrencyService)
local CombatService      = require(script.Parent.CombatService)
local PlayerBuildService = require(script.Parent.PlayerBuildService)
local LootService = require(script.Parent.LootService)
local EnemyService = require(script.Parent.EnemyService)
local DataService = require(script.Parent.DataService)

-- Initialization order matters:
-- 0. CharacterService: must disable CharacterAutoLoads and register
--    PlayerAdded BEFORE any player can join.
-- 1. CurrencyService: must be ready before LootService can award coins.
-- 2. LootService: must be ready before EnemyService death handlers fire.
-- 3. CombatService: wires the PartAttack remote.
-- 4. PlayerBuildService: wires build remotes and BuildChanged event.
-- 5. EnemyService: spawns enemies and starts AI loop.
-- 6. DataService: connects DataStore save/load AFTER all state services are ready.

CharacterService.Init()
CurrencyService.Init()
LootService.Init()
CombatService.Init()
PlayerBuildService.Init()
EnemyService.Init()
DataService.Init()

print("[Services] All server services initialized.")
