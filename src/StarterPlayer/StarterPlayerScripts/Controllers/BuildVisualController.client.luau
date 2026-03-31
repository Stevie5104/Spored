--!strict
-- BuildVisualController: updates the player's organism visual to reflect
-- their current build (body type + equipped parts) using colored placeholder geometry.
--
-- Listens to the BuildChanged RemoteEvent from PlayerBuildService.
-- Rebuilds visual attachments on character spawn and after every build change.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BodyData = require(ReplicatedStorage.Modules.BodyData)
local PartData = require(ReplicatedStorage.Modules.PartData)

local player = Players.LocalPlayer

-- ── Visual configuration ──────────────────────────────────────────────────────

-- Body-type to Color3 mapping for the main organism sphere.
local BODY_COLORS: { [string]: Color3 } = {
	StarterBlob    = Color3.fromRGB(100, 200, 120),  -- fresh green
	ArmoredShell   = Color3.fromRGB(160, 160, 160),  -- steel gray
	SwiftNucleus   = Color3.fromRGB(80, 140, 240),   -- electric blue
	VenomMantle    = Color3.fromRGB(170, 80, 220),   -- toxic purple
}

-- Part-category to Color3 mapping for attached part visuals.
local CATEGORY_COLORS: { [string]: Color3 } = {
	Attack   = Color3.fromRGB(230, 70, 60),   -- aggressive red
	Defense  = Color3.fromRGB(100, 160, 200), -- defensive blue
	Movement = Color3.fromRGB(60, 220, 210),  -- speed teal
	Utility  = Color3.fromRGB(240, 200, 50),  -- utility gold
}

-- Local-space offsets for each slot name (relative to HumanoidRootPart).
local SLOT_OFFSETS: { [string]: Vector3 } = {
	Front  = Vector3.new(0, 0, -3),
	Front2 = Vector3.new(0, 0, -4.5),
	Rear   = Vector3.new(0, 0, 3),
	Rear2  = Vector3.new(0, 0, 4.5),
	Left   = Vector3.new(-3, 0, 0),
	Left2  = Vector3.new(-4.5, 0, 0),
	Right  = Vector3.new(3, 0, 0),
	Right2 = Vector3.new(4.5, 0, 0),
	Core   = Vector3.new(0, 1.2, 0),
}

-- Tag used to identify visual attachment Parts so we can clean them up.
local VISUAL_TAG = "OrganismVisual"

-- ── Utility: create a welded visual Part ──────────────────────────────────────

-- Creates a sphere Part welded to `rootPart` at a given local-space offset.
local function createVisualPart(
	rootPart: BasePart,
	offset: Vector3,
	size: Vector3,
	color: Color3,
	transparency: number
): Part
	local part = Instance.new("Part")
	part.Name = VISUAL_TAG
	part.Shape = Enum.PartType.Ball
	part.Size = size
	part.Color = color
	part.Transparency = transparency
	part.CanCollide = false
	part.CastShadow = false
	part.Anchored = false
	part.Massless = true

	-- Position relative to rootPart BEFORE creating the WeldConstraint.
	-- WeldConstraint records the relative CFrame at creation time; setting CFrame
	-- after the weld would have no lasting effect.
	part.CFrame = rootPart.CFrame * CFrame.new(offset)
	part.Parent = rootPart.Parent  -- sibling of rootPart inside the character model

	-- Weld to root part so it moves with the character.
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = rootPart
	weld.Part1 = part
	weld.Parent = part

	-- Tag for identification.
	local tag = Instance.new("StringValue")
	tag.Name = "VisualTag"
	tag.Value = VISUAL_TAG
	tag.Parent = part

	return part
end

-- ── Core visual builder ───────────────────────────────────────────────────────

-- Removes all existing organism visual parts from the character.
local function clearVisuals(character: Model)
	for _, child in character:GetDescendants() do
		if child:IsA("StringValue") and child.Name == "VisualTag" and child.Value == VISUAL_TAG then
			local part = child.Parent
			if part then
				part:Destroy()
			end
		end
	end
end

-- Applies body + part visuals to the character based on the given build state.
local function applyVisuals(character: Model, bodyId: string, slots: { [string]: string })
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then return end

	clearVisuals(character)

	-- Determine body color and size.
	local bodyColor = BODY_COLORS[bodyId] or Color3.fromRGB(150, 150, 150)
	local bodyDef = BodyData[bodyId]

	-- Body sphere: scale size loosely with BaseHealth for visual variety.
	local healthScale = if bodyDef then math.clamp(bodyDef.BaseHealth / 100, 0.8, 1.8) else 1
	local bodySize = Vector3.new(2.5 * healthScale, 2.5 * healthScale, 2.5 * healthScale)

	createVisualPart(rootPart, Vector3.new(0, 0.5, 0), bodySize, bodyColor, 0)

	-- Equipped part visuals: small colored spheres at each slot offset.
	for slotName, partId in slots do
		local partDef = PartData[partId]
		if not partDef then continue end

		local offset = SLOT_OFFSETS[slotName]
		if not offset then continue end  -- unknown slot layout

		local partColor = CATEGORY_COLORS[partDef.Category] or Color3.fromRGB(200, 200, 200)

		-- Scale part visual slightly with CapacityCost for weight indication.
		local scale = math.clamp(0.6 + partDef.CapacityCost * 0.12, 0.6, 1.2)
		local partSize = Vector3.new(scale, scale, scale)

		createVisualPart(rootPart, offset, partSize, partColor, 0.1)
	end
end

-- ── Build state tracking ──────────────────────────────────────────────────────

local latestBodyId = "StarterBlob"
local latestSlots: { [string]: string } = {}

local function rebuildVisuals()
	local character = player.Character
	if character then
		applyVisuals(character, latestBodyId, latestSlots)
	end
end

-- Re-apply visuals whenever the character respawns.
player.CharacterAdded:Connect(function(character: Model)
	-- Wait for the root to fully load before placing geometry.
	character:WaitForChild("HumanoidRootPart", 5)
	task.wait()  -- defer one Heartbeat step to let the character settle before placing geometry
	applyVisuals(character, latestBodyId, latestSlots)
end)

-- Apply to any existing character at script startup.
if player.Character then
	local root = player.Character:FindFirstChild("HumanoidRootPart")
	if root then
		applyVisuals(player.Character, latestBodyId, latestSlots)
	end
end

-- ── RemoteEvent listener ──────────────────────────────────────────────────────

task.spawn(function()
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 10) :: Folder?
	if not remotes then
		warn("[BuildVisualController] Remotes folder not found.")
		return
	end

	local buildChangedRemote = remotes:WaitForChild("BuildChanged", 10) :: RemoteEvent?
	if not buildChangedRemote then
		warn("[BuildVisualController] BuildChanged remote not found.")
		return
	end

	buildChangedRemote.OnClientEvent:Connect(function(bodyId: unknown, slots: unknown)
		if typeof(bodyId) ~= "string" then return end
		if typeof(slots) ~= "table" then return end

		-- Build a clean typed copy of the slots snapshot.
		local typedSlots: { [string]: string } = {}
		for k, v in slots :: { [any]: any } do
			if typeof(k) == "string" and typeof(v) == "string" then
				typedSlots[k :: string] = v :: string
			end
		end

		latestBodyId = bodyId :: string
		latestSlots = typedSlots
		rebuildVisuals()
	end)
end)
