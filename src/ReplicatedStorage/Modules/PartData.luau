--!strict
-- PartData: defines available mutation parts with stats, rarity, and slot compatibility.
--
-- ValidSlots lists the specific named slots that accept each part.  The list
-- must be consistent with the slot-type ↔ part-category rule enforced by
-- OrganismEntity and PlayerBuildService:
--   front slots  (Front, Front2)           → Attack   parts only
--   side  slots  (Left, Right, Left2, Right2) → Defense  parts only
--   rear  slots  (Rear, Rear2)             → Movement parts only
--   core  slot   (Core)                    → Utility  parts only

export type Rarity = "Common" | "Rare" | "Epic" | "Legendary" | "Mythic" | "Ancient"
export type Category = "Attack" | "Defense" | "Movement" | "Utility"

export type PartDef = {
	Name: string,
	Category: Category,
	Rarity: Rarity,
	Damage: number,
	Cooldown: number,
	EnergyCost: number,
	Range: number,
	CapacityCost: number,
	ValidSlots: { [number]: string },
	Description: string,
	Traits: { [number]: string }?,  -- optional list of TraitData keys applied to this part
}

local PartData: { [string]: PartDef } = {

	-- Attack
	BiteJaw = {
		Name = "Bite Jaw",
		Category = "Attack",
		Rarity = "Common",
		Damage = 30,
		Cooldown = 1.2,
		EnergyCost = 10,
		Range = 4,
		CapacityCost = 2,
		ValidSlots = { "Front", "Front2" },
		Description = "A basic bite attack aimed forward.",
		Traits = { "Savage" },
	},

	ClawArm = {
		Name = "Claw Arm",
		Category = "Attack",
		Rarity = "Rare",
		Damage = 45,
		Cooldown = 1.8,
		EnergyCost = 18,
		Range = 5,
		CapacityCost = 3,
		ValidSlots = { "Front", "Front2" },
		Description = "A forward-mounted claw with good reach.",
	},

	AcidSpitter = {
		Name = "Acid Spitter",
		Category = "Attack",
		Rarity = "Rare",
		Damage = 20,
		Cooldown = 0.8,
		EnergyCost = 14,
		Range = 10,
		CapacityCost = 4,
		ValidSlots = { "Front", "Front2" },
		Description = "Fires acid projectiles. Lower damage but fast rate and good range.",
	},

	ElectricTendril = {
		Name = "Electric Tendril",
		Category = "Attack",
		Rarity = "Epic",
		Damage = 60,
		Cooldown = 2.5,
		EnergyCost = 25,
		Range = 7,
		CapacityCost = 4,
		ValidSlots = { "Front", "Front2" },
		Description = "Arcing electric lash that can chain to nearby enemies.",
		Traits = { "Volatile" },
	},

	-- Defense
	ShellPlate = {
		Name = "Shell Plate",
		Category = "Defense",
		Rarity = "Common",
		Damage = 0,
		Cooldown = 0,
		EnergyCost = 0,
		Range = 0,
		CapacityCost = 3,
		ValidSlots = { "Left", "Right", "Left2", "Right2" },
		Description = "Passive armor plating that reduces incoming damage.",
		Traits = { "Resilient" },
	},

	AbsorptionMembrane = {
		Name = "Absorption Membrane",
		Category = "Defense",
		Rarity = "Rare",
		Damage = 0,
		Cooldown = 8,
		EnergyCost = 20,
		Range = 0,
		CapacityCost = 3,
		ValidSlots = { "Left", "Right" },
		Description = "Periodically absorbs a portion of incoming damage.",
	},

	-- Movement
	DashFlagella = {
		Name = "Dash Flagella",
		Category = "Movement",
		Rarity = "Common",
		Damage = 0,
		Cooldown = 5,
		EnergyCost = 15,
		Range = 0,
		CapacityCost = 2,
		ValidSlots = { "Rear", "Rear2" },
		Description = "Provides a short forward dash on activation.",
		Traits = { "Swift" },
	},

	JetSac = {
		Name = "Jet Sac",
		Category = "Movement",
		Rarity = "Rare",
		Damage = 0,
		Cooldown = 8,
		EnergyCost = 22,
		Range = 0,
		CapacityCost = 3,
		ValidSlots = { "Rear", "Rear2" },
		Description = "Sustained speed boost for a short duration.",
	},

	-- Utility
	HealingGland = {
		Name = "Healing Gland",
		Category = "Utility",
		Rarity = "Rare",
		Damage = 0,
		Cooldown = 12,
		EnergyCost = 30,
		Range = 3,
		CapacityCost = 3,
		ValidSlots = { "Core" },
		Description = "Restores a portion of health on activation.",
		Traits = { "Efficient" },
	},

	ToxinCloud = {
		Name = "Toxin Cloud",
		Category = "Utility",
		Rarity = "Epic",
		Damage = 15,
		Cooldown = 10,
		EnergyCost = 25,
		Range = 6,
		CapacityCost = 4,
		ValidSlots = { "Core" },
		Description = "Releases a poisonous cloud behind the organism.",
	},
}

return PartData
