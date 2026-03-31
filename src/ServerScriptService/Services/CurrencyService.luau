--!strict
-- CurrencyService: maintains per-player coin balances with safe server-only APIs.

local Players = game:GetService("Players")

local CurrencyService = {}

local balances: { [number]: number } = {}

local STARTING_COINS = 50

local function initPlayer(player: Player)
	balances[player.UserId] = STARTING_COINS
end

local function cleanPlayer(player: Player)
	balances[player.UserId] = nil
end

function CurrencyService.Init()
	Players.PlayerAdded:Connect(initPlayer)
	Players.PlayerRemoving:Connect(cleanPlayer)
	for _, player in Players:GetPlayers() do
		initPlayer(player)
	end
end

function CurrencyService.GetBalance(player: Player): number
	return balances[player.UserId] or 0
end

function CurrencyService.AddCoins(player: Player, amount: number): number
	assert(amount >= 0, "AddCoins: amount must be non-negative")
	local current = balances[player.UserId] or 0
	balances[player.UserId] = current + amount
	return balances[player.UserId]
end

function CurrencyService.SpendCoins(player: Player, amount: number): (boolean, string?)
	assert(amount >= 0, "SpendCoins: amount must be non-negative")
	local current = balances[player.UserId] or 0
	if current < amount then
		return false, "Insufficient coins"
	end
	balances[player.UserId] = current - amount
	return true, nil
end

return CurrencyService
