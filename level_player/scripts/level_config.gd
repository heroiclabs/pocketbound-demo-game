class_name LevelConfig

const DEFAULT_GRID_SIZE: int = 4
const PUZZLE_SIZE: float = 512.0
const GRID_ORIGIN: Vector2 = Vector2(100, 100)
const SLIDE_DURATION: float = 0.15
const GOAL_MOVE_TWEEN_DELAY: float = 0.0
const EDGE_MARGIN: float = 1.2        # edge slots + padding (per side) in cell units

# Layout constants — all UI positions derive from these
const UI_PANEL_GAP: float = 64.0      # gap between grid right edge and side panel
const UI_PANEL_WIDTH: float = 540.0   # width of palette / side UI
const UI_PANEL_TOP: float = 20.0      # top margin for side panel
const BOTTOM_MARGIN: float = 108.0    # space below the grid
const RIGHT_MARGIN: float = 64.0      # space right of the panel
const GOAL_CAT_BASE_ROTATION_DEGREES: float = 0.0
const START_OVERLAY_SCALE: float = 0.33
const GOAL_OVERLAY_SCALE: float = 0.33

const SPRITE_DIR := "res://assets/sprites/"
const SPRITESHEET_DIR := "res://assets/sprites/Spritesheets/"

const ROOM_SPRITE_TO_ATLAS := {
	"block": "FullTilemap_packed_atlas/block.tres",
	"background": "FullTilemap_packed_atlas/background.tres",
	"portal": "FullTilemap_packed_atlas/portal.tres",
	"cat1": "FullTilemap_packed_atlas/cat1.tres",
	"goal": "FullTilemap_packed_atlas/cat1.tres",
	"N": "1door/N.tres",
	"E": "1door/E.tres",
	"S": "1door/S.tres",
	"W": "1door/W.tres",
	"NE": "2doors/NE.tres",
	"NW": "2doors/NW.tres",
	"NS": "2doors/NS.tres",
	"EW": "2doors/EW.tres",
	"ES": "2doors/ES.tres",
	"SW": "2doors/SW.tres",
	"NES": "3doors/NES.tres",
	"NEW": "3doors/NEW.tres",
	"NSW": "3doors/NSW.tres",
	"ESW": "3doors/ESW.tres",
	"NESW": "FullTilemap_packed_atlas/NESW.tres",
	"11": "FullTilemap_packed_atlas/NESW.tres",
}


static func _canonical_sprite_key(sprite_name: String) -> String:
	var key := sprite_name.get_file()
	if key.ends_with(".png"):
		key = key.substr(0, key.length() - 4)
	elif key.ends_with(".tres"):
		key = key.substr(0, key.length() - 5)

	if key.begins_with("room_"):
		key = key.substr(5)

	var lowered := key.to_lower()
	match lowered:
		"north":
			return "N"
		"east":
			return "E"
		"south":
			return "S"
		"west":
			return "W"
		"block", "background", "portal", "cat1", "goal":
			return lowered
		_:
			pass

	var upper := key.to_upper()
	if upper == "SE":
		return "ES"
	if upper == "WS":
		return "SW"
	return upper


static func sprite_resource_path(sprite_name: String) -> String:
	if sprite_name.begins_with("res://"):
		return sprite_name

	var key := _canonical_sprite_key(sprite_name)
	if ROOM_SPRITE_TO_ATLAS.has(key):
		return SPRITESHEET_DIR + str(ROOM_SPRITE_TO_ATLAS[key])

	if sprite_name.ends_with(".tres"):
		var candidate := SPRITESHEET_DIR + sprite_name
		if ResourceLoader.exists(candidate):
			return candidate

	return SPRITE_DIR + sprite_name


static func start_edge_room_sprite_name(edge_pos: Vector2i, grid_size: int) -> String:
	if edge_pos.x == -1 and edge_pos.y >= 0 and edge_pos.y < grid_size:
		return "E"
	if edge_pos.x == grid_size and edge_pos.y >= 0 and edge_pos.y < grid_size:
		return "W"
	if edge_pos.y == -1 and edge_pos.x >= 0 and edge_pos.x < grid_size:
		return "S"
	if edge_pos.y == grid_size and edge_pos.x >= 0 and edge_pos.x < grid_size:
		return "N"
	return "NESW"


static func edge_inward_component(edge_pos: Vector2i, grid_size: int) -> String:
	if edge_pos.x == -1 and edge_pos.y >= 0 and edge_pos.y < grid_size:
		return ComponentRegistry.EAST
	if edge_pos.x == grid_size and edge_pos.y >= 0 and edge_pos.y < grid_size:
		return ComponentRegistry.WEST
	if edge_pos.y == -1 and edge_pos.x >= 0 and edge_pos.x < grid_size:
		return ComponentRegistry.SOUTH
	if edge_pos.y == grid_size and edge_pos.x >= 0 and edge_pos.x < grid_size:
		return ComponentRegistry.NORTH
	return ""


static func edge_inward_rotation_degrees(edge_pos: Vector2i, grid_size: int) -> float:
	if edge_pos.x == -1 and edge_pos.y >= 0 and edge_pos.y < grid_size:
		return 0.0
	if edge_pos.x == grid_size and edge_pos.y >= 0 and edge_pos.y < grid_size:
		return 180.0
	if edge_pos.y == -1 and edge_pos.x >= 0 and edge_pos.x < grid_size:
		return 90.0
	if edge_pos.y == grid_size and edge_pos.x >= 0 and edge_pos.x < grid_size:
		return -90.0
	return 0.0


static func goal_cat_rotation_degrees(edge_pos: Vector2i, grid_size: int) -> float:
	return GOAL_CAT_BASE_ROTATION_DEGREES + edge_inward_rotation_degrees(edge_pos, grid_size)


static func load_sprite_texture(sprite_name: String) -> Texture2D:
	var path := sprite_resource_path(sprite_name)
	return load(path) as Texture2D
