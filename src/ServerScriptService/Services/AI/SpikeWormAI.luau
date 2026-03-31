--!strict
-- SpikeWormAI: aggressive melee chaser that charges and attacks nearby players.
--
-- Behavior:
--   - Idles with a slow patrol wander when no player is in AggroRange.
--   - Charges directly at the nearest player once detected.
--   - Deals melee damage when within AttackRange, respecting AttackCooldown.

local Players = game:GetService("Players")

local SpikeWormAI = {}

export type SpikeWormState = {
	attackCooldown: number,   -- remaining seconds until next attack is ready
	wanderTarget: Vector3,
	wanderTimer: number,
}

local WANDER_RADIUS = 12
local WANDER_INTERVAL = 5

local function nearestPlayerRoot(pos: Vector3, maxDist: number): (BasePart?, Player?, number)
	local best: BasePart? = nil
	local bestPlayer: Player? = nil
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
					bestPlayer = player
				end
			end
		end
	end
	return best, bestPlayer, bestDist
end

local function randomWanderTarget(origin: Vector3, radius: number): Vector3
	local angle = math.random() * 2 * math.pi
	local dist = math.random() * radius
	return Vector3.new(
		origin.X + math.cos(angle) * dist,
		origin.Y,
		origin.Z + math.sin(angle) * dist
	)
end

function SpikeWormAI.NewState(spawnPos: Vector3): SpikeWormState
	return {
		attackCooldown = 0,
		wanderTarget = randomWanderTarget(spawnPos, WANDER_RADIUS),
		wanderTimer = WANDER_INTERVAL,
	}
end

-- CombatService is passed in to avoid circular dependency in the AI module itself.
function SpikeWormAI.Update(
	model: Model,
	def: { AggroRange: number, AttackRange: number, AttackCooldown: number, MoveSpeed: number, Damage: number },
	state: SpikeWormState,
	dt: number,
	spawnPos: Vector3,
	combatService: any
)
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid?
	if not root or not humanoid or humanoid.Health <= 0 then return end

	local pos = root.Position
	state.attackCooldown = math.max(0, state.attackCooldown - dt)

	local playerRoot, targetPlayer, playerDist = nearestPlayerRoot(pos, def.AggroRange)

	if playerRoot and targetPlayer and playerDist < def.AggroRange then
		-- Chase the player.
		local toPlayer = Vector3.new(
			playerRoot.Position.X - pos.X,
			0,
			playerRoot.Position.Z - pos.Z
		)

		if playerDist <= def.AttackRange then
			-- Within attack range: stop moving and attack if cooldown ready.
			root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)

			if state.attackCooldown <= 0 then
				state.attackCooldown = def.AttackCooldown
				-- Apply melee damage directly (server-authoritative).
				combatService.DamagePlayer(targetPlayer, def.Damage, model)
			end
		else
			-- Rush toward the player at full speed.
			local dir = toPlayer.Unit
			root.AssemblyLinearVelocity = Vector3.new(
				dir.X * def.MoveSpeed,
				root.AssemblyLinearVelocity.Y,
				dir.Z * def.MoveSpeed
			)
		end
	else
		-- No target: patrol with a slow wander.
		state.wanderTimer -= dt
		local toTarget = Vector3.new(
			state.wanderTarget.X - pos.X,
			0,
			state.wanderTarget.Z - pos.Z
		)

		if toTarget.Magnitude < 2 or state.wanderTimer <= 0 then
			state.wanderTarget = randomWanderTarget(spawnPos, WANDER_RADIUS)
			state.wanderTimer = WANDER_INTERVAL
		else
			local dir = toTarget.Unit
			root.AssemblyLinearVelocity = Vector3.new(
				dir.X * def.MoveSpeed * 0.5,
				root.AssemblyLinearVelocity.Y,
				dir.Z * def.MoveSpeed * 0.5
			)
		end
	end
end

return SpikeWormAI
