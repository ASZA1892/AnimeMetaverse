local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local function safeWait(parent, name, timeout)
    if not parent then
        warn(("[NodeHitDetection] safeWait: parent is nil for '%s'"):format(name))
        return nil
    end

    local ok, inst = pcall(function()
        return parent:WaitForChild(name, timeout)
    end)
    if not ok then
        warn(("[NodeHitDetection] safeWait: WaitForChild('%s') errored"):format(name))
        return nil
    end
    if not inst then
        warn(("[NodeHitDetection] safeWait: WaitForChild('%s') timed out"):format(name))
        return nil
    end

    return inst
end

local function safeRequire(inst, name)
    if not inst then
        warn(("[NodeHitDetection] safeRequire: %s is nil"):format(name))
        return nil
    end

    local className = (inst.ClassName and tostring(inst.ClassName)) or "no ClassName"
    print(("DEBUG: safeRequire target %s -> ClassName=%s typeof=%s"):format(name, className, typeof(inst)))
    if className ~= "ModuleScript" then
        warn(("[NodeHitDetection] safeRequire: %s is not a ModuleScript (ClassName=%s)"):format(name, className))
    end

    local ok, result = pcall(require, inst)
    if not ok then
        warn(("[NodeHitDetection] safeRequire: require(%s) failed: %s"):format(name, tostring(result)))
        return nil
    end

    return result
end

local sharedFolder = safeWait(ReplicatedStorage, "Shared", 10)
local typesFolder = safeWait(sharedFolder, "Types", 10)
local constantsModule = safeWait(typesFolder, "constants", 5)
local serverScriptService = game:GetService("ServerScriptService")
local vitalFiveFolder = safeWait(serverScriptService, "VitalFive", 10)
local vitalNodeTrackerModule = safeWait(vitalFiveFolder, "VitalNodeTracker", 5)

print(
    "DEBUG: module presence:",
    "Shared=", tostring(sharedFolder ~= nil),
    "Types=", tostring(typesFolder ~= nil),
    "constants=", tostring(constantsModule ~= nil),
    "VitalFive=", tostring(vitalFiveFolder ~= nil),
    "VitalNodeTracker=", tostring(vitalNodeTrackerModule ~= nil)
)

local Constants = safeRequire(constantsModule, "constants")
local VitalNodeTracker = safeRequire(vitalNodeTrackerModule, "VitalNodeTracker")

if not Constants then
    error("[NodeHitDetection] Constants failed to load")
end
if not VitalNodeTracker then
    error("[NodeHitDetection] VitalNodeTracker failed to load")
end

local function dbg(...)
    if Constants.DEBUG then
        print("[NodeHitDetection]", ...)
    end
end

local NodeHitDetection = {}

local NODE_HIT_COOLDOWN = 2.0
local ALL_NODE_NAMES = { "Elemental", "Movement", "Guard", "Vision", "Chakra" }

local lastNodeHitAt = setmetatable({}, { __mode = "k" })

local function buildEligibleSet(nodeNames)
    local set = {}
    for _, name in ipairs(nodeNames) do
        set[name] = true
    end
    return set
end

local function resolveTargetCharacter(target)
    if typeof(target) ~= "Instance" then
        return nil, nil
    end

    if target:IsA("Player") then
        return target.Character, target
    end

    if target:IsA("Model") and target:FindFirstChildOfClass("Humanoid") then
        return target, Players:GetPlayerFromCharacter(target)
    end

    return nil, nil
end

function NodeHitDetection.CheckHit(context)
    if type(context) ~= "table" then
        dbg("CheckHit rejected: context missing or invalid")
        return { hitNode = false }
    end

    local attacker = context.attacker
    if not (typeof(attacker) == "Instance" and attacker:IsA("Player")) then
        dbg("CheckHit rejected: attacker invalid")
        return { hitNode = false }
    end

    if context.target == nil then
        dbg("CheckHit rejected: target missing")
        return { hitNode = false }
    end

    if typeof(context.hitCFrame) ~= "CFrame" then
        dbg("CheckHit rejected: hitCFrame invalid")
        return { hitNode = false }
    end

    if typeof(context.hitboxSize) ~= "Vector3" then
        dbg("CheckHit rejected: hitboxSize invalid")
        return { hitNode = false }
    end

    local targetCharacter, targetPlayer = resolveTargetCharacter(context.target)
    if not targetCharacter then
        dbg("CheckHit rejected: target character unresolved")
        return { hitNode = false }
    end

    local targetRoot = targetCharacter:FindFirstChild("HumanoidRootPart")
    if not targetRoot then
        dbg("CheckHit rejected: target has no HumanoidRootPart")
        return { hitNode = false }
    end

    local now = os.clock()
    local last = lastNodeHitAt[attacker] or 0
    if (now - last) < NODE_HIT_COOLDOWN then
        dbg(("CheckHit rate-limited for %s: %.3f remaining"):format(attacker.Name, NODE_HIT_COOLDOWN - (now - last)))
        return { hitNode = false }
    end

    local eligible = context.vitalNodes
    if type(eligible) ~= "table" or #eligible == 0 then
        eligible = ALL_NODE_NAMES
    end
    local eligibleSet = buildEligibleSet(eligible)

    local attackerCharacter = attacker.Character
    local rawNodes = {}
    local okNodes, nodeResults = pcall(function()
        return VitalNodeTracker.GetNodesInBox(context.hitCFrame, context.hitboxSize, attackerCharacter)
    end)
    if not okNodes then
        dbg("CheckHit failed: VitalNodeTracker.GetNodesInBox errored", tostring(nodeResults))
        return { hitNode = false }
    end
    if type(nodeResults) == "table" then
        rawNodes = nodeResults
    end

    if #rawNodes == 0 then
        dbg("CheckHit: no nodes found in hitbox")
        return { hitNode = false }
    end

    local candidates = {}
    for _, node in ipairs(rawNodes) do
        local isEligibleName = node and eligibleSet[node.nodeName] == true
        if isEligibleName then
            local belongsToTarget = false
if targetPlayer then
    belongsToTarget = node.player == targetPlayer
elseif targetCharacter then
    belongsToTarget = node.player ~= nil
        and node.player.Character == targetCharacter
end

            if belongsToTarget then
                table.insert(candidates, node)
            else
                dbg("Filtered node: ownership mismatch", tostring(node.nodeName))
            end
        end
    end

    if #candidates == 0 then
        dbg("CheckHit: no eligible nodes after filters")
        return { hitNode = false }
    end

    table.sort(candidates, function(a, b)
        return (a.distance or math.huge) < (b.distance or math.huge)
    end)
    local winner = candidates[1]
    if not winner or type(winner.nodeName) ~= "string" then
        dbg("CheckHit: winner invalid")
        return { hitNode = false }
    end

    lastNodeHitAt[attacker] = now

    local result = {
        hitNode = true,
        nodeName = winner.nodeName,
        targetPlayer = targetPlayer,
        attackerTier = type(context.attackerTier) == "number" and context.attackerTier or 1,
        element = context.element,
        hitType = context.hitType,
        bonusMastery = false,
        modifiedDamage = type(context.damage) == "number" and context.damage or 0,
    }

    dbg(("CheckHit success: %s hit %s on %s"):format(attacker.Name, result.nodeName, targetCharacter.Name))
    return result
end

if Constants.DEBUG then
    task.spawn(function()
        task.wait(3)

        local r1 = NodeHitDetection.CheckHit(nil)
        assert(r1 and r1.hitNode == false, "nil context should return hitNode=false")

        local r2 = NodeHitDetection.CheckHit({})
        assert(r2 and r2.hitNode == false, "empty context should return hitNode=false")

        local set = buildEligibleSet({ "Elemental", "Guard" })
        assert(set.Elemental == true and set.Guard == true and set.Vision ~= true, "buildEligibleSet failed")

        print("[NodeHitDetection self-test] PASSED")
    end)
end

print("✅ NodeHitDetection initialized")

return NodeHitDetection
