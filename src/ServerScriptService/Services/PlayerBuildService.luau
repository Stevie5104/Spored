--!strict
-- PlayerBuildService: server-side validation for equipping/unequipping parts to slots.

local BodyData = require(game:GetService("ReplicatedStorage").Modules.BodyData)
local PartData = require(game:GetService("ReplicatedStorage").Modules.PartData)

local PlayerBuildService = {}

-- Per-player equipped build state.
-- build[userId] = { bodyId, slots = { [slotName] = partId | nil } }
export type PlayerBuild = {
	BodyId: string,
	Slots: { [string]: string },
}

local builds: { [number]: PlayerBuild } = {}

local function getOrCreateBuild(player: Player): PlayerBuild
	if not builds[player.UserId] then
		builds[player.UserId] = {
			BodyId = "StarterBlob",
			Slots = {},
		}
	end
	return builds[player.UserId]
end

-- Returns total capacity currently used by equipped parts.
local function usedCapacity(build: PlayerBuild): number
	local total = 0
	for _, partId in build.Slots do
		local part = PartData[partId]
		if part then
			total += part.CapacityCost
		end
	end
	return total
end

-- Equip a part into a slot for a player.
-- Returns (success, errorMessage)
function PlayerBuildService.EquipPart(player: Player, slotName: string, partId: string): (boolean, string?)
	local build = getOrCreateBuild(player)
	local bodyDef = BodyData[build.BodyId]
	local partDef = PartData[partId]

	if not bodyDef then
		return false, "Invalid body"
	end
	if not partDef then
		return false, "Unknown part: " .. partId
	end

	-- Check slot exists on body
	local slotValid = false
	for _, slot in bodyDef.SlotLayout do
		if slot == slotName then
			slotValid = true
			break
		end
	end
	if not slotValid then
		return false, "Slot '" .. slotName .. "' does not exist on body '" .. build.BodyId .. "'"
	end

	-- Check slot type compatibility
	local slotCompatible = false
	for _, validSlot in partDef.ValidSlots do
		if validSlot == slotName then
			slotCompatible = true
			break
		end
	end
	if not slotCompatible then
		return false, "Part '" .. partId .. "' is not compatible with slot '" .. slotName .. "'"
	end

	-- Compute capacity after equip (remove existing part in slot first)
	local existing = build.Slots[slotName]
	local existingCost = 0
	if existing then
		local existingPart = PartData[existing]
		if existingPart then
			existingCost = existingPart.CapacityCost
		end
	end

	local newUsed = usedCapacity(build) - existingCost + partDef.CapacityCost
	if newUsed > bodyDef.Capacity then
		return false, string.format(
			"Capacity exceeded: need %d total but body allows %d",
			newUsed,
			bodyDef.Capacity
		)
	end

	build.Slots[slotName] = partId
	return true, nil
end

-- Unequip a part from a slot.
-- Returns (success, errorMessage)
function PlayerBuildService.UnequipPart(player: Player, slotName: string): (boolean, string?)
	local build = getOrCreateBuild(player)
	if not build.Slots[slotName] then
		return false, "No part equipped in slot '" .. slotName .. "'"
	end
	build.Slots[slotName] = nil
	return true, nil
end

-- Change the active body for a player (resets slots).
-- Returns (success, errorMessage)
function PlayerBuildService.SetBody(player: Player, bodyId: string): (boolean, string?)
	if not BodyData[bodyId] then
		return false, "Unknown body: " .. bodyId
	end
	builds[player.UserId] = {
		BodyId = bodyId,
		Slots = {},
	}
	return true, nil
end

-- Returns a read-only snapshot of the player's current build.
function PlayerBuildService.GetBuild(player: Player): PlayerBuild
	return getOrCreateBuild(player)
end

-- Clean up on player leave.
local function cleanPlayer(player: Player)
	builds[player.UserId] = nil
end

function PlayerBuildService.Init()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	game:GetService("Players").PlayerRemoving:Connect(cleanPlayer)

	-- Wire RemoteFunction for client equip requests.
	local remoteFolder = ReplicatedStorage:FindFirstChild("Remotes")
	if not remoteFolder then
		local folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
		remoteFolder = folder
	end

	local equipRemote = remoteFolder:FindFirstChild("EquipPart") :: RemoteFunction?
	if not equipRemote then
		local remote = Instance.new("RemoteFunction")
		remote.Name = "EquipPart"
		remote.Parent = remoteFolder
		equipRemote = remote
	end

	local unequipRemote = remoteFolder:FindFirstChild("UnequipPart") :: RemoteFunction?
	if not unequipRemote then
		local remote = Instance.new("RemoteFunction")
		remote.Name = "UnequipPart"
		remote.Parent = remoteFolder
		unequipRemote = remote
	end

	equipRemote.OnServerInvoke = function(player: Player, slotName: unknown, partId: unknown): (boolean, string?)
		if typeof(slotName) ~= "string" or typeof(partId) ~= "string" then
			return false, "Invalid arguments"
		end
		return PlayerBuildService.EquipPart(player, slotName :: string, partId :: string)
	end

	unequipRemote.OnServerInvoke = function(player: Player, slotName: unknown): (boolean, string?)
		if typeof(slotName) ~= "string" then
			return false, "Invalid arguments"
		end
		return PlayerBuildService.UnequipPart(player, slotName :: string)
	end
end

return PlayerBuildService
