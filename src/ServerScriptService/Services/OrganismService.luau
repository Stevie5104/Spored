--!strict
-- OrganismService: spawns and manages the custom organism as the player entity.
--
-- • Disables Roblox default character auto-loading.
-- • On PlayerAdded: creates an OrganismEntity model, positions it at a spawn
--   point, and assigns it to player.Character.  This triggers CharacterAdded on
--   all clients so existing controllers that watch that signal work unchanged—
--   they only need to look for "OrganismRootPart" instead of "HumanoidRootPart".
-- • On PlayerRemoving: destroys the organism and cleans up state.
--
-- Server API:
--   OrganismService.GetOrganism(player)    → OrganismInstance | nil
--   OrganismService.RespawnOrganism(player)
--   OrganismService.Init()

local Players   = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local OrganismEntity = require(game:GetService("ReplicatedStorage").Modules.OrganismEntity)

local OrganismService = {}

-- Per-player live OrganismInstance references, keyed by UserId.
local organisms: { [number]: typeof(OrganismEntity.new("StarterBlob")) } = {}

-- ── Internal ──────────────────────────────────────────────────────────────────

local function getSpawnCFrame(): CFrame
	-- Prefer an explicit SpawnLocation; fall back to world origin above baseplate.
	for _, obj in Workspace:GetChildren() do
		if obj:IsA("SpawnLocation") then
			return obj.CFrame * CFrame.new(0, 3, 0)
		end
	end
	return CFrame.new(0, 3, 0)
end

local function spawnOrganism(player: Player)
	-- Clean up any previous organism for this player.
	if organisms[player.UserId] then
		organisms[player.UserId]:Destroy()
		organisms[player.UserId] = nil
	end

	local organism            = OrganismEntity.new("StarterBlob")
	organism.Model.Name       = "Organism_" .. player.Name
	organism.RootPart.CFrame  = getSpawnCFrame()
	organism.Model.Parent     = Workspace

	organisms[player.UserId] = organism

	-- Assigning player.Character fires CharacterAdded on all clients and keeps
	-- the character reference accessible through player.Character everywhere
	-- (AI modules, combat, controllers, etc.).
	player.Character = organism.Model
end

local function cleanPlayer(player: Player)
	if organisms[player.UserId] then
		organisms[player.UserId]:Destroy()
		organisms[player.UserId] = nil
	end
end

-- ── Public API ────────────────────────────────────────────────────────────────

--- Returns the live OrganismInstance for the given player, or nil if not spawned.
function OrganismService.GetOrganism(player: Player)
	return organisms[player.UserId]
end

--- Destroys the current organism and spawns a fresh one (e.g., after death).
function OrganismService.RespawnOrganism(player: Player)
	spawnOrganism(player)
end

--- Initialises the service.  Call once from Services/init.server.luau.
function OrganismService.Init()
	-- Prevent the engine from auto-spawning the default Humanoid avatar.
	Players.CharacterAutoLoads = false

	Players.PlayerAdded:Connect(spawnOrganism)
	Players.PlayerRemoving:Connect(cleanPlayer)

	-- Spawn organisms for any players already in-game at init time.
	for _, player in Players:GetPlayers() do
		spawnOrganism(player)
	end

	print("[OrganismService] Initialized – custom organism spawning active.")
end

return OrganismService
