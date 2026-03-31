--!strict
-- HUDController: in-game heads-up display.
--
-- Displays:
--   • Health bar      – bottom-center, color shifts green→red with HP.
--   • Coin counter    – top-right, updated via CurrencyChanged RemoteEvent.
--   • Ability bar     – five slots (Q/E/R/F/G) showing part name and
--                       a cooldown overlay that drains as the ability recharges.
--   • Loot toasts     – right-side popups that appear on receiving loot
--                       and fade out after a few seconds.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local PartData = require(ReplicatedStorage.Modules.PartData)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

-- ── Slot key → slot name mapping ─────────────────────────────────────────────
-- Must match AbilityController's SLOT_KEYS table exactly.
type SlotBinding = { Key: Enum.KeyCode, Slot: string, Label: string }
local SLOT_BINDINGS: { SlotBinding } = {
	{ Key = Enum.KeyCode.Q, Slot = "Front", Label = "Q" },
	{ Key = Enum.KeyCode.E, Slot = "Core",  Label = "E" },
	{ Key = Enum.KeyCode.R, Slot = "Rear",  Label = "R" },
	{ Key = Enum.KeyCode.F, Slot = "Left",  Label = "F" },
	{ Key = Enum.KeyCode.G, Slot = "Right", Label = "G" },
}

-- ── Build + cooldown state ────────────────────────────────────────────────────
local currentSlots: { [string]: string } = {}   -- slotName → partId
local cooldownStart: { [string]: number } = {}   -- partId  → os.clock() at activation

local FALLBACK_COOLDOWN = 1.0

local function getPartCooldown(partId: string): number
	local def = PartData[partId]
	return if def then def.Cooldown else FALLBACK_COOLDOWN
end

-- ── Loot notification queue ───────────────────────────────────────────────────
local NOTIF_DURATION = 3.5  -- seconds before a toast disappears
local NOTIF_HEIGHT   = 28   -- px height of each toast label
local NOTIF_GAP      = 4    -- px gap between toasts

type LootNotif = { Label: TextLabel, Expiry: number }
local lootQueue: { LootNotif } = {}

-- ── ScreenGui ────────────────────────────────────────────────────────────────
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "HUD"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder = 10
screenGui.Parent = playerGui

-- ─ Health bar ─────────────────────────────────────────────────────────────────
--   Sits at bottom-center: top-left corner at (50% - 160 px, 100% - 60 px).
local healthBarBg = Instance.new("Frame")
healthBarBg.Name = "HealthBarBg"
healthBarBg.Size = UDim2.new(0, 320, 0, 22)
healthBarBg.Position = UDim2.new(0.5, -160, 1, -60)
healthBarBg.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
healthBarBg.BorderSizePixel = 0
healthBarBg.Parent = screenGui

local healthFill = Instance.new("Frame")
healthFill.Name = "HealthFill"
healthFill.Size = UDim2.new(1, 0, 1, 0)
healthFill.BackgroundColor3 = Color3.fromRGB(80, 200, 100)
healthFill.BorderSizePixel = 0
healthFill.Parent = healthBarBg

local healthText = Instance.new("TextLabel")
healthText.Name = "HealthText"
healthText.Size = UDim2.new(1, 0, 1, 0)
healthText.BackgroundTransparency = 1
healthText.TextColor3 = Color3.new(1, 1, 1)
healthText.TextStrokeTransparency = 0.5
healthText.Font = Enum.Font.GothamBold
healthText.TextSize = 13
healthText.Text = "HP: 100 / 100"
healthText.Parent = healthBarBg

-- ─ Ability bar ────────────────────────────────────────────────────────────────
--   Five 60 px wide slots with a 4 px gap → total width 316 px.
--   Sits directly above the health bar: top-left at (50% - 158 px, 100% - 120 px).
local SLOT_W = 60
local SLOT_STRIDE = 64  -- SLOT_W + 4 px gap
local NUM_SLOTS = #SLOT_BINDINGS
local ABILITY_BAR_W = NUM_SLOTS * SLOT_STRIDE - (SLOT_STRIDE - SLOT_W)  -- 316 px

local abilityBar = Instance.new("Frame")
abilityBar.Name = "AbilityBar"
abilityBar.Size = UDim2.new(0, ABILITY_BAR_W, 0, 52)
abilityBar.Position = UDim2.new(0.5, -ABILITY_BAR_W / 2, 1, -120)
abilityBar.BackgroundTransparency = 1
abilityBar.Parent = screenGui

type SlotUI = {
	Container: Frame,
	PartLabel: TextLabel,
	CooldownOverlay: Frame,
}
local slotUIs: { [string]: SlotUI } = {}

for i, binding in SLOT_BINDINGS do
	local xOffset = (i - 1) * SLOT_STRIDE

	local container = Instance.new("Frame")
	container.Name = "Slot_" .. binding.Label
	container.Size = UDim2.new(0, SLOT_W, 0, 52)
	container.Position = UDim2.new(0, xOffset, 0, 0)
	container.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
	container.BorderSizePixel = 0
	container.Parent = abilityBar

	local keyLabel = Instance.new("TextLabel")
	keyLabel.Size = UDim2.new(1, 0, 0, 18)
	keyLabel.Position = UDim2.new(0, 0, 0, 2)
	keyLabel.BackgroundTransparency = 1
	keyLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
	keyLabel.Font = Enum.Font.GothamBold
	keyLabel.TextSize = 12
	keyLabel.Text = binding.Label
	keyLabel.Parent = container

	local partLabel = Instance.new("TextLabel")
	partLabel.Name = "PartLabel"
	partLabel.Size = UDim2.new(1, -4, 0, 28)
	partLabel.Position = UDim2.new(0, 2, 0, 20)
	partLabel.BackgroundTransparency = 1
	partLabel.TextColor3 = Color3.fromRGB(240, 230, 160)
	partLabel.Font = Enum.Font.Gotham
	partLabel.TextSize = 9
	partLabel.TextWrapped = true
	partLabel.Text = "—"
	partLabel.Parent = container

	-- Cooldown overlay: covers the slot top-to-bottom as ability recharges.
	-- Height goes from 100% (just activated) → 0% (ready).
	local overlay = Instance.new("Frame")
	overlay.Name = "CooldownOverlay"
	overlay.Size = UDim2.new(1, 0, 0, 0)   -- 0 height = ready
	overlay.Position = UDim2.new(0, 0, 0, 0)
	overlay.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
	overlay.BackgroundTransparency = 0.45
	overlay.BorderSizePixel = 0
	overlay.Parent = container

	slotUIs[binding.Slot] = {
		Container = container,
		PartLabel = partLabel,
		CooldownOverlay = overlay,
	}
end

-- ─ Coin display ───────────────────────────────────────────────────────────────
local coinLabel = Instance.new("TextLabel")
coinLabel.Name = "CoinDisplay"
coinLabel.Size = UDim2.new(0, 150, 0, 30)
coinLabel.Position = UDim2.new(1, -160, 0, 10)
coinLabel.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
coinLabel.BackgroundTransparency = 0.3
coinLabel.BorderSizePixel = 0
coinLabel.TextColor3 = Color3.fromRGB(255, 215, 55)
coinLabel.Font = Enum.Font.GothamBold
coinLabel.TextSize = 16
coinLabel.Text = "Coins: 0"
coinLabel.Parent = screenGui

-- ─ Loot notification container ────────────────────────────────────────────────
--   Anchored to the right side; toasts stack upward from the bottom.
local lootContainer = Instance.new("Frame")
lootContainer.Name = "LootContainer"
lootContainer.Size = UDim2.new(0, 230, 0.4, 0)
lootContainer.Position = UDim2.new(1, -240, 0.55, 0)
lootContainer.BackgroundTransparency = 1
lootContainer.Parent = screenGui

-- ── Helper: show a loot toast ─────────────────────────────────────────────────
local function showLootToast(text: string)
	local yOffset = -((#lootQueue + 1) * (NOTIF_HEIGHT + NOTIF_GAP))

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, NOTIF_HEIGHT)
	label.Position = UDim2.new(0, 0, 1, yOffset)
	label.BackgroundColor3 = Color3.fromRGB(40, 38, 55)
	label.BackgroundTransparency = 0.15
	label.BorderSizePixel = 0
	label.TextColor3 = Color3.fromRGB(225, 215, 255)
	label.Font = Enum.Font.Gotham
	label.TextSize = 12
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = "  " .. text
	label.Parent = lootContainer

	table.insert(lootQueue, { Label = label, Expiry = os.clock() + NOTIF_DURATION })
end

-- ── RenderStepped: update health + cooldowns + expire toasts ─────────────────
RunService.RenderStepped:Connect(function(_dt: number)
	-- Health bar: read from organism Health/MaxHealth NumberValues (no Humanoid).
	local char = player.Character
	if char then
		local healthVal    = char:FindFirstChild("Health")    :: NumberValue?
		local maxHealthVal = char:FindFirstChild("MaxHealth") :: NumberValue?
		if healthVal and maxHealthVal then
			local hp    = healthVal.Value
			local maxHp = math.max(maxHealthVal.Value, 1)
			local ratio = math.clamp(hp / maxHp, 0, 1)
			healthFill.Size = UDim2.new(ratio, 0, 1, 0)

			-- Color: green (full) → yellow (half) → red (low).
			local r = math.clamp(2 * (1 - ratio), 0, 1)
			local g = math.clamp(2 * ratio, 0, 1)
			healthFill.BackgroundColor3 = Color3.new(r, g, 0.08)

			healthText.Text = string.format(
				"HP: %d / %d",
				math.floor(hp),
				math.floor(maxHp)
			)
		end
	end

	-- Ability slot cooldown overlays.
	local now = os.clock()
	for _, binding in SLOT_BINDINGS do
		local ui = slotUIs[binding.Slot]
		local partId = currentSlots[binding.Slot]

		if partId then
			local def = PartData[partId]
			ui.PartLabel.Text = if def then def.Name else partId

			local startTime = cooldownStart[partId]
			if startTime then
				local cd = getPartCooldown(partId)
				local remaining = math.clamp(1 - (now - startTime) / cd, 0, 1)
				ui.CooldownOverlay.Size = UDim2.new(1, 0, remaining, 0)
				if remaining <= 0 then
					cooldownStart[partId] = nil
				end
			else
				ui.CooldownOverlay.Size = UDim2.new(1, 0, 0, 0)
			end
		else
			ui.PartLabel.Text = "—"
			ui.CooldownOverlay.Size = UDim2.new(1, 0, 0, 0)
		end
	end

	-- Expire loot toasts.
	local i = 1
	while i <= #lootQueue do
		local notif = lootQueue[i]
		if now >= notif.Expiry then
			notif.Label:Destroy()
			table.remove(lootQueue, i)
		else
			i += 1
		end
	end
end)

-- ── Remote listeners ─────────────────────────────────────────────────────────
task.spawn(function()
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 10) :: Folder?
	if not remotes then
		warn("[HUDController] Remotes folder not found within 10 s.")
		return
	end

	-- BuildChanged: keep ability slot labels current.
	local buildChanged = remotes:WaitForChild("BuildChanged", 10) :: RemoteEvent?
	if buildChanged then
		buildChanged.OnClientEvent:Connect(function(_bodyId: unknown, slots: unknown)
			if typeof(slots) ~= "table" then return end
			local newSlots: { [string]: string } = {}
			for k, v in slots :: { [any]: any } do
				if typeof(k) == "string" and typeof(v) == "string" then
					newSlots[k :: string] = v :: string
				end
			end
			currentSlots = newSlots
		end)
	end

	-- CurrencyChanged: update coin label.
	local currencyChanged = remotes:WaitForChild("CurrencyChanged", 10) :: RemoteEvent?
	if currencyChanged then
		currencyChanged.OnClientEvent:Connect(function(newBalance: unknown)
			if typeof(newBalance) == "number" then
				coinLabel.Text = string.format("Coins: %d", newBalance)
			end
		end)
	end

	-- GetBalance: fetch initial balance on join.
	local getBalance = remotes:WaitForChild("GetBalance", 10) :: RemoteFunction?
	if getBalance then
		local ok, balance = pcall(function()
			return getBalance:InvokeServer()
		end)
		if ok and typeof(balance) == "number" then
			coinLabel.Text = string.format("Coins: %d", balance)
		end
	end

	-- LootDrop: show toast notification.
	local lootDrop = remotes:WaitForChild("LootDrop", 10) :: RemoteEvent?
	if lootDrop then
		lootDrop.OnClientEvent:Connect(function(dropType: unknown, itemId: unknown, rarity: unknown)
			if typeof(dropType) ~= "string" then return end
			if dropType == "Coins" then
				showLootToast(string.format("+ %s Coins", tostring(itemId)))
			elseif dropType == "Part" then
				local rarityStr = ""
				if typeof(rarity) == "string" and rarity ~= "" then
					rarityStr = " [" .. rarity .. "]"
				end
				showLootToast(string.format("Part: %s%s", tostring(itemId), rarityStr))
			end
		end)
	end
end)

-- ── Input: mark cooldowns when ability keys are pressed ──────────────────────
-- Mirrors AbilityController's input handling so the cooldown overlay
-- starts exactly when the player attempts to fire the ability.
-- If the ability was on cooldown, the check below prevents a false restart.
local KEY_TO_SLOT: { [Enum.KeyCode]: string } = {}
for _, b in SLOT_BINDINGS do
	KEY_TO_SLOT[b.Key] = b.Slot
end

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then return end
	local slot = KEY_TO_SLOT[input.KeyCode]
	if not slot then return end

	local partId = currentSlots[slot]
	if not partId then return end

	local def = PartData[partId]
	if not def or def.Cooldown <= 0 then return end

	-- Only start the visual cooldown if the ability is actually ready.
	local last = cooldownStart[partId]
	if last and (os.clock() - last) < def.Cooldown then return end

	cooldownStart[partId] = os.clock()
end)
