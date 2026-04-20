-- src/shared/Types/CombatActions.lua
-- Shared action names used by both client and server

local CombatActions = {}

-- Client fires these TO the server
CombatActions.ClientToServer = {
    M1_ATTACK = "M1Attack",
    M2_GUARDBREAK = "M2GuardBreak",
    BLOCK_START = "BlockStart",
    BLOCK_END = "BlockEnd",
    DASH = "Dash",
    GRAB_ATTEMPT = "GrabAttempt",
    PARRY = "Parry",
    CHARGE_START = "ChargeStart",
    CHARGE_RELEASE = "ChargeRelease",
    PHASE_STEP = "PhaseStep",
    SUBSTITUTION = "Substitution",
}

-- Server fires these TO clients
CombatActions.ServerToClient = {
    HIT_CONFIRMED = "HitConfirmed",
    STATE_CHANGED = "StateChanged",
    DAMAGE_DEALT = "DamageDealt",
    PARRY_SUCCESS = "ParrySuccess",
    GUARD_BROKEN = "GuardBroken",
    GUARD_UPDATE = "GuardUpdate",
    CLASH_START = "ClashStart",
    CLASH_END = "ClashEnd",
}

return CombatActions