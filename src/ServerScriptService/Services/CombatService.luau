--!strict
-- CombatService: server-authoritative damage application and attack hooks.

local Players = game:GetService("Players")

local CombatService = {}

-- Damage an NPC model (enemies are expected to have a Humanoid).
function CombatService.DamageNPC(target: Model, amount: number, attacker: Player?)
	assert(amount >= 0, "DamageNPC: damage amount must be non-negative")
	local humanoid = target:FindFirstChildOfClass("Humanoid") :: Humanoid?
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	humanoid:TakeDamage(amount)
end

-- Damage a player character (server-side only).
function CombatService.DamagePlayer(target: Player, amount: number, attacker: Model?)
	assert(amount >= 0, "DamagePlayer: damage amount must be non-negative")
	local character = target.Character
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid?
	if not humanoid or humanoid.Health <= 0 then return end
	humanoid:TakeDamage(amount)
end

-- Part-triggered attack hook: validates and processes an attack request from a client.
-- Returns true if the attack was applied, false if rejected.
function CombatService.HandlePartAttack(
	attacker: Player,
	partId: string,
	targetId: number -- target enemy model's unique ID or similar handle
): boolean
	-- Validate attacker character exists
	local character = attacker.Character
	if not character then
		return false
	end

	-- Stub: in full implementation, validate partId is equipped and cooldown is ready.
	-- For MVP, allow attack and log.
	print(string.format("[CombatService] %s used part '%s' targeting model %d", attacker.Name, partId, targetId))

	-- Find the target in Workspace (enemies tagged/parented under a known folder)
	local Workspace = game:GetService("Workspace")
	local enemiesFolder = Workspace:FindFirstChild("Enemies") :: Folder?
	if not enemiesFolder then
		return false
	end

	for _, child in enemiesFolder:GetChildren() do
		local model = child :: Model
		if model:IsA("Model") then
			local idTag = model:FindFirstChild("EnemyId") :: IntValue?
			if idTag and idTag.Value == targetId then
				-- Placeholder damage value; full implementation reads part stats.
				local damage = 20
				CombatService.DamageNPC(model, damage, attacker)
				return true
			end
		end
	end

	return false
end

-- RemoteEvent wiring for client ability requests.
function CombatService.Init()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local remoteFolder = ReplicatedStorage:FindFirstChild("Remotes")
	if not remoteFolder then
		local folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
		remoteFolder = folder
	end

	local attackRemote = remoteFolder:FindFirstChild("PartAttack") :: RemoteEvent?
	if not attackRemote then
		local remote = Instance.new("RemoteEvent")
		remote.Name = "PartAttack"
		remote.Parent = remoteFolder
		attackRemote = remote
	end

	attackRemote.OnServerEvent:Connect(function(player: Player, partId: unknown, targetId: unknown)
		if typeof(partId) ~= "string" or typeof(targetId) ~= "number" then
			return
		end
		CombatService.HandlePartAttack(player, partId :: string, targetId :: number)
	end)
end

return CombatService
