--!strict
-- EnemyService: spawns and initializes NPC enemies from EnemyData, connects death->loot flow.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local EnemyData = require(game:GetService("ReplicatedStorage").Modules.EnemyData)
local LootService = require(script.Parent.LootService)

local EnemyService = {}

-- Folder that holds all enemy models in Workspace.
local enemiesFolder: Folder

-- Incremental ID for identifying enemies.
local nextEnemyId = 1

-- Active enemy state table.
local activeEnemies: {
	[number]: {
		Model: Model,
		TypeId: string,
		Humanoid: Humanoid,
	}
} = {}

-- Create a simple placeholder enemy model (sphere body + humanoid).
local function buildEnemyModel(typeId: string, def: EnemyData.EnemyDef): Model
	local model = Instance.new("Model")
	model.Name = def.Name

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 2)
	root.Shape = Enum.PartType.Ball
	root.CastShadow = false
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

	activeEnemies[id] = { Model = model, TypeId = typeId, Humanoid = humanoid }

	-- Death handler: award loot to the nearest player.
	humanoid.Died:Connect(function()
		activeEnemies[id] = nil

		-- Award loot to a nearby player (nearest within 40 studs).
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
	end)

	return model
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
	}

	local types = { "Grazer", "Grazer", "SpikeWorm", "VenomBlob" }
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

	-- Wait for game to load, then spawn initial wave.
	task.delay(2, spawnInitialWave)
end

return EnemyService
