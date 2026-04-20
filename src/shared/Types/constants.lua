-- constants.lua
-- Single source of truth for all Phase 1 numbers
-- Change values here only — never hardcode numbers in other scripts

local Constants = {}

-- Debug
Constants.DEBUG = true -- Set to false when releasing

-- Combat timing
Constants.HIT_STOP_DURATION = 0.05 -- seconds
Constants.PARRY_WINDOW = 0.2 -- seconds
Constants.ATTACK_COOLDOWN = 0.3 -- seconds after attack before Idle

-- Damage values
Constants.JAB_DAMAGE = 10
Constants.CROSS_DAMAGE = 12
Constants.HOOK_DAMAGE = 12
Constants.UPPERCUT_DAMAGE = 11
Constants.GUARD_BREAK_DAMAGE = 20

-- Stamina
Constants.MAX_STAMINA = 100
Constants.STAMINA_REGEN_RATE = 15 -- per second standing
Constants.STAMINA_REGEN_SPRINT = 5 -- per second sprinting
Constants.DASH_STAMINA_QUICK = 10
Constants.DASH_STAMINA_MEDIUM = 18
Constants.DASH_STAMINA_FULL = 28
Constants.SUBSTITUTION_MIN_STAMINA = 20

-- Guard
Constants.MAX_GUARD = 100
Constants.GUARD_DEPLETION_PER_HIT = 20   -- Guard bar lost per blocked hit
Constants.GUARD_BREAK_STUN = 2           -- seconds stunned when guard breaks
Constants.GUARD_REGEN_RATE = 25          -- per second
Constants.GUARD_REGEN_DELAY = 2          -- seconds before regen starts
Constants.CHIP_DAMAGE_PERCENT = 0.15     -- 15% damage bleeds through block
Constants.PARRY_STUN_DURATION = 1.5      -- Stun applied to attacker on successful parry
Constants.PARRY_COOLDOWN = 1.0           -- Seconds between parry attempts

-- Dash
Constants.DASH_IFRAMES_QUICK = 0.1
Constants.DASH_IFRAMES_MEDIUM = 0.15
Constants.DASH_IFRAMES_FULL = 0.2
Constants.DASH_COOLDOWN = 0.8

-- Hitbox sizes
Constants.JAB_RANGE = 5
Constants.JAB_HITBOX = Vector3.new(6, 4, 6)

-- Camera
Constants.CAMERA_JOLT_STRENGTH = 0.2
Constants.CAMERA_JOLT_DURATION = 0.05

-- Momentum
Constants.MOMENTUM_PER_HIT = 15
Constants.MOMENTUM_ON_MISS = -20
Constants.MOMENTUM_MAX = 100
Constants.MOMENTUM_COMBO_TIMEOUT = 2 -- seconds

return Constants