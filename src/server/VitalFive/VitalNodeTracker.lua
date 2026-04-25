local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local function safeWait(parent, name, timeout)
    if not parent then
        warn(("[VitalNodeTracker] safeWait: parent is nil for '%s'"):format(name))
        return nil
    end

    local ok, inst = pcall(function()
        return parent:WaitForChild(name, timeout)
    end)
    if not ok then
        warn(("[VitalNodeTracker] safeWait: WaitForChild('%s') errored"):format(name))
        return nil
    end
    if not inst then
        warn(("[VitalNodeTracker] safeWait: WaitForChild('%s') timed out"):format(name))
        return nil
    end

    return inst
end

local function safeRequire(inst, name)
    if not inst then
        warn(("[VitalNodeTracker] safeRequire: %s is nil"):format(name))
        return nil
    end

    local className = (inst.ClassName and tostring(inst.ClassName)) or "no ClassName"
    print(("DEBUG: safeRequire target %s -> ClassName=%s typeof=%s"):format(name, className, typeof(inst)))
    if className ~= "ModuleScript" then
        warn(("[VitalNodeTracker] safeRequire: %s is not a ModuleScript (ClassName=%s)"):format(name, className))
    end

    local ok, result = pcall(require, inst)
    if not ok then
        warn(("[VitalNodeTracker] safeRequire: require(%s) failed: %s"):format(name, tostring(result)))
        return nil
    end

    return result
end

local sharedFolder = safeWait(ReplicatedStorage, "Shared", 10)
local typesFolder = safeWait(sharedFolder, "Types", 10)
local constantsModule = safeWait(typesFolder, "constants", 5)

print(
    "DEBUG: module presence:",
    "Shared=", tostring(sharedFolder ~= nil),
    "Types=", tostring(typesFolder ~= nil),
    "constants=", tostring(constantsModule ~= nil)
)

local Constants = safeRequire(constantsModule, "constants")
if not Constants then
    error("[VitalNodeTracker] Constants failed to load")
end

local function dbg(...)
    if Constants.DEBUG then
        print("[VitalNodeTracker]", ...)
    end
end

local VitalNodeTracker = {}

local NODE_DEFINITIONS = {
    { name = "Elemental", bodyPart = "UpperTorso", offset = Vector3.new(0, 0.5, -0.3) },
    { name = "Movement", bodyPart = "LowerTorso", offset = Vector3.new(0, 0, -0.4) },
    { name = "Guard", bodyPart = "RightUpperArm", offset = Vector3.new(0, -0.5, 0) },
    { name = "Vision", bodyPart = "Head", offset = Vector3.new(0.3, 0.2, 0) },
    { name = "Chakra", bodyPart = "HumanoidRootPart", offset = Vector3.new(0, -0.5, 0) },
}

local NODE_HITBOX_SIZE = Vector3.new(0.5, 0.5, 0.5)
local EXPECTED_NODE_COUNT = 5

local characterNodes = {} -- [characterModel] = { [nodeName] = nodePart }
local playerConnections = {} -- [userId] = { characterAddedConn = RBXScriptConnection }
local characterDiedConnections = {} -- [characterModel] = RBXScriptConnection

local function cleanupCharacter(character)
    if not character then
        return
    end

    characterNodes[character] = nil

    local diedConn = characterDiedConnections[character]
    if diedConn then
        pcall(function()
            diedConn:Disconnect()
        end)
        characterDiedConnections[character] = nil
    end
end

local function attachNodesToCharacter(player, character)
    if not player or not character then
        return
    end

    cleanupCharacter(character)

    local rootPart
    local humanoid

    local rootOk = pcall(function()
        rootPart = character:WaitForChild("HumanoidRootPart", 5)
    end)
    local humOk = pcall(function()
        humanoid = character:WaitForChild("Humanoid", 5)
    end)

    if not rootOk or not rootPart or not humOk or not humanoid then
        dbg("failed to attach nodes for", player.Name, "- missing HumanoidRootPart or Humanoid")
        return
    end

    local nodes = {}
    for _, node in ipairs(NODE_DEFINITIONS) do
        local bodyPart
        local bodyPartOk = pcall(function()
            bodyPart = character:FindFirstChild(node.bodyPart)
        end)

        if not bodyPartOk or not bodyPart or not bodyPart:IsA("BasePart") then
            dbg("missing body part for node", node.name, "on", player.Name, "expected", node.bodyPart)
        else
            local nodePart = Instance.new("Part")
            nodePart.Name = "VitalNode_" .. node.name
            nodePart.Size = NODE_HITBOX_SIZE
            nodePart.CanCollide = false
            nodePart.CanQuery = true
            nodePart.CanTouch = false
            nodePart.Massless = true
            nodePart.Transparency = 1
            nodePart.Anchored = false
            nodePart.CFrame = CFrame.new(bodyPart.Position + bodyPart.CFrame:VectorToWorldSpace(node.offset))
            nodePart:SetAttribute("VitalNode", node.name)
            nodePart:SetAttribute("OwnerUserId", player.UserId)
            nodePart.Parent = character

            local weld = Instance.new("WeldConstraint")
            weld.Part0 = bodyPart
            weld.Part1 = nodePart
            weld.Parent = nodePart

            nodes[node.name] = nodePart
        end
    end

    characterNodes[character] = nodes

    local diedConn = humanoid.Died:Connect(function()
        cleanupCharacter(character)
    end)
    characterDiedConnections[character] = diedConn

    local attachedCount = 0
    for _ in pairs(nodes) do
        attachedCount = attachedCount + 1
    end
    dbg(("attached %d nodes to %s"):format(attachedCount, player.Name))
end

local function buildNodeQueryResult(part, originPosition, excludeCharacter)
    local nodeName = part:GetAttribute("VitalNode")
    if not nodeName then
        return nil
    end

    if excludeCharacter and part:IsDescendantOf(excludeCharacter) then
        return nil
    end

    local ownerUserId = part:GetAttribute("OwnerUserId")
    local owner = ownerUserId and Players:GetPlayerByUserId(ownerUserId) or nil
    if not owner then
        return nil
    end

    return {
        player = owner,
        nodeName = nodeName,
        position = part.Position,
        distance = (part.Position - originPosition).Magnitude,
    }
end

function VitalNodeTracker.GetNodesInBox(cframe, size, excludeCharacter)
    if typeof(cframe) ~= "CFrame" or typeof(size) ~= "Vector3" then
        return {}
    end

    local overlapParams = OverlapParams.new()
    overlapParams.FilterType = Enum.RaycastFilterType.Exclude
    overlapParams.FilterDescendantsInstances = excludeCharacter and { excludeCharacter } or {}
    overlapParams.MaxParts = 20

    local parts = Workspace:GetPartBoundsInBox(cframe, size, overlapParams)
    local results = {}

    for _, part in ipairs(parts) do
        local result = buildNodeQueryResult(part, cframe.Position, excludeCharacter)
        if result then
            table.insert(results, result)
        end
    end

    return results
end

function VitalNodeTracker.GetNodesInRadius(position, radius, excludeCharacter)
    if typeof(position) ~= "Vector3" or type(radius) ~= "number" then
        return {}
    end

    local overlapParams = OverlapParams.new()
    overlapParams.FilterType = Enum.RaycastFilterType.Exclude
    overlapParams.FilterDescendantsInstances = excludeCharacter and { excludeCharacter } or {}
    overlapParams.MaxParts = 20

    local parts = Workspace:GetPartBoundsInRadius(position, radius, overlapParams)
    local results = {}

    for _, part in ipairs(parts) do
        local result = buildNodeQueryResult(part, position, excludeCharacter)
        if result then
            table.insert(results, result)
        end
    end

    return results
end

function VitalNodeTracker.GetCharacterNodes(character)
    local nodes = characterNodes[character]
    if not nodes then
        return {}
    end
    return table.clone(nodes)
end

function VitalNodeTracker.HasNodes(character)
    local nodes = characterNodes[character]
    if not nodes then
        return false
    end

    for _, node in ipairs(NODE_DEFINITIONS) do
        local nodePart = nodes[node.name]
        if not nodePart or not nodePart.Parent then
            return false
        end
    end

    local count = 0
    for _ in pairs(nodes) do
        count = count + 1
    end
    return count == EXPECTED_NODE_COUNT
end

local function trackPlayer(player)
    if not player or not player:IsA("Player") then
        return
    end

    local userId = player.UserId
    local existing = playerConnections[userId]
    if existing and existing.characterAddedConn then
        pcall(function()
            existing.characterAddedConn:Disconnect()
        end)
    end

    local characterAddedConn = player.CharacterAdded:Connect(function(character)
        attachNodesToCharacter(player, character)
    end)

    playerConnections[userId] = {
        characterAddedConn = characterAddedConn,
    }

    if player.Character then
        attachNodesToCharacter(player, player.Character)
    end
end

local function untrackPlayer(player)
    if not player or not player:IsA("Player") then
        return
    end

    local userId = player.UserId
    local connections = playerConnections[userId]
    if connections and connections.characterAddedConn then
        pcall(function()
            connections.characterAddedConn:Disconnect()
        end)
    end
    playerConnections[userId] = nil

    local character = player.Character
    if character then
        cleanupCharacter(character)
    end
end

for _, player in ipairs(Players:GetPlayers()) do
    trackPlayer(player)
end

Players.PlayerAdded:Connect(trackPlayer)
Players.PlayerRemoving:Connect(untrackPlayer)

if Constants.DEBUG then
    task.spawn(function()
        task.wait(5)

        for _, player in ipairs(Players:GetPlayers()) do
            if player.Character then
                local has = VitalNodeTracker.HasNodes(player.Character)
                print(("[VitalNodeTracker self-test] %s has nodes: %s"):format(player.Name, tostring(has)))

                if has then
                    local nodes = VitalNodeTracker.GetCharacterNodes(player.Character)
                    local count = 0
                    for _ in pairs(nodes) do
                        count = count + 1
                    end
                    print(("[VitalNodeTracker self-test] %s has %d node parts"):format(player.Name, count))
                    assert(count == 5, "expected 5 nodes per character")
                end

                local rootPart = player.Character:FindFirstChild("HumanoidRootPart")
                if rootPart then
                    local nearby = VitalNodeTracker.GetNodesInBox(
                        rootPart.CFrame,
                        Vector3.new(10, 10, 10),
                        nil
                    )
                    print(("[VitalNodeTracker self-test] query returned %d nodes near %s"):format(#nearby, player.Name))
                    assert(#nearby >= 1, "expected at least 1 node queryable — system working")
                end
            end
        end

        print("[VitalNodeTracker self-test] PASSED")
    end)
end

print("✅ VitalNodeTracker initialized")

return VitalNodeTracker
