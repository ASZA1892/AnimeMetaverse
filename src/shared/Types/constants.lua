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
Constants.DASH_COOLDOWN = 0.6 -- was 0.8, faster combos

-- Hitbox sizes
Constants.JAB_RANGE = 5
Constants.JAB_HITBOX = Vector3.new(3.5, 4, 4)

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
Constants.GRAPPLE_RANGE = 4.5
Constants.GRAPPLE_DISABLE_DURATION = 1.5
Constants.GRAPPLE_THROW_DISTANCE = 15


-- Chakra
Constants.MAX_CHAKRA = 100
Constants.CHAKRA_REGEN_RATE = 8         -- per second (deliberately slower than stamina)
Constants.CHAKRA_REGEN_DELAY = 2        -- seconds after taking a hit before regen resumes
Constants.CHAKRA_CHARGE_RATE = 25       -- per second when channeling (future charge move)

-- Chakra regen rates by player state (per second)
Constants.CHAKRA_REGEN_IDLE        = 8    -- standing calm / out of combat
Constants.CHAKRA_REGEN_MOVING      = 5    -- walking / neutral movement
Constants.CHAKRA_REGEN_SPRINT      = 2    -- sprinting or dashing
Constants.CHAKRA_REGEN_BLOCKING    = 2    -- holding block
Constants.CHAKRA_REGEN_CHARGING    = 12   -- meditating / charge move (vulnerable)
Constants.CHAKRA_REGEN_POST_USE    = 1.5  -- pause after using a technique (seconds)
Constants.CHAKRA_REGEN_PUSH_INTERVAL = 0.5 -- throttle rate for client push during regen

return Constants