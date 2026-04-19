local SmartMovementAI = {}

--// SERVICES
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

--// CONFIG
local MAX_JUMPS = 12
local DASH_DISTANCE = 30
local DASH_COOLDOWN = 1.2

local NODE_SPACING = 30
local GRID_RADIUS = 120
local SAFE_RADIUS = 50

local ENGAGE_DISTANCE = 18
local RETREAT_DISTANCE = 10

local SAFE_HP_THRESHOLD = 0.25

local COSTS = {
    walk = 3,
    dash = 0.2,
    jump = 25
}

--// NODE STORAGE
local nodes = {}

--// REQUIRED INPUT FUNCTION
-- function fireKey(key, isDown) end

--// UTILS
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

--// DASH CHECK (AIR ENABLED)
local function canDash(a, b)
    return (b - a).Magnitude <= DASH_DISTANCE and clearLine(a, b)
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

--// GRAPH CONNECT
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

--// SAFE POINT (within 50 studs)
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
            local cost = COSTS[e.type]

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
            local newCost = (g[ck] or math.huge) + cost

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

--// CORE AI
function SmartMovementAI.Start(character, fireKey, getEnemy)
    local humanoid = character:WaitForChild("Humanoid")
    local root = character:WaitForChild("HumanoidRootPart")

    local tool = character:FindFirstChildOfClass("Tool")

    local lastDash = 0

    RunService.Heartbeat:Connect(function()
        local enemy = getEnemy()
        if not enemy then return end

        local enemyRoot = enemy:FindFirstChild("HumanoidRootPart")
        if not enemyRoot then return end

        local hp = humanoid.Health / humanoid.MaxHealth
        local dist = (enemyRoot.Position - root.Position).Magnitude

        --// SAFE MODE
        if hp < SAFE_HP_THRESHOLD then
            local safe = getHighestNearby(root.Position)
            local dir = (safe - root.Position).Unit

            fireKey("W", true)
            root.AssemblyLinearVelocity = dir * 50
            return
        end

        --// COMBAT BEHAVIOR (ENGAGE / RETREAT LOOP)

        local dirToEnemy = (enemyRoot.Position - root.Position).Unit

        -- ENGAGE DASH IN
        if dist > ENGAGE_DISTANCE and dist < 40 and tick() - lastDash > DASH_COOLDOWN then
            fireKey("Q") -- dash in
            root.AssemblyLinearVelocity = dirToEnemy * 120
            lastDash = tick()

            -- attack on impact
            if tool then
                tool:Activate()
            end
        end

        -- MELEE PRESSURE
        if dist < 12 then
            fireKey("Space") -- jump pressure
            if tool then
                tool:Activate()
            end
        end

        -- RETREAT DASH BACK
        if dist < RETREAT_DISTANCE then
            local back = -dirToEnemy
            if tick() - lastDash > DASH_COOLDOWN then
                fireKey("Q")
                root.AssemblyLinearVelocity = back * 100
                lastDash = tick()
            end
        end

        --// PATH SYSTEM (still used for movement logic)
        generateNodes(root.Position)
        connectNodes()

        local start = closest(root.Position)
        local goal = closest(enemyRoot.Position)
        if not start or not goal then return end

        local path = findPath(start, goal)
        if not path or not path[1] then return end

        local step = path[1]
        local moveDir = (step.node.position - root.Position)
        if moveDir.Magnitude > 0 then moveDir = moveDir.Unit end

        root.AssemblyLinearVelocity =
            Vector3.new(moveDir.X * 60, root.AssemblyLinearVelocity.Y, moveDir.Z * 60)
    end)
end

return SmartMovementAI
