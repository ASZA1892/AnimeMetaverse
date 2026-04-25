local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local function safeWait(parent, name, timeout)
    if not parent then
        warn(("[NodeDebuffs] safeWait: parent is nil for '%s'"):format(name))
        return nil
    end

    local ok, inst = pcall(function()
        return parent:WaitForChild(name, timeout)
    end)
    if not ok then
        warn(("[NodeDebuffs] safeWait: WaitForChild('%s') errored"):format(name))
        return nil
    end
    if not inst then
        warn(("[NodeDebuffs] safeWait: WaitForChild('%s') timed out"):format(name))
        return nil
    end

    return inst
end

local function safeRequire(inst, name)
    if not inst then
        warn(("[NodeDebuffs] safeRequire: %s is nil"):format(name))
        return nil
    end

    local className = (inst.ClassName and tostring(inst.ClassName)) or "no ClassName"
    print(("DEBUG: safeRequire target %s -> ClassName=%s typeof=%s"):format(name, className, typeof(inst)))
    if className ~= "ModuleScript" then
        warn(("[NodeDebuffs] safeRequire: %s is not a ModuleScript (ClassName=%s)"):format(name, className))
    end

    local ok, result = pcall(require, inst)
    if not ok then
        warn(("[NodeDebuffs] safeRequire: require(%s) failed: %s"):format(name, tostring(result)))
        return nil
    end

    return result
end

local sharedFolder = safeWait(ReplicatedStorage, "Shared", 10)
local typesFolder = safeWait(sharedFolder, "Types", 10)
local constantsModule = safeWait(typesFolder, "constants", 5)
local elementStateModule = safeWait(sharedFolder, "ElementState", 5)
local elementRemote = safeWait(ReplicatedStorage, "ElementRemote", 5)

local combatFolder = safeWait(ServerScriptService, "Combat", 10)
local combatStateMachineModule = safeWait(combatFolder, "CombatStateMachine", 5)

print(
    "DEBUG: module presence:",
    "Shared=", tostring(sharedFolder ~= nil),
    "Types=", tostring(typesFolder ~= nil),
    "constants=", tostring(constantsModule ~= nil),
    "ElementState=", tostring(elementStateModule ~= nil),
    "Combat=", tostring(combatFolder ~= nil),
    "CombatStateMachine=", tostring(combatStateMachineModule ~= nil),
    "ElementRemote=", tostring(elementRemote ~= nil)
)

local Constants = safeRequire(constantsModule, "constants")
local ElementState = safeRequire(elementStateModule, "ElementState")
local CombatStateMachine = safeRequire(combatStateMachineModule, "CombatStateMachine")

if not Constants then
    error("[NodeDebuffs] Constants failed to load")
end
if not ElementState then
    error("[NodeDebuffs] ElementState failed to load")
end
if not CombatStateMachine then
    error("[NodeDebuffs] CombatStateMachine failed to load")
end

local function dbg(...)
    if Constants.DEBUG then
        print("[NodeDebuffs]", ...)
    end
end

local NodeDebuffs = {}

local ELEMENTAL_SEAL_DURATION = 6
local MOVEMENT_SLOW_DURATION  = 4
local GUARD_WEAKEN_DURATION   = 5
local VISION_DIM_DURATION     = 3
local CHAKRA_LOCK_DURATION    = 4

local MOVEMENT_REFRESH_INTERVAL = 1.5

local slowedHumanoids = setmetatable({}, { __mode = "k" })
local weakenedRoots = setmetatable({}, { __mode = "k" })

local function applyFailure(nodeName, targetPlayer, message, debuffId)
    return {
        applied = false,
        debuffId = debuffId or "none",
        nodeName = nodeName or "unknown",
        targetPlayer = targetPlayer,
        message = message or "failed",
    }
end

local function applySuccess(nodeName, targetPlayer, debuffId, message)
    return {
        applied = true,
        debuffId = debuffId,
        nodeName = nodeName,
        targetPlayer = targetPlayer,
        message = message,
    }
end

local function sealSpecificElement(targetPlayer, element)
    if not element then
        return false
    end

    local isSealedOk, isSealed = pcall(function()
        return ElementState.IsElementSealed(targetPlayer, element)
    end)
    if not isSealedOk then
        dbg("ElementState.IsElementSealed failed for", targetPlayer.Name, element)
        return false
    end
    if isSealed then
        return false
    end

    local sealOk = pcall(function()
        ElementState.SealElement(targetPlayer, element, ELEMENTAL_SEAL_DURATION)
    end)
    return sealOk
end

local function applyElementSeal(targetPlayer)
    if not (typeof(targetPlayer) == "Instance" and targetPlayer:IsA("Player")) then
        return false, "ElementSeal skipped: targetPlayer missing"
    end

    local affinityOk, affinity = pcall(function()
        return ElementState.GetAffinity(targetPlayer)
    end)
    if not affinityOk then
        return false, "ElementSeal failed: GetAffinity errored"
    end

    if affinity then
        local sealed = sealSpecificElement(targetPlayer, affinity)
        if sealed then
            return true, ("Element sealed: %s for %ds"):format(affinity, ELEMENTAL_SEAL_DURATION)
        end
        return false, ("ElementSeal skipped: affinity '%s' already sealed or failed"):format(affinity)
    end

    local knownOk, knownElements = pcall(function()
        return ElementState.GetKnownElements(targetPlayer)
    end)
    if not knownOk or type(knownElements) ~= "table" then
        return false, "ElementSeal failed: GetKnownElements errored"
    end

    local sealedCount = 0
    for _, element in ipairs(knownElements) do
        if sealSpecificElement(targetPlayer, element) then
            sealedCount = sealedCount + 1
        end
    end

    if sealedCount > 0 then
        return true, ("Wanderer sealed: %d elements for %ds"):format(sealedCount, ELEMENTAL_SEAL_DURATION)
    end
    return false, "ElementSeal skipped: no known unsealed elements"
end

local function applyMovementSlow(targetHumanoid)
    if not (typeof(targetHumanoid) == "Instance" and targetHumanoid:IsA("Humanoid")) then
        return false, "MovementSlow failed: humanoid missing"
    end

    local state = slowedHumanoids[targetHumanoid]
    if not state then
        state = {
            originalSpeed = targetHumanoid.WalkSpeed,
            token = 0,
        }
    end

    state.token = state.token + 1
    local activeToken = state.token
    slowedHumanoids[targetHumanoid] = state

    targetHumanoid.WalkSpeed = state.originalSpeed * 0.5

    task.delay(MOVEMENT_SLOW_DURATION, function()
        if not targetHumanoid or not targetHumanoid.Parent then
            slowedHumanoids[targetHumanoid] = nil
            return
        end

        local latest = slowedHumanoids[targetHumanoid]
        if latest and latest.token == activeToken then
            targetHumanoid.WalkSpeed = latest.originalSpeed
            slowedHumanoids[targetHumanoid] = nil
        end
    end)

    return true, ("Movement slowed to 50%% for %ds"):format(MOVEMENT_SLOW_DURATION)
end

local function applyGuardWeaken(targetCharacter)
    local root = targetCharacter:FindFirstChild("HumanoidRootPart")
    if not root then
        return false, "GuardWeaken failed: HumanoidRootPart missing"
    end

    local state = weakenedRoots[root] or { token = 0 }
    state.token = state.token + 1
    local activeToken = state.token
    weakenedRoots[root] = state

    root:SetAttribute("GuardWeakened", true)

    task.delay(GUARD_WEAKEN_DURATION, function()
        if not root or not root.Parent then
            weakenedRoots[root] = nil
            return
        end

        local latest = weakenedRoots[root]
        if latest and latest.token == activeToken then
            root:SetAttribute("GuardWeakened", false)
            weakenedRoots[root] = nil
        end
    end)

    return true, ("Guard weakened for %ds"):format(GUARD_WEAKEN_DURATION)
end

local function applyVisionDim(targetPlayer)
    if not (typeof(targetPlayer) == "Instance" and targetPlayer:IsA("Player")) then
        return false, "VisionDim skipped: targetPlayer missing"
    end
    if not elementRemote then
        return false, "VisionDim failed: ElementRemote missing"
    end

    if targetPlayer.Parent == Players then
        elementRemote:FireClient(targetPlayer, "VisionDim", { duration = VISION_DIM_DURATION })
    end

    return true, ("Vision dim sent for %ds"):format(VISION_DIM_DURATION)
end

local function applyChakraLock(targetPlayer)
    if not (typeof(targetPlayer) == "Instance" and targetPlayer:IsA("Player")) then
        return false, "ChakraLock skipped: targetPlayer missing"
    end

    local firstOk = pcall(function()
        ElementState.PauseRegen(targetPlayer)
    end)
    if not firstOk then
        return false, "ChakraLock failed: PauseRegen errored"
    end

    local endTime = tick() + CHAKRA_LOCK_DURATION
    task.spawn(function()
        while tick() < endTime do
            task.wait(MOVEMENT_REFRESH_INTERVAL)
            if tick() >= endTime then
                break
            end
            pcall(function()
                ElementState.PauseRegen(targetPlayer)
            end)
        end
    end)

    return true, ("Chakra regen locked for %ds"):format(CHAKRA_LOCK_DURATION)
end

local NODE_DEBUFFS = {
    Elemental = {
        id = "ElementSeal",
        apply = function(targetPlayer)
            return applyElementSeal(targetPlayer)
        end,
    },
    Movement = {
        id = "MovementSlow",
        apply = function(_, targetHumanoid)
            return applyMovementSlow(targetHumanoid)
        end,
    },
    Guard = {
        id = "GuardWeaken",
        apply = function(_, _, targetCharacter)
            return applyGuardWeaken(targetCharacter)
        end,
    },
    Vision = {
        id = "VisionDim",
        apply = function(targetPlayer)
            return applyVisionDim(targetPlayer)
        end,
    },
    Chakra = {
        id = "ChakraLock",
        apply = function(targetPlayer)
            return applyChakraLock(targetPlayer)
        end,
    },
}

function NodeDebuffs.Apply(nodeResult, context)
    if type(nodeResult) ~= "table" or nodeResult.hitNode ~= true or type(nodeResult.nodeName) ~= "string" or type(context) ~= "table" then
        return {
            applied = false,
            debuffId = "none",
            nodeName = "unknown",
            targetPlayer = nil,
            message = "invalid input",
        }
    end

    local nodeName = nodeResult.nodeName
    local targetPlayer = nodeResult.targetPlayer
    local target = context.target
    local attacker = context.attacker

    if targetPlayer and attacker == targetPlayer then
        return applyFailure(nodeName, targetPlayer, "debuff blocked: attacker cannot target self")
    end

    local targetCharacter = nil
    if targetPlayer then
        targetCharacter = targetPlayer.Character
    elseif typeof(target) == "Instance" and target:IsA("Model") and target:FindFirstChildOfClass("Humanoid") then
        targetCharacter = target
    end

    if not targetCharacter then
        return applyFailure(nodeName, targetPlayer, "target character not found")
    end

    local targetHumanoid = targetCharacter:FindFirstChildOfClass("Humanoid")
    if not targetHumanoid then
        return applyFailure(nodeName, targetPlayer, "target humanoid missing")
    end

    local debuffDef = NODE_DEBUFFS[nodeName]
    if not debuffDef then
        return applyFailure(nodeName, targetPlayer, "unknown node")
    end

    local _, currentState = pcall(function()
        if targetPlayer then
            return CombatStateMachine.GetState(targetPlayer)
        end
        return nil
    end)
    if currentState then
        dbg(("Applying %s while target state is %s"):format(debuffDef.id, tostring(currentState)))
    end

    local ok, applied, message = pcall(function()
        return debuffDef.apply(targetPlayer, targetHumanoid, targetCharacter, context, nodeResult)
    end)
    if not ok then
        return applyFailure(nodeName, targetPlayer, "debuff apply errored: " .. tostring(applied), debuffDef.id)
    end
    if not applied then
        return applyFailure(nodeName, targetPlayer, message or "debuff skipped", debuffDef.id)
    end

    local result = applySuccess(nodeName, targetPlayer, debuffDef.id, message or "debuff applied")
    dbg(("Applied %s to node %s target=%s"):format(debuffDef.id, nodeName, targetPlayer and targetPlayer.Name or targetCharacter.Name))
    return result
end

if Constants.DEBUG then
    task.spawn(function()
        task.wait(3)

        local r1 = NodeDebuffs.Apply(nil, {})
        assert(r1 and r1.applied == false, "nil nodeResult should return applied=false")

        local r2 = NodeDebuffs.Apply({ hitNode = false }, {})
        assert(r2 and r2.applied == false, "hitNode=false should return applied=false")

        local r3 = NodeDebuffs.Apply({ hitNode = true, nodeName = "FakeNode", targetPlayer = nil }, {})
        assert(r3 and r3.applied == false, "unknown node should return applied=false")

        print("[NodeDebuffs self-test] PASSED")
    end)
end

print("✅ NodeDebuffs initialized")

return NodeDebuffs
