class_name SlideManager
extends Node

signal tile_slid

var grid_manager: GridManager
var grid_visual: Node2D
var world: TileWorld
var locked_cell: Vector2i = Vector2i(-99, -99)

var _held_tile: PlaceableObject = null
var _held_origin: Vector2i = Vector2i(-1, -1)
var _hold_mouse_origin: Vector2 = Vector2.ZERO
var _preview_targets: Array[Vector2i] = []

func clear_selection() -> void:
	_clear_hold()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _held_tile:
		_update_preview(event.position)
		return

	if not event is InputEventMouseButton:
		return
	if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return

	if _held_tile:
		_try_commit(event.position)
	else:
		_try_pick_up(event.position)


func _try_pick_up(mouse_pos: Vector2) -> void:
	if not grid_manager.is_in_grid_area(mouse_pos):
		return

	var grid_pos := grid_manager.world_to_grid(mouse_pos)
	if grid_pos == locked_cell:
		return
	var tile := grid_manager.get_object_at(grid_pos.x, grid_pos.y) as PlaceableObject
	if tile == null:
		return
	if world.has(ComponentRegistry.BLOCKED, tile.entity_id):
		return

	var empties := grid_manager.get_adjacent_empty_cells(grid_pos.x, grid_pos.y)
	if empties.is_empty():
		return

	_held_tile = tile
	_held_origin = grid_pos
	_hold_mouse_origin = mouse_pos
	_preview_targets.clear()
	AudioManager.play("room_grab")

	tile.z_index = 10
	tile.modulate.a = 0.7

	grid_visual.clear_highlights()
	grid_visual.clear_move_arrow()


func _try_commit(mouse_pos: Vector2) -> void:
	if _is_origin_click(mouse_pos):
		_clear_hold()
		return

	var path := _build_path_to_mouse(mouse_pos)
	_preview_targets = path.duplicate()
	grid_visual.set_highlights(_preview_targets)
	_update_move_arrow(path)

	if path.is_empty():
		AudioManager.play("room_failed")
		return

	var tile := _held_tile
	var origin := _held_origin
	var moved_steps := path.size()
	var drop_pos := path[path.size() - 1]
	_clear_hold()

	if not grid_manager.move_object(origin, drop_pos):
		AudioManager.play("room_failed")
		return

	tile.slide_to(grid_manager.grid_to_world(drop_pos), drop_pos)
	AudioManager.play("room_place_move")
	for _step in range(moved_steps):
		tile_slid.emit()


func _update_preview(mouse_pos: Vector2) -> void:
	_preview_targets = _build_path_to_mouse(mouse_pos)
	grid_visual.set_highlights(_preview_targets)
	_update_move_arrow(_preview_targets)


func _update_move_arrow(path: Array[Vector2i]) -> void:
	if path.is_empty():
		grid_visual.clear_move_arrow()
		return
	grid_visual.set_move_arrow(_held_origin, path[path.size() - 1])


func _build_path_to_mouse(mouse_pos: Vector2) -> Array[Vector2i]:
	var direction := _axis_direction_to_mouse(mouse_pos)
	if direction == Vector2i.ZERO:
		return []

	var requested_steps := _requested_steps_in_direction(mouse_pos, direction)
	if requested_steps <= 0:
		return []

	var path: Array[Vector2i] = []
	var cursor := _held_origin
	for _step in range(requested_steps):
		cursor += direction
		if not grid_manager.is_valid_cell(cursor.x, cursor.y):
			break
		if cursor == locked_cell:
			break
		if not grid_manager.is_cell_empty(cursor.x, cursor.y):
			break
		path.append(cursor)
	return path


func _axis_direction_to_mouse(mouse_pos: Vector2) -> Vector2i:
	var delta := mouse_pos - _hold_mouse_origin
	var abs_x := absf(delta.x)
	var abs_y := absf(delta.y)
	if abs_x < 1.0 and abs_y < 1.0:
		return Vector2i.ZERO

	if abs_x >= abs_y:
		var x_sign := signf(delta.x)
		if is_zero_approx(x_sign):
			return Vector2i.ZERO
		return Vector2i(int(x_sign), 0)

	var y_sign := signf(delta.y)
	if is_zero_approx(y_sign):
		return Vector2i.ZERO
	return Vector2i(0, int(y_sign))


func _requested_steps_in_direction(mouse_pos: Vector2, direction: Vector2i) -> int:
	var mouse_grid := grid_manager.world_to_grid(mouse_pos)
	if direction.x != 0:
		return maxi(0, (mouse_grid.x - _held_origin.x) * direction.x)
	return maxi(0, (mouse_grid.y - _held_origin.y) * direction.y)


func _is_origin_click(mouse_pos: Vector2) -> bool:
	if not grid_manager.is_in_grid_area(mouse_pos):
		return false
	return grid_manager.world_to_grid(mouse_pos) == _held_origin


func _clear_hold() -> void:
	if _held_tile:
		_held_tile.z_index = 0
		_held_tile.modulate.a = 1.0
	_held_tile = null
	_held_origin = Vector2i(-1, -1)
	_hold_mouse_origin = Vector2.ZERO
	_preview_targets.clear()
	grid_visual.clear_highlights()
	grid_visual.clear_move_arrow()
