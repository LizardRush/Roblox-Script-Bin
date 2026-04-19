local SmartMovementAI = {}

--// SERVICES
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local VirtualInputManager = game:GetService("VirtualInputManager")

--// CONFIG
local MAX_JUMPS = 12
local DASH_DISTANCE = 30
local DASH_COOLDOWN = 1.2

local NODE_SPACING = 30
local GRID_RADIUS = 120
local SAFE_RADIUS = 50

local SAFE_HP_THRESHOLD = 0.25

--// STATE
local nodes = {}

--// INPUT SYSTEM (FIXED)
local function fireKey(key, isDown)
    if isDown == false then
        VirtualInputManager:SendKeyEvent(false, key, false, game)
    else
        VirtualInputManager:SendKeyEvent(true, key, false, game)
    end
end

--// RAY
local function ray(a, b)
    return workspace:Raycast(a, b - a)
end

local function clearLine(a, b)
    return ray(a, b) == nil
end

local function needsJump(a, b)
    local hit = ray(a, b)
    return hit ~= nil or (b.Y - a.Y) > 4
end

--// NODE GEN
local function generateNodes(center)
    nodes = {}

    for x = -GRID_RADIUS, GRID_RADIUS, NODE_SPACING do
        for z = -GRID_RADIUS, GRID_RADIUS, NODE_SPACING do
            local origin = center + Vector3.new(x, 60, z)
            local res = ray(origin, Vector3.new(0, -120, 0))

            if res then
                table.insert(nodes, {
                    id = tostring(#nodes + 1),
                    position = res.Position,
                    neighbors = {},
                    isGround = true
                })
            end
        end
    end
end

--// CONNECT GRAPH
local function connectNodes()
    for _, a in ipairs(nodes) do
        for _, b in ipairs(nodes) do
            if a == b then continue end

            local dist = (a.position - b.position).Magnitude

            if dist <= DASH_DISTANCE and clearLine(a.position, b.position) then
                table.insert(a.neighbors, {node = b, type = "dash"})
                continue
            end

            if dist < 12 and not needsJump(a.position, b.position) then
                table.insert(a.neighbors, {node = b, type = "walk"})
            end

            if needsJump(a.position, b.position) then
                table.insert(a.neighbors, {node = b, type = "jump"})
            end
        end
    end
end

--// A*
local function heuristic(a, b)
    return (a.position - b.position).Magnitude / 60
end

local function key(node, j, d)
    return node.id .. "_" .. j .. "_" .. math.floor(d * 10)
end

local function closest(pos)
    local best, dist = nil, math.huge
    for _, n in ipairs(nodes) do
        local d = (n.position - pos).Magnitude
        if d < dist then
            best, dist = n, d
        end
    end
    return best
end

--// SAFE POINT (50 studs)
local function getHighestNearby(origin)
    local best = origin
    local bestY = -math.huge

    for _, n in ipairs(nodes) do
        local dist = (n.position - origin).Magnitude
        if dist <= SAFE_RADIUS then
            if n.position.Y > bestY then
                bestY = n.position.Y
                best = n.position
            end
        end
    end

    return best
end

--// PATHFIND
local function findPath(startNode, goalNode)
    local open, cameFrom, g, f = {}, {}, {}, {}

    local start = {
        node = startNode,
        jumpsLeft = MAX_JUMPS,
        dashReady = 0,
        time = 0
    }

    local sk = key(startNode, MAX_JUMPS, 0)
    g[sk] = 0
    f[sk] = heuristic(startNode, goalNode)

    table.insert(open, start)

    while #open > 0 do
        table.sort(open, function(a, b)
            return f[key(a.node, a.jumpsLeft, a.dashReady)] <
                   f[key(b.node, b.jumpsLeft, b.dashReady)]
        end)

        local cur = table.remove(open, 1)
        local ck = key(cur.node, cur.jumpsLeft, cur.dashReady)

        if cur.node == goalNode then
            local path = {}
            while cameFrom[ck] do
                table.insert(path, 1, cameFrom[ck].step)
                ck = cameFrom[ck].prev
            end
            return path
        end

        for _, e in ipairs(cur.node.neighbors) do
            local nj = cur.jumpsLeft
            local nt = cur.time
            local dr = cur.dashReady

            if e.type == "jump" then
                if nj <= 0 then continue end
                nj -= 1
                nt += 0.4

            elseif e.type == "dash" then
                if nt < dr then continue end
                dr = nt + DASH_COOLDOWN
                nt += 0.15

            else
                nt += 0.3
            end

            if e.node.isGround then
                nj = MAX_JUMPS
            end

            local nk = key(e.node, nj, dr)
            local newCost = (g[ck] or math.huge) + 1

            if not g[nk] or newCost < g[nk] then
                g[nk] = newCost
                f[nk] = newCost + heuristic(e.node, goalNode)

                cameFrom[nk] = {
                    prev = ck,
                    step = {node = e.node, type = e.type}
                }

                table.insert(open, {
                    node = e.node,
                    jumpsLeft = nj,
                    dashReady = dr,
                    time = nt
                })
            end
        end
    end

    return nil
end

--// MAIN AI
function SmartMovementAI.Start(character, targetGetter)
    local humanoid = character:WaitForChild("Humanoid")
    local root = character:WaitForChild("HumanoidRootPart")

    local tool = character:FindFirstChildOfClass("Tool")

    local lastDash = 0
    local inSafeMode = false
    local safeTarget = nil

    -- HOLD W ALWAYS INITIALLY
    fireKey("W", true)

    RunService.Heartbeat:Connect(function()
        local enemy = targetGetter()
        if not enemy then return end

        local enemyRoot = enemy:FindFirstChild("HumanoidRootPart")
        if not enemyRoot then return end

        local hp = humanoid.Health / humanoid.MaxHealth
        local dist = (enemyRoot.Position - root.Position).Magnitude
        local dirToEnemy = (enemyRoot.Position - root.Position)

        if dirToEnemy.Magnitude > 0 then
            dirToEnemy = dirToEnemy.Unit
        end

        --// SAFE MODE (WAIT UNTIL FULL HP)
        if hp < SAFE_HP_THRESHOLD then
            if not inSafeMode then
                safeTarget = getHighestNearby(root.Position)
                inSafeMode = true
            end

            local dir = (safeTarget - root.Position)
            if dir.Magnitude > 0 then dir = dir.Unit end

            root.AssemblyLinearVelocity = dir * 50

            if hp >= 1 then
                inSafeMode = false
                safeTarget = nil
            end

            return
        end

        inSafeMode = false

        --// COMBAT LOGIC

        -- DASH IN + ATTACK
        if dist < 40 and dist > 12 and tick() - lastDash > DASH_COOLDOWN then
            fireKey("Q", true)
            root.AssemblyLinearVelocity = dirToEnemy * 120
            lastDash = tick()

            if tool then tool:Activate() end
        end

        -- CLOSE RANGE PRESSURE
        if dist < 10 then
            fireKey("Space", true)
            if tool then tool:Activate() end
        end

        -- RETREAT DASH
        if dist < 8 then
            fireKey("Q", true)
            root.AssemblyLinearVelocity = (-dirToEnemy) * 100
        end

        --// PATH UPDATE
        generateNodes(root.Position)
        connectNodes()

        local start = closest(root.Position)
        local goal = closest(enemyRoot.Position)
        if not start or not goal then return end

        local path = findPath(start, goal)
        if not path or not path[1] then return end

        local step = path[1]
        local moveDir = (step.node.position - root.Position)

        if moveDir.Magnitude > 0 then
            moveDir = moveDir.Unit
        end

        root.AssemblyLinearVelocity =
            Vector3.new(moveDir.X * 60, root.AssemblyLinearVelocity.Y, moveDir.Z * 60)
    end)
end

return SmartMovementAI
