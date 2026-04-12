# Cutscene System — April 11 2026

## Overview

The cutscene system drives scripted in-game sequences: characters moving to positions, playing animations, and delivering dialogue. It is data-driven — each cutscene is defined in a JSON file and played back by the engine without bespoke GDScript per sequence.

---

## Files

| File | Role |
|---|---|
| `scripts/autoload/cutscene_manager.gd` | Autoload singleton. Owns the registry, spawns actors, drives movement, triggers dialogue. |
| `scripts/tools/cutscene.gd` | Per-instance controller Node2D placed inside a scene. Handles local spawning and cleanup for one cutscene. |
| `scenes/tools/cutscene.tscn` | Scene wrapping `cutscene.gd`. Instantiated at runtime by `start_cutscene_original()`. |
| `scenes/tools/cutscene_marker.tscn` | Lightweight Node2D used as a named position marker inside editor-placed cutscene scenes. |
| `data/cutscenes/<location>/cs_<id>.json` | One file per cutscene. Naming convention: `cs_` prefix, `.json` suffix. |

---

## Data Format — `cs_<id>.json`

```json
{
  "cutscene_id": "intro_to_poison",
  "description": "Human-readable note",
  "location": "dorm_room",
  "one_time": true,
  "auto_trigger": false,
  "priority": 1.0,
  "triggers": [],
  "unlocks": [],
  "player_start_marker": "A0",
  "dialog_file": "intro_to_poison",
  "dialog_title": "start",
  "marker_positions": {
	"A0": { "x": 159.0, "y": 177.0 },
	"P0": { "x": 251.0, "y": 104.0 }
  },
  "npcs": [
	{
	  "id": "poison",
	  "character_id": "poison",
	  "character_name": "Poison",
	  "scene_path": "res://scenes/npc.tscn",
	  "parent": "z_objects",
	  "marker": "P0",
	  "initial_animation": "idle_up",
	  "dialogue_file": "poison.dialogue",
	  "dialogue_title": "start",
	  "temporary": false
	}
  ],
  "props": []
}
```

### Key fields

| Field | Type | Notes |
|---|---|---|
| `cutscene_id` | String | Must be unique. Inferred from filename if omitted (`cs_foo.json` → `foo`). |
| `location` | String | Scene name. Used by `trigger_cutscene_in_location()` and `check_location_cutscenes()`. |
| `one_time` | bool | If `true`, cannot replay after `cutscene_seen_<id>` tag is set. Default `true`. |
| `auto_trigger` | bool | If `true`, `check_location_cutscenes()` fires it automatically on scene load. |
| `triggers` | Array[String] | All tags must be present in GameState for `can_trigger_cutscene()` to pass. |
| `unlocks` | Array[String] | Tags set in GameState when the cutscene starts. |
| `player_start_marker` | String | Player is teleported to this marker before dialogue starts. |
| `dialog_file` | String | Dialogue file name (no extension). Passed to `DialogSystem.start_dialog()`. |
| `dialog_title` | String | Node title within the dialogue file. |
| `marker_positions` | Dict | Runtime Node2D markers created at named `{x, y}` positions. Cleaned up after cutscene. |
| `npcs[].parent` | String | Layer name resolved via `GameState.get_layer()`. Common values: `"z_objects"`, `"floor"`. |
| `npcs[].marker` | String | Key into `marker_positions`; sets the NPC's spawn position. |
| `npcs[].temporary` | bool | If `false`, NPC persists after the cutscene ends. |

---

## CutsceneManager — How It Works

### Registry loading (`_ready`)

On startup, `_load_cutscene_registry()` walks `data/cutscenes/` recursively and loads every file matching `cs_*.json`. Files are stored in `stored_cutscenes[cutscene_id]`. Subdirectory structure is for organisation only — all IDs share a flat namespace.

### Triggering a cutscene

**Primary path — `start_cutscene(cutscene_id)`**:

1. `can_trigger_cutscene()` checks required tags and the `one_time` / `cutscene_seen_*` guard.
2. `cleanup_active_cutscene()` removes any in-progress cutscene.
3. Runtime markers are created as temporary Node2Ds in the current scene.
4. NPCs are instantiated from their `scene_path`, positioned via marker or direct coordinates, scaled to match the parent layer, and added to the appropriate layer node.
5. Props are instantiated similarly and added to `z_Objects`.
6. Player is teleported to `player_start_marker` if set.
7. `DialogSystem.start_dialog()` is called with `dialog_file` / `dialog_title`.
8. `cutscene_seen_<id>` tag and all `unlocks` tags are set in GameState.
9. Signal `cutscene_started` is emitted.

**Legacy path — `start_cutscene_original(cutscene_id)`**: Instantiates a `cutscene.tscn` node controller and adds it to the current scene. The `cutscene.gd` instance then handles its own spawning/cleanup independently. This path is preserved but superseded by the primary path above.

### Cleanup

When `_on_cutscene_dialogue_finished()` fires (connected to `DialogSystem.dialog_finished`):
- All NPCs in `active_cutscene_npcs` are freed.
- All props in `active_cutscene_props` are freed.
- All runtime markers in `cutscene_markers` are freed.
- `GameState.set_current_npcs()` and `GameState.set_current_markers()` are called to refresh GameState's references.
- Signal `cutscene_finished` is emitted.

### Character movement (`move_character`, `_process`)

`move_character(character_id, target, animation, speed, stop_distance, time)` registers a movement in `active_movements`. `_process(delta)` ticks all active movements each frame via `_process_movement()`, calling `move_and_slide()` on CharacterBody2D actors or direct position updates on Node2D actors. When a character reaches its destination (within `stop_distance` pixels), `movement_completed` signal is emitted and the entry is removed.

`move_character_to_marker(character_id, marker_id, run)` is a convenience wrapper that resolves a named marker via `GameState.get_marker_by_id()`.

`face_to(actor, target)` resolves both actor and target to nodes (by string ID or direct reference) and calls `CharacterBase.face_target()`.

### DialogSystem integration

`dialog_system.gd` intercepts three custom dialogue mutations and forwards them to CutsceneManager:

| Mutation | CutsceneManager call |
|---|---|
| `move_character` | `CutsceneManager.move_character(...)` |
| `play_animation` | `CutsceneManager.play_animation(...)` |
| `wait_for_movements` | awaits `CutsceneManager.movement_completed` signal |

This means movement and animation commands can be written directly in `.dialogue` files as `do` statements.

---

## `cutscene.gd` — Per-Instance Controller

`cutscene.gd` (attached to `scenes/tools/cutscene.tscn`) is used by the legacy `start_cutscene_original` path. It self-contained: reads its own `cutscene_id`, fetches data from CutsceneManager, spawns NPCs into `z_Objects`, collects marker nodes, and starts dialogue on its own. Cleanup (`cleanup_cutscene`) only frees NPCs/props with `temporary: true`.

Helper methods available on a cutscene instance:
- `add_npc(...)` / `add_prop(...)` — programmatic setup before `start_cutscene()`
- `get_spawned_npc(id)` / `get_spawned_prop(id)` — access to spawned entities during playback
- `get_marker_position(name)` — resolve a marker to a world position

---

## Triggering from Game Code

**From a location script** (e.g. `dorm_room.gd`):
```gdscript
CutsceneManager.start_cutscene("intro_to_poison")
```

**Auto-trigger on scene load** — call from the location's `_ready()`:
```gdscript
await get_tree().create_timer(0.2).timeout
CutsceneManager.check_location_cutscenes("dorm_room")
```
Only cutscenes with `"auto_trigger": true` will fire, one at a time.

**From a dialogue `do` statement**:
```
do CutsceneManager.trigger_cutscene_by_dialogue("some_cutscene_id")
```

**Location-gated trigger**:
```gdscript
CutsceneManager.trigger_cutscene_in_location("some_id", "campus_quad")
```
Will silently skip if the required location doesn't match.

---

## Adding a New Cutscene

1. Create `data/cutscenes/<location>/cs_<your_id>.json` following the data format above.
2. Write the dialogue in `data/dialogues/<your_id>.dialogue` (or reuse an existing file with a new title node).
3. Define marker positions in `marker_positions` using the Godot scene editor to find the right coordinates.
4. List any NPCs that need to be spawned, or leave `"npcs": []` if they're already in the scene.
5. Set `"triggers"` to any GameState tags that must be present, and `"unlocks"` for tags to set on start.
6. Call `CutsceneManager.start_cutscene("your_id")` from the appropriate location script or use `"auto_trigger": true` with `check_location_cutscenes()`.

No code changes are required unless the cutscene needs custom logic beyond movement, animation, and dialogue.

---

## Known Issues / Notes (as of April 2026)

- Several `_fname` constants inside `cutscene_manager.gd` are copy-paste errors — many functions after `_start_cutscene_dialogue` incorrectly set `_fname = "_spawn_cutscene_props"`. This affects debug output labelling only, not runtime behaviour.
- `start_cutscene_original()` and `start_cutscene()` overlap in responsibility. The original path instantiates a full `cutscene.tscn` controller node; the primary path does everything inline in CutsceneManager. Prefer the primary path for new cutscenes.
- NPC scale is computed as `player.scale / parent_node.scale / parent_node.get_parent().scale` — this works for the current scene hierarchy but is fragile if the hierarchy changes.
- `queue_movement()` populates `movement_queue` but `_process_movement_queue()` is never defined in the file. The queue system is incomplete.
