# Phase 2 Plan — Element System Foundation

**Goal:** Transform the working Phase 1 physical combat pipeline into a full technique-based combat system with elements, Vital 5 precision targeting, and GPL progression.

**Duration estimate:** 4-6 weeks at current pace

---

## Phase 2 Build Order (Critical)

These MUST be built in this order. Each depends on the previous.

### Week 1: Element Foundation
1. **ElementState module** — track each player's element affinity, known elements, mastery levels
2. **ElementDefinitions** — Fire, Water, Grass with unique properties
3. **Basic element projectile** — one technique per element to prove pipeline
4. **Element interactions** — Fire burns Grass traps, Water creates steam from Fire, Grass absorbs Water

### Week 2: Vital 5 Precision System
1. **VitalNodeTracker** — attach 5 invisible hitbox markers to every character
2. **NodeHitDetection** — distinguish node hits from regular hits
3. **NodeDebuffs** — apply unique effects per node hit
4. **Element node seal** — Vital 5 Elemental Node hit seals opponent's element 6 seconds
5. **Underdog mastery rewards** — bonus for low-GPL players hitting nodes on high-GPL opponents

### Week 3: GPL & Progression
1. **GPL tracking module** — store, calculate, sync GPL across sessions
2. **Layered death penalty** — calculate loss based on skill gap
3. **Honor/Karma system** — track good/bad actions, apply effects
4. **Aura Pressure** — stronger players drain stamina faster vs weaker
5. **Mastery tracking** — per-technique Raw→Refined→Mastered→Transcendent→Resonance

### Week 4: Combat Economy
1. **Stamina costs on attacks** — implement 5/10/15/20-30 tiered costs
2. **Momentum damage system** — velocity-based damage scaling
3. **Regen pause after hit** — 2 second delay before regen kicks in
4. **Element cost economy** — techniques use element energy (separate resource)

### Week 5: Testing & Tuning
1. **Two-device real multiplayer test** — verify all systems across PC/mobile
2. **Tuning pass** — adjust all numbers based on actual play feel
3. **Bug fix sprint** — address anything found in testing
4. **Commit Phase 2 milestone**

### Week 6: Buffer / Polish
- Reserved for unexpected complexity
- If on schedule, start Phase 3 planning early

---

## Critical Phase 2 Modules

### Shared (ReplicatedStorage)

```
Types/
├── ElementDefinitions.lua    # Fire/Water/Grass data
├── TechniqueDefinitions.lua  # All element techniques
├── VitalNodes.lua            # Node positions and effects
└── ProgressionConstants.lua  # GPL curves, mastery rates

ElementState.lua              # Shared element resource tracking
ProgressionState.lua          # Shared GPL/Mastery tracking
HonorState.lua                # Shared Honor/Karma tracking
```

### Server (ServerScriptService)

```
Element/
├── ElementHandler.server.lua     # Element technique dispatcher
├── ElementInteractions.lua       # Fire+Grass=burn, Water+Fire=steam
├── TechniqueExecutor.lua         # Generic technique processor
└── ElementRegenerator.lua        # Element energy regen

Progression/
├── GPLHandler.server.lua         # GPL gain/loss logic
├── MasteryTracker.lua            # Mastery progress per player
├── HonorSystem.lua               # Karma tracking
└── AuraPressure.lua              # Power gap prevention

VitalFive/
├── VitalNodeHandler.server.lua   # Node hit detection
├── NodeDebuffs.lua               # Debuff application
└── NodeValidation.lua            # Anti-exploit precision checks
```

### Client (StarterPlayerScripts)

```
Element/
├── ElementController.client.lua  # Element input binding
├── ElementVFX.lua                # Particle effects
└── ElementUI.client.lua          # Element resource bar

Progression/
├── GPLDisplay.client.lua         # GPL UI
├── HonorIndicator.client.lua     # Honor bar
└── MasteryUI.client.lua          # Technique progression display

VitalFive/
├── NodeTargetAssist.client.lua   # Visual node hints on target lock
└── NodeHitFeedback.client.lua    # Visual feedback on node hits
```

---

## Element System Technical Design

### Element Resource
Each player has three element bars (one per known element):
- Max 100 per element
- Regenerates slowly when not using that element
- Depletes per technique use
- Initially only affinity element available, others unlock through progression

### Element Techniques (Examples)
**Fire:**
- **Ember Palm** (Raw): short-range burst, applies Burn DoT
- **Flame Trail** (Refined): dash that leaves fire trail behind
- **Inferno Wave** (Mastered): large AoE, burns through obstacles

**Water:**
- **Ripple Strike** (Raw): medium-range projectile, applies Soak debuff
- **Fluid Step** (Refined): instant redirect/parry counter
- **Tsunami Surge** (Mastered): wave push, creates steam on Fire contact

**Grass:**
- **Thorn Trap** (Raw): place trap that roots on contact
- **Regrowth** (Refined): self-heal over time
- **Verdant Prison** (Mastered): large AoE trap zone

### Element Interaction Rules (Server-Side)
When technique hits affected element:
- Fire + Grass trap/wall → instant destruction, no roots applied
- Water projectile + Fire AoE → converts to steam cloud, obscures vision
- Grass absorb + Water projectile → Grass user heals, Water wasted
- Fire vs Fire → mutual partial cancellation (60%)

Implementation: Each technique has `interactions` table in `ElementDefinitions` with lookup by opposing element.

---

## Vital 5 Technical Design

### Node Attachment
On `CharacterAdded`, attach 5 invisible parts:
- Elemental Node: on UpperTorso (sternum)
- Movement Node: on LowerTorso (lower back)
- Guard Node: on RightUpperArm (forearm)
- Vision Node: on Head (temple)
- Chakra Node: on HumanoidRootPart (abdomen)

Each part: 0.5×0.5×0.5 stud, CanCollide=false, Transparency=1 (invisible).

### Hit Detection Priority
When server processes a hit:
1. Check if Vital 5 node was hit (smaller hitbox)
2. If yes: apply node-specific debuff + standard damage + skill bonus
3. If no: standard hit processing

### Debuff Effects
- Elemental Node: opponent's element sealed 6 seconds
- Movement Node: 50% walk speed 4 seconds
- Guard Node: guard drain 2x rate 5 seconds
- Vision Node: screen dim 60% 3 seconds (client-side VFX)
- Chakra Node: stamina locked 4 seconds

### Anti-Exploit
- Client cannot claim node hits
- Server-side precision check: was the hit part actually within node hitbox
- Rate limit: max 1 node hit per 2 seconds per player (prevents spam chaining)

---

## GPL System Technical Design

### Formula
Base GPL + (Level × 10) + (Mastery total / 5) + (Equipment bonus) + (Resonance / 100)

Starting: 100
Typical Mastered-tier player: 2000-5000
Top 1%: 10000+
Resonance-veterans: Infinite (scales visually)

### Layered Death Loss
```
lossMultiplier = math.clamp(killerGPL / victimGPL, 0.5, 2.0)
lossAmount = math.min(victimGPL * 0.05, recentSessionGPL * 0.10) / lossMultiplier
```

If killer is half victim's GPL → 2x loss multiplier (bigger loss for upset)
If killer equal → 1x (moderate loss)
If killer double → 0.5x (small loss)

Never lose more than 5% total GPL or 10% of session's earned GPL.

### Aura Pressure
If `attackerGPL > victimGPL * 1.5`:
- Attacker stamina drain rate: 2x
- Applied server-side during combat state

If `attackerGPL < victimGPL * 0.5`:
- Successful Vital 5 hit: Mastery boost +0.5%
- Winning the fight: +50 Honor, +10% GPL gain

---

## Honor/Karma System Technical Design

### Range: -100 to +100

### Trigger Points
| Action | Honor Change |
|---|---|
| Defend new player from ganker | +5 |
| Complete village quest | +3 |
| Fair PvP win (no ganking) | +1 |
| Train new player (Sensei) | +10 |
| Gank new player (3+ GPL tiers below) | -10 |
| Betray clan | -25 |
| Kill same player 3+ times in 10 min | -5 per extra |
| Perform dark ritual / serve Architect | -15 |

### Effects
- Honor ≥ 50: NPC 10% discounts, exclusive quests, village promotions
- Honor ≥ 0: Normal interactions
- Honor < -50: Dark NPC recruiter appears, rogue path accessible
- Honor < -80: Villages become hostile on sight
- Profile card display (toggleable)

---

## Momentum System Technical Design

### Velocity Damage Scaling
```lua
local speed = rootPart.AssemblyLinearVelocity.Magnitude
local velocityMultiplier = math.clamp(speed / 50, 1.0, 1.5)
local finalDamage = baseDamage * velocityMultiplier
```

Walking (16 speed): 1.0x
Sprinting (28 speed): 1.15x
Dashing (80 speed): 1.5x
Fall + sprint: up to 1.5x cap

Only certain moves have `velocityScaling = true` in MoveDefinitions. Flying Kick, Dropkick, specific techniques.

---

## Testing Protocol (Each Week)

1. Studio solo test — verify code runs without errors
2. Studio Server+Clients test — verify client/server communication
3. Publish to private game — test with real device
4. Phone + PC test — real multiplayer verification
5. F9 developer console log review
6. Commit progress to GitHub with descriptive message

---

## Files To Never Touch During Phase 2

Phase 1 code is stable. Do not modify unless Phase 2 feature requires it:
- CombatStateMachine.lua (may need new states added, that's OK)
- GuardSystem.lua (may need element-aware blocking added)
- DashHandler.lua (stable, leave alone)
- GrappleHandler.lua (stable, leave alone)
- SubstitutionHandler.lua (stable, leave alone)

---

## Phase 2 Success Criteria

Phase 2 is complete when:
- [ ] Fire, Water, Grass techniques all functional
- [ ] Element interactions working (burn traps, steam, absorb)
- [ ] Vital 5 node hits detected and debuffs applied
- [ ] GPL tracked persistently across sessions
- [ ] Honor system functional with NPC responses
- [ ] Momentum damage verified in testing
- [ ] Stamina economy feels balanced (testers report)
- [ ] Two-device multiplayer test passes all new features
- [ ] No Phase 1 regressions
- [ ] GitHub committed with Phase 2 milestone tag

Then proceed to Phase 3.
