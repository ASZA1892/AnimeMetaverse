-- constants.lua
-- Single source of truth for all Phase 1 numbers

local Constants = {}

-- Debug
Constants.DEBUG = true

-- Combat timing
Constants.HIT_STOP_DURATION = 0.05
Constants.PARRY_WINDOW = 0.2
Constants.ATTACK_COOLDOWN = 0.15 -- was 0.3, faster combos

-- Damage values
Constants.JAB_DAMAGE = 10
Constants.CROSS_DAMAGE = 12
Constants.HOOK_DAMAGE = 12
Constants.UPPERCUT_DAMAGE = 11
Constants.GUARD_BREAK_DAMAGE = 20

-- Stamina
Constants.MAX_STAMINA = 100
Constants.STAMINA_REGEN_RATE = 15
Constants.STAMINA_REGEN_SPRINT = 5
Constants.DASH_STAMINA_QUICK = 10
Constants.DASH_STAMINA_MEDIUM = 18
Constants.DASH_STAMINA_FULL = 28
Constants.SUBSTITUTION_MIN_STAMINA = 20

-- Guard
Constants.MAX_GUARD = 100
Constants.GUARD_DEPLETION_PER_HIT = 20
Constants.GUARD_BREAK_STUN = 2
Constants.GUARD_REGEN_RATE = 25
Constants.GUARD_REGEN_DELAY = 2
Constants.CHIP_DAMAGE_PERCENT = 0.15
Constants.PARRY_STUN_DURATION = 1.5
Constants.PARRY_COOLDOWN = 1.0

-- Dash
Constants.DASH_IFRAMES_QUICK = 0.08 -- was 0.1
Constants.DASH_IFRAMES_MEDIUM = 0.15
Constants.DASH_IFRAMES_FULL = 0.2
Constants.DASH_COOLDOWN = 0.5 -- was 0.8, faster combos

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
Constants.MOMENTUM_COMBO_TIMEOUT = 2

-- Grapple
Constants.GRAPPLE_COOLDOWN = 6
Constants.GRAPPLE_RANGE = 3.5
Constants.GRAPPLE_DISABLE_DURATION = 1.5
Constants.GRAPPLE_THROW_DISTANCE = 15

return Constants