--!strict
-- EnemyData: defines NPC enemy types with behavior tags, stats, and drop tables.

export type DropEntry = {
	Type: "Coins" | "Part",
	Id: string?,
	Amount: number?,
	Rarity: string?,
	Weight: number,
}

export type EnemyDef = {
	Name: string,
	BaseHealth: number,
	MoveSpeed: number,
	Damage: number,
	AggroRange: number,
	AttackRange: number,
	AttackCooldown: number,
	BehaviorTags: { [number]: string },
	DropTable: { [number]: DropEntry },
}

local EnemyData: { [string]: EnemyDef } = {

	Grazer = {
		Name = "Grazer",
		BaseHealth = 60,
		MoveSpeed = 10,
		Damage = 5,
		AggroRange = 8,
		AttackRange = 3,
		AttackCooldown = 2.0,
		BehaviorTags = { "Passive", "FleeOnAttack" },
		DropTable = {
			{ Type = "Coins", Id = "Coins", Amount = 10, Weight = 80 },
			{ Type = "Coins", Id = "Coins", Amount = 25, Weight = 20 },
		},
	},

	SpikeWorm = {
		Name = "Spike Worm",
		BaseHealth = 120,
		MoveSpeed = 16,
		Damage = 20,
		AggroRange = 18,
		AttackRange = 4,
		AttackCooldown = 1.5,
		BehaviorTags = { "Aggressive", "MeleeChase" },
		DropTable = {
			{ Type = "Coins", Id = "Coins", Amount = 15, Weight = 60 },
			{ Type = "Part", Id = "ShellPlate", Rarity = "Common", Weight = 25 },
			{ Type = "Part", Id = "ShellPlate", Rarity = "Rare", Weight = 10 },
			{ Type = "Part", Id = "ClawArm", Rarity = "Epic", Weight = 5 },
		},
	},

	VenomBlob = {
		Name = "Venom Blob",
		BaseHealth = 90,
		MoveSpeed = 12,
		Damage = 14,
		AggroRange = 14,
		AttackRange = 9,
		AttackCooldown = 1.2,
		BehaviorTags = { "Aggressive", "RangedPoison", "KeepDistance" },
		DropTable = {
			{ Type = "Coins", Id = "Coins", Amount = 12, Weight = 55 },
			{ Type = "Part", Id = "AcidSpitter", Rarity = "Common", Weight = 25 },
			{ Type = "Part", Id = "ToxinCloud", Rarity = "Rare", Weight = 15 },
			{ Type = "Part", Id = "ToxinCloud", Rarity = "Epic", Weight = 5 },
		},
	},

	HunterCell = {
		Name = "Hunter Cell",
		BaseHealth = 200,
		MoveSpeed = 22,
		Damage = 35,
		AggroRange = 24,
		AttackRange = 5,
		AttackCooldown = 1.0,
		BehaviorTags = { "Aggressive", "FastChase", "PackHunter" },
		DropTable = {
			{ Type = "Coins", Id = "Coins", Amount = 30, Weight = 50 },
			{ Type = "Part", Id = "BiteJaw", Rarity = "Rare", Weight = 25 },
			{ Type = "Part", Id = "DashFlagella", Rarity = "Rare", Weight = 15 },
			{ Type = "Part", Id = "ElectricTendril", Rarity = "Epic", Weight = 10 },
		},
	},
}

return EnemyData
