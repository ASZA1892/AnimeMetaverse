--[[
    ElementRemote actions (future ElementActions.lua enum):

    ClientToServer:
        "TechniqueUse" — { techniqueId = string }

    ServerToClient:
        "TechniqueResult" — { techniqueId, attacker, target, damage, position, blocked, parried, timestamp }
        "TechniqueBlocked" — { techniqueId, reason }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")

local function safeWait(parent, name, timeout)
    if not parent then
        warn(("safeWait: parent is nil for '%s'"):format(name))
        return nil
    end
    local ok, inst = pcall(function()
        return parent:WaitForChild(name, timeout)
    end)
    if not ok then
        warn(("safeWait: WaitForChild('%s') errored"):format(name))
        return nil
    end
    if not inst then
        warn(("safeWait: WaitForChild('%s') timed out"):format(name))
        return nil
    end
    return inst
end

local sharedFolder = safeWait(ReplicatedStorage, "Shared", 10)
local typesFolder = safeWait(sharedFolder, "Types", 10)
local combatFolder = safeWait(ServerScriptService, "Combat", 10)

local ConstantsModule = safeWait(typesFolder, "constants", 2)
local TechniqueDefinitionsModule = safeWait(typesFolder, "TechniqueDefinitions", 2)
local ElementDefinitionsModule = safeWait(typesFolder, "ElementDefinitions", 2)
local ElementStateModule = safeWait(sharedFolder, "ElementState", 10)
local CombatStateMachineModule = safeWait(combatFolder, "CombatStateMachine", 5)
local GuardSystemModule = safeWait(combatFolder, "GuardSystem", 5)
local ElementInteractionsModule = safeWait(script.Parent, "ElementInteractions", 5)

print("DEBUG: module presence:",
    "Shared=", tostring(sharedFolder ~= nil),
    "Types=", tostring(typesFolder ~= nil),
    "Combat=", tostring(combatFolder ~= nil),
    "constants=", tostring(ConstantsModule ~= nil),
    "TechniqueDefinitions=", tostring(TechniqueDefinitionsModule ~= nil),
    "ElementDefinitions=", tostring(ElementDefinitionsModule ~= nil),
    "ElementState=", tostring(ElementStateModule ~= nil),
    "CombatStateMachine=", tostring(CombatStateMachineModule ~= nil),
    "GuardSystem=", tostring(GuardSystemModule ~= nil),
    "ElementInteractions=", tostring(ElementInteractionsModule ~= nil)
)

local function safeRequire(inst, name)
    if not inst then
        warn(("safeRequire: %s is nil"):format(name))
        return nil
    end
    local className = (inst.ClassName and tostring(inst.ClassName)) or "no ClassName"
    print(("DEBUG: safeRequire target %s -> ClassName=%s typeof=%s"):format(name, className, typeof(inst)))
    if className ~= "ModuleScript" then
        warn(("safeRequire: %s is not a ModuleScript (ClassName=%s)"):format(name, className))
    end
    local ok, result = pcall(require, inst)
    if not ok then
        warn(("safeRequire: require(%s) failed: %s"):format(name, tostring(result)))
        return nil
    end
    return result
end

local Constants = safeRequire(ConstantsModule, "constants")
local TechniqueDefinitions = safeRequire(TechniqueDefinitionsModule, "TechniqueDefinitions")
local ElementDefinitions = safeRequire(ElementDefinitionsModule, "ElementDefinitions")
local ElementState = safeRequire(ElementStateModule, "ElementState")
local CombatStateMachine = safeRequire(CombatStateMachineModule, "CombatStateMachine")
local GuardSystem = safeRequire(GuardSystemModule, "GuardSystem")
local ElementInteractions = safeRequire(ElementInteractionsModule, "ElementInteractions")

if not TechniqueDefinitions then
    error("[ElementHandler] TechniqueDefinitions failed to load")
end
if not ElementState then
    error("[ElementHandler] ElementState failed to load")
end
if not ElementDefinitions then
    error("[ElementHandler] ElementDefinitions failed to load")
end
if not CombatStateMachine then
    error("[ElementHandler] CombatStateMachine failed to load")
end
if not GuardSystem then
    error("[ElementHandler] GuardSystem failed to load")
end
if not Constants then
    error("[ElementHandler] Constants failed to load")
end

local ElementRemote = ReplicatedStorage:FindFirstChild("ElementRemote")
if not ElementRemote then
    ElementRemote = ReplicatedStorage:WaitForChild("ElementRemote", 10)
end
if not ElementRemote then
    error("[ElementHandler] ElementRemote missing — ElementState must load first")
end

local function dbg(...)
    if Constants and Constants.DEBUG then
        print("[ElementHandler]", ...)
    end
end

local techniqueCooldowns = setmetatable({}, { __mode = "k" })
local lastTechniqueAt = setmetatable({}, { __mode = "k" })

local TECHNIQUE_MIN_INTERVAL = 0.15

local ACTION_TECHNIQUE_USE = "TechniqueUse"
local ACTION_TECHNIQUE_RESULT = "TechniqueResult"
local ACTION_TECHNIQUE_BLOCKED = "TechniqueBlocked"

local function findCharacterModelFromPart(part)
    local node = part
    local depth = 0
    while node and depth < 12 do
        if node:IsA("Model") then
            if node:FindFirstChildOfClass("Humanoid") or node:FindFirstChild("HumanoidRootPart") then
                return node
            end
        end
        node = node.Parent
        depth = depth + 1
    end
    return nil
end

local function fireBlocked(player, techniqueId, reason)
    ElementRemote:FireClient(player, ACTION_TECHNIQUE_BLOCKED, {
        techniqueId = techniqueId,
        reason = reason,
    })
end

local function anyKnownElementSealed(player)
    local known = ElementState.GetKnownElements(player)
    for _, el in ipairs(known) do
        if ElementState.IsElementSealed(player, el) then
            return true
        end
    end
    return false
end

local function finalSetupSatisfied(player, technique)
    if not technique.isFinal then
        return true
    end
    local setup = technique.setup
    if type(setup) ~= "table" then
        return false
    end

    local anyChecked = false
    local anyPass = false

    local function consider(flagName, passes)
        if setup[flagName] == true then
            anyChecked = true
            if passes then
                anyPass = true
            end
        end
    end

    local meta = CombatStateMachine.GetMeta(player)
    consider("requireGuardBroken", meta.guardBroken == true)
    consider("requireNodeSealed", anyKnownElementSealed(player))
    -- Week 4: momentum >= Constants.MOMENTUM_MAX
    consider("requireMomentumFull", false)
    consider("requireCharge", CombatStateMachine.GetState(player) == "Channeling")
    consider("requireFavourableTerrain", true)

    if not anyChecked then
        return true
    end
    return anyPass
end

local function getHitPosition(hitModel, fallbackPos)
    local root = hitModel.PrimaryPart or hitModel:FindFirstChild("HumanoidRootPart")
    if root then
        return root.Position
    end
    return fallbackPos
end

ElementRemote.OnServerEvent:Connect(function(player, action, data)
    if action ~= ACTION_TECHNIQUE_USE then
        return
    end

    if not (player and typeof(player) == "Instance" and player:IsA("Player") and player.UserId and player.UserId > 0) then
        return
    end

    local now = tick()
    local last = lastTechniqueAt[player] or 0
    if now - last < TECHNIQUE_MIN_INTERVAL then
        fireBlocked(player, type(data) == "table" and data.techniqueId or nil, "rate_limited")
        return
    end
    lastTechniqueAt[player] = now

    local character = player.Character
    if not character or not character.PrimaryPart then
        fireBlocked(player, type(data) == "table" and data.techniqueId or nil, "no_character")
        return
    end

    local tid = type(data) == "table" and data.techniqueId or nil
    local technique = type(tid) == "string" and TechniqueDefinitions.GetTechnique(tid) or nil

    if type(data) ~= "table" or type(tid) ~= "string" or not technique then
        fireBlocked(player, tid, "invalid_technique")
        return
    end

    if not ElementState.KnowsElement(player, technique.element) then
        fireBlocked(player, technique.id, "element_locked")
        return
    end

    if ElementState.IsElementSealed(player, technique.element) then
        fireBlocked(player, technique.id, "element_sealed")
        return
    end

    local currentState = CombatStateMachine.GetState(player)
    if currentState == "Stunned" or currentState == "Grappling" then
        fireBlocked(player, technique.id, "invalid_state")
        return
    end

    if not technique.isFinal and not CombatStateMachine.CanAttack(player) then
        fireBlocked(player, technique.id, "invalid_state")
        return
    end

    local cdMap = techniqueCooldowns[player]
    if cdMap and cdMap[technique.id] and tick() < cdMap[technique.id] then
        fireBlocked(player, technique.id, "cooldown_active")
        return
    end

    if not ElementState.HasEnoughChakra(player, technique.cost) then
        fireBlocked(player, technique.id, "insufficient_chakra")
        return
    end

    if technique.isFinal and not finalSetupSatisfied(player, technique) then
        fireBlocked(player, technique.id, "setup_required")
        return
    end

    -- TODO Phase 2 Week 3: read player mastery progression and pass actual tier
    local tierData = TechniqueDefinitions.GetTierData(technique.id, "mastered")
    if not tierData then
        fireBlocked(player, technique.id, "tier_data_missing")
        return
    end

    if not ElementState.DeductChakra(player, technique.cost) then
        fireBlocked(player, technique.id, "insufficient_chakra")
        return
    end

    local okState, stateReason = CombatStateMachine.TrySetState(player, "Attacking", {
        expiresAt = tick() + technique.cooldown,
    })
    if not okState then
        ElementState.AddChakra(player, technique.cost)
        dbg("TrySetState failed:", tostring(stateReason))
        fireBlocked(player, technique.id, "state_transition_failed")
        return
    end

    techniqueCooldowns[player] = techniqueCooldowns[player] or {}
    techniqueCooldowns[player][technique.id] = tick() + technique.cooldown

    local rootPart = character.PrimaryPart
    local range = tierData.range or 0

    if technique.projectile == true then
        dbg("[ElementHandler] Projectile technique — TODO Phase 2: spawn projectile via ElementInteractions.lua")
        local pos = rootPart.Position
        local payload = {
            techniqueId = technique.id,
            attacker = player,
            target = nil,
            damage = 0,
            position = pos,
            blocked = false,
            parried = false,
            timestamp = tick(),
        }
        ElementRemote:FireClient(player, ACTION_TECHNIQUE_RESULT, payload)
        return
    end

    local hits = {}
    if range == 0 then
        table.insert(hits, character)
    else
        local forward = rootPart.CFrame.LookVector
        local center = rootPart.Position + forward * (range / 2)
        local boxCFrame = CFrame.new(center)

        local overlapParams = OverlapParams.new()
        overlapParams.FilterType = Enum.RaycastFilterType.Exclude
        overlapParams.FilterDescendantsInstances = { character }

        local hitboxSize = tierData.hitboxSize or Vector3.new(4, 4, 4)
        local partsInBox = Workspace:GetPartBoundsInBox(boxCFrame, hitboxSize, overlapParams)

        dbg("partsInBox count:", #partsInBox)

        local seen = {}
        for _, part in ipairs(partsInBox) do
            local model = findCharacterModelFromPart(part)
            if model and model ~= character and not seen[model] then
                local hum = model:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 then
                    seen[model] = true
                    table.insert(hits, model)
                    if technique.aoe ~= true then
                        break
                    end
                end
            end
        end
    end

    local passiveInfo = TechniqueDefinitions.GetPassive(technique.element)

    for _, hitModel in ipairs(hits) do
        local hitPlayer = Players:GetPlayerFromCharacter(hitModel)
        local hitHumanoid = hitModel:FindFirstChildOfClass("Humanoid")
        if hitHumanoid and hitHumanoid.Health > 0 then
            local hitRoot = hitModel.PrimaryPart or hitModel:FindFirstChild("HumanoidRootPart")
            local inRange = true
            if hitRoot then
                local dist = (hitRoot.Position - rootPart.Position).Magnitude
                if dist > (range + 2) then
                    inRange = false
                end
            end

            if inRange then
                local okProc, finalDamage, wasParried, _guardBroken = pcall(function()
                    return GuardSystem.ProcessHit(player, hitPlayer or hitModel, tierData.damage or 0, technique)
                end)

                if okProc then
                    if type(finalDamage) ~= "number" then
                        finalDamage = 0
                    end

                    local hitPos = getHitPosition(hitModel, rootPart.Position)
                    local blockedFlag = (hitPlayer and CombatStateMachine.GetState(hitPlayer) == "Blocking") or false

                    if wasParried then
                        local parryPayload = {
                            techniqueId = technique.id,
                            attacker = player,
                            target = hitPlayer,
                            damage = 0,
                            position = hitPos,
                            blocked = blockedFlag,
                            parried = true,
                            timestamp = tick(),
                        }
                        ElementRemote:FireClient(player, ACTION_TECHNIQUE_RESULT, parryPayload)
                        if hitPlayer and hitPlayer ~= player then
                            ElementRemote:FireClient(hitPlayer, ACTION_TECHNIQUE_RESULT, parryPayload)
                        end
                    else
                        if finalDamage > 0 and hitHumanoid.Parent then
                            hitHumanoid:TakeDamage(finalDamage)
                            if hitPlayer and hitPlayer ~= player then
                                ElementState.PauseRegen(hitPlayer)
                            end
                        end

                        if hitModel ~= character and ElementInteractions then
                            -- Resolve element interactions against world effects near impact
                            local resolution = ElementInteractions.ResolveHit({
                                attacker      = player,
                                attackerTier  = 3, -- TODO Phase 2 Week 3: read from mastery system
                                technique     = technique,
                                targetPosition = hitPos,
                                damage        = finalDamage,
                            })

                            -- Spawn world effect from this technique's effect tag
                            ElementInteractions.SpawnEffectFromTechnique({
                                attacker     = player,
                                attackerTier = 3, -- TODO Phase 2 Week 3: read from mastery system
                                technique    = technique,
                                tierData     = tierData,
                                position     = hitPos,
                            })

                            -- Trigger passive if this element has an always-trigger passive
                            if passiveInfo and passiveInfo.trigger == "always" then
                                ElementInteractions.SpawnPassive({
                                    player   = player,
                                    element  = technique.element,
                                    position = hitPos,
                                    tier     = 3, -- TODO Phase 2 Week 3: read from mastery system
                                })
                            end

                            dbg(("ElementInteractions resolved: damageMod=%.2f interactions=%d spawned=%d destroyed=%d"):format(
                                resolution.damageModifier,
                                #resolution.interactionsTriggered,
                                #resolution.effectsSpawned,
                                #resolution.effectsDestroyed
                            ))
                        end

                        local resultPayload = {
                            techniqueId = technique.id,
                            attacker = player,
                            target = hitPlayer,
                            damage = finalDamage,
                            position = hitPos,
                            blocked = blockedFlag,
                            parried = false,
                            timestamp = tick(),
                        }
                        ElementRemote:FireClient(player, ACTION_TECHNIQUE_RESULT, resultPayload)
                        if hitPlayer and hitPlayer ~= player then
                            ElementRemote:FireClient(hitPlayer, ACTION_TECHNIQUE_RESULT, resultPayload)
                        end
                    end
                else
                    warn(("[ElementHandler] GuardSystem.ProcessHit pcall failed: %s"):format(tostring(finalDamage)))
                end
            end
        end
    end
end)

print("✅ ElementHandler initialized")
