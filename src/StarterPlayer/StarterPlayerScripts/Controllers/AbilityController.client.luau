--!strict
-- AbilityController: handles client-side ability input, cursor aiming, and
-- sending validated attack requests to the server CombatService.
--
-- Each equipped part slot can be triggered with a key:
--   Q → Front slot ability
--   E → Core slot ability
--   R → Rear slot ability
--   (Extensible pattern for additional slots)

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

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

-- ── RemoteEvent reference (created by CombatService.Init on server) ──────────
local attackRemote: RemoteEvent? = nil

local function getAttackRemote(): RemoteEvent?
	if attackRemote then return attackRemote end
	local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
	if remotes then
		attackRemote = remotes:FindFirstChild("PartAttack") :: RemoteEvent?
	end
	return attackRemote
end

-- ── Aim direction toward cursor ───────────────────────────────────────────────
-- Returns a unit Vector3 pointing from the organism toward the cursor world pos.
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
-- Returns the EnemyId value of the closest enemy model within a cone in front
-- of the cursor direction, up to maxRange studs.
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
	local bestDot = 0.5 -- minimum cos(angle) for cone (~60 degree half-angle)

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
local cooldowns: { [string]: number } = {}
local SLOT_COOLDOWN_DEFAULT = 1.0

local function canActivate(slot: string): boolean
	local last = cooldowns[slot]
	if not last then return true end
	return (os.clock() - last) >= SLOT_COOLDOWN_DEFAULT
end

local function markCooldown(slot: string)
	cooldowns[slot] = os.clock()
end

-- ── Input: ability activation ─────────────────────────────────────────────────
UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then return end

	local slot = SLOT_KEYS[input.KeyCode]
	if not slot then return end
	if not canActivate(slot) then return end

	-- MVP stub: part equipped in this slot.
	-- In the full implementation this is resolved from the player's active build
	-- synced from PlayerBuildService. Slot name is used as a placeholder partId
	-- until the client-side build state module is wired up.
	local partId = slot .. "Part"

	-- Targeting range in studs. Should ultimately be derived from the part's Range
	-- stat once the client build state is available.
	local ABILITY_RANGE = 12
	local targetId = findTargetInAim(ABILITY_RANGE)
	if not targetId then return end

	local remote = getAttackRemote()
	if not remote then
		warn("[AbilityController] PartAttack remote not found.")
		return
	end

	markCooldown(slot)
	remote:FireServer(partId, targetId)
end)

-- ── Expose aim direction for other controllers (e.g., movement WASD aim) ──────
-- This module intentionally exports nothing at runtime; controllers communicate
-- via shared Remotes. Aim utilities above are also duplicated in MovementController
-- to keep controllers independent. A shared Utility module can be extracted later.
