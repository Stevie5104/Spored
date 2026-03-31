--!strict
-- CombatService: server-authoritative damage application and attack hooks.
-- Validates that attacking players actually have the requested part equipped,
-- enforces server-side cooldowns per player+slot, and checks target range.

local Players = game:GetService("Players")

local PartData = require(game:GetService("ReplicatedStorage").Modules.PartData)

-- Lazy-require to avoid circular dependency (PlayerBuildService also requires nothing here).
local PlayerBuildService: any = nil
local function getBuildService()
	if not PlayerBuildService then
		PlayerBuildService = require(script.Parent.PlayerBuildService)
	end
	return PlayerBuildService
end

local CombatService = {}

-- Tolerance added to the server-side cooldown check to accommodate network latency.
-- A client fire that arrives up to this many seconds early is still accepted.
local COOLDOWN_TOLERANCE_BUFFER = 0.1  -- seconds

-- Server-side range is multiplied by this factor to allow for latency and movement.
-- Set to 2× the stated part range so fast-moving players aren't unfairly rejected.
local RANGE_LATENCY_MULTIPLIER = 2

-- Server-side cooldown tracking: [userId][partId] = lastActivationClock
local serverCooldowns: { [number]: { [string]: number } } = {}

local function getCooldownTable(player: Player): { [string]: number }
	if not serverCooldowns[player.UserId] then
		serverCooldowns[player.UserId] = {}
	end
	return serverCooldowns[player.UserId]
end

-- Remove cooldown state when a player leaves.
local function cleanPlayer(player: Player)
	serverCooldowns[player.UserId] = nil
end

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
	targetId: number
): boolean
	-- Validate attacker character exists and has a root part.
	local character = attacker.Character
	if not character then return false end
	local attackerRoot = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not attackerRoot then return false end
	-- No Humanoid check: the player uses a custom organism with no Humanoid.

	-- Validate the part definition exists.
	local partDef = PartData[partId]
	if not partDef then
		warn(string.format("[CombatService] Unknown partId '%s' from %s", partId, attacker.Name))
		return false
	end

	-- Validate the player actually has this part equipped in their current build.
	local build = getBuildService().GetBuild(attacker)
	local partEquipped = false
	for _, equippedPartId in build.Slots do
		if equippedPartId == partId then
			partEquipped = true
			break
		end
	end
	if not partEquipped then
		warn(string.format("[CombatService] %s tried to use unequipped part '%s'", attacker.Name, partId))
		return false
	end

	-- Server-side cooldown check (prevents client from bypassing local cooldown).
	local cooldowns = getCooldownTable(attacker)
	local lastUse = cooldowns[partId] or 0
	local elapsed = os.clock() - lastUse
	if elapsed < (partDef.Cooldown - COOLDOWN_TOLERANCE_BUFFER) then
		return false
	end
	cooldowns[partId] = os.clock()

	-- Find and validate the target enemy.
	local Workspace = game:GetService("Workspace")
	local enemiesFolder = Workspace:FindFirstChild("Enemies") :: Folder?
	if not enemiesFolder then return false end

	for _, child in enemiesFolder:GetChildren() do
		local model = child :: Model
		if not model:IsA("Model") then continue end
		local idTag = model:FindFirstChild("EnemyId") :: IntValue?
		if not idTag or idTag.Value ~= targetId then continue end

		-- Range validation: target must be within part range * RANGE_LATENCY_MULTIPLIER.
		local enemyRoot = model:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not enemyRoot then continue end
		local dist = (Vector3.new(enemyRoot.Position.X, 0, enemyRoot.Position.Z)
			- Vector3.new(attackerRoot.Position.X, 0, attackerRoot.Position.Z)).Magnitude
		if dist > partDef.Range * RANGE_LATENCY_MULTIPLIER then
			warn(string.format("[CombatService] %s attack out of range (dist=%.1f, range=%.1f)",
				attacker.Name, dist, partDef.Range))
			return false
		end

		-- Apply authoritative damage from part stats.
		CombatService.DamageNPC(model, partDef.Damage, attacker)
		print(string.format("[CombatService] %s used '%s' on %s for %d dmg",
			attacker.Name, partId, model.Name, partDef.Damage))
		return true
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

	Players.PlayerRemoving:Connect(cleanPlayer)
end

return CombatService
