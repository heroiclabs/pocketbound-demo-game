class_name LevelCreator
extends CanvasLayer

signal main_menu_requested
signal play_requested(level_key: String, owner_id: String)

@onready var grid_manager: GridManager = $GridManager
@onready var grid_visual: Node2D = $CreatorGridVisual
@onready var drag_manager: Node = $CreatorDragManager
@onready var object_container: Node2D = $ObjectContainer
@onready var tile_palette: PanelContainer = $TilePalette

const PlaceableScene = preload("res://level_player/placeable_object.tscn")
const FULL_BG_TEXTURE: Texture2D = preload("res://assets/sprites/fullbackground.png")
const GUI_BUTTON_NORMAL_TEXTURE: Texture2D = preload("res://assets/sprites/Spritesheets/FullTilemap_packed_atlas/gui_button_strip.tres")
const GUI_BUTTON_ACTIVE_TEXTURE: Texture2D = preload("res://assets/sprites/Spritesheets/FullTilemap_packed_atlas/gui_button_strip_right.tres")
const TOP_UI_RESERVE := 110.0
const BOTTOM_UI_RESERVE := 88.0
const CREATOR_DESIGN_SIZE := Vector2(
	LevelConfig.GRID_ORIGIN.x + LevelConfig.PUZZLE_SIZE + LevelConfig.UI_PANEL_GAP + LevelConfig.UI_PANEL_WIDTH + LevelConfig.RIGHT_MARGIN,
	LevelConfig.GRID_ORIGIN.y + LevelConfig.PUZZLE_SIZE + LevelConfig.BOTTOM_MARGIN
)

@export var level_key: String = ""


var world: TileWorld
var _panel_x: float
var _back_button: Button
var _title_label: Label
var _level_owner_id: String = ""
var _background: Sprite2D
var _test_button_dirty := true


func _ready() -> void:
	_background = Sprite2D.new()
	_background.texture = FULL_BG_TEXTURE
	_background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_background.z_index = -100
	add_child(_background)
	move_child(_background, 0)

	world = TileWorld.new()
	grid_manager.world = world

	_setup_grid()

	grid_visual.grid_manager = grid_manager
	grid_visual.queue_redraw()

	drag_manager.grid_manager = grid_manager
	drag_manager.grid_visual = grid_visual
	drag_manager.object_container = object_container
	drag_manager.edge_objects = {}
	drag_manager.world = world

	tile_palette.world = world
	tile_palette.tile_picked.connect(_on_tile_picked)
	tile_palette.grid_size_changed.connect(_on_grid_size_changed)
	tile_palette.save_requested.connect(_on_save_pressed)
	tile_palette.publish_requested.connect(_on_publish_pressed)
	tile_palette.play_requested.connect(_on_play_pressed)
	drag_manager.tile_placed.connect(_on_tile_placed)
	drag_manager.tile_removed.connect(_on_tile_removed)

	_title_label = Label.new()
	_title_label.text = "Level Creator"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_title_label.theme_type_variation = &"LightTitleLabel"
	_title_label.add_theme_font_size_override("font_size", 54)
	add_child(_title_label)

	_back_button = Button.new()
	_back_button.text = "Back"
	_style_pixel_button(_back_button)
	_back_button.add_theme_font_size_override("font_size", 22)
	_back_button.custom_minimum_size = Vector2(132.0, 48.0)
	_back_button.pressed.connect(func(): main_menu_requested.emit())
	add_child(_back_button)

	get_viewport().size_changed.connect(_layout_for_viewport)
	call_deferred("_layout_for_viewport")


func _process(_delta: float) -> void:
	if world:
		world.commit()
		if _test_button_dirty:
			_sync_test_button_enabled()
			_test_button_dirty = false


func _setup_grid() -> void:
	grid_manager.grid_size = int(tile_palette.grid_size)
	grid_manager._initialize_grid()


func start_new_level() -> void:
	level_key = ""
	_level_owner_id = ""
	for child in object_container.get_children():
		child.queue_free()
	grid_manager.clear_object_registry()
	drag_manager.clear()
	tile_palette.reset()
	tile_palette.level_name = ""
	tile_palette.level_description = ""
	tile_palette.grid_size = LevelConfig.DEFAULT_GRID_SIZE
	world.clear()
	_setup_grid()
	_layout_for_viewport()
	grid_visual.queue_redraw()
	_test_button_dirty = true


func edit_level(key: String, owner_id: String) -> void:
	start_new_level()
	level_key = key
	_level_owner_id = owner_id
	_load_level_from_server()


func _load_level_from_server() -> void:
	if level_key.is_empty():
		return

	var user_id: String = _level_owner_id if not _level_owner_id.is_empty() else OnlineSession.session.user_id
	var payload := JSON.stringify({"user_id": user_id, "key": level_key})
	var result = await OnlineSession.call_rpc("get_level", payload)
	if result == null:
		return

	var value: Dictionary = result.get("value", {})
	var grid_size: int = value.get("grid_size", int(tile_palette.grid_size))

	# Apply grid size and rebuild
	tile_palette.grid_size = grid_size
	_setup_grid()
	_layout_for_viewport()
	grid_visual.queue_redraw()

	# Set level info fields
	var loaded_name := str(value.get("name", "")).strip_edges()
	if loaded_name.is_empty():
		loaded_name = level_key
	tile_palette.level_name = loaded_name
	tile_palette.level_description = value.get("description", "")

	# Load world from server data
	world.from_dict(value)
	_build_tiles_from_world()


func _build_tiles_from_world() -> void:
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

		if world.has(ComponentRegistry.START, id):
			var pos := Vector2i(x, y)
			obj.grid_pos = pos
			obj.global_position = drag_manager._edge_to_world(pos)
			drag_manager.edge_objects[pos] = obj
			tile_palette._start_button.disabled = true
		elif world.has(ComponentRegistry.END, id):
			var pos := Vector2i(x, y)
			obj.grid_pos = pos
			obj.global_position = drag_manager._edge_to_world(pos)
			drag_manager.edge_objects[pos] = obj
			tile_palette._end_button.disabled = true
		else:
			if not grid_manager.is_valid_cell(x, y):
				obj.queue_free()
				continue
			obj.grid_pos = Vector2i(x, y)
			obj.global_position = grid_manager.grid_to_world(Vector2i(x, y))

	_layout_for_viewport()
	_test_button_dirty = true


func _on_tile_picked(obj: PlaceableObject) -> void:
	object_container.add_child(obj)
	_scale_to_cell(obj)
	obj.global_position = obj.get_viewport().get_mouse_position()
	drag_manager.start_drag(obj)


func _on_tile_placed(obj: PlaceableObject, pos: Vector2i) -> void:
	_test_button_dirty = true
	if world.has(ComponentRegistry.START, obj.entity_id):
		_apply_start_visual(obj, pos)
		_scale_to_cell(obj)
	elif world.has(ComponentRegistry.END, obj.entity_id):
		_apply_goal_visual(obj, pos)
		_scale_to_cell(obj)


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
	var portal_texture := LevelConfig.load_sprite_texture("portal")
	_sync_special_edge_components(obj.entity_id, edge_pos)
	obj.set_layered_textures(room_texture, portal_texture, 0.0, LevelConfig.START_OVERLAY_SCALE)


func _apply_goal_visual(obj: PlaceableObject, edge_pos: Vector2i) -> void:
	var room_sprite := LevelConfig.start_edge_room_sprite_name(edge_pos, grid_manager.grid_size)
	var room_texture := LevelConfig.load_sprite_texture(room_sprite)
	var cat_texture := LevelConfig.load_sprite_texture("cat1")
	_sync_special_edge_components(obj.entity_id, edge_pos)
	obj.set_layered_textures(room_texture, cat_texture, 0.0, LevelConfig.GOAL_OVERLAY_SCALE)


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


func _scale_to_cell(obj: PlaceableObject) -> void:
	var sprite := obj.get_node("Sprite2D") as Sprite2D
	if not sprite.texture:
		push_warning("Missing texture for placed object: %s" % obj.sprite_path)
		return
	var tex_size := sprite.texture.get_size()
	var s := grid_manager.cell_size / tex_size.x
	obj.scale = Vector2(s, s)


func _on_tile_removed(obj: PlaceableObject) -> void:
	_test_button_dirty = true
	if world.has(ComponentRegistry.START, obj.entity_id):
		tile_palette.enable_start()
	elif world.has(ComponentRegistry.END, obj.entity_id):
		tile_palette.enable_end()


func _on_grid_size_changed(_value: float) -> void:
	_test_button_dirty = true
	for child in object_container.get_children():
		child.queue_free()
	grid_manager.clear_object_registry()
	drag_manager.clear()
	tile_palette.reset()
	world.clear()

	_setup_grid()
	_layout_for_viewport()
	grid_visual.queue_redraw()


func _on_save_pressed() -> void:
	await _save_level()


func save_current_level() -> String:
	return await _save_level()


func _on_play_pressed() -> void:
	var save_error := await _save_level()
	if not save_error.is_empty():
		return
	if level_key.is_empty():
		return
	var owner_id := _level_owner_id
	if owner_id.is_empty() and OnlineSession.session:
		owner_id = OnlineSession.session.user_id
	if owner_id.is_empty():
		return
	play_requested.emit(level_key, owner_id)


func _on_publish_pressed() -> void:
	var save_error := await _save_level()
	if not save_error.is_empty():
		return
	if level_key.is_empty():
		tile_palette.show_status("Save level before publishing.", true)
		return

	var result: Variant = await OnlineSession.call_rpc("publish_level", JSON.stringify({"key": level_key}))
	if result != null:
		tile_palette.show_status("Level published.", false)
		return

	var rpc_error := OnlineSession.last_rpc_error.to_lower()
	if "published levels are read-only" in rpc_error:
		tile_palette.show_status("Level is already published.", true)
		return
	tile_palette.show_status("Could not publish level.", true)


func _save_level() -> String:
	if not OnlineSession.session:
		push_warning("Not authenticated, cannot save")
		return "Not authenticated."

	var validation_error: String = _validate_level_before_save()
	if not validation_error.is_empty():
		tile_palette.show_status(validation_error, true)
		return validation_error

	var level_name: String = str(tile_palette.level_name).strip_edges()
	if level_name.is_empty():
		level_name = level_key
	if level_name.is_empty():
		level_name = "My Level"
	tile_palette.level_name = level_name
	if await _has_duplicate_level_name_for_user(level_name, level_key):
		var msg := "A level with that name already exists."
		tile_palette.show_status(msg, true)
		return msg

	var data := world.to_dict()
	data["grid_size"] = grid_manager.grid_size
	data["name"] = level_name
	if not level_key.is_empty():
		data["key"] = level_key
	if not tile_palette.level_description.is_empty():
		data["description"] = tile_palette.level_description

	var json_payload := JSON.stringify(data)
	var result = await OnlineSession.call_rpc("submit_level", json_payload)
	if result:
		level_key = level_name
		_level_owner_id = OnlineSession.session.user_id
		tile_palette.show_status("Saved!", false)
		return ""

	var rpc_error := OnlineSession.last_rpc_error.to_lower()
	var msg: String
	if "name contains prohibited content" in rpc_error:
		msg = "Level name contains prohibited content."
	elif "description contains prohibited content" in rpc_error:
		msg = "Level description contains prohibited content."
	elif "level name already exists" in rpc_error:
		msg = "A level with that name already exists."
	else:
		msg = "Failed to save. Check your connection."
	tile_palette.show_status(msg, true)
	return msg


func _has_duplicate_level_name_for_user(level_name: String, current_level_name: String) -> bool:
	var desired := level_name.strip_edges()
	if desired.is_empty():
		return false

	var current := current_level_name.strip_edges()
	var result: Variant = await OnlineSession.call_rpc("list_my_levels", "")
	if not (result is Dictionary):
		return false

	var levels: Array = (result as Dictionary).get("levels", []) as Array
	for entry_variant in levels:
		if not (entry_variant is Dictionary):
			continue
		var entry: Dictionary = entry_variant as Dictionary
		var entry_key := _entry_level_key(entry)
		if entry_key.is_empty():
			continue
		if not current.is_empty() and entry_key == current:
			continue
		if entry_key == desired:
			return true
	return false


func _entry_level_key(entry: Dictionary) -> String:
	var value_variant: Variant = entry.get("value", {})
	if value_variant is Dictionary:
		var level_name := str((value_variant as Dictionary).get("name", "")).strip_edges()
		if not level_name.is_empty():
			return level_name
	return str(entry.get("key", "")).strip_edges()


func _validate_level_before_save() -> String:
	world.commit()
	return _current_save_validation_error()


func _current_save_validation_error() -> String:
	var start_ids: Array[int] = world.get_ids(ComponentRegistry.START)
	if start_ids.size() != 1:
		return "Level must contain exactly one Start tile."
	var start_id := int(start_ids[0])
	if not world.has(ComponentRegistry.WALKABLE, start_id):
		return "Start tile must have walkable component."

	var end_ids: Array[int] = world.get_ids(ComponentRegistry.END)
	if end_ids.size() != 1:
		return "Level must contain exactly one End tile."
	var end_id := int(end_ids[0])
	if not world.has(ComponentRegistry.WALKABLE, end_id):
		return "End tile must have walkable component."

	var walkable_count := 0
	for id in range(world.entity_count()):
		if not world.is_alive(id):
			continue
		if world.has(ComponentRegistry.START, id) or world.has(ComponentRegistry.END, id):
			continue
		if not world.has(ComponentRegistry.WALKABLE, id):
			continue
		if world.has(ComponentRegistry.BLOCKED, id):
			continue

		var x: int = world.pos_x[id]
		var y: int = world.pos_y[id]
		if not grid_manager.is_valid_cell(x, y):
			continue
		walkable_count += 1

	if walkable_count < 2:
		return "Level must contain at least 2 walkable room tiles."

	return ""


func _sync_test_button_enabled() -> void:
	tile_palette.set_test_enabled(_current_save_validation_error().is_empty())


func _layout_for_viewport() -> void:
	var vp := get_viewport().get_visible_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return

	_layout_background(vp)
	var content_scale := minf(vp.x / CREATOR_DESIGN_SIZE.x, vp.y / CREATOR_DESIGN_SIZE.y)
	var content_offset := (vp - CREATOR_DESIGN_SIZE * content_scale) * 0.5
	var design_vp := CREATOR_DESIGN_SIZE
	if _title_label:
		_title_label.scale = Vector2.ONE * content_scale
		_title_label.position = content_offset + Vector2(0.0, 16.0) * content_scale
		_title_label.size = Vector2(design_vp.x, 70.0)

	var outer_cells := float(grid_manager.grid_size + 2)
	var padding := 24.0
	var side_gap := 24.0
	var min_cell := 24.0
	var palette_columns := 4.0
	var palette_separation := 8.0
	var panel_extra_width := 24.0 + palette_separation * (palette_columns - 1.0)

	var usable_top := TOP_UI_RESERVE
	var usable_bottom := design_vp.y - BOTTOM_UI_RESERVE
	var usable_height := maxf(outer_cells * min_cell, usable_bottom - usable_top)
	var max_h_cells := usable_height / outer_cells
	var max_w_cells := (design_vp.x - 2.0 * padding - side_gap - panel_extra_width) / (outer_cells + palette_columns)
	var cell := floorf(minf(max_h_cells, max_w_cells))
	cell = maxf(min_cell, cell)

	var panel_width := floorf(palette_columns * cell + panel_extra_width)
	var board_span := outer_cells * cell
	var total_w := board_span + side_gap + panel_width
	var board_left := floorf((design_vp.x - total_w) * 0.5)
	board_left = maxf(padding, board_left)
	var board_top := floorf(usable_top + (usable_height - board_span) * 0.5)
	board_top = maxf(usable_top, board_top)

	var scaled_cell := cell * content_scale
	grid_manager.cell_size = scaled_cell
	grid_manager.grid_origin = content_offset + Vector2(board_left + cell, board_top + cell) * content_scale

	var panel_top := floorf(board_top)
	var panel_bottom_limit := design_vp.y - BOTTOM_UI_RESERVE - 6.0
	var panel_bottom := floorf(minf(board_top + board_span, panel_bottom_limit))
	panel_bottom = maxf(panel_top + 220.0, panel_bottom)

	var panel_x := board_left + board_span + side_gap
	var panel_height := panel_bottom - panel_top
	var panel_left := content_offset.x + panel_x * content_scale
	var panel_top_pos := content_offset.y + panel_top * content_scale
	_panel_x = panel_left
	tile_palette.scale = Vector2.ONE * content_scale
	tile_palette.size = Vector2(panel_width, panel_height)
	tile_palette.custom_minimum_size = Vector2(panel_width, panel_height)
	tile_palette.offset_left = floorf(panel_left)
	tile_palette.offset_top = floorf(panel_top_pos)
	tile_palette.offset_right = floorf(panel_left + panel_width)
	tile_palette.offset_bottom = floorf(panel_top_pos + panel_height)
	if tile_palette.has_method("apply_layout"):
		tile_palette.call("apply_layout", panel_width, panel_height, cell)

	if _back_button:
		_back_button.scale = Vector2.ONE * content_scale
		_back_button.size = _back_button.custom_minimum_size
		_back_button.position = content_offset + Vector2(24.0, design_vp.y - BOTTOM_UI_RESERVE + 18.0) * content_scale

	for child in object_container.get_children():
		var obj := child as PlaceableObject
		if obj == null:
			continue
		_scale_to_cell(obj)
		if grid_manager.is_valid_cell(obj.grid_pos.x, obj.grid_pos.y):
			obj.global_position = grid_manager.grid_to_world(obj.grid_pos)

	if drag_manager and drag_manager.edge_objects != null:
		for edge_key in drag_manager.edge_objects.keys():
			var edge_pos := edge_key as Vector2i
			var edge_obj := drag_manager.edge_objects[edge_key] as PlaceableObject
			if edge_obj == null:
				continue
			_scale_to_cell(edge_obj)
			edge_obj.global_position = drag_manager._edge_to_world(edge_pos)

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


func _make_button_style(texture: Texture2D) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.texture_margin_left = 10
	style.texture_margin_top = 10
	style.texture_margin_right = 10
	style.texture_margin_bottom = 10
	style.draw_center = true
	return style


func _style_pixel_button(button: Button) -> void:
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	button.add_theme_stylebox_override("normal", _make_button_style(GUI_BUTTON_NORMAL_TEXTURE))
	button.add_theme_stylebox_override("hover", _make_button_style(GUI_BUTTON_ACTIVE_TEXTURE))
	button.add_theme_stylebox_override("pressed", _make_button_style(GUI_BUTTON_ACTIVE_TEXTURE))
	button.add_theme_stylebox_override("focus", _make_button_style(GUI_BUTTON_ACTIVE_TEXTURE))
	button.add_theme_stylebox_override("disabled", _make_button_style(GUI_BUTTON_NORMAL_TEXTURE))
