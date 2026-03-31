--!strict
-- BodyData: defines available organism bodies with base stats, capacity, and slot layouts.

export type SlotLayout = { [number]: string }

export type BodyDef = {
	Name: string,
	BaseHealth: number,
	MoveSpeed: number,
	-- Capacity is the total CapacityCost budget for equipped parts.
	-- The sum of all equipped parts' CapacityCost must not exceed this value.
	Capacity: number,
	SlotLayout: SlotLayout,
	Description: string,
}

local BodyData: { [string]: BodyDef } = {

	StarterBlob = {
		Name = "Starter Blob",
		BaseHealth = 100,
		MoveSpeed = 24,
		Capacity = 10,
		SlotLayout = { "Front", "Left", "Right", "Rear", "Core" },
		Description = "A balanced, beginner-friendly body. Good starter choice.",
	},

	ArmoredShell = {
		Name = "Armored Shell",
		BaseHealth = 180,
		MoveSpeed = 16,
		Capacity = 12,
		SlotLayout = { "Front", "Left", "Right", "Left2", "Right2", "Core" },
		Description = "Tough defensive chassis. Slower but can equip more defense parts.",
	},

	SwiftNucleus = {
		Name = "Swift Nucleus",
		BaseHealth = 70,
		MoveSpeed = 34,
		Capacity = 8,
		SlotLayout = { "Front", "Rear", "Rear2", "Core" },
		Description = "Lightweight and fast. Limited slots but high mobility.",
	},

	VenomMantle = {
		Name = "Venom Mantle",
		BaseHealth = 120,
		MoveSpeed = 20,
		Capacity = 14,
		SlotLayout = { "Front", "Front2", "Left", "Right", "Rear", "Core" },
		Description = "Toxin-adapted body. Generous capacity suited for poison builds.",
	},
}

return BodyData
