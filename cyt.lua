local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

local Window = Rayfield:CreateWindow({
	Name = "Chop Your Tree | Hub",
	LoadingTitle = "Chop Your Tree Automation",
	LoadingSubtitle = "Event Currency, Watering Cans & Purifier",
	ConfigurationSaving = {
		Enabled = true,
		FolderName = "ChopYourTree_Rayfield",
		FileName = "ChopYourTreeConfig"
	},
	KeySystem = false
})

local EventTab = Window:CreateTab("Event Farm", 4483362458)
local CanTab = Window:CreateTab("Watering Cans", 4483362458)
local PurifierTab = Window:CreateTab("Water Purifier", 4483362458)
local EquipTab = Window:CreateTab("Can Equipper", 4483362458)

local State = {
	-- Event Farm State
	AutoCollect = false,
	Mode = "TouchInterest (Silent / No TP)",
	ScanInterval = 0.25,
	TeleportDelay = 0.08,
	ReturnToStart = true,

	-- Watering Can Auto-Pickup State
	AutoPickupCans = false,
	MinXpInput = "50SXT",
	CanScanInterval = 0.5,
	PickupCooldown = 0.15,
	MoveIntoRange = true,
	ReturnAfterMove = true,

	-- Water Purifier State
	AutoPurify = false,
	PurifyCycleInterval = 0.2,
	EquipDelay = 0,
	ClaimPollInterval = 0.35,
	MaxPurifyWait = 60,
	PrioritizeLowestXp = true,
	MaxPurifyXpInput = "",

	-- Can Equipper State
	AutoHoldHighestXp = false,
	AutoHoldLowestXp = false,
	AutoEquipInterval = 0.5
}

local MAX_CAN_RANGE = 32
local PurifiedRegistry = {
	ByInstance = setmetatable({}, { __mode = "k" }),
	ByName = {}
}

local function getRootPart(): BasePart?
	local char = LocalPlayer.Character
	if not char then return nil end
	return char.PrimaryPart or char:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid(): Humanoid?
	local char = LocalPlayer.Character
	return char and char:FindFirstChildWhichIsA("Humanoid")
end

-- ==========================================
-- SUFFIXED NUMBER PARSER (RichText & SEPT Safe)
-- ==========================================
local SUFFIX_MULTIPLIERS = {
	[""] = 1,
	["K"] = 1e3,
	["M"] = 1e6,
	["B"] = 1e9,
	["T"] = 1e12,
	["QA"] = 1e15,
	["QI"] = 1e18,
	["SX"] = 1e21,
	["SXT"] = 1e21,
	["SP"] = 1e24,
	["SPT"] = 1e24,
	["SEP"] = 1e24,
	["SEPT"] = 1e24,
	["OC"] = 1e27,
	["OCT"] = 1e27,
	["NO"] = 1e30,
	["NON"] = 1e30,
	["DC"] = 1e33,
	["DEC"] = 1e33,
	["UD"] = 1e36,
	["UDC"] = 1e36,
	["UDEC"] = 1e36,
	["DD"] = 1e39,
	["DDC"] = 1e39,
	["TD"] = 1e42,
	["TDC"] = 1e42
}

local function stripRichText(str: string): string
	return string.gsub(str, "<[^>]->", "")
end

local function parseSuffixedNumber(rawText: string?): number?
	if not rawText or rawText == "" then return nil end

	local plain = stripRichText(rawText)
	local firstPart = string.match(plain, "^([^/]+)") or plain
	local cleaned = string.gsub(firstPart, ",", "")
	cleaned = string.gsub(cleaned, "%s*[Xx][Pp]%s*", "")

	local numStr, suffix = string.match(cleaned, "([%d%.]+)%s*([%a]*)")
	local baseNum = tonumber(numStr)
	if not baseNum then return nil end

	local key = string.upper(suffix or "")
	local mult = SUFFIX_MULTIPLIERS[key] or 1
	return baseNum * mult
end

local function isWateringCanTool(tool: Instance): boolean
	if not tool:IsA("Tool") then return false end
	local lower = string.lower(tool.Name)
	if string.find(lower, "axe", 1, true) then
		return false
	end
	if string.find(lower, "xp", 1, true)
		or string.find(lower, "can", 1, true)
		or string.find(lower, "water", 1, true)
		or tool:GetAttribute("WateringCan") ~= nil
	then
		return true
	end
	return false
end

local function getToolXpValue(tool: Tool): number?
	local xpVal = parseSuffixedNumber(tool.Name)
	if xpVal then return xpVal end

	for attrName, attrVal in pairs(tool:GetAttributes()) do
		if string.find(string.lower(tostring(attrName)), "xp", 1, true) then
			if type(attrVal) == "number" then
				return attrVal
			elseif type(attrVal) == "string" then
				local parsed = parseSuffixedNumber(attrVal)
				if parsed then return parsed end
			end
		end
	end

	for _, desc in ipairs(tool:GetDescendants()) do
		if desc:IsA("TextLabel") then
			local parsed = parseSuffixedNumber(desc.Text)
			if parsed then return parsed end
		elseif desc:IsA("NumberValue") or desc:IsA("IntValue") then
			if string.find(string.lower(desc.Name), "xp", 1, true) then
				return desc.Value
			end
		elseif desc:IsA("StringValue") then
			if string.find(string.lower(desc.Name), "xp", 1, true) then
				local parsed = parseSuffixedNumber(desc.Value)
				if parsed then return parsed end
			end
		end
	end

	return nil
end

local function equipToolDirect(tool: Tool, delaySeconds: number?): boolean
	local char = LocalPlayer.Character
	local hum = getHumanoid()
	if not (char and tool and tool.Parent) then
		return false
	end

	if tool.Parent == char then
		return true
	end

	if hum then
		pcall(function()
			hum:EquipTool(tool)
		end)
	end

	if tool.Parent ~= char then
		pcall(function()
			tool.Parent = char
		end)
	end

	if delaySeconds and delaySeconds > 0 then
		task.wait(delaySeconds)
	end

	return tool.Parent == char
end

local function unequipCurrentTool()
	local hum = getHumanoid()
	if hum then
		pcall(function()
			hum:UnequipTools()
		end)
	end
end

-- ==========================================
-- TAB 1: EVENT CURRENCY COLLECTOR (PRESERVED)
-- ==========================================
local function getCoinHitbox(obj: Instance): BasePart?
	if obj.Name == "EventCurrency" then
		local hb = obj:FindFirstChild("HitBox")
		if hb and hb:IsA("BasePart") then
			return hb
		end
		if obj:IsA("BasePart") then
			return obj
		end
		if obj:IsA("Model") then
			return obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart", true)
		end
	elseif obj.Name == "HitBox" and obj:IsA("BasePart") and obj.Parent and obj.Parent.Name == "EventCurrency" then
		return obj
	end
	return nil
end

local function collectSingleCoin(hitbox: BasePart)
	local hrp = getRootPart()
	if not (hrp and hitbox and hitbox.Parent) then return end

	if State.Mode == "TouchInterest (Silent / No TP)" and typeof(firetouchinterest) == "function" then
		pcall(function()
			firetouchinterest(hrp, hitbox, 0)
			task.wait()
			firetouchinterest(hrp, hitbox, 1)
		end)
	else
		hrp.CFrame = hitbox.CFrame + Vector3.new(0, 2, 0)
		if typeof(firetouchinterest) == "function" then
			pcall(function()
				firetouchinterest(hrp, hitbox, 0)
				firetouchinterest(hrp, hitbox, 1)
			end)
		end
		task.wait(State.TeleportDelay)
	end
end

local function collectAllExistingCoins()
	local hrp = getRootPart()
	if not hrp then return end

	local savedCFrame = hrp.CFrame
	local collectedAny = false

	for _, child in ipairs(Workspace:GetChildren()) do
		if not State.AutoCollect then break end
		local hb = getCoinHitbox(child)
		if hb then
			collectSingleCoin(hb)
			collectedAny = true
		end
	end

	if collectedAny and State.Mode == "Teleport to Coin" and State.ReturnToStart then
		local currentHrp = getRootPart()
		if currentHrp then
			currentHrp.CFrame = savedCFrame
		end
	end
end

Workspace.ChildAdded:Connect(function(child)
	if not State.AutoCollect then return end
	if child.Name == "EventCurrency" then
		task.wait(0.05)
		local hb = getCoinHitbox(child)
		if hb then
			if State.Mode == "TouchInterest (Silent / No TP)" then
				collectSingleCoin(hb)
			else
				collectAllExistingCoins()
			end
		end
	end
end)

EventTab:CreateSection("Event Currency Collector")

EventTab:CreateDropdown({
	Name = "Collection Method",
	Options = {
		"TouchInterest (Silent / No TP)",
		"Teleport to Coin"
	},
	CurrentOption = {State.Mode},
	MultipleOptions = false,
	Flag = "CollectModeDropdown",
	Callback = function(Options)
		State.Mode = Options[1]
	end
})

EventTab:CreateToggle({
	Name = "Return to Original Spot (Teleport Mode)",
	CurrentValue = true,
	Flag = "ReturnSpotToggle",
	Callback = function(Value)
		State.ReturnToStart = Value
	end
})

EventTab:CreateSlider({
	Name = "Teleport Step Delay (Seconds)",
	Range = {0.03, 0.5},
	Increment = 0.01,
	Suffix = "s",
	CurrentValue = State.TeleportDelay,
	Flag = "TpDelaySlider",
	Callback = function(Value)
		State.TeleportDelay = Value
	end
})

EventTab:CreateToggle({
	Name = "Auto-Collect Event Currency (AFK)",
	CurrentValue = false,
	Flag = "AutoCollectEventToggle",
	Callback = function(Value)
		State.AutoCollect = Value
		if Value then
			Rayfield:Notify({
				Title = "Event Collector Active",
				Content = "Watching Workspace.EventCurrency (" .. State.Mode .. ")",
				Duration = 3
			})
			task.spawn(collectAllExistingCoins)
		end
	end
})

-- ==========================================
-- TAB 2: WATERING CAN AUTO-PICKUP (PRESERVED)
-- ==========================================
local function getHorizontalDistance(partA: BasePart, partB: BasePart): number
	local vecA = Vector3.new(partA.Position.X, 0, partA.Position.Z)
	local vecB = Vector3.new(partB.Position.X, 0, partB.Position.Z)
	return (vecA - vecB).Magnitude
end

local function getClickWateringCanRemote(): RemoteEvent?
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local remote = remotes and remotes:FindFirstChild("ClickWateringCan")
	if remote and remote:IsA("RemoteEvent") then
		return remote
	end
	return nil
end

local function triggerWateringCanPickup(canModel: Model): boolean
	local remote = getClickWateringCanRemote()
	local hrp = getRootPart()
	if not (remote and hrp and canModel and canModel.Parent) then
		return false
	end

	local hitBox = canModel:FindFirstChild("HitBox")
	local savedCFrame: CFrame? = nil
	local moved = false

	if hitBox and hitBox:IsA("BasePart") then
		local dist = getHorizontalDistance(hitBox, hrp)
		if dist > MAX_CAN_RANGE then
			if not State.MoveIntoRange then
				return false
			end
			savedCFrame = hrp.CFrame
			hrp.CFrame = hitBox.CFrame + Vector3.new(0, 2.5, 0)
			moved = true
			task.wait(0.05)
		end
	end

	local prevFlag = _G.TapButtonClicked
	_G.TapButtonClicked = true
	local ok = pcall(function()
		remote:FireServer(canModel)
	end)
	task.wait(0.1)
	_G.TapButtonClicked = prevFlag

	if moved and savedCFrame and State.ReturnAfterMove then
		local currentHrp = getRootPart()
		if currentHrp then
			currentHrp.CFrame = savedCFrame
		end
	end

	return ok
end

local function stepWateringCanPickup()
	local mutations = Workspace:FindFirstChild("Mutations")
	if not mutations then return end

	local minXpThreshold = parseSuffixedNumber(State.MinXpInput)
	if not minXpThreshold then return end

	for _, container in ipairs(mutations:GetChildren()) do
		if not State.AutoPickupCans then return end

		for _, desc in ipairs(container:GetDescendants()) do
			if not State.AutoPickupCans then return end
			if desc.Name == "WateringCan" and desc:IsA("Model") then
				local xpLabel = desc:FindFirstChild("LevelBar")
					and desc.LevelBar:FindFirstChild("Bar")
					and desc.LevelBar.Bar:FindFirstChild("XP")

				if xpLabel and xpLabel:IsA("TextLabel") then
					local currentXp = parseSuffixedNumber(xpLabel.Text)
					if currentXp and currentXp >= minXpThreshold then
						if triggerWateringCanPickup(desc) then
							task.wait(State.PickupCooldown)
							return
						end
					end
				end
			end
		end
	end
end

CanTab:CreateSection("XP Threshold Whitelist")

CanTab:CreateInput({
	Name = "Minimum XP to Pick Up (e.g. 50SXT, 200SXT, 1SP)",
	PlaceholderText = "50SXT",
	RemoveTextAfterFocusLost = false,
	Flag = "MinCanXpInput",
	Callback = function(Text)
		if Text ~= "" then
			State.MinXpInput = Text
			if not parseSuffixedNumber(Text) then
				Rayfield:Notify({
					Title = "Invalid XP Format",
					Content = "Use formats like 50SXT, 250SXT, 1SP, 500B",
					Duration = 3
				})
			end
		end
	end
})

CanTab:CreateToggle({
	Name = "Move Into Range if >32 Studs",
	CurrentValue = true,
	Flag = "MoveCanIntoRangeToggle",
	Callback = function(Value)
		State.MoveIntoRange = Value
	end
})

CanTab:CreateToggle({
	Name = "Return After Moving Into Range",
	CurrentValue = true,
	Flag = "ReturnAfterCanMoveToggle",
	Callback = function(Value)
		State.ReturnAfterMove = Value
	end
})

CanTab:CreateSlider({
	Name = "Pickup Cooldown (Seconds)",
	Range = {0.1, 1.5},
	Increment = 0.05,
	Suffix = "s",
	CurrentValue = State.PickupCooldown,
	Flag = "CanConfirmDelaySlider",
	Callback = function(Value)
		State.PickupCooldown = Value
	end
})

CanTab:CreateSlider({
	Name = "Pickup Cycle Interval (Seconds)",
	Range = {0.25, 3.0},
	Increment = 0.05,
	Suffix = "s",
	CurrentValue = State.CanScanInterval,
	Flag = "CanScanIntervalSlider",
	Callback = function(Value)
		State.CanScanInterval = Value
	end
})

CanTab:CreateSection("Automation Toggle")

CanTab:CreateToggle({
	Name = "Auto-Pick Up Cans Above Minimum XP",
	CurrentValue = false,
	Flag = "AutoPickupCansToggle",
	Callback = function(Value)
		State.AutoPickupCans = Value
		if Value then
			Rayfield:Notify({
				Title = "Watering Can Auto-Pickup Active",
				Content = "Picking up cans >= " .. State.MinXpInput .. " XP",
				Duration = 3
			})
			task.spawn(stepWateringCanPickup)
		end
	end
})

-- ==========================================
-- TAB 3: WATER PURIFIER AUTOMATION (PRESERVED)
-- ==========================================
local function findPurifierRemote(name: string): RemoteFunction?
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if remotes then
		local found = remotes:FindFirstChild(name, true)
		if found and found:IsA("RemoteFunction") then
			return found
		end
	end
	local fallback = ReplicatedStorage:FindFirstChild(name, true)
	if fallback and fallback:IsA("RemoteFunction") then
		return fallback
	end
	return nil
end

local function isAlreadyPurified(tool: Tool): boolean
	if PurifiedRegistry.ByInstance[tool] then
		return true
	end
	if PurifiedRegistry.ByName[tool.Name] then
		return true
	end
	local lower = string.lower(tool.Name)
	if string.find(lower, "purif", 1, true) then
		return true
	end
	for attrName, attrVal in pairs(tool:GetAttributes()) do
		local aLower = string.lower(tostring(attrName))
		if string.find(aLower, "purif", 1, true) and (attrVal == true or tostring(attrVal) ~= "") then
			return true
		end
	end
	return false
end

local function markPurified(tool: Tool?)
	if not tool then return end
	PurifiedRegistry.ByInstance[tool] = true
	PurifiedRegistry.ByName[tool.Name] = true
end

local function findBestUnpurifiedCanFast(): Tool?
	local maxXpCap = nil
	if State.MaxPurifyXpInput ~= "" then
		maxXpCap = parseSuffixedNumber(State.MaxPurifyXpInput)
	end

	local bestTool: Tool? = nil
	local bestXp: number = math.huge

	local function considerContainer(container: Instance?)
		if not container then return end
		for _, child in ipairs(container:GetChildren()) do
			if isWateringCanTool(child) and not isAlreadyPurified(child) then
				local xp = getToolXpValue(child)
				if maxXpCap and xp and xp > maxXpCap then
					continue
				end

				if not State.PrioritizeLowestXp then
					return child
				end

				local score = xp or math.huge
				if score < bestXp or not bestTool then
					bestXp = score
					bestTool = child
				end
			end
		end
	end

	considerContainer(LocalPlayer.Character)
	if bestTool and not State.PrioritizeLowestXp then
		return bestTool
	end

	considerContainer(LocalPlayer:FindFirstChild("Backpack"))
	return bestTool
end

local function startPurification(): boolean
	local startRemote = findPurifierRemote("WaterPurifier")
	if startRemote then
		local ok, result = pcall(function()
			return startRemote:InvokeServer()
		end)
		if ok and result ~= false then
			return true
		end
	end

	local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
	local purGui = playerGui and playerGui:FindFirstChild("WaterPurifier")
	local startBtn = purGui and purGui:FindFirstChild("Start", true)
	if startBtn and startBtn:IsA("GuiButton") and typeof(firesignal) == "function" then
		local ok = pcall(function()
			firesignal(startBtn.Activated)
		end)
		if ok then
			return true
		end
	end

	return false
end

local function tryClaimPurifiedCan(): boolean
	local claimRemote = findPurifierRemote("ClaimWaterPurifier")
	if claimRemote then
		local ok, result = pcall(function()
			return claimRemote:InvokeServer()
		end)
		if ok and result ~= false and result ~= nil then
			return true
		end
	end

	local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
	local purGui = playerGui and playerGui:FindFirstChild("WaterPurifier")
	local claimBtn = purGui and purGui:FindFirstChild("Claim", true)
	if claimBtn and claimBtn:IsA("GuiButton") and claimBtn.Visible and typeof(firesignal) == "function" then
		local ok = pcall(function()
			firesignal(claimBtn.Activated)
		end)
		if ok then
			return true
		end
	end

	return false
end

local function stepWaterPurifier()
	local tool = findBestUnpurifiedCanFast()
	if not tool then
		return
	end

	local canName = tool.Name
	if not equipToolDirect(tool, State.EquipDelay) then
		return
	end

	if not State.AutoPurify then return end
	if not startPurification() then
		return
	end

	markPurified(tool)

	local backpack = LocalPlayer:FindFirstChild("Backpack")
	local claimed = false
	local claimedTool: Tool? = nil
	local addedConn: RBXScriptConnection? = nil

	if backpack then
		addedConn = backpack.ChildAdded:Connect(function(item)
			if item:IsA("Tool") then
				claimedTool = item
			end
		end)
	end

	local elapsed = 0
	while State.AutoPurify and elapsed < State.MaxPurifyWait do
		if tryClaimPurifiedCan() then
			claimed = true
			break
		end
		task.wait(State.ClaimPollInterval)
		elapsed += State.ClaimPollInterval
	end

	if addedConn then
		addedConn:Disconnect()
	end

	if claimed and claimedTool then
		markPurified(claimedTool)
	elseif claimed then
		PurifiedRegistry.ByName[canName] = true
	end
end

PurifierTab:CreateSection("Fast Selection & Filtering")

PurifierTab:CreateToggle({
	Name = "Prioritize Lowest XP Cans First (Fast Unpurified)",
	CurrentValue = true,
	Flag = "PrioritizeLowestXpToggle",
	Callback = function(Value)
		State.PrioritizeLowestXp = Value
	end
})

PurifierTab:CreateInput({
	Name = "Max XP Filter (Optional, e.g. 500SXT — Blank = All)",
	PlaceholderText = "Leave blank for no cap",
	RemoveTextAfterFocusLost = false,
	Flag = "MaxPurifyXpInput",
	Callback = function(Text)
		State.MaxPurifyXpInput = Text
	end
})

PurifierTab:CreateSection("Purifier Timing")

PurifierTab:CreateSlider({
	Name = "Equip Wait Delay (Seconds)",
	Range = {0, 1.5},
	Increment = 0.05,
	Suffix = "s",
	CurrentValue = State.EquipDelay,
	Flag = "PurifyEquipDelaySlider",
	Callback = function(Value)
		State.EquipDelay = Value
	end
})

PurifierTab:CreateSlider({
	Name = "Claim Check Interval (Seconds)",
	Range = {0.2, 2.0},
	Increment = 0.05,
	Suffix = "s",
	CurrentValue = State.ClaimPollInterval,
	Flag = "PurifyClaimPollSlider",
	Callback = function(Value)
		State.ClaimPollInterval = Value
	end
})

PurifierTab:CreateSlider({
	Name = "Max Timer Wait (Seconds)",
	Range = {10, 180},
	Increment = 5,
	Suffix = "s",
	CurrentValue = State.MaxPurifyWait,
	Flag = "PurifyMaxWaitSlider",
	Callback = function(Value)
		State.MaxPurifyWait = Value
	end
})

PurifierTab:CreateSlider({
	Name = "Cycle Interval Between Cans (Seconds)",
	Range = {0.1, 5.0},
	Increment = 0.1,
	Suffix = "s",
	CurrentValue = State.PurifyCycleInterval,
	Flag = "PurifyCycleIntervalSlider",
	Callback = function(Value)
		State.PurifyCycleInterval = Value
	end
})

PurifierTab:CreateButton({
	Name = "Mark Held Can as Purified (Skip)",
	Callback = function()
		local char = LocalPlayer.Character
		local heldTool = char and char:FindFirstChildWhichIsA("Tool")
		if heldTool then
			markPurified(heldTool)
			Rayfield:Notify({
				Title = "Marked as Purified",
				Content = "Will skip '" .. heldTool.Name .. "'",
				Duration = 2.5
			})
		end
	end
})

PurifierTab:CreateButton({
	Name = "Reset Purified Can Memory",
	Callback = function()
		table.clear(PurifiedRegistry.ByInstance)
		table.clear(PurifiedRegistry.ByName)
		Rayfield:Notify({
			Title = "Purifier Memory Cleared",
			Content = "Cleared session history of purified cans.",
			Duration = 3
		})
	end
})

PurifierTab:CreateSection("Automation Toggle")

PurifierTab:CreateToggle({
	Name = "Auto-Purify Watering Cans (Loop)",
	CurrentValue = false,
	Flag = "AutoPurifyCansToggle",
	Callback = function(Value)
		State.AutoPurify = Value
		if Value then
			Rayfield:Notify({
				Title = "Water Purifier Active",
				Content = "Fast-scanning inventory for unpurified cans.",
				Duration = 3
			})
			task.spawn(stepWaterPurifier)
		end
	end
})

-- ==========================================
-- TAB 4: CAN EQUIPPER (HIGHEST / LOWEST XP)
-- ==========================================
local function findExtremeXpCan(mode: "HIGHEST" | "LOWEST"): (Tool?, number?)
	local chosenTool: Tool? = nil
	local chosenXp: number? = nil

	local function scanContainer(container: Instance?)
		if not container then return end
		for _, child in ipairs(container:GetChildren()) do
			if isWateringCanTool(child) then
				local xp = getToolXpValue(child)
				if xp then
					if not chosenXp then
						chosenXp = xp
						chosenTool = child
					elseif mode == "HIGHEST" and xp > chosenXp then
						chosenXp = xp
						chosenTool = child
					elseif mode == "LOWEST" and xp < chosenXp then
						chosenXp = xp
						chosenTool = child
					end
				elseif not chosenTool then
					chosenTool = child
				end
			end
		end
	end

	scanContainer(LocalPlayer.Character)
	scanContainer(LocalPlayer:FindFirstChild("Backpack"))

	return chosenTool, chosenXp
end

local function equipExtremeCan(mode: "HIGHEST" | "LOWEST", notify: boolean): boolean
	local tool, _ = findExtremeXpCan(mode)
	if not tool then
		if notify then
			Rayfield:Notify({
				Title = "No Watering Can Found",
				Content = "No watering cans found in Character or Backpack.",
				Duration = 2.5
			})
		end
		return false
	end

	local ok = equipToolDirect(tool, 0)
	if notify then
		local label = mode == "HIGHEST" and "Highest XP Can" or "Lowest XP Can"
		Rayfield:Notify({
			Title = ok and ("Equipped " .. label) or "Equip Failed",
			Content = tool.Name,
			Duration = 2.5
		})
	end
	return ok
end

EquipTab:CreateSection("Instant Hold by XP")

EquipTab:CreateButton({
	Name = "Hold Highest XP Can",
	Callback = function()
		equipExtremeCan("HIGHEST", true)
	end
})

EquipTab:CreateButton({
	Name = "Hold Lowest XP Can",
	Callback = function()
		equipExtremeCan("LOWEST", true)
	end
})

EquipTab:CreateButton({
	Name = "Unequip Held Can",
	Callback = function()
		unequipCurrentTool()
		Rayfield:Notify({
			Title = "Unequipped",
			Content = "Returned held tool to Backpack.",
			Duration = 2
		})
	end
})

EquipTab:CreateSection("Continuous Auto-Hold")

local AutoHoldHighestToggle
local AutoHoldLowestToggle

AutoHoldHighestToggle = EquipTab:CreateToggle({
	Name = "Auto-Hold Highest XP Can",
	CurrentValue = false,
	Flag = "AutoHoldHighestXpToggle",
	Callback = function(Value)
		State.AutoHoldHighestXp = Value
		if Value then
			if State.AutoHoldLowestXp then
				State.AutoHoldLowestXp = false
				if AutoHoldLowestToggle then
					AutoHoldLowestToggle:Set(false)
				end
			end
			equipExtremeCan("HIGHEST", false)
		end
	end
})

AutoHoldLowestToggle = EquipTab:CreateToggle({
	Name = "Auto-Hold Lowest XP Can (Great for Trading)",
	CurrentValue = false,
	Flag = "AutoHoldLowestXpToggle",
	Callback = function(Value)
		State.AutoHoldLowestXp = Value
		if Value then
			if State.AutoHoldHighestXp then
				State.AutoHoldHighestXp = false
				if AutoHoldHighestToggle then
					AutoHoldHighestToggle:Set(false)
				end
			end
			equipExtremeCan("LOWEST", false)
		end
	end
})

EquipTab:CreateSlider({
	Name = "Auto-Hold Check Interval (Seconds)",
	Range = {0.1, 3.0},
	Increment = 0.05,
	Suffix = "s",
	CurrentValue = State.AutoEquipInterval,
	Flag = "AutoEquipIntervalSlider",
	Callback = function(Value)
		State.AutoEquipInterval = Value
	end
})

-- ==========================================
-- BACKGROUND LOOPS
-- ==========================================
task.spawn(function()
	while true do
		if State.AutoCollect then
			pcall(collectAllExistingCoins)
		end
		task.wait(State.ScanInterval)
	end
end)

task.spawn(function()
	while true do
		if State.AutoPickupCans then
			pcall(stepWateringCanPickup)
		end
		task.wait(State.CanScanInterval)
	end
end)

task.spawn(function()
	while true do
		if State.AutoPurify then
			pcall(stepWaterPurifier)
		end
		task.wait(State.PurifyCycleInterval)
	end
end)

task.spawn(function()
	while true do
		if State.AutoHoldHighestXp then
			pcall(equipExtremeCan, "HIGHEST", false)
		elseif State.AutoHoldLowestXp then
			pcall(equipExtremeCan, "LOWEST", false)
		end
		task.wait(State.AutoEquipInterval)
	end
end)

Rayfield:LoadConfiguration()
