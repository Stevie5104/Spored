--!strict
-- HunterCellAI: fast, aggressive pack hunter that charges players on sight.
-- Has a brief attack telegraph and gains an aggro range bonus when other
-- HunterCells are nearby (pack behaviour).

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local HunterCellAI = {}

export type HunterCellState = {
	attackCooldown: number,
	wanderTarget: Vector3,
	wanderTimer: number,
	attackWindup: number,  -- telegraph pause before each strike
}

local WANDER_RADIUS = 16
local WANDER_INTERVAL_MIN = 2
local WANDER_INTERVAL_MAX = 5
local ATTACK_WINDUP = 0.25    -- seconds of pause before striking
local PACK_NEARBY_RADIUS = 28 -- studs within which another HunterCell counts as a pack member
local PACK_AGGRO_BONUS = 6    -- extra aggro studs per additional living pack member

-- ── Utilities ─────────────────────────────────────────────────────────────────

local function randomWanderTarget(origin: Vector3, radius: number): Vector3
	local angle = math.random() * 2 * math.pi
	local dist = math.random() * radius
	return Vector3.new(
		origin.X + math.cos(angle) * dist,
		origin.Y,
		origin.Z + math.sin(angle) * dist
	)
end

-- Return the nearest player's root part, the Player, and the distance.
local function nearestPlayerRoot(pos: Vector3, maxDist: number): (BasePart?, Player?, number)
	local best: BasePart? = nil
	local bestPlayer: Player? = nil
	local bestDist = maxDist
	for _, p in Players:GetPlayers() do
		local char = p.Character
		if char then
			local rp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if rp then
				local d = (rp.Position - pos).Magnitude
				if d < bestDist then
					bestDist = d
					best = rp
					bestPlayer = p
				end
			end
		end
	end
	return best, bestPlayer, bestDist
end

-- Count living HunterCell enemies within PACK_NEARBY_RADIUS of `pos`.
-- Subtracts 1 because the calling enemy's own model is included.
-- NOTE: This scans the Enemies folder on each call. The initial wave has at most
-- 1–2 HunterCells, so the cost is negligible. If the enemy count grows to 20+,
-- consider passing a pre-built list from EnemyService instead.
local function countNearbyPackMembers(pos: Vector3): number
	local count = 0
	local enemiesFolder = Workspace:FindFirstChild("Enemies") :: Folder?
	if not enemiesFolder then return 0 end
	for _, child in enemiesFolder:GetChildren() do
		local model = child :: Model
		if not model:IsA("Model") then continue end
		local typeTag = model:FindFirstChild("EnemyTypeId") :: StringValue?
		if not typeTag or typeTag.Value ~= "HunterCell" then continue end
		local rootPart = model:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not rootPart then continue end
		local hum = model:FindFirstChildOfClass("Humanoid") :: Humanoid?
		if not hum or hum.Health <= 0 then continue end
		if (rootPart.Position - pos).Magnitude <= PACK_NEARBY_RADIUS then
			count += 1
		end
	end
	return math.max(0, count - 1)
end

-- ── Public API ────────────────────────────────────────────────────────────────

function HunterCellAI.NewState(spawnPos: Vector3): HunterCellState
	return {
		attackCooldown = 0,
		wanderTarget = randomWanderTarget(spawnPos, WANDER_RADIUS),
		wanderTimer = WANDER_INTERVAL_MIN
			+ math.random() * (WANDER_INTERVAL_MAX - WANDER_INTERVAL_MIN),
		attackWindup = 0,
	}
end

-- Update AI for one heartbeat tick.
-- combatService is passed in to avoid a circular module dependency.
function HunterCellAI.Update(
	model: Model,
	def: {
		AggroRange: number,
		AttackRange: number,
		AttackCooldown: number,
		MoveSpeed: number,
		Damage: number,
	},
	state: HunterCellState,
	dt: number,
	spawnPos: Vector3,
	combatService: any
)
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid?
	if not root or not humanoid or humanoid.Health <= 0 then return end

	local pos = root.Position
	state.attackCooldown = math.max(0, state.attackCooldown - dt)

	-- Pack bonus: aggro range grows when other HunterCells are nearby.
	local packCount = countNearbyPackMembers(pos)
	local effectiveAggroRange = def.AggroRange + packCount * PACK_AGGRO_BONUS

	local playerRoot, targetPlayer, playerDist = nearestPlayerRoot(pos, effectiveAggroRange)

	if playerRoot and targetPlayer then
		local toPlayer = Vector3.new(
			playerRoot.Position.X - pos.X,
			0,
			playerRoot.Position.Z - pos.Z
		)

		if playerDist <= def.AttackRange then
			-- Telegraph windup: briefly pause, then strike.
			if state.attackWindup < ATTACK_WINDUP then
				state.attackWindup += dt
				root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
			else
				root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
				if state.attackCooldown <= 0 then
					state.attackCooldown = def.AttackCooldown
					state.attackWindup = 0
					combatService.DamagePlayer(targetPlayer, def.Damage, model)
				end
			end
		else
			-- Rush at the player at full speed.
			state.attackWindup = 0
			local dir = toPlayer.Unit
			root.AssemblyLinearVelocity = Vector3.new(
				dir.X * def.MoveSpeed,
				root.AssemblyLinearVelocity.Y,
				dir.Z * def.MoveSpeed
			)
		end
	else
		-- No target: patrol at a brisk pace.
		state.attackWindup = 0
		state.wanderTimer -= dt
		local toTarget = Vector3.new(
			state.wanderTarget.X - pos.X,
			0,
			state.wanderTarget.Z - pos.Z
		)

		if toTarget.Magnitude < 2 or state.wanderTimer <= 0 then
			state.wanderTarget = randomWanderTarget(spawnPos, WANDER_RADIUS)
			state.wanderTimer = WANDER_INTERVAL_MIN
				+ math.random() * (WANDER_INTERVAL_MAX - WANDER_INTERVAL_MIN)
		else
			local dir = toTarget.Unit
			-- Patrol at 65% of top speed (livelier than other enemy types).
			root.AssemblyLinearVelocity = Vector3.new(
				dir.X * def.MoveSpeed * 0.65,
				root.AssemblyLinearVelocity.Y,
				dir.Z * def.MoveSpeed * 0.65
			)
		end
	end
end

return HunterCellAI
