--!strict
-- TraitData: defines traits that can roll on parts, with stat modifier metadata.

export type StatModifier = {
	Stat: string,
	Type: "Multiply" | "Add",
	Value: number,
}

export type TraitDef = {
	Name: string,
	Description: string,
	Modifiers: { [number]: StatModifier },
	Tags: { [number]: string },
}

local TraitData: { [string]: TraitDef } = {

	Savage = {
		Name = "Savage",
		Description = "+20% damage output.",
		Modifiers = {
			{ Stat = "Damage", Type = "Multiply", Value = 1.20 },
		},
		Tags = { "Offense" },
	},

	Efficient = {
		Name = "Efficient",
		Description = "-25% energy cost.",
		Modifiers = {
			{ Stat = "EnergyCost", Type = "Multiply", Value = 0.75 },
		},
		Tags = { "Economy" },
	},

	Giant = {
		Name = "Giant",
		Description = "+30% hit radius/range.",
		Modifiers = {
			{ Stat = "Range", Type = "Multiply", Value = 1.30 },
		},
		Tags = { "Utility" },
	},

	Symbiotic = {
		Name = "Symbiotic",
		Description = "Reduces cooldown of adjacent parts by 10%.",
		Modifiers = {
			{ Stat = "Cooldown", Type = "Multiply", Value = 0.90 },
		},
		Tags = { "Support", "Adjacency" },
	},

	Volatile = {
		Name = "Volatile",
		Description = "+50% damage but -30% health on the host body.",
		Modifiers = {
			{ Stat = "Damage", Type = "Multiply", Value = 1.50 },
			{ Stat = "BaseHealth", Type = "Multiply", Value = 0.70 },
		},
		Tags = { "HighRisk", "Offense" },
	},

	Resilient = {
		Name = "Resilient",
		Description = "+15% to body max health.",
		Modifiers = {
			{ Stat = "BaseHealth", Type = "Multiply", Value = 1.15 },
		},
		Tags = { "Defense" },
	},

	Swift = {
		Name = "Swift",
		Description = "+10 flat move speed.",
		Modifiers = {
			{ Stat = "MoveSpeed", Type = "Add", Value = 10 },
		},
		Tags = { "Mobility" },
	},
}

return TraitData
