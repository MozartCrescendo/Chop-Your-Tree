if getgenv().ChopYourTreeHub and type(getgenv().ChopYourTreeHub.Unload) == "function" then
	pcall(getgenv().ChopYourTreeHub.Unload)
	task.wait(0.2)
end

local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local LocalPlayer = Players.LocalPlayer

local Window = Rayfield:CreateWindow({
	Name = "Chop Your Tree | Hub",
	LoadingTitle = "Chop Your Tree Automation",
	LoadingSubtitle = "Automation, Cans, Purifier, Equipper & Player",
	ConfigurationSaving = {
		Enabled = true,
		FolderName = "ChopYourTree_Rayfield",
		FileName = "ChopYourTreeConfig"
	},
	KeySystem = false
})

local AutoTab = Window:CreateTab("Automation", 4483362458)
local CanTab = Window:CreateTab("Watering Cans", 4483362458)
local PurifierTab = Window:CreateTab("Water Purifier", 4483362458)
local EquipTab = Window:CreateTab("Can Equipper", 4483362458)
local PlayerTab = Window:CreateTab("Player", 4483362458)

local State = {
	Running = true,

	-- Automation & Event Farm State
	AutoTapTree = false,
	TapInterval = 0.01,
	AutoPickupCans = false,
	AutoPurify = false,
	AutoCollectCoins = false,
	CollectMode = "TouchInterest",
	ScanInterval = 0.1,
	TeleportDelay = 0.01,
	ReturnToStart = true,

	-- Watering Cans Config (Fixed / Hidden UI)
	MinXpInput = "50SXT",
	CanScanInterval = 0.1,
	PickupCooldown = 0.1,
	MoveIntoRange = true,
	ReturnAfterMove = true,

	-- Water Purifier Config (Fixed / Hidden UI)
	PurifyCycleInterval = 0.1,
	EquipDelay = 0,
	ClaimPollInterval = 0.1,
	MaxPurifyWait = 15,
	PrioritizeLowestXp = true,
	MaxPurifyXpInput = "",

	-- Can Equipper Config (Fixed / Hidden UI)
	AutoHoldHighestXp = false,
	AutoHoldLowestXp = false,
	AutoEquipInterval = 0.1,

	-- Player Utility State
	AutoPrestige = false,
	PrestigeInterval = 5,
	SpeedHack = false,
	SpeedAmount = 60,
	NoClip = false,
	InfiniteJump = false,
	InstantPrompts = false
}

local MAX_CAN_RANGE = 32
local DEFAULT_WALKSPEED = 16
local PurifierBusy = false
local PurifiedRegistry = {
	ByInstance = setmetatable({}, { __mode = "k" }),
	ByName = {}
}

local Threads = {}
local Connections = {}
local SavedPromptHoldDurations = {}

local function trackThread(name: string, fn: () -> ())
	if Threads[name] then
		pcall(function() task.cancel(Threads[name]) end)
	end
	Threads[name] = task.spawn(fn)
	return Threads[name]
end

local function trackConnection(name: string, conn: RBXScriptConnection)
	if Connections[name] then
		pcall(function() conn:Disconnect() end)
	end
	Connections[name] = conn
	return conn
end

local function getRootPart(): BasePart?
	local char = LocalPlayer.Character
	if not char then return nil end
	return char.PrimaryPart or char:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid(): Humanoid?
	local char = LocalPlayer.Character
	return char and char:FindFirstChildWhichIsA("Humanoid")
end

local function setWalkSpeed(speed: number)
	local hum = getHumanoid()
	if hum then
		pcall(function()
			hum.WalkSpeed = speed
		end)
	end
end

local function applyNoClipStep()
	local char = LocalPlayer.Character
	if not char then return end
	for _, part in ipairs(char:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
		end
	end
end

local function applyInstantPrompt(prompt: ProximityPrompt)
	if SavedPromptHoldDurations[prompt] == nil then
		SavedPromptHoldDurations[prompt] = prompt.HoldDuration
	end
	pcall(function()
		prompt.HoldDuration = 0
	end)
end

local function setInstantPromptsEnabled(enabled: boolean)
	if enabled then
		for _, desc in ipairs(Workspace:GetDescendants()) do
			if desc:IsA("ProximityPrompt") then
				applyInstantPrompt(desc)
			end
		end
	else
		for prompt, origDuration in pairs(SavedPromptHoldDurations) do
			if prompt and prompt.Parent then
				pcall(function()
					prompt.HoldDuration = origDuration
				end)
			end
		end
		table.clear(SavedPromptHoldDurations)
	end
end

local function getPlayerPlot(): Instance?
	local plotVal = LocalPlayer:FindFirstChild("Plot")
	if plotVal and plotVal:IsA("ObjectValue") and plotVal.Value then
		return plotVal.Value
	end
	local plots = Workspace:FindFirstChild("Plots")
	if plots then
		for _, plot in ipairs(plots:GetChildren()) do
			if plot:GetAttribute("Plr") == LocalPlayer.Name then
				return plot
			end
		end
	end
	return nil
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
	local char = LocalPlayer.Character
	local hum = getHumanoid()
	if hum then
		pcall(function()
			hum:UnequipTools()
		end)
	end
	if char then
		local backpack = LocalPlayer:FindFirstChild("Backpack")
		for _, child in ipairs(char:GetChildren()) do
			if child:IsA("Tool") and backpack then
				pcall(function()
					child.Parent = backpack
				end)
			end
		end
	end
end

-- ==========================================
-- HIDDEN EVENT CURRENCY & TREE TAP LOGIC
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

	if typeof(firetouchinterest) == "function" then
		pcall(function()
			firetouchinterest(hrp, hitbox, 0)
			task.wait()
			firetouchinterest(hrp, hitbox, 1)
		end)
	end
end

local function collectAllExistingCoins()
	if not State.Running or not State.AutoCollectCoins then return end
	for _, child in ipairs(Workspace:GetChildren()) do
		if not State.Running or not State.AutoCollectCoins then break end
		local hb = getCoinHitbox(child)
		if hb then
			collectSingleCoin(hb)
		end
	end
end

local function stepAutoTapTree()
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then return end

	local tapRemote = remotes:FindFirstChild("TapButtonClick")
	local axeSwing = remotes:FindFirstChild("AxeSwing")
	local treeClick = remotes:FindFirstChild("TreeClick")
	local plot = getPlayerPlot()

	if tapRemote and tapRemote:IsA("RemoteEvent") and plot then
		pcall(function()
			tapRemote:FireServer(plot)
		end)
	end

	if axeSwing and axeSwing:IsA("RemoteEvent") then
		pcall(function()
			axeSwing:FireServer()
		end)
	end

	if treeClick and treeClick:IsA("RemoteFunction") and plot then
		local mainTree = plot:FindFirstChild("PlotContents") and plot.PlotContents:FindFirstChild("Tree")
		if mainTree then
			pcall(function()
				treeClick:InvokeServer(mainTree)
			end)
		end
	end
end

trackConnection("EventCoinAdded", Workspace.ChildAdded:Connect(function(child)
	if not State.Running or not State.AutoCollectCoins then return end
	if child.Name == "EventCurrency" then
		task.wait(0.02)
		local hb = getCoinHitbox(child)
		if hb then
			collectSingleCoin(hb)
		end
	end
end))

-- ==========================================
-- WATERING CAN AUTO-PICKUP LOGIC
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
			task.wait(0.02)
		end
	end

	local prevFlag = _G.TapButtonClicked
	_G.TapButtonClicked = true
	local ok = pcall(function()
		remote:FireServer(canModel)
	end)
	task.wait(0.05)
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
		if not State.Running or not State.AutoPickupCans then return end

		for _, desc in ipairs(container:GetDescendants()) do
			if not State.Running or not State.AutoPickupCans then return end
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

-- ==========================================
-- WATER PURIFIER AUTOMATION LOGIC
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
	if PurifierBusy or not State.Running then
		return
	end

	local tool = findBestUnpurifiedCanFast()
	if not tool then
		return
	end

	PurifierBusy = true
	local canName = tool.Name

	local ok, err = pcall(function()
		if not equipToolDirect(tool, State.EquipDelay) then
			return
		end

		if not State.Running or not State.AutoPurify then return end
		if not startPurification() then
			return
		end

		markPurified(tool)

		task.wait(0.02)
		unequipCurrentTool()

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
		while State.Running and State.AutoPurify and elapsed < State.MaxPurifyWait do
			local stepWait = math.min(State.ClaimPollInterval, State.MaxPurifyWait - elapsed)
			if stepWait > 0 then
				task.wait(stepWait)
				elapsed += stepWait
			else
				break
			end

			if tryClaimPurifiedCan() then
				claimed = true
				break
			end
		end

		if State.Running and State.AutoPurify and not claimed then
			if tryClaimPurifiedCan() then
				claimed = true
			end
		end

		if addedConn then
			addedConn:Disconnect()
		end

		if claimed and claimedTool then
			markPurified(claimedTool)
		elseif claimed then
			PurifiedRegistry.ByName[canName] = true
		end
	end)

	PurifierBusy = false

	if not ok then
		warn("[Water Purifier Error]", tostring(err))
	end
end

-- ==========================================
-- CAN EQUIPPER LOGIC
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

-- ==========================================
-- TAB 1: AUTOMATION
-- ==========================================
AutoTab:CreateSection("Core Automation")

AutoTab:CreateToggle({
	Name = "Auto-Tap Tree",
	CurrentValue = false,
	Flag = "AutoTapTreeToggle",
	Callback = function(Value)
		State.AutoTapTree = Value
	end
})

AutoTab:CreateToggle({
	Name = "Auto-Pick Up Watering Cans",
	CurrentValue = false,
	Flag = "AutoPickupCansToggle",
	Callback = function(Value)
		State.AutoPickupCans = Value
		if Value then
			task.spawn(stepWateringCanPickup)
		end
	end
})

AutoTab:CreateToggle({
	Name = "Auto-Purify Watering Cans",
	CurrentValue = false,
	Flag = "AutoPurifyCansToggle",
	Callback = function(Value)
		State.AutoPurify = Value
		if Value then
			task.spawn(stepWaterPurifier)
		end
	end
})

AutoTab:CreateToggle({
	Name = "Auto-Collect Asgard Coin",
	CurrentValue = false,
	Flag = "AutoCollectAsgardCoinToggle",
	Callback = function(Value)
		State.AutoCollectCoins = Value
		if Value then
			task.spawn(collectAllExistingCoins)
		end
	end
})

-- ==========================================
-- TAB 2: WATERING CANS
-- ==========================================
CanTab:CreateSection("XP Filter")

CanTab:CreateInput({
	Name = "Minimum XP to Pick Up",
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

-- ==========================================
-- TAB 3: WATER PURIFIER
-- ==========================================
PurifierTab:CreateSection("Filter & Memory")

PurifierTab:CreateInput({
	Name = "Max XP Filter",
	PlaceholderText = "Leave blank for no cap",
	RemoveTextAfterFocusLost = false,
	Flag = "MaxPurifyXpInput",
	Callback = function(Text)
		State.MaxPurifyXpInput = Text
	end
})

PurifierTab:CreateButton({
	Name = "Mark Held Can as Purified",
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

-- ==========================================
-- TAB 4: CAN EQUIPPER
-- ==========================================
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
	Name = "Auto-Hold Lowest XP Can",
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

-- ==========================================
-- TAB 5: PLAYER
-- ==========================================
local function triggerPrestigeOnce()
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local prestigeRemote = remotes and remotes:FindFirstChild("Prestige")
	if prestigeRemote and prestigeRemote:IsA("RemoteFunction") then
		pcall(function()
			prestigeRemote:InvokeServer()
		end)
	elseif prestigeRemote and prestigeRemote:IsA("RemoteEvent") then
		pcall(function()
			prestigeRemote:FireServer()
		end)
	end
end

local function formatLiveStats(): string
	local coinsText = "N/A"
	local prestigeText = "N/A"
	local ls = LocalPlayer:FindFirstChild("leaderstats")
	if ls then
		for _, stat in ipairs(ls:GetChildren()) do
			local lower = string.lower(stat.Name)
			if string.find(lower, "coin", 1, true) then
				coinsText = tostring(stat.Value)
			elseif string.find(lower, "prest", 1, true) then
				prestigeText = tostring(stat.Value)
			end
		end
	end

	local canCount = 0
	local function countCans(container: Instance?)
		if not container then return end
		for _, item in ipairs(container:GetChildren()) do
			if isWateringCanTool(item) then
				canCount += 1
			end
		end
	end
	countCans(LocalPlayer.Character)
	countCans(LocalPlayer:FindFirstChild("Backpack"))

	return string.format("Coins: %s | Prestiges: %s | Cans Held/Bag: %d", coinsText, prestigeText, canCount)
end

PlayerTab:CreateSection("Live Stats")
local StatsParagraph = PlayerTab:CreateParagraph({
	Title = "Player Overview",
	Content = formatLiveStats()
})

PlayerTab:CreateSection("Prestige")

PlayerTab:CreateButton({
	Name = "Prestige Now",
	Callback = function()
		triggerPrestigeOnce()
		Rayfield:Notify({
			Title = "Prestige Requested",
			Content = "Sent prestige request to server.",
			Duration = 2
		})
	end
})

PlayerTab:CreateSlider({
	Name = "Auto-Prestige Interval (Seconds)",
	Range = {1, 30},
	Increment = 1,
	Suffix = "s",
	CurrentValue = State.PrestigeInterval,
	Flag = "AutoPrestigeIntervalSlider",
	Callback = function(Value)
		State.PrestigeInterval = Value
	end
})

PlayerTab:CreateToggle({
	Name = "Auto-Prestige",
	CurrentValue = false,
	Flag = "AutoPrestigeToggle",
	Callback = function(Value)
		State.AutoPrestige = Value
	end
})

PlayerTab:CreateSection("Movement & World")

PlayerTab:CreateSlider({
	Name = "WalkSpeed",
	Range = {16, 200},
	Increment = 2,
	Suffix = "",
	CurrentValue = State.SpeedAmount,
	Flag = "WalkSpeedSlider",
	Callback = function(Value)
		State.SpeedAmount = Value
		if State.SpeedHack then
			setWalkSpeed(Value)
		end
	end
})

PlayerTab:CreateToggle({
	Name = "WalkSpeed Boost",
	CurrentValue = false,
	Flag = "SpeedHackToggle",
	Callback = function(Value)
		State.SpeedHack = Value
		if not Value then
			setWalkSpeed(DEFAULT_WALKSPEED)
		else
			setWalkSpeed(State.SpeedAmount)
		end
	end
})

PlayerTab:CreateToggle({
	Name = "No Clip",
	CurrentValue = false,
	Flag = "NoClipToggle",
	Callback = function(Value)
		State.NoClip = Value
	end
})

PlayerTab:CreateToggle({
	Name = "Infinite Jump",
	CurrentValue = false,
	Flag = "InfiniteJumpToggle",
	Callback = function(Value)
		State.InfiniteJump = Value
	end
})

PlayerTab:CreateToggle({
	Name = "Instant Proximity Prompts",
	CurrentValue = false,
	Flag = "InstantPromptsToggle",
	Callback = function(Value)
		State.InstantPrompts = Value
		setInstantPromptsEnabled(Value)
	end
})

-- ==========================================
-- CLEANUP & BACKGROUND LOOPS
-- ==========================================
local function unloadHub()
	State.Running = false
	State.AutoCollectCoins = false
	State.AutoTapTree = false
	State.AutoPickupCans = false
	State.AutoPurify = false
	State.AutoHoldHighestXp = false
	State.AutoHoldLowestXp = false
	State.AutoPrestige = false
	State.SpeedHack = false
	State.NoClip = false
	State.InfiniteJump = false
	State.InstantPrompts = false
	PurifierBusy = false

	setInstantPromptsEnabled(false)
	setWalkSpeed(DEFAULT_WALKSPEED)

	for name, thread in pairs(Threads) do
		pcall(function() task.cancel(thread) end)
		Threads[name] = nil
	end

	for name, conn in pairs(Connections) do
		pcall(function() conn:Disconnect() end)
		Connections[name] = nil
	end

	getgenv().ChopYourTreeHub = nil
end

getgenv().ChopYourTreeHub = {
	State = State,
	Unload = unloadHub
}

trackConnection("SteppedLoop", RunService.Stepped:Connect(function()
	if not State.Running then return end
	if State.NoClip then
		applyNoClipStep()
	end
	if State.SpeedHack then
		setWalkSpeed(State.SpeedAmount)
	end
end))

trackConnection("JumpRequestConn", UserInputService.JumpRequest:Connect(function()
	if not State.Running or not State.InfiniteJump then return end
	local hum = getHumanoid()
	if hum then
		pcall(function()
			hum:ChangeState(Enum.HumanoidStateType.Jumping)
		end)
	end
end))

trackConnection("PromptShownConn", ProximityPromptService.PromptShown:Connect(function(prompt)
	if State.Running and State.InstantPrompts and prompt then
		applyInstantPrompt(prompt)
	end
end))

trackThread("EventCollectorLoop", function()
	while State.Running do
		if State.AutoCollectCoins then
			pcall(collectAllExistingCoins)
		end
		task.wait(State.ScanInterval)
	end
end)

trackThread("AutoTapLoop", function()
	while State.Running do
		if State.AutoTapTree then
			pcall(stepAutoTapTree)
		end
		task.wait(State.TapInterval)
	end
end)

trackThread("CanPickupLoop", function()
	while State.Running do
		if State.AutoPickupCans then
			pcall(stepWateringCanPickup)
		end
		task.wait(State.CanScanInterval)
	end
end)

trackThread("PurifierLoop", function()
	while State.Running do
		if State.AutoPurify and not PurifierBusy then
			pcall(stepWaterPurifier)
		end
		task.wait(State.PurifyCycleInterval)
	end
end)

trackThread("EquipperLoop", function()
	while State.Running do
		if State.AutoHoldHighestXp then
			pcall(equipExtremeCan, "HIGHEST", false)
		elseif State.AutoHoldLowestXp then
			pcall(equipExtremeCan, "LOWEST", false)
		end
		task.wait(State.AutoEquipInterval)
	end
end)

trackThread("PrestigeLoop", function()
	while State.Running do
		if State.AutoPrestige then
			pcall(triggerPrestigeOnce)
		end
		task.wait(State.PrestigeInterval)
	end
end)

trackThread("StatsLoop", function()
	while State.Running do
		if StatsParagraph then
			pcall(function()
				StatsParagraph:Set({
					Title = "Player Overview",
					Content = formatLiveStats()
				})
			end)
		end
		task.wait(1)
	end
end)

Rayfield:LoadConfiguration()
