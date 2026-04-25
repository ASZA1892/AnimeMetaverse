local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function safeWait(parent, name, timeout)
    if not parent then
        warn(("[WorldEffectRegistry] safeWait: parent is nil for '%s'"):format(name))
        return nil
    end

    local ok, inst = pcall(function()
        return parent:WaitForChild(name, timeout)
    end)
    if not ok then
        warn(("[WorldEffectRegistry] safeWait: WaitForChild('%s') errored"):format(name))
        return nil
    end
    if not inst then
        warn(("[WorldEffectRegistry] safeWait: WaitForChild('%s') timed out"):format(name))
        return nil
    end

    return inst
end

local function safeRequire(inst, name)
    if not inst then
        warn(("[WorldEffectRegistry] safeRequire: %s is nil"):format(name))
        return nil
    end

    local className = (inst.ClassName and tostring(inst.ClassName)) or "no ClassName"
    print(("DEBUG: safeRequire target %s -> ClassName=%s typeof=%s"):format(name, className, typeof(inst)))
    if className ~= "ModuleScript" then
        warn(("[WorldEffectRegistry] safeRequire: %s is not a ModuleScript (ClassName=%s)"):format(name, className))
    end

    local ok, result = pcall(require, inst)
    if not ok then
        warn(("[WorldEffectRegistry] safeRequire: require(%s) failed: %s"):format(name, tostring(result)))
        return nil
    end

    return result
end

local sharedFolder = safeWait(ReplicatedStorage, "Shared", 10)
local typesFolder = safeWait(sharedFolder, "Types", 10)
local constantsModule = safeWait(typesFolder, "constants", 5)

print("DEBUG: module presence:",
    "Shared=", tostring(sharedFolder ~= nil),
    "Types=", tostring(typesFolder ~= nil),
    "constants=", tostring(constantsModule ~= nil)
)

local Constants = safeRequire(constantsModule, "constants")
if not Constants then
    error("[WorldEffectRegistry] Constants failed to load")
end

local function dbg(...)
    if Constants.DEBUG then
        print("[WorldEffectRegistry]", ...)
    end
end

local WorldEffectRegistry = {}

local effects = {} -- [effectId] = effectData
local ownerEffects = {} -- [userId] = { [effectId] = true }
local nextEffectId = 0

local VALID_SHAPES = {
    Sphere = true,
    Box = true,
    Cone = true,
    Line = true,
}

local function cloneEffect(effect)
    if not effect then
        return nil
    end
    return table.clone(effect)
end

local function removeFromOwnerIndex(userId, effectId)
    local ownerBucket = ownerEffects[userId]
    if ownerBucket then
        ownerBucket[effectId] = nil
    end
end

local function generateEffectId()
    nextEffectId = nextEffectId + 1
    return "effect_" .. tostring(nextEffectId)
end

local function validateEffectData(effectData)
    if type(effectData) ~= "table" then
        return false, "effectData must be a table"
    end
    if type(effectData.effectType) ~= "string" then
        return false, "effectType must be a string"
    end
    if type(effectData.element) ~= "string" then
        return false, "element must be a string"
    end
    if type(effectData.ownerUserId) ~= "number" then
        return false, "ownerUserId must be a number"
    end
    if typeof(effectData.position) ~= "Vector3" then
        return false, "position must be a Vector3"
    end
    if type(effectData.shape) ~= "string" or not VALID_SHAPES[effectData.shape] then
        return false, "shape must be one of Sphere, Box, Cone, Line"
    end
    if type(effectData.duration) ~= "number" or effectData.duration <= 0 then
        return false, "duration must be a positive number"
    end
    return true, nil
end

local function removeEffectInternal(effectId, reason)
    local effect = effects[effectId]
    if not effect then
        return false
    end

    effect.alive = false

    if type(effect.onExpire) == "function" then
        local ok, err = pcall(effect.onExpire, effect, WorldEffectRegistry)
        if not ok then
            dbg("onExpire callback failed for", effectId, "-", tostring(err))
        end
    end

    effects[effectId] = nil
    removeFromOwnerIndex(effect.ownerUserId, effectId)
    dbg("removed effect", effectId, "reason:", reason or "manual")
    return true
end

function WorldEffectRegistry.CreateEffect(effectData)
    local isValid, reason = validateEffectData(effectData)
    if not isValid then
        dbg("CreateEffect rejected:", reason)
        return nil
    end

    local now = os.clock()
    local effectId = generateEffectId()

    local effect = table.clone(effectData)
    effect.id = effectId
    effect.createdAt = now
    effect.expiresAt = now + effect.duration
    effect.lastTick = 0
    effect.alive = true

    effects[effectId] = effect

    ownerEffects[effect.ownerUserId] = ownerEffects[effect.ownerUserId] or {}
    ownerEffects[effect.ownerUserId][effectId] = true

    dbg("created effect", effectId, effect.effectType, "owner:", effect.ownerUserId)
    return effectId
end

function WorldEffectRegistry.RemoveEffect(effectId)
    if type(effectId) ~= "string" then
        return false
    end
    return removeEffectInternal(effectId, "manual_remove")
end

function WorldEffectRegistry.GetEffectById(effectId)
    if type(effectId) ~= "string" then
        return nil
    end
    local effect = effects[effectId]
    if not effect or not effect.alive then
        return nil
    end
    return cloneEffect(effect)
end

function WorldEffectRegistry.GetEffectsInRadius(position, radius)
    if typeof(position) ~= "Vector3" or type(radius) ~= "number" then
        return {}
    end

    local results = {}
    for _, effect in pairs(effects) do
        if effect.alive then
            local baseDistance = (effect.position - position).Magnitude
            local extraRange = 0

            if effect.shape == "Sphere" then
                extraRange = type(effect.radius) == "number" and effect.radius or 0
            elseif effect.shape == "Box" then
                if typeof(effect.size) == "Vector3" then
                    extraRange = math.max(effect.size.X, effect.size.Y, effect.size.Z)
                end
            elseif effect.shape == "Cone" or effect.shape == "Line" then
                extraRange = type(effect.length) == "number" and effect.length or 0
            end

            if baseDistance <= (radius + extraRange) then
                table.insert(results, cloneEffect(effect))
            end
        end
    end

    return results
end

function WorldEffectRegistry.GetEffectsInBox(cframe, size)
    if typeof(cframe) ~= "CFrame" or typeof(size) ~= "Vector3" then
        return {}
    end

    local results = {}
    local half = size * 0.5

    for _, effect in pairs(effects) do
        if effect.alive then
            local localPos = cframe:PointToObjectSpace(effect.position)
            if math.abs(localPos.X) <= half.X
                and math.abs(localPos.Y) <= half.Y
                and math.abs(localPos.Z) <= half.Z then
                table.insert(results, cloneEffect(effect))
            end
        end
    end

    return results
end

function WorldEffectRegistry.GetEffectsByOwner(userId)
    if type(userId) ~= "number" then
        return {}
    end

    local results = {}
    local ownerBucket = ownerEffects[userId]
    if not ownerBucket then
        return results
    end

    for effectId in pairs(ownerBucket) do
        local effect = effects[effectId]
        if effect and effect.alive then
            table.insert(results, cloneEffect(effect))
        end
    end

    return results
end

function WorldEffectRegistry.GetEffectsByTag(tagName)
    if type(tagName) ~= "string" then
        return {}
    end

    local results = {}
    for _, effect in pairs(effects) do
        if effect.alive
            and type(effect.tags) == "table"
            and effect.tags[tagName] == true then
            table.insert(results, cloneEffect(effect))
        end
    end

    return results
end

function WorldEffectRegistry.GetAllEffects()
    local results = {}
    for _, effect in pairs(effects) do
        if effect.alive then
            table.insert(results, cloneEffect(effect))
        end
    end
    return results
end

function WorldEffectRegistry.GetEffectCount()
    local count = 0
    for _, effect in pairs(effects) do
        if effect.alive then
            count = count + 1
        end
    end
    return count
end

local function onPlayerAdded(player)
    ownerEffects[player.UserId] = ownerEffects[player.UserId] or {}
    dbg("player tracked", player.Name, player.UserId)
end

local function onPlayerRemoving(player)
    local userId = player.UserId
    local ownerBucket = ownerEffects[userId]
    if not ownerBucket then
        return
    end

    local toRemove = {}
    for effectId in pairs(ownerBucket) do
        table.insert(toRemove, effectId)
    end

    local removedCount = 0
    for _, effectId in ipairs(toRemove) do
        if removeEffectInternal(effectId, "owner_left") then
            removedCount = removedCount + 1
        end
    end

    ownerEffects[userId] = nil
    dbg("owner cleanup complete", player.Name, "removed:", removedCount)
end

for _, player in ipairs(Players:GetPlayers()) do
    onPlayerAdded(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

task.spawn(function()
    while true do
        local now = os.clock()
        local expiredIds = {}

        for effectId, effect in pairs(effects) do
            if effect.alive then
                if now >= effect.expiresAt then
                    table.insert(expiredIds, effectId)
                elseif type(effect.tickRate) == "number"
                    and effect.tickRate > 0
                    and (now - effect.lastTick) >= effect.tickRate then
                    effect.lastTick = now
                    if type(effect.onTick) == "function" then
                        local ok, err = pcall(effect.onTick, effect, WorldEffectRegistry)
                        if not ok then
                            dbg("onTick callback failed for", effectId, "-", tostring(err))
                        elseif Constants.DEBUG then
                            dbg("tick", effectId)
                        end
                    end
                end
            end
        end

        for _, effectId in ipairs(expiredIds) do
            removeEffectInternal(effectId, "expired")
            dbg("expired effect", effectId)
        end

        task.wait(0.1)
    end
end)

if Constants.DEBUG then
    -- TODO: remove self-test once integrated with ElementInteractions
    task.spawn(function()
        task.wait(2)
        local testId = WorldEffectRegistry.CreateEffect({
            effectType = "TestEffect",
            element = "Neutral",
            ownerUserId = 0,
            position = Vector3.new(0, 0, 0),
            shape = "Sphere",
            radius = 5,
            duration = 3,
            tickRate = 1,
            tags = { TestTag = true },
            metadata = { note = "self-test" },
            onTick = function(effect)
                print("[WorldEffectRegistry self-test] tick on", effect.id)
            end,
            onExpire = function(effect)
                print("[WorldEffectRegistry self-test] expired", effect.id)
            end,
        })
        if testId then
            print("[WorldEffectRegistry self-test] created", testId, "— count:", WorldEffectRegistry.GetEffectCount())
        else
            warn("[WorldEffectRegistry self-test] CreateEffect returned nil — failure")
        end
    end)
end

print("✅ WorldEffectRegistry initialized")

return WorldEffectRegistry
