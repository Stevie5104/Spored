--!strict
-- VenomBlobAI: ranged attacker that keeps distance and fires poison projectiles.
--
-- Behavior:
--   - Maintains a preferred engagement distance from players (mid-range).
--   - Fires a slow-moving poison projectile toward the player when cooldown is ready.
--   - Leaves short-lived poison pools on the ground while moving.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local VenomBlobAI = {}

export type VenomBlobState = {
	attackCooldown: number,
	poisonTrailTimer: number,   -- countdown until next poison pool is dropped
}

-- Preferred distance from target: blob tries to stay at this range.
local PREFERRED_DIST_MIN = 6
local PREFERRED_DIST_MAX = 9

-- Poison pool settings.
local POISON_POOL_INTERVAL = 2.5   -- seconds between pool drops while moving
local POISON_POOL_DURATION = 6     -- seconds before pool disappears
local POISON_POOL_DAMAGE = 5       -- damage per tick inside pool
local POISON_POOL_TICK = 1.0       -- seconds between damage ticks
local POISON_POOL_RADIUS = 3       -- visual radius of pool

-- Projectile settings.
local PROJECTILE_SPEED = 18        -- studs per second
local PROJECTILE_MAX_TRAVEL = 25   -- studs before projectile expires
local PROJECTILE_HIT_RADIUS = 2.5  -- hit detection radius in studs

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

-- Spawn a poison pool Part at the given world position.
-- The pool deals periodic damage to any player standing in it.
local function spawnPoisonPool(pos: Vector3, combatService: any)
	local pool = Instance.new("Part")
	pool.Name = "PoisonPool"
	pool.Shape = Enum.PartType.Cylinder
	pool.Size = Vector3.new(0.3, POISON_POOL_RADIUS * 2, POISON_POOL_RADIUS * 2)
	pool.CFrame = CFrame.new(pos.X, pos.Y - 0.5, pos.Z) * CFrame.Angles(0, 0, math.pi / 2)
	pool.Anchored = true
	pool.CanCollide = false
	pool.Transparency = 0.55
	pool.Color = Color3.fromRGB(80, 200, 60)   -- toxic green
	pool.CastShadow = false
	pool.Parent = Workspace

	-- Tick damage while the pool lives.
	local elapsed = 0
	local tickTimer = 0
	local connection: RBXScriptConnection

	connection = game:GetService("RunService").Heartbeat:Connect(function(dt: number)
		elapsed += dt
		tickTimer += dt

		if tickTimer >= POISON_POOL_TICK then
			tickTimer -= POISON_POOL_TICK
			-- Damage any player standing inside the pool radius.
			for _, player in Players:GetPlayers() do
				local char = player.Character
				if char then
					local rp = char:FindFirstChild("OrganismRootPart") :: BasePart?
					if rp then
						local flatDist = Vector3.new(
							rp.Position.X - pos.X,
							0,
							rp.Position.Z - pos.Z
						).Magnitude
						if flatDist <= POISON_POOL_RADIUS then
							combatService.DamagePlayer(player, POISON_POOL_DAMAGE, nil)
						end
					end
				end
			end
		end

		if elapsed >= POISON_POOL_DURATION then
			connection:Disconnect()
			if pool.Parent then
				pool:Destroy()
			end
		end
	end)
end

-- Fire a poison projectile from the enemy toward the player.
-- The projectile moves in a straight line and damages the first player it reaches.
local function fireProjectile(fromPos: Vector3, toPos: Vector3, damage: number, combatService: any)
	local projectile = Instance.new("Part")
	projectile.Name = "VenomProjectile"
	projectile.Shape = Enum.PartType.Ball
	projectile.Size = Vector3.new(1.2, 1.2, 1.2)
	projectile.CFrame = CFrame.new(fromPos)
	projectile.CanCollide = false
	projectile.CastShadow = false
	projectile.Transparency = 0.3
	projectile.Color = Color3.fromRGB(60, 220, 80)
	projectile.Parent = Workspace

	local traveled = 0

	local dir = Vector3.new(toPos.X - fromPos.X, 0, toPos.Z - fromPos.Z)
	if dir.Magnitude < 1e-3 then
		projectile:Destroy()
		return
	end
	dir = dir.Unit

	local connection: RBXScriptConnection
	connection = game:GetService("RunService").Heartbeat:Connect(function(dt: number)
		if not projectile.Parent then
			connection:Disconnect()
			return
		end

		local step = PROJECTILE_SPEED * dt
		traveled += step
		projectile.CFrame = projectile.CFrame + dir * step

		-- Check hit against all players.
		for _, player in Players:GetPlayers() do
			local char = player.Character
			if char then
				local rp = char:FindFirstChild("OrganismRootPart") :: BasePart?
				if rp then
					local dist = (rp.Position - projectile.Position).Magnitude
					if dist < PROJECTILE_HIT_RADIUS then
						combatService.DamagePlayer(player, damage, nil)
						connection:Disconnect()
						projectile:Destroy()
						return
					end
				end
			end
		end

		-- Expire after max travel distance.
		if traveled >= PROJECTILE_MAX_TRAVEL then
			connection:Disconnect()
			projectile:Destroy()
		end
	end)
end

function VenomBlobAI.NewState(): VenomBlobState
	return {
		attackCooldown = 0,
		poisonTrailTimer = POISON_POOL_INTERVAL,
	}
end

function VenomBlobAI.Update(
	model: Model,
	def: { AggroRange: number, AttackRange: number, AttackCooldown: number, MoveSpeed: number, Damage: number },
	state: VenomBlobState,
	dt: number,
	combatService: any
)
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid?
	if not root or not humanoid or humanoid.Health <= 0 then return end

	local pos = root.Position
	state.attackCooldown = math.max(0, state.attackCooldown - dt)

	local playerRoot, targetPlayer, playerDist = nearestPlayerRoot(pos, def.AggroRange)

	if playerRoot and targetPlayer and playerDist < def.AggroRange then
		local toPlayer = Vector3.new(
			playerRoot.Position.X - pos.X,
			0,
			playerRoot.Position.Z - pos.Z
		)
		local flatDist = toPlayer.Magnitude

		-- Movement: maintain preferred distance range.
		if flatDist < PREFERRED_DIST_MIN then
			-- Too close: retreat away from player.
			local awayDir = if flatDist > 1e-3 then (-toPlayer.Unit) else Vector3.new(1, 0, 0)
			root.AssemblyLinearVelocity = Vector3.new(
				awayDir.X * def.MoveSpeed,
				root.AssemblyLinearVelocity.Y,
				awayDir.Z * def.MoveSpeed
			)
		elseif flatDist > PREFERRED_DIST_MAX then
			-- Too far: close in toward player.
			local chaseDir = if flatDist > 1e-3 then toPlayer.Unit else Vector3.new(0, 0, 1)
			root.AssemblyLinearVelocity = Vector3.new(
				chaseDir.X * def.MoveSpeed,
				root.AssemblyLinearVelocity.Y,
				chaseDir.Z * def.MoveSpeed
			)
		else
			-- In preferred range: stop moving.
			root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
		end

		-- Attack: fire projectile when cooldown is ready and player is in attack range.
		if state.attackCooldown <= 0 and flatDist <= def.AttackRange then
			state.attackCooldown = def.AttackCooldown
			fireProjectile(pos, playerRoot.Position, def.Damage, combatService)
		end

		-- Poison trail: drop a pool periodically while the blob is near a player.
		state.poisonTrailTimer -= dt
		if state.poisonTrailTimer <= 0 then
			state.poisonTrailTimer = POISON_POOL_INTERVAL
			spawnPoisonPool(pos, combatService)
		end
	else
		-- No target in range: idle (gentle drift toward zero velocity).
		root.AssemblyLinearVelocity = root.AssemblyLinearVelocity * math.max(0, 1 - 5 * dt)
	end
end

return VenomBlobAI
