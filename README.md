# Spored

A top-down Roblox organism-builder game. Players control a customizable organism, equip mutation parts, and battle AI enemies in a server-authoritative PvE loop.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Installation](#2-installation)
3. [Launching Rojo and Connecting Studio](#3-launching-rojo-and-connecting-studio)
4. [Project Structure](#4-project-structure)
5. [System Overview](#5-system-overview)
6. [Controls and Hotkeys](#6-controls-and-hotkeys)
7. [Testing Guide](#7-testing-guide)
8. [Troubleshooting](#8-troubleshooting)

---

## 1. Prerequisites

| Tool | Version | Install |
|---|---|---|
| [Git](https://git-scm.com/) | any | https://git-scm.com/downloads |
| [Aftman](https://github.com/LPGhatguy/aftman) | latest | https://github.com/LPGhatguy/aftman/releases |
| [Rojo](https://rojo.space/) | 7.7.0-rc.1 | installed via Aftman (see below) |
| [Roblox Studio](https://create.roblox.com/landing) | latest | https://create.roblox.com/landing |
| [Rojo Studio Plugin](https://create.roblox.com/marketplace/asset/1503141663) | latest | Roblox Marketplace (link above) |

---

## 2. Installation

### 2a. Clone the repository

```bash
git clone https://github.com/Stevie5104/Spored.git
cd Spored
```

### 2b. Install Rojo via Aftman

Aftman manages the exact Rojo version pinned in `aftman.toml` (7.7.0-rc.1).

```bash
# Install Aftman itself (one-time, follow the instructions at the link above)
# Then, from the project root:
aftman install
```

This downloads the `rojo` binary into `.aftman/bin/` and makes it available in your shell for this project.

> **Alternative (no Aftman):** Download the Rojo 7.7.0-rc.1 binary directly from
> https://github.com/rojo-rbx/rojo/releases/tag/v7.7.0-rc.1 and place it somewhere on your `PATH`.

### 2c. Install the Rojo Studio Plugin

1. Open Roblox Studio.
2. Navigate to the [Rojo plugin page](https://create.roblox.com/marketplace/asset/13916111412) in your browser and click **Get Plugin**, or search "Rojo" in Studio's Plugin Manager.
3. Install it. You will see a **Rojo** button appear in the Studio ribbon.

---

## 3. Launching Rojo and Connecting Studio

### 3a. Build a place file (optional, first-time setup)

If you want a saved `.rbxlx` place file as a starting point, run:

```bash
rojo build -o "Spored.rbxlx"
```

Then open `Spored.rbxlx` in Roblox Studio.

### 3b. Start the Rojo dev server

```bash
rojo serve
```

Expected output:

```
Rojo server listening on port 34872
```

Leave this terminal open while you work.

### 3c. Connect the Studio plugin

1. In Roblox Studio, click the **Rojo** button in the ribbon.
2. The address should already read `localhost:34872`. If not, type it in.
3. Click **Connect**.
4. Studio will sync your local `src/` tree into the DataModel immediately.
   Any subsequent file save in your editor will hot-reload in Studio automatically.

### 3d. Play the game

Click **Play** (F5) or **Play Here** in Studio to start a local server session and begin testing.

---

## 4. Project Structure

```
Spored/
├── aftman.toml                          # Toolchain version pin (Rojo 7.7.0-rc.1)
├── default.project.json                 # Rojo project mapping
└── src/
    ├── client/
    │   └── init.client.luau             # Client bootstrap entry point
    ├── server/
    │   └── init.server.luau             # Server bootstrap entry point
    ├── shared/
    │   └── Hello.luau                   # Shared utility example
    ├── ReplicatedStorage/
    │   └── Modules/
    │       ├── BodyData.luau            # Player body definitions and base stats
    │       ├── EnemyData.luau           # Enemy type definitions and drop tables
    │       ├── PartData.luau            # Mutation part definitions and stats
    │       └── TraitData.luau           # Passive trait definitions
    ├── ServerScriptService/
    │   └── Services/
    │       ├── init.server.luau         # Service bootstrapper (loads all services)
    │       ├── CombatService.luau       # Server-authoritative damage and cooldowns
    │       ├── CurrencyService.luau     # Coin balance tracking
    │       ├── EnemyService.luau        # Enemy spawning and AI heartbeat loop
    │       ├── LootService.luau         # Drop table resolution and inventory
    │       ├── PlayerBuildService.luau  # Build equipping and validation
    │       └── AI/
    │           ├── GrazerAI.luau        # Passive wanderer / flee behavior
    │           ├── SpikeWormAI.luau     # Aggressive melee chaser
    │           └── VenomBlobAI.luau     # Ranged poison attacker
    └── StarterPlayer/
        └── StarterPlayerScripts/
            └── Controllers/
                ├── AbilityController.client.luau      # Part activation and aim
                ├── BuildUIController.client.luau      # Build editor GUI
                ├── BuildVisualController.client.luau  # Organism visual rendering
                ├── CameraController.client.luau       # Top-down camera follow
                ├── MovementController.client.luau     # Movement input handling
                └── MovementController.spec.luau       # Unit tests for movement
```

### Rojo DataModel mapping (`default.project.json`)

| Source path | Roblox location |
|---|---|
| `src/shared` | `ReplicatedStorage.Shared` |
| `src/ReplicatedStorage/Modules` | `ReplicatedStorage.Modules` |
| `src/server` | `ServerScriptService.Server` |
| `src/ServerScriptService/Services` | `ServerScriptService.Services` |
| `src/client` | `StarterPlayer.StarterPlayerScripts.Client` |
| `src/StarterPlayer/StarterPlayerScripts/Controllers` | `StarterPlayer.StarterPlayerScripts.Controllers` |

---

## 5. System Overview

### Movement (`MovementController.client.luau`)

Two input modes share the same physics backend:

- **ClickToMove** (default, press `1`): Single-click to walk toward a ground point; hold and drag the mouse to continuously update the destination.
- **WASDMouseAim** (press `2`): WASD keys for movement, mouse cursor for facing direction.

Smooth acceleration (80 units/s²), deceleration with a drag factor of 10× (velocity decays to near-zero within ~0.5 s after input stops), rotation speed 540°/s.

### Camera (`CameraController.client.luau`)

Fixed top-down 2.5D view:

- Camera sits 38 studs above the organism and 5 studs behind.
- 65° downward pitch gives an isometric feel.
- Exponential follow (lerp factor 12) keeps the camera smooth.
- Roblox's default camera is disabled.

### Abilities (`AbilityController.client.luau`)

Client tracks cooldowns locally (read from `PartData.Cooldown`). When a key is pressed the controller:

1. Finds the nearest enemy within a 60° half-cone in the aim direction (dot product threshold: `cos(60°) = 0.5`).
2. Fires the `PartAttack` RemoteEvent to the server with `partId` and target enemy ID.
3. `CombatService` re-validates the request (equipped part, cooldown, range) before applying damage.

### Build System

**Data layer** (`BodyData.luau`, `PartData.luau`, `TraitData.luau`):
Centralises all stats, slot layouts, capacity costs, rarities, and categories.

**Server** (`PlayerBuildService.luau`):
Validates every equip/unequip/body-change. Enforces slot compatibility and body capacity. Broadcasts `BuildChanged` to clients.

**UI** (`BuildUIController.client.luau`, `B` key):
- Left panel: body picker with HP / speed / capacity stats.
- Middle panel: equipped slot grid.
- Right panel: available parts for the selected slot, colour-coded by category.
- Capacity bar turns red when the body is at or over capacity.

**Visuals** (`BuildVisualController.client.luau`):
Renders coloured spheres — one for the body and one per equipped part at slot-specific offsets. Sizes scale with stats. Rebuilds automatically on `BuildChanged`.

### Server Authority (`CombatService.luau`, `PlayerBuildService.luau`, `CurrencyService.luau`)

- All damage calculations run on the server.
- Cooldowns are re-checked server-side with a 0.1 s latency buffer.
- Range checks use 2× the stated range to tolerate latency.
- Build mutations are rejected if a slot is incompatible or capacity would be exceeded.
- Coins are stored in `CurrencyService` and never trusted from the client.

### Enemy AI (`EnemyService.luau` + `AI/`)

`EnemyService` spawns 6 enemies 2 s after startup and runs a heartbeat (~0.1 s ticks) that calls each enemy's AI module:

| Enemy | AI file | Behavior |
|---|---|---|
| Grazer | `GrazerAI.luau` | Wanders randomly; flees at 1.5× speed if player is within 8 studs |
| SpikeWorm | `SpikeWormAI.luau` | Patrols; charges player within 18 studs; melee attacks within 4 studs (1.5 s cooldown) |
| VenomBlob | `VenomBlobAI.luau` | Maintains 6–9 stud distance; fires poison projectiles; drops persistent poison pools |
| HunterCell | *(uses SpikeWorm logic)* | Faster and higher HP aggressive chaser |

### Loot and Currency (`LootService.luau`, `CurrencyService.luau`)

On enemy death, `EnemyService` calls `LootService`, which:

1. Runs weighted random selection from the enemy's drop table.
2. Awards the nearest player within 40 studs coins or a part.
3. Fires `LootDrop` RemoteEvent so the client can display feedback.

Players start with 50 coins. All balances are server-side.

---

## 6. Controls and Hotkeys

| Input | Action |
|---|---|
| `1` | Switch to **ClickToMove** mode |
| `2` | Switch to **WASDMouseAim** mode |
| **Left-click** (ClickToMove) | Move to clicked ground position |
| **Hold left-click + drag** (ClickToMove) | Continuously update move target |
| `W / A / S / D` (WASDMouseAim) | Move organism |
| **Mouse cursor** (WASDMouseAim) | Aim / facing direction |
| `Q` | Activate **Front** slot part |
| `E` | Activate **Core** slot part |
| `R` | Activate **Rear** slot part |
| `F` | Activate **Left** slot part |
| `G` | Activate **Right** slot part |
| `B` | Toggle **Build Editor** UI |

---

## 7. Testing Guide

Use the following checklist after connecting Studio and pressing Play.

### 7.1 Movement

1. **ClickToMove (mode 1):**
   - Press `1` to confirm the mode.
   - Single-click on the baseplate — the organism should walk to that point and stop.
   - Click-and-hold, then drag — the target position should update continuously while the button is held.
   - Release the mouse — movement should stop updating.

2. **WASDMouseAim (mode 2):**
   - Press `2` to switch.
   - Hold `W` — organism moves forward.
   - Move the mouse — organism rotates to face the cursor on the ground plane.
   - Combine movement and rotation freely.

3. **Mode switching:**
   - Switch between `1` and `2` several times mid-movement. No position glitches or rotation snaps should occur.

### 7.2 Camera

- Camera should always sit above and slightly behind the organism at ~38 studs height.
- Moving in any direction should keep the organism near the centre of the screen.
- Camera follows smoothly — no instant jumping.

### 7.3 Abilities

1. Press `B` and equip a part to a slot (e.g. **BiteJaw** → **Front**).
2. Close the Build UI (`B`).
3. Move near an enemy (Grazer or SpikeWorm).
4. Press `Q` (Front slot) while facing the enemy — a `PartAttack` event fires.
5. **Expected result:** If the enemy is within range and within the 60° half-cone aim angle, it takes damage. Check the Studio Output window for server-side log messages confirming the hit.
6. **Cooldown test:** Rapid-press `Q` — additional presses within the cooldown window should be silently ignored (no double damage on the server).

### 7.4 Build Editor

1. Press `B` to open the Build UI.
2. **Body switching:**
   - Click each body in the left panel (StarterBlob, ArmoredShell, SwiftNucleus, VenomMantle).
   - Stats (HP / speed / capacity) in the panel should update.
   - The organism's visual sphere should change size and colour immediately.
3. **Equip a part:**
   - Click a slot in the middle panel (e.g. Front).
   - The right panel shows compatible parts for that slot.
   - Click a part to equip it — the slot label updates and the capacity bar increases.
4. **Over-capacity test:**
   - Fill all slots until the capacity bar turns red and the body is at or over capacity.
   - The server should reject further equips; the UI should reflect this.
5. **Unequip:**
   - Click an occupied slot — the part is removed, capacity bar decreases.

### 7.5 Visual Feedback

- After equipping parts, coloured spheres should orbit the main organism sphere.
- Colours by category: Attack = red, Defense = blue, Movement = teal, Utility = gold.
- Body sphere colour and size changes with each body type.
- All visuals rebuild after re-equipping or switching body.

### 7.6 PvE Loop

1. **Spawn check:** After pressing Play, wait ~2 seconds — 6 enemies should appear (visible as coloured spheres on the baseplate).
2. **AI behaviour:**
   - Walk near a **Grazer** (green/neutral) — it should flee.
   - Walk near a **SpikeWorm** — it should chase and deal melee damage.
   - Stand in range of a **VenomBlob** — it should fire projectiles and leave poison pools.
3. **Kill an enemy:**
   - Equip an attack part and press the corresponding ability key while facing the enemy.
   - Repeat until the enemy's HP reaches 0 — the model is removed.
4. **Loot drop:**
   - A `LootDrop` RemoteEvent fires to your client — check Studio Output for the log.
   - Your coin balance should increase, or a part should be added to your inventory (check `LootService` logs in Output).
5. **Collect coins:**
   - Coins are awarded automatically to the nearest player within 40 studs when the enemy dies.

### 7.7 Server-Side Validation

1. **Range exploit test:**
   - Stand far from all enemies (> 30 studs) and press an ability key.
   - The server should log a range-validation failure in Output — no damage applied.
2. **Cooldown exploit test:**
   - Rapidly fire the same ability key from a Lua script injector or repeated client calls.
   - The server re-checks cooldown; only the first hit within the cooldown window is applied.
3. **Build over-capacity test:**
   - Try to invoke `EquipPart` (via RemoteFunction) with a part that exceeds body capacity.
   - `PlayerBuildService` returns `false` and logs the rejection.

### 7.8 Rojo Sync / Iteration Loop

1. With `rojo serve` running and Studio connected, open any source file (e.g. `src/ReplicatedStorage/Modules/PartData.luau`) in your editor.
2. Change a stat value (e.g. a damage number) and save the file.
3. Studio should hot-reload the script within 1–2 seconds — no manual re-sync needed.
4. Press **Play** to verify the change takes effect immediately.

---

## 8. Troubleshooting

### Rojo plugin shows "Not connected"

- Make sure `rojo serve` is running in the **project root** (the folder containing `default.project.json`).
- Confirm the plugin address is `localhost:34872`.
- Check your firewall / antivirus — it may block localhost connections. Add an exception for port 34872.
- Restart Studio and reconnect.

### Scripts appear in the wrong location in Studio

- The file → DataModel mapping is defined in `default.project.json`. Verify you haven't moved files outside their mapped directories.
- Run `rojo build -o "Spored.rbxlx"` to get a fresh place file with the correct structure.

### Studio output shows "module not found" errors

- This usually means Rojo is not connected or the script path in a `require()` call doesn't match the DataModel path.
- Check that the `require` path matches the Rojo mapping table in [Section 4](#4-project-structure).

### Enemies don't spawn

- Look for errors from `EnemyService` in the Output window.
- Confirm `ServerScriptService.Services` contains `init.server.luau` and all service files after Rojo sync.

### Abilities do nothing / no damage appears

- Ensure you have a part equipped in the slot you are pressing (open Build UI with `B`).
- Check Output for server-side validation messages from `CombatService` (range failure, cooldown, or "part not equipped").

### Build UI doesn't open

- Press `B` while the game is running (not in edit mode).
- Check Output for errors in `BuildUIController`.

### aftman install fails

- Make sure the Aftman binary is on your system `PATH` after installation.
- On Windows, restart your terminal after installing Aftman to pick up the new `PATH` entry.
- Alternatively, install Rojo directly: https://github.com/rojo-rbx/rojo/releases/tag/v7.7.0-rc.1

---

For more help, check out the [Rojo documentation](https://rojo.space/docs).