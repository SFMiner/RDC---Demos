# Blank RPG Framework

A flexible RPG/Visual Novel framework built in Godot 4.4+ for creating narrative-driven games with dialogue, inventory, quests, and relationship systems.

## Project Overview

This project provides a foundation for building story-driven games with character interactions, player choices, and dynamic world responses. It combines core RPG systems including dialogue management, inventory handling, quest tracking, and NPC relationships.

## Core Systems

### Dialog System
Handles character conversations and branching dialogue trees. Dialogue data is stored in `.dialogue` files and processed by the Dialogue Manager addon.

### Relationship System
Tracks the player's relationships with NPCs, evolving based on interactions, dialogue choices, and special events.

### Inventory System
Manages the player's items and equipment.

### Quest System
Tracks objectives, progress, and quest completion.

### Memory System
Records player discoveries and story elements that unlock over time.

## Getting Started

### Prerequisites
- Godot 4.4 or later

### Project Setup
1. Open the project in Godot 4.4
2. Go to Project > Project Settings > AutoLoad tab
3. Add the following autoloads in this exact order:
   - GameController: `res://scripts/autoload/game_controller.gd`
   - DialogSystem: `res://scripts/autoload/dialog_system.gd`
   - RelationshipSystem: `res://scripts/autoload/relationship_system.gd`
   - InventorySystem: `res://scripts/autoload/inventory_system.gd`
   - SaveLoadSystem: `res://scripts/autoload/save_load_system.gd`
4. Go to Project > Project Settings > Input Map tab
   - Add a new action called "interact"
   - Add key bindings: E and Space
   - Configure movement inputs:
     - ui_up: W, Up Arrow
     - ui_down: S, Down Arrow
     - ui_left: A, Left Arrow
     - ui_right: D, Right Arrow
5. Set the main scene to `res://scenes/game.tscn`
6. Run the project

### Troubleshooting
- If you see "GameController not found" errors, double-check that all autoloads are properly configured
- Make sure GameController is listed first in the autoload order

## Project Structure

```
blank-rpg/
├── assets/           # Game assets (images, sounds, fonts, etc.)
├── scenes/           # Game scenes and UI components
├── scripts/          # Game logic and systems
│   ├── autoload/     # Singleton systems
│   ├── ui/           # UI scripts
│   ├── world/        # World-related scripts
│   └── player/       # Player-related scripts
├── data/             # Game data in JSON and dialogue format
│   ├── characters/   # Character definitions
│   ├── dialogues/    # Dialogue files
│   ├── quests/       # Quest definitions
│   └── memories/     # Memory system data
└── addons/           # Third-party addons
```

## Key Features

- **Dialogue Manager Integration**: Full support for branching conversations
- **Character Customization**: Define custom fonts, colors, and personalities
- **Flexible Quest System**: Create complex objectives and multi-step quests
- **Save/Load System**: Multiple save slots with automatic persistence
- **Tag-Based Memory System**: Track player discoveries and story progress
- **Relationship Tracking**: Build and change NPC relationships dynamically
- **Inventory Management**: Handle items, equipment, and special pickups
- **Navigation System**: Click-to-navigate and keyboard movement support

## Development Notes

This framework is designed to be modular and extensible. Create your own stories by:
1. Adding character data to `data/characters/`
2. Writing dialogue in `data/dialogues/`
3. Defining quests in `data/quests/`
4. Creating locations in `scenes/world/locations/`
5. Implementing custom logic in `scripts/world/` as needed

## Credits

Developed by Sean Miner using the Godot Engine
