-- src/shared/StaminaState.lua
-- Shared stamina state readable by any client script

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage.Shared.Types.constants)

local StaminaState = {}

local currentStamina = Constants.MAX_STAMINA or 100

function StaminaState.GetStamina()
	return currentStamina
end

function StaminaState.SetStamina(value)
	currentStamina = math.clamp(value, 0, Constants.MAX_STAMINA or 100)
end

function StaminaState.Deduct(amount)
	currentStamina = math.clamp(currentStamina - amount, 0, Constants.MAX_STAMINA or 100)
end

function StaminaState.Regen(amount)
	currentStamina = math.clamp(currentStamina + amount, 0, Constants.MAX_STAMINA or 100)
end

return StaminaState