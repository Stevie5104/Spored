--!strict
-- BuildUIController: ScreenGui allowing players to switch bodies and equip/unequip parts.
--
-- Toggle with [B]. The panel shows:
--   LEFT:  available bodies with stats (click to switch).
--   RIGHT: current body slots + available parts for each slot (click to equip).
--   TOP:   capacity bar showing used/total.
--
-- All changes go through server RemoteFunctions for validation.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BodyData = require(ReplicatedStorage.Modules.BodyData)
local PartData = require(ReplicatedStorage.Modules.PartData)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

-- ── Remote references (populated once Remotes folder is ready) ───────────────
local equipPartRemote: RemoteFunction? = nil
local unequipPartRemote: RemoteFunction? = nil
local setBodyRemote: RemoteFunction? = nil
local buildChangedRemote: RemoteEvent? = nil

-- ── Client-side build state mirror ───────────────────────────────────────────
local currentBuild: { BodyId: string, Slots: { [string]: string } } = {
	BodyId = "StarterBlob",
	Slots = {},
}

-- Selected slot in the parts panel.
local selectedSlot: string? = nil

-- ── Color constants ───────────────────────────────────────────────────────────
local COLORS = {
	BG           = Color3.fromRGB(25, 25, 35),
	PANEL        = Color3.fromRGB(35, 35, 50),
	ACCENT       = Color3.fromRGB(80, 200, 120),
	BUTTON       = Color3.fromRGB(50, 50, 70),
	BUTTON_HOVER = Color3.fromRGB(65, 65, 90),
	SELECTED     = Color3.fromRGB(60, 140, 200),
	TEXT         = Color3.fromRGB(230, 230, 230),
	DIM_TEXT     = Color3.fromRGB(150, 150, 165),
	WARN         = Color3.fromRGB(220, 100, 80),
	CAP_BAR_BG   = Color3.fromRGB(60, 60, 80),
	CAP_BAR_FG   = Color3.fromRGB(80, 200, 120),
	CAP_BAR_FULL = Color3.fromRGB(220, 80, 60),
}

local CATEGORY_COLORS = {
	Attack   = Color3.fromRGB(230, 70, 60),
	Defense  = Color3.fromRGB(100, 160, 200),
	Movement = Color3.fromRGB(60, 220, 210),
	Utility  = Color3.fromRGB(240, 200, 50),
}

-- ── GUI construction ─────────────────────────────────────────────────────────

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BuildUI"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Enabled = false
screenGui.Parent = playerGui

-- Darken background overlay.
local overlay = Instance.new("Frame")
overlay.Name = "Overlay"
overlay.Size = UDim2.fromScale(1, 1)
overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
overlay.BackgroundTransparency = 0.55
overlay.BorderSizePixel = 0
overlay.Parent = screenGui

-- Main panel container.
local mainPanel = Instance.new("Frame")
mainPanel.Name = "MainPanel"
mainPanel.Size = UDim2.new(0, 780, 0, 520)
mainPanel.Position = UDim2.new(0.5, -390, 0.5, -260)
mainPanel.BackgroundColor3 = COLORS.BG
mainPanel.BorderSizePixel = 0
mainPanel.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = mainPanel

-- Title bar.
local titleBar = Instance.new("Frame")
titleBar.Name = "TitleBar"
titleBar.Size = UDim2.new(1, 0, 0, 44)
titleBar.BackgroundColor3 = COLORS.PANEL
titleBar.BorderSizePixel = 0
titleBar.Parent = mainPanel

local titleCorner = Instance.new("UICorner")
titleCorner.CornerRadius = UDim.new(0, 10)
titleCorner.Parent = titleBar

local titleLabel = Instance.new("TextLabel")
titleLabel.Text = "BUILD EDITOR"
titleLabel.Size = UDim2.new(1, -60, 1, 0)
titleLabel.Position = UDim2.new(0, 16, 0, 0)
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 18
titleLabel.TextColor3 = COLORS.ACCENT
titleLabel.BackgroundTransparency = 1
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = titleBar

local closeButton = Instance.new("TextButton")
closeButton.Text = "✕"
closeButton.Size = UDim2.new(0, 36, 0, 36)
closeButton.Position = UDim2.new(1, -40, 0, 4)
closeButton.Font = Enum.Font.GothamBold
closeButton.TextSize = 18
closeButton.TextColor3 = COLORS.TEXT
closeButton.BackgroundColor3 = COLORS.BUTTON
closeButton.BorderSizePixel = 0
closeButton.Parent = titleBar
local cBtnCorner = Instance.new("UICorner")
cBtnCorner.CornerRadius = UDim.new(0, 6)
cBtnCorner.Parent = closeButton

closeButton.MouseButton1Click:Connect(function()
	screenGui.Enabled = false
end)

-- ── Capacity bar ─────────────────────────────────────────────────────────────

local capBarBg = Instance.new("Frame")
capBarBg.Name = "CapBarBg"
capBarBg.Size = UDim2.new(1, -32, 0, 14)
capBarBg.Position = UDim2.new(0, 16, 0, 52)
capBarBg.BackgroundColor3 = COLORS.CAP_BAR_BG
capBarBg.BorderSizePixel = 0
capBarBg.Parent = mainPanel
local capCorner = Instance.new("UICorner")
capCorner.CornerRadius = UDim.new(0, 7)
capCorner.Parent = capBarBg

local capBarFg = Instance.new("Frame")
capBarFg.Name = "CapBarFg"
capBarFg.Size = UDim2.new(0, 0, 1, 0)
capBarFg.BackgroundColor3 = COLORS.CAP_BAR_FG
capBarFg.BorderSizePixel = 0
capBarFg.Parent = capBarBg
local capFgCorner = Instance.new("UICorner")
capFgCorner.CornerRadius = UDim.new(0, 7)
capFgCorner.Parent = capBarFg

local capLabel = Instance.new("TextLabel")
capLabel.Name = "CapLabel"
capLabel.Size = UDim2.new(1, 0, 1, 0)
capLabel.BackgroundTransparency = 1
capLabel.Font = Enum.Font.GothamBold
capLabel.TextSize = 10
capLabel.TextColor3 = COLORS.TEXT
capLabel.Text = "CAPACITY  0 / 10"
capLabel.Parent = capBarBg

-- ── Left panel: body list ─────────────────────────────────────────────────────

local leftPanel = Instance.new("Frame")
leftPanel.Name = "BodyPanel"
leftPanel.Size = UDim2.new(0, 230, 1, -76)
leftPanel.Position = UDim2.new(0, 8, 0, 74)
leftPanel.BackgroundColor3 = COLORS.PANEL
leftPanel.BorderSizePixel = 0
leftPanel.Parent = mainPanel
local lpCorner = Instance.new("UICorner")
lpCorner.CornerRadius = UDim.new(0, 8)
lpCorner.Parent = leftPanel

local leftTitle = Instance.new("TextLabel")
leftTitle.Text = "BODIES"
leftTitle.Size = UDim2.new(1, 0, 0, 28)
leftTitle.Font = Enum.Font.GothamBold
leftTitle.TextSize = 13
leftTitle.TextColor3 = COLORS.DIM_TEXT
leftTitle.BackgroundTransparency = 1
leftTitle.Parent = leftPanel

local bodyList = Instance.new("ScrollingFrame")
bodyList.Name = "BodyList"
bodyList.Size = UDim2.new(1, -8, 1, -32)
bodyList.Position = UDim2.new(0, 4, 0, 30)
bodyList.BackgroundTransparency = 1
bodyList.BorderSizePixel = 0
bodyList.ScrollBarThickness = 4
bodyList.CanvasSize = UDim2.new(0, 0, 0, 0)
bodyList.AutomaticCanvasSize = Enum.AutomaticSize.Y
bodyList.Parent = leftPanel

local bodyListLayout = Instance.new("UIListLayout")
bodyListLayout.Padding = UDim.new(0, 4)
bodyListLayout.Parent = bodyList

-- ── Right panel: slots + part picker ─────────────────────────────────────────

local rightPanel = Instance.new("Frame")
rightPanel.Name = "SlotPanel"
rightPanel.Size = UDim2.new(1, -254, 1, -76)
rightPanel.Position = UDim2.new(0, 246, 0, 74)
rightPanel.BackgroundColor3 = COLORS.PANEL
rightPanel.BorderSizePixel = 0
rightPanel.Parent = mainPanel
local rpCorner = Instance.new("UICorner")
rpCorner.CornerRadius = UDim.new(0, 8)
rpCorner.Parent = rightPanel

local slotTitle = Instance.new("TextLabel")
slotTitle.Text = "SLOTS"
slotTitle.Size = UDim2.new(0.5, 0, 0, 28)
slotTitle.Font = Enum.Font.GothamBold
slotTitle.TextSize = 13
slotTitle.TextColor3 = COLORS.DIM_TEXT
slotTitle.BackgroundTransparency = 1
slotTitle.Parent = rightPanel

local partsTitle = Instance.new("TextLabel")
partsTitle.Text = "AVAILABLE PARTS"
partsTitle.Size = UDim2.new(0.5, 0, 0, 28)
partsTitle.Position = UDim2.new(0.5, 0, 0, 0)
partsTitle.Font = Enum.Font.GothamBold
partsTitle.TextSize = 13
partsTitle.TextColor3 = COLORS.DIM_TEXT
partsTitle.BackgroundTransparency = 1
partsTitle.Parent = rightPanel

-- Divider between slot list and parts picker.
local divider = Instance.new("Frame")
divider.Size = UDim2.new(0, 2, 1, -30)
divider.Position = UDim2.new(0.5, -1, 0, 30)
divider.BackgroundColor3 = COLORS.BUTTON
divider.BorderSizePixel = 0
divider.Parent = rightPanel

local slotList = Instance.new("ScrollingFrame")
slotList.Name = "SlotList"
slotList.Size = UDim2.new(0.5, -6, 1, -32)
slotList.Position = UDim2.new(0, 4, 0, 30)
slotList.BackgroundTransparency = 1
slotList.BorderSizePixel = 0
slotList.ScrollBarThickness = 4
slotList.CanvasSize = UDim2.new(0, 0, 0, 0)
slotList.AutomaticCanvasSize = Enum.AutomaticSize.Y
slotList.Parent = rightPanel

local slotListLayout = Instance.new("UIListLayout")
slotListLayout.Padding = UDim.new(0, 4)
slotListLayout.Parent = slotList

local partList = Instance.new("ScrollingFrame")
partList.Name = "PartList"
partList.Size = UDim2.new(0.5, -6, 1, -32)
partList.Position = UDim2.new(0.5, 2, 0, 30)
partList.BackgroundTransparency = 1
partList.BorderSizePixel = 0
partList.ScrollBarThickness = 4
partList.CanvasSize = UDim2.new(0, 0, 0, 0)
partList.AutomaticCanvasSize = Enum.AutomaticSize.Y
partList.Parent = rightPanel

local partListLayout = Instance.new("UIListLayout")
partListLayout.Padding = UDim.new(0, 4)
partListLayout.Parent = partList

-- Hint label at bottom.
local hintLabel = Instance.new("TextLabel")
hintLabel.Name = "Hint"
hintLabel.Size = UDim2.new(1, 0, 0, 20)
hintLabel.Position = UDim2.new(0, 0, 1, -22)
hintLabel.Font = Enum.Font.Gotham
hintLabel.TextSize = 11
hintLabel.TextColor3 = COLORS.DIM_TEXT
hintLabel.BackgroundTransparency = 1
hintLabel.Text = "[B] Toggle  •  Click slot to select  •  Click part to equip/unequip"
hintLabel.Parent = mainPanel

-- ── Helper: make a styled button ─────────────────────────────────────────────

local function makeButton(parent: Instance, text: string, height: number): TextButton
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, 0, 0, height)
	btn.Font = Enum.Font.Gotham
	btn.TextSize = 13
	btn.TextColor3 = COLORS.TEXT
	btn.BackgroundColor3 = COLORS.BUTTON
	btn.BorderSizePixel = 0
	btn.Text = text
	btn.TextXAlignment = Enum.TextXAlignment.Left
	btn.TextTruncate = Enum.TextTruncate.AtEnd
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.Parent = btn
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 5)
	c.Parent = btn
	btn.Parent = parent
	return btn
end

-- ── Capacity display update ───────────────────────────────────────────────────

local function getUsedCapacity(): number
	local total = 0
	for _, partId in currentBuild.Slots do
		local pd = PartData[partId]
		if pd then total += pd.CapacityCost end
	end
	return total
end

local function refreshCapacityBar()
	local bodyDef = BodyData[currentBuild.BodyId]
	local maxCap = if bodyDef then bodyDef.Capacity else 10
	local used = getUsedCapacity()
	local ratio = math.clamp(used / maxCap, 0, 1)
	capBarFg.Size = UDim2.new(ratio, 0, 1, 0)
	capBarFg.BackgroundColor3 = if ratio >= 1 then COLORS.CAP_BAR_FULL else COLORS.CAP_BAR_FG
	capLabel.Text = string.format("CAPACITY  %d / %d", used, maxCap)
end

-- ── Part picker (right-right panel) ──────────────────────────────────────────

local function clearPartList()
	for _, child in partList:GetChildren() do
		if child:IsA("TextButton") then child:Destroy() end
	end
end

local function populatePartList(slotName: string)
	clearPartList()

	local equippedPartId = currentBuild.Slots[slotName]

	-- Collect parts valid for this slot, sorted by CapacityCost.
	local valid: { { id: string, def: PartData.PartDef } } = {}
	for partId, partDef in PartData do
		for _, validSlot in partDef.ValidSlots do
			if validSlot == slotName then
				table.insert(valid, { id = partId, def = partDef })
				break
			end
		end
	end
	table.sort(valid, function(a, b)
		return a.def.CapacityCost < b.def.CapacityCost
	end)

	for _, entry in valid do
		local partId = entry.id
		local partDef = entry.def
		local isEquipped = equippedPartId == partId
		local catColor = CATEGORY_COLORS[partDef.Category] or COLORS.TEXT

		local label = string.format(
			"%s  [%d cap]  %s",
			partDef.Name,
			partDef.CapacityCost,
			if isEquipped then "✓" else ""
		)
		local btn = makeButton(partList, label, 42)
		btn.BackgroundColor3 = if isEquipped then COLORS.SELECTED else COLORS.BUTTON
		btn.TextColor3 = catColor

		-- Sub-label for stats.
		local statsLabel = Instance.new("TextLabel")
		statsLabel.Size = UDim2.new(1, -8, 0, 14)
		statsLabel.Position = UDim2.new(0, 8, 1, -16)
		statsLabel.BackgroundTransparency = 1
		statsLabel.Font = Enum.Font.Gotham
		statsLabel.TextSize = 10
		statsLabel.TextColor3 = COLORS.DIM_TEXT
		statsLabel.TextXAlignment = Enum.TextXAlignment.Left
		statsLabel.Text = string.format(
			"DMG %d  CD %.1fs  RNG %d  %s",
			partDef.Damage, partDef.Cooldown, partDef.Range, partDef.Rarity
		)
		statsLabel.Parent = btn

		btn.MouseButton1Click:Connect(function()
			local remote = if isEquipped then unequipPartRemote else equipPartRemote
			if not remote then
				warn("[BuildUIController] Remote not ready.")
				return
			end

			local ok: boolean
			local err: string?
			if isEquipped then
				ok, err = (remote :: RemoteFunction):InvokeServer(slotName)
			else
				ok, err = (remote :: RemoteFunction):InvokeServer(slotName, partId)
			end

			if not ok then
				warn("[BuildUIController] Action failed:", err or "unknown error")
			end
			-- BuildChanged will fire → currentBuild updates → UI refreshes.
		end)
	end
end

-- ── Slot list (right-left panel) ──────────────────────────────────────────────

local function clearSlotList()
	for _, child in slotList:GetChildren() do
		if child:IsA("TextButton") then child:Destroy() end
	end
end

local function populateSlotList()
	clearSlotList()
	selectedSlot = nil

	local bodyDef = BodyData[currentBuild.BodyId]
	if not bodyDef then return end

	for _, slotName in bodyDef.SlotLayout do
		local equippedId = currentBuild.Slots[slotName]
		local partName = if equippedId and PartData[equippedId]
			then PartData[equippedId].Name
			else "— empty —"

		local label = string.format("%s\n%s", slotName, partName)
		local btn = makeButton(slotList, label, 46)
		btn.TextSize = 12
		btn.BackgroundColor3 = if equippedId then COLORS.SELECTED else COLORS.BUTTON

		btn.MouseButton1Click:Connect(function()
			selectedSlot = slotName
			clearPartList()
			populatePartList(slotName)

			-- Highlight selected slot button.
			for _, child in slotList:GetChildren() do
				if child:IsA("TextButton") then
					child.BackgroundColor3 = COLORS.BUTTON
				end
			end
			btn.BackgroundColor3 = COLORS.ACCENT
		end)
	end
end

-- ── Body list (left panel) ────────────────────────────────────────────────────

local function clearBodyList()
	for _, child in bodyList:GetChildren() do
		if child:IsA("TextButton") then child:Destroy() end
	end
end

local function populateBodies()
	clearBodyList()

	-- Consistent ordering.
	local bodyOrder = { "StarterBlob", "ArmoredShell", "SwiftNucleus", "VenomMantle" }
	for _, bodyId in bodyOrder do
		local bodyDef = BodyData[bodyId]
		if not bodyDef then continue end

		local isActive = currentBuild.BodyId == bodyId
		local label = string.format(
			"%s\nHP %d  SPD %d  CAP %d",
			bodyDef.Name, bodyDef.BaseHealth, bodyDef.MoveSpeed, bodyDef.Capacity
		)
		local btn = makeButton(bodyList, label, 52)
		btn.TextSize = 12
		btn.BackgroundColor3 = if isActive then COLORS.SELECTED else COLORS.BUTTON

		btn.MouseButton1Click:Connect(function()
			if currentBuild.BodyId == bodyId then return end
			local remote = setBodyRemote
			if not remote then
				warn("[BuildUIController] SetBody remote not ready.")
				return
			end
			local ok: boolean, err: string? = (remote :: RemoteFunction):InvokeServer(bodyId)
			if not ok then
				warn("[BuildUIController] SetBody failed:", err or "unknown error")
			end
		end)
	end
end

-- ── Full panel refresh ────────────────────────────────────────────────────────

local function refreshUI()
	populateBodies()
	populateSlotList()
	refreshCapacityBar()
	-- Re-populate part list if a slot was already selected.
	if selectedSlot then
		populatePartList(selectedSlot)
	else
		clearPartList()
	end
end

-- ── Toggle input ──────────────────────────────────────────────────────────────

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.B then
		local isNowOpen = not screenGui.Enabled
		screenGui.Enabled = isNowOpen
		if isNowOpen then
			refreshUI()
		end
	end
end)

-- ── Wire remotes + BuildChanged listener ─────────────────────────────────────

task.spawn(function()
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 10) :: Folder?
	if not remotes then
		warn("[BuildUIController] Remotes folder not found.")
		return
	end

	equipPartRemote   = remotes:WaitForChild("EquipPart", 10)   :: RemoteFunction?
	unequipPartRemote = remotes:WaitForChild("UnequipPart", 10) :: RemoteFunction?
	setBodyRemote     = remotes:WaitForChild("SetBody", 10)     :: RemoteFunction?
	buildChangedRemote = remotes:WaitForChild("BuildChanged", 10) :: RemoteEvent?

	if buildChangedRemote then
		buildChangedRemote.OnClientEvent:Connect(function(bodyId: unknown, slots: unknown)
			if typeof(bodyId) ~= "string" then return end
			if typeof(slots) ~= "table" then return end

			local typedSlots: { [string]: string } = {}
			for k, v in slots :: { [any]: any } do
				if typeof(k) == "string" and typeof(v) == "string" then
					typedSlots[k :: string] = v :: string
				end
			end
			currentBuild.BodyId = bodyId :: string
			currentBuild.Slots = typedSlots

			-- Refresh UI if it's currently open.
			if screenGui.Enabled then
				refreshUI()
			end
		end)
	end
end)
