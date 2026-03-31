--!strict
-- CharacterService: replaces the default Roblox character with a custom organism.
--
-- Disables CharacterAutoLoads so no Humanoid-based avatar is ever spawned.
-- Creates a lightweight custom model (no Humanoid, no animations, no jump)
-- and assigns it as player.Character so all existing client controllers
-- (MovementController, CameraController, BuildVisualController, AbilityController)
-- bind to it via the CharacterAdded event.
--
-- The root part is named "HumanoidRootPart" for compatibility with those controllers;
-- no Humanoid instance is present so jump and built-in movement mechanics
-- are completely absent.

local Players  = game:GetService("Players")
local Workspace = game:GetService("Workspace")

-- ── Spawn constants ────────────────────────────────────────────────────────────
-- SPAWN_Y must match ORGANISM_Y in MovementController so the organism sits
-- at the correct height above the ground plane from the very first frame.
local SPAWN_Y      = 1.0  -- world-Y of the organism root centre
local SPAWN_RADIUS = 8    -- studs; scatter radius so co-op players don't overlap

-- ── Build the organism model for one player ────────────────────────────────────
local function createOrganism(player: Player): Model
	local model    = Instance.new("Model")
	model.Name     = player.Name

	-- Root part: thin flat box acting as the organism's physics root.
	-- Anchored = true → position is driven each frame by MovementController
	-- via CFrame, with no physics/gravity interference.
	-- Transparency = 1 → invisible; BuildVisualController adds sphere geometry.
	-- Named "HumanoidRootPart" so CharacterAdded listeners in the client
	-- controllers can bind without modification.
	local root          = Instance.new("Part")
	root.Name           = "HumanoidRootPart"
	root.Size           = Vector3.new(2, 0.5, 2)
	root.Transparency   = 1
	root.CanCollide     = false
	root.CastShadow     = false
	root.Anchored       = true

	-- Scatter spawn so multiple testers don't start on top of each other.
	local angle   = math.random() * 2 * math.pi
	local r       = math.random() * SPAWN_RADIUS
	root.CFrame   = CFrame.new(math.cos(angle) * r, SPAWN_Y, math.sin(angle) * r)

	root.Parent        = model
	model.PrimaryPart  = root

	-- Parent to Workspace BEFORE setting player.Character so that the
	-- CharacterAdded event fires with a model that is already in the world.
	model.Parent = Workspace

	return model
end

-- ── Service ────────────────────────────────────────────────────────────────────
local CharacterService = {}

function CharacterService.Init()
	-- Prevent the engine from ever loading the default Humanoid avatar.
	-- Must be set before any player joins; this script runs at server start
	-- in ServerScriptService so it will always execute in time.
	Players.CharacterAutoLoads = false

	Players.PlayerAdded:Connect(function(player: Player)
		player.Character = createOrganism(player)

		-- Re-spawn organism when it is removed (death / future mechanics).
		player.CharacterRemoving:Connect(function()
			task.wait(1)
			-- player.Parent is non-nil only while the player is still connected.
			if player.Parent then
				player.Character = createOrganism(player)
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		-- Destroy organism from Workspace when the player disconnects.
		local char = player.Character
		if char and char.Parent == Workspace then
			char:Destroy()
		end
	end)

	print("[CharacterService] Initialized – custom organism spawning active.")
end

return CharacterService
