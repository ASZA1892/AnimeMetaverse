# Phase 1 Cleanup — Before Starting Phase 2

Do these steps in order before beginning Phase 2 work.

---

## 1. Delete Broken Files

These were removed during polish attempts but may still exist in your local project. Check and delete:

- `src/client/Combat/TargetLockController.client.lua` — delete entirely
- `src/client/Combat/TiltController.client.lua` — delete entirely

These will be rebuilt properly in Phase 2.5 (polish pass after Phase 2 mechanics complete).

---

## 2. Verify Working Files

Confirm these files exist and are in their working state:

### Server (src/server/Combat/)
- CombatHandler.server.lua ✓
- CombatStateMachine.lua ✓
- GuardSystem.lua ✓
- DashHandler.lua ✓
- SubstitutionHandler.lua ✓
- GrappleHandler.lua ✓

### Client Combat (src/client/Combat/)
- CombatController.client.lua ✓
- CameraShaker.lua ✓
- DashController.client.lua ✓
- SubstitutionController.client.lua ✓
- SprintController.client.lua ✓

### Client Animations (src/client/Animations/)
- AnimationLoader.client.lua ✓

### Client UI (src/client/UI/)
- GuardUI.client.lua ✓
- StaminaUI.client.lua ✓
- MobileUI.client.lua ✓

### Shared (src/shared/)
- Types/CombatActions.lua ✓
- Types/MoveDefinitions.lua ✓
- Types/constants.lua ✓
- StaminaState.lua ✓

---

## 3. Add New Files To Project Root

Copy these into `C:\Dev\AnimeMetaverse\` root:

- `CLAUDE.md` — Claude's permanent context
- `.cursorrules` — Cursor AI rules
- `Phase1_Handoff.md` — Phase 1 architecture reference
- `Phase2_Plan.md` — Phase 2 build plan
- `GameDesignDecisions.md` — Locked-in design decisions
- `Phase1_Cleanup.md` — This document

---

## 4. Update default.project.json

Ensure no references to removed files. Your current structure should match:

```json
{
  "name": "AnimeMetaverse",
  "tree": {
    "$className": "DataModel",
    "ReplicatedStorage": {
      "$className": "ReplicatedStorage",
      "Shared": { "$path": "src/shared" }
    },
    "ServerScriptService": {
      "$className": "ServerScriptService",
      "Combat": {
        "$className": "Folder",
        "CombatHandler": { "$path": "src/server/Combat/CombatHandler.server.lua" },
        "CombatStateMachine": { "$path": "src/server/Combat/CombatStateMachine.lua" },
        "GuardSystem": { "$path": "src/server/Combat/GuardSystem.lua" },
        "DashHandler": { "$path": "src/server/Combat/DashHandler.lua" },
        "SubstitutionHandler": { "$path": "src/server/Combat/SubstitutionHandler.lua" },
        "GrappleHandler": { "$path": "src/server/Combat/GrappleHandler.lua" }
      }
    },
    "StarterPlayer": {
      "$className": "StarterPlayer",
      "StarterPlayerScripts": {
        "$className": "StarterPlayerScripts",
        "Combat": { "$path": "src/client/Combat" },
        "Animations": { "$path": "src/client/Animations" }
      }
    },
    "StarterGui": {
      "$className": "StarterGui",
      "UI": { "$path": "src/client/UI" }
    }
  }
}
```

---

## 5. Verify Animations Are Disabled

Animations were disabled in CombatController to prevent log spam from failed placeholder IDs. Confirm these lines are commented out in `src/client/Combat/CombatController.client.lua`:

```lua
-- Animations disabled until custom Moon Animator anims are ready
-- if AnimationLoader then AnimationLoader.playAttackAnimation(moveId) end
```

Animations will be re-enabled when custom ones are made before launch.

---

## 6. Test Clean Build

1. Start Rojo: `C:\Dev\Tools\rojo.exe serve`
2. Open Studio, connect Rojo
3. Press Play
4. Verify server output shows all 9 modules loaded:
   - Shared, Types, CombatActions, constants, MoveDefinitions
   - CombatStateMachine, GuardSystem, DashHandler
   - SubstitutionHandler, GrappleHandler
5. Verify client output shows all controllers initialized:
   - DashController, SubstitutionController, SprintController
   - CombatController, AnimationLoader, GuardUI, StaminaUI
6. Hit a dummy — confirm damage applies
7. If all pass: commit and push to GitHub

---

## 7. Commit Message Template

```
Phase 1 complete — handoff documents added

- Combat pipeline verified on multiplayer (PC + mobile)
- All systems: hits, grapple, substitution, dash, sprint, camera shake
- Knockback replicating cleanly via client event
- Added CLAUDE.md, .cursorrules, Phase docs
- Removed broken TargetLock and Tilt controllers (rebuild in Phase 2.5)

Ready to begin Phase 2: Element System
```

---

## 8. New Chat Instructions

When opening the new chat to begin Phase 2:

1. Set up Claude Project with these documents:
   - CLAUDE.md (project instructions in sidebar)
   - Phase1_Handoff.md (knowledge base)
   - Phase2_Plan.md (knowledge base)
   - GameDesignDecisions.md (knowledge base)

2. Start new chat with this message:

```
I'm Alan, continuing work on The Anime Metaverse. Phase 1 is complete and verified on multiplayer. I'm ready to begin Phase 2 — Element System.

Please read CLAUDE.md, Phase1_Handoff.md, Phase2_Plan.md, and GameDesignDecisions.md first. Then let's start with the Element State module as outlined in Week 1 of the Phase 2 Plan.
```

3. The new Claude will have full context instantly with zero setup cost.

---

## 9. Repository Checklist

Before closing this chat:

- [ ] Delete TargetLockController and TiltController if they still exist
- [ ] Add all 6 new documents to project root
- [ ] Update default.project.json to match clean state
- [ ] Test clean build in Studio
- [ ] Commit and push to GitHub
- [ ] Create Claude Project
- [ ] Upload documents to Claude Project knowledge base
- [ ] Start new chat with intro message above

Once checklist complete, Phase 1 is officially closed. Phase 2 begins.
