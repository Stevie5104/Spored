--!strict
-- MovementController: top-down organism movement supporting two input modes.
--
-- Mode 1 (ClickToMove): left-click a world position; organism swims toward it.
-- Mode 2 (WASDMouseAim): WASD drives movement; mouse controls aim/facing.
--
-- Both modes feed the same velocity backend (acceleration + drag = floaty feel).
-- Press [1] to switch to ClickToMove, [2] to switch to WASDMouseAim.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

-- ── Movement stats (overridable by body stats in a future update) ─────────────
local MOVE_SPEED = 24
local ACCELERATION = 80
local DRAG = 10
local TURN_SPEED = math.rad(540)
local STOP_DIST = 1.5
local MOVE_PLANE_Y = 0

-- ── Control modes ─────────────────────────────────────────────────────────────
type ControlMode = "ClickToMove" | "WASDMouseAim"
local controlMode: ControlMode = "ClickToMove"

-- ── Runtime state ─────────────────────────────────────────────────────────────
local rootPart: BasePart? = nil
local humanoid: Humanoid? = nil
local velocity = Vector3.zero
local clickTarget: Vector3? = nil

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

local function bindCharacter(char: Model)
	rootPart = char:WaitForChild("HumanoidRootPart") :: BasePart
	humanoid = char:WaitForChild("Humanoid") :: Humanoid
	humanoid.AutoRotate = false
	velocity = Vector3.zero
	clickTarget = nil
end

player.CharacterAdded:Connect(bindCharacter)
if player.Character then
	bindCharacter(player.Character)
end

-- ── Input handling ────────────────────────────────────────────────────────────

-- Tracks whether the left mouse button is currently held for click-and-drag movement.
local mouseHeld = false

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if controlMode == "ClickToMove" then
			mouseHeld = true
			clickTarget = mouseToPlane(MOVE_PLANE_Y)
		end

	elseif input.KeyCode == Enum.KeyCode.One then
		controlMode = "ClickToMove"

	elseif input.KeyCode == Enum.KeyCode.Two then
		controlMode = "WASDMouseAim"
		clickTarget = nil

	elseif input.KeyCode == Enum.KeyCode.W then keyState.W = true; recomputeMoveInput()
	elseif input.KeyCode == Enum.KeyCode.A then keyState.A = true; recomputeMoveInput()
	elseif input.KeyCode == Enum.KeyCode.S then keyState.S = true; recomputeMoveInput()
	elseif input.KeyCode == Enum.KeyCode.D then keyState.D = true; recomputeMoveInput()
	end
end)

UserInputService.InputEnded:Connect(function(input: InputObject, processed: boolean)
	if processed then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		mouseHeld = false
	elseif input.KeyCode == Enum.KeyCode.W then keyState.W = false; recomputeMoveInput()
	elseif input.KeyCode == Enum.KeyCode.A then keyState.A = false; recomputeMoveInput()
	elseif input.KeyCode == Enum.KeyCode.S then keyState.S = false; recomputeMoveInput()
	elseif input.KeyCode == Enum.KeyCode.D then keyState.D = false; recomputeMoveInput()
	end
end)

-- ── Shared movement backend (RenderStepped) ───────────────────────────────────

RunService.RenderStepped:Connect(function(dt: number)
	if not rootPart or not humanoid then return end
	if humanoid.Health <= 0 then return end

	local pos = rootPart.Position
	local desiredMoveDir = Vector3.zero
	local desiredFacingDir = Vector3.zero

	if controlMode == "ClickToMove" then
		-- While mouse button is held, continuously drag the target to the cursor position.
		if mouseHeld then
			clickTarget = mouseToPlane(MOVE_PLANE_Y)
		end

		if clickTarget then
			local toTarget = flatten(clickTarget - pos)
			if toTarget.Magnitude <= STOP_DIST then
				clickTarget = nil
			else
				desiredMoveDir = toTarget.Unit
				desiredFacingDir = desiredMoveDir
			end
		end

	elseif controlMode == "WASDMouseAim" then
		local cam = Workspace.CurrentCamera
		if cam and moveInput.Magnitude > 0 then
			local look = flatten(cam.CFrame.LookVector)
			local right = flatten(cam.CFrame.RightVector)
			if look.Magnitude > 1e-4 then look = look.Unit end
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
	local dv = target - velocity
	local step = ACCELERATION * dt
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
