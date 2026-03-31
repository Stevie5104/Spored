--!strict
-- CurrencyService: maintains per-player coin balances with safe server-only APIs.
-- Fires CurrencyChanged to the owning client whenever the balance changes.

local Players = game:GetService("Players")

local CurrencyService = {}

local balances: { [number]: number } = {}

-- RemoteEvent reference; set during Init.
local currencyChangedRemote: RemoteEvent? = nil

local STARTING_COINS = 50

local function initPlayer(player: Player)
	balances[player.UserId] = STARTING_COINS
end

local function cleanPlayer(player: Player)
	balances[player.UserId] = nil
end

local function fireChanged(player: Player)
	if currencyChangedRemote then
		currencyChangedRemote:FireClient(player, balances[player.UserId] or 0)
	end
end

function CurrencyService.Init()
	Players.PlayerAdded:Connect(initPlayer)
	Players.PlayerRemoving:Connect(cleanPlayer)
	for _, player in Players:GetPlayers() do
		initPlayer(player)
	end

	-- Set up Remotes folder (shared with other services).
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local remoteFolder = ReplicatedStorage:FindFirstChild("Remotes")
	if not remoteFolder then
		local folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
		remoteFolder = folder
	end

	-- CurrencyChanged: fires to the client whenever their balance changes.
	local changedRemote = remoteFolder:FindFirstChild("CurrencyChanged") :: RemoteEvent?
	if not changedRemote then
		local r = Instance.new("RemoteEvent")
		r.Name = "CurrencyChanged"
		r.Parent = remoteFolder
		changedRemote = r
	end
	currencyChangedRemote = changedRemote

	-- GetBalance: RemoteFunction so the client can fetch the current balance on join.
	local getBalRemote = remoteFolder:FindFirstChild("GetBalance") :: RemoteFunction?
	if not getBalRemote then
		local r = Instance.new("RemoteFunction")
		r.Name = "GetBalance"
		r.Parent = remoteFolder
		getBalRemote = r
	end
	getBalRemote.OnServerInvoke = function(player: Player): number
		return CurrencyService.GetBalance(player)
	end
end

function CurrencyService.GetBalance(player: Player): number
	return balances[player.UserId] or 0
end

-- Override the balance directly (used by DataService to restore saved data).
function CurrencyService.SetBalance(player: Player, amount: number)
	assert(amount >= 0, "SetBalance: amount must be non-negative")
	balances[player.UserId] = amount
	fireChanged(player)
end

function CurrencyService.AddCoins(player: Player, amount: number): number
	assert(amount >= 0, "AddCoins: amount must be non-negative")
	local current = balances[player.UserId] or 0
	balances[player.UserId] = current + amount
	fireChanged(player)
	return balances[player.UserId]
end

function CurrencyService.SpendCoins(player: Player, amount: number): (boolean, string?)
	assert(amount >= 0, "SpendCoins: amount must be non-negative")
	local current = balances[player.UserId] or 0
	if current < amount then
		return false, "Insufficient coins"
	end
	balances[player.UserId] = current - amount
	fireChanged(player)
	return true, nil
end

return CurrencyService
