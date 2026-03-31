--!strict
-- LootService: resolves enemy drop tables into coin and part drops for a player.

local CurrencyService = require(script.Parent.CurrencyService)
local EnemyData = require(game:GetService("ReplicatedStorage").Modules.EnemyData)

local LootService = {}

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
		return { Type = "Coins", Detail = tostring(amount) }

	elseif drop.Type == "Part" then
		-- Foundation stub: part item grant would be implemented when inventory system exists.
		-- For now, record the award for wiring.
		local partId = drop.Id or "Unknown"
		local rarity = drop.Rarity or "Common"
		print(string.format("[LootService] %s received part drop: %s (%s)", player.Name, partId, rarity))
		return { Type = "Part", Detail = partId .. " [" .. rarity .. "]" }
	end

	return nil
end

return LootService
