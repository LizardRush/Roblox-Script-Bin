-- Imports
local RS = game:GetService("ReplicatedStorage")
local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()
local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local textChannels = TextChatService:WaitForChild("TextChannels")
local TS = game:GetService("TweenService")
local general = textChannels:WaitForChild("RBXGeneral")
local VirtualUser = game:GetService("VirtualUser")
local workspace = game:GetService("Workspace") -- Cached workspace
local HttpService = game:GetService("HttpService") -- Added HttpService for webhooks

-- |
-- | --- Command System
local function compileCommands(commands)
    local compiled = {}

    for _, command in ipairs(commands) do
        local variables = {}

        -- Collect variable names
        for name in command.template:gmatch("{(.-)}") do
            table.insert(variables, name)
        end

        -- Escape Lua pattern characters
        local pattern = command.template:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")

        -- Replace variables with capture groups
        pattern = "^" .. pattern:gsub("{.-}", "(.+)") .. "$"

        table.insert(compiled, {
            pattern = pattern,
            variables = variables,
            callback = command.callback,
            template = command.template,
        })
    end

    return compiled
end

local function unequip()
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	if humanoid then
		humanoid:UnequipTools()
	end
end

local function searchInventory(query)
	query = query:lower()

	local player = Players.LocalPlayer
	local character = player.Character
	local backpack = player:FindFirstChild("Backpack")

	if character then
		for _, tool in ipairs(character:GetChildren()) do
			if tool:IsA("Tool") and tool.Name:lower():find(query, 1, true) then
				return tool
			end
		end
	end

	if backpack then
		for _, tool in ipairs(backpack:GetChildren()) do
			if tool:IsA("Tool") and tool.Name:lower():find(query, 1, true) then
				return tool
			end
		end
	end

	return nil
end

local function tween(cf, speed)
    local character = Players.LocalPlayer.Character
    if not character or not character.PrimaryPart then return false end
    
    local primaryPart = character.PrimaryPart
    primaryPart.Anchored = true
    
    local vectorPosition = cf.Position
    local distance = (primaryPart.Position - vectorPosition).magnitude
    local time = distance / speed
    
    local tweenInfo = TweenInfo.new(time, Enum.EasingStyle.Linear)
    local tweenObject = TS:Create(primaryPart, tweenInfo, {CFrame = cf})
    tweenObject:Play()
    
    tweenObject.Completed:Wait()
    primaryPart.Anchored = false
    
    return true
end

local function searchPlayers(query)
	query = query:lower()

    for _, player in ipairs(Players:GetPlayers()) do
        if player.Name:lower():find(query, 1, true) then
            return player
        end
    end

	return nil
end

local function facePart(part)
	local player = Players.LocalPlayer
	local char = player.Character

	if not char or not char:FindFirstChild("HumanoidRootPart") then
		return
	end

	local root = char.HumanoidRootPart

	root.CFrame = CFrame.lookAt(
		root.Position,
		part.Position
	)
end

local function drop(tool)
	if not tool or not tool:IsA("Tool") then
		return false
	end

	local player = Players.LocalPlayer
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	if not character or not humanoid then
		return false
	end

	if tool.Parent ~= character then
		humanoid:EquipTool(tool)
		task.wait()
	end

	tool.Parent = workspace

	return true
end

-- Variables
local speed = 300
local collecting = false
local enabled = true
local disableOverride = false

local commands = {
    {
        template = "give {user} a {fruit}",
        callback = function(args)
            local player = searchPlayers(args.user)
            local fruit = searchInventory(args.fruit)
            
            if player and player.Character and player.Character.PrimaryPart then
                local char = player.Character
                local pos = char.PrimaryPart.CFrame * CFrame.new(0, 0, -3.5)
                
                if fruit then
                    general:Chat("i gotchu")
                    disableOverride = true
                    if tween(pos, speed) then
                        drop(fruit)
                        disableOverride = false
                    end
                else
                    general:Chat("i don't gotchu")
                end
            else
                general:Chat("Player or character not found.")
            end
        end,
    },
    { -- New command: send inv
        template = "send inv",
        callback = function()
            local player = Players.LocalPlayer
            local inventory = {}

            -- Check character for tools
            if player.Character then
                for _, child in ipairs(player.Character:GetChildren()) do
                    if child:IsA("Tool") then
                        table.insert(inventory, child.Name)
                    end
                end
            end

            -- Check backpack for tools
            if player.Backpack then
                for _, child in ipairs(player.Backpack:GetChildren()) do
                    if child:IsA("Tool") then
                        table.insert(inventory, child.Name)
                    end
                end
            end

            local inventoryMessage
            if #inventory > 0 then
                inventoryMessage = player.Name .. "'s Inventory:\n- " .. table.concat(inventory, "\n- ")
            else
                inventoryMessage = player.Name .. " has no tools in their inventory."
            end

            -- Send to all active webhooks
            if Webhooks.Hook1Allowed and Webhooks.Hook1 ~= "" then
                sendDiscordWebhook(Webhooks.Hook1, inventoryMessage)
            end
            if Webhooks.Hook2Allowed and Webhooks.Hook2 ~= "" then
                sendDiscordWebhook(Webhooks.Hook2, inventoryMessage)
            end
            if Webhooks.Hook3Allowed and Webhooks.Hook3 ~= "" then
                sendDiscordWebhook(Webhooks.Hook3, inventoryMessage)
            end
            if Webhooks.Hook4Allowed and Webhooks.Hook4 ~= "" then
                sendDiscordWebhook(Webhooks.Hook4, inventoryMessage)
            end
            
            general:Chat("Inventory sent to active webhooks!")
        end,
    },
}

local compiled = compileCommands(commands)

-- Window
local Window = Library:CreateWindow({
	Title = "Vyrn Fruit Bot",
	Footer = "version: idk mate why do you look here",
    Center = true,
	NotifySide = "Right",
	ShowCustomCursor = true,
    AutoShow = true,
    Resizable = false,
})

local Tabs = {
    Collection = Window:AddTab("Collection", "settings"),
    Webhook = Window:AddTab("Webhooks", "settings"),
    Chat = Window:AddTab("Chat Commands", "settings"),
}

local Boxes = {
    Webhook = {
        Hook1 = Tabs.Webhook:AddLeftGroupbox("Webhook 1", "wrench"),
        Hook2 = Tabs.Webhook:AddRightGroupbox("Webhook 2", "wrench"),
        Hook3 = Tabs.Webhook:AddLeftGroupbox("Webhook 3", "wrench"),
        Hook4 = Tabs.Webhook:AddRightGroupbox("Webhook 4", "wrench"),
    },
    Settings = {
        Speed = Tabs.Collection:AddLeftGroupbox("Settings", "wrench"),
    },
    RarityFilters = Tabs.Collection:AddRightGroupbox("Fruit Rarity Filters", "filter") -- New Rarity Filters Groupbox
}

local Webhooks = {
    Hook1 = "",
    Hook1Allowed = false,
    Hook2 = "",
    Hook2Allowed = false,
    Hook3 = "",
    Hook3Allowed = false,
    Hook4 = "",
    Hook4Allowed = false,
}

local Toggles = {
    WebhookAllow1 = Boxes.Webhook.Hook1:AddToggle("Allow Sending", {Text = "Allow Sending",Default = false,}),
    WebhookAllow2 = Boxes.Webhook.Hook2:AddToggle("Allow Sending", {Text = "Allow Sending",Default = false,}),
    WebhookAllow3 = Boxes.Webhook.Hook3:AddToggle("Allow Sending", {Text = "Allow Sending",Default = false,}),
    WebhookAllow4 = Boxes.Webhook.Hook4:AddToggle("Allow Sending", {Text = "Allow Sending",Default = false,}),

    -- New Rarity Filter Toggles
}

local SpeedSlider = Boxes.Settings.Speed:AddSlider("Speed", {
    Text = "Speed",
    Default = speed,
    Min = 0,
    Max = 350,
    Rounding = 0,
})

-- UI Init
Boxes.Webhook.Hook1:AddInput("Webhook URL", {
    Callback = function(Value)
		Webhooks.Hook1 = Value
	end,
})
Boxes.Webhook.Hook2:AddInput("Webhook URL", {
    Callback = function(Value)
		Webhooks.Hook2 = Value
	end,
})
Boxes.Webhook.Hook3:AddInput("Webhook URL", {
    Callback = function(Value)
		Webhooks.Hook3 = Value
	end,
})
Boxes.Webhook.Hook4:AddInput("Webhook URL", {
    Callback = function(Value)
		Webhooks.Hook4 = Value
	end,
})

-- Callbacks
Toggles.WebhookAllow1:OnChanged(function(state)
    Webhooks.Hook1Allowed = state
end)
Toggles.WebhookAllow2:OnChanged(function(state)
    Webhooks.Hook2Allowed = state
end)
Toggles.WebhookAllow3:OnChanged(function(state)
    Webhooks.Hook3Allowed = state
end)
Toggles.WebhookAllow4:OnChanged(function(state)
    Webhooks.Hook4Allowed = state
end)

-- Rarity Filter Callbacks

SpeedSlider:OnChanged(function(value)
    speed = value
end)

-- Functions
local function findCommand(input)
    for _, command in ipairs(compiled) do
        local captures = {input:match(command.pattern)}

        if #captures > 0 then
            local args = {}

            for i, variable in ipairs(command.variables) do
                args[variable] = captures[i]
            end

            command.callback(args)

            return true
        end
    end

    return false
end

local function FindBasePart(item)
    if not item then
        return nil
    end

    if item:IsA("BasePart") then
        return item
    end

    return item:FindFirstChildWhichIsA("BasePart", true)
end

local function sendDiscordWebhook(url, message)
    if not url or url == "" then return end

    local data = HttpService:JSONEncode({
        content = message,
    })

    pcall(function()
        game:HttpGet(url, true, "POST", data)
    end)
end

-- New function to determine fruit rarity
local function getFruitRarity(fruitObject)
    -- Check for a StringValue named "Rarity" inside the fruit object
    local rarityValue = fruitObject:FindFirstChild("Rarity")
    if rarityValue and rarityValue:IsA("StringValue") then
        local rarityString = rarityValue.Value
        -- Normalize the rarity string to match our categories
        local knownRarities = {"Common", "Uncommon", "Rare", "Legendary", "Mythic"}
        for _, knownRarity in ipairs(knownRarities) do
            if rarityString == knownRarity then
                return rarityString
            end
        end
    end
    -- If no "Rarity" StringValue or it's not a known rarity, default to "Unknown"
    return "Unknown"
end

local function CollectItem(item)
    if not item then return false end
    
    local playerChar = Players.LocalPlayer.Character
    if not playerChar or not playerChar:FindFirstChild("HumanoidRootPart") then return false end

    local collected = false

    if item:IsA("Tool") then
        local handle = item:FindFirstChild("Handle")
        if handle then
            handle.CFrame = playerChar.HumanoidRootPart.CFrame
            task.wait(0.1)
            if not item:IsDescendantOf(workspace) then
                collected = true
            end
        end
    elseif item:IsA("Model") and (item.Name:lower():find("fruit", 1, true)) then -- Changed to use find for "fruit"
        local basePart = FindBasePart(item)
        if basePart then
            if tween(CFrame.new(basePart.Position + Vector3.new(0, 3, 0)), speed) then
                task.wait(0.1) -- Give time for collection to register
                if not item:IsDescendantOf(workspace) then
                    collected = true
                end
            end
        end
    end

    if collected then
        -- Send webhooks if enabled
        local fruitName = item.Name
        local collectionMessage = Players.LocalPlayer.Name .. " collected a " .. fruitName .. "!"
        if Webhooks.Hook1Allowed and Webhooks.Hook1 ~= "" then
            sendDiscordWebhook(Webhooks.Hook1, collectionMessage)
        end
        if Webhooks.Hook2Allowed and Webhooks.Hook2 ~= "" then
            sendDiscordWebhook(Webhooks.Hook2, collectionMessage)
        end
        if Webhooks.Hook3Allowed and Webhooks.Hook3 ~= "" then
            sendDiscordWebhook(Webhooks.Hook3, collectionMessage)
        end
        if Webhooks.Hook4Allowed and Webhooks.Hook4 ~= "" then
            sendDiscordWebhook(Webhooks.Hook4, collectionMessage)
        end
    end

    return collected
end

local function listenToChat(callback)
    Players.PlayerAdded:Connect(function(player)
        player.Chatted:Connect(function(message)
            callback({
                username = player.Name,
                displayName = player.DisplayName,
                message = message,
                player = player,
            })
        end)
    end)

    for _, player in ipairs(Players:GetPlayers()) do
        player.Chatted:Connect(function(message)
            callback({
                username = player.Name,
                displayName = player.DisplayName,
                message = message,
                player = player,
            })
        end)
    end
end
-- Init
local function chatCallback(args)
    local command = args.message
    command = command:gsub(" me ", " " ..args.username.. " ")
    findCommand(command)
end

local function StartFruits()
    while task.wait(0.1) do
        RS.Remotes.CommF_:InvokeServer("Cousin", "Buy")
        
        if not collecting and enabled and not disableOverride then
            pcall(function()
                local collected = false
                
                -- Check for Tool-type fruits first
                for _, v in ipairs(workspace:GetChildren()) do
                    if v:IsA("Tool") and v.Name:find("fruit", 1, true) then

                        collecting = true
                        if CollectItem(v) then
                            collected = true
                        end
                        collecting = false
                        if collected then break end -- Break if collected successfully
                    end
                end
                
                -- If not collected as a Tool, check for Model-type fruits
                if not collected then
                    for _, v in ipairs(workspace:GetChildren()) do
                        if v:IsA("Model") and (v.Name:lower():find("fruit", 1, true)) then

                            collecting = true
                            if CollectItem(v) then
                                collected = true
                            end
                            collecting = false
                            if collected then break end -- Break if collected successfully
                        end
                    end
                end
            end)
        end
    end
end

local function StartChests()
    while task.wait(0.1) do
        if collecting or not enabled or disableOverride then 
            task.wait(0.5)
            continue 
        end
        
        pcall(function()
            local playerChar = Players.LocalPlayer.Character
            if not playerChar or not playerChar.PrimaryPart then return end
            
            for _,v in pairs(workspace:GetDescendants()) do
                if string.find(v.Name, "Chest") and v:IsA("BasePart") then -- Only tween to BaseParts, not TouchTransmitters
                    print("Attempting to collect chest:", v.Parent.Name)
                    -- Calculate a CFrame slightly above the chest
                    local chestCFrame = CFrame.new(v.Position + Vector3.new(0, 3, 0))
                    
                    if tween(chestCFrame, speed) then
                        task.wait(0.2) -- Stay at the chest for a moment to trigger collection
                    end
                end
            end
        end)
    end
end

local function Start()
    local player = Players.LocalPlayer
    
    player.Idled:Connect(function()
        VirtualUser:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
        task.wait(1)
        VirtualUser:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
    end)    
    task.spawn(StartChests)
    task.spawn(StartFruits)
end

-- Call the Start function to begin
Start()
listenToChat(chatCallback)
