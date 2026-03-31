--!strict
-- CameraController: top-down 2.5D camera that follows the local player organism.
--
-- Features:
-- - Camera locked above organism with a downward angle (configurable pitch).
-- - Smooth exponential follow with configurable lerp speed.
-- - Scriptable camera type; no Roblox default camera interference.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

-- ── Camera tuning ─────────────────────────────────────────────────────────────
local HEIGHT = 38         -- World units above the organism.
local BACK_OFFSET = 5     -- Small backwards offset for depth cue.
local PITCH_DEG = 65      -- Downward tilt in degrees (90 = straight down).
local SMOOTH = 12         -- Exponential follow speed (higher = tighter follow).

local pitch = math.rad(PITCH_DEG)

-- ── Runtime state ─────────────────────────────────────────────────────────────
local targetPart: BasePart? = nil
local currentCFrame: CFrame? = nil

-- ── Character binding ─────────────────────────────────────────────────────────

local function bindCharacter(char: Model)
	targetPart = char:WaitForChild("HumanoidRootPart") :: BasePart
	currentCFrame = nil
end

player.CharacterAdded:Connect(bindCharacter)
if player.Character then
	bindCharacter(player.Character)
end

-- ── Camera override ───────────────────────────────────────────────────────────

camera.CameraType = Enum.CameraType.Scriptable

RunService.RenderStepped:Connect(function(dt: number)
	if not targetPart then return end

	local focus = targetPart.Position

	-- Fixed top-down offset (no yaw dependency; camera does not rotate with organism).
	local offset = Vector3.new(0, HEIGHT, BACK_OFFSET)
	local desiredPos = focus + offset

	-- Compute look target slightly below focus so organism stays in frame.
	local lookTarget = focus + Vector3.new(0, -math.tan(math.pi / 2 - pitch) * HEIGHT * 0.3, 0)
	local desired = CFrame.lookAt(desiredPos, lookTarget)

	if not currentCFrame then
		currentCFrame = desired
	else
		local alpha = 1 - math.exp(-SMOOTH * dt)
		currentCFrame = currentCFrame:Lerp(desired, alpha)
	end

	camera.CFrame = currentCFrame :: CFrame
end)
