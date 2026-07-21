class_name LevelPlayer
extends CanvasLayer

signal main_menu_requested
signal edit_level_requested(level_key: String, owner_id: String)
signal level_completed(level_key: String, owner_id: String, level_name: String, time_ms: int, slide_count: int, rank: int)

@onready var grid_manager: GridManager = $GridManager
@onready var grid_visual: Node2D = $GridVisual
@onready var slide_manager: SlideManager = $SlideManager
@onready var object_container: Node2D = $ObjectContainer
var _background: Sprite2D

const PlaceableScene = preload("res://level_player/placeable_object.tscn")
const FULL_BG_TEXTURE: Texture2D = preload("res://assets/sprites/fullbackground.png")
const PLAYER_Z_INDEX := 20

const OptionsPanel = preload("res://scenes/options_panel.tscn")
const WinAnimationScene = preload("res://scenes/win_animation.tscn")
const PortalAnimationScene = preload("res://scenes/portal_animation.tscn")
const CatAnimationScene = preload("res://scenes/cat_animation.tscn")
const PlayerWalkAnimScene = preload("res://scenes/player_walk_anim.tscn")

@export var level_key: String = ""
@export var level_owner_id: String = ""

var world: TileWorld
var _raw_level_data: Dictionary = {}
var _level_name: String = ""
var _level_ctrl := LevelLoadController.new()

@onready var _reset_button: Button = %ResetBtn
@onready var _back_button: Button = %BackBtn
@onready var _edit_button: Button = %EditBtn
@onready var _options_button: Button = %OptionsBtn
@onready var _level_title_label: Label = get_node_or_null("Hud/VBoxContainer/NinePatchRect/VBoxContainer/label_level_title") as Label
@onready var _creator_label: Label = %creator_label
@onready var _description_label: Label = %description_label
@onready var _slides_label: Label = %slides_label
@onready var _time_label: Label = get_node_or_null("Hud/VBoxContainer/NinePatchRect/VBoxContainer/HBoxContainer/time_label") as Label
@onready var _rank_label: Label = get_node_or_null("Hud/VBoxContainer/NinePatchRect/VBoxContainer/HBoxContainer/rank_label") as Label
@onready var _plays_label: Label = get_node_or_null("Hud/VBoxContainer/NinePatchRect/VBoxContainer/HBoxContainer/plays_label") as Label

var _start_pos: Vector2i
var _end_pos: Vector2i
var _current_pos: Vector2i
var _goal_entry_from_pos: Vector2i
var _options_overlay: Node
var _player_node: Node2D
var _player_controller: PlayerController

var _start_time_ms: int = 0
var _slide_count: int = 0
var _goal_win_anim_started := false
var _goal_win_anim_finished := false
var _play_source: String = ""
var _active_win_sprite: AnimatedSprite2D
var _time_running := false


func _ready() -> void:
	_background = get_node_or_null("Fullbackground") as Sprite2D
	if _background == null:
		_background = Sprite2D.new()
		_background.name = "Fullbackground"
		_background.z_index = -100
		add_child(_background)
	if _background.texture == null:
		_background.texture = FULL_BG_TEXTURE
	_background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	world = TileWorld.new()
	grid_manager.world = world

	grid_visual.grid_manager = grid_manager
	grid_visual.queue_redraw()
	slide_manager.grid_manager = grid_manager
	slide_manager.grid_visual = grid_visual
	slide_manager.world = world
	slide_manager.tile_slid.connect(_on_tile_slid)

	_reset_button.pressed.connect(_reset_level)
	_back_button.pressed.connect(func(): main_menu_requested.emit())
	_edit_button.pressed.connect(_on_edit_pressed)
	_options_button.pressed.connect(_show_options_overlay)
	_reset_button.focus_mode = Control.FOCUS_NONE
	_back_button.focus_mode = Control.FOCUS_NONE
	_edit_button.focus_mode = Control.FOCUS_NONE
	_options_button.focus_mode = Control.FOCUS_NONE

	get_viewport().size_changed.connect(_layout_for_viewport)
	call_deferred("_layout_for_viewport")


func _process(_delta: float) -> void:
	if world:
		world.commit()
	if _time_running and _start_time_ms > 0:
		_update_time_label(Time.get_ticks_msec() - _start_time_ms)


func load_level(key: String, owner_id: String, source: String = "") -> void:
	_cleanup()
	level_key = key
	level_owner_id = owner_id
	_play_source = source
	_update_edit_button_visibility()
	if OnlineSession.session:
		_load_level_from_server()
	else:
		OnlineSession.session_ready.connect(_load_level_from_server, CONNECT_ONE_SHOT)


func _cleanup() -> void:
	_goal_win_anim_started = false
	_goal_win_anim_finished = false
	if _active_win_sprite:
		_active_win_sprite.queue_free()
		_active_win_sprite = null
	if _player_controller:
		_player_controller.queue_free()
		_player_controller = null
	if _player_node:
		_player_node.queue_free()
		_player_node = null
	grid_manager.clear_object_registry()
	for child in object_container.get_children():
		child.queue_free()
	world.clear()
	_raw_level_data = {}
	_level_name = ""
	_goal_entry_from_pos = Vector2i.ZERO
	if _level_title_label:
		_level_title_label.text = ""
	if _creator_label:
		_creator_label.text = ""
	if _description_label:
		_description_label.text = ""
	if _time_label:
		_time_label.text = "0.00"
	if _rank_label:
		_rank_label.text = "0"
	if _plays_label:
		_plays_label.text = "0"
	_time_running = false


func _setup_grid(grid_size: int) -> void:
	grid_manager.grid_size = grid_size
	grid_manager._initialize_grid()
	_layout_for_viewport()
	grid_visual.queue_redraw()


func _load_level_from_server() -> void:
	if level_key.is_empty():
		push_warning("No level_key set, skipping load")
		return

	var result := await _level_ctrl.fetch_level(level_key, level_owner_id)
	if result.is_empty():
		push_warning("Failed to fetch level %s/%s" % [level_owner_id, level_key])
		return

	if level_owner_id.is_empty() and OnlineSession.session:
		level_owner_id = str(OnlineSession.session.user_id)
	_update_edit_button_visibility()

	var value: Dictionary = result.get("value", {})
	_raw_level_data = value
	_level_name = _extract_level_name(value)
	_apply_level_metadata(value, result)

	var grid_size: int = value.get("grid_size", LevelConfig.DEFAULT_GRID_SIZE)
	_setup_grid(grid_size)

	world.from_dict(value)
	_build_tiles_from_world()

	_current_pos = _start_pos
	_slide_count = 0
	_slides_label.text = "0"
	_start_time_ms = Time.get_ticks_msec()
	_time_running = true
	_update_time_label(0)
	_spawn_player()


func _extract_level_name(level_data: Dictionary) -> String:
	var raw_name := str(level_data.get("name", "")).strip_edges()
	if not raw_name.is_empty():
		return raw_name
	return level_key


func _apply_level_metadata(level_data: Dictionary, level_response: Dictionary = {}) -> void:
	if _level_title_label:
		_level_title_label.text = str(level_data.get("name", "")).strip_edges()
	if _creator_label:
		_creator_label.text = _resolve_creator_name(level_data, level_response)
	if _rank_label:
		var likes := _variant_to_int(level_data.get("likes", 0))
		var dislikes := _variant_to_int(level_data.get("dislikes", 0))
		_rank_label.text = str(likes - dislikes)
	if _plays_label:
		_plays_label.text = str(_extract_leaderboard_entries_count(level_data))
	if _description_label == null:
		return
	var description := str(level_data.get("description", "")).strip_edges()
	_description_label.text = description if not description.is_empty() else "No description."

func _extract_leaderboard_entries_count(level_data: Dictionary) -> int:
	var leaderboard_variant: Variant = level_data.get("leaderboard", [])
	if leaderboard_variant is Array:
		return (leaderboard_variant as Array).size()

	var entries_variant: Variant = level_data.get("entries", [])
	if entries_variant is Array:
		return (entries_variant as Array).size()

	return max(0, _variant_to_int(level_data.get("play_count", 0)))


func _variant_to_int(value: Variant) -> int:
	if value is int:
		return value
	if value is float:
		return int(value)
	if value is String:
		var text := (value as String).strip_edges()
		if text.is_valid_int():
			return text.to_int()
	return 0


func _resolve_creator_name(level_data: Dictionary, level_response: Dictionary) -> String:
	if _play_source == "campaign":
		return "Heroic Labs"

	var candidate_keys := ["creator_name", "owner_name", "author", "created_by"]
	for key in candidate_keys:
		var creator := str(level_data.get(key, "")).strip_edges()
		if not creator.is_empty():
			return creator

	var username := str(level_response.get("username", "")).strip_edges()
	if not username.is_empty():
		return username

	var owner_id := str(level_response.get("user_id", "")).strip_edges()
	if owner_id.is_empty():
		owner_id = level_owner_id.strip_edges()
	if owner_id.is_empty():
		return "Unknown"

	if OnlineSession.session and owner_id == str(OnlineSession.session.user_id):
		var session_username := str(OnlineSession.session.username).strip_edges()
		if not session_username.is_empty():
			return session_username
	return owner_id.left(8)


func _build_tiles_from_world() -> void:
	_start_pos = world.get_start_pos()
	_end_pos = world.get_end_pos()

	for id in range(world.entity_count()):
		if not world.is_alive(id):
			continue
		var x := world.pos_x[id]
		var y := world.pos_y[id]
		var sprite_name := world.sprites[id]

		var obj := PlaceableScene.instantiate() as PlaceableObject
		obj.entity_id = id
		obj.sprite_path = sprite_name
		object_container.add_child(obj)
		grid_manager.register_object(obj)
		_apply_object_visual(obj, sprite_name, Vector2i(x, y))
		_scale_to_cell(obj)

		if world.has(ComponentRegistry.START, id) or world.has(ComponentRegistry.END, id):
			obj.grid_pos = Vector2i(x, y)
			obj.global_position = grid_manager.grid_to_world(Vector2i(x, y))
		else:
			if not grid_manager.is_valid_cell(x, y):
				obj.queue_free()
				continue
			obj.grid_pos = Vector2i(x, y)
			obj.global_position = grid_manager.grid_to_world(Vector2i(x, y))

	_layout_for_viewport()


func _apply_object_visual(obj: PlaceableObject, sprite_name: String, grid_pos: Vector2i) -> void:
	if world.has(ComponentRegistry.START, obj.entity_id):
		_apply_start_visual(obj, grid_pos)
		return
	if world.has(ComponentRegistry.END, obj.entity_id):
		_apply_goal_visual(obj, grid_pos)
		return
	if not sprite_name.is_empty():
		obj.set_texture(LevelConfig.load_sprite_texture(sprite_name))


func _apply_start_visual(obj: PlaceableObject, edge_pos: Vector2i) -> void:
	var room_sprite := LevelConfig.start_edge_room_sprite_name(edge_pos, grid_manager.grid_size)
	var room_texture := LevelConfig.load_sprite_texture(room_sprite)
	_sync_special_edge_components(obj.entity_id, edge_pos)
	obj.set_texture(room_texture)
	_set_portal_animation_overlay(
		obj,
		room_texture,
		"StartPortalAnimation",
		_goal_far_wall_local_offset(room_texture, edge_pos),
		LevelConfig.START_OVERLAY_SCALE,
		1
	)


func _apply_goal_visual(obj: PlaceableObject, edge_pos: Vector2i) -> void:
	var room_sprite := LevelConfig.start_edge_room_sprite_name(edge_pos, grid_manager.grid_size)
	var room_texture := LevelConfig.load_sprite_texture(room_sprite)
	_sync_special_edge_components(obj.entity_id, edge_pos)
	obj.set_texture(room_texture)
	_set_cat_animation_overlay(obj, room_texture)
	_set_goal_far_wall_portal(obj, room_texture, edge_pos)


func _set_goal_far_wall_portal(obj: PlaceableObject, room_texture: Texture2D, edge_pos: Vector2i) -> void:
	const PORTAL_NODE_NAME := "GoalFarWallPortalAnimation"
	var existing := obj.get_node_or_null(PORTAL_NODE_NAME)
	if existing:
		existing.queue_free()

	if room_texture == null:
		return

	_set_portal_animation_overlay(
		obj,
		room_texture,
		PORTAL_NODE_NAME,
		_goal_far_wall_local_offset(room_texture, edge_pos),
		LevelConfig.START_OVERLAY_SCALE,
		2
	)


func _set_portal_animation_overlay(
	obj: PlaceableObject,
	room_texture: Texture2D,
	node_name: String,
	local_pos: Vector2,
	scale_ratio: float,
	z_index: int
) -> void:
	if obj == null or room_texture == null:
		return
	var existing := obj.get_node_or_null(node_name)
	if existing:
		existing.queue_free()

	var portal_anim := PortalAnimationScene.instantiate() as AnimatedSprite2D
	if portal_anim == null:
		return
	portal_anim.name = node_name
	portal_anim.position = local_pos
	portal_anim.z_index = z_index
	portal_anim.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portal_anim.scale = _animated_overlay_scale_for_base_texture(room_texture, portal_anim, scale_ratio)
	obj.add_child(portal_anim)
	portal_anim.play("idle")


func _set_cat_animation_overlay(obj: PlaceableObject, room_texture: Texture2D) -> void:
	const CAT_NODE_NAME := "GoalCatAnimation"
	if obj == null or room_texture == null:
		return
	var existing := obj.get_node_or_null(CAT_NODE_NAME)
	if existing:
		existing.queue_free()

	var cat_anim := CatAnimationScene.instantiate() as AnimatedSprite2D
	if cat_anim == null:
		return
	cat_anim.name = CAT_NODE_NAME
	cat_anim.position = Vector2.ZERO
	cat_anim.z_index = 1
	cat_anim.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	cat_anim.scale = _animated_overlay_scale_for_base_texture(room_texture, cat_anim, LevelConfig.GOAL_OVERLAY_SCALE)
	obj.add_child(cat_anim)
	cat_anim.play("idle")


func _overlay_scale_for_base_texture(base_texture: Texture2D, overlay_texture: Texture2D, ratio: float) -> Vector2:
	if ratio <= 0.0 or base_texture == null or overlay_texture == null:
		return Vector2.ONE
	var base_width := base_texture.get_size().x
	var overlay_width := overlay_texture.get_size().x
	if base_width <= 0.0 or overlay_width <= 0.0:
		return Vector2.ONE
	var target_width := base_width * ratio
	return Vector2.ONE * (target_width / overlay_width)


func _animated_overlay_scale_for_base_texture(base_texture: Texture2D, anim_sprite: AnimatedSprite2D, ratio: float) -> Vector2:
	if ratio <= 0.0 or base_texture == null or anim_sprite == null or anim_sprite.sprite_frames == null:
		return Vector2.ONE
	if not anim_sprite.sprite_frames.has_animation("idle"):
		return Vector2.ONE
	var frame_texture := anim_sprite.sprite_frames.get_frame_texture("idle", 0)
	if frame_texture == null:
		return Vector2.ONE
	return _overlay_scale_for_base_texture(base_texture, frame_texture, ratio)


func _goal_far_wall_local_offset(room_texture: Texture2D, edge_pos: Vector2i) -> Vector2:
	if room_texture == null:
		return Vector2.ZERO

	var room_size := room_texture.get_size()
	if room_size.x <= 0.0 or room_size.y <= 0.0:
		return Vector2.ZERO

	var wall_offset_x := room_size.x * 0.28
	var wall_offset_y := room_size.y * 0.28
	var inward := LevelConfig.edge_inward_component(edge_pos, grid_manager.grid_size)
	match inward:
		ComponentRegistry.EAST:
			return Vector2(-wall_offset_x, 0.0)
		ComponentRegistry.WEST:
			return Vector2(wall_offset_x, 0.0)
		ComponentRegistry.SOUTH:
			return Vector2(0.0, -wall_offset_y)
		ComponentRegistry.NORTH:
			return Vector2(0.0, wall_offset_y)
		_:
			return Vector2.ZERO


func _sync_special_edge_components(entity_id: int, edge_pos: Vector2i) -> void:
	if world == null:
		return
	world.remove(ComponentRegistry.NORTH, entity_id)
	world.remove(ComponentRegistry.EAST, entity_id)
	world.remove(ComponentRegistry.SOUTH, entity_id)
	world.remove(ComponentRegistry.WEST, entity_id)

	var inward_component := LevelConfig.edge_inward_component(edge_pos, grid_manager.grid_size)
	if not inward_component.is_empty():
		world.add(inward_component, entity_id)


func _spawn_player() -> void:
	_player_node = PlayerWalkAnimScene.instantiate() as AnimatedSprite2D
	if _player_node == null:
		return
	_player_node.z_index = PLAYER_Z_INDEX
	var player_anim := _player_node as AnimatedSprite2D
	if player_anim:
		player_anim.play("down")
	_scale_player_to_cell()
	_player_node.global_position = grid_manager.grid_to_world(_current_pos)
	add_child(_player_node)

	_player_controller = PlayerController.new()
	_player_controller.grid_manager = grid_manager
	_player_controller.world = world
	_player_controller.player_node = _player_node
	_player_controller.start_pos = _start_pos
	_player_controller.end_pos = _end_pos
	_player_controller.current_pos = _current_pos
	_player_controller.reached_end.connect(_on_reached_end)
	_player_controller.goal_move_started.connect(_on_goal_move_started)
	_player_controller.moved.connect(_on_player_moved)
	add_child(_player_controller)
	AudioManager.play("player_spawn")

	slide_manager.locked_cell = _current_pos
	_layout_for_viewport()


func _on_player_moved(pos: Vector2i) -> void:
	var from_pos := _current_pos
	var direction := pos - _current_pos
	slide_manager.clear_selection()
	if pos == _end_pos:
		_goal_entry_from_pos = from_pos
	_current_pos = pos
	slide_manager.locked_cell = pos
	if direction != Vector2i.ZERO:
		_set_player_facing(direction)


func _on_tile_slid() -> void:
	_slide_count += 1
	_slides_label.text = str(_slide_count)


func _on_goal_move_started() -> void:
	_start_goal_win_animation_if_needed()
	_hide_player_mid_goal_tween()


func _on_reached_end() -> void:
	var elapsed_ms := Time.get_ticks_msec() - _start_time_ms
	_time_running = false
	_update_time_label(elapsed_ms)
	AudioManager.play("player_win")
	AudioManager.play("catmeow")
	_hide_goal_reached_visuals()

	# Freeze input
	_player_controller.set_process_unhandled_input(false)
	slide_manager.set_process(false)
	slide_manager.set_process_unhandled_input(false)
	await _wait_for_goal_win_animation()

	# Submit score
	var rank := await _level_ctrl.submit_score(level_owner_id, level_key, elapsed_ms, _slide_count)

	level_completed.emit(level_key, level_owner_id, _level_name, elapsed_ms, _slide_count, rank)


func _start_goal_win_animation_if_needed() -> void:
	if _goal_win_anim_started:
		return
	_goal_win_anim_started = true
	_goal_win_anim_finished = false
	_hide_goal_cat_visual()
	_play_goal_win_animation()


func _hide_player_mid_goal_tween() -> void:
	var hide_delay := LevelConfig.GOAL_MOVE_TWEEN_DELAY + (LevelConfig.SLIDE_DURATION * 0.5)
	var timer := get_tree().create_timer(hide_delay)
	timer.timeout.connect(_on_hide_player_goal_delay_timeout, CONNECT_ONE_SHOT)


func _on_hide_player_goal_delay_timeout() -> void:
	if not is_instance_valid(self):
		return
	if _player_node == null or _player_controller == null:
		return
	# Only hide if this is still the goal-move context.
	if _player_controller.current_pos == _end_pos:
		_player_node.visible = false


func _wait_for_goal_win_animation() -> void:
	_start_goal_win_animation_if_needed()
	while not _goal_win_anim_finished:
		await get_tree().process_frame


func _play_goal_win_animation() -> void:
	const WIN_ANIM_ENTRANCE_OFFSET_PX := 0.0
	var win_sprite := WinAnimationScene.instantiate() as AnimatedSprite2D
	if win_sprite == null:
		_goal_win_anim_finished = true
		return
	_active_win_sprite = win_sprite

	# Ensure only this instance is one-shot; the scene resource loops by default.
	var frames := win_sprite.sprite_frames
	if frames != null:
		frames = frames.duplicate()
		win_sprite.sprite_frames = frames

	var animation_name := _goal_win_animation_name(_end_pos)
	if frames != null and frames.has_animation(animation_name):
		frames.set_animation_loop(animation_name, false)
		win_sprite.animation = animation_name
	else:
		win_sprite.animation = "win_down"
		if frames != null and frames.has_animation("win_down"):
			frames.set_animation_loop("win_down", false)

	_scale_win_animation_to_cell(win_sprite)
	var from_world := grid_manager.grid_to_world(_goal_entry_from_pos)
	var goal_world := grid_manager.grid_to_world(_end_pos)
	win_sprite.global_position = ((from_world + goal_world) * 0.5) + _goal_entrance_offset(_end_pos, WIN_ANIM_ENTRANCE_OFFSET_PX)
	win_sprite.z_index = PLAYER_Z_INDEX + 1
	add_child(win_sprite)
	win_sprite.animation_finished.connect(_on_goal_win_animation_finished.bind(win_sprite), CONNECT_ONE_SHOT)
	win_sprite.play()


func _on_goal_win_animation_finished(win_sprite: AnimatedSprite2D) -> void:
	if not is_instance_valid(win_sprite):
		_goal_win_anim_finished = true
		return
	var finished_anim := win_sprite.animation
	win_sprite.stop()
	if win_sprite.sprite_frames != null and win_sprite.sprite_frames.has_animation(finished_anim):
		var frame_count := win_sprite.sprite_frames.get_frame_count(finished_anim)
		if frame_count > 0:
			win_sprite.frame = frame_count - 1
	_goal_win_anim_finished = true


func _scale_win_animation_to_cell(win_sprite: AnimatedSprite2D) -> void:
	if win_sprite == null or win_sprite.sprite_frames == null:
		return
	if not win_sprite.sprite_frames.has_animation(win_sprite.animation):
		return
	var frame_tex := win_sprite.sprite_frames.get_frame_texture(win_sprite.animation, 0)
	if frame_tex == null:
		return
	var tex_size := frame_tex.get_size()
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return
	var target_span := grid_manager.cell_size * 2.0
	var major_size := tex_size.x if win_sprite.animation == "win_left" or win_sprite.animation == "win_right" else tex_size.y
	if major_size <= 0.0:
		return
	var s := target_span / major_size
	win_sprite.scale = Vector2.ONE * s


func _goal_win_animation_name(edge_pos: Vector2i) -> String:
	if edge_pos.x == -1:
		return "win_right"
	if edge_pos.x == grid_manager.grid_size:
		return "win_left"
	if edge_pos.y == -1:
		return "win_down"
	if edge_pos.y == grid_manager.grid_size:
		return "win_up"
	return "win_down"


func _goal_entrance_offset(edge_pos: Vector2i, amount_px: float) -> Vector2:
	var inward := LevelConfig.edge_inward_component(edge_pos, grid_manager.grid_size)
	match inward:
		ComponentRegistry.EAST:
			return Vector2(amount_px, 0.0)
		ComponentRegistry.WEST:
			return Vector2(-amount_px, 0.0)
		ComponentRegistry.SOUTH:
			return Vector2(0.0, amount_px)
		ComponentRegistry.NORTH:
			return Vector2(0.0, -amount_px)
		_:
			return Vector2.ZERO


func _hide_goal_reached_visuals() -> void:
	if _player_node:
		_player_node.visible = false

	_hide_goal_cat_visual()


func _hide_goal_cat_visual() -> void:
	var goal_obj := _find_goal_object()
	if goal_obj == null:
		return

	var cat_overlay := goal_obj.get_node_or_null("GoalCatAnimation") as CanvasItem
	if cat_overlay:
		cat_overlay.visible = false

	# Backward compatibility in case old static overlay exists.
	cat_overlay = goal_obj.get_node_or_null("OverlaySprite2D") as CanvasItem
	if cat_overlay:
		cat_overlay.visible = false


func _find_goal_object() -> PlaceableObject:
	if world == null:
		return null
	for id in range(world.entity_count()):
		if not world.is_alive(id):
			continue
		if not world.has(ComponentRegistry.END, id):
			continue
		for child in object_container.get_children():
			var obj := child as PlaceableObject
			if obj != null and obj.entity_id == id:
				return obj
		break
	return null


func _reset_level() -> void:
	var saved_data := _raw_level_data.duplicate(true)
	_cleanup()
	_raw_level_data = saved_data

	# Rebuild from stored data
	world.from_dict(_raw_level_data)

	var grid_size: int = _raw_level_data.get("grid_size", LevelConfig.DEFAULT_GRID_SIZE)
	_setup_grid(grid_size)

	_build_tiles_from_world()

	_current_pos = _start_pos
	_slide_count = 0
	_slides_label.text = "0"
	_start_time_ms = Time.get_ticks_msec()
	_time_running = true
	_update_time_label(0)

	slide_manager.set_process(true)
	slide_manager.set_process_unhandled_input(true)

	_spawn_player()


func _update_time_label(elapsed_ms: int) -> void:
	if _time_label == null:
		return
	_time_label.text = "%.2f" % (maxi(0, elapsed_ms) / 1000.0)


func _scale_to_cell(obj: PlaceableObject) -> void:
	var sprite := obj.get_node("Sprite2D") as Sprite2D
	if not sprite or not sprite.texture:
		return
	var tex_w := sprite.texture.get_size().x
	if tex_w <= 0.0:
		return
	var s := grid_manager.cell_size / tex_w
	obj.scale = Vector2(s, s)


func _layout_for_viewport() -> void:
	var vp := get_viewport().get_visible_rect().size
	_layout_background(vp)
	var outer_cells := float(grid_manager.grid_size + 2)
	var padding := 24.0
	var side_gap := 24.0
	var side_width := 110.0

	var avail_w := maxf(outer_cells, vp.x - 2.0 * padding - side_gap - side_width)
	var avail_h := maxf(outer_cells, vp.y - 2.0 * padding)
	var cell := floorf(minf(avail_w / outer_cells, avail_h / outer_cells))
	cell = maxf(32.0, cell)
	grid_manager.cell_size = cell

	var board_span := outer_cells * cell
	var board_left := padding + (avail_w - board_span) * 0.5
	var board_top := padding + (avail_h - board_span) * 0.5
	grid_manager.grid_origin = Vector2(board_left + cell, board_top + cell)

	for child in object_container.get_children():
		var obj := child as PlaceableObject
		if obj == null:
			continue
		_scale_to_cell(obj)
		obj.global_position = grid_manager.grid_to_world(obj.grid_pos)

	if _player_node:
		_scale_player_to_cell()
		_player_node.global_position = grid_manager.grid_to_world(_current_pos)

	grid_visual.queue_redraw()


func _layout_background(vp_size: Vector2) -> void:
	if not _background or not _background.texture:
		return
	var tex_size := _background.texture.get_size()
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return
	var scale_factor := maxf(vp_size.x / tex_size.x, vp_size.y / tex_size.y)
	_background.scale = Vector2.ONE * scale_factor
	_background.position = vp_size * 0.5


func _set_player_facing(direction: Vector2i) -> void:
	var sprite := _player_node as AnimatedSprite2D
	if not sprite:
		return
	if direction == Vector2i(0, -1):
		sprite.play("up")
	elif direction == Vector2i(1, 0):
		sprite.play("right")
	elif direction == Vector2i(0, 1):
		sprite.play("down")
	elif direction == Vector2i(-1, 0):
		sprite.play("left")
	_scale_player_to_cell()


func _scale_player_to_cell() -> void:
	var sprite := _player_node as AnimatedSprite2D
	if not sprite or sprite.sprite_frames == null:
		return
	if not sprite.sprite_frames.has_animation(sprite.animation):
		return
	var tex := sprite.sprite_frames.get_frame_texture(sprite.animation, 0)
	if tex == null:
		return
	var tex_size := tex.get_size()
	var base := maxf(tex_size.x, tex_size.y)
	if base <= 0.0:
		return
	var target := grid_manager.cell_size * 0.33
	var s := target / base
	_player_node.scale = Vector2.ONE * s


func _update_edit_button_visibility() -> void:
	if _reset_button:
		_reset_button.visible = true
	if _edit_button:
		_edit_button.disabled = (_play_source == "campaign" or _play_source == "community")
	if _options_button:
		_options_button.visible = true


func _show_options_overlay() -> void:
	if is_instance_valid(_options_overlay):
		return
	_options_overlay = OptionsPanel.instantiate()
	_options_overlay.tree_exited.connect(func(): _options_overlay = null)
	add_child(_options_overlay)


func _on_edit_pressed() -> void:
	if level_key.is_empty() or level_owner_id.is_empty():
		return
	edit_level_requested.emit(level_key, level_owner_id)
