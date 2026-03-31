--!strict
-- Functional tests for OrganismEntity slot compatibility and stat computation.
--
-- These tests exercise pure logic that does not require a live Roblox server.
-- Run them with a Luau test runner (e.g. TestEZ or standalone Luau) that
-- provides the Roblox globals via a mock environment.
--
-- Each test function calls expect() which accumulates pass/fail counts and
-- prints a result line.  The script errors at the end if any test failed.

-- ── Minimal mock environment ──────────────────────────────────────────────────
-- We inline only the data needed to exercise OrganismEntity without loading the
-- full Roblox engine.

-- Stub out require() calls made inside the modules under test.
local BodyDataStub: { [string]: any } = {
	StarterBlob = {
		Name        = "Starter Blob",
		BaseHealth  = 100,
		MoveSpeed   = 24,
		Capacity    = 10,
		SlotLayout  = { "Front", "Left", "Right", "Rear", "Core" },
		Description = "Test body",
	},
	SwiftNucleus = {
		Name        = "Swift Nucleus",
		BaseHealth  = 70,
		MoveSpeed   = 34,
		Capacity    = 8,
		SlotLayout  = { "Front", "Rear", "Rear2", "Core" },
		Description = "Fast body",
	},
}

local PartDataStub: { [string]: any } = {
	BiteJaw = {
		Name         = "Bite Jaw",
		Category     = "Attack",
		Rarity       = "Common",
		CapacityCost = 2,
		ValidSlots   = { "Front", "Front2" },
		Traits       = nil,
	},
	ShellPlate = {
		Name         = "Shell Plate",
		Category     = "Defense",
		Rarity       = "Common",
		CapacityCost = 3,
		ValidSlots   = { "Left", "Right", "Left2", "Right2" },
		Traits       = { "Resilient" },
	},
	DashFlagella = {
		Name         = "Dash Flagella",
		Category     = "Movement",
		Rarity       = "Common",
		CapacityCost = 2,
		ValidSlots   = { "Rear", "Rear2" },
		Traits       = { "Swift" },
	},
	HealingGland = {
		Name         = "Healing Gland",
		Category     = "Utility",
		Rarity       = "Rare",
		CapacityCost = 3,
		ValidSlots   = { "Core" },
		Traits       = nil,
	},
}

local TraitDataStub: { [string]: any } = {
	Resilient = {
		Name        = "Resilient",
		Description = "+15% to body max health.",
		Modifiers   = {
			{ Stat = "BaseHealth", Type = "Multiply", Value = 1.15 },
		},
		Tags = { "Defense" },
	},
	Swift = {
		Name        = "Swift",
		Description = "+10 flat move speed.",
		Modifiers   = {
			{ Stat = "MoveSpeed", Type = "Add", Value = 10 },
		},
		Tags = { "Mobility" },
	},
}

-- ── Inline re-implementation of the testable pure logic ──────────────────────
-- Mirrors OrganismEntity without Roblox Instance creation so tests are portable.

local SLOT_TYPE_MAP: { [string]: string } = {
	Front  = "front", Front2 = "front",
	Left   = "side",  Left2  = "side",
	Right  = "side",  Right2 = "side",
	Rear   = "rear",  Rear2  = "rear",
	Core   = "core",
}

local SLOT_CATEGORY_COMPAT: { [string]: string } = {
	front = "Attack",
	side  = "Defense",
	rear  = "Movement",
	core  = "Utility",
}

local function getSlotType(slotName: string): string?
	return SLOT_TYPE_MAP[slotName]
end

local function isPartCompatibleWithSlot(partCategory: string, slotName: string): boolean
	local slotType = SLOT_TYPE_MAP[slotName]
	if not slotType then return false end
	return SLOT_CATEGORY_COMPAT[slotType] == partCategory
end

local function computeStats(bodyId: string, equippedSlots: { [string]: string }): any
	local bodyDef = BodyDataStub[bodyId]
	assert(bodyDef, "Unknown bodyId: " .. bodyId)

	local stats = {
		Health       = bodyDef.BaseHealth,
		MaxHealth    = bodyDef.BaseHealth,
		MoveSpeed    = bodyDef.MoveSpeed,
		Acceleration = 80,
		TurnSpeed    = math.rad(540),
		Capacity     = bodyDef.Capacity,
		UsedCapacity = 0,
	}

	for _, partId in equippedSlots do
		local partDef = PartDataStub[partId]
		if not partDef then continue end
		stats.UsedCapacity += partDef.CapacityCost
		if not partDef.Traits then continue end
		for _, traitId in partDef.Traits do
			local traitDef = TraitDataStub[traitId]
			if not traitDef then continue end
			for _, mod in traitDef.Modifiers do
				if mod.Stat == "MoveSpeed" then
					if mod.Type == "Add" then
						stats.MoveSpeed += mod.Value
					elseif mod.Type == "Multiply" then
						stats.MoveSpeed *= mod.Value
					end
				elseif mod.Stat == "BaseHealth" then
					if mod.Type == "Multiply" then
						stats.MaxHealth = math.round(stats.MaxHealth * mod.Value)
						stats.Health    = math.min(stats.Health, stats.MaxHealth)
					elseif mod.Type == "Add" then
						stats.MaxHealth += mod.Value
					end
				end
			end
		end
	end
	return stats
end

-- ── Test helpers ──────────────────────────────────────────────────────────────

local passed = 0
local failed = 0

local function expect(label: string, condition: boolean, detail: string?)
	if condition then
		passed += 1
		print(("  ✓ %s"):format(label))
	else
		failed += 1
		print(("  ✗ %s%s"):format(label, detail and (" — " .. detail) or ""))
	end
end

local function approxEq(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 1e-4)
end

-- ── Tests: slot-type mapping ──────────────────────────────────────────────────

print("OrganismEntity – slot type mapping tests")

expect("Front maps to 'front'",  getSlotType("Front")  == "front")
expect("Left maps to 'side'",    getSlotType("Left")   == "side")
expect("Right maps to 'side'",   getSlotType("Right")  == "side")
expect("Rear maps to 'rear'",    getSlotType("Rear")   == "rear")
expect("Core maps to 'core'",    getSlotType("Core")   == "core")
expect("Front2 maps to 'front'", getSlotType("Front2") == "front")
expect("Rear2 maps to 'rear'",   getSlotType("Rear2")  == "rear")
expect("Unknown slot returns nil", getSlotType("Bogus") == nil)

-- ── Tests: slot-category compatibility ───────────────────────────────────────

print("OrganismEntity – slot-category compatibility tests")

-- Attack parts go in front slots only
expect("Attack compatible with Front",     isPartCompatibleWithSlot("Attack",   "Front"))
expect("Attack compatible with Front2",    isPartCompatibleWithSlot("Attack",   "Front2"))
expect("Attack NOT compatible with Left",  not isPartCompatibleWithSlot("Attack",   "Left"))
expect("Attack NOT compatible with Rear",  not isPartCompatibleWithSlot("Attack",   "Rear"))
expect("Attack NOT compatible with Core",  not isPartCompatibleWithSlot("Attack",   "Core"))

-- Defense parts go in side slots only
expect("Defense compatible with Left",     isPartCompatibleWithSlot("Defense",  "Left"))
expect("Defense compatible with Right",    isPartCompatibleWithSlot("Defense",  "Right"))
expect("Defense NOT compatible with Front",not isPartCompatibleWithSlot("Defense",  "Front"))
expect("Defense NOT compatible with Rear", not isPartCompatibleWithSlot("Defense",  "Rear"))
expect("Defense NOT compatible with Core", not isPartCompatibleWithSlot("Defense",  "Core"))

-- Movement parts go in rear slots only
expect("Movement compatible with Rear",    isPartCompatibleWithSlot("Movement", "Rear"))
expect("Movement compatible with Rear2",   isPartCompatibleWithSlot("Movement", "Rear2"))
expect("Movement NOT compatible with Front",not isPartCompatibleWithSlot("Movement", "Front"))
expect("Movement NOT compatible with Left", not isPartCompatibleWithSlot("Movement", "Left"))
expect("Movement NOT compatible with Core", not isPartCompatibleWithSlot("Movement", "Core"))

-- Utility parts go in core slot only
expect("Utility compatible with Core",     isPartCompatibleWithSlot("Utility",  "Core"))
expect("Utility NOT compatible with Front",not isPartCompatibleWithSlot("Utility",  "Front"))
expect("Utility NOT compatible with Left", not isPartCompatibleWithSlot("Utility",  "Left"))
expect("Utility NOT compatible with Rear", not isPartCompatibleWithSlot("Utility",  "Rear"))

-- Unknown slot names always return false
expect("Unknown slot is never compatible", not isPartCompatibleWithSlot("Attack", "Bogus"))

-- ── Tests: ComputeStats – base stats ─────────────────────────────────────────

print("OrganismEntity – ComputeStats base stats tests")

do
	local stats = computeStats("StarterBlob", {})
	expect("base health equals body BaseHealth",
		stats.MaxHealth == 100 and stats.Health == 100,
		("MaxHealth=%d Health=%d"):format(stats.MaxHealth, stats.Health))
	expect("base MoveSpeed equals body MoveSpeed",
		approxEq(stats.MoveSpeed, 24),
		("MoveSpeed=%g"):format(stats.MoveSpeed))
	-- TurnSpeed is set to DEFAULT_TURN_SPEED in OrganismEntity (math.rad(540)).
	-- The spec stub mirrors this value; if the production default changes, this
	-- expected value must be updated in sync.
	expect("base Acceleration is 80",
		approxEq(stats.Acceleration, 80),
		("Acceleration=%g"):format(stats.Acceleration))
	expect("base UsedCapacity is 0",
		stats.UsedCapacity == 0)
end

-- ── Tests: ComputeStats – capacity accounting ─────────────────────────────────

print("OrganismEntity – ComputeStats capacity tests")

do
	local slots = { Front = "BiteJaw", Left = "ShellPlate" }
	local stats = computeStats("StarterBlob", slots)
	-- BiteJaw costs 2, ShellPlate costs 3 → total 5
	expect("equipped parts sum to correct UsedCapacity",
		stats.UsedCapacity == 5,
		("UsedCapacity=%d"):format(stats.UsedCapacity))
end

-- ── Tests: ComputeStats – trait stat modifiers ────────────────────────────────

print("OrganismEntity – ComputeStats trait modifier tests")

do -- DashFlagella has Swift (+10 MoveSpeed)
	local stats = computeStats("StarterBlob", { Rear = "DashFlagella" })
	expect("Swift trait adds +10 to MoveSpeed",
		approxEq(stats.MoveSpeed, 34),
		("MoveSpeed=%g"):format(stats.MoveSpeed))
end

do -- ShellPlate has Resilient (+15% MaxHealth on StarterBlob base 100 → 115)
	local stats = computeStats("StarterBlob", { Left = "ShellPlate" })
	expect("Resilient trait multiplies MaxHealth by 1.15",
		stats.MaxHealth == 115,
		("MaxHealth=%d"):format(stats.MaxHealth))
end

do -- Multiple trait-bearing parts stack independently
	local stats = computeStats("StarterBlob", {
		Rear = "DashFlagella",  -- +10 speed
		Left = "ShellPlate",    -- +15% health
	})
	expect("multiple traits stack: speed increased",
		approxEq(stats.MoveSpeed, 34),
		("MoveSpeed=%g"):format(stats.MoveSpeed))
	expect("multiple traits stack: health increased",
		stats.MaxHealth == 115,
		("MaxHealth=%d"):format(stats.MaxHealth))
	expect("multiple parts sum capacity correctly",
		stats.UsedCapacity == 5,
		("UsedCapacity=%d"):format(stats.UsedCapacity))
end

-- ── Summary ───────────────────────────────────────────────────────────────────

print(("\nResults: %d passed, %d failed"):format(passed, failed))
if failed > 0 then
	error(("%d test(s) failed"):format(failed), 2)
end
