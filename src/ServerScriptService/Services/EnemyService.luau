--!strict
-- EnemyService: spawns and initializes NPC enemies from EnemyData, connects death->loot flow.
-- Each enemy type runs a dedicated AI module updated via a Heartbeat loop.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local EnemyData = require(game:GetService("ReplicatedStorage").Modules.EnemyData)
local LootService = require(script.Parent.LootService)

-- AI modules (loaded at the bottom of Init to avoid any load-order issues).
local GrazerAI = require(script.Parent.AI.GrazerAI)
local SpikeWormAI = require(script.Parent.AI.SpikeWormAI)
local VenomBlobAI = require(script.Parent.AI.VenomBlobAI)
local HunterCellAI = require(script.Parent.AI.HunterCellAI)

-- CombatService is required lazily to avoid circular dependency.
local CombatService: any = nil
local function getCombat()
	if not CombatService then
		CombatService = require(script.Parent.CombatService)
	end
	return CombatService
end

local EnemyService = {}

-- How many seconds after death before an enemy respawns at its spawn position.
local RESPAWN_DELAY = 25

-- Folder that holds all enemy models in Workspace.
local enemiesFolder: Folder

-- Incremental ID for identifying enemies.
local nextEnemyId = 1

-- Active enemy state table.
type EnemyEntry = {
	Model: Model,
	TypeId: string,
	Humanoid: Humanoid,
	SpawnPos: Vector3,
	AIState: any,   -- type varies per AI module
}

local activeEnemies: { [number]: EnemyEntry } = {}

-- Create a simple placeholder enemy model (sphere body + humanoid).
local function buildEnemyModel(typeId: string, def: EnemyData.EnemyDef): Model
	local model = Instance.new("Model")
	model.Name = def.Name

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 2)
	root.Shape = Enum.PartType.Ball
	root.CastShadow = false

	-- Give each enemy type a distinct color for readability.
	if typeId == "Grazer" then
		root.Color = Color3.fromRGB(80, 200, 100)    -- green
	elseif typeId == "SpikeWorm" then
		root.Color = Color3.fromRGB(200, 80, 80)     -- red
	elseif typeId == "VenomBlob" then
		root.Color = Color3.fromRGB(130, 60, 200)    -- purple
	elseif typeId == "HunterCell" then
		root.Color = Color3.fromRGB(220, 140, 40)    -- orange
	else
		root.Color = Color3.fromRGB(180, 180, 180)
	end

	root.Parent = model

	local humanoid = Instance.new("Humanoid")
	humanoid.MaxHealth = def.BaseHealth
	humanoid.Health = def.BaseHealth
	humanoid.WalkSpeed = def.MoveSpeed
	humanoid.Parent = model

	model.PrimaryPart = root

	-- Tag for identification
	local idTag = Instance.new("IntValue")
	idTag.Name = "EnemyId"
	idTag.Value = nextEnemyId
	idTag.Parent = model

	local typeTag = Instance.new("StringValue")
	typeTag.Name = "EnemyTypeId"
	typeTag.Value = typeId
	typeTag.Parent = model

	return model
end

-- Spawn a single enemy of the given type near a position.
function EnemyService.SpawnEnemy(typeId: string, position: Vector3): Model?
	local def = EnemyData[typeId]
	if not def then
		warn("EnemyService.SpawnEnemy: unknown enemy type:", typeId)
		return nil
	end

	local model = buildEnemyModel(typeId, def)
	local root = model.PrimaryPart :: BasePart
	root.CFrame = CFrame.new(position)
	model.Parent = enemiesFolder

	local id = nextEnemyId
	nextEnemyId += 1

	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid

	-- Build AI state for this instance.
	local aiState: any
	if typeId == "Grazer" then
		aiState = GrazerAI.NewState(position)
	elseif typeId == "SpikeWorm" then
		aiState = SpikeWormAI.NewState(position)
	elseif typeId == "VenomBlob" then
		aiState = VenomBlobAI.NewState()
	elseif typeId == "HunterCell" then
		aiState = HunterCellAI.NewState(position)
	else
		aiState = {}  -- fallback for unknown types
	end

	activeEnemies[id] = {
		Model = model,
		TypeId = typeId,
		Humanoid = humanoid,
		SpawnPos = position,
		AIState = aiState,
	}

	-- Death handler: award loot to the nearest player.
	humanoid.Died:Connect(function()
		activeEnemies[id] = nil

		-- Award loot to the nearest player within 40 studs.
		local bestPlayer: Player? = nil
		local bestDist = 40
		for _, player in Players:GetPlayers() do
			local char = player.Character
			if char then
				local rp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
				if rp then
					local dist = (rp.Position - root.Position).Magnitude
					if dist < bestDist then
						bestDist = dist
						bestPlayer = player
					end
				end
			end
		end

		if bestPlayer then
			local result = LootService.AwardLoot(bestPlayer, typeId)
			if result then
				print(string.format("[EnemyService] %s killed %s -> %s: %s",
					bestPlayer.Name, def.Name, result.Type, result.Detail))
			end
		end

		-- Remove model after a short delay.
		task.delay(3, function()
			if model.Parent then
				model:Destroy()
			end
		end)

		-- Respawn this enemy at its original position after a delay.
		task.delay(RESPAWN_DELAY, function()
			EnemyService.SpawnEnemy(typeId, position)
		end)
	end)

	return model
end

-- AI update loop: runs every ~0.1s and ticks each active enemy's behavior.
-- NOTE: For larger enemy counts (50+), consider level-of-detail AI ticking that
-- skips updates for enemies outside any player's view distance.
local AI_TICK = 0.1
local aiAccumulator = 0

local function onHeartbeat(dt: number)
	aiAccumulator += dt
	if aiAccumulator < AI_TICK then return end
	local tickDt = aiAccumulator
	aiAccumulator = 0

	local combat = getCombat()

	for id, entry in activeEnemies do
		if not entry.Model.Parent then
			-- Model was removed externally; clean up entry.
			activeEnemies[id] = nil
			continue
		end

		local typeId = entry.TypeId
		local def = EnemyData[typeId]
		if not def then continue end

		if typeId == "Grazer" then
			GrazerAI.Update(entry.Model, def, entry.AIState, tickDt, entry.SpawnPos)

		elseif typeId == "SpikeWorm" then
			SpikeWormAI.Update(entry.Model, def, entry.AIState, tickDt, entry.SpawnPos, combat)

		elseif typeId == "VenomBlob" then
			VenomBlobAI.Update(entry.Model, def, entry.AIState, tickDt, combat)

		elseif typeId == "HunterCell" then
			HunterCellAI.Update(entry.Model, def, entry.AIState, tickDt, entry.SpawnPos, combat)
		end
	end
end

-- Simple wave spawn: spawn a mix of enemies around the map at startup.
local function spawnInitialWave()
	local spawnPoints = {
		Vector3.new(20, 0, 20),
		Vector3.new(-20, 0, 20),
		Vector3.new(20, 0, -20),
		Vector3.new(-20, 0, -20),
		Vector3.new(40, 0, 0),
		Vector3.new(-40, 0, 0),
		Vector3.new(0, 0, 40),
	}

	local types = { "Grazer", "Grazer", "SpikeWorm", "VenomBlob", "SpikeWorm", "VenomBlob", "HunterCell" }
	for i, pos in spawnPoints do
		local typeId = types[((i - 1) % #types) + 1]
		EnemyService.SpawnEnemy(typeId, pos)
	end
end

function EnemyService.Init()
	-- Ensure Enemies folder exists.
	enemiesFolder = Workspace:FindFirstChild("Enemies") :: Folder
	if not enemiesFolder then
		enemiesFolder = Instance.new("Folder")
		enemiesFolder.Name = "Enemies"
		enemiesFolder.Parent = Workspace
	end

	-- Start the AI tick loop.
	RunService.Heartbeat:Connect(onHeartbeat)

	-- Wait for game to load, then spawn initial wave.
	task.delay(2, spawnInitialWave)
end

return EnemyService
