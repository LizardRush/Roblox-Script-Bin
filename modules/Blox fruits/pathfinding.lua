local SmartMovementAI = {}

--// SERVICES
local RunService = game:GetService("RunService")
local VIM = game:GetService("VirtualInputManager")

--// ========================
--// LOCAL FLAGS (ENV STYLE)
--// ========================
getgenv().SmartAI.BetaFlags = {
    UsePathfinding = true,
    UseAbilities = false,   -- Z X C V
    UseParkour = true,     -- Q Space
    UseSafeMode = true
}

SmartMovementAI.Flags = Flags
--// CONFIG
local DASH_COOLDOWN = 1.2
local SAFE_RADIUS = 50

local SAFE_HP_THRESHOLD = 0.25
local RETREAT_HP_THRESHOLD = 0.40
local REENGAGE_HP_THRESHOLD = 0.75

local TARGET_DISTANCE = 8
local RETREAT_DISTANCE = 20

--// STATE
local nodes = {}

--// INPUT
local function fireKey(key, isDown)
    VIM:SendKeyEvent(isDown ~= false, key, false, game)
end

--// NODE GEN
local function generateNodes(center)
    nodes = {}

    for x = -60, 60, 30 do
        for z = -60, 60, 30 do
            local pos = center + Vector3.new(x, 50, z)
            local ray = workspace:Raycast(pos, Vector3.new(0, -100, 0))
            if ray then
                table.insert(nodes, ray.Position)
            end
        end
    end
end

local function getClosestNode(pos)
    local best, dist = nil, math.huge
    for _, n in ipairs(nodes) do
        local d = (n - pos).Magnitude
        if d < dist then
            best, dist = n, d
        end
    end
    return best
end

--// SAFE POINT
local function getHighestNearby(origin)
    local best = origin
    local bestY = -math.huge

    for _, n in ipairs(nodes) do
        local dist = (n - origin).Magnitude
        if dist <= SAFE_RADIUS and n.Y > bestY then
            bestY = n.Y
            best = n
        end
    end

    return best
end

--// MAIN
function SmartMovementAI.Start(character, targetGetter)
    local humanoid = character:WaitForChild("Humanoid")
    local root = character:WaitForChild("HumanoidRootPart")

    local tool = character:FindFirstChildOfClass("Tool")

    local lastDash = 0
    local inSafeMode = false
    local safeTarget = nil
    local retreating = false

    fireKey("W", true)

    RunService.Heartbeat:Connect(function()
        local enemy = targetGetter()
        if not enemy then return end

        local enemyRoot = enemy:FindFirstChild("HumanoidRootPart")
        if not enemyRoot then return end

        local hp = humanoid.Health / humanoid.MaxHealth
        local dist = (enemyRoot.Position - root.Position).Magnitude

        local dir = (enemyRoot.Position - root.Position)
        if dir.Magnitude > 0 then dir = dir.Unit end

        --// SAFE MODE
        if Flags.UseSafeMode and hp < SAFE_HP_THRESHOLD then
            if not inSafeMode then
                generateNodes(root.Position)
                safeTarget = getHighestNearby(root.Position)
                inSafeMode = true
            end

            local move = (safeTarget - root.Position)
            if move.Magnitude > 0 then move = move.Unit end

            root.AssemblyLinearVelocity =
                Vector3.new(move.X * 50, root.AssemblyLinearVelocity.Y, move.Z * 50)

            if hp >= 1 then
                inSafeMode = false
                safeTarget = nil
            end

            return
        end

        inSafeMode = false

        --// RETREAT LOGIC
        if hp < RETREAT_HP_THRESHOLD then
            retreating = true
        elseif hp >= REENGAGE_HP_THRESHOLD then
            retreating = false
        end

        local desiredDir

        if retreating then
            if dist < RETREAT_DISTANCE then
                desiredDir = -dir
            else
                desiredDir = Vector3.zero
            end
        else
            if dist > TARGET_DISTANCE then
                desiredDir = dir
            else
                desiredDir = Vector3.zero
            end
        end

        --// MOVEMENT
        if desiredDir.Magnitude > 0 then
            root.AssemblyLinearVelocity =
                Vector3.new(desiredDir.X * 60, root.AssemblyLinearVelocity.Y, desiredDir.Z * 60)
        end

        --// PARKOUR (Q / SPACE)
        if Flags.UseParkour then
            if dist > 10 and dist < 40 and tick() - lastDash > DASH_COOLDOWN then
                fireKey("Q", true)
                root.AssemblyLinearVelocity = dir * 120
                lastDash = tick()
            end

            if dist < 10 then
                fireKey("Space", true)
            end
        end

        --// ABILITIES (Z / X / C / V)
        if Flags.UseAbilities and not retreating then
            -- Not implimented
        end

        --// PATHFINDING (optional assist)
        if Flags.UsePathfinding then
            generateNodes(root.Position)
            local node = getClosestNode(enemyRoot.Position)

            if node then
                local moveDir = (node - root.Position)
                if moveDir.Magnitude > 0 then
                    moveDir = moveDir.Unit
                    root.AssemblyLinearVelocity =
                        Vector3.new(moveDir.X * 60, root.AssemblyLinearVelocity.Y, moveDir.Z * 60)
                end
            end
        end
    end)
end

return SmartMovementAI
