-- src/client/Combat/DashController.client.lua

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local Workspace         = game:GetService("Workspace")

local CombatRemote  = ReplicatedStorage:WaitForChild("CombatRemote", 10)
local CombatActions = require(ReplicatedStorage.Shared.Types.CombatActions)
local Constants     = require(ReplicatedStorage.Shared.Types.constants)
local StaminaState  = require(ReplicatedStorage.Shared.StaminaState)

if not CombatRemote then error("CombatRemote not found") end

local player = Players.LocalPlayer

local lastDashAt        = 0
local isHoldingQ        = false

local dashCooldown          = Constants.DASH_COOLDOWN       or 0.8
local quickDashStaminaCost  = Constants.DASH_STAMINA_QUICK  or 10
local mediumDashStaminaCost = Constants.DASH_STAMINA_MEDIUM or 18
local fullDashStaminaCost   = Constants.DASH_STAMINA_FULL   or 28

local DASH_CONFIRMED_ACTION = (CombatActions.ServerToClient and CombatActions.ServerToClient.DASH_CONFIRMED) or "DashConfirmed"

local function dbg(...)
    if Constants.DEBUG then
        print("[DashController]", ...)
    end
end

local function getDashDirection()
    local character = player.Character
    if not character then return Vector3.zero end
    local root = character:FindFirstChild("HumanoidRootPart")
    if not root then return Vector3.zero end

    local w = UserInputService:IsKeyDown(Enum.KeyCode.W)
    local s = UserInputService:IsKeyDown(Enum.KeyCode.S)
    local a = UserInputService:IsKeyDown(Enum.KeyCode.A)
    local d = UserInputService:IsKeyDown(Enum.KeyCode.D)

    local camera = Workspace.CurrentCamera
    if not camera then return root.CFrame.LookVector end

    local camLook  = Vector3.new(camera.CFrame.LookVector.X,  0, camera.CFrame.LookVector.Z)
    local camRight = Vector3.new(camera.CFrame.RightVector.X, 0, camera.CFrame.RightVector.Z)

    if camLook.Magnitude  > 0 then camLook  = camLook.Unit  end
    if camRight.Magnitude > 0 then camRight = camRight.Unit end

    local moveVec = Vector3.zero
    if w then moveVec = moveVec + camLook  end
    if s then moveVec = moveVec - camLook  end
    if a then moveVec = moveVec - camRight end
    if d then moveVec = moveVec + camRight end

    if moveVec.Magnitude > 0 then return moveVec.Unit end
    return root.CFrame.LookVector
end

local function canDash(cost)
    local now = tick()
    if (now - lastDashAt) < dashCooldown then
        dbg("Dash blocked: cooldown active")
        return false
    end
    if StaminaState.GetStamina() < cost then
        dbg("Dash blocked: insufficient stamina", StaminaState.GetStamina(), "/", cost)
        return false
    end
    return true
end

local function applyDashVisual(direction, speed, duration)
    local character = player.Character
    if not character then return end
    local root = character:FindFirstChild("HumanoidRootPart")
    if not root then return end

    local currentVelocity = root.AssemblyLinearVelocity
    root.AssemblyLinearVelocity = Vector3.new(
        direction.X * speed,
        currentVelocity.Y,
        direction.Z * speed
    )

    task.delay(duration, function()
        if root and root.Parent then
            local vel = root.AssemblyLinearVelocity
            root.AssemblyLinearVelocity = Vector3.new(0, vel.Y, 0)
        end
    end)
end

local function fireDash(dashType, cost, speed, duration)
    if not canDash(cost) then return end
    local direction = getDashDirection()
    lastDashAt = tick()

    applyDashVisual(direction, speed, duration)

    CombatRemote:FireServer(CombatActions.ClientToServer.DASH, {
        direction    = { x = direction.X, y = direction.Y, z = direction.Z },
        dashType     = dashType,
        clientSentAt = tick(),
    })

    dbg("Fired", dashType, "dash | stamina cache=", StaminaState.GetStamina())
end

-- ─────────────────────────────────────────────
-- INPUT HANDLING
-- ─────────────────────────────────────────────

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end

    if input.KeyCode == Enum.KeyCode.Q then
        local isShiftHeld = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
        local isCtrlHeld  = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)

        if isShiftHeld then
            -- Q + Shift → full dash
            dbg("Q+Shift → full dash")
            fireDash("full", fullDashStaminaCost, 140, 0.25)
        elseif isCtrlHeld then
            -- Q + Ctrl → medium dash
            dbg("Q+Ctrl → medium dash")
            fireDash("medium", mediumDashStaminaCost, 110, 0.2)
        else
            -- Q → quick dash
            dbg("Q → quick dash")
            fireDash("quick", quickDashStaminaCost, 80, 0.15)
        end
    end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
    if input.KeyCode == Enum.KeyCode.Q then
        isHoldingQ = false
    end
end)

player.CharacterAdded:Connect(function()
    lastDashAt  = 0
    isHoldingQ  = false
end)

print("[DashController] DashController initialized")