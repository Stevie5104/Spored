--!strict
-- AbilityController: handles client-side ability input, cursor aiming, and
-- sending validated attack requests to the server CombatService.
--
-- Each equipped part slot can be triggered with a key:
--   Q → Front slot ability
--   E → Core slot ability
--   R → Rear slot ability
--   (Extensible pattern for additional slots)
--
-- Cooldowns are read from PartData for the currently equipped part.
-- The BuildChanged RemoteEvent keeps currentBuild in sync with the server.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PartData = require(ReplicatedStorage.Modules.PartData)

local player = Players.LocalPlayer

-- ── Ability slot key bindings ────────────────────────────────────────────────
local SLOT_KEYS: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.Q] = "Front",
	[Enum.KeyCode.E] = "Core",
	[Enum.KeyCode.R] = "Rear",
	[Enum.KeyCode.F] = "Left",
	[Enum.KeyCode.G] = "Right",
}

-- ── Mouse-to-plane utility ────────────────────────────────────────────────────
local MOVE_PLANE_Y = 0

local function mouseToPlane(planeY: number): Vector3?
	local cam = Workspace.CurrentCamera
	if not cam then return nil end

	local mousePos = UserInputService:GetMouseLocation()
	local ray = cam:ViewportPointToRay(mousePos.X, mousePos.Y)
	local dir = ray.Direction

	if math.abs(dir.Y) < 1e-5 then return nil end
	local t = (planeY - ray.Origin.Y) / dir.Y
	if t < 0 then return nil end

	return ray.Origin + dir * t
end

-- ── Client-side build state (kept in sync via BuildChanged RemoteEvent) ───────
local currentBuild: { BodyId: string, Slots: { [string]: string } } = {
	BodyId = "StarterBlob",
	Slots = {},
}

-- ── RemoteEvent/Function references ─────────────────────────────────────────
local attackRemote: RemoteEvent? = nil
local buildChangedRemote: RemoteEvent? = nil

-- Wait until Remotes folder exists (server creates it during Init).
task.spawn(function()
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 10) :: Folder?
	if not remotes then
		warn("[AbilityController] Remotes folder not found.")
		return
	end

	attackRemote = remotes:WaitForChild("PartAttack", 10) :: RemoteEvent?
	buildChangedRemote = remotes:WaitForChild("BuildChanged", 10) :: RemoteEvent?

	if buildChangedRemote then
		-- Update local build state whenever the server broadcasts a change.
		buildChangedRemote.OnClientEvent:Connect(function(bodyId: unknown, slots: unknown)
			if typeof(bodyId) == "string" and typeof(slots) == "table" then
				currentBuild.BodyId = bodyId :: string
				-- Replace slots table with the server snapshot.
				local newSlots: { [string]: string } = {}
				for k, v in slots :: { [any]: any } do
					if typeof(k) == "string" and typeof(v) == "string" then
						newSlots[k :: string] = v :: string
					end
				end
				currentBuild.Slots = newSlots
			end
		end)
	end
end)

-- ── Aim direction toward cursor ───────────────────────────────────────────────
local function getAimDirection(): Vector3?
	local character = player.Character
	if not character then return nil end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return nil end

	local mouseWorld = mouseToPlane(MOVE_PLANE_Y)
	if not mouseWorld then return nil end

	local flat = Vector3.new(mouseWorld.X - root.Position.X, 0, mouseWorld.Z - root.Position.Z)
	if flat.Magnitude < 1e-3 then return nil end
	return flat.Unit
end

-- ── Target finding: nearest enemy in aim direction ────────────────────────────
local function findTargetInAim(maxRange: number): number?
	local character = player.Character
	if not character then return nil end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return nil end

	local aimDir = getAimDirection()
	if not aimDir then return nil end

	local enemiesFolder = Workspace:FindFirstChild("Enemies") :: Folder?
	if not enemiesFolder then return nil end

	local bestId: number? = nil
	local bestDot = 0.5  -- minimum cos(angle) (~60-degree half-cone)

	for _, child in enemiesFolder:GetChildren() do
		local model = child :: Model
		if not model:IsA("Model") then continue end
		local enemyRoot = model:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not enemyRoot then continue end

		local toEnemy = Vector3.new(
			enemyRoot.Position.X - root.Position.X,
			0,
			enemyRoot.Position.Z - root.Position.Z
		)
		local dist = toEnemy.Magnitude
		if dist > maxRange then continue end

		local dot = if dist > 1e-3 then aimDir:Dot(toEnemy.Unit) else 0
		if dot > bestDot then
			local idTag = model:FindFirstChild("EnemyId") :: IntValue?
			if idTag then
				bestDot = dot
				bestId = idTag.Value
			end
		end
	end

	return bestId
end

-- ── Per-slot cooldown tracking ────────────────────────────────────────────────
-- Records the os.clock() time at last activation for each partId.
local cooldownTimestamps: { [string]: number } = {}
local FALLBACK_COOLDOWN = 1.0  -- used when equipped part is unknown

-- Returns the cooldown duration for the part currently in a given slot.
local function getPartCooldown(partId: string): number
	local partDef = PartData[partId]
	if partDef then
		return partDef.Cooldown
	end
	return FALLBACK_COOLDOWN
end

local function canActivate(partId: string): boolean
	local last = cooldownTimestamps[partId]
	if not last then return true end
	return (os.clock() - last) >= getPartCooldown(partId)
end

local function markCooldown(partId: string)
	cooldownTimestamps[partId] = os.clock()
end

-- ── Input: ability activation ─────────────────────────────────────────────────
UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then return end

	local slot = SLOT_KEYS[input.KeyCode]
	if not slot then return end

	-- Resolve partId from current build state.
	local partId = currentBuild.Slots[slot]
	if not partId then return end  -- no part equipped in this slot

	if not canActivate(partId) then return end

	-- Look up the part's stated range for targeting.
	local partDef = PartData[partId]
	local abilityRange = if partDef then partDef.Range else 12

	local targetId = findTargetInAim(abilityRange)
	if not targetId then return end

	local remote = attackRemote
	if not remote then
		warn("[AbilityController] PartAttack remote not ready.")
		return
	end

	markCooldown(partId)
	remote:FireServer(partId, targetId)
end)
