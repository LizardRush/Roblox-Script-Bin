
--[[
    Blox Fruits Exploit + Discord Bot Controller
    Based on open source BF script patterns (Redz, Hoho, etc.)
    Prefix: !
    Compatible with: Synapse X, KRNL, Fluxus, Delta, Solara, Xeno
]]

-- Executor API Detection
local http_request = syn and syn.request or http and http.request or request or fluxus and fluxus.request
local WebSocket = syn and syn.websocket or WebSocket or getgenv().WebSocket
local queue_on_teleport = syn and syn.queue_on_teleport or queue_on_teleport or function() end

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")

-- Game References (Standard BF Structure)
local CommF_ = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CommF_")
local Player = Players.LocalPlayer
local Character = Player.Character or Player.CharacterAdded:Wait()
local Humanoid = Character:WaitForChild("Humanoid")
local HRP = Character:WaitForChild("HumanoidRootPart")

-- CONFIG
local CONFIG = {
    DiscordBotToken = "YOUR_BOT_TOKEN",      -- Bot token
    DiscordChannelId = "YOUR_CHANNEL_ID",    -- Channel ID
    Prefix = "!",                              -- Changed from / to !
    TargetLevel = 50,
    FarmSpeed = 350,
    AttackCooldown = 0.15,
    QuestRetryDelay = 1,
    FruitRollCost = 300000,                    -- 300k per roll
    WebhookUrl = nil                           -- Optional webhook
}

-- State
local State = {
    Running = false,
    Mode = "LEVEL",       -- LEVEL, FRUIT_CHEST, IDLE
    CurrentQuest = nil,
    CurrentEnemy = nil,
    Inventory = {},
    Stats = {
        StartTime = os.time(),
        Kills = 0,
        Chests = 0,
        FruitsRolled = 0
    },
    WebSocket = nil
}

-- Utility Functions
local function notify(title, text)
    game:GetService("StarterGui"):SetCore("SendNotification", {
        Title = title,
        Text = text,
        Duration = 3
    })
end

local function sendDiscord(content, embed)
    if CONFIG.WebhookUrl then
        local data = {content = content, embeds = embed and {embed} or nil}
        pcall(function()
            http_request({
                Url = CONFIG.WebhookUrl,
                Method = "POST",
                Headers = {["Content-Type"] = "application/json"},
                Body = HttpService:JSONEncode(data)
            })
        end)
    end
    
    -- Also send via bot if token available
    if not CONFIG.DiscordBotToken:find("YOUR_") then
        local data = {content = content, embeds = embed and {embed} or nil}
        pcall(function()
            http_request({
                Url = "https://discord.com/api/v10/channels/" .. CONFIG.DiscordChannelId .. "/messages",
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json",
                    ["Authorization"] = "Bot " .. CONFIG.DiscordBotToken
                },
                Body = HttpService:JSONEncode(data)
            })
        end)
    end
end

-- Game Functions (Based on open source BF scripts)
local function getLevel()
    return Player.Data.Level.Value
end

local function getMoney()
    return Player.Data.Beli.Value
end

local function getFragments()
    return Player.Data.Fragments.Value
end

local function getCurrentSea()
    -- Detect current sea based on level or location
    local level = getLevel()
    if level < 700 then return 1 end
    if level < 1500 then return 2 end
    return 3
end

local function getQuestData()
    -- Standard BF quest check
    local success, result = pcall(function()
        return CommF_:InvokeServer("GetQuests")
    end)
    if success then return result end
    return nil
end

local function checkQuest()
    -- Check if quest is active and valid
    local questData = getQuestData()
    if questData then
        for _, quest in pairs(questData) do
            if quest.Active then
                return quest
            end
        end
    end
    return nil
end

local function getEnemyForQuest(questName)
    -- Find enemy matching quest in Enemies folder
    for _, enemy in pairs(Workspace.Enemies:GetChildren()) do
        if enemy:FindFirstChild("Humanoid") and enemy.Humanoid.Health > 0 then
            -- Match enemy name to quest target
            if questName:find(enemy.Name) or enemy.Name:find(questName) then
                return enemy
            end
        end
    end
    return nil
end

local function getAnyEnemy()
    -- Get nearest enemy for farming
    local nearest, dist = nil, math.huge
    for _, enemy in pairs(Workspace.Enemies:GetChildren()) do
        if enemy:FindFirstChild("Humanoid") and enemy.Humanoid.Health > 0 
           and enemy:FindFirstChild("HumanoidRootPart") then
            local d = (enemy.HumanoidRootPart.Position - HRP.Position).Magnitude
            if d < dist then
                dist = d
                nearest = enemy
            end
        end
    end
    return nearest
end

local function acceptQuestForLevel()
    -- Auto accept quest based on level (simplified)
    local level = getLevel()
    local questNPC = nil
    
    -- Determine quest NPC based on level ranges (simplified logic)
    if level < 10 then questNPC = "BanditQuest1"
    elseif level < 20 then questNPC = "BanditQuest2"
    elseif level < 30 then questNPC = "MonkeyQuest1"
    elseif level < 40 then questNPC = "GorillaQuest1"
    elseif level < 50 then questNPC = "PirateQuest1"
    else questNPC = "DesertQuest1"
    end
    
    pcall(function()
        CommF_:InvokeServer("StartQuest", questNPC, 1)
    end)
    
    task.wait(0.5)
    return checkQuest()
end

local function bringMob(enemy)
    -- Open source "bring mob" technique
    if enemy and enemy:FindFirstChild("HumanoidRootPart") then
        local targetPos = HRP.Position + Vector3.new(0, 0, 5)
        enemy.HumanoidRootPart.CFrame = CFrame.new(targetPos)
        enemy.HumanoidRootPart.Anchored = true
        task.wait(0.1)
        enemy.HumanoidRootPart.Anchored = false
    end
end

local function attack()
    -- Fast attack method from open source scripts
    VirtualUser:CaptureController()
    VirtualUser:Button1Down(Vector2.new(1280, 672))
    task.wait(CONFIG.AttackCooldown)
    VirtualUser:Button1Up(Vector2.new(1280, 672))
end

local function tweenTo(pos, speed)
    local distance = (pos - HRP.Position).Magnitude
    local time = distance / (speed or CONFIG.FarmSpeed)
    local tween = TweenService:Create(HRP, TweenInfo.new(time, Enum.EasingStyle.Linear), {
        CFrame = CFrame.new(pos)
    })
    tween:Play()
    tween.Completed:Wait()
end

-- Auto Farm Logic (Based on open source patterns)
local function farmLevel()
    while State.Running and State.Mode == "LEVEL" and getLevel() < CONFIG.TargetLevel do
        -- Check/accept quest
        local quest = checkQuest()
        if not quest then
            quest = acceptQuestForLevel()
            task.wait(CONFIG.QuestRetryDelay)
        end
        
        -- Find target enemy
        local enemy = nil
        if quest then
            enemy = getEnemyForQuest(quest.Name or quest.Target)
        end
        
        -- Fallback to any enemy
        if not enemy then
            enemy = getAnyEnemy()
        end
        
        if enemy and enemy:FindFirstChild("HumanoidRootPart") then
            State.CurrentEnemy = enemy
            
            -- Tween to enemy
            tweenTo(enemy.HumanoidRootPart.Position + Vector3.new(0, 5, 0))
            
            -- Attack loop
            while enemy.Humanoid and enemy.Humanoid.Health > 0 
                  and State.Running and State.Mode == "LEVEL" do
                -- Bring mob to player (anti-knockback)
                bringMob(enemy)
                
                -- Position above enemy
                HRP.CFrame = enemy.HumanoidRootPart.CFrame * CFrame.new(0, 5, 0)
                
                -- Attack
                attack()
                
                task.wait()
            end
            
            State.Stats.Kills = State.Stats.Kills + 1
            
            -- Progress update every 5 kills
            if State.Stats.Kills % 5 == 0 then
                sendDiscord(string.format("Level: %d/%d | Kills: %d | Beli: %d",
                    getLevel(), CONFIG.TargetLevel, State.Stats.Kills, getMoney()))
            end
        else
            -- No enemy found, wait
            task.wait(1)
        end
    end
    
    -- Switch to fruit/chest mode
    if getLevel() >= CONFIG.TargetLevel then
        State.Mode = "FRUIT_CHEST"
        sendDiscord("**Target Reached!** Level 50 achieved! Switching to fruit rolling + chest farming mode.")
    end
end

-- Chest Farm
local function getNearestChest()
    local nearest, dist = nil, math.huge
    for _, obj in pairs(Workspace:GetChildren()) do
        if obj.Name:find("Chest") and obj:FindFirstChild("TouchInterest") then
            local d = (obj.Position - HRP.Position).Magnitude
            if d < dist then
                dist = d
                nearest = obj
            end
        end
    end
    return nearest
end

local function farmChest()
    local chest = getNearestChest()
    if chest then
        tweenTo(chest.Position, 500)
        firetouchinterest(HRP, chest, 0)
        firetouchinterest(HRP, chest, 1)
        State.Stats.Chests = State.Stats.Chests + 1
        return true
    end
    return false
end

-- Fruit Rolling
local function rollFruit()
    if getMoney() < CONFIG.FruitRollCost then return false end
    
    -- Teleport to fruit dealer (simplified - adjust for your sea)
    local dealer = Workspace:FindFirstChild("FruitDealer") 
                  or Workspace:FindFirstChild("AdvancedFruitDealer")
    
    if dealer then
        tweenTo(dealer.Position + Vector3.new(0, 5, 0), 500)
        task.wait(0.5)
        
        -- Invoke roll
        pcall(function()
            CommF_:InvokeServer("GetFruits")
            CommF_:InvokeServer("PurchaseRawFruit", "Random")
        end)
        
        State.Stats.FruitsRolled = State.Stats.FruitsRolled + 1
        return true
    end
    return false
end

local function fruitAndChestLoop()
    while State.Running and State.Mode == "FRUIT_CHEST" do
        -- Roll fruit if we have money
        if getMoney() >= CONFIG.FruitRollCost then
            rollFruit()
            sendDiscord(string.format("Rolled fruit! Money: %d | Fruits rolled: %d", 
                getMoney(), State.Stats.FruitsRolled))
            task.wait(3)
        end
        
        -- Farm chests
        farmChest()
        task.wait(0.1)
    end
end

-- Inventory System
local function scanInventory()
    local fruits = {}
    
    -- Check backpack
    for _, tool in pairs(Player.Backpack:GetChildren()) do
        if tool:IsA("Tool") then
            if tool:FindFirstChild("Fruit") or 
               tool.Name:find("Fruit") or
               tool.Name:find("Blox") then
                table.insert(fruits, {
                    name = tool.Name,
                    location = "Backpack"
                })
            end
        end
    end
    
    -- Check character
    for _, tool in pairs(Character:GetChildren()) do
        if tool:IsA("Tool") then
            if tool:FindFirstChild("Fruit") or 
               tool.Name:find("Fruit") or
               tool.Name:find("Blox") then
                table.insert(fruits, {
                    name = tool.Name,
                    location = "Equipped"
                })
            end
        end
    end
    
    State.Inventory = fruits
    return fruits
end

-- Give Function
local function giveFruit(fruitName, amount, targetUsername)
    -- Find target player
    local target = Players:FindFirstChild(targetUsername)
    if not target then
        return "who?"
    end
    
    -- Find fruit in inventory
    local fruitTool = nil
    for _, tool in pairs(Player.Backpack:GetChildren()) do
        if tool:IsA("Tool") and tool.Name:lower():find(fruitName:lower()) then
            fruitTool = tool
            break
        end
    end
    
    if not fruitTool then
        return "Fruit '" .. fruitName .. "' not found in inventory!"
    end
    
    -- Drop fruit near player
    local targetChar = target.Character
    if targetChar and targetChar:FindFirstChild("HumanoidRootPart") then
        -- Teleport to target
        tweenTo(targetChar.HumanoidRootPart.Position + Vector3.new(0, 3, 0), 500)
        
        -- Attempt drop (method varies by game version)
        pcall(function()
            -- Try to drop using remote
            CommF_:InvokeServer("DropFruit", fruitTool.Name)
        end)
        
        -- Also try physical drop
        fruitTool.Parent = Workspace
        fruitTool.Handle.CFrame = targetChar.HumanoidRootPart.CFrame
        
        return string.format("Dropped %s x%d near %s!", fruitName, amount, targetUsername)
    end
    
    return "Target not spawned!"
end

-- Discord Commands (Now using ! prefix)
local Commands = {
    ["start"] = function(args, user)
        if State.Running then
            return "Already running! Current mode: " .. State.Mode
        end
        
        State.Running = true
        State.Mode = "LEVEL"
        State.Stats.StartTime = os.time()
        
        task.spawn(farmLevel)
        
        return string.format("**Farming Started!**\nTarget: Level %d\nCurrent: Level %d\nMode: Level Farming", 
            CONFIG.TargetLevel, getLevel())
    end,
    
    ["stop"] = function(args, user)
        State.Running = false
        State.Mode = "IDLE"
        return "**Farming Stopped!**\nSession Stats:\nKills: " .. State.Stats.Kills .. 
               "\nChests: " .. State.Stats.Chests .. 
               "\nFruits Rolled: " .. State.Stats.FruitsRolled
    end,
    
    ["inventory"] = function(args, user)
        local fruits = scanInventory()
        if #fruits == 0 then
            return "**Inventory Empty!**\nNo fruits found in backpack."
        end
        
        local list = ""
        for i, fruit in ipairs(fruits) do
            list = list .. string.format("%d. %s (%s)\n", i, fruit.name, fruit.location)
        end
        
        return string.format("**Fruit Inventory (%d items):**\n```\n%s```", #fruits, list)
    end,
    
    ["give"] = function(args, user)
        if #args < 3 then
            return "Usage: `!give [fruit] [amount] [username]`"
        end
        
        local fruitName = args[1]
        local amount = tonumber(args[2]) or 1
        local targetName = args[3]
        
        return giveFruit(fruitName, amount, targetName)
    end,
    
    ["status"] = function(args, user)
        local sessionTime = math.floor((os.time() - State.Stats.StartTime) / 60)
        return string.format(
            "**Status Report**\n```\nLevel: %d/%d\nMoney: %d\nFragments: %d\nMode: %s\nRunning: %s\nSession Time: %dm\n\nStats:\nKills: %d\nChests: %d\nFruits Rolled: %d\n```",
            getLevel(), CONFIG.TargetLevel, getMoney(), getFragments(),
            State.Mode, tostring(State.Running), sessionTime,
            State.Stats.Kills, State.Stats.Chests, State.Stats.FruitsRolled
        )
    end,
    
    ["roll"] = function(args, user)
        if rollFruit() then
            return "Rolled a fruit! Check inventory."
        else
            return "Not enough money! Need " .. CONFIG.FruitRollCost .. " beli."
        end
    end,
    
    ["chest"] = function(args, user)
        if farmChest() then
            return "Farmed a chest! Total: " .. State.Stats.Chests
        else
            return "No chests found nearby."
        end
    end,
    
    ["help"] = function(args, user)
        return [[**Available Commands:**
```
!start      - Begin auto farming (level → fruit/chest)
!stop       - Stop all farming
!inventory  - Show fruit inventory
!give [fruit] [amount] [username] - Give fruit to player
!status     - Show detailed status
!roll       - Roll a fruit manually
!chest      - Farm nearest chest manually
!help       - Show this message
```]]
    end
}

-- Discord Integration (WebSocket or Polling)
local function connectDiscord()
    if WebSocket and not CONFIG.DiscordBotToken:find("YOUR_") then
        -- WebSocket Mode
        local success, ws = pcall(function()
            return WebSocket.connect("wss://gateway.discord.gg/?v=10&encoding=json")
        end)
        
        if success and ws then
            State.WebSocket = ws
            
            ws.OnMessage:Connect(function(msg)
                local data = HttpService:JSONDecode(msg)
                
                -- Heartbeat handling
                if data.op == 10 then
                    local interval = data.d.heartbeat_interval / 1000
                    task.spawn(function()
                        while ws.State == Enum.WebSocketState.Open do
                            task.wait(interval * math.random(0.9, 1))
                            ws:Send(HttpService:JSONEncode({op = 1, d = nil}))
                        end
                    end)
                    
                    -- Identify
                    ws:Send(HttpService:JSONEncode({
                        op = 2,
                        d = {
                            token = CONFIG.DiscordBotToken,
                            intents = 512,
                            properties = {os = "linux", browser = "bf_bot", device = "bf_bot"}
                        }
                    }))
                end
                
                -- Handle messages
                if data.t == "MESSAGE_CREATE" and data.d then
                    local msgData = data.d
                    if msgData.content:sub(1, 1) == CONFIG.Prefix then
                        local args = {}
                        for arg in msgData.content:sub(2):gmatch("%S+") do
                            table.insert(args, arg)
                        end
                        
                        local cmd = table.remove(args, 1)
                        if Commands[cmd] then
                            local response = Commands[cmd](args, msgData.author.username)
                            
                            -- Reply
                            pcall(function()
                                http_request({
                                    Url = "https://discord.com/api/v10/channels/" .. msgData.channel_id .. "/messages",
                                    Method = "POST",
                                    Headers = {
                                        ["Content-Type"] = "application/json",
                                        ["Authorization"] = "Bot " .. CONFIG.DiscordBotToken
                                    },
                                    Body = HttpService:JSONEncode({
                                        content = response,
                                        message_reference = {message_id = msgData.id}
                                    })
                                })
                            end)
                        end
                    end
                end
            end)
            
            ws.OnClose:Connect(function()
                notify("Discord", "Disconnected! Reconnecting...")
                task.wait(5)
                connectDiscord()
            end)
            
            notify("Discord", "Connected via WebSocket!")
            return
        end
    end
    
    -- Polling Fallback
    notify("Discord", "Using polling mode (2s delay)")
    local lastMsgId = nil
    
    task.spawn(function()
        while true do
            if not CONFIG.DiscordBotToken:find("YOUR_") then
                pcall(function()
                    local url = "https://discord.com/api/v10/channels/" .. CONFIG.DiscordChannelId .. "/messages?limit=10"
                    local res = http_request({
                        Url = url,
                        Method = "GET",
                        Headers = {["Authorization"] = "Bot " .. CONFIG.DiscordBotToken}
                    })
                    
                    local messages = HttpService:JSONDecode(res.Body)
                    for i = #messages, 1, -1 do
                        local msg = messages[i]
                        if msg.content:sub(1, 1) == CONFIG.Prefix 
                           and msg.author.id ~= "YOUR_BOT_ID" 
                           and msg.id ~= lastMsgId then
                            lastMsgId = msg.id
                            
                            local args = {}
                            for arg in msg.content:sub(2):gmatch("%S+") do
                                table.insert(args, arg)
                            end
                            
                            local cmd = table.remove(args, 1)
                            if Commands[cmd] then
                                local response = Commands[cmd](args, msg.author.username)
                                sendDiscord(response)
                            end
                        end
                    end
                end)
            end
            task.wait(2)
        end
    end)
end

-- Character respawn handling
Player.CharacterAdded:Connect(function(char)
    Character = char
    Humanoid = char:WaitForChild("Humanoid")
    HRP = char:WaitForChild("HumanoidRootPart")
end)

-- Anti-AFK
Player.Idled:Connect(function()
    VirtualUser:Button2Down(Vector2.new(0,0), Workspace.CurrentCamera.CFrame)
    task.wait(1)
    VirtualUser:Button2Up(Vector2.new(0,0), Workspace.CurrentCamera.CFrame)
end)

-- Queue on teleport (reconnect)
queue_on_teleport([[
    -- Re-run script after teleport (optional)
]])

-- Initialize
task.spawn(connectDiscord)
notify("BF Bot", "Loaded! Use !start in Discord to begin.")

-- Keep alive
while true do task.wait(1) end
