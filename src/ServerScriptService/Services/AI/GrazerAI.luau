--!strict
-- GrazerAI: passive wanderer that flees when a player gets too close.
--
-- Behavior:
--   - Wanders to random nearby positions at low speed.
--   - When a player comes within AggroRange, turns and flees.
--   - Resumes wandering once the threat is gone.

local Players = game:GetService("Players")

local GrazerAI = {}

-- Per-instance state stored by EnemyService.
export type GrazerState = {
	wanderTarget: Vector3,
	wanderTimer: number,   -- countdown until next wander target pick
	isFleeing: boolean,
}

local WANDER_INTERVAL_MIN = 3
local WANDER_INTERVAL_MAX = 7
local WANDER_RADIUS = 18     -- max stud radius from spawn for wander targets
local FLEE_SPEED_MULT = 1.5  -- multiplier over base MoveSpeed when fleeing

-- Pick a random ground position within radius of the given origin.
local function randomWanderTarget(origin: Vector3, radius: number): Vector3
	local angle = math.random() * 2 * math.pi
	local dist = math.random() * radius
	return Vector3.new(
		origin.X + math.cos(angle) * dist,
		origin.Y,
		origin.Z + math.sin(angle) * dist
	)
end

-- Find the nearest player character and return its root part (or nil if none in range).
local function nearestPlayerRoot(pos: Vector3, maxDist: number): (BasePart?, number)
	local best: BasePart? = nil
	local bestDist = maxDist
	for _, player in Players:GetPlayers() do
		local char = player.Character
		if char then
			local rp = char:FindFirstChild("OrganismRootPart") :: BasePart?
			if rp then
				local d = (rp.Position - pos).Magnitude
				if d < bestDist then
					bestDist = d
					best = rp
				end
			end
		end
	end
	return best, bestDist
end

-- Create fresh AI state for a new Grazer instance.
function GrazerAI.NewState(spawnPos: Vector3): GrazerState
	return {
		wanderTarget = randomWanderTarget(spawnPos, WANDER_RADIUS),
		wanderTimer = math.random(WANDER_INTERVAL_MIN, WANDER_INTERVAL_MAX),
		isFleeing = false,
	}
end

-- Update AI logic for one heartbeat tick.
-- model: the enemy Model instance
-- def: the EnemyDef from EnemyData
-- state: the GrazerState for this instance
-- dt: delta time in seconds
-- spawnPos: original spawn position used to constrain wander range
function GrazerAI.Update(
	model: Model,
	def: { AggroRange: number, MoveSpeed: number },
	state: GrazerState,
	dt: number,
	spawnPos: Vector3
)
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid?
	if not root or not humanoid or humanoid.Health <= 0 then return end

	local pos = root.Position
	local playerRoot, playerDist = nearestPlayerRoot(pos, def.AggroRange)

	if playerRoot and playerDist < def.AggroRange then
		-- Flee: move directly away from the nearest player.
		state.isFleeing = true
		local awayDir = Vector3.new(pos.X - playerRoot.Position.X, 0, pos.Z - playerRoot.Position.Z)
		if awayDir.Magnitude > 1e-3 then
			awayDir = awayDir.Unit
			local fleeSpeed = def.MoveSpeed * FLEE_SPEED_MULT
			root.AssemblyLinearVelocity = Vector3.new(
				awayDir.X * fleeSpeed,
				root.AssemblyLinearVelocity.Y,
				awayDir.Z * fleeSpeed
			)
		end
	else
		state.isFleeing = false

		-- Wander: move toward the current wander target.
		state.wanderTimer -= dt
		local toTarget = Vector3.new(
			state.wanderTarget.X - pos.X,
			0,
			state.wanderTarget.Z - pos.Z
		)

		if toTarget.Magnitude < 2 or state.wanderTimer <= 0 then
			-- Pick a new wander target.
			state.wanderTarget = randomWanderTarget(spawnPos, WANDER_RADIUS)
			state.wanderTimer = WANDER_INTERVAL_MIN
				+ math.random() * (WANDER_INTERVAL_MAX - WANDER_INTERVAL_MIN)
		else
			local dir = toTarget.Unit
			local speed = def.MoveSpeed * 0.6  -- wander at 60% speed
			root.AssemblyLinearVelocity = Vector3.new(
				dir.X * speed,
				root.AssemblyLinearVelocity.Y,
				dir.Z * speed
			)
		end
	end
end

return GrazerAI
