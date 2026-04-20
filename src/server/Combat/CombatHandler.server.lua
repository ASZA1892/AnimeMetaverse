-- src/server/Combat/CombatHandler.server.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local function safeWait(parent, name, timeout)
    if not parent then return nil end
    local ok, inst = pcall(function() return parent:WaitForChild(name, timeout) end)
    if not ok then return nil end
    return inst
end

local sharedFolder = safeWait(ReplicatedStorage, "Shared", 5)
local typesFolder = safeWait(sharedFolder, "Types", 5)

local CombatActionsModule = safeWait(typesFolder, "CombatActions", 2)
local ConstantsModule = safeWait(typesFolder, "constants", 2)
local MoveDefinitionsModule = safeWait(typesFolder, "MoveDefinitions", 2)

local CombatStateMachineModule = safeWait(script.Parent, "CombatStateMachine", 5)
local GuardSystemModule = safeWait(script.Parent, "GuardSystem", 5)

local function safeRequire(inst)
    if not inst then return nil end
    local ok, result = pcall(require, inst)
    if not ok then
        warn(("safeRequire: require failed for %s"):format(tostring(inst.Name or "unknown")))
        return nil
    end
    return result
end

local CombatActions = safeRequire(CombatActionsModule)
local Constants = safeRequire(ConstantsModule)
local MoveDefinitions = safeRequire(MoveDefinitionsModule)
local CombatStateMachine = safeRequire(CombatStateMachineModule)
local GuardSystem = safeRequire(GuardSystemModule)

local CombatRemote = ReplicatedStorage:FindFirstChild("CombatRemote")
if not CombatRemote then
    CombatRemote = Instance.new("RemoteEvent")
    CombatRemote.Name = "CombatRemote"
    CombatRemote.Parent = ReplicatedStorage
end

local function dbg(...)
    if Constants and Constants.DEBUG then
        print(...)
    end
end

local lastRpcAt = setmetatable({}, { __mode = "k" })
local RPC_MIN_INTERVAL = 0.05

local function canProcessRpc(player)
    local now = tick()
    local last = lastRpcAt[player] or 0
    if now - last < RPC_MIN_INTERVAL then
        return false
    end
    lastRpcAt[player] = now
    return true
end

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

local function applyEffects(targetModel, move, attacker)
    local hum = targetModel:FindFirstChildOfClass("Humanoid")
    if not hum then return end

    if move.slow then
        local originalSpeed = hum.WalkSpeed
        hum.WalkSpeed = originalSpeed * (move.slow.percent or 1)
        task.delay(move.slow.duration or 0.5, function()
            if hum and hum.Parent then
                hum.WalkSpeed = originalSpeed
            end
        end)
    end

    if move.launch then
        local root = targetModel.PrimaryPart or targetModel:FindFirstChild("HumanoidRootPart")
        if root then
            root.Velocity = Vector3.new(0, move.launchPower or 25, 0)
        end
    end

    if move.stun and move.stun > 0 then
        local targetPlayer = Players:GetPlayerFromCharacter(targetModel)
        if targetPlayer and CombatStateMachine and CombatStateMachine.ForceState then
            CombatStateMachine.ForceState(targetPlayer, CombatStateMachine.States.Stunned, {
                expiresAt = tick() + move.stun
            })
        else
            local oldWalkSpeed = hum.WalkSpeed
            hum.WalkSpeed = 0
            task.delay(move.stun, function()
                if hum and hum.Parent then
                    hum.WalkSpeed = oldWalkSpeed
                end
            end)
        end
    end

    if move.groundBounce then
        local root = targetModel.PrimaryPart or targetModel:FindFirstChild("HumanoidRootPart")
        if root then
            root.Velocity = Vector3.new(0, 20, 0)
        end
    end
end

CombatRemote.OnServerEvent:Connect(function(player, action, data)
    if not player or not player:IsA("Player") then return end
    if not canProcessRpc(player) then return end

    if not CombatStateMachine or not MoveDefinitions or not GuardSystem or not CombatActions then
        warn("CombatHandler: missing core modules, aborting RPC")
        return
    end

    local currentState = CombatStateMachine.GetState(player)

    if action == CombatActions.ClientToServer.BLOCK_START then
        GuardSystem.StartBlocking(player)
        return
    elseif action == CombatActions.ClientToServer.BLOCK_END then
        GuardSystem.StopBlocking(player)
        return
    end

    if action == CombatActions.ClientToServer.PARRY then
        local ok = GuardSystem.RecordParry(player)
        if not ok then
            dbg("Parry ignored for", player.Name)
        end
        return
    end

    if type(data) ~= "table" then return end

    local moveId = data.moveId
    if type(moveId) ~= "string" then return end

    local move = MoveDefinitions.GetMove(moveId)
    if not move then return end

    if not CombatStateMachine.CanAttack(player) then return end

    if move.requiresDash and currentState ~= CombatStateMachine.States.Dashing then return end
    if move.requiresAirborne and not CombatStateMachine.GetIsAirborne(player) then return end

    local ok, reason = CombatStateMachine.TrySetState(player, CombatStateMachine.States.Attacking, {
        expiresAt = tick() + (move.cooldown or 0)
    })
    if not ok then return end

    local character = player.Character
    if not character or not character.PrimaryPart then
        CombatStateMachine.ForceState(player, CombatStateMachine.States.Idle)
        return
    end

    local rootPart = character.PrimaryPart
    local forward = rootPart.CFrame.LookVector
    local offset = forward * ((move.range or 3) / 2)
    local center = rootPart.Position + offset
    local boxCFrame = CFrame.new(center)

    local overlapParams = OverlapParams.new()
    overlapParams.FilterType = Enum.RaycastFilterType.Exclude
    overlapParams.FilterDescendantsInstances = {character}

    local partsInBox = Workspace:GetPartBoundsInBox(boxCFrame, move.hitboxSize or Vector3.new(3,3,3), overlapParams)

    local hitModel, hitPlayer
    for _, part in ipairs(partsInBox) do
        local model = findCharacterModelFromPart(part)
        if model and model ~= character then
            local hum = model:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                hitModel = model
                hitPlayer = Players:GetPlayerFromCharacter(model)
                break
            end
        end
    end

    if not hitModel then return end

    local hitRoot = hitModel.PrimaryPart or hitModel:FindFirstChild("HumanoidRootPart")
    if hitRoot then
        local dist = (hitRoot.Position - rootPart.Position).Magnitude
        if dist > ((move.range or 3) + 0.5) then
            return
        end
    end

    local hitHumanoid = hitModel:FindFirstChildOfClass("Humanoid")
    local targetName = hitPlayer and hitPlayer.Name or hitModel.Name

    -- Normal ProcessHit call
    local finalDamage, wasParried, guardBroken = GuardSystem.ProcessHit(player, hitPlayer or hitModel, move.damage or 0, move)

    if wasParried then
        dbg("Parried by", targetName)
        local parryData = {attacker = player, target = hitPlayer, moveId = moveId, serverTimestamp = tick()}
        CombatRemote:FireClient(player, CombatActions.ServerToClient.HIT_PARRIED, parryData)
        if hitPlayer then
            CombatRemote:FireClient(hitPlayer, CombatActions.ServerToClient.PARRY_SUCCESS, parryData)
        end
        return
    end

    if finalDamage > 0 and hitHumanoid and hitHumanoid.Parent then
        hitHumanoid:TakeDamage(finalDamage)
    else
        dbg("Blocked!", targetName)
    end

    if not wasParried then
        if move.knockback and move.knockback > 0 and hitRoot then
            local dirVec = hitRoot.Position - rootPart.Position
            local okUnit, knockbackDir = pcall(function() return dirVec.Unit end)
            if okUnit and knockbackDir then
                local multiplier = (hitPlayer and CombatStateMachine.GetState(hitPlayer) == CombatStateMachine.States.Blocking) and 0.5 or 1.0
                hitRoot.Velocity = knockbackDir * (move.knockback * 10) * multiplier
            end
        end

        if not hitPlayer or CombatStateMachine.GetState(hitPlayer) ~= CombatStateMachine.States.Blocking then
            applyEffects(hitModel, move, player)
        end
    end

    if move.lunge then
        rootPart.Velocity = forward * (move.lunge * 20)
    end

    if finalDamage > 0 or guardBroken then
        local hitData = {
            attacker = player,
            target = hitPlayer,
            position = hitModel.PrimaryPart and hitModel.PrimaryPart.Position or Vector3.zero,
            damage = finalDamage,
            moveId = moveId,
            hitStop = Constants and Constants.HIT_STOP_DURATION or 0,
            serverTimestamp = tick(),
            blocked = (hitPlayer and CombatStateMachine.GetState(hitPlayer) == CombatStateMachine.States.Blocking) or false,
            guardBroken = guardBroken
        }
        CombatRemote:FireClient(player, CombatActions.ServerToClient.HIT_CONFIRMED, hitData)
        if hitPlayer then
            CombatRemote:FireClient(hitPlayer, CombatActions.ServerToClient.HIT_CONFIRMED, hitData)
        end
    end
end)

dbg("✅ CombatHandler server initialized (with Guard/Parry)")
