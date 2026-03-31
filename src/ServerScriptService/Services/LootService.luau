--!strict
-- LootService: resolves enemy drop tables into coin and part drops for a player.
-- Maintains a server-side in-memory part inventory and notifies the client of drops.

local CurrencyService = require(script.Parent.CurrencyService)
local EnemyData = require(game:GetService("ReplicatedStorage").Modules.EnemyData)

local LootService = {}

-- Per-player part inventory: inventories[userId][partId] = count
local inventories: { [number]: { [string]: number } } = {}

-- RemoteEvent for notifying the client about received loot.
local lootDropRemote: RemoteEvent? = nil

local function getInventory(player: Player): { [string]: number }
	if not inventories[player.UserId] then
		inventories[player.UserId] = {}
	end
	return inventories[player.UserId]
end

-- Clean up inventory state on player leave.
local function cleanPlayer(player: Player)
	inventories[player.UserId] = nil
end

-- Weighted random selection from a drop table.
local function rollDrop(dropTable: { [number]: EnemyData.DropEntry }): EnemyData.DropEntry?
	local totalWeight = 0
	for _, entry in dropTable do
		totalWeight += entry.Weight
	end

	local roll = math.random() * totalWeight
	local cumulative = 0
	for _, entry in dropTable do
		cumulative += entry.Weight
		if roll <= cumulative then
			return entry
		end
	end
	return nil
end

-- Award loot to a player from a killed enemy type.
-- Returns a description of what was awarded (for logging/feedback).
function LootService.AwardLoot(player: Player, enemyTypeId: string): { Type: string, Detail: string }?
	local enemyDef = EnemyData[enemyTypeId]
	if not enemyDef then
		warn("LootService.AwardLoot: unknown enemy type:", enemyTypeId)
		return nil
	end

	local drop = rollDrop(enemyDef.DropTable)
	if not drop then
		return nil
	end

	if drop.Type == "Coins" then
		local amount = drop.Amount or 0
		CurrencyService.AddCoins(player, amount)

		-- Notify the client.
		if lootDropRemote then
			lootDropRemote:FireClient(player, "Coins", tostring(amount), "")
		end
		return { Type = "Coins", Detail = tostring(amount) }

	elseif drop.Type == "Part" then
		local partId = drop.Id or "Unknown"
		local rarity = drop.Rarity or "Common"

		-- Add to server-side inventory.
		local inv = getInventory(player)
		inv[partId] = (inv[partId] or 0) + 1

		-- Notify the client so it can update any UI or play a drop animation.
		if lootDropRemote then
			lootDropRemote:FireClient(player, "Part", partId, rarity)
		end

		print(string.format("[LootService] %s received part drop: %s (%s)", player.Name, partId, rarity))
		return { Type = "Part", Detail = partId .. " [" .. rarity .. "]" }
	end

	return nil
end

-- Returns the part inventory for a player (read-only by convention).
function LootService.GetInventory(player: Player): { [string]: number }
	return getInventory(player)
end

function LootService.Init()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local remoteFolder = ReplicatedStorage:FindFirstChild("Remotes")
	if not remoteFolder then
		local folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
		remoteFolder = folder
	end

	-- LootDrop: fires to client when they receive a loot item.
	-- Args: dropType ("Coins"|"Part"), itemId (string), rarity (string)
	local remote = remoteFolder:FindFirstChild("LootDrop") :: RemoteEvent?
	if not remote then
		local r = Instance.new("RemoteEvent")
		r.Name = "LootDrop"
		r.Parent = remoteFolder
		remote = r
	end
	lootDropRemote = remote

	game:GetService("Players").PlayerRemoving:Connect(cleanPlayer)
end

return LootService
