--!strict
-- MovementController: top-down organism movement supporting two input modes.
--
-- Mode 1 (ClickToMove):
--   • Single click  – organism swims to the clicked world position.
--   • Click-and-drag – hold the left mouse button and move the cursor;
--     clickTarget updates every frame while the button is held so the
--     organism continuously tracks the cursor.  On release the organism
--     keeps heading toward the last cursor position until it arrives.
--
--   To DISABLE drag behaviour set DRAG_ENABLED = false below.
--
-- Mode 2 (WASDMouseAim): WASD drives movement; mouse controls aim/facing.
--
-- Both modes feed the same velocity backend (acceleration + drag = floaty feel).
-- Press [1] to switch to ClickToMove, [2] to switch to WASDMouseAim.
--
-- Movement stats are derived from OrganismEntity.ComputeStats() each time the
-- player's build changes (BuildChanged RemoteEvent) so that equipped parts such
-- as DashFlagella (+10 speed via Swift trait) take effect immediately.

local Players         = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService      = game:GetService("RunService")
local Workspace       = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local OrganismEntity  = require(ReplicatedStorage.Modules.OrganismEntity)

local player = Players.LocalPlayer

-- ── Live movement stats (updated from OrganismEntity.ComputeStats) ────────────
-- These defaults match the StarterBlob body and are overwritten on the first
-- BuildChanged event, so they are always accurate once a build is broadcast.
local MOVE_SPEED  : number = 24
local ACCELERATION: number = 80
local TURN_SPEED  : number = math.rad(540)
local DRAG        = 10
local STOP_DIST   = 1.5
local MOVE_PLANE_Y = 0

-- ── Feature flags ─────────────────────────────────────────────────────────────
-- Set DRAG_ENABLED = false to revert to single-click-only behaviour.
local DRAG_ENABLED = true

-- ── Control modes ─────────────────────────────────────────────────────────────
type ControlMode = "ClickToMove" | "WASDMouseAim"
local controlMode: ControlMode = "ClickToMove"

-- ── Runtime state ─────────────────────────────────────────────────────────────
local rootPart: BasePart? = nil
local velocity = Vector3.zero
local clickTarget: Vector3? = nil

-- isDragging is true while MouseButton1 is held in ClickToMove mode.
-- Each RenderStepped frame the cursor world position overwrites clickTarget
-- so the path continuously tracks the cursor.
local isDragging = false

local keyState = { W = false, A = false, S = false, D = false }
local moveInput = Vector3.zero

-- ── Utilities ─────────────────────────────────────────────────────────────────

local function flatten(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Cast a ray from the camera through the mouse position onto a Y-plane.
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

local function recomputeMoveInput()
	local x = (keyState.D and 1 or 0) - (keyState.A and 1 or 0)
	local z = (keyState.S and 1 or 0) - (keyState.W and 1 or 0)
	local v = Vector3.new(x, 0, z)
	moveInput = if v.Magnitude > 1 then v.Unit else v
end

-- Smoothly rotate rootPart CFrame toward a flat direction by at most TURN_SPEED*dt.
local function rotateToward(current: CFrame, dir: Vector3, dt: number): CFrame
	local flat = flatten(dir)
	if flat.Magnitude < 1e-4 then return current end

	local desired = math.atan2(-flat.X, -flat.Z)
	local _, currentYaw, _ = current:ToOrientation()
	local delta = ((desired - currentYaw + math.pi) % (2 * math.pi)) - math.pi
	local step = math.clamp(delta, -TURN_SPEED * dt, TURN_SPEED * dt)

	return CFrame.new(current.Position) * CFrame.Angles(0, currentYaw + step, 0)
end

-- ── Character binding ──────────────────────────────────────────────────────────
-- Binds to the custom organism model set as player.Character by OrganismService.
-- The organism has "OrganismRootPart" instead of "HumanoidRootPart" and no
-- Humanoid, so movement is applied purely through AssemblyLinearVelocity.

local function bindCharacter(char: Model)
	rootPart = char:WaitForChild("OrganismRootPart") :: BasePart
	velocity    = Vector3.zero
	clickTarget = nil
	isDragging  = false
end

player.CharacterAdded:Connect(bindCharacter)
if player.Character then
	bindCharacter(player.Character)
end

-- ── Build-state sync: update movement stats when equipped parts change ─────────
-- When the server broadcasts a BuildChanged event, recompute OrganismStats so
-- that movement parts (fins, flagella) immediately affect speed/turn rate.

local currentBodyId = "StarterBlob"
local currentSlots: { [string]: string } = {}

local function applyStats(bodyId: string, slots: { [string]: string })
	currentBodyId = bodyId
	currentSlots  = slots
	local stats = OrganismEntity.ComputeStats(bodyId, slots)
	MOVE_SPEED   = stats.MoveSpeed
	ACCELERATION = stats.Acceleration
	TURN_SPEED   = stats.TurnSpeed
end

task.spawn(function()
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 10) :: Folder?
	if not remotes then
		warn("[MovementController] Remotes folder not found – movement stats will remain at body defaults and will not update when build changes.")
		return
	end

	local buildChanged = remotes:WaitForChild("BuildChanged", 10) :: RemoteEvent?
	if not buildChanged then
		warn("[MovementController] BuildChanged remote not found – movement speed will not update when parts are equipped or swapped.")
		return
	end

	buildChanged.OnClientEvent:Connect(function(bodyId: unknown, slots: unknown)
		if typeof(bodyId) ~= "string" then return end
		if typeof(slots) ~= "table" then return end
		local typedSlots: { [string]: string } = {}
		for k, v in slots :: { [any]: any } do
			if typeof(k) == "string" and typeof(v) == "string" then
				typedSlots[k :: string] = v :: string
			end
		end
		applyStats(bodyId :: string, typedSlots)
	end)
end)

-- ── Input handling ────────────────────────────────────────────────────────────
--
-- ClickToMove input flow:
--   MouseButton1 Down → set isDragging = true, sample initial clickTarget.
--   While held (isDragging)  → RenderStepped refreshes clickTarget each frame.
--   MouseButton1 Up   → clear isDragging; organism continues to last position.
--
-- To disable drag: set DRAG_ENABLED = false at the top of this file.

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if controlMode == "ClickToMove" then
			-- Record initial click target.
			local hit = mouseToPlane(MOVE_PLANE_Y)
			clickTarget = hit
			-- Begin drag tracking only when the cursor maps to a valid world
			-- position and the feature is enabled.
			if DRAG_ENABLED and hit ~= nil then
				isDragging = true
			end
		end

	elseif input.KeyCode == Enum.KeyCode.One then
		controlMode = "ClickToMove"

	elseif input.KeyCode == Enum.KeyCode.Two then
		controlMode = "WASDMouseAim"
		clickTarget = nil
		isDragging  = false

	elseif input.KeyCode == Enum.KeyCode.W then keyState.W = true; recomputeMoveInput()
	elseif input.KeyCode == Enum.KeyCode.A then keyState.A = true; recomputeMoveInput()
	elseif input.KeyCode == Enum.KeyCode.S then keyState.S = true; recomputeMoveInput()
	elseif input.KeyCode == Enum.KeyCode.D then keyState.D = true; recomputeMoveInput()
	end
end)

UserInputService.InputEnded:Connect(function(input: InputObject, processed: boolean)
	if processed then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		-- Stop drag; organism keeps heading toward the last sampled position.
		isDragging = false

	elseif input.KeyCode == Enum.KeyCode.W then keyState.W = false; recomputeMoveInput()
	elseif input.KeyCode == Enum.KeyCode.A then keyState.A = false; recomputeMoveInput()
	elseif input.KeyCode == Enum.KeyCode.S then keyState.S = false; recomputeMoveInput()
	elseif input.KeyCode == Enum.KeyCode.D then keyState.D = false; recomputeMoveInput()
	end
end)

-- ── Shared movement backend (RenderStepped) ───────────────────────────────────

RunService.RenderStepped:Connect(function(dt: number)
	if not rootPart then return end

	local pos           = rootPart.Position
	local desiredMoveDir  = Vector3.zero
	local desiredFacingDir = Vector3.zero

	if controlMode == "ClickToMove" then
		-- While the mouse button is held, continuously refresh the target so
		-- the organism tracks the cursor (drag-to-move behaviour).
		if isDragging then
			local hit = mouseToPlane(MOVE_PLANE_Y)
			if hit then
				clickTarget = hit
			end
		end

		if clickTarget then
			local toTarget = flatten(clickTarget - pos)
			if toTarget.Magnitude <= STOP_DIST then
				clickTarget = nil
			else
				desiredMoveDir  = toTarget.Unit
				desiredFacingDir = desiredMoveDir
			end
		end

	elseif controlMode == "WASDMouseAim" then
		local cam = Workspace.CurrentCamera
		if cam and moveInput.Magnitude > 0 then
			local look  = flatten(cam.CFrame.LookVector)
			local right = flatten(cam.CFrame.RightVector)
			if look.Magnitude  > 1e-4 then look  = look.Unit  end
			if right.Magnitude > 1e-4 then right = right.Unit end

			local world = right * moveInput.X + look * moveInput.Z
			desiredMoveDir = if world.Magnitude > 1 then world.Unit else world
		end

		-- Aim follows mouse cursor at all times in WASD mode.
		local mouseWorld = mouseToPlane(MOVE_PLANE_Y)
		if mouseWorld then
			local aim = flatten(mouseWorld - pos)
			if aim.Magnitude > 1e-3 then
				desiredFacingDir = aim.Unit
			end
		end
	end

	-- Acceleration toward desired velocity.
	local target = desiredMoveDir * MOVE_SPEED
	local dv     = target - velocity
	local step   = ACCELERATION * dt
	velocity += if dv.Magnitude > step then dv.Unit * step else dv

	-- Drag (floaty decay).
	velocity *= math.max(0, 1 - DRAG * dt)

	-- Apply horizontal velocity while preserving physics Y.
	local currentY = rootPart.AssemblyLinearVelocity.Y
	rootPart.AssemblyLinearVelocity = Vector3.new(velocity.X, currentY, velocity.Z)

	-- Rotation: prefer move direction; fall back to aim direction.
	local facing = if desiredMoveDir.Magnitude > 0.05 then desiredMoveDir else desiredFacingDir
	if facing.Magnitude > 0.01 then
		rootPart.CFrame = rotateToward(rootPart.CFrame, facing, dt)
	end
end)

