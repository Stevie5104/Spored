--!strict
-- OrganismEntity: factory and API for the custom player organism model.
--
-- Creates a non-Humanoid Model containing:
--   • OrganismRootPart  – physics root; movement velocity is applied here.
--   • Slot Attachments  – named anchor points for mutation part attachment.
--   • Health / MaxHealth NumberValues – tracked instead of a Humanoid.
--
-- Slot-type categories enforce which mutation part types fit which slots:
--   front  → Attack    (jaws, spitters, tendrils)
--   side   → Defense   (shell plates, membranes)
--   rear   → Movement  (flagella, jet sacs)
--   core   → Utility   (healing glands, toxin clouds)
--
-- Static helpers are callable from both server and client (all data lives in
-- ReplicatedStorage so no environment restriction applies).
--
-- Usage (server, via OrganismService):
--   local OrganismEntity = require(ReplicatedStorage.Modules.OrganismEntity)
--   local organism = OrganismEntity.new("StarterBlob")
--   organism.Model.Parent = Workspace
--
-- Usage (shared stat computation, callable from client or server):
--   local stats = OrganismEntity.ComputeStats("StarterBlob", equippedSlots)

local BodyData  = require(script.Parent.BodyData)
local PartData  = require(script.Parent.PartData)
local TraitData = require(script.Parent.TraitData)

local OrganismEntity = {}
OrganismEntity.__index = OrganismEntity

-- ── Public types ──────────────────────────────────────────────────────────────

export type OrganismStats = {
	Health       : number,
	MaxHealth    : number,
	MoveSpeed    : number,
	Acceleration : number,
	TurnSpeed    : number,
	Capacity     : number,
	UsedCapacity : number,
}

export type OrganismInstance = typeof(setmetatable(
	{} :: {
		Model         : Model,
		RootPart      : BasePart,
		Stats         : OrganismStats,
		BodyId        : string,
		AttachedParts : { [string]: BasePart },
	},
	OrganismEntity
))

-- ── Slot-type ↔ part-category compatibility ───────────────────────────────────
-- Maps every recognised slot name to its slot-type category.
-- Extend this table when new slot names are introduced.
local SLOT_TYPE_MAP: { [string]: string } = {
	Front  = "front", Front2 = "front",
	Left   = "side",  Left2  = "side",
	Right  = "side",  Right2 = "side",
	Rear   = "rear",  Rear2  = "rear",
	Core   = "core",
}

-- Maps each slot-type category to the single part category it accepts.
local SLOT_CATEGORY_COMPAT: { [string]: string } = {
	front = "Attack",
	side  = "Defense",
	rear  = "Movement",
	core  = "Utility",
}

-- ── Physical model defaults ───────────────────────────────────────────────────

local DEFAULT_ROOT_SIZE = Vector3.new(4, 1.5, 4)
local DEFAULT_COLOR     = Color3.fromRGB(80, 180, 240)

-- PhysicalProperties parameters for the organism root part.
-- Low elasticity keeps the organism from bouncing; moderate friction gives
-- enough traction without interfering with velocity-driven movement.
local ORGANISM_DENSITY           = 1
local ORGANISM_FRICTION          = 0.3
local ORGANISM_ELASTICITY        = 0
local ORGANISM_FRICTION_WEIGHT   = 0
local ORGANISM_ELASTICITY_WEIGHT = 0

-- Default turn speed in degrees-per-second converted to radians.
-- 540 °/s gives smooth rotation without feeling sluggish at normal game speeds.
-- Modify this constant or override via ComputeStats() when adding turn-rate parts.
local DEFAULT_TURN_SPEED = math.rad(540)

-- ── Internal: build slot Attachments ─────────────────────────────────────────
-- Creates one Attachment per slot in slotLayout and parents it to rootPart.
-- Slots of the same type are spread evenly along their body edge.
local function buildSlotAttachments(rootPart: BasePart, slotLayout: { [number]: string })
	local halfX = rootPart.Size.X / 2
	local halfZ = rootPart.Size.Z / 2

	-- Count how many slots of each type appear so we can centre-spread them.
	local typeCount: { [string]: number } = {}
	for _, slotName in slotLayout do
		local t = SLOT_TYPE_MAP[slotName] or "core"
		typeCount[t] = (typeCount[t] or 0) + 1
	end

	local typeIndex: { [string]: number } = {}
	for _, slotName in slotLayout do
		local t   = SLOT_TYPE_MAP[slotName] or "core"
		local cnt = typeCount[t] or 1
		typeIndex[t] = (typeIndex[t] or 0) + 1

		-- Symmetrical spread: centre the group around the midpoint of the edge.
		local spread = (typeIndex[t] - 1) - (cnt - 1) / 2

		local localCFrame: CFrame
		if t == "front" then
			localCFrame = CFrame.new(spread * 0.8, 0, -(halfZ + 0.6))
		elseif t == "side" then
			local side = if slotName:find("Left") then -1 else 1
			localCFrame = CFrame.new(side * (halfX + 0.6), 0, spread * 0.8)
		elseif t == "rear" then
			localCFrame = CFrame.new(spread * 0.8, 0, halfZ + 0.6)
		else -- core
			localCFrame = CFrame.new(0, 0.5, 0)
		end

		local att    = Instance.new("Attachment")
		att.Name     = slotName
		att.CFrame   = localCFrame
		att.Parent   = rootPart
	end
end

-- ── Public: factory ───────────────────────────────────────────────────────────

--- Creates a new OrganismInstance from a body definition key.
-- @param bodyId  Key in BodyData (e.g. "StarterBlob").
-- @returns OrganismInstance with Model, RootPart, Stats and slot Attachments.
function OrganismEntity.new(bodyId: string): OrganismInstance
	local bodyDef = BodyData[bodyId]
	assert(bodyDef, "OrganismEntity.new: unknown bodyId '" .. tostring(bodyId) .. "'")

	-- ── Model ──────────────────────────────────────────────────────────────────
	local model   = Instance.new("Model")
	model.Name    = "Organism"

	-- ── RootPart ───────────────────────────────────────────────────────────────
	local root                        = Instance.new("Part")
	root.Name                         = "OrganismRootPart"
	root.Size                         = DEFAULT_ROOT_SIZE
	root.Color                        = DEFAULT_COLOR
	root.Material                     = Enum.Material.SmoothPlastic
	root.Anchored                     = true
	root.CanCollide                   = false
	root.Transparency                 = 1
	root.CastShadow                   = false
	root.CustomPhysicalProperties     = PhysicalProperties.new(
		ORGANISM_DENSITY,
		ORGANISM_FRICTION,
		ORGANISM_ELASTICITY,
		ORGANISM_FRICTION_WEIGHT,
		ORGANISM_ELASTICITY_WEIGHT
	)
	root.Parent       = model
	model.PrimaryPart = root

	-- ── Health values (read by HUDController and CombatService) ───────────────
	local healthVal        = Instance.new("NumberValue")
	healthVal.Name         = "Health"
	healthVal.Value        = bodyDef.BaseHealth
	healthVal.Parent       = model

	local maxHealthVal     = Instance.new("NumberValue")
	maxHealthVal.Name      = "MaxHealth"
	maxHealthVal.Value     = bodyDef.BaseHealth
	maxHealthVal.Parent    = model

	-- ── Slot Attachments ───────────────────────────────────────────────────────
	buildSlotAttachments(root, bodyDef.SlotLayout)

	-- ── Base stats ─────────────────────────────────────────────────────────────
	local stats: OrganismStats = {
		Health       = bodyDef.BaseHealth,
		MaxHealth    = bodyDef.BaseHealth,
		MoveSpeed    = bodyDef.MoveSpeed,
		Acceleration = 80,
		TurnSpeed    = DEFAULT_TURN_SPEED,
		Capacity     = bodyDef.Capacity,
		UsedCapacity = 0,
	}

	local self = setmetatable({
		Model         = model,
		RootPart      = root,
		Stats         = stats,
		BodyId        = bodyId,
		AttachedParts = {},
	} :: any, OrganismEntity) :: OrganismInstance

	return self
end

-- ── Public: shared stat computation ──────────────────────────────────────────

--- Compute effective OrganismStats for a body + equipped-slots snapshot.
-- Side-effect-free; callable from both server and client.
-- @param bodyId        Key in BodyData.
-- @param equippedSlots { [slotName]: partId } from PlayerBuildService.
-- @returns OrganismStats with all trait modifiers applied.
function OrganismEntity.ComputeStats(
	bodyId        : string,
	equippedSlots : { [string]: string }
): OrganismStats
	local bodyDef = BodyData[bodyId]
	assert(bodyDef, "OrganismEntity.ComputeStats: unknown bodyId '" .. tostring(bodyId) .. "'")

	local stats: OrganismStats = {
		Health       = bodyDef.BaseHealth,
		MaxHealth    = bodyDef.BaseHealth,
		MoveSpeed    = bodyDef.MoveSpeed,
		Acceleration = 80,
		TurnSpeed    = DEFAULT_TURN_SPEED,
		Capacity     = bodyDef.Capacity,
		UsedCapacity = 0,
	}

	-- Accumulate capacity usage and apply trait modifiers to movement/health stats.
	for _, partId in equippedSlots do
		local partDef = PartData[partId]
		if not partDef then continue end

		stats.UsedCapacity += partDef.CapacityCost

		local traits = partDef.Traits
		if not traits then continue end

		for _, traitId in traits do
			local traitDef = TraitData[traitId]
			if not traitDef then continue end

			for _, mod in traitDef.Modifiers do
				if mod.Stat == "MoveSpeed" then
					if mod.Type == "Multiply" then
						stats.MoveSpeed *= mod.Value
					elseif mod.Type == "Add" then
						stats.MoveSpeed += mod.Value
					end
				elseif mod.Stat == "BaseHealth" then
					if mod.Type == "Multiply" then
						stats.MaxHealth = math.round(stats.MaxHealth * mod.Value)
						stats.Health    = math.min(stats.Health, stats.MaxHealth)
					elseif mod.Type == "Add" then
						stats.MaxHealth += mod.Value
					end
				end
				-- Damage / Cooldown / EnergyCost modifiers are applied
				-- per-attack inside CombatService and are not part of these stats.
			end
		end
	end

	return stats
end

-- ── Public: slot query helpers (static, callable anywhere) ───────────────────

--- Returns the slot-type category ("front"|"side"|"rear"|"core") for a named
-- slot, or nil for unrecognised names.
function OrganismEntity.GetSlotType(slotName: string): string?
	return SLOT_TYPE_MAP[slotName]
end

--- Returns the part category compatible with a given slot-type, or nil.
function OrganismEntity.GetSlotCompatibleCategory(slotType: string): string?
	return SLOT_CATEGORY_COMPAT[slotType]
end

--- Returns true when a part of `partCategory` is compatible with `slotName`.
function OrganismEntity.IsPartCompatibleWithSlot(partCategory: string, slotName: string): boolean
	local slotType = SLOT_TYPE_MAP[slotName]
	if not slotType then return false end
	return SLOT_CATEGORY_COMPAT[slotType] == partCategory
end

-- ── Public: slot attachment API (instance methods) ────────────────────────────

--- Returns the Attachment for a named slot, or nil if the slot does not exist.
function OrganismEntity:GetSlotAttachment(slotName: string): Attachment?
	return self.RootPart:FindFirstChild(slotName) :: Attachment?
end

--- Welds a BasePart to the named slot on this organism.
-- Removes any previously attached part in the same slot first.
-- @returns true on success, false if the slot does not exist.
function OrganismEntity:AttachPartToSlot(slotName: string, partModel: BasePart): boolean
	local att = self:GetSlotAttachment(slotName)
	if not att then return false end

	-- Remove any existing occupant in this slot.
	self:DetachPartFromSlot(slotName)

	-- Position the incoming part at the slot's world CFrame.
	partModel.CFrame = self.RootPart.CFrame * att.CFrame

	-- WeldConstraint so the part follows the root rigidly.
	local weld    = Instance.new("WeldConstraint")
	weld.Name     = "SlotWeld_" .. slotName
	weld.Part0    = self.RootPart
	weld.Part1    = partModel
	weld.Parent   = self.RootPart

	partModel.Parent             = self.Model
	self.AttachedParts[slotName] = partModel
	return true
end

--- Removes and destroys the part currently attached to a named slot.
function OrganismEntity:DetachPartFromSlot(slotName: string)
	local existing = self.AttachedParts[slotName]
	if not existing then return end

	local weld = self.RootPart:FindFirstChild("SlotWeld_" .. slotName)
	if weld then weld:Destroy() end

	existing:Destroy()
	self.AttachedParts[slotName] = nil
end

--- Destroys the organism model and all attached parts.
function OrganismEntity:Destroy()
	self.Model:Destroy()
end

return OrganismEntity
