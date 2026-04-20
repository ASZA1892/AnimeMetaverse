-- src/client/Animations/AnimationLoader.client.lua
-- Safe animation loader with R15/R6 fallback
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- Safely require CombatActions (won't crash if missing)
local CombatActions
local ok, result = pcall(function()
    return require(ReplicatedStorage.Shared.Types.CombatActions)
end)
if ok and result then
    CombatActions = result
else
    warn("[AnimationLoader] CombatActions module missing; using fallback string.")
end

local player = Players.LocalPlayer
local function getLocalCharacter()
    return player.Character or player.CharacterAdded:Wait()
end

local function findAnimationForMove(moveId)
    local character = getLocalCharacter()
    local animationsFolder = ReplicatedStorage:FindFirstChild("Animations")
    if animationsFolder then
        local fromReplicatedStorage = animationsFolder:FindFirstChild(moveId)
        if fromReplicatedStorage then
            return fromReplicatedStorage, "ReplicatedStorage.Animations"
        end
    end
    local fromCharacter = character:FindFirstChild(moveId, true)
    if fromCharacter then
        return fromCharacter, "Character"
    end
    return nil, "None"
end

local function safeLoadAndPlay(moveId)
    local character = getLocalCharacter()
    local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid")
    local isR15 = humanoid.RigType == Enum.HumanoidRigType.R15
    local animator = humanoid:FindFirstChildOfClass("Animator")
    local animObject, source = findAnimationForMove(moveId)
    if not animObject then
        print(string.format("[AnimationLoader] moveId=%s source=%s load=failed reason=AnimationNotFound", tostring(moveId), source))
        return false
    end
    if not animObject:IsA("Animation") then
        warn(string.format("[AnimationLoader] moveId=%s source=%s load=failed reason=ObjectNotAnimation object=%s", tostring(moveId), source, animObject.Name))
        return false
    end

    local loaderUsed = "Humanoid:LoadAnimation (R6 fallback)"
    if isR15 then
        loaderUsed = "Animator:LoadAnimation (R15)"
        if not animator then
            animator = Instance.new("Animator")
            animator.Parent = humanoid
        end
    end

    local tracksToStop = {}
    -- Always enumerate playing tracks from the Humanoid (Animator does not expose GetPlayingAnimationTracks)
    local okTracks, playingTracks = pcall(function()
        return humanoid:GetPlayingAnimationTracks()
    end)
    if okTracks and playingTracks then
        tracksToStop = playingTracks
    end

    for _, track in ipairs(tracksToStop) do
        pcall(function()
            track:Stop(0.05)
        end)
    end

    task.wait(0.03)

    local okLoad, track = pcall(function()
        if isR15 then
            return animator:LoadAnimation(animObject)
        end
        return humanoid:LoadAnimation(animObject)
    end)
    if not okLoad or not track then
        warn(string.format(
            "[AnimationLoader] moveId=%s anim=%s animId=%s loader=%s load=failed",
            tostring(moveId),
            tostring(animObject.Name),
            tostring(animObject.AnimationId),
            loaderUsed
        ))
        return false
    end

    track.Priority = Enum.AnimationPriority.Action
    track:Play(0.05)

    -- Optional: print playing tracks shortly after play to verify nothing immediately overrides it
    task.delay(0.05, function()
        for _, t in ipairs(humanoid:GetPlayingAnimationTracks()) do
            print("[AnimationLoader] Playing track:", t.Name, "Priority:", tostring(t.Priority))
        end
    end)

    print(string.format(
        "[AnimationLoader] moveId=%s anim=%s animId=%s loader=%s load=success",
        tostring(moveId),
        tostring(animObject.Name),
        tostring(animObject.AnimationId),
        loaderUsed
    ))
    return true
end

local function playAttackAnimation(moveId)
    print("[AnimationLoader] Playing animation for: " .. tostring(moveId))
    safeLoadAndPlay(moveId)
end

local CombatRemote = ReplicatedStorage:WaitForChild("CombatRemote")
CombatRemote.OnClientEvent:Connect(function(action, data)
    local hitAction = (CombatActions and CombatActions.ServerToClient and CombatActions.ServerToClient.HIT_CONFIRMED) or "HitConfirmed"
    if action == hitAction and data then
        local attacker = data.attacker
        local attackerIsLocal =
            attacker == player
            or attacker == player.Character
            or (type(attacker) == "number" and attacker == player.UserId)
            or (type(attacker) == "string" and attacker == player.Name)
        if attackerIsLocal then
            playAttackAnimation(data.moveId)
        end
    end
end)

print("✅ AnimationLoader initialized (safe mode)")
