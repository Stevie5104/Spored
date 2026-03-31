--!strict
-- DataService: persists player coin balances and part inventories across sessions
-- using Roblox DataStoreService.
--
-- On player join: loads saved coins and inventory, restoring them via the
-- appropriate service APIs.
-- On player leave: saves current coins and inventory.
-- Periodically: auto-saves all active players every SAVE_INTERVAL seconds.
--
-- All DataStore operations are wrapped in pcall so a failed save/load never
-- crashes the server.  If DataStoreService is unavailable (e.g., offline Studio
-- test without API services enabled), the service silently skips persistence.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local CurrencyService = require(script.Parent.CurrencyService)
local LootService = require(script.Parent.LootService)

local DataService = {}

local STORE_NAME = "SporedData_v1"
local SAVE_INTERVAL = 60  -- auto-save every 60 seconds

-- The DataStore instance; nil when DataStoreService is unavailable.
local playerStore: DataStore? = nil

type SaveData = {
	Coins: number,
	Inventory: { [string]: number },
}

local function getKey(player: Player): string
	return "Player_" .. tostring(player.UserId)
end

local function buildSaveData(player: Player): SaveData
	return {
		Coins = CurrencyService.GetBalance(player),
		Inventory = LootService.GetInventory(player),
	}
end

local function loadPlayer(player: Player)
	local store = playerStore
	if not store then return end

	local key = getKey(player)
	local ok, result = pcall(function()
		return store:GetAsync(key)
	end)

	if not ok then
		warn("[DataService] Failed to load data for", player.Name, "–", result)
		return
	end

	if not result then
		-- First-time player: no saved data; defaults from CurrencyService apply.
		return
	end

	local data = result :: SaveData

	-- Restore coin balance (override the default STARTING_COINS assigned on join).
	if type(data.Coins) == "number" and data.Coins >= 0 then
		CurrencyService.SetBalance(player, data.Coins)
	end

	-- Restore part inventory.
	if type(data.Inventory) == "table" then
		LootService.LoadInventory(player, data.Inventory :: { [string]: number })
	end
end

local function savePlayer(player: Player)
	local store = playerStore
	if not store then return end

	local key = getKey(player)
	local data = buildSaveData(player)

	local ok, err = pcall(function()
		store:SetAsync(key, data)
	end)

	if not ok then
		warn("[DataService] Failed to save data for", player.Name, "–", err)
	end
end

function DataService.Init()
	-- Attempt to get the DataStore; gracefully degrade if unavailable.
	local storeOk, storeResult = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if storeOk then
		playerStore = storeResult :: DataStore
	else
		warn("[DataService] DataStoreService unavailable (offline Studio?). Persistence disabled.")
		return
	end

	-- Load data after a short delay to ensure other services (CurrencyService,
	-- LootService) have finished initialising the player state first.
	-- All services are initialised synchronously in init.server.luau before any
	-- player connection can arrive, so 1 second is a conservative safety margin.
	-- A future improvement would be an explicit "services ready" signal rather
	-- than a fixed wait.
	Players.PlayerAdded:Connect(function(player: Player)
		task.wait(1)
		loadPlayer(player)
	end)

	Players.PlayerRemoving:Connect(savePlayer)

	-- Handle any players already in-game at Init time (rare in production).
	for _, player in Players:GetPlayers() do
		task.spawn(function()
			task.wait(1)
			loadPlayer(player)
		end)
	end

	-- Periodic auto-save to reduce data loss on crashes.
	task.spawn(function()
		while true do
			task.wait(SAVE_INTERVAL)
			for _, player in Players:GetPlayers() do
				savePlayer(player)
			end
		end
	end)
end

return DataService
