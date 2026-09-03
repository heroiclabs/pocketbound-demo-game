# Pocketbound - a demo game by Heroic Labs

A grid-based puzzle game built with Godot 4.6 and a Nakama 3.37.0 backend. Players create levels with a tile editor and solve them by sliding tiles and walking a character from start to end. The server (Go plugin) handles level storage and per-level leaderboards.

For a full walkthrough, see the [documentation](https://heroiclabs.com/docs/sample-projects/games/pocketbound/).

## Getting started

**Prerequisites:** Docker, Godot 4.6

### Server

```bash
docker-compose up              # Start Nakama (port 7350) + PostgreSQL (port 5432)
docker-compose up --build      # Force rebuild after Go code changes
```

Nakama console: http://localhost:7351

The Go module is a Nakama plugin, so it can't be built standalone. Use `go vet ./...` to check for errors.

### One-time username lowercase migration

If you need to normalize all existing usernames in Postgres:

```bash
task migrate:usernames-lowercase
```

This migrates every row in `users.username` to lowercase. If two usernames differ only by case, one keeps the canonical lowercase name and the others receive deterministic lowercase fallback names.

### Client

Open the project in the Godot 4.6 editor and press Play. Main scene: `res://scenes/main.tscn`.

**Autoloads** (registered in `project.godot`):

| Name | Script | Role |
|------|--------|------|
| `Nakama` | `addons/com.heroiclabs.nakama/Nakama.gd` | Nakama client factory |
| `OnlineSession` | `auth/nakama_session.gd` | Auth session + `call_rpc()` wrapper |

## Project structure

```
scenes/
  main.tscn / main.gd             Navigation controller (Menu ↔ Creator ↔ Player)
  space_background.tscn            Reusable space background prefab
  VFX/                             Particle effect prefabs (win, portal, placement)
auth/
  nakama_session.gd                OnlineSession autoload — auth + RPC wrapper
main_menu/
  main_menu.gd                     Main menu UI (level list, friends, create/play)
shared/
  component_registry.gd            Loads shared/component_registry.json on the client
  component_registry.json          Tile component definitions (shared by client + server)
level_creator/
  level_creator.tscn / scripts/    Self-contained level editor module
level_player/
  level_player.tscn / scripts/     Self-contained puzzle gameplay module
main.go                            Nakama Go plugin — all server RPCs + validation
docker-compose.yml                 Postgres 18 + Nakama 3.37.0
Dockerfile                         Multi-stage build: pluginbuilder → nakama runtime
assets/
  Fonts/                           Pixelify Sans, Plus Jakarta Sans
  sprites/Spritesheets/            Atlased tile and UI textures
addons/com.heroiclabs.nakama/      Nakama GDScript client addon
```

## Architecture

### Navigation

`main.gd` manages three screens via a `Screen` enum (`MENU`, `CREATOR`, `PLAYER`). Both modules start hidden; navigation toggles `visible` and propagates `set_process`/`set_process_unhandled_input` through the subtree. All transitions are signal-driven:

```
MainMenu.create_level_requested  → LevelCreator.start_new_level() → CREATOR
MainMenu.play_level_requested    → LevelPlayer.load_level()       → PLAYER
MainMenu.edit_level_requested    → LevelCreator.edit_level()       → CREATOR
LevelCreator.play_requested      → LevelPlayer.load_level()       → PLAYER
LevelPlayer.edit_level_requested → LevelCreator.edit_level()       → swap PLAYER→CREATOR
LevelPlayer.main_menu_requested  → navigate_out()                  → MENU
LevelCreator.main_menu_requested → navigate_out()                  → MENU
```

### TileWorld ECS

`level_player/scripts/tile_world.gd` is a lightweight entity-component system that serves as the **single source of truth** for all tile state. Both the creator and player modules operate on a TileWorld instance.

- **Entities** are stored in parallel arrays: `pos_x`, `pos_y`, `sprites`, `_dead`, `move_signature`.
- **Components** are tag-based strings stored in a `components` Dictionary (name → Array[int] of entity IDs) with a fast lookup index.
- **Command buffering:** all structural writes are deferred into `_commands` and applied on `commit()`. Both module roots call `world.commit()` every `_process()` frame, so multiple mutations can be batched freely.
- **Movement rules** (`can_move()`) evaluate a configurable `move_rule_table` in order: target exists → target walkable → target not blocked → source exit direction bitmask → target entry direction bitmask.
- **`move_signature`** bitmask is maintained automatically when direction components (north/east/south/west) are added or removed.
- **Serialization:** `to_dict()` compacts entities into `{grid_size, x:[], y:[], sprite:[], walkable:[], north:[], ...}`. `from_dict()` reconstructs in reverse. This is the format stored on the server.

### GridManager

`level_player/scripts/grid_manager.gd` is a coordinate and presentation layer **shared by both modules** (both `.tscn` files reference the same script). It maps entity IDs to scene nodes and converts between grid and world coordinates, but always delegates occupancy queries to TileWorld via `world.entity_at(x, y)`.

- Grid coordinates: `(0,0)` is top-left. `grid_to_world()` returns the cell center in world pixels.
- Edge tiles (START/END) sit outside the grid boundary (e.g. `(-1, 2)`) — not stored in the grid but `grid_to_world()` still computes valid positions for them.
- Cell size: `PUZZLE_SIZE / grid_size` (512px / grid_size), recomputed dynamically in `_layout_for_viewport()`.
- Constants in `level_player/scripts/level_config.gd`: `PUZZLE_SIZE=512`, `GRID_ORIGIN=(100,100)`, `SLIDE_DURATION=0.15`.

### Component registry

`shared/component_registry.json` defines 8 tile components shared between client and server:

| ID | Name | Kind | Bit |
|----|------|------|-----|
| 1 | walkable | tag | — |
| 2 | blocked | tag | — |
| 3 | start | tag | — |
| 4 | end | tag | — |
| 5 | north | direction | 1 |
| 6 | east | direction | 2 |
| 7 | south | direction | 4 |
| 8 | west | direction | 8 |

The client loads this via `scripts/component_registry.gd` (lazy static class). The Go server embeds it at build time (`//go:embed shared/component_registry.json`). Any component changes must update this shared file.

### Level player module

Scene tree:
```
LevelPlayer (Node2D)         — level_player.gd
├── Fullbackground (Sprite2D)
├── GridManager (Node)       — grid_manager.gd
├── GridVisual (Node2D)      — grid_visual.gd (draws grid with _draw())
├── SlideManager (Node)      — slide_manager.gd
└── ObjectContainer (Node2D) — parent for PlaceableObject instances
```

`PlayerController` and the player `Sprite2D` are added dynamically in `_spawn_player()`.

**Gameplay:** simultaneous WASD movement + mouse tile sliding.
- `PlayerController` handles arrow/WASD input, validates moves against the TileWorld, emits `reached_end` and `moved` signals.
- `SlideManager` handles mouse drag-drop of tiles to adjacent empties. `locked_cell` prevents moving the tile under the player.
- `PlaceableObject` has `TileType { REGULAR, START, END }`. Regular tiles live in the grid; start/end are edge tiles.
- On reaching the end tile: input freezes, score is submitted via RPC, a completion modal shows time/slides/rank.

**Level load flow:**
1. `load_level(key, owner_id)` calls `_cleanup()`, awaits `OnlineSession.session_ready` if needed
2. `call_rpc("get_level", ...)` returns parsed JSON
3. `world.from_dict(value)` populates the TileWorld ECS
4. `_build_tiles_from_world()` instantiates scene nodes for each entity
5. `_spawn_player()` creates the player sprite and controller

### Level creator module

Scene tree:
```
LevelCreator (CanvasLayer)       — level_creator.gd
├── GridManager (Node)           — grid_manager.gd (same script as player)
├── CreatorGridVisual (Node2D)   — creator_grid_visual.gd
├── CreatorDragManager (Node)    — creator_drag_manager.gd
├── ObjectContainer (Node2D)
└── TilePalette (PanelContainer) — tile_palette.gd
```

**Tile palette** has two tabs: "Design" (tile grid with 16 room shapes + Start/End) and "Level Info" (name, grid size 2–4, description).

**Edge slot system:** START and END tiles are placed outside the grid boundary (`x == -1`, `x == grid_size`, etc.) tracked in `CreatorDragManager.edge_objects`. The creator grid visual draws edge slot rectangles around the grid border.

**Room tiles** (16 shapes) map sprite names to component sets (WALKABLE + direction bits like north, east, south, west).

**Save validation** runs both client-side (`_validate_level_before_save()`) and server-side (`validateLevelData` + `validatePlayableLevel` in `main.go`): exactly 1 START, 1 END, both WALKABLE, at least 2 walkable room tiles.

### Client-server communication

All server calls go through `OnlineSession.call_rpc(id, payload)`, which wraps `NakamaClient.rpc_async()`, handles session refresh, retries on 401, and returns parsed JSON. RPCs are registered in `main.go:InitModule()`.

| RPC | Purpose |
|-----|---------|
| `submit_level` | Save a level (server validates structure + playability) |
| `get_level` | Fetch a level by owner + key |
| `list_my_levels` | List all levels for the authenticated user |
| `submit_score` | Submit completion time/slides, returns leaderboard rank |
| `submit_level_vote` | Submit a like/dislike vote (one vote per player per level) |

**Storage model:** all of a user's levels are packed into a single Nakama Storage Object (`collection:"levels"`, `key:"levels"`) as a JSON object containing an ordered `levels` array. Each array item is a full level object, and its internal `name` is used as the level key.

**Leaderboards:** one ascending leaderboard per level, ID format `{level_owner_id}_{level_key}`, with `time_ms` as score and `slide_count` as subscore.

## Conventions

- All UI (buttons, modals, menus) is created programmatically in GDScript — no UI nodes in `.tscn` files.
- Manager nodes (`GridManager`, `SlideManager`, `PlayerController`) are wired in code via `_ready()`, not scene references.
- Animations use `create_tween()` with cubic ease-out and `SLIDE_DURATION`.
- Grid visuals use `_draw()` immediate-mode rendering with `queue_redraw()`.
- Layout is viewport-driven: both modules call `_layout_for_viewport()` on resize, recomputing cell size and grid origin dynamically.

## License

Apache License 2.0 — see [LICENSE](LICENSE).
