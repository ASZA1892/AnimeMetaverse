# Phase 1 Handoff — Complete State

**Status:** COMPLETE as of April 24, 2026
**Commit:** Phase 1 complete — combat pipeline, dash, substitution, grapple, sprint, camera shake all implemented and verified on real multiplayer

---

## What Phase 1 Built

A working server-authoritative combat pipeline with full multiplayer verification. All core mechanics function end-to-end on real network conditions (PC + mobile).

### Verified Working
- Hit registration with 10-20 damage per move
- State machine cycling correctly (Idle → Attacking → Idle)
- Server-authoritative damage calculation
- Knockback replicating to target client
- Dash with stamina cost and regen (8-directional, camera-relative)
- Grapple system (server-side confirmed, visual feedback added)
- Substitution teleport on Q press during hit
- Guard/Block/Parry system
- Sprint (LeftShift → 16 to 28 walkspeed)
- Camera shake on hits (spring-decay system)
- Stamina UI (yellow bar, 100/100 display)
- Guard UI
- Mobile UI (attack button works, others connected but not fully working)
- All 9 core modules load cleanly on every server start

### Known Gaps (Deferred to Phase 2.5 Polish)
- Target Lock — removed from Phase 1, needs complete rebuild
- Tilt Tweening — removed, needs redesign without physics conflicts
- Animation system — placeholder IDs don't all work, needs custom Moon Animator animations
- Full mobile parity — only attack button reliable on mobile
- Grapple visual feedback — server works, client feedback minimal

---

## File Architecture

### Project Root
```
C:\Dev\AnimeMetaverse\
├── default.project.json      # Rojo config
├── wally.toml                # Package manifest
├── selene.toml               # Lua linter config
├── .cursorrules              # Cursor AI rules (NEW)
├── CLAUDE.md                 # Project context (NEW)
├── Phase1_Handoff.md         # This document
├── Phase2_Plan.md            # Phase 2 build plan
├── GameDesignDecisions.md    # All design decisions
└── src/
    ├── shared/               # → ReplicatedStorage.Shared
    ├── server/               # → ServerScriptService
    └── client/               # → StarterPlayerScripts
```

### src/shared/ (ReplicatedStorage.Shared)
```
Types/
├── CombatActions.lua         # Enum of all client↔server actions
├── MoveDefinitions.lua       # 14 moves with context-aware scoring
└── constants.lua             # All tuning values (damage, timing, hitboxes)
StaminaState.lua              # Shared stamina module (Get/Set/Deduct/Regen)
```

### src/server/Combat/ (ServerScriptService.Combat)
```
CombatHandler.server.lua      # Main server, dispatches to handlers
CombatStateMachine.lua        # State tracking with expiry
GuardSystem.lua               # Block/parry/chip damage/guard break
DashHandler.lua               # Server dash validation
SubstitutionHandler.lua       # Teleport behind attacker
GrappleHandler.lua            # Grab, disable, throw
```

### src/client/ (StarterPlayerScripts)
```
Combat/
├── CombatController.client.lua     # Main input + remote listener
├── CameraShaker.lua                # Spring-decay additive shake
├── DashController.client.lua       # Q input, camera-relative dash
├── SubstitutionController.client.lua  # Q during hit window
└── SprintController.client.lua     # LeftShift 16→28 walkspeed

Animations/
└── AnimationLoader.client.lua      # Placeholder animation IDs

UI/
├── GuardUI.client.lua              # Guard bar
├── StaminaUI.client.lua            # Yellow stamina bar bottom-center
└── MobileUI.client.lua             # 4 round buttons (ATK/DASH/BLK/GRB)
```

---

## Key Design Decisions Made

### Combat Facing
Player always attacks in direction they're facing. No aim-based targeting. Standard for the genre (Shindo Life, Blox Fruits).

### Hitbox Design
Jab hitbox is 3.5×4×4 studs extending forward from character. Tight enough to require facing, generous enough to feel good. All moves use `GetPartBoundsInBox` with character excluded.

### State Machine
6 states with meta and expiry:
- `Idle` — default
- `Attacking` — can't start new attack, expires after move cooldown
- `Blocking` — holding F, damage reduced
- `Dashing` — 0.2s duration, iframes active
- `Disabled` — stunned by grapple or knockback
- `Grappling` — actively holding target

### Knockback Solution
Physics via `AssemblyLinearVelocity` doesn't replicate cleanly to other clients. Solution: server fires `KNOCKBACK` RemoteEvent to target client with velocity vector. Target client applies it locally. This replicates smoothly across all viewers.

### Rate Limiting
Attack interval minimum 0.1s per player. Tracked in WeakKey table `lastAttackAt`. Other RPCs (block, parry, dash) not rate-limited to avoid blocking legitimate input chains.

### CombatRemote Creation
Server creates single `CombatRemote` in ReplicatedStorage on init with `FindFirstChild` fallback check. Never create client-side — causes two-instance bug where client and server listen on different objects.

---

## Constants Reference

Current values in `src/shared/Types/constants.lua`:

```
DEBUG = true

# Combat Timing
HIT_STOP_DURATION = 0.05
PARRY_WINDOW = 0.2
ATTACK_COOLDOWN = 0.15

# Damage
JAB_DAMAGE = 10
CROSS_DAMAGE = 12
HOOK_DAMAGE = 12
UPPERCUT_DAMAGE = 11
GUARD_BREAK_DAMAGE = 20

# Stamina
MAX_STAMINA = 100
STAMINA_REGEN_RATE = 15
STAMINA_REGEN_SPRINT = 5
DASH_STAMINA_QUICK = 10
DASH_STAMINA_MEDIUM = 18
DASH_STAMINA_FULL = 28
SUBSTITUTION_MIN_STAMINA = 20

# Guard
MAX_GUARD = 100
GUARD_DEPLETION_PER_HIT = 20
GUARD_BREAK_STUN = 2
GUARD_REGEN_RATE = 25
GUARD_REGEN_DELAY = 2
CHIP_DAMAGE_PERCENT = 0.15
PARRY_STUN_DURATION = 1.5
PARRY_COOLDOWN = 1.0

# Dash
DASH_IFRAMES_QUICK = 0.08
DASH_IFRAMES_MEDIUM = 0.15
DASH_IFRAMES_FULL = 0.2
DASH_COOLDOWN = 0.6

# Hitbox
JAB_RANGE = 5
JAB_HITBOX = Vector3.new(3.5, 4, 4)

# Camera
CAMERA_JOLT_STRENGTH = 0.2
CAMERA_JOLT_DURATION = 0.05

# Momentum (defined but not yet implemented)
MOMENTUM_PER_HIT = 15
MOMENTUM_ON_MISS = -20
MOMENTUM_MAX = 100
MOMENTUM_COMBO_TIMEOUT = 2

# Grapple
GRAPPLE_COOLDOWN = 6
GRAPPLE_RANGE = 5
GRAPPLE_DISABLE_DURATION = 1.5
GRAPPLE_THROW_DISTANCE = 15
```

---

## PC Controls (Current)

| Key | Action |
|---|---|
| Left Click | Jab (M1 attack) |
| Right Click | Guard Break (M2 attack) |
| E | Kick / Alt attack |
| W + Click | Cross |
| S + Click | Uppercut |
| A or D + Click | Hook |
| F | Block (hold) / Parry (tap during enemy attack) |
| G | Grapple (tap) / Throw (tap again) |
| Q | Dash (direction based on WASD) |
| Q during hit | Substitution (teleport behind attacker) |
| LeftShift | Sprint |

## Mobile Controls (Current State)
- ATK button works reliably
- DASH, BLK, GRB buttons present but inconsistent
- Full mobile parity is Phase 2.5 work

---

## Animation Status

Placeholder IDs used. Most moves use `rbxassetid://180435571` (Roblox default punch) or `rbxassetid://522635514` (right punch). Some IDs fail to load due to Roblox permission restrictions. **Custom animations via Moon Animator required before launch.** Animations are currently disabled in CombatController (commented out) to prevent log noise during testing.

---

## Phase 2 Entry Checklist

When starting Phase 2:
- [ ] Read CLAUDE.md
- [ ] Read Phase2_Plan.md
- [ ] Read GameDesignDecisions.md
- [ ] Verify all Phase 1 modules still loading on fresh clone
- [ ] Confirm Rojo serve works (port 34872)
- [ ] Pull latest from GitHub
- [ ] First feature: Element System foundation
