--!strict
-- MovementController: top-down organism movement for the custom organism entity.
-- No Humanoid or default Roblox character controller is used.
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

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
local Workspace        = game:GetService("Workspace")

local player = Players.LocalPlayer

-- ── Movement stats (configurable; will be driven by body/part upgrades later) ─
-- NOTE: Values are intentionally high for development / testing.
-- Tune down via equipped parts once progression systems are in place.
local MOVE_SPEED   = 80     -- studs/s max speed (dev-boosted; design target ~24)
local ACCELERATION = 200    -- studs/s²  – how quickly the organism reaches max speed
local DRAG         = 8      -- velocity decay coefficient  (higher = snappier stop)
local TURN_SPEED   = math.rad(720)  -- radians/s rotation speed (dev-boosted)
local STOP_DIST    = 1.5    -- studs; organism stops when within this of the click target

-- Y of the ground plane used for mouse raycasting.
local MOVE_PLANE_Y = 0
-- Y of the organism root centre above the ground plane.
-- Must match SPAWN_Y in CharacterService so the organism is flush with the
-- ground from the first frame.
local ORGANISM_Y   = 1.0

-- ── Feature flags ─────────────────────────────────────────────────────────────
-- Set DRAG_ENABLED = false to revert to single-click-only behaviour.
local DRAG_ENABLED = true

-- ── Control modes ─────────────────────────────────────────────────────────────
type ControlMode = "ClickToMove" | "WASDMouseAim"
local controlMode: ControlMode = "ClickToMove"

-- ── Runtime state ─────────────────────────────────────────────────────────────
local rootPart: BasePart? = nil
local velocity   = Vector3.zero
local currentYaw = 0         -- current organism facing angle (radians)
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
	local ray      = cam:ViewportPointToRay(mousePos.X, mousePos.Y)
	local dir      = ray.Direction

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

-- Advance yaw toward a flat world direction by at most TURN_SPEED*dt radians.
-- Returns the updated yaw angle.
local function stepYaw(yaw: number, dir: Vector3, dt: number): number
	local flat = flatten(dir)
	if flat.Magnitude < 1e-4 then return yaw end
	local desired = math.atan2(-flat.X, -flat.Z)
	local delta   = ((desired - yaw + math.pi) % (2 * math.pi)) - math.pi
	return yaw + math.clamp(delta, -TURN_SPEED * dt, TURN_SPEED * dt)
end

-- ── Character binding ──────────────────────────────────────────────────────────

local function bindCharacter(char: Model)
	-- The custom organism has no Humanoid – only wait for the root part.
	local root = char:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not root then
		warn("[MovementController] HumanoidRootPart not found in character.")
		return
	end

	rootPart  = root
	velocity  = Vector3.zero
	clickTarget = nil
	isDragging  = false

	-- Sync facing from the spawned CFrame so rotation continues smoothly.
	local _, yaw, _ = root.CFrame:ToOrientation()
	currentYaw = yaw
end

player.CharacterAdded:Connect(bindCharacter)
if player.Character then
	bindCharacter(player.Character)
end

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

	elseif input.KeyCode == Enum.KeyCode.W then keyState.W = true;  recomputeMoveInput()
	elseif input.KeyCode == Enum.KeyCode.A then keyState.A = true;  recomputeMoveInput()
	elseif input.KeyCode == Enum.KeyCode.S then keyState.S = true;  recomputeMoveInput()
	elseif input.KeyCode == Enum.KeyCode.D then keyState.D = true;  recomputeMoveInput()
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
	local root = rootPart
	if not root then return end

	local pos            = root.Position
	local desiredMoveDir = Vector3.zero
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
				desiredMoveDir   = toTarget.Unit
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

			local world  = right * moveInput.X + look * moveInput.Z
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

	-- ── Velocity update (shared acceleration + drag backend) ─────────────────
	-- Both ClickToMove and WASDMouseAim feed desiredMoveDir into the same
	-- physics model so max speed and feel are identical across input methods.
	local targetVel = desiredMoveDir * MOVE_SPEED
	local dv        = targetVel - velocity
	local step      = ACCELERATION * dt
	velocity += if dv.Magnitude > step then dv.Unit * step else dv

	-- Drag (floaty decay toward zero when no input).
	velocity *= math.max(0, 1 - DRAG * dt)

	-- ── Position update (CFrame-driven; organism constrained to horizontal plane)
	-- The root part is Anchored so we write the CFrame directly each frame.
	-- ORGANISM_Y keeps the organism at a fixed height above the ground plane.
	local newPos = Vector3.new(
		pos.X + velocity.X * dt,
		ORGANISM_Y,
		pos.Z + velocity.Z * dt
	)

	-- ── Rotation update (smooth yaw interpolation) ────────────────────────────
	-- Prefer move direction for facing; fall back to explicit aim direction
	-- (e.g. mouse cursor in WASDMouseAim with no WASD keys held).
	local facing = if desiredMoveDir.Magnitude > 0.05 then desiredMoveDir else desiredFacingDir
	if facing.Magnitude > 0.01 then
		currentYaw = stepYaw(currentYaw, facing, dt)
	end

	root.CFrame = CFrame.new(newPos) * CFrame.Angles(0, currentYaw, 0)
end)

